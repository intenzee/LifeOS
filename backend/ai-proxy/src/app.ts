// The proxy's HTTP surface (doc 07 §3), independent of Workers bindings so it
// runs under plain Node in tests. `worker.ts` wires the real bindings.

import {
  AttestError,
  checkChallenge,
  clientDataForRequest,
  issueChallenge,
  verifyAssertion,
  verifyAttestation,
} from "./attest";
import { fromBase64, sha256, toHex, utf8 } from "./bytes";
import { ProxyConfig, publicConfig, ROUTE_QUOTA, RouteKey } from "./config";
import { DeviceCheckCredentials, validateDeviceToken } from "./devicecheck";
import { barcode, FoodCache, isBarcode, search } from "./food";
import { InstallClaims, signToken, TOKEN_LIFETIME_SECONDS, verifyToken } from "./jwt";
import { Breakers, InstallDirectory, InstallRecord } from "./limits";
import type { Metrics } from "./metrics";
import { RequestError, route, ROUTE_LIMITS, sanitise } from "./router";

export interface Settings {
  environment: "development" | "production";
  /** `TEAMID.bundle.id` values allowed to attest. */
  appIds: string[];
  jwtSecret: string;
  /** Non-production only: lets simulators and CI get a token. */
  debugToken?: string;
  deviceCheck?: DeviceCheckCredentials;
  usdaKey?: string;
  providerKeys: Record<string, string | undefined>;
  metricsSalt: string;
  attestRoots: string[];
}

export interface Deps {
  settings: Settings;
  installs: InstallDirectory;
  breakers: Breakers;
  loadConfig: () => Promise<ProxyConfig>;
  foodCache: FoodCache;
  fetch: typeof fetch;
  metrics: Metrics;
  now: () => number;
  sleep: (ms: number) => Promise<void>;
}

const ASSERTION_HEADER = "x-lifeos-assertion";
const TIMESTAMP_HEADER = "x-lifeos-timestamp";
const DEBUG_HEADER = "x-lifeos-debug";
const MAX_CLOCK_SKEW_MS = 5 * 60 * 1000;
const SMALL_BODY = 16_000;

const AI_ROUTES: Record<string, RouteKey> = {
  "/v1/vision/meal": "vision.meal",
  "/v1/parse/meal": "parse.meal",
  "/v1/chat": "chat",
};

export function createApp(deps: Deps): (request: Request) => Promise<Response> {
  return async (request) => {
    const started = deps.now();
    const url = new URL(request.url);
    let event: { route: string; install?: string; provider?: string; model?: string; reason?: string } = {
      route: routeName(request.method, url.pathname),
    };
    let response: Response;
    try {
      response = await dispatch(request, url, deps, (patch) => (event = { ...event, ...patch }));
    } catch (error) {
      response = errorResponse(error);
      if (error instanceof RequestError) event.reason = error.reason;
      else console.error(JSON.stringify({ route: event.route, error: String(error) }));
    }
    deps.metrics.record({ ...event, status: response.status, latencyMs: deps.now() - started });
    return response;
  };
}

function routeName(method: string, path: string): string {
  if (path.startsWith("/v1/food/barcode/")) return `${method} /v1/food/barcode`;
  return `${method} ${path}`;
}

type Note = (patch: { install?: string; provider?: string; model?: string; reason?: string }) => void;

async function dispatch(request: Request, url: URL, deps: Deps, note: Note): Promise<Response> {
  const path = url.pathname;
  const method = request.method;

  if (method === "GET" && path === "/v1/config") {
    return json(publicConfig(await deps.loadConfig()), 200, { "cache-control": "public, max-age=3600" });
  }
  if (method === "POST" && path === "/v1/attest/challenge") {
    return json({ challenge: await issueChallenge(deps.settings.jwtSecret, deps.now()) });
  }
  if (method === "POST" && path === "/v1/attest/register") return register(request, deps, note);
  if (method === "POST" && path === "/v1/attest/refresh") return refresh(request, url, deps, note);
  if (method === "POST" && path === "/v1/attest/devicecheck") return deviceCheck(request, deps, note);
  if (method === "POST" && path === "/v1/attest/debug") return debugToken(request, deps, note);

  const aiRoute = AI_ROUTES[path];
  if (aiRoute && method === "POST") return ai(aiRoute, request, url, deps, note);
  if (method === "GET" && path.startsWith("/v1/food/")) return food(request, url, deps, note);

  if (method === "OPTIONS") return new Response(null, { status: 405 }); // no CORS: app-only
  throw new RequestError(404, "not_found", "no such endpoint");
}

// MARK: - Install tokens

async function installId(prefix: string, value: string): Promise<string> {
  return toHex(await sha256(`${prefix}:${value}`)).slice(0, 32);
}

async function metricId(deps: Deps, id: string): Promise<string> {
  return toHex(await sha256(`${deps.settings.metricsSalt}:${id}`)).slice(0, 16);
}

async function tokenResponse(deps: Deps, record: Pick<InstallRecord, "installId" | "kind">): Promise<Response> {
  const token = await signToken({ sub: record.installId, kind: record.kind, env: deps.settings.environment },
    deps.settings.jwtSecret, deps.now());
  return json({ installToken: token, expiresIn: TOKEN_LIFETIME_SECONDS, kind: record.kind });
}

async function readJSON(request: Request, limit: number): Promise<{ bytes: Uint8Array; value: unknown }> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > limit) throw new RequestError(413, "too_large", "request body too large");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > limit) throw new RequestError(413, "too_large", "request body too large");
  try {
    return { bytes, value: JSON.parse(new TextDecoder().decode(bytes)) };
  } catch {
    throw new RequestError(400, "bad_request", "body must be JSON");
  }
}

function stringField(value: unknown, key: string): string {
  const v = (value as Record<string, unknown> | null)?.[key];
  if (typeof v !== "string" || v.length === 0 || v.length > 64_000) {
    throw new RequestError(400, "bad_request", `missing ${key}`);
  }
  return v;
}

/** `POST /attest/register {keyId, attestation, challenge}` → install token. */
async function register(request: Request, deps: Deps, note: Note): Promise<Response> {
  const { value } = await readJSON(request, 64_000);
  const keyId = stringField(value, "keyId");
  const challenge = stringField(value, "challenge");
  if (!(await checkChallenge(challenge, deps.settings.jwtSecret, deps.now()))) {
    throw new RequestError(401, "bad_challenge", "challenge expired or forged");
  }
  let attested;
  try {
    attested = await verifyAttestation({
      keyId,
      attestation: fromBase64(stringField(value, "attestation")),
      clientData: utf8(challenge),
      appIds: deps.settings.appIds,
      allowDevelopment: deps.settings.environment !== "production",
      roots: deps.settings.attestRoots,
      now: new Date(deps.now()),
    });
  } catch (error) {
    if (error instanceof AttestError) throw new RequestError(401, "attestation_failed", error.message);
    throw error;
  }
  const id = await installId("attest", keyId);
  note({ install: await metricId(deps, id) });
  const created = await deps.installs.install(id).register({
    installId: id,
    kind: "attest",
    publicKeySpki: attested.publicKeySpki,
    counter: 0,
    environment: attested.environment,
    createdAt: deps.now(),
  });
  if (!created) throw new RequestError(409, "already_registered", "this key is already registered");
  return tokenResponse(deps, { installId: id, kind: "attest" });
}

/** `POST /attest/refresh {keyId}` signed with an assertion → a fresh token. */
async function refresh(request: Request, url: URL, deps: Deps, note: Note): Promise<Response> {
  const { bytes, value } = await readJSON(request, SMALL_BODY);
  const id = await installId("attest", stringField(value, "keyId"));
  note({ install: await metricId(deps, id) });
  const store = deps.installs.install(id);
  const record = await store.get();
  if (!record || record.kind !== "attest") throw new RequestError(401, "unknown_install", "register first");
  await checkAssertion(request, url, bytes, record, deps);
  return tokenResponse(deps, record);
}

/** `POST /attest/devicecheck {deviceToken, installUUID}`: the fallback. */
async function deviceCheck(request: Request, deps: Deps, note: Note): Promise<Response> {
  const credentials = deps.settings.deviceCheck;
  if (!credentials) throw new RequestError(501, "unavailable", "DeviceCheck is not configured");
  const { value } = await readJSON(request, SMALL_BODY);
  const deviceToken = stringField(value, "deviceToken");
  const installUUID = stringField(value, "installUUID");
  const valid = await validateDeviceToken(deviceToken, credentials, deps.settings.environment === "production",
    deps.fetch, deps.now());
  if (!valid) throw new RequestError(401, "devicecheck_failed", "device token rejected");
  const id = await installId("devicecheck", installUUID);
  note({ install: await metricId(deps, id) });
  await deps.installs.install(id).register({ installId: id, kind: "devicecheck", counter: 0, createdAt: deps.now() });
  return tokenResponse(deps, { installId: id, kind: "devicecheck" });
}

/** `POST /attest/debug {installUUID}` with `X-LifeOS-Debug`: development only. */
async function debugToken(request: Request, deps: Deps, note: Note): Promise<Response> {
  const { debugToken: secret, environment } = deps.settings;
  const offered = request.headers.get(DEBUG_HEADER);
  if (environment === "production" || !secret || offered !== secret) {
    throw new RequestError(404, "not_found", "no such endpoint");
  }
  const { value } = await readJSON(request, SMALL_BODY);
  const id = await installId("debug", stringField(value, "installUUID"));
  note({ install: await metricId(deps, id) });
  await deps.installs.install(id).register({ installId: id, kind: "debug", counter: 0, createdAt: deps.now() });
  return tokenResponse(deps, { installId: id, kind: "debug" });
}

// MARK: - Authenticated requests

async function authenticate(request: Request, deps: Deps, note: Note): Promise<InstallClaims> {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const claims = token ? await verifyToken(token, deps.settings.jwtSecret, deps.settings.environment, deps.now()) : null;
  if (!claims) throw new RequestError(401, "unauthorized", "missing or expired install token");
  if (claims.kind === "debug" && deps.settings.environment === "production") {
    throw new RequestError(401, "unauthorized", "debug tokens don't work in production");
  }
  note({ install: await metricId(deps, claims.sub) });
  return claims;
}

/** App Attest installs sign every POST: method, path, timestamp and body hash. */
async function checkAssertion(request: Request, url: URL, body: Uint8Array, record: InstallRecord, deps: Deps) {
  const assertion = request.headers.get(ASSERTION_HEADER);
  const timestamp = request.headers.get(TIMESTAMP_HEADER);
  if (!assertion || !timestamp || !record.publicKeySpki) {
    throw new RequestError(401, "assertion_required", "missing assertion");
  }
  if (Math.abs(deps.now() - Number(timestamp)) > MAX_CLOCK_SKEW_MS) {
    throw new RequestError(401, "assertion_failed", "timestamp outside the allowed window");
  }
  let counter: number;
  try {
    counter = await verifyAssertion({
      assertion: fromBase64(assertion),
      clientData: await clientDataForRequest(request.method, url.pathname + url.search, timestamp, body),
      publicKeySpki: record.publicKeySpki,
      previousCounter: record.counter,
      appIds: deps.settings.appIds,
    });
  } catch (error) {
    if (error instanceof AttestError) throw new RequestError(401, "assertion_failed", error.message);
    throw error;
  }
  if (!(await deps.installs.install(record.installId).advanceCounter(counter))) {
    throw new RequestError(401, "assertion_failed", "assertion replayed");
  }
}

async function consume(claims: InstallClaims, quota: keyof ProxyConfig["quotas"], config: ProxyConfig, deps: Deps) {
  const share = claims.kind === "devicecheck" ? config.deviceCheckShare : 1;
  const limit = Math.max(1, Math.floor(config.quotas[quota] * share));
  const decision = await deps.installs.install(claims.sub).consume(quota, limit, config.burst, deps.now());
  if (!decision.allowed) {
    throw new RequestError(429, decision.reason ?? "rate_limited", String(decision.retryAfter ?? 60));
  }
  return decision;
}

async function ai(routeKey: RouteKey, request: Request, url: URL, deps: Deps, note: Note): Promise<Response> {
  const limits = ROUTE_LIMITS[routeKey];
  const claims = await authenticate(request, deps, note);
  const { bytes, value } = await readJSON(request, limits.maxBodyBytes);
  if (claims.kind === "attest") {
    const record = await deps.installs.install(claims.sub).get();
    if (!record) throw new RequestError(401, "unknown_install", "register again");
    await checkAssertion(request, url, bytes, record, deps);
  }
  const config = await deps.loadConfig();
  if (config.killSwitches[routeKey] || config.flags.proxyEnabled === false) {
    throw new RequestError(503, "disabled", "3600");
  }
  const chat = sanitise(value, routeKey);
  const decision = await consume(claims, ROUTE_QUOTA[routeKey], config, deps);

  const result = await route(routeKey, chat, {
    config,
    keys: deps.settings.providerKeys,
    breakers: deps.breakers,
    fetch: deps.fetch,
    sleep: deps.sleep,
    now: deps.now,
  });
  note({ provider: result.provider, model: result.model });
  const headers: Record<string, string> = {
    "content-type": chat.stream ? "text/event-stream" : "application/json",
    "x-lifeos-model": result.model,
    "x-lifeos-quota-remaining": String(decision.remaining ?? 0),
  };
  if (chat.stream) headers["cache-control"] = "no-store";
  return new Response(result.response.body, { status: 200, headers });
}

async function food(request: Request, url: URL, deps: Deps, note: Note): Promise<Response> {
  const claims = await authenticate(request, deps, note);
  const config = await deps.loadConfig();
  if (config.killSwitches.food) throw new RequestError(503, "disabled", "3600");
  const foodDeps = { fetch: deps.fetch, cache: deps.foodCache, usdaKey: deps.settings.usdaKey };

  if (url.pathname.startsWith("/v1/food/barcode/")) {
    const code = url.pathname.slice("/v1/food/barcode/".length);
    if (!isBarcode(code)) throw new RequestError(400, "bad_request", "barcodes are 8–14 digits");
    await consume(claims, "food", config, deps);
    const item = await barcode(code, foodDeps);
    if (!item) throw new RequestError(404, "not_found", "no product with nutrition for this barcode");
    return json(item);
  }
  if (url.pathname === "/v1/food/search") {
    const query = url.searchParams.get("q") ?? "";
    if (query.trim().length < 2) throw new RequestError(400, "bad_request", "q needs at least 2 characters");
    await consume(claims, "food", config, deps);
    return json({ items: await search(query, foodDeps) });
  }
  throw new RequestError(404, "not_found", "no such endpoint");
}

// MARK: - Responses

function json(value: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(value), { status, headers: { "content-type": "application/json", ...headers } });
}

/** `{error, message, retryAfter?}` plus `Retry-After` for 429/503. */
function errorResponse(error: unknown): Response {
  if (!(error instanceof RequestError)) return json({ error: "internal", message: "unexpected error" }, 500);
  const retryable = error.status === 429 || error.status === 503;
  const retryAfter = retryable ? Number(error.message) || 60 : undefined;
  return json(
    { error: error.reason, message: retryable ? retryMessage(error.reason) : error.message, retryAfter },
    error.status,
    retryAfter ? { "retry-after": String(retryAfter) } : {},
  );
}

function retryMessage(reason: string): string {
  switch (reason) {
    case "daily_quota": return "Daily limit reached. It resets at midnight UTC.";
    case "rate_limited": return "Too many requests. Try again in a moment.";
    case "disabled": return "This feature is paused.";
    default: return "The AI service is busy. Try again shortly.";
  }
}
