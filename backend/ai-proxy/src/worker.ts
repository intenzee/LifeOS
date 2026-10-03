// Cloudflare Workers entry: binds Durable Objects, KV and the edge cache to
// the binding-free app in app.ts.

import { DurableObject } from "cloudflare:workers";
import { createApp, Deps } from "./app";
import { APPLE_APP_ATTEST_ROOT } from "./attest";
import { DEFAULT_CONFIG, mergeConfig, ProxyConfig, QuotaKey } from "./config";
import { FoodCache } from "./food";
import {
  Breaker,
  BreakerState,
  Breakers,
  Burst,
  InstallDirectory,
  InstallRecord,
  Ledger,
  LedgerState,
  UsageDecision,
} from "./limits";
import { AnalyticsDataset, AnalyticsMetrics } from "./metrics";

export interface Env {
  ENVIRONMENT: "development" | "production";
  /** Comma-separated `TEAMID.bundle.id` list. */
  APP_IDS: string;
  // Secrets (wrangler secret put …)
  JWT_SECRET: string;
  GROQ_API_KEY?: string;
  DEBUG_TOKEN?: string;
  METRICS_SALT?: string;
  DEVICECHECK_TEAM_ID?: string;
  DEVICECHECK_KEY_ID?: string;
  DEVICECHECK_PRIVATE_KEY?: string;
  USDA_API_KEY?: string;
  // Bindings
  CONFIG: KVNamespace;
  INSTALLS: DurableObjectNamespace<InstallState>;
  BREAKERS: DurableObjectNamespace<ProviderBreaker>;
  METRICS?: AnalyticsDataset;
}

/** One per install: registration, assertion counter, quotas, burst bucket. */
export class InstallState extends DurableObject<Env> {
  private async load(): Promise<LedgerState> {
    return (await this.ctx.storage.get<LedgerState>("state")) ?? {};
  }

  private async mutate<T>(change: (state: LedgerState) => T): Promise<T> {
    const state = await this.load();
    const result = change(state);
    await this.ctx.storage.put("state", state);
    return result;
  }

  async register(record: InstallRecord): Promise<boolean> {
    return this.mutate((s) => Ledger.register(s, record));
  }

  async get(): Promise<InstallRecord | null> {
    return (await this.load()).record ?? null;
  }

  async advanceCounter(counter: number): Promise<boolean> {
    return this.mutate((s) => Ledger.advanceCounter(s, counter));
  }

  async consume(quota: QuotaKey, limit: number, burst: Burst, nowMs: number): Promise<UsageDecision> {
    return this.mutate((s) => Ledger.consume(s, quota, limit, burst, nowMs));
  }
}

/** One per provider: the circuit breaker shared by every isolate. */
export class ProviderBreaker extends DurableObject<Env> {
  async retryAfter(nowMs: number): Promise<number | null> {
    return Breaker.retryAfter((await this.ctx.storage.get<BreakerState>("state")) ?? {}, nowMs);
  }

  async record(status: number, nowMs: number): Promise<void> {
    const state = (await this.ctx.storage.get<BreakerState>("state")) ?? {};
    const next = Breaker.record(state, status, nowMs);
    if (JSON.stringify(next) !== JSON.stringify(state)) await this.ctx.storage.put("state", next);
  }
}

class DurableInstalls implements InstallDirectory {
  constructor(private readonly namespace: DurableObjectNamespace<InstallState>) {}

  install(installId: string) {
    const stub = this.namespace.get(this.namespace.idFromName(installId));
    return {
      register: (record: InstallRecord) => stub.register(record),
      get: () => stub.get(),
      advanceCounter: (counter: number) => stub.advanceCounter(counter),
      consume: (quota: QuotaKey, limit: number, burst: Burst, now: number) => stub.consume(quota, limit, burst, now),
    };
  }
}

/** Open breakers are remembered in the isolate for a few seconds to spare a DO call. */
class DurableBreakers implements Breakers {
  private static openUntil = new Map<string, number>();

  constructor(private readonly namespace: DurableObjectNamespace<ProviderBreaker>) {}

  private stub(provider: string) {
    return this.namespace.get(this.namespace.idFromName(provider));
  }

  async retryAfter(provider: string, nowMs: number) {
    const known = DurableBreakers.openUntil.get(provider);
    if (known !== undefined && nowMs < known) return Math.ceil((known - nowMs) / 1000);
    const wait = await this.stub(provider).retryAfter(nowMs);
    if (wait !== null) DurableBreakers.openUntil.set(provider, nowMs + wait * 1000);
    return wait;
  }

  async record(provider: string, status: number, nowMs: number) {
    // Only throttles and successes change the breaker; skip the call otherwise.
    if (status === 429 || (status >= 200 && status < 300)) await this.stub(provider).record(status, nowMs);
  }
}

/** The Cache API, keyed by synthetic URLs. */
class EdgeFoodCache implements FoodCache {
  private readonly cache = (caches as unknown as { default: Cache }).default;

  private key(key: string) {
    return new Request(`https://food-cache.lifeos.internal/${encodeURIComponent(key)}`);
  }

  async get(key: string) {
    const hit = await this.cache.match(this.key(key));
    return hit ? hit.json() : undefined;
  }

  async put(key: string, value: unknown, ttlSeconds: number) {
    await this.cache.put(this.key(key), new Response(JSON.stringify(value), {
      headers: { "content-type": "application/json", "cache-control": `public, max-age=${ttlSeconds}` },
    }));
  }
}

let cachedConfig: { value: ProxyConfig; at: number } | undefined;
const CONFIG_TTL_MS = 60_000;

async function loadConfig(env: Env): Promise<ProxyConfig> {
  if (cachedConfig && Date.now() - cachedConfig.at < CONFIG_TTL_MS) return cachedConfig.value;
  let override: unknown;
  try {
    override = await env.CONFIG.get("config", "json");
  } catch {
    override = undefined; // a bad override must never take the proxy down
  }
  const value = mergeConfig(DEFAULT_CONFIG, override);
  cachedConfig = { value, at: Date.now() };
  return value;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const deps: Deps = {
      settings: {
        environment: env.ENVIRONMENT,
        appIds: env.APP_IDS.split(",").map((s) => s.trim()).filter(Boolean),
        jwtSecret: env.JWT_SECRET,
        debugToken: env.ENVIRONMENT === "production" ? undefined : env.DEBUG_TOKEN,
        deviceCheck: env.DEVICECHECK_TEAM_ID && env.DEVICECHECK_KEY_ID && env.DEVICECHECK_PRIVATE_KEY
          ? { teamId: env.DEVICECHECK_TEAM_ID, keyId: env.DEVICECHECK_KEY_ID, privateKey: env.DEVICECHECK_PRIVATE_KEY }
          : undefined,
        usdaKey: env.USDA_API_KEY,
        providerKeys: { GROQ_API_KEY: env.GROQ_API_KEY },
        metricsSalt: env.METRICS_SALT ?? "lifeos",
        attestRoots: [APPLE_APP_ATTEST_ROOT],
      },
      installs: new DurableInstalls(env.INSTALLS),
      breakers: new DurableBreakers(env.BREAKERS),
      loadConfig: () => loadConfig(env),
      foodCache: new EdgeFoodCache(),
      fetch: (input, init) => fetch(input, init),
      metrics: new AnalyticsMetrics(env.METRICS, env.ENVIRONMENT),
      now: () => Date.now(),
      sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
    };
    void ctx;
    return createApp(deps)(request);
  },
} satisfies ExportedHandler<Env>;
