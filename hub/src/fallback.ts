/**
 * Fallback chain with rate-limit awareness.
 *
 * Each model tracks: failures, last_failure_ts, last_status.
 * When a model returned 429 < 60s ago, it is deprioritized.
 * Chain order: primary → same-tier siblings → cross-tier last resort.
 */
import { CURATED_MODELS, type CuratedModel, modelsByTier } from './curated.js';

interface ModelHealth {
  failures: number;
  last_failure_ts: number;
  last_status: number;
  successes: number;
  last_success_ts: number;
}

const HEALTH = new Map<string, ModelHealth>();
const PENALTY_MS = 60_000; // skip a model for 60s after 429/5xx
const HARD_FAIL_THRESHOLD = 5;

function init(id: string): ModelHealth {
  let h = HEALTH.get(id);
  if (!h) {
    h = { failures: 0, last_failure_ts: 0, last_status: 0, successes: 0, last_success_ts: 0 };
    HEALTH.set(id, h);
  }
  return h;
}

export function recordSuccess(id: string) {
  const h = init(id);
  h.successes++;
  h.last_success_ts = Date.now();
  // Reset partial failure streak after a success
  h.failures = Math.max(0, h.failures - 1);
}

export function recordFailure(id: string, status: number) {
  const h = init(id);
  h.failures++;
  h.last_failure_ts = Date.now();
  h.last_status = status;
}

function isPenalized(id: string): boolean {
  const h = HEALTH.get(id);
  if (!h) return false;
  if (h.failures >= HARD_FAIL_THRESHOLD) {
    // Reset failure window after some time has passed
    if (Date.now() - h.last_failure_ts > PENALTY_MS * 5) {
      h.failures = 0;
      return false;
    }
    return true;
  }
  if ([429, 502, 503, 504].includes(h.last_status)) {
    return Date.now() - h.last_failure_ts < PENALTY_MS;
  }
  return false;
}

/**
 * Build fallback chain for a primary model.
 * Order:
 *   1. primary (if not penalized)
 *   2. same-tier alternates (round-robin avoiding penalized)
 *   3. cross-tier (premium → fast → reasoning → coding → local)
 *   4. penalized last resort (better than total failure)
 */
export function rotateFallback(primary: CuratedModel, _requestedId: string): CuratedModel[] {
  const chain: CuratedModel[] = [];
  const seen = new Set<string>();

  const push = (m: CuratedModel) => {
    if (!seen.has(m.id)) {
      chain.push(m);
      seen.add(m.id);
    }
  };

  // 1. Primary (if not penalized)
  if (!isPenalized(primary.id)) push(primary);

  // 2. Same-tier alternates (non-penalized first)
  const sameTier = modelsByTier(primary.tier).filter(m => m.id !== primary.id);
  for (const m of sameTier) if (!isPenalized(m.id)) push(m);

  // 3. Cross-tier broad fallback (premium → fast → reasoning → coding)
  const tierOrder: Array<typeof primary.tier> = ['premium', 'fast', 'reasoning', 'coding'];
  for (const t of tierOrder) {
    if (t === primary.tier) continue;
    for (const m of modelsByTier(t)) if (!isPenalized(m.id)) push(m);
  }

  // 4. Penalized as last resort
  if (!seen.has(primary.id)) push(primary);
  for (const m of CURATED_MODELS) push(m);

  return chain;
}

export function getHealthSnapshot(): Record<string, ModelHealth> {
  const out: Record<string, ModelHealth> = {};
  HEALTH.forEach((v, k) => { out[k] = { ...v }; });
  return out;
}
