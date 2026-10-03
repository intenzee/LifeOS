// Remote config (BE-08) and the router's model lists (BE-04). Defaults live
// here; a JSON override in KV (key "config") is deep-merged on top, so retiring
// a model or flipping a kill switch is a KV edit, not a deploy or an App Store release.

export type RouteKey = "vision.meal" | "parse.meal" | "chat";
export type QuotaKey = "photo" | "parse" | "chat" | "food";

export interface RouteTarget {
  provider: string;
  models: string[];
}

export interface ProxyConfig {
  version: string;
  /** Older apps are asked to update (the app decides how loudly). */
  minimumAppVersion: string;
  flags: Record<string, boolean>;
  /** `true` turns a route off: it answers 503 `disabled` and the app degrades. */
  killSwitches: Record<RouteKey | "food", boolean>;
  /** Per install per UTC day. DeviceCheck installs get `deviceCheckShare` of these. */
  quotas: Record<QuotaKey, number>;
  deviceCheckShare: number;
  /** Per-install burst limit: a token bucket. */
  burst: { capacity: number; refillPerSecond: number };
  routes: Record<RouteKey, RouteTarget[]>;
  policy: {
    /** Never list a provider whose free terms allow training on, or human review of, inputs (doc 07 §5). */
    personalDataAllowedProviders: string[];
    retry: { maxAttempts: number; backoffMs: number[] };
    /** A retired or unknown model: try the next candidate. */
    skipOnStatus: number[];
  };
}

export const ROUTE_QUOTA: Record<RouteKey, QuotaKey> = {
  "vision.meal": "photo",
  "parse.meal": "parse",
  chat: "chat",
};

// Model ids match the app's (`AIRemoteConfig` groq lists, `GroqMealAnalyzer`).
// Verify the live Groq lineup before each deploy; a retired id is skipped automatically.
export const DEFAULT_CONFIG: ProxyConfig = {
  version: "2026.10.1",
  minimumAppVersion: "1.0",
  flags: { proxyEnabled: true },
  killSwitches: { "vision.meal": false, "parse.meal": false, chat: false, food: false },
  quotas: { photo: 25, parse: 100, chat: 60, food: 300 },
  deviceCheckShare: 0.5,
  burst: { capacity: 10, refillPerSecond: 0.5 },
  routes: {
    "vision.meal": [{ provider: "groq", models: ["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"] }],
    "parse.meal": [{ provider: "groq", models: ["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"] }],
    chat: [{ provider: "groq", models: ["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"] }],
  },
  policy: {
    personalDataAllowedProviders: ["groq"],
    retry: { maxAttempts: 2, backoffMs: [600, 1400] },
    skipOnStatus: [400, 404, 422],
  },
};

type Plain = Record<string, unknown>;

function isPlain(value: unknown): value is Plain {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Objects merge key by key; arrays and scalars replace when the type matches.
 *  Unknown keys are ignored, except new boolean `flags`. */
export function mergeConfig(base: ProxyConfig, override: unknown): ProxyConfig {
  return merge(base as unknown as Plain, override, "") as unknown as ProxyConfig;
}

const OPEN_MAPS = new Set(["flags"]);

function merge(base: Plain, override: unknown, path: string): Plain {
  if (!isPlain(override)) return base;
  const out: Plain = { ...base };
  for (const [key, value] of Object.entries(override)) {
    const current = base[key];
    if (current === undefined) {
      if (OPEN_MAPS.has(path) && typeof value === "boolean") out[key] = value;
      continue;
    }
    if (isPlain(current) && isPlain(value)) out[key] = merge(current, value, path ? `${path}.${key}` : key);
    else if (Array.isArray(current) ? Array.isArray(value) : typeof current === typeof value) out[key] = value;
  }
  return out;
}

/** What `GET /config` returns to the app: everything here is safe to show. */
export function publicConfig(config: ProxyConfig): Plain {
  return {
    version: config.version,
    minimumAppVersion: config.minimumAppVersion,
    flags: config.flags,
    killSwitches: config.killSwitches,
    quotas: config.quotas,
    routes: Object.fromEntries(
      Object.entries(config.routes).map(([route, targets]) => [route, targets.map((t) => ({ ...t }))]),
    ),
  };
}
