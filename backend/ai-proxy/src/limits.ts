// Per-install state (registration, assertion counter, daily quotas, burst
// bucket) and the provider circuit breaker (BE-09). Pure state machines over
// plain objects: a Durable Object persists them in production, a Map in tests.

import type { InstallKind } from "./jwt";
import type { QuotaKey } from "./config";

export interface InstallRecord {
  installId: string;
  kind: InstallKind;
  /** App Attest installs: the key that signs assertions. */
  publicKeySpki?: string;
  counter: number;
  environment?: "production" | "development";
  createdAt: number;
}

export interface UsageDecision {
  allowed: boolean;
  reason?: "daily_quota" | "rate_limited";
  /** Seconds until a retry can succeed. */
  retryAfter?: number;
  remaining?: number;
}

export interface LedgerState {
  record?: InstallRecord;
  usage?: { day: string; counts: Partial<Record<QuotaKey, number>> };
  bucket?: { tokens: number; at: number };
}

export interface Burst {
  capacity: number;
  refillPerSecond: number;
}

export const utcDay = (nowMs: number) => new Date(nowMs).toISOString().slice(0, 10);

function secondsToNextUtcMidnight(nowMs: number): number {
  const next = new Date(nowMs);
  next.setUTCHours(24, 0, 0, 0);
  return Math.ceil((next.getTime() - nowMs) / 1000);
}

/** One install's rules. Every method mutates `state` and returns the result. */
export const Ledger = {
  /** `false` if this install is already registered: an App Attest key registers once. */
  register(state: LedgerState, record: InstallRecord): boolean {
    if (state.record) return false;
    state.record = record;
    return true;
  },

  /** Stores `counter` if it moved forward (assertion replay protection). */
  advanceCounter(state: LedgerState, counter: number): boolean {
    if (!state.record || counter <= state.record.counter) return false;
    state.record.counter = counter;
    return true;
  },

  /** Burst bucket first (cheap to refill), then the daily quota. */
  consume(state: LedgerState, quota: QuotaKey, limit: number, burst: Burst, nowMs: number): UsageDecision {
    const bucket = state.bucket ?? { tokens: burst.capacity, at: nowMs };
    const tokens = Math.min(burst.capacity, bucket.tokens + ((nowMs - bucket.at) / 1000) * burst.refillPerSecond);
    if (tokens < 1) {
      state.bucket = { tokens, at: nowMs };
      return { allowed: false, reason: "rate_limited", retryAfter: Math.ceil((1 - tokens) / burst.refillPerSecond) };
    }

    const day = utcDay(nowMs);
    const usage = state.usage?.day === day ? state.usage : { day, counts: {} };
    const used = usage.counts[quota] ?? 0;
    if (used >= limit) {
      state.usage = usage;
      return { allowed: false, reason: "daily_quota", retryAfter: secondsToNextUtcMidnight(nowMs), remaining: 0 };
    }
    usage.counts[quota] = used + 1;
    state.usage = usage;
    state.bucket = { tokens: tokens - 1, at: nowMs };
    return { allowed: true, remaining: limit - used - 1 };
  },
};

/** The storage for one install: a Durable Object in production. */
export interface InstallStore {
  register(record: InstallRecord): Promise<boolean>;
  get(): Promise<InstallRecord | null>;
  advanceCounter(counter: number): Promise<boolean>;
  consume(quota: QuotaKey, limit: number, burst: Burst, nowMs: number): Promise<UsageDecision>;
}

export interface InstallDirectory {
  install(installId: string): InstallStore;
}

export class MemoryInstallDirectory implements InstallDirectory {
  readonly states = new Map<string, LedgerState>();

  install(installId: string): InstallStore {
    const state = () => {
      let s = this.states.get(installId);
      if (!s) this.states.set(installId, (s = {}));
      return s;
    };
    return {
      register: async (record) => Ledger.register(state(), record),
      get: async () => state().record ?? null,
      advanceCounter: async (counter) => Ledger.advanceCounter(state(), counter),
      consume: async (quota, limit, burst, now) => Ledger.consume(state(), quota, limit, burst, now),
    };
  }
}

// MARK: - Circuit breaker

/** Provider 429s for more than 30 s open the breaker for 60 s (doc 07 §6). */
export const BREAKER_THROTTLE_MS = 30_000;
export const BREAKER_OPEN_MS = 60_000;

export interface BreakerState {
  throttledSince?: number;
  openUntil?: number;
}

export const Breaker = {
  record(state: BreakerState, status: number, nowMs: number): BreakerState {
    if (status === 429) {
      const since = state.throttledSince ?? nowMs;
      if (nowMs - since >= BREAKER_THROTTLE_MS) return { openUntil: nowMs + BREAKER_OPEN_MS };
      return { ...state, throttledSince: since };
    }
    if (status >= 200 && status < 300) return {};
    return state;
  },

  /** Seconds until it closes, or `null` when closed. */
  retryAfter(state: BreakerState, nowMs: number): number | null {
    return state.openUntil !== undefined && nowMs < state.openUntil
      ? Math.ceil((state.openUntil - nowMs) / 1000)
      : null;
  },
};

export interface Breakers {
  retryAfter(provider: string, nowMs: number): Promise<number | null>;
  record(provider: string, status: number, nowMs: number): Promise<void>;
}

export class MemoryBreakers implements Breakers {
  readonly states = new Map<string, BreakerState>();

  async retryAfter(provider: string, nowMs: number) {
    return Breaker.retryAfter(this.states.get(provider) ?? {}, nowMs);
  }

  async record(provider: string, status: number, nowMs: number) {
    this.states.set(provider, Breaker.record(this.states.get(provider) ?? {}, status, nowMs));
  }
}
