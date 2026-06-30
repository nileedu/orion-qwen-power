# Security Policy

Orion Qwen Power is designed for local use.

## Defaults

- The hub binds to `127.0.0.1` by default.
- Local secrets, browser state, Qwen session files, logs, databases, and `.env` files are ignored by Git.
- Do not publish `proxies/qwenproxy/data`, `proxies/qwenproxy/qwen_profiles`, `.env`, or logs.
- Change `HUB_API_KEY` if you expose the hub beyond your own machine.

## Claude Code Auth

Do not delete Claude Code OAuth login files unless the user explicitly asks.

For Orion Qwen Power, the active proxy environment should use:

```text
ANTHROPIC_BASE_URL=http://localhost:3800
ANTHROPIC_API_KEY=<your local hub key>
```

Do not keep `ANTHROPIC_AUTH_TOKEN` active in that same proxy environment, because it can route Claude Code through OAuth instead of the local API-key proxy path.

## Reporting

Open a private issue or contact the maintainer before disclosing a sensitive bug publicly.
