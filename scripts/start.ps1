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
    Invoke-RestMethod -Uri $Url -TimeoutSec 5 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Test-AuthenticatedEndpoint([string]$Url, [string]$Key) {
  try {
    Invoke-RestMethod -Uri $Url -Headers @{ Authorization = "Bearer $Key" } -TimeoutSec 5 | Out-Null
    return $true
  } catch {
    return $false
  }
}

function Wait-Endpoint([string]$Name, [string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-Endpoint $Url) { return }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)

  throw "$Name did not become reachable within $TimeoutSeconds seconds. Check $LogDir."
}

function Wait-AuthenticatedEndpoint([string]$Name, [string]$Url, [string]$Key, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-AuthenticatedEndpoint $Url $Key) { return }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)

  throw "$Name did not become reachable within $TimeoutSeconds seconds. Check $LogDir."
}

function Stop-ProcessTree([int]$ProcessId) {
  if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
    & "$env:SystemRoot\System32\taskkill.exe" /PID $ProcessId /T /F 2>$null | Out-Null
    Start-Sleep -Milliseconds 500
  }
}

function Stop-UnhealthyListener([int]$Port) {
  $pids = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
  foreach ($processId in $pids) {
    Stop-ProcessTree $processId
  }
}

function Stop-StaleProcesses([string]$PathMarker) {
  $matches = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.ProcessId -ne $PID -and
      $_.Name -match '^(node|powershell|cmd)\.exe$' -and
      $_.CommandLine -and
      $_.CommandLine.IndexOf($PathMarker, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } |
    Sort-Object CreationDate

  foreach ($process in $matches) {
    Stop-ProcessTree $process.ProcessId
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

$DeepseekRoot = if ($env:DEEPSPROXY_ROOT) { $env:DEEPSPROXY_ROOT } else { "$HOME\Documents\orion-proxy-stack\proxies\deepsproxy" }
$DeepseekAvailable = (Test-Path "$DeepseekRoot\package.json") -and (Test-Path "$DeepseekRoot\node_modules")

$startMutex = New-Object System.Threading.Mutex($false, "Local\OrionQwenPowerStart")
$hasStartLock = $false

try {
  $hasStartLock = $startMutex.WaitOne([TimeSpan]::FromMinutes(6))
  if (-not $hasStartLock) {
    throw "Another Orion Qwen startup is still running after 6 minutes."
  }

  $qwenHealth = "http://127.0.0.1:3802/health"
  $deepseekHealth = "http://127.0.0.1:3801/health"
  $hubHealth = "http://127.0.0.1:3800/health"

  if ($DeepseekAvailable) {
    if (Test-AuthenticatedEndpoint $deepseekHealth "orion-proxy-key") {
      Write-Status "Deepsproxy already reachable on :3801"
    } else {
      Stop-UnhealthyListener 3801
      Stop-StaleProcesses $DeepseekRoot
      $log = Join-Path $LogDir "deepsproxy.log"
      Rotate-Log $log
      $deepseekRootEscaped = $DeepseekRoot.Replace("'", "''")
      $logPath = $log.Replace("'", "''")
      $command = "Set-Location -LiteralPath '$deepseekRootEscaped'; `$env:PORT='3801'; `$env:API_KEY='orion-proxy-key'; `$env:PLAYWRIGHT_HEADLESS='true'; & npm.cmd run start *>> '$logPath'"
      $deepseek = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command
      )
      Write-Status "Starting deepsproxy PID $($deepseek.Id) on :3801"
      try {
        Wait-AuthenticatedEndpoint "deepsproxy" $deepseekHealth "orion-proxy-key" 180
      } catch {
        Stop-ProcessTree $deepseek.Id
        throw
      }
    }
  } else {
    Write-Status "Deepsproxy not configured; skipping optional DeepSeek backend ($DeepseekRoot)"
  }

  if (Test-Endpoint $qwenHealth) {
    Write-Status "Qwenproxy already reachable on :3802"
  } else {
    Stop-UnhealthyListener 3802
    Stop-StaleProcesses "$Root\proxies\qwenproxy"
    $log = Join-Path $LogDir "qwenproxy.log"
    Rotate-Log $log
    $qwenRoot = "$Root\proxies\qwenproxy".Replace("'", "''")
    $logPath = $log.Replace("'", "''")
    $command = "Set-Location -LiteralPath '$qwenRoot'; `$env:PORT='3802'; `$env:API_KEY='orion-proxy-key'; `$env:HOST='127.0.0.1'; & npm.cmd run start *>> '$logPath'"
    $qwen = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command
    )
    Write-Status "Starting qwenproxy PID $($qwen.Id) on :3802"
    try {
      Wait-Endpoint "qwenproxy" $qwenHealth 240
    } catch {
      Stop-ProcessTree $qwen.Id
      throw
    }
  }

  if (Test-Endpoint $hubHealth) {
    Write-Status "Hub already reachable on :3800"
  } else {
    Stop-UnhealthyListener 3800
    Stop-StaleProcesses "$Root\hub"
    $log = Join-Path $LogDir "hub.log"
    Rotate-Log $log
    $hubRoot = "$Root\hub".Replace("'", "''")
    $logPath = $log.Replace("'", "''")
    $command = "Set-Location -LiteralPath '$hubRoot'; `$env:PORT='3800'; `$env:HOST='127.0.0.1'; `$env:HUB_API_KEY='orion-proxy-key'; `$env:QWENPROXY_URL='http://127.0.0.1:3802'; `$env:QWENPROXY_KEY='orion-proxy-key'; `$env:DEEPSPROXY_URL='http://127.0.0.1:3801'; `$env:DEEPSPROXY_KEY='orion-proxy-key'; & npm.cmd run start *>> '$logPath'"
    $hub = Start-Process powershell.exe -WindowStyle Hidden -PassThru -ArgumentList @(
      "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command
    )
    Write-Status "Starting hub PID $($hub.Id) on :3800"
    try {
      Wait-Endpoint "hub" $hubHealth 60
    } catch {
      Stop-ProcessTree $hub.Id
      throw
    }
  }

  $models = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" `
    -Headers @{ Authorization = "Bearer orion-proxy-key" } -TimeoutSec 15
  if (-not $models.data -or $models.data.Count -eq 0) {
    throw "Hub is reachable but returned no models."
  }

  Write-Status "Orion Qwen Power is ready with $($models.data.Count) model(s)."
  Write-Status "Logs: $LogDir"
} finally {
  if ($hasStartLock) { $startMutex.ReleaseMutex() }
  $startMutex.Dispose()
}
