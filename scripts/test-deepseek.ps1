$ErrorActionPreference = "Stop"

$Headers = @{ Authorization = "Bearer orion-proxy-key"; "Content-Type" = "application/json" }
$Model = if ($env:DEEPSEEK_TEST_MODEL) { $env:DEEPSEEK_TEST_MODEL } else { "deepseek/v4-flash" }

Write-Host "Testing DeepSeek model availability through hub..."
$models = Invoke-RestMethod -Uri "http://127.0.0.1:3800/v1/models" -Headers $Headers -TimeoutSec 15
if (-not ($models.data.id -contains $Model)) {
  throw "DeepSeek model $Model is missing from hub /v1/models."
}
Write-Host "OK      $Model available through hub"

Write-Host "Testing DeepSeek chat through hub..."
$body = @{
  model = $Model
  max_tokens = 40
  messages = @(@{ role = "user"; content = "responda exatamente: DEEPSEEK_CONECTADO" })
  stream = $false
} | ConvertTo-Json -Depth 5 -Compress

$response = Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:3800/v1/chat/completions" `
  -Headers $Headers -Body $body -TimeoutSec 180
$text = ([string]$response.choices[0].message.content).Trim()

if ($text -ne "DEEPSEEK_CONECTADO") {
  throw "DeepSeek chat returned unexpected content: $text"
}

if ($response.model -like "qwen*") {
  throw "DeepSeek request fell back to Qwen unexpectedly: $($response.model)"
}

Write-Host "OK      DeepSeek chat -> $text ($($response.model))"
Write-Host "DEEPSEEK TEST PASSED"
