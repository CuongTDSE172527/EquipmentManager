param(
  [Parameter(Mandatory=$true)][int]$ParentPid,
  [Parameter(Mandatory=$true)][ValidateSet('setup','portable')][string]$Mode,
  [Parameter(Mandatory=$true)][string]$Package,
  [Parameter(Mandatory=$true)][string]$Destination,
  [Parameter(Mandatory=$true)][string]$ExpectedHash,
  [Parameter(Mandatory=$true)][string]$ExpectedVersion,
  [Parameter(Mandatory=$true)][string]$StatusFile,
  [Parameter(Mandatory=$true)][string]$ReadyFile,
  [switch]$NoRelaunch
)
$ErrorActionPreference = 'Stop'
$packagePath = [IO.Path]::GetFullPath($Package)
$destinationPath = [IO.Path]::GetFullPath($Destination).TrimEnd('\')
$stage = [IO.Path]::GetDirectoryName($packagePath)
$expanded = Join-Path $stage 'expanded'
$rollback = Join-Path $stage ('rollback-' + [Guid]::NewGuid().ToString('N'))
$touched = [Collections.Generic.List[object]]::new()
$script:status = 'error'
$parentExited = $false

function Save-Status([string]$state, [string]$message) {
  [ordered]@{state=$state; version=$ExpectedVersion; message=$message; time=[DateTime]::UtcNow.ToString('o')} |
    ConvertTo-Json | Set-Content -LiteralPath $StatusFile -Encoding UTF8
}
function Assert-Child([string]$path, [string]$root) {
  $resolved = [IO.Path]::GetFullPath($path)
  $prefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
  if (!$resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'A file path is outside the update directory.' }
  return $resolved
}
function Check-Version([string]$exe) {
  $version = (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion
  if (!$version -or $version.Split('+')[0] -ne $ExpectedVersion) { throw 'The executable version does not match the release.' }
}

try {
  if ($ParentPid -le 0 -or $ParentPid -eq $PID) { throw 'Invalid application process.' }
  if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+$' -or $ExpectedHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid update metadata.' }
  if ($destinationPath -eq [IO.Path]::GetPathRoot($destinationPath).TrimEnd('\')) { throw 'Put the portable app in its own folder before updating.' }
  if (!(Test-Path -LiteralPath (Join-Path $destinationPath 'EquipmentManager.exe') -PathType Leaf)) { throw 'The application directory is missing.' }
  if (!(Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'The downloaded package is missing.' }
  if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'The downloaded package checksum changed.' }
  $StatusFile = Assert-Child $StatusFile $stage
  $ReadyFile = Assert-Child $ReadyFile $stage
  if ($Mode -eq 'portable') {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
      $total = 0L
      if ($archive.Entries.Count -gt 10000) { throw 'Too many files in the update.' }
      foreach ($entry in $archive.Entries) {
        $null = Assert-Child (Join-Path $expanded $entry.FullName) $expanded
        $total += $entry.Length
        if ($total -gt 1GB) { throw 'The expanded update is too large.' }
      }
    } finally { $archive.Dispose() }
    # A fresh extraction directory avoids stale files and never needs recursive removal.
    $expanded = Join-Path $stage ('expanded-' + [Guid]::NewGuid().ToString('N'))
    [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $expanded)
    Check-Version (Join-Path $expanded 'EquipmentManager.exe')
  }
  Save-Status 'waiting' 'Waiting for EquipmentManager to close.'
  Set-Content -LiteralPath $ReadyFile -Value 'ready' -Encoding ASCII
  $parent = Get-Process -Id $ParentPid -ErrorAction SilentlyContinue
  if ($parent -and !$parent.WaitForExit(120000)) { throw 'EquipmentManager did not close within two minutes.' }
  $parentExited = $true
  Save-Status 'installing' 'Applying the verified update.'
  if ($Mode -eq 'setup') {
    $arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOCANCEL',
      ('/DIR="{0}"' -f $destinationPath), ('/LOG="{0}"' -f (Join-Path $stage 'installer.log')))
    $process = Start-Process -FilePath $packagePath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -notin @(0,3010)) { throw ('Installer failed with code ' + $process.ExitCode) }
  } else {
    foreach ($source in Get-ChildItem -LiteralPath $expanded -File -Recurse) {
      $relative = $source.FullName.Substring($expanded.Length).TrimStart('\')
      $target = Assert-Child (Join-Path $destinationPath $relative) $destinationPath
      $saved = Assert-Child (Join-Path $rollback $relative) $rollback
      $existed = Test-Path -LiteralPath $target -PathType Leaf
      if ($existed) {
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($saved)) -Force | Out-Null
        Copy-Item -LiteralPath $target -Destination $saved
      }
      $touched.Add([PSCustomObject]@{target=$target; saved=$saved; existed=$existed})
      New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
      Copy-Item -LiteralPath $source.FullName -Destination $target -Force
    }
  }
  Check-Version (Join-Path $destinationPath 'EquipmentManager.exe')
  $script:status = 'success'
  Save-Status 'success' 'Update completed. The data backup was preserved.'
} catch {
  $failure = $_.Exception.Message
  $rollbackFailed = $false
  $rollbackFiles = $touched.ToArray()
  [Array]::Reverse($rollbackFiles)
  foreach ($file in $rollbackFiles) {
    try {
      if ($file.existed) { Copy-Item -LiteralPath $file.saved -Destination $file.target -Force }
      elseif (Test-Path -LiteralPath $file.target -PathType Leaf) { Remove-Item -LiteralPath $file.target -Force }
    } catch { $rollbackFailed = $true }
  }
  if ($rollbackFailed) { $failure += ' Some files could not be restored. Close other app instances and reinstall the downloaded package.' }
  try { Save-Status 'error' $failure } catch { }
} finally {
  if (!$NoRelaunch -and $parentExited -and (Test-Path -LiteralPath $ReadyFile) -and (Test-Path -LiteralPath (Join-Path $destinationPath 'EquipmentManager.exe'))) {
    # Reopening the main interactive app is intentional after the chosen update.
    Start-Process -FilePath (Join-Path $destinationPath 'EquipmentManager.exe') -WorkingDirectory $destinationPath -WindowStyle Normal
  }
}
if ($script:status -ne 'success') { exit 1 }
