param(
  [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function Write-Status([string]$Message) {
  if (-not $Quiet) { Write-Host $Message }
}

function Test-Endpoint([string]$Url) {
  try {
    Invoke-RestMethod -Uri $Url -TimeoutSec 3 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Wait-Endpoint([string]$Name, [string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-Endpoint $Url) { return }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  throw "$Name did not become healthy within $TimeoutSeconds seconds. Check $LogDir."
}

function Stop-UnhealthyListener([int]$Port) {
  $pids = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
  foreach ($processId in $pids) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }
}

function Rotate-Log([string]$Path) {
  if ((Test-Path $Path) -and (Get-Item $Path).Length -gt 10MB) {
    Move-Item -Force $Path "$Path.1"
  }
}

if (-not (Test-Path "$Root\hub\node_modules")) {
  throw "Hub dependencies are missing. Run .\scripts\setup.ps1 first."
}
if (-not (Test-Path "$Root\proxies\qwenproxy\node_modules")) {
  throw "Qwenproxy dependencies are missing. Run .\scripts\setup.ps1 first."
}

$qwenHealth = "http://127.0.0.1:3802/health"
$hubHealth = "http://127.0.0.1:3800/health"

if (Test-Endpoint $qwenHealth) {
  Write-Status "Qwenproxy already healthy on :3802"
} else {
  Stop-UnhealthyListener 3802
  $log = Join-Path $LogDir "qwenproxy.log"
  Rotate-Log $log
  $qwenRoot = "$Root\proxies\qwenproxy".Replace("'", "''")
  $logPath = $log.Replace("'", "''")
  $command = "Set-Location -LiteralPath '$qwenRoot'; `$env:PORT='3802'; `$env:API_KEY='orion-proxy-key'; `$env:HOST='127.0.0.1'; & npm.cmd run start *>> '$logPath'"
  $qwen = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command
  )
  Write-Status "Starting qwenproxy PID $($qwen.Id) on :3802"
  Wait-Endpoint "qwenproxy" $qwenHealth 60
}

if (Test-Endpoint $hubHealth) {
  Write-Status "Hub already healthy on :3800"
} else {
  Stop-UnhealthyListener 3800
  $log = Join-Path $LogDir "hub.log"
  Rotate-Log $log
  $hubRoot = "$Root\hub".Replace("'", "''")
  $logPath = $log.Replace("'", "''")
  $command = "Set-Location -LiteralPath '$hubRoot'; `$env:PORT='3800'; `$env:HOST='127.0.0.1'; `$env:HUB_API_KEY='orion-proxy-key'; `$env:QWENPROXY_URL='http://127.0.0.1:3802'; `$env:QWENPROXY_KEY='orion-proxy-key'; & npm.cmd run start *>> '$logPath'"
  $hub = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command
  )
  Write-Status "Starting hub PID $($hub.Id) on :3800"
  Wait-Endpoint "hub" $hubHealth 30
}

$models = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" `
  -Headers @{ Authorization = "Bearer orion-proxy-key" } -TimeoutSec 10
if (-not $models.data -or $models.data.Count -eq 0) {
  throw "Hub is healthy but returned no models."
}

Write-Status "Orion Qwen Power is ready with $($models.data.Count) model(s)."
Write-Status "Logs: $LogDir"
