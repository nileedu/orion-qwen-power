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

Port `3800` is the supported client contract. Port `3802` is an internal browser-session backend and a single direct 502 is not enough to classify the system as blocked. Verdict rules:

- `PASS`: `test.ps1` passes both API formats and a Claude Code smoke request succeeds.
- `DEGRADED`: hub requests pass while an internal direct diagnostic is transient.
- `BLOCKED`: three consecutive hub chat requests fail after recovery, or human login/captcha is required.

Never claim that evidence was saved without providing an absolute path to an existing file.

When a 502 or instability is suspected, run `scripts\test-stability.ps1`. It validates both API formats, sends concurrent requests through the supported hub, prints the verdict, and writes real evidence to `logs\stability-latest.json`.

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
