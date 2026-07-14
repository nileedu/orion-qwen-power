# VS Code local com Orion Qwen Power

Este manual usa somente o repositorio atual:

```text
C:\Users\Nilo\Documents\orion-qwen-power
```

Nao use `orion-proxy-stack` para iniciar este gateway.

## Estado esperado

```text
Claude Code -> http://localhost:3800 -> qwenproxy :3802 -> Qwen
Modelo padrao: qwen/3.7-max
API key local: orion-proxy-key
```

## Uso diario no VS Code

O watchdog inicia o gateway quando voce entra no Windows e o reinicia se uma das portas cair. Para confirmar:

```powershell
cd "$HOME\Documents\orion-qwen-power"
.\scripts\status.ps1
```

O resultado deve mostrar `OK` para hub e qwenproxy. Depois abra o painel Claude Code normalmente. O modo agente, as ferramentas e `bypass permissions` continuam sendo controlados pelo Claude Code; o modelo de resposta e o Qwen.

Modelos configurados no seletor:

```text
qwen/3.7-max
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
```

Para trocar, use `/model` ou `/model qwen/3.7-max`.

## Configuracao inicial ou reparo

```powershell
cd "$HOME\Documents\orion-qwen-power"
.\scripts\setup.ps1 -InstallBrowsers
.\scripts\start.ps1
.\scripts\configure-claude.ps1 -ClearConflictingUserEnvironment
.\scripts\install-autostart.ps1
.\scripts\test.ps1
```

O configurador preserva os dados da conta OAuth existente, consulta o hub e adiciona ao seletor todos os modelos Qwen disponiveis. Ele remove somente configuracoes conflitantes do caminho proxy: `apiKeyHelper`, `ANTHROPIC_AUTH_TOKEN` e variaveis antigas de outro proxy.

Depois de mudar a configuracao, feche todas as janelas do VS Code e abra de novo. `Developer: Reload Window` pode nao limpar variaveis herdadas por um processo antigo.

## Continue, Cline, Roo, Kilo e OpenCode

Use o provedor `OpenAI Compatible`:

```text
Base URL: http://localhost:3800/v1
API key:  orion-proxy-key
Model:    qwen/3.7-max
```

Esses clientes nao dependem da configuracao OAuth do Claude Code.

## Diagnostico rapido

```powershell
.\scripts\status.ps1
.\scripts\start.ps1
.\scripts\test.ps1
Get-Content .\logs\watchdog.log -Tail 30
Get-Content .\logs\qwenproxy.log -Tail 50
Get-Content .\logs\hub.log -Tail 50
```

Se aparecer `No available account lanes`, a sessao Qwen expirou. Execute:

```powershell
.\scripts\login-qwen.ps1
```

Entre na conta na janela do Chrome, feche a janela de login ao terminar e rode `start.ps1` e `test.ps1` novamente.
