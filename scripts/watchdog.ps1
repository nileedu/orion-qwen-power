param(
  [ValidateRange(5, 3600)]
  [int]$IntervalSeconds = 20,
  [switch]$Once
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
$LogFile = Join-Path $LogDir "watchdog.log"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$mutex = New-Object System.Threading.Mutex($false, "Local\OrionQwenPowerWatchdog")
$hasLock = $false

function Write-WatchdogLog([string]$Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -Path $LogFile -Value $line
}

function Test-Endpoint([string]$Url) {
  try {
    Invoke-RestMethod -Uri $Url -TimeoutSec 3 | Out-Null
    return $true
  } catch {
    return $false
  }
}

try {
  $hasLock = $mutex.WaitOne(0)
  if (-not $hasLock) { exit 0 }

  Write-WatchdogLog "watchdog started"
  $consecutiveFailures = 0
  do {
    $qwenOk = Test-Endpoint "http://127.0.0.1:3802/health"
    $hubOk = Test-Endpoint "http://127.0.0.1:3800/health"

    if ($qwenOk -and $hubOk) {
      $consecutiveFailures = 0
    } else {
      $consecutiveFailures++
    }

    $bothDown = -not $qwenOk -and -not $hubOk
    $shouldRecover = $Once -or $bothDown -or $consecutiveFailures -ge 2
    if ($shouldRecover -and (-not $qwenOk -or -not $hubOk)) {
      Write-WatchdogLog "recovery requested (qwenproxy=$qwenOk hub=$hubOk)"
      try {
        & "$PSScriptRoot\start.ps1" -Quiet
        Write-WatchdogLog "recovery completed"
        $consecutiveFailures = 0
      } catch {
        Write-WatchdogLog "recovery failed: $($_.Exception.Message)"
      }
    }

    if (-not $Once) { Start-Sleep -Seconds $IntervalSeconds }
  } while (-not $Once)
} finally {
  if ($hasLock) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
