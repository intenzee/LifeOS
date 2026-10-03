import { describe, expect, it } from "vitest";
import {
  APPLE_APP_ATTEST_ROOT,
  checkChallenge,
  clientDataForRequest,
  derToRawSignature,
  issueChallenge,
  readNonce,
  verifyAssertion,
  verifyAttestation,
} from "../src/attest";
import { X509Certificate } from "@peculiar/x509";
import { fromBase64, utf8 } from "../src/bytes";
import { CBORError, decodeCBOR, encodeCBOR } from "../src/cbor";
import { signToken, verifyToken } from "../src/jwt";
import { APP_ID, assert, attest, makeDevice, makePKI, rawToDer } from "./helpers";

const now = new Date(Date.UTC(2026, 9, 3, 12));
const secret = "s".repeat(40);

describe("CBOR", () => {
  it("round-trips the shapes App Attest uses", () => {
    const value = new Map<unknown, unknown>([
      ["fmt", "apple-appattest"],
      ["n", -7],
      ["big", 70_000],
      ["bytes", new Uint8Array([1, 2, 3])],
      ["list", [true, false, null, "x"]],
    ]);
    expect(decodeCBOR(encodeCBOR(value as never))).toEqual(value);
  });

  it("rejects truncated and trailing input", () => {
    const bytes = encodeCBOR("hello");
    expect(() => decodeCBOR(bytes.slice(0, 3))).toThrow(CBORError);
    expect(() => decodeCBOR(new Uint8Array([...bytes, 0]))).toThrow(CBORError);
    expect(() => decodeCBOR(new Uint8Array([0xfb, 0, 0, 0, 0, 0, 0, 0, 0]))).toThrow(CBORError); // float
  });
});

describe("install tokens", () => {
  it("verifies its own tokens and rejects tampering, expiry and other environments", async () => {
    const t = now.getTime();
    const token = await signToken({ sub: "abc", kind: "attest", env: "development" }, secret, t);
    expect((await verifyToken(token, secret, "development", t))?.sub).toBe("abc");
    expect(await verifyToken(token, secret, "production", t)).toBeNull();
    expect(await verifyToken(token, "other-secret", "development", t)).toBeNull();
    expect(await verifyToken(token, secret, "development", t + 25 * 3600 * 1000)).toBeNull();
    const [h, , s] = token.split(".");
    const forged = btoa(JSON.stringify({ sub: "x", kind: "debug", env: "development", aud: "lifeos-proxy", iat: 0,
      exp: 9e9 })).replace(/=+$/, "");
    expect(await verifyToken(`${h}.${forged}.${s}`, secret, "development", t)).toBeNull();
    const none = btoa(JSON.stringify({ alg: "none" })).replace(/=+$/, "");
    expect(await verifyToken(`${none}.${token.split(".")[1]}.`, secret, "development", t)).toBeNull();
  });
});

describe("challenges", () => {
  it("are accepted for five minutes and can't be forged", async () => {
    const t = now.getTime();
    const challenge = await issueChallenge(secret, t);
    expect(await checkChallenge(challenge, secret, t + 60_000)).toBe(true);
    expect(await checkChallenge(challenge, secret, t + 6 * 60_000)).toBe(false);
    expect(await checkChallenge(challenge, "other", t)).toBe(false);
    expect(await checkChallenge(challenge.slice(0, -2) + "AA", secret, t)).toBe(false);
    expect(await checkChallenge("not base64 !!", secret, t)).toBe(false);
  });
});

describe("attestation", () => {
  async function setup() {
    const pki = await makePKI(now);
    const device = await makeDevice();
    const challenge = await issueChallenge(secret, now.getTime());
    const input = (attestation: Uint8Array, overrides: Partial<Parameters<typeof verifyAttestation>[0]> = {}) => ({
      keyId: device.keyId,
      attestation,
      clientData: utf8(challenge),
      appIds: [APP_ID],
      allowDevelopment: true,
      roots: [pki.rootPem],
      now,
      ...overrides,
    });
    return { pki, device, challenge, input };
  }

  it("accepts a genuine attestation and returns the key", async () => {
    const { pki, device, challenge, input } = await setup();
    const key = await verifyAttestation(input(await attest(device, pki, challenge, now)));
    expect(key.environment).toBe("development");
    expect(key.counter).toBe(0);
    expect(fromBase64(key.publicKeySpki).length).toBe(91);
  });

  it("rejects a chain that doesn't reach the trusted root", async () => {
    const { device, challenge, input } = await setup();
    const impostor = await makePKI(now, "Test App Attestation Root CA"); // same name, other key
    await expect(verifyAttestation(input(await attest(device, impostor, challenge, now)))).rejects.toThrow(/certificate/);
    await expect(verifyAttestation(input(await attest(device, impostor, challenge, now), { roots: [APPLE_APP_ATTEST_ROOT] })))
      .rejects.toThrow(/trusted root/);
  });

  it("rejects a nonce for another challenge", async () => {
    const { pki, device, challenge, input } = await setup();
    const attestation = await attest(device, pki, challenge, now, { clientData: utf8("other challenge") });
    await expect(verifyAttestation(input(attestation))).rejects.toThrow(/nonce/);
  });

  it("rejects another app, a non-zero counter, a wrong key id and production-only mismatches", async () => {
    const { pki, device, challenge, input } = await setup();
    await expect(verifyAttestation(input(await attest(device, pki, challenge, now, { appId: "X.other.app" }))))
      .rejects.toThrow(/app id/);
    await expect(verifyAttestation(input(await attest(device, pki, challenge, now, { counter: 1 }))))
      .rejects.toThrow(/counter/);
    const other = await makeDevice();
    await expect(verifyAttestation(input(await attest(device, pki, challenge, now), { keyId: other.keyId })))
      .rejects.toThrow(/key id/);
    await expect(verifyAttestation(input(await attest(device, pki, challenge, now), { allowDevelopment: false })))
      .rejects.toThrow(/environment/);
    const production = await verifyAttestation(input(await attest(device, pki, challenge, now,
      { aaguid: "appattest\0\0\0\0\0\0\0" }), { allowDevelopment: false }));
    expect(production.environment).toBe("production");
  });

  it("rejects expired certificates", async () => {
    const { pki, device, challenge, input } = await setup();
    const later = new Date(now.getTime() + 40 * 24 * 3600 * 1000);
    await expect(verifyAttestation(input(await attest(device, pki, challenge, now), { now: later }))).rejects.toThrow();
  });

  it("ships Apple's real root", () => {
    const root = new X509Certificate(APPLE_APP_ATTEST_ROOT);
    expect(root.subject).toContain("Apple App Attestation Root CA");
    expect(root.notAfter.getUTCFullYear()).toBe(2045);
  });

  it("reads the nonce extension", () => {
    const nonce = new Uint8Array(32).fill(7);
    expect(readNonce(new Uint8Array([0x30, 0x24, 0xa1, 0x22, 0x04, 0x20, ...nonce]))).toEqual(nonce);
    expect(() => readNonce(new Uint8Array([0x31, 0x00]))).toThrow();
  });
});

describe("assertions", () => {
  async function registered() {
    const pki = await makePKI(now);
    const device = await makeDevice();
    const challenge = await issueChallenge(secret, now.getTime());
    const key = await verifyAttestation({ keyId: device.keyId, attestation: await attest(device, pki, challenge, now),
      clientData: utf8(challenge), appIds: [APP_ID], allowDevelopment: true, roots: [pki.rootPem], now });
    return { device, key };
  }

  it("verifies the signature and returns the new counter", async () => {
    const { device, key } = await registered();
    const clientData = await clientDataForRequest("POST", "/v1/chat", "1", utf8("{}"));
    const assertion = await assert(device, clientData);
    expect(await verifyAssertion({ assertion, clientData, publicKeySpki: key.publicKeySpki, previousCounter: 0,
      appIds: [APP_ID] })).toBe(1);
  });

  it("rejects replays, other bodies, other apps and other keys", async () => {
    const { device, key } = await registered();
    const clientData = await clientDataForRequest("POST", "/v1/chat", "1", utf8("{}"));
    const base = { publicKeySpki: key.publicKeySpki, appIds: [APP_ID] };
    const assertion = await assert(device, clientData, { counter: 5 });
    await expect(verifyAssertion({ ...base, assertion, clientData, previousCounter: 5 })).rejects.toThrow(/counter/);
    const otherBody = await clientDataForRequest("POST", "/v1/chat", "1", utf8('{"a":1}'));
    await expect(verifyAssertion({ ...base, assertion, clientData: otherBody, previousCounter: 0 }))
      .rejects.toThrow(/signature/);
    const foreign = await assert(device, clientData, { appId: "X.other" });
    await expect(verifyAssertion({ ...base, assertion: foreign, clientData, previousCounter: 0 }))
      .rejects.toThrow(/app id/);
    const stranger = await registered();
    await expect(verifyAssertion({ ...base, publicKeySpki: stranger.key.publicKeySpki, assertion: await assert(device,
      clientData), clientData, previousCounter: 0 })).rejects.toThrow(/signature/);
  });

  it("converts DER signatures, including leading-zero integers", () => {
    const raw = new Uint8Array(64);
    raw[0] = 0x80; // needs a 0x00 pad in DER
    raw[63] = 1;
    expect(derToRawSignature(rawToDer(raw))).toEqual(raw);
  });
});
