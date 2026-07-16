# Recuperacao e disponibilidade

## Onde o Claude procura as instrucoes

O Claude Code separa configuracao de conexao e instrucoes de trabalho:

```text
%USERPROFILE%\.claude\settings.json
endpoint, API key, modelo padrao e lista de modelos

%USERPROFILE%\.claude\CLAUDE.md
instrucoes globais carregadas em qualquer projeto

<projeto>\CLAUDE.md
instrucoes especificas do repositorio atual

%USERPROFILE%\.claude\skills\configure-orion-qwen\SKILL.md
procedimento detalhado de configuracao e recuperacao
```

`AGENTS.md` e usado principalmente pelo Codex. Para garantir que o Claude Code saiba recuperar o Qwen, mantenha as regras no `CLAUDE.md` e a skill no diretorio global do Claude. `scripts\configure-claude.ps1` reinstala a skill automaticamente.

## O que aconteceu no VS Code

`API Error: Unable to connect to API (ConnectionRefused)` significa que o Claude Code tentou acessar `http://localhost:3800`, mas o hub local nao estava executando. A conta OAuth e a sessao Qwen nao foram apagadas.

## Como interpretar 502 e o veredito

O contrato usado pelos clientes e o hub na porta `3800`. As portas `3801` e `3802` sao backends internos controlados por navegador. Um unico 502 em teste direto de backend nao significa que Claude Code esta bloqueado se `scripts\test.ps1` passa pelo hub.

```text
PASS
test.ps1 passa OpenAI + Anthropic e o smoke do claude.exe responde

DEGRADED
hub funciona, mas um diagnostico interno direto e transiente

BLOCKED
3 chamadas consecutivas pelo hub falham depois do reparo, ou login/captcha humano e necessario
```

Qualquer relatorio que diga "evidencia salva" deve informar o caminho absoluto de um arquivo que realmente existe.

Para suspeita de 502 ou instabilidade concorrente, use o teste oficial:

```powershell
.\scripts\test-stability.ps1
```

Ele testa os dois formatos da porta `3800`, executa tres chamadas concorrentes e grava o resultado real em `logs\stability-latest.json`.

## Recuperacao em um comando

```powershell
cd "$HOME\Documents\orion-qwen-power"
.\scripts\start.ps1
```

O script espera as duas portas ficarem saudaveis e valida a lista de modelos antes de retornar. Pode ser executado varias vezes sem criar processos duplicados.

Confirme com uma chamada real:

```powershell
.\scripts\test.ps1
```

Se estiver testando DeepSeek tambem, confirme pelo mesmo hub:

```powershell
.\scripts\test-deepseek.ps1
```

Para refazer tambem a configuracao do Claude Code e a tarefa automatica:

```powershell
.\scripts\repair.ps1
```

## Protecao automatica no Windows

Instale uma vez:

```powershell
.\scripts\install-autostart.ps1
```

Isso cria a tarefa de usuario `Orion Qwen Power Watchdog`. Ela:

- inicia no login do Windows, sem precisar abrir PowerShell como administrador;
- verifica o hub `:3800` e o qwenproxy `:3802` a cada 20 segundos;
- reinicia somente o componente que estiver indisponivel;
- e reiniciada pelo Agendador de Tarefas se o proprio watchdog encerrar.

Verifique a tarefa:

```powershell
Get-ScheduledTask -TaskName "Orion Qwen Power Watchdog"
Get-Content .\logs\watchdog.log -Tail 30
```

Remova a automacao com:

```powershell
.\scripts\uninstall-autostart.ps1
```

## Quando o reinicio automatico nao resolve

Se as portas estao online, mas o chat retorna `No available account lanes`, `captcha` ou erro de sessao, o Qwen exige login humano:

```powershell
.\scripts\login-qwen.ps1
```

Conclua o login no Chrome e teste novamente. O watchdog nao tenta automatizar captcha ou credenciais.

Para DeepSeek, `health` e `/v1/models` podem passar mesmo com sessao web expirada. O teste definitivo e `scripts\test-deepseek.ps1`. Se ele falhar por login/captcha/sessao, renove a sessao interativamente no `deepsproxy` configurado; nao extraia credenciais, nao tente burlar captcha e nao apague dados de sessao sem ordem explicita.

## Claude Code e OAuth

Para reparar apenas o caminho Qwen:

```powershell
.\scripts\configure-claude.ps1 -ClearConflictingUserEnvironment
```

O script preserva o objeto de conta OAuth em `.claude.json`, mas remove `apiKeyHelper` duplicado e `ANTHROPIC_AUTH_TOKEN` do ambiente usado pelo proxy. O arquivo ativo fica com `ANTHROPIC_BASE_URL=http://localhost:3800` e somente `ANTHROPIC_API_KEY=orion-proxy-key`.

Feche e reabra o VS Code depois da reparacao.
