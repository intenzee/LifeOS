// App Attest verification (BE-02), following Apple's "Validating apps that
// connect to your server". Pure functions over bytes; storage lives elsewhere.

// @peculiar/x509 resolves its parsers through tsyringe, which needs this polyfill.
import "reflect-metadata";
import { X509Certificate, cryptoProvider } from "@peculiar/x509";
import { concat, equalBytes, fromBase64, randomBytes, sha256, toBase64Url, utf8 } from "./bytes";
import { bytesField, CBORValue, decodeCBOR, field } from "./cbor";

cryptoProvider.set(crypto);

/** Apple App Attestation Root CA (valid 2020-03-18 → 2045-03-15).
 *  SHA-256 fingerprint 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32. */
export const APPLE_APP_ATTEST_ROOT = `-----BEGIN CERTIFICATE-----
MIICITCCAaegAwIBAgIQC/O+DvHN0uD7jG5yH2IXmDAKBggqhkjOPQQDAzBSMSYw
JAYDVQQDDB1BcHBsZSBBcHAgQXR0ZXN0YXRpb24gUm9vdCBDQTETMBEGA1UECgwK
QXBwbGUgSW5jLjETMBEGA1UECAwKQ2FsaWZvcm5pYTAeFw0yMDAzMTgxODMyNTNa
Fw00NTAzMTUwMDAwMDBaMFIxJjAkBgNVBAMMHUFwcGxlIEFwcCBBdHRlc3RhdGlv
biBSb290IENBMRMwEQYDVQQKDApBcHBsZSBJbmMuMRMwEQYDVQQIDApDYWxpZm9y
bmlhMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdh
NbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9au
Yen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41o0IwQDAPBgNVHRMBAf8EBTADAQH/
MB0GA1UdDgQWBBSskRBTM72+aEH/pwyp5frq5eWKoTAOBgNVHQ8BAf8EBAMCAQYw
CgYIKoZIzj0EAwMDaAAwZQIwQgFGnByvsiVbpTKwSga0kP0e8EeDS4+sQmTvb7vn
53O5+FRXgeLhpJ06ysC5PrOyAjEAp5U4xDgEgllF7En3VcE3iexZZtKeYnpqtijV
oyFraWVIyd/dganmrduC1bmTBGwD
-----END CERTIFICATE-----`;

const NONCE_OID = "1.2.840.113635.100.8.2";
const AAGUID_PRODUCTION = utf8("appattest\0\0\0\0\0\0\0");
const AAGUID_DEVELOPMENT = utf8("appattestdevelop");

export class AttestError extends Error {}

// MARK: - Challenges

/** Challenges are stateless: random ‖ issued-at ‖ HMAC. Single use comes from
 *  key registration being one-time (a key id can't be registered twice). */
export const CHALLENGE_LIFETIME_MS = 5 * 60 * 1000;

async function challengeMac(secret: string, body: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", utf8(`challenge:${secret}`), { name: "HMAC", hash: "SHA-256" },
    false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, body)).slice(0, 16);
}

export async function issueChallenge(secret: string, nowMs: number): Promise<string> {
  const body = concat(randomBytes(16), u64(nowMs));
  return toBase64Url(concat(body, await challengeMac(secret, body)));
}

export async function checkChallenge(challenge: string, secret: string, nowMs: number): Promise<boolean> {
  let bytes: Uint8Array;
  try {
    bytes = fromBase64(challenge);
  } catch {
    return false;
  }
  if (bytes.length !== 40) return false;
  const body = bytes.slice(0, 24);
  if (!equalBytes(bytes.slice(24), await challengeMac(secret, body))) return false;
  const issued = readU64(body.slice(16, 24));
  return issued <= nowMs + 30_000 && nowMs - issued <= CHALLENGE_LIFETIME_MS;
}

function u64(value: number): Uint8Array {
  const out = new Uint8Array(8);
  new DataView(out.buffer).setBigUint64(0, BigInt(Math.floor(value)));
  return out;
}

function readU64(bytes: Uint8Array): number {
  return Number(new DataView(bytes.buffer, bytes.byteOffset, 8).getBigUint64(0));
}

// MARK: - Authenticator data

export interface AuthenticatorData {
  rpIdHash: Uint8Array;
  flags: number;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

export function parseAuthenticatorData(bytes: Uint8Array, withCredential: boolean): AuthenticatorData {
  if (bytes.length < 37) throw new AttestError("authenticator data too short");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.length);
  const data: AuthenticatorData = {
    rpIdHash: bytes.slice(0, 32),
    flags: bytes[32] ?? 0,
    counter: view.getUint32(33),
  };
  if (withCredential) {
    if (bytes.length < 55) throw new AttestError("attested credential data missing");
    data.aaguid = bytes.slice(37, 53);
    const length = view.getUint16(53);
    if (bytes.length < 55 + length) throw new AttestError("credential id truncated");
    data.credentialId = bytes.slice(55, 55 + length);
  }
  return data;
}

// MARK: - Attestation (one-time key registration)

export interface AttestedKey {
  /** SubjectPublicKeyInfo DER of the device's P-256 key, base64. */
  publicKeySpki: string;
  counter: number;
  environment: "production" | "development";
  /** For a later fraud-metric check with Apple. */
  receipt: string;
}

export interface AttestationInput {
  keyId: string; // base64, as DCAppAttestService returns it
  attestation: Uint8Array; // CBOR
  /** The exact bytes the app hashed into `clientDataHash` (the challenge string, UTF-8). */
  clientData: Uint8Array;
  /** Accepted `TEAMID.bundle.id` values. */
  appIds: string[];
  allowDevelopment: boolean;
  roots: string[];
  now: Date;
}

export async function verifyAttestation(input: AttestationInput): Promise<AttestedKey> {
  let object: CBORValue;
  try {
    object = decodeCBOR(input.attestation);
  } catch (error) {
    throw new AttestError(`attestation is not CBOR: ${String(error)}`);
  }
  if (field(object, "fmt") !== "apple-appattest") throw new AttestError("wrong attestation format");
  const statement = field(object, "attStmt");
  const chain = field(statement ?? null, "x5c");
  if (!Array.isArray(chain) || chain.length < 2 || !chain.every((c) => c instanceof Uint8Array)) {
    throw new AttestError("certificate chain missing");
  }
  const authDataBytes = bytesField(object, "authData");
  const receipt = field(statement ?? null, "receipt");

  // 1. The chain ends at Apple's App Attestation root.
  const [credCert, ...intermediates] = (chain as Uint8Array[]).map((der) => new X509Certificate(der));
  await verifyChain(credCert!, intermediates, input.roots, input.now);

  // 2–4. nonce = SHA256(authData ‖ SHA256(clientData)) is in the credential certificate.
  const clientDataHash = await sha256(input.clientData);
  const nonce = await sha256(concat(authDataBytes, clientDataHash));
  const extension = credCert!.getExtension(NONCE_OID);
  if (!extension) throw new AttestError("nonce extension missing");
  if (!equalBytes(readNonce(new Uint8Array(extension.value)), nonce)) throw new AttestError("nonce mismatch");

  // 5. The key id is the SHA-256 of the credential's public key point.
  const spki = new Uint8Array(credCert!.publicKey.rawData);
  const point = spki.slice(spki.length - 65);
  const keyId = fromBase64(input.keyId);
  if (point[0] !== 0x04 || !equalBytes(await sha256(point), keyId)) throw new AttestError("key id mismatch");

  // 6–9. App id, counter, environment and credential id.
  const auth = parseAuthenticatorData(authDataBytes, true);
  if (!(await matchesAppId(auth.rpIdHash, input.appIds))) throw new AttestError("app id mismatch");
  if (auth.counter !== 0) throw new AttestError("counter must start at 0");
  let environment: AttestedKey["environment"];
  if (equalBytes(auth.aaguid!, AAGUID_PRODUCTION)) environment = "production";
  else if (equalBytes(auth.aaguid!, AAGUID_DEVELOPMENT) && input.allowDevelopment) environment = "development";
  else throw new AttestError("unexpected App Attest environment");
  if (!equalBytes(auth.credentialId!, keyId)) throw new AttestError("credential id mismatch");

  return {
    publicKeySpki: btoa(String.fromCharCode(...spki)),
    counter: 0,
    environment,
    receipt: receipt instanceof Uint8Array ? btoa(String.fromCharCode(...receipt)) : "",
  };
}

async function verifyChain(leaf: X509Certificate, intermediates: X509Certificate[], roots: string[], now: Date) {
  const trusted = roots.map((pem) => new X509Certificate(pem));
  const path = [leaf, ...intermediates];
  for (let i = 0; i < path.length; i++) {
    const cert = path[i]!;
    const issuer = path[i + 1] ?? trusted.find((root) => root.subject === cert.issuer);
    if (!issuer) throw new AttestError("chain does not reach a trusted root");
    if (i === path.length - 1 && !trusted.some((root) => root.subject === issuer.subject)) {
      throw new AttestError("chain does not reach a trusted root");
    }
    const ok = await cert.verify({ publicKey: issuer.publicKey, date: now });
    if (!ok) throw new AttestError(`certificate ${i} failed verification`);
  }
}

/** The extension holds `SEQUENCE { [1] EXPLICIT OCTET STRING nonce }`. */
export function readNonce(der: Uint8Array): Uint8Array {
  const seq = readTLV(der, 0, 0x30);
  const tagged = readTLV(der, seq.start, 0xa1);
  const octets = readTLV(der, tagged.start, 0x04);
  return der.slice(octets.start, octets.end);
}

function readTLV(der: Uint8Array, offset: number, tag: number): { start: number; end: number } {
  if (der[offset] !== tag) throw new AttestError(`expected DER tag ${tag.toString(16)}`);
  let length = der[offset + 1] ?? 0;
  let start = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + (der[start + i] ?? 0);
    start += count;
  }
  if (start + length > der.length) throw new AttestError("DER truncated");
  return { start, end: start + length };
}

async function matchesAppId(rpIdHash: Uint8Array, appIds: string[]): Promise<boolean> {
  for (const id of appIds) if (equalBytes(rpIdHash, await sha256(id))) return true;
  return false;
}

// MARK: - Assertions (every POST)

/** What an assertion signs: method, path with query, timestamp and the body hash. */
export async function clientDataForRequest(method: string, pathAndQuery: string, timestamp: string,
  body: Uint8Array): Promise<Uint8Array> {
  const bodyHash = Array.from(await sha256(body), (b) => b.toString(16).padStart(2, "0")).join("");
  return utf8(`${method.toUpperCase()}\n${pathAndQuery}\n${timestamp}\n${bodyHash}`);
}

export interface AssertionInput {
  assertion: Uint8Array; // CBOR { signature, authenticatorData }
  clientData: Uint8Array;
  publicKeySpki: string;
  previousCounter: number;
  appIds: string[];
}

/** The new counter. Throws unless the signature, app id and counter all check out. */
export async function verifyAssertion(input: AssertionInput): Promise<number> {
  let object: CBORValue;
  try {
    object = decodeCBOR(input.assertion);
  } catch {
    throw new AttestError("assertion is not CBOR");
  }
  const signature = bytesField(object, "signature");
  const authData = bytesField(object, "authenticatorData");
  const nonce = await sha256(concat(authData, await sha256(input.clientData)));

  const key = await crypto.subtle.importKey("spki", fromBase64(input.publicKeySpki),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const ok = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, derToRawSignature(signature), nonce);
  if (!ok) throw new AttestError("bad assertion signature");

  const auth = parseAuthenticatorData(authData, false);
  if (!(await matchesAppId(auth.rpIdHash, input.appIds))) throw new AttestError("app id mismatch");
  if (auth.counter <= input.previousCounter) throw new AttestError("assertion counter did not increase");
  return auth.counter;
}

/** ECDSA DER `SEQUENCE { r INTEGER, s INTEGER }` → the 64-byte r‖s WebCrypto expects. */
export function derToRawSignature(der: Uint8Array): Uint8Array {
  const seq = readTLV(der, 0, 0x30);
  const r = readTLV(der, seq.start, 0x02);
  const s = readTLV(der, r.end, 0x02);
  const pad = (bytes: Uint8Array) => {
    const trimmed = bytes[0] === 0 ? bytes.slice(1) : bytes;
    if (trimmed.length > 32) throw new AttestError("signature integer too long");
    const out = new Uint8Array(32);
    out.set(trimmed, 32 - trimmed.length);
    return out;
  };
  return concat(pad(der.slice(r.start, r.end)), pad(der.slice(s.start, s.end)));
}
