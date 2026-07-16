param(
  [ValidateRange(2, 10)]
  [int]$Concurrency = 3
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$EvidencePath = Join-Path $LogDir "stability-latest.json"

$baseOutput = ""
$basePassed = $false
try {
  $baseOutput = (& "$PSScriptRoot\test.ps1" 2>&1 | Out-String).Trim()
  $basePassed = $true
} catch {
  $baseOutput = $_.Exception.Message
}
Write-Host $baseOutput

try {
  $qwenHealth = Invoke-RestMethod -Uri "http://127.0.0.1:3802/health" -TimeoutSec 5
} catch {
  $qwenHealth = [pscustomobject]@{ status = "unreachable"; error = $_.Exception.Message }
}

$results = @()
if ($basePassed) {
  $worker = {
    param($Run)
    $body = @{
      model = "qwen/3.7-max"
      max_tokens = 20
      messages = @(@{ role = "user"; content = "responda exatamente: PARALELO_$Run" })
    } | ConvertTo-Json -Depth 5 -Compress
    $timer = [Diagnostics.Stopwatch]::StartNew()
    try {
      $response = Invoke-RestMethod -Method Post `
        -Uri "http://127.0.0.1:3800/v1/chat/completions" `
        -Headers @{ Authorization = "Bearer orion-proxy-key"; "Content-Type" = "application/json" } `
        -Body $body -TimeoutSec 240
      $timer.Stop()
      [pscustomobject]@{
        run = $Run
        status = 200
        text = ([string]$response.choices[0].message.content).Trim()
        duration_ms = $timer.ElapsedMilliseconds
        model = $response.model
      }
    } catch {
      $timer.Stop()
      [pscustomobject]@{
        run = $Run
        status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        text = $_.Exception.Message
        duration_ms = $timer.ElapsedMilliseconds
        model = $null
      }
    }
  }

  $jobs = 1..$Concurrency | ForEach-Object { Start-Job -ScriptBlock $worker -ArgumentList $_ }
  $completed = @($jobs | Wait-Job -Timeout 300)
  if ($completed.Count -ne $Concurrency) {
    $jobs | Stop-Job -ErrorAction SilentlyContinue
  }
  $results = @($jobs | Receive-Job -ErrorAction SilentlyContinue)
  $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
}

$parallelPassed = $results.Count -eq $Concurrency
foreach ($result in $results) {
  $expected = "PARALELO_$($result.run)"
  if ($result.status -ne 200 -or $result.text -ne $expected) {
    $parallelPassed = $false
  }
}

$verdict = if ($basePassed -and $parallelPassed) { "PASS" } else { "BLOCKED" }
$evidence = [ordered]@{
  timestamp = (Get-Date).ToString("o")
  verdict = $verdict
  supported_endpoint = "http://127.0.0.1:3800"
  qwenproxy_internal_status = $qwenHealth.status
  base_test_passed = $basePassed
  base_test_output = $baseOutput
  concurrent_results = @($results | Sort-Object run)
}
$evidence | ConvertTo-Json -Depth 10 | Set-Content -Path $EvidencePath -Encoding utf8

$results | Sort-Object run | Format-Table run, status, text, duration_ms, model -AutoSize
Write-Host "VERDICT=$verdict"
Write-Host "EVIDENCE=$EvidencePath"

if ($verdict -ne "PASS") {
  throw "Stability validation failed. Evidence: $EvidencePath"
}
