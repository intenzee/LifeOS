import { beforeEach, describe, expect, it } from "vitest";
import { clientDataForRequest } from "../src/attest";
import { toBase64, utf8 } from "../src/bytes";
import { completion, Device, get, Harness, makeDevice, makeHarness, makePKI, PKI, post, attest, assert } from "./helpers";

const parseBody = {
  messages: [
    { role: "system", content: "Extract foods." },
    { role: "user", content: "two rotis and dal makhani for lunch" },
  ],
  response_format: { type: "json_object" },
  temperature: 0.2,
  max_tokens: 5000,
  model: "something-the-app-must-not-choose",
};

/** Registers a device and returns a signed-request helper. */
async function enrol(h: Harness, pki: PKI) {
  const device = await makeDevice();
  const { challenge } = (await (await h.handle(post("/v1/attest/challenge", {}))).json()) as { challenge: string };
  const attestation = await attest(device, pki, challenge, new Date(h.clock.now));
  const res = await h.handle(post("/v1/attest/register", { keyId: device.keyId, challenge,
    attestation: toBase64(attestation) }));
  expect(res.status).toBe(200);
  const { installToken } = (await res.json()) as { installToken: string };
  const signed = async (path: string, body: unknown, dev: Device = device, extra: Record<string, string> = {}) => {
    const text = JSON.stringify(body);
    const timestamp = String(h.clock.now);
    const assertion = await assert(dev, await clientDataForRequest("POST", path, timestamp, utf8(text)));
    return new Request(`https://proxy.test${path}`, {
      method: "POST",
      body: text,
      headers: { authorization: `Bearer ${installToken}`, "x-lifeos-assertion": toBase64(assertion),
        "x-lifeos-timestamp": timestamp, "content-type": "application/json", ...extra },
    });
  };
  return { device, installToken, signed };
}

describe("proxy", () => {
  let pki: PKI;
  let h: Harness;

  beforeEach(async () => {
    pki = await makePKI(new Date(Date.UTC(2026, 9, 3, 12)));
    h = makeHarness({ attestRoots: [pki.rootPem] });
  });

  it("registers once, then serves a signed parse request with the server's key and model", async () => {
    const { signed, device } = await enrol(h, pki);
    h.upstream.handler = () => completion('{"items":[{"name":"roti"}],"mealType":"lunch"}', "qwen/qwen3.6-27b");

    const res = await h.handle(await signed("/v1/parse/meal", parseBody));
    expect(res.status).toBe(200);
    expect(res.headers.get("x-lifeos-model")).toBe("qwen/qwen3.6-27b");
    expect(res.headers.get("x-lifeos-quota-remaining")).toBe("99");
    const payload = (await res.json()) as { choices: { message: { content: string } }[] };
    expect(JSON.parse(payload.choices[0]!.message.content).items[0].name).toBe("roti");

    const call = h.calls[0]!;
    expect(call.url).toBe("https://api.groq.com/openai/v1/chat/completions");
    expect(call.headers.get("authorization")).toBe("Bearer gsk_test");
    expect((call.body as { model: string }).model).toBe("qwen/qwen3.6-27b"); // not the app's
    expect((call.body as { max_tokens: number }).max_tokens).toBe(800);       // capped per route

    // The same key can't register twice.
    const { challenge } = (await (await h.handle(post("/v1/attest/challenge", {}))).json()) as { challenge: string };
    const again = await h.handle(post("/v1/attest/register", { keyId: device.keyId, challenge,
      attestation: toBase64(await attest(device, pki, challenge, new Date(h.clock.now))) }));
    expect(again.status).toBe(409);
  });

  it("rejects missing tokens, missing or replayed assertions and tampered bodies", async () => {
    const { signed, installToken } = await enrol(h, pki);
    expect((await h.handle(post("/v1/parse/meal", parseBody))).status).toBe(401);
    expect((await h.handle(post("/v1/parse/meal", parseBody, { authorization: `Bearer ${installToken}` }))).status)
      .toBe(401);

    const request = await signed("/v1/parse/meal", parseBody);
    const replay = request.clone();
    expect((await h.handle(request)).status).toBe(200);
    const replayed = await h.handle(replay);
    expect(replayed.status).toBe(401);
    expect(((await replayed.json()) as { error: string }).error).toBe("assertion_failed");

    const good = await signed("/v1/parse/meal", parseBody);
    const tampered = new Request(good.url, { method: "POST", headers: good.headers,
      body: JSON.stringify({ ...parseBody, temperature: 1 }) });
    expect((await h.handle(tampered)).status).toBe(401);

    h.clock.now += 10 * 60_000; // stale timestamp
    const stale = await signed("/v1/parse/meal", parseBody);
    h.clock.now += 10 * 60_000;
    expect((await h.handle(stale)).status).toBe(401);
  });

  it("refreshes a token with an assertion", async () => {
    const { signed, device } = await enrol(h, pki);
    const res = await h.handle(await signed("/v1/attest/refresh", { keyId: device.keyId }));
    expect(res.status).toBe(200);
    expect(((await res.json()) as { kind: string }).kind).toBe("attest");
  });

  it("enforces the daily quota with Retry-After until UTC midnight", async () => {
    const { signed } = await enrol(h, pki);
    h.config.quotas.parse = 2;
    h.config.burst = { capacity: 100, refillPerSecond: 100 };
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
    const blocked = await h.handle(await signed("/v1/parse/meal", parseBody));
    expect(blocked.status).toBe(429);
    expect(((await blocked.json()) as { error: string }).error).toBe("daily_quota");
    expect(blocked.headers.get("retry-after")).toBe(String(12 * 3600)); // noon → midnight UTC

    h.clock.now += 12 * 3600 * 1000;
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
  });

  it("limits bursts per install", async () => {
    const { signed } = await enrol(h, pki);
    h.config.burst = { capacity: 2, refillPerSecond: 0.5 };
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
    const limited = await h.handle(await signed("/v1/parse/meal", parseBody));
    expect(limited.status).toBe(429);
    expect(((await limited.json()) as { error: string }).error).toBe("rate_limited");
    h.clock.now += 2_000;
    expect((await h.handle(await signed("/v1/parse/meal", parseBody))).status).toBe(200);
  });

  it("honours kill switches", async () => {
    const { signed } = await enrol(h, pki);
    h.config.killSwitches["parse.meal"] = true;
    const res = await h.handle(await signed("/v1/parse/meal", parseBody));
    expect(res.status).toBe(503);
    expect(((await res.json()) as { error: string }).error).toBe("disabled");
    expect(h.calls).toHaveLength(0);
  });

  it("validates shape and size per route", async () => {
    const { signed } = await enrol(h, pki);
    const image = { role: "user", content: [{ type: "image_url", image_url: { url: "data:image/jpeg;base64,AAAA" } }] };
    expect((await h.handle(await signed("/v1/parse/meal", { messages: [image] }))).status).toBe(400);
    const remote = { role: "user", content: [{ type: "image_url", image_url: { url: "https://x/y.jpg" } }] };
    expect((await h.handle(await signed("/v1/vision/meal", { messages: [remote] }))).status).toBe(400);
    expect((await h.handle(await signed("/v1/parse/meal", { messages: [] }))).status).toBe(400);
    expect((await h.handle(await signed("/v1/parse/meal", { ...parseBody, stream: true }))).status).toBe(400);
    const huge = { messages: [{ role: "user", content: "x".repeat(40_000) }] };
    expect((await h.handle(await signed("/v1/parse/meal", huge))).status).toBe(413);

    h.upstream.handler = () => completion('{"items":[]}');
    expect((await h.handle(await signed("/v1/vision/meal", { messages: [image],
      response_format: { type: "json_object" } }))).status).toBe(200);
  });

  it("streams /chat through untouched", async () => {
    const { signed } = await enrol(h, pki);
    const sse = 'data: {"choices":[{"delta":{"content":"Hi"}}]}\n\ndata: [DONE]\n\n';
    h.upstream.handler = () => new Response(sse, { headers: { "content-type": "text/event-stream" } });
    const res = await h.handle(await signed("/v1/chat", { messages: [{ role: "user", content: "hi" }], stream: true,
      tools: [{ type: "function", function: { name: "getTodayStatus", parameters: { type: "object" } } }] }));
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/event-stream");
    expect(await res.text()).toBe(sse);
    expect((h.calls[0]!.body as { tools: unknown[] }).tools).toHaveLength(1);
  });

  it("issues debug tokens only outside production, with a smaller trust level than attestation", async () => {
    const denied = await h.handle(post("/v1/attest/debug", { installUUID: "u1" }));
    expect(denied.status).toBe(404);

    const dev = makeHarness({ attestRoots: [pki.rootPem], debugToken: "letmein" });
    const res = await dev.handle(post("/v1/attest/debug", { installUUID: "u1" }, { "x-lifeos-debug": "letmein" }));
    expect(res.status).toBe(200);
    const { installToken } = (await res.json()) as { installToken: string };
    const ok = await dev.handle(post("/v1/parse/meal", parseBody, { authorization: `Bearer ${installToken}` }));
    expect(ok.status).toBe(200); // debug installs skip assertions

    const prod = makeHarness({ attestRoots: [pki.rootPem], debugToken: "letmein", environment: "production" });
    expect((await prod.handle(post("/v1/attest/debug", { installUUID: "u1" }, { "x-lifeos-debug": "letmein" })))
      .status).toBe(404);
    // A development token is useless against production.
    expect((await prod.handle(post("/v1/parse/meal", parseBody, { authorization: `Bearer ${installToken}` }))).status)
      .toBe(401);
  });

  it("serves public config with a one-hour cache", async () => {
    h.config.killSwitches.chat = true;
    const res = await h.handle(get("/v1/config"));
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=3600");
    const body = (await res.json()) as { killSwitches: { chat: boolean }; quotas: { photo: number } };
    expect(body.killSwitches.chat).toBe(true);
    expect(body.quotas.photo).toBe(25);
    expect(JSON.stringify(body)).not.toContain("gsk_");
  });

  it("records metrics without bodies or raw install ids", async () => {
    const { signed, device } = await enrol(h, pki);
    await h.handle(await signed("/v1/parse/meal", parseBody));
    const logged = JSON.stringify(h.metrics.events);
    expect(logged).not.toContain("roti");
    expect(logged).not.toContain(device.keyId);
    const event = h.metrics.events.at(-1)!;
    expect(event).toMatchObject({ route: "POST /v1/parse/meal", status: 200, provider: "groq" });
    expect(event.install).toMatch(/^[0-9a-f]{16}$/);
  });

  it("answers unknown paths with 404 and has no CORS", async () => {
    expect((await h.handle(get("/v1/nope"))).status).toBe(404);
    const preflight = await h.handle(new Request("https://proxy.test/v1/chat", { method: "OPTIONS" }));
    expect(preflight.headers.get("access-control-allow-origin")).toBeNull();
  });
});

describe("food endpoints", () => {
  it("look up barcodes through the cache and need a token", async () => {
    const pki = await makePKI(new Date(Date.UTC(2026, 9, 3, 12)));
    const h = makeHarness({ attestRoots: [pki.rootPem], debugToken: "d" });
    const { installToken } = (await (await h.handle(post("/v1/attest/debug", { installUUID: "u" },
      { "x-lifeos-debug": "d" }))).json()) as { installToken: string };
    const auth = { authorization: `Bearer ${installToken}` };
    h.upstream.handler = () => new Response(JSON.stringify({ status: 1, product: { product_name: "Parle-G",
      brands: "Parle", nutriments: { "energy-kcal_100g": 450, proteins_100g: 7, carbohydrates_100g: 77, fat_100g: 12 } } }));

    expect((await h.handle(get("/v1/food/barcode/8901719101038"))).status).toBe(401);
    const first = await h.handle(get("/v1/food/barcode/8901719101038", auth));
    expect(first.status).toBe(200);
    expect(((await first.json()) as { name: string }).name).toBe("Parle-G");
    await h.handle(get("/v1/food/barcode/8901719101038", auth));
    expect(h.calls).toHaveLength(1); // second hit from the cache
    expect(h.calls[0]!.headers.get("user-agent")).toContain("LifeOS");
    expect((await h.handle(get("/v1/food/barcode/12ab", auth))).status).toBe(400);
  });
});
