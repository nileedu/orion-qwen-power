# Orion Qwen Power

Orion Qwen Power is a local Qwen-first AI gateway for Windows and Linux.

It exposes one local OpenAI-compatible and Anthropic-compatible endpoint:

```text
http://localhost:3800
```

Default model:

```text
qwen/3.7-max
```

Author: nileedu

## What This Provides

- Qwen web session bridge through `qwenproxy`.
- A local hub on port `3800`.
- OpenAI-compatible `/v1/chat/completions`.
- Anthropic-compatible `/v1/messages` for Claude Code style clients.
- `/v1/models` with dynamic Qwen model discovery.
- Fallback between Qwen models when one fails.
- Metrics at `/metrics`.
- Windows PowerShell and Linux/macOS shell scripts.
- A bundled AI configuration skill in `skills/configure-orion-qwen`.

## Architecture

```text
Claude Code / Continue / OpenCode / curl / SDK
                  |
                  v
       Orion Qwen Power Hub :3800
                  |
                  v
          qwenproxy :3802
                  |
                  v
            chat.qwen.ai
```

The hub accepts either `Authorization: Bearer orion-proxy-key` or `x-api-key: orion-proxy-key`.

## Models

The public model names are stable even if Qwen changes internal names:

```text
qwen/3.7-max
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
qwen/3.6-max-preview
qwen/3.6-27b
qwen/3.6-35b-a3b
qwen/3.5-plus
qwen/3.5-omni-plus
qwen/3.5-flash
```

The hub maps these to backend names such as `qwen3.7-max` automatically.

## Requirements

- Node.js 20 or newer.
- npm.
- Chrome recommended for login.
- A logged-in Qwen account when using account-backed models.

Guest mode may work depending on Qwen availability, but account login is the reliable path.

## Windows Install

```powershell
git clone https://github.com/nileedu/orion-qwen-power.git
cd orion-qwen-power
.\scripts\setup.ps1 -InstallBrowsers
```

Login:

```powershell
.\scripts\login-qwen.ps1
```

Start:

```powershell
.\scripts\start.ps1
```

Status:

```powershell
.\scripts\status.ps1
```

Test:

```powershell
.\scripts\test.ps1
```

Stop:

```powershell
.\scripts\stop.ps1
```

## Linux/macOS Install

```bash
git clone https://github.com/nileedu/orion-qwen-power.git
cd orion-qwen-power
chmod +x scripts/*.sh
INSTALL_BROWSERS=1 ./scripts/setup.sh
```

Login:

```bash
./scripts/login-qwen.sh
```

Start:

```bash
./scripts/start.sh
```

Status:

```bash
./scripts/status.sh
```

Test:

```bash
./scripts/test.sh
```

Stop:

```bash
./scripts/stop.sh
```

## Claude Code

Recommended config file:

Windows:

```text
C:\Users\<you>\.claude\settings.json
```

Linux/macOS:

```text
~/.claude/settings.json
```

Config:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:3800",
    "ANTHROPIC_API_KEY": "orion-proxy-key",
    "ANTHROPIC_MODEL": "qwen/3.7-max",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "permissions": {
    "allow": [],
    "deny": []
  },
  "apiKeyHelper": "echo 'orion-proxy-key'"
}
```

Important: do not set `ANTHROPIC_AUTH_TOKEN`. If it exists in shell profiles, `.claude.json`, `.claude/settings.json`, or environment variables, remove it. It bypasses the intended API-key flow and can break proxy routing.

If you are already logged into Claude Code with OAuth, do not delete the OAuth files. Only set the API environment for the workspace or shell where you want to use Orion Qwen.

## VS Code Continue

Use OpenAI-compatible mode:

```json
{
  "title": "Orion Qwen Max",
  "provider": "openai",
  "model": "qwen/3.7-max",
  "apiBase": "http://localhost:3800/v1",
  "apiKey": "orion-proxy-key"
}
```

Add more models with the same `apiBase` and `apiKey`.

## OpenAI SDK

```bash
curl http://localhost:3800/v1/chat/completions \
  -H "Authorization: Bearer orion-proxy-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/3.7-max","messages":[{"role":"user","content":"responda: CONECTADO"}]}'
```

## Anthropic API Compatibility

```bash
curl http://localhost:3800/v1/messages \
  -H "x-api-key: orion-proxy-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"qwen/3.7-max","max_tokens":40,"messages":[{"role":"user","content":"responda: CONECTADO"}]}'
```

## AI Setup Skill

The repo includes:

```text
skills/configure-orion-qwen/SKILL.md
```

Give that skill to Codex, Claude Code, or another coding agent and ask:

```text
Use the configure-orion-qwen skill to configure this machine for Orion Qwen Power.
Preserve existing OAuth login. Ask whether I want Claude Code, VS Code Continue, OpenCode, shell env, or all of them. Then test /v1/models and a chat request.
```

## Troubleshooting

If `/v1/models` works but chat fails:

- Run `scripts/login-qwen.*`.
- Confirm `qwenproxy` is online on `http://localhost:3802/health`.
- Check `logs/qwenproxy.log`.
- If Qwen asks for captcha or re-login, complete it in the browser opened by the login script.

If Claude Code ignores the proxy:

- Remove `ANTHROPIC_AUTH_TOKEN`.
- Keep only `ANTHROPIC_API_KEY`.
- Restart the terminal or reload VS Code.

If a port is busy:

- Hub uses `3800`.
- qwenproxy uses `3802`.
- Stop old processes with `scripts/stop.*` or change ports in the `.env` files.

## Validation Checklist

Run these before sharing with a user:

```bash
cd hub && npm install && npx tsc --noEmit
cd ../proxies/qwenproxy && npm install && npm run typecheck
cd ../.. && ./scripts/status.sh
cd ../.. && ./scripts/test.sh
```

On Windows, use the `.ps1` equivalents.
