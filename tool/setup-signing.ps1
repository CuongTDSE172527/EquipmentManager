param([Parameter(Mandatory=$true)][string]$Keytool,
      [Parameter(Mandatory=$true)][string]$GitHubHelper,
      [string]$Repository='CuongTDSE172527/EquipmentManager')
$ErrorActionPreference='Stop'
$signingDir=Join-Path $PSScriptRoot '..\private\signing'
New-Item -ItemType Directory -Path $signingDir -Force | Out-Null
$store=Join-Path $signingDir 'equipmentmanager.keystore'
$credentialsFile=Join-Path $signingDir 'signing-credentials.json'
if(-not(Test-Path -LiteralPath $store)){
  $randomBytes=New-Object byte[] 32
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$rng.GetBytes($randomBytes)}finally{$rng.Dispose()}
  $password=[BitConverter]::ToString($randomBytes).Replace('-','').ToLowerInvariant()
  $credentials=@{storePassword=$password;keyPassword=$password;alias='equipmentmanager'}
  $env:EM_STORE_PASSWORD=$password
  try{
    & $Keytool -genkeypair -keystore $store -storetype PKCS12 -storepass:env EM_STORE_PASSWORD -keypass:env EM_STORE_PASSWORD -alias equipmentmanager -keyalg RSA -keysize 3072 -validity 10950 -dname 'CN=EquipmentManager, OU=Equipment Management, O=CAH, C=VN'
    if($LASTEXITCODE -ne 0){throw 'Failed to create signing key.'}
    $credentials | ConvertTo-Json | Set-Content -LiteralPath $credentialsFile -Encoding UTF8
  }finally{Remove-Item Env:EM_STORE_PASSWORD}
}else{
  if(-not(Test-Path -LiteralPath $credentialsFile)){throw 'Keystore exists without credentials; refusing to replace it.'}
  $credentials=Get-Content -LiteralPath $credentialsFile -Raw | ConvertFrom-Json
}
$secrets=@{
  ANDROID_KEYSTORE_BASE64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($store))
  KEYSTORE_PASSWORD=$credentials.storePassword
  KEY_ALIAS=$credentials.alias
  KEY_PASSWORD=$credentials.keyPassword
}
foreach($name in $secrets.Keys){
  $secrets[$name] | & $GitHubHelper secret set $name --repo $Repository
  if($LASTEXITCODE -ne 0){throw ('Failed to configure secret: '+$name)}
}
Write-Output 'Configured Android signing secrets. Back up private/signing securely.'
