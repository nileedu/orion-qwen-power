# test-qwen-coder-contract.ps1
# Reproduz empiricamente o comportamento de qwen/3-coder-plus-no-thinking em 4 caminhos:
#   A. backend/proxy bruto (qwenproxy, porta 3802, sem passar pelo hub)
#   B. hub Orion /v1/chat/completions (porta 3800)
#   C. hub Orion /v1/messages (formato Anthropic, porta 3800)
#   D. streaming SSE via hub (porta 3800, stream:true)
# Salva request normalizado (sem segredo) + resposta completa de cada caminho em
# tests/fixtures/qwen-coder-response-cases/, e imprime um resumo comparativo.

$ErrorActionPreference = "Continue"
$HUB = "http://127.0.0.1:3800"
$BACKEND = "http://127.0.0.1:3802"
$KEY = "orion-proxy-key"
$MODEL = "qwen/3-coder-plus-no-thinking"
$BACKEND_MODEL = "qwen3-coder-plus-no-thinking"
$OUTDIR = "C:\Users\Nilo\Documents\orion-qwen-power\tests\fixtures\qwen-coder-response-cases"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$prompts = @(
  @{ name = "json-estrito"; content = 'Responda APENAS com um JSON valido de uma linha: {"status":"ok","numero":42}. Nao escreva mais nada alem do JSON.' },
  @{ name = "funcao-curta"; content = "Revise esta funcao Python em 2 frases curtas: `ndef soma(a, b):`n    return a - b`n`nHa um bug? Qual?" },
  @{ name = "tres-linhas-marcadores"; content = "Responda EXATAMENTE com estas 3 linhas, sem nada antes ou depois: `nLINHA1: ok`nLINHA2: ok`nLINHA3: fim" },
  @{ name = "codigo-checksum"; content = "Escreva uma funcao JavaScript curta chamada soma(a,b) que retorna a+b. Depois escreva uma linha separada: CHECKSUM: OK" }
)

function Invoke-JsonPost($url, $body, $timeoutSec = 60) {
  $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
  $result = [ordered]@{
    url = $url
    request_body_normalized = ($body | ConvertTo-Json -Depth 10)
    status = $null
    headers = $null
    raw_response = $null
    parsed = $null
    error = $null
    elapsed_ms = $null
  }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $resp = Invoke-WebRequest -Uri $url -Method Post -Headers @{Authorization = "Bearer $KEY"} `
      -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
      -TimeoutSec $timeoutSec -ErrorAction Stop
    $sw.Stop()
    $result.elapsed_ms = $sw.ElapsedMilliseconds
    $result.status = [int]$resp.StatusCode
    $result.headers = ($resp.Headers | ConvertTo-Json -Compress)
    $raw = $resp.Content
    $result.raw_response = $raw
    try { $result.parsed = $raw | ConvertFrom-Json } catch { $result.parsed = $null }
  } catch {
    $sw.Stop()
    $result.elapsed_ms = $sw.ElapsedMilliseconds
    $result.error = $_.Exception.Message
    if ($_.Exception.Response) {
      try {
        $result.status = [int]$_.Exception.Response.StatusCode
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $result.raw_response = $reader.ReadToEnd()
      } catch {}
    }
  }
  return $result
}

function Summarize($label, $result) {
  $contentVal = $null
  $reasoningVal = $null
  $finishReason = $null
  $completionTokens = $null
  if ($result.parsed) {
    $msg = $result.parsed.choices[0].message
    if ($msg) {
      $contentVal = $msg.content
      $reasoningVal = $msg.reasoning_content
    }
    $finishReason = $result.parsed.choices[0].finish_reason
    $completionTokens = $result.parsed.usage.completion_tokens
  }
  [PSCustomObject]@{
    caminho = $label
    status = $result.status
    elapsed_ms = $result.elapsed_ms
    completion_tokens = $completionTokens
    content_length = if ($contentVal) { $contentVal.Length } else { 0 }
    content_preview = if ($contentVal) { $contentVal.Substring(0, [Math]::Min(80, $contentVal.Length)) } else { "(vazio/null)" }
    reasoning_content_present = [bool]$reasoningVal
    finish_reason = $finishReason
    error = $result.error
  }
}

$allSummaries = @()

foreach ($p in $prompts) {
  Write-Output "=== Prompt: $($p.name) ==="

  # Caminho A: backend bruto (qwenproxy porta 3802), model = backend id
  $bodyA = @{ model = $BACKEND_MODEL; messages = @(@{role = "user"; content = $p.content}); temperature = 0.1; stream = $false }
  $resA = Invoke-JsonPost "$BACKEND/v1/chat/completions" $bodyA 90
  $resA | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OUTDIR\$($p.name)__A-backend-bruto.json" -Encoding utf8
  $sumA = Summarize "A-backend-bruto" $resA
  $allSummaries += $sumA

  # Caminho B: hub /v1/chat/completions, model = public id
  $bodyB = @{ model = $MODEL; messages = @(@{role = "user"; content = $p.content}); temperature = 0.1; stream = $false }
  $resB = Invoke-JsonPost "$HUB/v1/chat/completions" $bodyB 90
  $resB | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OUTDIR\$($p.name)__B-hub-chat-completions.json" -Encoding utf8
  $sumB = Summarize "B-hub-chat-completions" $resB
  $allSummaries += $sumB

  # Caminho C: hub /v1/messages (formato Anthropic)
  $bodyC = @{ model = $MODEL; messages = @(@{role = "user"; content = $p.content}); max_tokens = 1024; stream = $false }
  $resC = Invoke-JsonPost "$HUB/v1/messages" $bodyC 90
  $resC | ConvertTo-Json -Depth 10 | Out-File -FilePath "$OUTDIR\$($p.name)__C-hub-messages.json" -Encoding utf8
  $contentC = $null
  if ($resC.parsed -and $resC.parsed.content) {
    $textBlock = $resC.parsed.content | Where-Object { $_.type -eq "text" } | Select-Object -First 1
    if ($textBlock) { $contentC = $textBlock.text }
  }
  $sumC = [PSCustomObject]@{
    caminho = "C-hub-messages"
    status = $resC.status
    elapsed_ms = $resC.elapsed_ms
    completion_tokens = if ($resC.parsed) { $resC.parsed.usage.output_tokens } else { $null }
    content_length = if ($contentC) { $contentC.Length } else { 0 }
    content_preview = if ($contentC) { $contentC.Substring(0, [Math]::Min(80, $contentC.Length)) } else { "(vazio/null)" }
    reasoning_content_present = $false
    finish_reason = if ($resC.parsed) { $resC.parsed.stop_reason } else { $null }
    error = $resC.error
  }
  $allSummaries += $sumC

  Write-Output ($allSummaries | Where-Object { $_.caminho -like "*$($p.name -replace '.*','' )*" -or $true } | Select-Object -Last 3 | Format-Table -AutoSize | Out-String)
}

$allSummaries | Export-Csv -Path "$OUTDIR\_resumo_comparativo.csv" -NoTypeInformation -Encoding UTF8
$allSummaries | ConvertTo-Json -Depth 5 | Out-File -FilePath "$OUTDIR\_resumo_comparativo.json" -Encoding utf8
Write-Output ""
Write-Output "=== RESUMO COMPARATIVO COMPLETO ==="
$allSummaries | Format-Table -AutoSize | Out-String | Write-Output
