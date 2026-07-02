# test-qwen-coder-stress.ps1
# Duas hipoteses finais antes de concluir "nao reproduzido":
#  1. Resposta MUITO longa (>5000 chars) - estressa a janela de scan de 2000 chars
#     em getIncrementalDelta com mais forca.
#  2. Concorrencia: 3 requisicoes simultaneas (nao sequenciais) ao mesmo backend.

$ErrorActionPreference = "Continue"
$HUB = "http://127.0.0.1:3800"
$KEY = "orion-proxy-key"
$MODEL = "qwen/3-coder-plus-no-thinking"
$OUTDIR = "C:\Users\Nilo\Documents\orion-qwen-power\tests\fixtures\qwen-coder-response-cases"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$longPrompt = @"
Escreva um guia extremamente detalhado e longo (nao resuma, seja exaustivo) sobre
boas praticas de tratamento de erros em Python, cobrindo TODOS estes topicos, cada
um com pelo menos 1 paragrafo de explicacao e 1 exemplo de codigo curto:
1. try/except especifico vs generico
2. finally e context managers
3. excecoes customizadas
4. logging de excecoes
5. re-raise vs suprimir
6. excecoes em generators
7. excecoes em async/await
8. excecoes em threads
9. retry com backoff
10. excecoes e testes unitarios
11. excecoes e APIs publicas (design de biblioteca)
12. excecoes e validacao de entrada
13. excecoes e recursos externos (arquivos, rede, banco)
14. anti-padroes comuns
15. ferramentas de analise estatica para deteccao de excecoes mal tratadas
"@

Write-Output "=== Teste 1: resposta MUITO longa (non-streaming, hub) ==="
$body = @{ model = $MODEL; messages = @(@{role = "user"; content = $longPrompt}); temperature = 0.1; stream = $false; max_tokens = 4000 }
$bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
try {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $resp = Invoke-WebRequest -Uri "$HUB/v1/chat/completions" -Method Post -Headers @{Authorization = "Bearer $KEY"} `
    -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
    -TimeoutSec 180 -ErrorAction Stop
  $sw.Stop()
  $resp.Content | Out-File -FilePath "$OUTDIR\muito-longo__B-hub-nonstream.json" -Encoding utf8
  $parsed = $resp.Content | ConvertFrom-Json
  $content = $parsed.choices[0].message.content
  Write-Output "status=$($resp.StatusCode) elapsed=$($sw.ElapsedMilliseconds)ms completion_tokens=$($parsed.usage.completion_tokens) content_length=$($content.Length) finish_reason=$($parsed.choices[0].finish_reason)"
  Write-Output "  tail: $($content.Substring([Math]::Max(0,$content.Length-200)))"
} catch {
  Write-Output "ERRO: $($_.Exception.Message)"
}

Write-Output ""
Write-Output "=== Teste 2: 3 requisicoes CONCORRENTES (paralelo real) ==="
$jobs = @()
for ($i = 1; $i -le 3; $i++) {
  $jobs += Start-Job -ScriptBlock {
    param($hub, $key, $model, $idx, $outdir)
    $body = @{ model = $model; messages = @(@{role = "user"; content = "Escreva um paragrafo curto (3-4 frases) explicando o que e recursao em programacao, numerado como resposta $idx."}); temperature = 0.1; stream = $false }
    $bodyJson = $body | ConvertTo-Json -Depth 10 -Compress
    try {
      $resp = Invoke-WebRequest -Uri "$hub/v1/chat/completions" -Method Post -Headers @{Authorization = "Bearer $key"} `
        -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
        -TimeoutSec 60 -ErrorAction Stop
      $resp.Content | Out-File -FilePath "$outdir\concorrente-$idx.json" -Encoding utf8
      $parsed = $resp.Content | ConvertFrom-Json
      return "job$idx : status=$($resp.StatusCode) tokens=$($parsed.usage.completion_tokens) content_length=$($parsed.choices[0].message.content.Length)"
    } catch {
      return "job$idx : ERRO $($_.Exception.Message)"
    }
  } -ArgumentList $HUB, $KEY, $MODEL, $i, $OUTDIR
}
$results = $jobs | Wait-Job -Timeout 90 | Receive-Job
$jobs | Remove-Job -Force
$results | ForEach-Object { Write-Output $_ }
