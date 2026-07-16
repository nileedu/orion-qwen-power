# Orion Qwen Power Agent Instructions

This repository provides the local Qwen gateway used by Claude Code and other VS Code agents.

## Windows Runtime

Use PowerShell from the repository root:

```powershell
.\scripts\status.ps1
.\scripts\start.ps1
.\scripts\test.ps1
```

`start.ps1` is idempotent. `test.ps1` must return `CONECTADO` through both `/v1/chat/completions` and `/v1/messages` before claiming the gateway works.

For complete repair:

```powershell
.\scripts\repair.ps1
```

For an expired Qwen browser session:

```powershell
.\scripts\login-qwen.ps1
```

Preserve `proxies\qwenproxy\data`, `proxies\qwenproxy\qwen_profiles`, `.env` files, and the Claude OAuth account. Never configure `ANTHROPIC_AUTH_TOKEN` for this proxy. Use `ANTHROPIC_API_KEY` with `ANTHROPIC_BASE_URL=http://localhost:3800`.

The automatic recovery task is named `Orion Qwen Power Watchdog`. Read `docs\RECOVERY.md` for diagnosis details.
