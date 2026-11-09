param(
  [Parameter(Mandatory=$true)][string]$OldZip,
  [Parameter(Mandatory=$true)][string]$NewZip,
  [Parameter(Mandatory=$true)][string]$Version,
  [Parameter(Mandatory=$true)][string]$FixtureRoot,
  [string]$OldSetup,
  [string]$NewSetup,
  [switch]$TestSetup
)
$ErrorActionPreference = 'Stop'
if ($TestSetup -and $env:GITHUB_ACTIONS -ne 'true') { throw 'Installer registration tests run only on the disposable GitHub runner.' }
$root = [IO.Path]::GetFullPath($FixtureRoot)
New-Item -ItemType Directory -Path $root -Force | Out-Null
$helper = (Resolve-Path -LiteralPath 'assets/updates/windows-update.ps1').Path
$oldArchive = (Resolve-Path -LiteralPath $OldZip).Path
$newArchive = (Resolve-Path -LiteralPath $NewZip).Path
function New-Fixture([string]$name) {
  $path = [IO.Path]::GetFullPath((Join-Path $root ($name + '-' + [Guid]::NewGuid().ToString('N'))))
  if (!$path.StartsWith($root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture path escaped root' }
  New-Item -ItemType Directory -Path $path | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $path 'stage') | Out-Null
  Expand-Archive -LiteralPath $oldArchive -DestinationPath (Join-Path $path 'app')
  Set-Content -LiteralPath (Join-Path $path 'app/user-marker.txt') -Value 'preserve user files' -Encoding ASCII
  return $path
}
function Invoke-Update([string]$fixture, [string]$package, [string]$mode, [string]$hash) {
  $parent = Start-Process powershell.exe -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 2') -WindowStyle Hidden -PassThru
  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $helper -ParentPid $parent.Id -Mode $mode `
    -Package $package -Destination (Join-Path $fixture 'app') -ExpectedHash $hash -ExpectedVersion $Version `
    -StatusFile (Join-Path $fixture 'stage/status.json') -ReadyFile (Join-Path $fixture 'stage/ready.txt') -NoRelaunch
  return $LASTEXITCODE
}
function Snapshot-Files([string]$path) {
  $snapshot = @{}
  foreach ($file in Get-ChildItem -LiteralPath $path -File -Recurse) {
    $snapshot[$file.FullName.Substring($path.Length)] = (Get-FileHash -LiteralPath $file.FullName).Hash
  }
  return $snapshot
}
$ok = New-Fixture 'portable'
$package = Join-Path $ok 'stage/update.zip'
Copy-Item -LiteralPath $newArchive -Destination $package
if ((Invoke-Update $ok $package 'portable' (Get-FileHash -LiteralPath $package).Hash) -ne 0) { throw 'Portable update failed' }
if ((Get-Item -LiteralPath (Join-Path $ok 'app/EquipmentManager.exe')).VersionInfo.ProductVersion.Split('+')[0] -ne $Version) { throw 'Portable version mismatch' }
if ((Get-Content -LiteralPath (Join-Path $ok 'app/user-marker.txt')).Trim() -ne 'preserve user files') { throw 'Portable user marker changed' }
'PASS portable update and preserved user file'

$bad = New-Fixture 'bad-hash'
$package = Join-Path $bad 'stage/update.zip'
Copy-Item -LiteralPath $newArchive -Destination $package
$before = (Get-FileHash -LiteralPath (Join-Path $bad 'app/EquipmentManager.exe')).Hash
if ((Invoke-Update $bad $package 'portable' ('0' * 64)) -eq 0) { throw 'Bad hash was accepted' }
if ((Get-FileHash -LiteralPath (Join-Path $bad 'app/EquipmentManager.exe')).Hash -ne $before) { throw 'Bad hash modified app' }
if (Test-Path -LiteralPath (Join-Path $bad 'stage/ready.txt')) { throw 'Bad hash reached ready state' }
'PASS bad hash rejected before replacing files'

$locked = New-Fixture 'rollback'
$package = Join-Path $locked 'stage/update.zip'
Copy-Item -LiteralPath $newArchive -Destination $package
$app = Join-Path $locked 'app'
$before = Snapshot-Files $app
$stream = [IO.File]::Open((Join-Path $app 'flutter_windows.dll'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
try { $result = Invoke-Update $locked $package 'portable' (Get-FileHash -LiteralPath $package).Hash }
finally { $stream.Dispose() }
if ($result -eq 0) { throw 'Locked file did not fail the update' }
$after = Snapshot-Files $app
if ($before.Count -ne $after.Count) { throw 'Rollback changed the file set' }
foreach ($key in $before.Keys) { if ($before[$key] -ne $after[$key]) { throw ('Rollback differs: ' + $key) } }
'PASS copy failure rolled back every changed file'

if ($TestSetup) {
  $fixture = New-Fixture 'setup'
  $arguments = @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="{0}"' -f (Join-Path $fixture 'app')))
  $process = Start-Process -FilePath (Resolve-Path -LiteralPath $OldSetup).Path -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
  if ($process.ExitCode -ne 0) { throw 'Old fixture installer failed' }
  $package = Join-Path $fixture 'stage/update.exe'
  Copy-Item -LiteralPath (Resolve-Path -LiteralPath $NewSetup).Path -Destination $package
  if ((Invoke-Update $fixture $package 'setup' (Get-FileHash -LiteralPath $package).Hash) -ne 0) { throw 'Setup update failed' }
  if ((Get-Item -LiteralPath (Join-Path $fixture 'app/EquipmentManager.exe')).VersionInfo.ProductVersion.Split('+')[0] -ne $Version) { throw 'Setup version mismatch' }
  if ((Get-Content -LiteralPath (Join-Path $fixture 'app/user-marker.txt')).Trim() -ne 'preserve user files') { throw 'Setup user marker changed' }
  'PASS setup update and preserved user file'
}
