$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$qwen = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
  "-NoProfile","-ExecutionPolicy","Bypass","-Command",
  "cd '$Root\proxies\qwenproxy'; `$env:PORT='3802'; `$env:API_KEY='orion-proxy-key'; `$env:HOST='127.0.0.1'; npm run start *> '$LogDir\qwenproxy.log'"
)

Start-Sleep -Seconds 3

$hub = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
  "-NoProfile","-ExecutionPolicy","Bypass","-Command",
  "cd '$Root\hub'; `$env:PORT='3800'; `$env:HOST='127.0.0.1'; `$env:HUB_API_KEY='orion-proxy-key'; `$env:QWENPROXY_URL='http://localhost:3802'; `$env:QWENPROXY_KEY='orion-proxy-key'; npm run start *> '$LogDir\hub.log'"
)

Write-Host "Started qwenproxy PID $($qwen.Id) on :3802"
Write-Host "Started hub PID $($hub.Id) on :3800"
Write-Host "Logs: $LogDir"
