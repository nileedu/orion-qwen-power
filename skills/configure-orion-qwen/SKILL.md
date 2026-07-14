---
name: configure-orion-qwen
description: Configure Orion Qwen Power on Windows, Linux, or macOS for Claude Code, VS Code Continue, OpenAI-compatible clients, or shell environments. Use when an agent must preserve existing Claude OAuth login, avoid ANTHROPIC_AUTH_TOKEN conflicts, set API-key based proxy variables, choose Qwen models, and validate the local hub with /v1/models plus chat tests.
---

# Configure Orion Qwen Power

Use this skill to configure a machine for Orion Qwen Power without breaking existing OAuth login.

## Rules

- Preserve existing Claude Code OAuth files and login state.
- Never create or keep `ANTHROPIC_AUTH_TOKEN` in the environment used for this proxy.
- Use `ANTHROPIC_API_KEY=orion-proxy-key`.
- Use `ANTHROPIC_BASE_URL=http://localhost:3800`.
- Use default model `qwen/3.7-max`.
- Ask the user where to configure it when unclear: Claude Code, VS Code Continue, OpenCode/OpenAI-compatible client, shell profile, or all.
- Merge JSON config files. Do not overwrite unrelated settings.
- Test after configuration.

## Local Endpoints

```text
Hub:       http://localhost:3800
OpenAI:    http://localhost:3800/v1
Qwenproxy: http://localhost:3802
Key:       orion-proxy-key
Default:   qwen/3.7-max
```

## Setup Workflow

1. Detect OS and home directory.
2. Check Node.js with `node --version`; require Node 20+.
3. From the repo root, install dependencies:
   - Windows: `.\scripts\setup.ps1 -InstallBrowsers`
   - Linux/macOS: `INSTALL_BROWSERS=1 ./scripts/setup.sh`
4. If Qwen is not logged in, run:
   - Windows: `.\scripts\login-qwen.ps1`
   - Linux/macOS: `./scripts/login-qwen.sh`
5. Start:
   - Windows: `.\scripts\start.ps1`
   - Linux/macOS: `./scripts/start.sh`
6. On Windows, run `.\scripts\configure-claude.ps1` to merge the Claude settings and discover every Qwen model exposed by the running hub.
7. Configure automatic recovery on Windows with `.\scripts\install-autostart.ps1`.
8. Validate:
   - Windows: `.\scripts\test.ps1`
   - Linux/macOS: `./scripts/test.sh`

## Claude Code Config

Edit or create:

```text
Windows: %USERPROFILE%\.claude\settings.json
Linux/macOS: ~/.claude/settings.json
```

Merge this block:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:3800",
    "ANTHROPIC_API_KEY": "orion-proxy-key",
    "ANTHROPIC_MODEL": "qwen/3.7-max",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  }
}
```

Remove `apiKeyHelper` when `ANTHROPIC_API_KEY` is configured. Do not configure both authentication paths.

If a `permissions` object already exists, preserve it. If missing, it is acceptable to add:

```json
{
  "permissions": {
    "allow": [],
    "deny": []
  }
}
```

Also inspect `~/.claude.json`. If it has an `env` block, update only these keys and remove `ANTHROPIC_AUTH_TOKEN` from that proxy-specific environment. Do not delete OAuth login files.

## Shell Profiles

Only change shell profiles when the user asks for global shell config.

Linux/macOS profile candidates:

```text
~/.bashrc
~/.zshrc
~/.profile
```

Add or update:

```bash
export ANTHROPIC_BASE_URL="http://localhost:3800"
export ANTHROPIC_API_KEY="orion-proxy-key"
export ANTHROPIC_MODEL="qwen/3.7-max"
```

Remove or comment lines exporting `ANTHROPIC_AUTH_TOKEN` only when that shell profile is meant to use Orion Qwen.

Windows PowerShell profile:

```powershell
$PROFILE
```

Add or update:

```powershell
$env:ANTHROPIC_BASE_URL = "http://localhost:3800"
$env:ANTHROPIC_API_KEY = "orion-proxy-key"
$env:ANTHROPIC_MODEL = "qwen/3.7-max"
```

Remove or comment lines setting `ANTHROPIC_AUTH_TOKEN` only when that PowerShell profile is meant to use Orion Qwen.

## VS Code Continue

Open Continue config and add an OpenAI-compatible model:

```json
{
  "title": "Orion Qwen Max",
  "provider": "openai",
  "model": "qwen/3.7-max",
  "apiBase": "http://localhost:3800/v1",
  "apiKey": "orion-proxy-key"
}
```

Query `/v1/models` and add any desired models with the same base/key. Common choices include:

```text
qwen/3.7-max-no-thinking
qwen/3.7-plus
qwen/3.7-plus-no-thinking
qwen/3.6-plus
qwen/coder-plus
```

## Tests

Model list:

```bash
curl http://localhost:3800/v1/models -H "Authorization: Bearer orion-proxy-key"
```

OpenAI chat:

```bash
curl http://localhost:3800/v1/chat/completions \
  -H "Authorization: Bearer orion-proxy-key" \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen/3.7-max","messages":[{"role":"user","content":"responda exatamente: CONECTADO"}]}'
```

Anthropic messages:

```bash
curl http://localhost:3800/v1/messages \
  -H "x-api-key: orion-proxy-key" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{"model":"qwen/3.7-max","max_tokens":40,"messages":[{"role":"user","content":"responda exatamente: CONECTADO"}]}'
```

Success means the model list returns Qwen models and chat returns a normal assistant message.
