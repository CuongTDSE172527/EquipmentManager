$ErrorActionPreference = 'Stop'
$env:CI = 'true'
$env:PUB_CACHE = 'E:\Work\Code\.tooling\pub-cache'
$env:GIT_CONFIG_COUNT = '2'
$env:GIT_CONFIG_KEY_0 = 'safe.directory'
$env:GIT_CONFIG_VALUE_0 = 'E:/Work/Code/.tooling/flutter'
$env:GIT_CONFIG_KEY_1 = 'http.sslBackend'
$env:GIT_CONFIG_VALUE_1 = 'openssl'
& 'E:\Work\Code\.tooling\flutter\bin\flutter.bat' @args
exit $LASTEXITCODE
