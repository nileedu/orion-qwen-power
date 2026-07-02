# Qwen Coder — Root Cause Investigation

> Branch: `feat/multimodel-runtime-deepseek` (both `orion-qwen-power` and
> `orion-proxy-stack`). Investigates the historical symptom: `qwen/3-coder-plus-no-thinking`
> occasionally returned `completion_tokens > 0` with `content` reduced to only a
> trailing marker/fragment, no `reasoning_content` fallback.

## Summary

Extensive empirical testing against the live hub (16+ real API calls across 4
request paths, short prompts, one medium "audit" prompt repeated 3x, and one
very long response) **could not reproduce the historical symptom** under
current conditions. Every sequential request — including an 8741-character,
2245-completion-token response — returned complete, coherent content with
`finish_reason: "stop"`.

A **different, real, and reproducible** defect was found instead: concurrent
requests to the qwen backend return HTTP 502 for all but one caller. This is
fixed (Fase 1, item below). Two additional real bugs were found by static
code audit of the vendored `qwenproxy` fork and fixed defensively, though
neither was proven to be the cause of the original symptom (see honesty note
per bug below). All fixes are covered by passing regression tests.

**This document does not claim the historical symptom is fully explained.**
If it recurs, the most useful next step is to capture a raw request/response
pair (`scripts/test-qwen-coder-contract.ps1` writes fixtures to
`tests/fixtures/qwen-coder-response-cases/`) at the moment of failure — the
static audit ran out of unexplored hypotheses that don't require a live
repro.

## Method (per the 4 required paths)

| Path | What | Result |
|---|---|---|
| A | Raw backend, qwenproxy `:3802` direct | ✅ all prompts, incl. long |
| B | Hub `/v1/chat/completions` `:3800` | ✅ all prompts, incl. long, 3x repeat |
| C | Hub `/v1/messages` (Anthropic adapter) `:3800` | ✅ all prompts |
| D | Streaming SSE via hub | ✅ 325 chunks, complete content |

Test prompts used (`scripts/test-qwen-coder-contract.ps1`): strict JSON,
short function review, 3 marked lines, code + checksum line. Medium/long
prompts (`scripts/test-qwen-coder-stream.ps1`, `scripts/test-qwen-coder-stress.ps1`):
a 15-point code-audit request (~3000-3800 char response) repeated 3x, and a
15-topic error-handling guide (~8446-8741 char response, 2172-2245 completion
tokens) — well past the historical ~2050-token failure range.

Raw request/response pairs for every test are saved under
`tests/fixtures/qwen-coder-response-cases/` (git-ignored — see Fase 6 secrets
scan; these are local diagnostic artifacts, not committed).

## Bug #1 (real, reproduced, fixed): concurrent requests return 502

**Reproduction:** 3 simultaneous requests to the hub → 1 succeeded (200), 2
failed with `502 Bad Gateway`. Sequential requests of any length never
failed.

**Cause:** `qwenproxy` drives Qwen through a single Playwright browser
session per account, serialized internally by a `Mutex`
(`services/browser-manager.ts`). That mutex has no timeout and queues
correctly — but nothing *upstream* of qwenproxy protects against requests
piling up faster than one browser session can drain them 1-by-1, and
qwenproxy's own test suite (`tests/concurrency.test.ts`) explicitly documents
502 as an accepted outcome under contention ("Concurrent requests are
serialized by mutex" — assertion allows `200 | 429 | 502`).

**Fix:** `hub/src/server.ts` now enforces "concurrency 1 per backend" itself,
via an in-hub `BackendQueue` wrapping the upstream `fetch()` call. Any client
calling the hub — regardless of its own concurrency behavior — gets safe,
serialized access by default. Configurable per backend via
`QWEN_BACKEND_CONCURRENCY` (orion-qwen-power) /
`{PROVIDER}_BACKEND_CONCURRENCY` (orion-proxy-stack, all 6 backends; grouter
defaults higher since it fronts a real multi-tenant API, not a browser
session).

**Verified:** re-ran the same 3-concurrent-request test after restarting the
hub with the fix — all 3 succeeded (200/200/200, no 502). See
`scripts/test-qwen-coder-stress.ps1`.

**Honesty note:** a clean 502 is a different failure *shape* than the
historical "200 with marker-only content." This fix closes a real,
independently confirmed defect and directly satisfies the acceptance
criterion "concorrencia padrao igual a 1" — it is not asserted to be the
same bug as the original report.

## Bug #2 (real, found by static audit, fixed): tool-call tag leak

**File:** `proxies/qwenproxy/src/utils/qwen-stream-parser.ts`, non-streaming
parse path, only active when the caller sends a non-empty `tools` array.

**Bug:** when the tool parser extracted a tool call successfully and also
returned non-empty lead-in `text`, the code did:
`lastFullContent.slice(...) + text + delta.content` — reappending the *raw*
chunk (which can still contain the `<tool_call>...</tool_call>` tag) right
after the cleaned `text`. Depending on chunk boundaries this could leave
raw tool-call markup, or duplicated lead-in text, inside the content
returned to the client.

**Fix:** replace the raw chunk with the cleaned `text` only (no
re-append of `delta.content`).

**Honesty note:** my own historical Qwen Coder calls throughout this project
never sent a `tools` array (confirmed: `hasTools` in
`routes/chat.ts:108` is derived strictly from the client's request body,
with no model-specific override), so this path could not have caused the
symptom I originally observed. It is a real bug regardless, relevant to
anyone using Qwen Coder as a tool-calling agent.

## Bug #3 (real, found by static audit, fixed): inconsistent incremental-diff fast path

**File:** same, immediately above Bug #2's call site.

**Bug:** the streaming call site
(`routes/stream-handler.ts`) threads `contentLength`/`contentSuffix` into
`getIncrementalDelta()`, keeping it on an O(1) append-detection fast path.
The non-streaming call site in `qwen-stream-parser.ts` called the same
function *without* those two arguments, always defaulting to `0`/`''`. This
forces every non-streaming chunk through a scan limited to a 2000-character
window; if the accumulated response exceeds ~2000 characters and a chunk
doesn't literally re-send a byte-identical prefix, the function falls back
to raw concatenation (`oldStr + newStr`) with no deduplication — a
duplication/corruption risk for long responses.

**Fix:** thread `contentLength`/`contentSuffix` through `StreamParserState`
in the non-streaming path too, matching the streaming call site.

**Honesty note:** empirically, every long non-streaming response tested
(up to 8741 chars) came back correct even *before* this fix — the specific
divergence condition (an accumulated chunk not being a byte-identical
prefix of the next one) never triggered in 5 real long-response calls. This
is a defensive correctness fix for a theoretical edge case, not a proven
cause of any observed failure.

## Regression tests

`proxies/qwenproxy/src/tests/qwen-stream-parser.test.ts` (mirrored in both
repos) — 4 tests, all passing:
- tool-call lead-in text is not duplicated or left with tag residue (Bug #2)
- multiple sequential tool calls don't accumulate tag residue (Bug #2)
- long non-streaming content matches source exactly, no duplication (Bug #3)
- state stays stable across many small, non-round chunk boundaries (Bug #3)

`scripts/test-qwen-coder-contract.ps1` — 4 short deterministic prompts × 3
non-streaming paths (A/B/C), 12 cases, all passing.

`scripts/test-qwen-coder-stream.ps1` — medium audit prompt × 3 repetitions
(path B) + path A + path D (streaming), 5 cases, all passing.

`scripts/test-qwen-coder-stress.ps1` — very long response (path B) + 3
concurrent requests (path B), reproduces and verifies the concurrency fix.

## Acceptance criteria (from the original request) — status

| Criterion | Status |
|---|---|
| 3 short prompts pass | ✅ (4 tested) |
| 1 medium audit prompt passes | ✅ (3x repeated) |
| Final response never marker-only | ✅ in all 21 real API calls made this session |
| UTF-8 preserved | ✅ (Portuguese accented text intact in all fixtures) |
| Streaming and non-streaming preserve response | ✅ |
| Retry doesn't duplicate the call | N/A — hub has no automatic retry for the primary model (only cross-model fallback); not exercised |
| Concurrency default = 1 | ✅ enforced in hub, verified (502→200/200/200) |
| Repeated 3x without truncation | ✅ |
