// Test fixtures: a fake App Attest PKI and device, built with the same shapes
// Apple uses (CBOR attestation, nonce extension, DER ECDSA assertions).

import "reflect-metadata";
import {
  BasicConstraintsExtension,
  Extension,
  X509Certificate,
  X509CertificateGenerator,
  cryptoProvider,
} from "@peculiar/x509";
import { concat, sha256, toBase64, utf8 } from "../src/bytes";
import { encodeCBOR } from "../src/cbor";
import { createApp, Deps, Settings } from "../src/app";
import { DEFAULT_CONFIG, ProxyConfig } from "../src/config";
import { MemoryFoodCache } from "../src/food";
import { MemoryBreakers, MemoryInstallDirectory } from "../src/limits";
import { MemoryMetrics } from "../src/metrics";

cryptoProvider.set(crypto);

export const APP_ID = "DN9P7V5R2B.com.tanmay.LifeOS";
const NONCE_OID = "1.2.840.113635.100.8.2";
const DAY = 24 * 3600 * 1000;

export interface PKI {
  rootPem: string;
  root: X509Certificate;
  intermediate: X509Certificate;
  intermediateKeys: CryptoKeyPair;
}

const ecdsa384 = { name: "ECDSA", namedCurve: "P-384", hash: "SHA-384" } as const;

export async function makePKI(now: Date, name = "Test App Attestation Root CA"): Promise<PKI> {
  const rootKeys = (await crypto.subtle.generateKey(ecdsa384, true, ["sign", "verify"])) as CryptoKeyPair;
  const root = await X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: `CN=${name}`,
    notBefore: new Date(now.getTime() - DAY),
    notAfter: new Date(now.getTime() + 365 * DAY),
    signingAlgorithm: ecdsa384,
    keys: rootKeys,
    extensions: [new BasicConstraintsExtension(true, undefined, true)],
  });
  const intermediateKeys = (await crypto.subtle.generateKey(ecdsa384, true, ["sign", "verify"])) as CryptoKeyPair;
  const intermediate = await X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test App Attestation CA 1",
    issuer: root.subject,
    notBefore: new Date(now.getTime() - DAY),
    notAfter: new Date(now.getTime() + 30 * DAY),
    signingAlgorithm: ecdsa384,
    publicKey: intermediateKeys.publicKey,
    signingKey: rootKeys.privateKey,
    extensions: [new BasicConstraintsExtension(true, 0, true)],
  });
  return { rootPem: root.toString("pem"), root, intermediate, intermediateKeys };
}

export interface Device {
  keys: CryptoKeyPair;
  keyId: string;
  keyIdBytes: Uint8Array;
  counter: number;
}

export async function makeDevice(): Promise<Device> {
  const keys = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true,
    ["sign", "verify"])) as CryptoKeyPair;
  const point = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  const keyIdBytes = await sha256(point);
  return { keys, keyId: toBase64(keyIdBytes), keyIdBytes, counter: 0 };
}

function u32(value: number): Uint8Array {
  const out = new Uint8Array(4);
  new DataView(out.buffer).setUint32(0, value);
  return out;
}

function u16(value: number): Uint8Array {
  return new Uint8Array([value >> 8, value & 0xff]);
}

export interface AttestOptions {
  appId?: string;
  aaguid?: string;
  counter?: number;
  clientData?: Uint8Array;
  nonceOverride?: Uint8Array;
  credentialId?: Uint8Array;
}

/** `DCAppAttestService.attestKey` output for `challenge`, signed by `pki`. */
export async function attest(device: Device, pki: PKI, challenge: string, now: Date, options: AttestOptions = {})
  : Promise<Uint8Array> {
  const credentialId = options.credentialId ?? device.keyIdBytes;
  const authData = concat(
    await sha256(options.appId ?? APP_ID),
    new Uint8Array([0x40]),
    u32(options.counter ?? 0),
    utf8(options.aaguid ?? "appattestdevelop"),
    u16(credentialId.length),
    credentialId,
  );
  const clientData = options.clientData ?? utf8(challenge);
  const nonce = options.nonceOverride ?? (await sha256(concat(authData, await sha256(clientData))));
  const extensionValue = concat(new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20]), nonce);
  const leaf = await X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=device-key",
    issuer: pki.intermediate.subject,
    notBefore: new Date(now.getTime() - DAY),
    notAfter: new Date(now.getTime() + 3 * DAY),
    signingAlgorithm: ecdsa384,
    publicKey: device.keys.publicKey,
    signingKey: pki.intermediateKeys.privateKey,
    extensions: [new Extension(NONCE_OID, false, extensionValue)],
  });
  return encodeCBOR(new Map<string, unknown>([
    ["fmt", "apple-appattest"],
    ["attStmt", new Map<string, unknown>([
      ["x5c", [new Uint8Array(leaf.rawData), new Uint8Array(pki.intermediate.rawData)]],
      ["receipt", utf8("receipt")],
    ])],
    ["authData", authData],
  ]) as never);
}

/** raw r‖s → DER, as Apple sends assertion signatures. */
export function rawToDer(raw: Uint8Array): Uint8Array {
  const int = (bytes: Uint8Array) => {
    let i = 0;
    while (i < bytes.length - 1 && bytes[i] === 0) i++;
    let v: Uint8Array = bytes.slice(i);
    if ((v[0] ?? 0) & 0x80) v = concat(new Uint8Array([0]), v);
    return concat(new Uint8Array([0x02, v.length]), v);
  };
  const body = concat(int(raw.slice(0, 32)), int(raw.slice(32)));
  return concat(new Uint8Array([0x30, body.length]), body);
}

/** `generateAssertion` output over `clientData`. Increments the device counter. */
export async function assert(device: Device, clientData: Uint8Array, options: { appId?: string; counter?: number } = {})
  : Promise<Uint8Array> {
  device.counter = options.counter ?? device.counter + 1;
  const authData = concat(await sha256(options.appId ?? APP_ID), new Uint8Array([0x40]), u32(device.counter));
  const nonce = await sha256(concat(authData, await sha256(clientData)));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, device.keys.privateKey, nonce));
  return encodeCBOR(new Map<string, unknown>([
    ["signature", rawToDer(raw)],
    ["authenticatorData", authData],
  ]) as never);
}

// MARK: - App harness

export interface Harness {
  handle: (request: Request) => Promise<Response>;
  deps: Deps;
  installs: MemoryInstallDirectory;
  breakers: MemoryBreakers;
  metrics: MemoryMetrics;
  cache: MemoryFoodCache;
  clock: { now: number };
  config: ProxyConfig;
  calls: { url: string; body?: unknown; headers: Headers }[];
  /** Answers outgoing fetches; default: a JSON chat completion. */
  upstream: { handler: (url: string, init: RequestInit) => Promise<Response> | Response };
  sleeps: number[];
}

export function completion(content: string, model = "m"): Response {
  return new Response(JSON.stringify({ model, choices: [{ message: { role: "assistant", content } }],
    usage: { prompt_tokens: 10, completion_tokens: 5 } }), { status: 200, headers: { "content-type": "application/json" } });
}

export function makeHarness(settings: Partial<Settings> & { attestRoots: string[] }, start = Date.UTC(2026, 9, 3, 12))
  : Harness {
  const clock = { now: start };
  const installs = new MemoryInstallDirectory();
  const breakers = new MemoryBreakers();
  const metrics = new MemoryMetrics();
  const cache = new MemoryFoodCache();
  const calls: Harness["calls"] = [];
  const sleeps: number[] = [];
  const upstream: Harness["upstream"] = { handler: () => completion('{"items":[]}') };
  const config: ProxyConfig = structuredClone(DEFAULT_CONFIG);
  const deps: Deps = {
    settings: {
      environment: "development",
      appIds: [APP_ID],
      jwtSecret: "test-secret-test-secret-test-secret",
      providerKeys: { GROQ_API_KEY: "gsk_test" },
      metricsSalt: "salt",
      ...settings,
    },
    installs,
    breakers,
    loadConfig: async () => config,
    foodCache: cache,
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      const body = typeof init?.body === "string" ? JSON.parse(init.body) : undefined;
      calls.push({ url, body, headers: new Headers(init?.headers) });
      return upstream.handler(url, init ?? {});
    }) as typeof fetch,
    metrics,
    now: () => clock.now,
    sleep: async (ms) => {
      sleeps.push(ms);
      clock.now += ms;
    },
  };
  return { handle: createApp(deps), deps, installs, breakers, metrics, cache, clock, config, calls, upstream, sleeps };
}

export function post(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`https://proxy.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

export function get(path: string, headers: Record<string, string> = {}): Request {
  return new Request(`https://proxy.test${path}`, { headers });
}
