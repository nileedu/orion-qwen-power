/**
 * Orion Proxy Hub — Universal AI Gateway
 *
 * OpenAI-compatible aggregator with intelligent routing,
 * automatic fallback chain, and session-preserving model switching.
 *
 * Licença: MIT
 */
import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import crypto from 'node:crypto';
import * as dotenv from 'dotenv';
import { CURATED_MODELS, DEFAULT_MODEL, getModelById, type CuratedModel } from './curated.js';
import { rotateFallback, recordFailure, recordSuccess, getHealthSnapshot } from './fallback.js';
import { sessionStore } from './session.js';

dotenv.config();

const app = new Hono();

const HUB_API_KEY = process.env.HUB_API_KEY || 'orion-proxy-key';
const PORT = parseInt(process.env.PORT || '3800');
const HOST = process.env.HOST || '127.0.0.1';
const CORS_ORIGINS = (process.env.CORS_ORIGINS || 'http://localhost,http://127.0.0.1,vscode-webview://')
  .split(',')
  .map((x) => x.trim())
  .filter(Boolean);
const MODEL_CACHE_TTL_MS = parseInt(process.env.MODEL_CACHE_TTL_MS || '60000');
const MAX_PAYLOAD_BYTES = parseInt(process.env.MAX_PAYLOAD_BYTES || String(10 * 1024 * 1024));

app.use('*', cors({
  origin: (origin) => {
    if (!origin) return null;
    if (CORS_ORIGINS.some((allowed) => origin === allowed || origin.startsWith(allowed))) return origin;
    return null;
  },
}));

const BACKENDS: Record<'qwen', { url: string; key: string }> = {
  qwen: { url: process.env.QWENPROXY_URL || 'http://localhost:3802', key: process.env.QWENPROXY_KEY || 'orion-proxy-key' },
};

const EXPOSED_MODEL_IDS = new Set<string>([
  'qwen/3.7-plus',
  'qwen/3.7-plus-no-thinking',
  'qwen/3.7-max',
  'qwen/3.7-max-no-thinking',
  'qwen/3.6-plus',
  'qwen/coder-plus',
]);

const metricsState = {
  startedAt: Date.now(),
  requestsTotal: 0,
  requestsErrors: 0,
  upstreamFailures: 0,
  chatCompletions: 0,
  anthropicMessages: 0,
  fallbackUsed: 0,
  modelRequests: new Map<string, number>(),
  backendRequests: new Map<string, number>(),
};

let qwenModelCache: { at: number; models: CuratedModel[] } = { at: 0, models: [] };

function withTimeout<T>(promise: Promise<T>, ms: number, label: string): Promise<T> {
  let timeout: NodeJS.Timeout;
  const timer = new Promise<T>((_, reject) => {
    timeout = setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timer]).finally(() => clearTimeout(timeout));
}

function increment(map: Map<string, number>, key: string) {
  map.set(key, (map.get(key) || 0) + 1);
}

function normalizeQwenPublicId(id: string): string {
  if (id.startsWith('qwen/')) return id;
  if (id === 'qwen3-coder-plus') return 'qwen/coder-plus';
  if (id.startsWith('qwen3.')) return `qwen/${id.slice('qwen'.length)}`;
  if (id.startsWith('qwen-')) return `qwen/${id.slice('qwen-'.length)}`;
  return `qwen/${id.replace(/^qwen\/?/, '')}`;
}

function normalizeQwenBackendId(id: string): string {
  if (!id.startsWith('qwen/')) return id;
  const suffix = id.slice('qwen/'.length);
  if (suffix === 'coder-plus') return 'qwen3-coder-plus';
  if (/^\d/.test(suffix)) return `qwen${suffix}`;
  return `qwen-${suffix}`;
}

function tierForQwenModel(id: string): CuratedModel['tier'] {
  if (id.includes('max')) return 'premium';
  if (id.includes('coder')) return 'coding';
  if (id.includes('omni') || id.includes('vl')) return 'multimodal';
  if (id.includes('flash') || id.includes('no-thinking')) return 'fast';
  return 'coding';
}

function timeoutForPayload(bytes: number, model = ''): number {
  const base = model.includes('max') || model.includes('reason') ? 180_000 : 120_000;
  const perMb = Math.ceil(bytes / (1024 * 1024)) * 30_000;
  return Math.min(Math.max(base + perMb, 60_000), 600_000);
}

async function readJsonWithLimit(c: any): Promise<{ body: any; bytes: number } | Response> {
  const text = await c.req.text();
  const bytes = Buffer.byteLength(text, 'utf8');
  if (bytes > MAX_PAYLOAD_BYTES) {
    return c.json({
      error: {
        message: `payload too large: ${bytes} bytes exceeds ${MAX_PAYLOAD_BYTES}`,
        type: 'payload_too_large',
      },
    }, 413);
  }
  try {
    return { body: text ? JSON.parse(text) : {}, bytes };
  } catch {
    return c.json({ error: { message: 'invalid JSON body', type: 'invalid_request_error' } }, 400);
  }
}

async function getDynamicQwenModels(): Promise<CuratedModel[]> {
  const now = Date.now();
  if (qwenModelCache.models.length && now - qwenModelCache.at < MODEL_CACHE_TTL_MS) {
    return qwenModelCache.models;
  }

  const backend = BACKENDS.qwen;
  try {
    const r = await withTimeout(fetch(`${backend.url}/v1/models`, {
      headers: { Authorization: `Bearer ${backend.key}` },
      signal: AbortSignal.timeout(1500),
    }), 1800, 'qwen model discovery');
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const data: any = await r.json();
    const seen = new Set<string>();
    const models: CuratedModel[] = [];
    for (const item of data?.data ?? []) {
      const backendId = String(item?.id ?? '');
      if (!backendId || !backendId.startsWith('qwen')) continue;
      const publicId = normalizeQwenPublicId(backendId);
      if (seen.has(publicId)) continue;
      seen.add(publicId);
      models.push({
        id: publicId,
        provider: 'qwen',
        backend_model: backendId,
        tier: tierForQwenModel(publicId),
        speed: publicId.includes('no-thinking') || publicId.includes('flash') ? 'fast' : 'medium',
        description: `Qwen dynamic model (${backendId})`,
        best_for: publicId.includes('coder') ? ['code', 'refactor', 'debug'] : ['chat', 'code', 'analysis'],
      });
    }
    if (models.length) {
      qwenModelCache = { at: now, models };
      return models;
    }
  } catch {
    // Fall back to curated local list when qwenproxy is offline.
  }

  const fallback = CURATED_MODELS.filter((m) => m.provider === 'qwen');
  qwenModelCache = { at: now, models: fallback };
  return fallback;
}

async function getExposedModels(): Promise<CuratedModel[]> {
  const qwenModels = await getDynamicQwenModels();
  const qwenIds = new Set(qwenModels.map((m) => m.id));
  const curatedQwenMissing = CURATED_MODELS.filter((m) => m.provider === 'qwen' && EXPOSED_MODEL_IDS.has(m.id) && !qwenIds.has(m.id));
  return [...qwenModels, ...curatedQwenMissing];
}

function resolveModel(requestedModel: string): CuratedModel {
  const normalized = requestedModel ? normalizeQwenPublicId(requestedModel) : DEFAULT_MODEL;
  const curated = getModelById(normalized);
  if (curated) return curated;
  return {
    id: normalized,
    provider: 'qwen',
    backend_model: normalizeQwenBackendId(normalized),
    tier: tierForQwenModel(normalized),
  };
}

app.use('/v1/*', async (c, next) => {
  metricsState.requestsTotal++;
  const auth = c.req.header('Authorization') || '';
  const token = (
    auth.replace(/^Bearer\s+/i, '').trim() ||
    c.req.header('x-api-key') ||
    c.req.header('anthropic-api-key') ||
    c.req.header('api-key') ||
    ''
  ).trim().replace(/^['"]|['"]$/g, '');
  if (token !== HUB_API_KEY) {
    metricsState.requestsErrors++;
    return c.json({ error: { message: 'unauthorized', type: 'authentication_error' } }, 401);
  }
  await next();
});

app.get('/health', async (c) => {
  const health: Record<string, boolean> = {};
  await Promise.all(Object.entries(BACKENDS).map(async ([name, b]) => {
    try {
      const r = await fetch(`${b.url}/health`, {
        headers: { Authorization: `Bearer ${b.key}` },
        signal: AbortSignal.timeout(3000),
      });
      health[name] = r.ok;
    } catch { health[name] = false; }
  }));
  return c.json({ status: 'ok', backends: health, working_models: CURATED_MODELS.length });
});

app.get('/v1/models', async (c) => {
  const models = await getExposedModels();
  return c.json({
    object: 'list',
    data: models.map(m => ({
      id: m.id,
      object: 'model',
      created: 1720000000,
      owned_by: m.provider,
    })),
  });
});

app.get('/v1/health/models', (c) => c.json(getHealthSnapshot()));

app.get('/metrics', (c) => {
  const auth = c.req.header('Authorization') || '';
  const token = auth.replace(/^Bearer\s+/i, '').trim();
  const remote = c.req.header('x-forwarded-for') || c.req.header('x-real-ip') || '';
  if (token && token !== HUB_API_KEY) {
    return c.text('unauthorized\n', 401);
  }
  if (!token && remote && !remote.startsWith('127.') && remote !== '::1') {
    return c.text('metrics are local-only unless Authorization is provided\n', 403);
  }
  const lines: string[] = [];
  const uptime = Math.floor((Date.now() - metricsState.startedAt) / 1000);
  lines.push('# HELP orion_hub_uptime_seconds Hub uptime in seconds');
  lines.push('# TYPE orion_hub_uptime_seconds gauge');
  lines.push(`orion_hub_uptime_seconds ${uptime}`);
  lines.push('# HELP orion_hub_requests_total Total authenticated /v1 requests');
  lines.push('# TYPE orion_hub_requests_total counter');
  lines.push(`orion_hub_requests_total ${metricsState.requestsTotal}`);
  lines.push('# HELP orion_hub_errors_total Total hub errors');
  lines.push('# TYPE orion_hub_errors_total counter');
  lines.push(`orion_hub_errors_total ${metricsState.requestsErrors}`);
  lines.push('# HELP orion_hub_upstream_failures_total Total upstream failures');
  lines.push('# TYPE orion_hub_upstream_failures_total counter');
  lines.push(`orion_hub_upstream_failures_total ${metricsState.upstreamFailures}`);
  lines.push('# HELP orion_hub_fallback_used_total Total fallback responses');
  lines.push('# TYPE orion_hub_fallback_used_total counter');
  lines.push(`orion_hub_fallback_used_total ${metricsState.fallbackUsed}`);
  for (const [model, count] of metricsState.modelRequests) {
    lines.push(`orion_hub_model_requests_total{model="${model.replace(/"/g, '\\"')}"} ${count}`);
  }
  for (const [backend, count] of metricsState.backendRequests) {
    lines.push(`orion_hub_backend_requests_total{backend="${backend.replace(/"/g, '\\"')}"} ${count}`);
  }
  return c.text(`${lines.join('\n')}\n`, {
    headers: { 'Content-Type': 'text/plain; version=0.0.4' },
  });
});

function anthropicContentToText(content: any): string {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return JSON.stringify(content ?? '');

  const parts: string[] = [];
  for (const block of content) {
    if (block?.type === 'text') parts.push(block.text ?? '');
    else if (block?.type === 'tool_result') {
      const result = typeof block.content === 'string' ? block.content : JSON.stringify(block.content ?? '');
      parts.push(`Tool result (${block.tool_use_id ?? 'tool'}): ${result}`);
    } else if (block?.type === 'tool_use') {
      parts.push(`<tool_call>\n${JSON.stringify({ name: block.name, arguments: block.input ?? {} })}\n</tool_call>`);
    } else {
      parts.push(JSON.stringify(block ?? ''));
    }
  }
  return parts.filter(Boolean).join('\n');
}

function anthropicMessagesToOpenAI(messages: any[] = [], system: any): any[] {
  const out: any[] = [];
  if (system) out.push({ role: 'system', content: anthropicContentToText(system) });
  for (const message of messages) {
    out.push({
      role: message.role === 'assistant' ? 'assistant' : 'user',
      content: anthropicContentToText(message.content),
    });
  }
  return out;
}

function anthropicToolsToOpenAI(tools: any[] | undefined): any[] | undefined {
  if (!Array.isArray(tools) || tools.length === 0) return undefined;
  return tools.map((tool) => ({
    type: 'function',
    function: {
      name: tool.name,
      description: tool.description ?? '',
      parameters: tool.input_schema ?? { type: 'object', properties: {} },
    },
  }));
}

function openAIMessageToAnthropicContent(message: any): any[] {
  const blocks: any[] = [];
  if (message?.content) {
    blocks.push({ type: 'text', text: String(message.content) });
  }
  if (Array.isArray(message?.tool_calls)) {
    for (const call of message.tool_calls) {
      let input: any = {};
      const rawArgs = call?.function?.arguments;
      if (typeof rawArgs === 'string') {
        try { input = JSON.parse(rawArgs); } catch { input = { raw: rawArgs }; }
      } else if (rawArgs && typeof rawArgs === 'object') {
        input = rawArgs;
      }
      blocks.push({
        type: 'tool_use',
        id: call.id ?? `toolu_${crypto.randomUUID?.() ?? Math.random().toString(36).slice(2)}`,
        name: call?.function?.name ?? 'tool',
        input,
      });
    }
  }
  return blocks.length > 0 ? blocks : [{ type: 'text', text: '' }];
}

function toAnthropicResponse(openai: any, model: string): any {
  const message = openai?.choices?.[0]?.message ?? {};
  const content = openAIMessageToAnthropicContent(message);
  return {
    id: openai?.id ?? `msg_${Date.now()}`,
    type: 'message',
    role: 'assistant',
    model: openai?.model ?? model,
    content,
    stop_reason: content.some((b: any) => b.type === 'tool_use') ? 'tool_use' : 'end_turn',
    stop_sequence: null,
    usage: {
      input_tokens: openai?.usage?.prompt_tokens ?? 0,
      output_tokens: openai?.usage?.completion_tokens ?? 0,
    },
  };
}

function sseEvent(event: string, data: any): string {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

function anthropicStreamResponse(message: any): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(sseEvent('message_start', { type: 'message_start', message: { ...message, content: [] } })));
      message.content.forEach((block: any, index: number) => {
        controller.enqueue(encoder.encode(sseEvent('content_block_start', { type: 'content_block_start', index, content_block: block.type === 'tool_use' ? { type: 'tool_use', id: block.id, name: block.name, input: {} } : { type: 'text', text: '' } })));
        if (block.type === 'tool_use') {
          controller.enqueue(encoder.encode(sseEvent('content_block_delta', { type: 'content_block_delta', index, delta: { type: 'input_json_delta', partial_json: JSON.stringify(block.input ?? {}) } })));
        } else {
          controller.enqueue(encoder.encode(sseEvent('content_block_delta', { type: 'content_block_delta', index, delta: { type: 'text_delta', text: block.text ?? '' } })));
        }
        controller.enqueue(encoder.encode(sseEvent('content_block_stop', { type: 'content_block_stop', index })));
      });
      controller.enqueue(encoder.encode(sseEvent('message_delta', { type: 'message_delta', delta: { stop_reason: message.stop_reason, stop_sequence: null }, usage: { output_tokens: message.usage.output_tokens } })));
      controller.enqueue(encoder.encode(sseEvent('message_stop', { type: 'message_stop' })));
      controller.close();
    },
  });
  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
}

app.post('/v1/messages', async (c) => {
  metricsState.anthropicMessages++;
  const parsed = await readJsonWithLimit(c);
  if (parsed instanceof Response) return parsed;
  const { body, bytes } = parsed;
  const model = body.model || process.env.ANTHROPIC_MODEL || DEFAULT_MODEL;
  const payload: any = {
    model,
    messages: anthropicMessagesToOpenAI(body.messages, body.system),
    max_tokens: body.max_tokens,
    temperature: body.temperature,
    stream: false,
  };
  const tools = anthropicToolsToOpenAI(body.tools);
  if (tools) payload.tools = tools;

  const upstream = await fetch(`http://localhost:${PORT}/v1/chat/completions`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${HUB_API_KEY}` },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(timeoutForPayload(bytes, model)),
  });

  const text = await upstream.text();
  if (!upstream.ok) {
    return new Response(text, {
      status: upstream.status,
      headers: { 'Content-Type': upstream.headers.get('Content-Type') || 'application/json' },
    });
  }

  const openai = JSON.parse(text);
  const anthropic = toAnthropicResponse(openai, model);
  if (body.stream) return anthropicStreamResponse(anthropic);
  return c.json(anthropic);
});

app.post('/v1/messages/count_tokens', async (c) => {
  const parsed = await readJsonWithLimit(c);
  if (parsed instanceof Response) return parsed;
  const { body } = parsed;
  const text = anthropicMessagesToOpenAI(body.messages, body.system).map((m) => m.content).join('\n');
  return c.json({ input_tokens: Math.max(1, Math.ceil(text.length / 4)) });
});

app.post('/v1/chat/completions', async (c) => {
  metricsState.chatCompletions++;
  const parsedBody = await readJsonWithLimit(c);
  if (parsedBody instanceof Response) return parsedBody;
  const { body, bytes } = parsedBody;
  const requestedModel: string = body.model || '';
  const sessionId: string | undefined = c.req.header('X-Session-Id') || body?.session_id;

  let primary = resolveModel(requestedModel);
  increment(metricsState.modelRequests, primary.id);

  const chain = rotateFallback(primary, requestedModel);

  if (sessionId && Array.isArray(body.messages)) {
    const session = sessionStore.get(sessionId);
    if (session && session.messages.length > 0) {
      const existingFirst = body.messages[0]?.content;
      const stored = session.messages;
      const hasOverlap = stored.length > 0 && stored[stored.length - 1]?.content === existingFirst;
      if (!hasOverlap) {
        body.messages = [...stored, ...body.messages];
      }
    }
  }

  // Backends que são wrappers browser-stateless: cada chat é DM novo no site,
  // não respeitam multi-turn API. Pra esses, concatenamos history em prompt único.
  const STATELESS_BACKENDS = new Set(['qwen']);

  let lastError: any = null;
  for (const candidate of chain) {
    const backend = BACKENDS[candidate.provider];
    if (!backend) continue;
    increment(metricsState.backendRequests, candidate.provider);
    let outboundMessages = body.messages;
    if (STATELESS_BACKENDS.has(candidate.provider) && Array.isArray(body.messages) && body.messages.length > 1) {
      // Concat: histórico vira "Conversa anterior:\n<role>: <content>\n..." + pergunta atual
      const last = body.messages[body.messages.length - 1];
      const earlier = body.messages.slice(0, -1);
      const ctx = earlier
        .map((m: any) => {
          const r = m.role === 'user' ? 'Você' : m.role === 'assistant' ? 'Eu' : (m.role || 'system');
          const c = typeof m.content === 'string' ? m.content : JSON.stringify(m.content);
          return `${r}: ${c}`;
        })
        .join('\n');
      const merged = ctx
        ? `Contexto da conversa anterior:\n${ctx}\n\nPergunta atual: ${typeof last.content === 'string' ? last.content : JSON.stringify(last.content)}`
        : (typeof last.content === 'string' ? last.content : JSON.stringify(last.content));
      outboundMessages = [{ role: 'user', content: merged }];
    }
    const payload = { ...body, model: candidate.backend_model, messages: outboundMessages };
    delete (payload as any).session_id;

    try {
      const upstream = await fetch(`${backend.url}/v1/chat/completions`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${backend.key}` },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(timeoutForPayload(bytes, candidate.id)),
      });

      if (upstream.ok) {
        recordSuccess(candidate.id);
        if (candidate.id !== requestedModel) metricsState.fallbackUsed++;
        const text = await upstream.text();
        const parsed = (() => { try { return JSON.parse(text); } catch { return null; } })();
        if (sessionId && parsed?.choices?.[0]?.message) {
          sessionStore.append(sessionId, body.messages, parsed.choices[0].message, candidate.id);
        }
        return new Response(text, {
          status: 200,
          headers: {
            'Content-Type': upstream.headers.get('Content-Type') || 'application/json',
            'X-Resolved-Model': candidate.id,
            'X-Fallback-Used': candidate.id === requestedModel ? 'no' : 'yes',
          },
        });
      }

      recordFailure(candidate.id, upstream.status);
      metricsState.upstreamFailures++;
      lastError = { status: upstream.status, model: candidate.id };
      if (upstream.status >= 400 && upstream.status < 500 && upstream.status !== 429) {
        if (candidate.id === requestedModel) {
          const errBody = await upstream.text().catch(() => '');
          return new Response(errBody || JSON.stringify({ error: lastError }), {
            status: upstream.status,
            headers: { 'Content-Type': 'application/json' },
          });
        }
      }
    } catch (e: any) {
      recordFailure(candidate.id, 0);
      metricsState.upstreamFailures++;
      lastError = { message: String(e?.message || e), model: candidate.id };
    }
  }

  return c.json({
    error: {
      message: 'all fallback models failed',
      type: 'upstream_unavailable',
      tried: chain.map(c => c.id),
      last: lastError,
    },
  }, 502);
});

app.post('/v1/chat/completions/stop', async (c) => {
  const parsedBody = await readJsonWithLimit(c);
  if (parsedBody instanceof Response) return parsedBody;
  const { body } = parsedBody;
  const requestedModel = body.model || DEFAULT_MODEL;
  const model = resolveModel(requestedModel);
  const backend = BACKENDS[model.provider];
  if (!backend) return c.json({ error: { message: `No backend for provider: ${model.provider}` } }, 400);

  const upstream = await fetch(`${backend.url}/v1/chat/completions/stop`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${backend.key}` },
    body: JSON.stringify({ ...body, model: model.backend_model }),
    signal: AbortSignal.timeout(30_000),
  });
  const text = await upstream.text();
  return new Response(text || JSON.stringify({ ok: upstream.ok }), {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') || 'application/json' },
  });
});

app.post('/v1/upload', async (c) => {
  const backend = BACKENDS.qwen;
  const uploadBody = await c.req.arrayBuffer();
  if (uploadBody.byteLength > MAX_PAYLOAD_BYTES) {
    return c.json({
      error: {
        message: `upload too large: ${uploadBody.byteLength} bytes exceeds ${MAX_PAYLOAD_BYTES}`,
        type: 'payload_too_large',
      },
    }, 413);
  }
  const upstream = await fetch(`${backend.url}/v1/upload`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${backend.key}`,
      'Content-Type': c.req.header('Content-Type') || 'application/octet-stream',
    },
    body: uploadBody,
    signal: AbortSignal.timeout(300_000),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { 'Content-Type': upstream.headers.get('Content-Type') || 'application/json' },
  });
});

app.get('/v1/sessions/:id', (c) => {
  const id = c.req.param('id');
  const s = sessionStore.get(id);
  if (!s) return c.json({ error: 'session not found' }, 404);
  return c.json({ id, ...s });
});

app.delete('/v1/sessions/:id', (c) => {
  sessionStore.delete(c.req.param('id'));
  return c.json({ ok: true });
});

console.log(`Orion Proxy Hub — listening on :${PORT}`);
console.log(`  Curated working models: ${CURATED_MODELS.length}`);
console.log(`  Backends: ${Object.keys(BACKENDS).join(', ')}`);
serve({ fetch: app.fetch, port: PORT, hostname: HOST });
