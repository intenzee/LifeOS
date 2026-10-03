// Provider router (BE-04) and the OpenAI-compatible request contract shared by
// /vision/meal, /parse/meal and /chat. The app's gateway keeps its prompts
// (PromptRegistry); the proxy owns the model choice, the key, size and shape
// limits, retries and fallback.

import type { ProxyConfig, RouteKey } from "./config";
import type { Breakers } from "./limits";

/** Base URLs live in code, never in config, so a config edit can't send the key elsewhere. */
export const PROVIDERS: Record<string, { url: string; keyName: string }> = {
  groq: { url: "https://api.groq.com/openai/v1/chat/completions", keyName: "GROQ_API_KEY" },
};

export interface RouteLimits {
  maxBodyBytes: number;
  maxTokens: number;
  images: boolean;
  stream: boolean;
  /** The content must be a JSON object, and this check must pass. */
  validate?: (json: unknown) => boolean;
}

export const ROUTE_LIMITS: Record<RouteKey, RouteLimits> = {
  // A ≤1.6 MB JPEG is ~2.2 MB as base64.
  "vision.meal": { maxBodyBytes: 2_600_000, maxTokens: 1_500, images: true, stream: false },
  "parse.meal": {
    maxBodyBytes: 32_000,
    maxTokens: 800,
    images: false,
    stream: false,
    // `ParsedMeal` (LifeOS/AI/Food/ParsedMeal.swift): `items` is the one required field.
    validate: (json) => typeof json === "object" && json !== null && Array.isArray((json as { items?: unknown }).items),
  },
  chat: { maxBodyBytes: 256_000, maxTokens: 2_048, images: false, stream: true },
};

export class RequestError extends Error {
  constructor(readonly status: number, readonly reason: string, message: string) {
    super(message);
  }
}

const ROLES = new Set(["system", "user", "assistant", "tool"]);
const FORWARDED = ["temperature", "top_p", "response_format", "tools", "tool_choice", "stream"] as const;

export interface ChatRequest {
  body: Record<string, unknown>;
  stream: boolean;
  wantsJSON: boolean;
}

/** Checks the app's body and builds what goes to the provider (minus `model`). */
export function sanitise(raw: unknown, route: RouteKey): ChatRequest {
  const limits = ROUTE_LIMITS[route];
  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new RequestError(400, "bad_request", "body must be a JSON object");
  }
  const input = raw as Record<string, unknown>;
  const messages = input.messages;
  if (!Array.isArray(messages) || messages.length === 0 || messages.length > 40) {
    throw new RequestError(400, "bad_request", "messages must hold 1–40 items");
  }
  for (const message of messages) checkMessage(message, limits);

  const body: Record<string, unknown> = { messages };
  for (const key of FORWARDED) if (input[key] !== undefined) body[key] = input[key];

  const requested = Number(input.max_tokens ?? input.max_completion_tokens ?? limits.maxTokens);
  body.max_tokens = Math.max(1, Math.min(Number.isFinite(requested) ? requested : limits.maxTokens, limits.maxTokens));
  if (typeof body.temperature === "number") body.temperature = Math.min(Math.max(body.temperature, 0), 2);

  const stream = body.stream === true;
  if (stream && !limits.stream) throw new RequestError(400, "bad_request", "streaming is only available on /chat");
  if (!stream) delete body.stream;
  const format = body.response_format as { type?: unknown } | undefined;
  if (format !== undefined && format.type !== "json_object" && format.type !== "text") {
    throw new RequestError(400, "bad_request", "response_format must be json_object or text");
  }
  if (body.tools !== undefined && (!Array.isArray(body.tools) || body.tools.length > 16)) {
    throw new RequestError(400, "bad_request", "at most 16 tools");
  }
  return { body, stream, wantsJSON: format?.type === "json_object" || limits.validate !== undefined };
}

function checkMessage(message: unknown, limits: RouteLimits): void {
  if (typeof message !== "object" || message === null) throw new RequestError(400, "bad_request", "bad message");
  const { role, content } = message as { role?: unknown; content?: unknown };
  if (typeof role !== "string" || !ROLES.has(role)) throw new RequestError(400, "bad_request", "bad role");
  if (content === undefined || content === null || typeof content === "string") return;
  if (!Array.isArray(content)) throw new RequestError(400, "bad_request", "bad content");
  for (const part of content as { type?: unknown; image_url?: { url?: unknown } }[]) {
    if (part?.type === "text") continue;
    if (part?.type !== "image_url") throw new RequestError(400, "bad_request", "unsupported content part");
    if (!limits.images) throw new RequestError(400, "bad_request", "images are only accepted on /vision/meal");
    // Inline JPEGs only: no remote URLs for the provider to fetch.
    const url = part.image_url?.url;
    if (typeof url !== "string" || !url.startsWith("data:image/jpeg;base64,")) {
      throw new RequestError(400, "bad_request", "images must be inline JPEG data URLs");
    }
  }
}

// MARK: - Routing

export interface RouteResult {
  response: Response;
  provider: string;
  model: string;
  attempts: number;
}

export interface RouterDeps {
  config: ProxyConfig;
  keys: Record<string, string | undefined>;
  breakers: Breakers;
  fetch: typeof fetch;
  sleep: (ms: number) => Promise<void>;
  now: () => number;
}

/**
 * Tries each allowed provider and model in order:
 * - a retired/unknown model (`skipOnStatus`) or a non-JSON answer moves to the next model;
 * - 429/5xx/network errors retry with backoff, then move on;
 * - an open breaker skips the provider.
 * Throws `RequestError` (503 when nothing could answer).
 */
export async function route(route: RouteKey, request: ChatRequest, deps: RouterDeps): Promise<RouteResult> {
  const { config } = deps;
  const policy = config.policy;
  let attempts = 0;
  let breakerWait: number | null = null;
  let lastStatus = 503;

  for (const target of config.routes[route] ?? []) {
    const provider = PROVIDERS[target.provider];
    const key = provider ? deps.keys[provider.keyName] : undefined;
    // Every route carries food or health data.
    if (!provider || !key || !policy.personalDataAllowedProviders.includes(target.provider)) continue;
    const wait = await deps.breakers.retryAfter(target.provider, deps.now());
    if (wait !== null) {
      breakerWait = Math.max(breakerWait ?? 0, wait);
      continue;
    }

    models: for (const model of target.models) {
      for (let attempt = 0; attempt < Math.max(policy.retry.maxAttempts, 1); attempt++) {
        if (attempt > 0) await deps.sleep(policy.retry.backoffMs[attempt - 1] ?? 1_000);
        attempts++;
        let response: Response;
        try {
          response = await deps.fetch(provider.url, {
            method: "POST",
            headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify({ ...request.body, model }),
          });
        } catch {
          lastStatus = 502;
          continue; // network: retry
        }
        await deps.breakers.record(target.provider, response.status, deps.now());

        if (response.ok) {
          if (request.stream || !request.wantsJSON) return { response, provider: target.provider, model, attempts };
          const checked = await checkJSON(response, ROUTE_LIMITS[route].validate);
          if (checked) return { response: checked, provider: target.provider, model, attempts };
          lastStatus = 502;
          continue models; // a model that answers in prose: next model
        }
        lastStatus = response.status;
        await response.body?.cancel();
        if (policy.skipOnStatus.includes(response.status)) continue models;
        if (response.status === 429 || response.status >= 500) continue; // retry
        // 401/403: our key is wrong. Not the app's fault and not retryable.
        throw new RequestError(502, "provider_error", `provider ${target.provider} answered ${response.status}`);
      }
    }
  }

  if (breakerWait !== null) throw new RequestError(503, "provider_busy", String(breakerWait));
  throw new RequestError(lastStatus === 429 ? 503 : 502, lastStatus === 429 ? "provider_busy" : "no_model_available",
    "no provider could answer");
}

/** Returns a fresh Response if the first choice's content is a JSON object that passes `validate`. */
async function checkJSON(response: Response, validate?: (json: unknown) => boolean): Promise<Response | null> {
  const text = await response.text();
  try {
    const payload = JSON.parse(text) as { choices?: { message?: { content?: unknown } }[] };
    const content = payload.choices?.[0]?.message?.content;
    if (typeof content !== "string") return null;
    const start = content.indexOf("{");
    const end = content.lastIndexOf("}");
    if (start < 0 || end <= start) return null;
    const json = JSON.parse(content.slice(start, end + 1));
    if (validate && !validate(json)) return null;
  } catch {
    return null;
  }
  return new Response(text, { status: response.status, headers: { "content-type": "application/json" } });
}
