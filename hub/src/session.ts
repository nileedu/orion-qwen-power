/**
 * Session-preserving memory across model switches.
 *
 * Client sends "X-Session-Id: <uuid>" or body.session_id.
 * Hub stores conversation messages so that if a fallback kicks in,
 * the new model sees the full history — context preserved.
 *
 * In-memory store with TTL. For production replace with SQLite/Redis.
 */

interface SessionData {
  messages: Array<{ role: string; content: string }>;
  model_history: string[];           // models that handled turns
  created_at: number;
  updated_at: number;
}

const TTL_MS = 30 * 60_000; // 30 min
const MAX_MESSAGES = 60;     // cap to avoid context overflow

class SessionStore {
  private store = new Map<string, SessionData>();

  get(id: string): SessionData | null {
    const s = this.store.get(id);
    if (!s) return null;
    if (Date.now() - s.updated_at > TTL_MS) {
      this.store.delete(id);
      return null;
    }
    return s;
  }

  append(id: string, requestMessages: any[], assistantMessage: any, modelUsed: string) {
    let s = this.store.get(id);
    if (!s) {
      s = { messages: [], model_history: [], created_at: Date.now(), updated_at: 0 };
      this.store.set(id, s);
    }

    // Merge: dedup messages we've already saved (compare last few)
    const tail = s.messages.slice(-3);
    const tailHash = tail.map(m => `${m.role}:${m.content?.slice(0,40)}`).join('|');

    for (const m of requestMessages) {
      const sig = `${m.role}:${(m.content || '').slice(0,40)}`;
      if (tailHash.includes(sig)) continue;
      s.messages.push({ role: m.role, content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content) });
    }
    if (assistantMessage) {
      s.messages.push({ role: 'assistant', content: typeof assistantMessage.content === 'string' ? assistantMessage.content : JSON.stringify(assistantMessage.content) });
    }

    // Cap messages from the start (keep recent)
    if (s.messages.length > MAX_MESSAGES) {
      s.messages = s.messages.slice(-MAX_MESSAGES);
    }

    s.model_history.push(modelUsed);
    if (s.model_history.length > 20) s.model_history = s.model_history.slice(-20);
    s.updated_at = Date.now();
  }

  delete(id: string) {
    this.store.delete(id);
  }

  // periodic cleanup (called every 5 min)
  sweep() {
    const now = Date.now();
    for (const [id, s] of this.store.entries()) {
      if (now - s.updated_at > TTL_MS) this.store.delete(id);
    }
  }
}

export const sessionStore = new SessionStore();
setInterval(() => sessionStore.sweep(), 5 * 60_000).unref?.();
