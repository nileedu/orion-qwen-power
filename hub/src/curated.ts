export type Tier = 'premium' | 'coding' | 'reasoning' | 'fast' | 'multimodal' | 'unknown';
export type Provider = 'qwen';

export interface CuratedModel {
  id: string;
  provider: Provider;
  backend_model: string;
  tier: Tier;
  description?: string;
  best_for?: string[];
  speed?: 'instant' | 'fast' | 'medium' | 'slow';
}

export const DEFAULT_MODEL = 'qwen/3.7-max';

export const CURATED_MODELS: CuratedModel[] = [
  {
    id: 'qwen/3.7-max',
    provider: 'qwen',
    backend_model: 'qwen3.7-max',
    tier: 'premium',
    speed: 'slow',
    description: 'Qwen 3.7 Max - highest-quality default model for hard coding, planning, writing, and agentic work.',
    best_for: ['agent', 'code', 'architecture', 'research', 'writing', 'analysis'],
  },
  {
    id: 'qwen/3.7-max-no-thinking',
    provider: 'qwen',
    backend_model: 'qwen3.7-max-no-thinking',
    tier: 'premium',
    speed: 'medium',
    description: 'Qwen 3.7 Max without thinking mode - premium direct answers with lower latency.',
    best_for: ['code', 'analysis', 'writing', 'quick-agent'],
  },
  {
    id: 'qwen/3.7-plus',
    provider: 'qwen',
    backend_model: 'qwen3.7-plus',
    tier: 'coding',
    speed: 'medium',
    description: 'Qwen 3.7 Plus - balanced current Qwen model for code, chat, Portuguese, and daily agent tasks.',
    best_for: ['code', 'chat', 'translation', 'long-context', 'analysis'],
  },
  {
    id: 'qwen/3.7-plus-no-thinking',
    provider: 'qwen',
    backend_model: 'qwen3.7-plus-no-thinking',
    tier: 'fast',
    speed: 'fast',
    description: 'Qwen 3.7 Plus without thinking mode - faster direct responses.',
    best_for: ['quick-qa', 'summarize', 'chat', 'light-code'],
  },
  {
    id: 'qwen/3.6-plus',
    provider: 'qwen',
    backend_model: 'qwen3.6-plus',
    tier: 'coding',
    speed: 'medium',
    description: 'Qwen 3.6 Plus - stable coding and chat fallback.',
    best_for: ['code', 'chat', 'translation'],
  },
  {
    id: 'qwen/coder-plus',
    provider: 'qwen',
    backend_model: 'qwen3-coder-plus',
    tier: 'coding',
    speed: 'medium',
    description: 'Qwen Coder Plus - coding-focused Qwen model.',
    best_for: ['code', 'refactor', 'debug', 'architecture'],
  },
  {
    id: 'qwen/3.6-max-preview',
    provider: 'qwen',
    backend_model: 'qwen3.6-max-preview',
    tier: 'premium',
    speed: 'slow',
    description: 'Qwen 3.6 Max Preview - high-quality fallback when available.',
    best_for: ['hardest-tasks', 'long-form-writing', 'research'],
  },
  {
    id: 'qwen/3.6-27b',
    provider: 'qwen',
    backend_model: 'qwen3.6-27b',
    tier: 'fast',
    speed: 'fast',
    description: 'Qwen 3.6 27B - efficient mid-size model.',
    best_for: ['code', 'chat'],
  },
  {
    id: 'qwen/3.6-35b-a3b',
    provider: 'qwen',
    backend_model: 'qwen3.6-35b-a3b',
    tier: 'fast',
    speed: 'fast',
    description: 'Qwen 3.6 35B A3B - fast MoE variant.',
    best_for: ['code', 'chat', 'analysis'],
  },
  {
    id: 'qwen/3.5-plus',
    provider: 'qwen',
    backend_model: 'qwen3.5-plus',
    tier: 'coding',
    speed: 'medium',
    description: 'Qwen 3.5 Plus - stable previous-generation fallback.',
    best_for: ['code', 'chat'],
  },
  {
    id: 'qwen/3.5-omni-plus',
    provider: 'qwen',
    backend_model: 'qwen3.5-omni-plus',
    tier: 'multimodal',
    speed: 'medium',
    description: 'Qwen 3.5 Omni Plus - multimodal model when the web account exposes it.',
    best_for: ['vision', 'audio', 'multimodal-analysis'],
  },
  {
    id: 'qwen/3.5-flash',
    provider: 'qwen',
    backend_model: 'qwen3.5-flash',
    tier: 'fast',
    speed: 'instant',
    description: 'Qwen 3.5 Flash - low-latency fallback for short tasks.',
    best_for: ['quick-qa', 'classify', 'short-summary'],
  },
];

export function getProvider(modelId: string): Provider | null {
  const m = CURATED_MODELS.find((x) => x.id === modelId);
  return m?.provider ?? null;
}

export function getModelById(modelId: string): CuratedModel | null {
  return CURATED_MODELS.find((x) => x.id === modelId) ?? null;
}

export function modelsByTier(tier: Tier): CuratedModel[] {
  return CURATED_MODELS.filter((m) => m.tier === tier);
}

export function modelsForUseCase(useCase: string): CuratedModel[] {
  return CURATED_MODELS.filter((m) => m.best_for?.includes(useCase));
}
