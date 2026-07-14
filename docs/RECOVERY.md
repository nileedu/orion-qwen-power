# Recuperacao e disponibilidade

## O que aconteceu no VS Code

`API Error: Unable to connect to API (ConnectionRefused)` significa que o Claude Code tentou acessar `http://localhost:3800`, mas o hub local nao estava executando. A conta OAuth e a sessao Qwen nao foram apagadas.

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

## Claude Code e OAuth

Para reparar apenas o caminho Qwen:

```powershell
.\scripts\configure-claude.ps1 -ClearConflictingUserEnvironment
```

O script preserva o objeto de conta OAuth em `.claude.json`, mas remove `apiKeyHelper` duplicado e `ANTHROPIC_AUTH_TOKEN` do ambiente usado pelo proxy. O arquivo ativo fica com `ANTHROPIC_BASE_URL=http://localhost:3800` e somente `ANTHROPIC_API_KEY=orion-proxy-key`.

Feche e reabra o VS Code depois da reparacao.
