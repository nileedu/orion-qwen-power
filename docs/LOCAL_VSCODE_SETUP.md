# Orion Proxy Stack - VS Code local

Este setup deixa o VS Code usando o Orion local de dois jeitos:

```text
Claude Code = agente, edita arquivos, roda comandos, trabalha no projeto.
Continue = chat/autocomplete simples, bom para perguntar sobre codigo.
Kilo/Cline/Roo = agentes alternativos instalados no VS Code.
Aider/OpenCode = agentes de terminal.
```

## Estado atual

Endpoint local:

```text
http://localhost:3800/v1
```

API key local:

```text
orion-proxy-key
```

O hub agora busca modelos Qwen dinamicamente em `qwenproxy` e expoe todos os modelos `qwen*` como aliases limpos `qwen/...`.

Default recomendado:

```text
qwen/3.7-max
```

Modelos principais:

```text
qwen/3.7-max
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
```

Se o backend Qwen listar mais modelos, eles aparecem automaticamente em:

```powershell
Invoke-RestMethod "http://localhost:3800/v1/models" -Headers @{ Authorization = "Bearer orion-proxy-key" }
```

Ultimo resultado de teste direto dos modelos principais:

```text
qwen/3.7-plus              OK
qwen/3.7-plus-no-thinking  OK
qwen/3.7-max               OK
qwen/3.7-max-no-thinking   OK
qwen/3.6-plus              OK
qwen/coder-plus            OK
skynet/default             OK, mas tende a mostrar raciocinio antes da resposta
```

## Arquitetura Best Of Three

O setup atual mistura os pontos fortes dos tres caminhos analisados:

```text
Nossa stack:
- hub central em :3800
- aliases limpos qwen/...
- integracao Claude Code, Continue, OpenCode e Aider
- cuidado para nao quebrar OAuth

QwenBridge:
- modelos Qwen dinamicos
- endpoint Anthropic /v1/messages
- /v1/messages/count_tokens
- limites de payload
- timeout dinamico por tamanho/modelo
- metricas Prometheus no hub

JHONSSBR/qwenproxy:
- qwenproxy local moderno
- direct fetch/browser fallback no backend
- watchdog, cooldown, health e stream handling no lane Qwen
- ideia futura de GUI propria, sem copiar binario externo
```

Endpoints novos/importantes no hub:

```text
GET  /v1/models
POST /v1/chat/completions
POST /v1/chat/completions/stop
POST /v1/messages
POST /v1/messages/count_tokens
POST /v1/upload
GET  /metrics
GET  /health
```

## Arquivos importantes

Continue:

```text
C:\Users\Nilo\.continue\config.json
```

VS Code settings:

```text
C:\Users\Nilo\AppData\Roaming\Code\User\settings.json
```

Stack:

```text
C:\Users\Nilo\Documents\orion-proxy-stack
```

OpenCode:

```text
C:\Users\Nilo\.config\opencode\opencode.jsonc
C:\Users\Nilo\.local\share\opencode\auth.json
```

Perfil reutilizavel para Kilo/Roo/Cline:

```text
C:\Users\Nilo\.orion-agent-configs\orion-openai-compatible.json
```

## Ligar o stack

Abra PowerShell:

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
.\start-all.ps1
```

Ver status:

```powershell
.\status.ps1
```

O minimo para usar no VS Code e:

```text
hub :3800 ONLINE
qwenproxy :3802 ONLINE
skynetchat :3806 ONLINE
```

## Desligar o stack

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
.\stop-all.ps1
```

## Testar manualmente

Qwen:

```powershell
$body = @{
  model = "qwen/3.7-plus"
  messages = @(@{ role = "user"; content = "responda apenas CONECTADO" })
  stream = $false
} | ConvertTo-Json -Depth 10 -Compress

Invoke-RestMethod "http://localhost:3800/v1/chat/completions" `
  -Method Post `
  -Headers @{ Authorization = "Bearer orion-proxy-key" } `
  -ContentType "application/json" `
  -Body $body
```

SKYNET:

```powershell
$body = @{
  model = "skynet/default"
  messages = @(@{ role = "user"; content = "responda apenas CONECTADO" })
  stream = $false
} | ConvertTo-Json -Depth 10 -Compress

Invoke-RestMethod "http://localhost:3800/v1/chat/completions" `
  -Method Post `
  -Headers @{ Authorization = "Bearer orion-proxy-key" } `
  -ContentType "application/json" `
  -Body $body
```

## Usar no Claude Code dentro do VS Code

Use este para trabalho agentico.

1. Garanta que o stack esta ligado:

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
.\status.ps1
```

2. No VS Code, recarregue a janela:

```text
Ctrl+Shift+P -> Developer: Reload Window
```

3. Abra o painel do Claude Code.

4. Comece uma conversa normal, por exemplo:

```text
olha esse projeto e me diga como rodar
```

ou:

```text
crie os testes para esta tela
```

O Claude Code esta configurado para usar:

```text
ANTHROPIC_BASE_URL=http://localhost:3800
ANTHROPIC_API_KEY=orion-proxy-key
ANTHROPIC_MODEL=qwen/3.7-max
```

Ele continua agentico: pode ler arquivos, editar, rodar terminal e usar bypass permissions.

Para trocar modelo dentro do Claude Code, use:

```text
/model
```

Modelos que devem aparecer:

```text
qwen/3.7-max
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
```

Mesmo se o seletor visual esconder modelo customizado, voce pode digitar:

```text
/model qwen/3.7-max
```

## Usar no Continue dentro do VS Code

Use este para chat simples, explicacao de codigo e autocomplete. Nao e o melhor para tarefas agenticas longas.

1. Abra o VS Code.
2. Recarregue a janela: `Ctrl+Shift+P` -> `Developer: Reload Window`.
3. Abra o painel do Continue.
4. No seletor de modelo, escolha um destes:
   - `Orion - Qwen3.7 Plus`
   - `Orion - Qwen3.7 Plus Direct`
   - `Orion - Qwen3.7 Max`
   - `Orion - Qwen3.7 Max Direct`
   - `Orion - Qwen3.6 Plus`
   - `Orion - Qwen Coder Plus`
   - `Orion - SKYNET`
5. Use o chat do Continue normalmente.

## Usar Kilo Code, Cline ou Roo Code

Estas extensoes estao instaladas:

```text
kilocode.kilo-code
saoudrizwan.claude-dev
rooveterinaryinc.roo-cline
```

Use quando quiser um agente visual dentro do VS Code sem depender do painel do Claude Code.

Configuracao OpenAI-compatible:

```text
Base URL: http://localhost:3800/v1
API key: orion-proxy-key
Model: qwen/3.7-max
```

Modelos alternativos:

```text
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
```

Como configurar no VS Code:

```text
1. Abra o painel da extensao.
2. Escolha Provider: OpenAI Compatible.
3. Preencha Base URL, API key e Model.
4. Salve o perfil como Orion Local.
5. Rode uma pergunta curta: responda apenas OK.
```

O arquivo abaixo tem o perfil pronto para importar/copiar nas extensoes que aceitam importacao:

```text
C:\Users\Nilo\.orion-agent-configs\orion-openai-compatible.json
```

Observacao: Kilo, Cline e Roo guardam perfis/chaves no storage interno do VS Code quando o painel abre. A instalacao foi feita por CLI, mas o primeiro teste real dessas tres precisa ser pelo painel visual da extensao.

## Usar no terminal

Claude Code:

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
claude --model qwen/3.7-plus --dangerously-skip-permissions
```

Novo default recomendado:

```powershell
claude --model qwen/3.7-max --dangerously-skip-permissions
```

Teste rapido:

```powershell
claude -p "responda apenas CLAUDE_OK" --model qwen/3.7-plus --dangerously-skip-permissions --output-format json
```

Aider:

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
$env:OPENAI_API_KEY="orion-proxy-key"
$env:OPENAI_BASE_URL="http://localhost:3800/v1"
aider --model openai/qwen/3.7-plus --openai-api-key orion-proxy-key --openai-api-base http://localhost:3800/v1 --no-auto-commits --no-show-model-warnings --no-check-model-accepts-settings
```

OpenCode:

```powershell
cd "C:\Users\Nilo\Documents\orion-proxy-stack"
opencode --model orion/qwen/3.7-plus-no-thinking
```

Teste rapido:

```powershell
opencode run "responda apenas OPENCODE_OK" --model orion/qwen/3.7-plus-no-thinking
```

## Qual modelo usar

Uso principal:

```text
Orion - Qwen3.7 Max
```

Respostas mais diretas e rapidas:

```text
Orion - Qwen3.7 Max Direct
```

Uso geral/balanceado:

```text
Orion - Qwen3.7 Plus
```

Codigo:

```text
Orion - Qwen Coder Plus
```

Fallback/alternativa:

```text
Orion - Qwen3.6 Plus
```

## Observabilidade

Metricas Prometheus do hub:

```powershell
Invoke-WebRequest "http://localhost:3800/metrics" -UseBasicParsing
```

Health:

```powershell
Invoke-RestMethod "http://localhost:3800/health"
```

Contagem aproximada de tokens Anthropic:

```powershell
$body = @{
  model = "qwen/3.7-max"
  messages = @(@{ role = "user"; content = "teste" })
} | ConvertTo-Json -Depth 10

Invoke-RestMethod "http://localhost:3800/v1/messages/count_tokens" `
  -Method Post `
  -Headers @{ "x-api-key" = "orion-proxy-key"; "anthropic-version" = "2023-06-01" } `
  -ContentType "application/json" `
  -Body $body
```

## Veredito por ferramenta

```text
Claude Code no VS Code: 9/10
Melhor opcao principal. Agentico, ja testado no Orion local, edita arquivos e roda terminal.

OpenCode CLI: 8/10
Boa alternativa agentica no terminal. Testado com provedor Orion customizado.

Aider CLI: 8/10
Muito bom para editar codigo com diff no terminal. Testado. Menos confortavel para explorar UI.

Kilo Code: 8/10
Boa alternativa visual ao Claude Code. Instalado; requer primeiro perfil pela UI do VS Code.

Cline: 7.5/10
Agente maduro e direto. Instalado; requer primeiro perfil pela UI do VS Code.

Roo Code: 7/10
Poderoso, mas mais cheio de opcoes e sobrepoe Kilo/Cline. Instalado; requer primeiro perfil pela UI do VS Code.

Continue: 6.5/10
Bom para chat/autocomplete. Nao e a melhor escolha para tarefas agenticas longas.
```

Removidos por nao servirem bem neste setup:

```text
@aaif/goose
claude-code@1.0.0 antigo/duplicado
```

## Claude Code e OAuth

O login OAuth da sua conta Claude continua salvo no arquivo local, mas o Claude Code foi configurado para preferir o Orion local enquanto estas variaveis estiverem ativas.

Para voltar para Conduit/OAuth depois, restaure o backup criado em:

```text
C:\Users\Nilo\.claude\settings.json.orion-backup-*
C:\Users\Nilo\.claude.json.orion-backup-*
C:\Users\Nilo\AppData\Roaming\Code\User\settings.json.orion-backup-*
```

O Orion tambem esta exposto como OpenAI local para o Continue:

```text
OPENAI_BASE_URL=http://localhost:3800/v1
OPENAI_API_KEY=orion-proxy-key
OPENAI_MODEL=qwen/3.7-plus
```

## Backends instalados mas nao habilitados no Continue

Estes ficam fora do menu do Continue/Claude Code ate responderem conteudo valido em teste real:

```text
deepseek/v4-pro
kimi/k2d6
anthropic/claude-sonnet-4.6 via grouter
xiaomi/mimo-*
```

Motivo atual:

```text
DeepSeek: health OK, mas nao esta na lista final de modelos validados do hub.
Kimi: health OK, mas nao esta na lista final de modelos validados do hub.
Grouter: servico nao esta instalado em :3099.
Mimo: binario/credenciais nao estao prontos em :3804.
```
