$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Push-Location "$Root\proxies\qwenproxy"
npm run login:chrome
Pop-Location
