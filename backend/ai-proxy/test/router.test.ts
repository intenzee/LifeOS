import { describe, expect, it } from "vitest";
import { DEFAULT_CONFIG, mergeConfig, ProxyConfig, publicConfig } from "../src/config";
import { barcode, MemoryFoodCache, normaliseOFF, normaliseUSDA, search } from "../src/food";
import { Breaker, Ledger, LedgerState, MemoryBreakers } from "../src/limits";
import { RequestError, route, sanitise } from "../src/router";
import { completion } from "./helpers";

function deps(responses: (Response | Error)[], config: ProxyConfig = structuredClone(DEFAULT_CONFIG)) {
  const clock = { now: 0 };
  const models: string[] = [];
  const sleeps: number[] = [];
  const breakers = new MemoryBreakers();
  return {
    clock, models, sleeps, breakers,
    deps: {
      config,
      keys: { GROQ_API_KEY: "k" } as Record<string, string | undefined>,
      breakers,
      fetch: (async (_url: unknown, init?: RequestInit) => {
        models.push(JSON.parse(String(init?.body)).model);
        const next = responses.shift();
        if (!next) throw new Error("no more responses");
        if (next instanceof Error) throw next;
        return next;
      }) as typeof fetch,
      sleep: async (ms: number) => {
        sleeps.push(ms);
        clock.now += ms;
      },
      now: () => clock.now,
    },
  };
}

const parse = sanitise({ messages: [{ role: "user", content: "dal" }], response_format: { type: "json_object" } },
  "parse.meal");
const status = (code: number) => new Response("{}", { status: code });

describe("provider router", () => {
  it("skips a retired model and answers from the next one", async () => {
    const t = deps([status(404), completion('{"items":[]}')]);
    const result = await route("parse.meal", parse, t.deps);
    expect(t.models).toEqual(["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"]);
    expect(result.model).toBe("qwen/qwen3.8-27b");
  });

  it("moves on when a model answers in prose or without ParsedMeal's items", async () => {
    const t = deps([completion("Sure! Here are your foods."), completion('{"foods":[]}')]);
    await expect(route("parse.meal", parse, t.deps)).rejects.toMatchObject({ status: 502, reason: "no_model_available" });
    expect(t.models).toHaveLength(2);
  });

  it("retries throttling and server errors with the configured backoff", async () => {
    const t = deps([status(429), completion('{"items":[]}')]);
    expect((await route("parse.meal", parse, t.deps)).attempts).toBe(2);
    expect(t.sleeps).toEqual([600]);
    const network = deps([new Error("offline"), status(500), status(503), completion('{"items":[]}')]);
    expect((await route("parse.meal", parse, network.deps)).model).toBe("qwen/qwen3.8-27b");
    expect(network.sleeps).toEqual([600, 600]);
  });

  it("opens the breaker after 30 s of 429s and then refuses fast", async () => {
    const config = structuredClone(DEFAULT_CONFIG);
    config.policy.retry = { maxAttempts: 2, backoffMs: [20_000] };
    const t = deps(Array.from({ length: 4 }, () => status(429)), config);
    await expect(route("parse.meal", parse, t.deps)).rejects.toMatchObject({ status: 503, reason: "provider_busy" });
    expect(t.clock.now).toBe(40_000);
    expect(await t.breakers.retryAfter("groq", t.clock.now)).toBe(60);
    const calls = t.models.length;
    await expect(route("parse.meal", parse, t.deps)).rejects.toMatchObject({ status: 503, reason: "provider_busy" });
    expect(t.models.length).toBe(calls); // no provider call while open
  });

  it("treats an auth failure as ours, not retryable", async () => {
    const t = deps([status(401)]);
    await expect(route("parse.meal", parse, t.deps)).rejects.toMatchObject({ status: 502, reason: "provider_error" });
    expect(t.models).toHaveLength(1);
  });

  it("never sends personal data to a provider outside the allow-list, or without a key", async () => {
    const config = structuredClone(DEFAULT_CONFIG);
    config.policy.personalDataAllowedProviders = [];
    await expect(route("parse.meal", parse, deps([], config).deps)).rejects.toBeInstanceOf(RequestError);
    const t = deps([]);
    t.deps.keys = {};
    await expect(route("parse.meal", parse, t.deps)).rejects.toBeInstanceOf(RequestError);
    expect(t.models).toHaveLength(0);
  });

  it("sanitises the body: no model, capped tokens, clamped temperature, allow-listed fields", () => {
    const req = sanitise({ messages: [{ role: "user", content: "x" }], model: "evil", max_tokens: 99_999,
      temperature: 9, user: "someone@example.com", logit_bias: { 1: 100 } }, "chat");
    expect(req.body).toEqual({ messages: [{ role: "user", content: "x" }], max_tokens: 2048, temperature: 2 });
    expect(() => sanitise({ messages: [{ role: "root", content: "x" }] }, "chat")).toThrow(RequestError);
    expect(() => sanitise({ messages: [{ role: "user", content: "x" }], response_format: { type: "json_schema" } },
      "chat")).toThrow(RequestError);
  });
});

describe("limits", () => {
  const burst = { capacity: 10, refillPerSecond: 1 };

  it("counts per UTC day and quota", () => {
    const state: LedgerState = {};
    const noon = Date.UTC(2026, 9, 3, 12);
    expect(Ledger.consume(state, "photo", 1, burst, noon)).toMatchObject({ allowed: true, remaining: 0 });
    expect(Ledger.consume(state, "photo", 1, burst, noon + 1000)).toMatchObject({ allowed: false, reason: "daily_quota" });
    expect(Ledger.consume(state, "parse", 1, burst, noon + 2000).allowed).toBe(true);
    expect(Ledger.consume(state, "photo", 1, burst, Date.UTC(2026, 9, 4, 0, 0, 1)).allowed).toBe(true);
  });

  it("registers once and only moves the counter forward", () => {
    const state: LedgerState = {};
    const record = { installId: "i", kind: "attest" as const, counter: 0, createdAt: 0 };
    expect(Ledger.register(state, record)).toBe(true);
    expect(Ledger.register(state, { ...record })).toBe(false);
    expect(Ledger.advanceCounter(state, 3)).toBe(true);
    expect(Ledger.advanceCounter(state, 3)).toBe(false);
    expect(Ledger.advanceCounter(state, 2)).toBe(false);
  });

  it("breaker: 429s under 30 s don't open it; a success resets it", () => {
    let s = Breaker.record({}, 429, 0);
    s = Breaker.record(s, 429, 29_000);
    expect(Breaker.retryAfter(s, 29_000)).toBeNull();
    s = Breaker.record(s, 200, 29_500);
    s = Breaker.record(s, 429, 40_000);
    expect(Breaker.retryAfter(s, 40_000)).toBeNull();
    s = Breaker.record(s, 429, 70_000);
    expect(Breaker.retryAfter(s, 70_000)).toBe(60);
    expect(Breaker.retryAfter(s, 130_001)).toBeNull();
  });
});

describe("config", () => {
  it("merges KV overrides safely", () => {
    const merged = mergeConfig(DEFAULT_CONFIG, {
      killSwitches: { chat: true },
      quotas: { photo: 10, parse: "lots" },
      routes: { "vision.meal": [{ provider: "groq", models: ["new-model"] }] },
      flags: { newThing: true, weird: "x" },
      secrets: { leak: true },
    });
    expect(merged.killSwitches.chat).toBe(true);
    expect(merged.killSwitches["vision.meal"]).toBe(false);
    expect(merged.quotas).toEqual({ photo: 10, parse: 100, chat: 60, food: 300 });
    expect(merged.routes["vision.meal"][0]!.models).toEqual(["new-model"]);
    expect(merged.flags).toEqual({ proxyEnabled: true, newThing: true });
    expect("secrets" in merged).toBe(false);
    expect(mergeConfig(DEFAULT_CONFIG, "garbage")).toEqual(DEFAULT_CONFIG);
    expect(Object.keys(publicConfig(merged))).not.toContain("policy");
  });
});

describe("food", () => {
  it("normalises Open Food Facts, falling back from kJ and salt", () => {
    const food = normaliseOFF({ code: "123", product_name: " Poha ", brands: "A, B", serving_quantity: "40",
      nutriments: { energy_100g: 1674, proteins_100g: 6, carbohydrates_100g: 77, fat_100g: 1, salt_100g: 1 } })!;
    expect(food).toMatchObject({ id: "off:123", name: "Poha", brand: "A", servingSizeG: 40,
      per100g: { kcal: 400.1, proteinG: 6, sodiumMg: 400 }, attribution: { license: "ODbL-1.0" } });
    expect(normaliseOFF({ code: "1", product_name: "", nutriments: {} })).toBeNull();
    expect(normaliseOFF({ code: "1", product_name: "No energy", nutriments: { proteins_100g: 3 } })).toBeNull();
  });

  it("normalises USDA nutrients by number", () => {
    const food = normaliseUSDA({ fdcId: 9, description: "Lentils, cooked", foodNutrients: [
      { nutrientNumber: "208", value: 116 }, { nutrientNumber: "203", value: 9 }, { nutrientNumber: "205", value: 20.1 },
      { nutrientNumber: "204", value: 0.4 }, { nutrientNumber: "291", value: 7.9 }] })!;
    expect(food).toMatchObject({ id: "usda:9", source: "usda", per100g: { kcal: 116, proteinG: 9, fiberG: 7.9 } });
  });

  it("caches misses for a day and search results only when non-empty", async () => {
    const cache = new MemoryFoodCache();
    let calls = 0;
    const fetcher = (async () => {
      calls++;
      return new Response(JSON.stringify({ status: 0 }), { status: 404 });
    }) as unknown as typeof fetch;
    expect(await barcode("12345678", { fetch: fetcher, cache })).toBeNull();
    expect(await barcode("12345678", { fetch: fetcher, cache })).toBeNull();
    expect(calls).toBe(1);

    const empty = (async () => new Response(JSON.stringify({ products: [] }))) as unknown as typeof fetch;
    expect(await search("dal", { fetch: empty, cache })).toEqual([]);
    expect(cache.entries.has("search:dal")).toBe(false);
  });
});
