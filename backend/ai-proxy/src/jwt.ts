// HS256 install tokens (doc 07 §4): short-lived, signed with a Worker secret.

import { fromBase64, toBase64Url, utf8 } from "./bytes";

export type InstallKind = "attest" | "devicecheck" | "debug";

export interface InstallClaims {
  /** Install id: a hash, never the raw App Attest key id. */
  sub: string;
  kind: InstallKind;
  /** The environment that issued it; a dev token never works in production. */
  env: string;
  aud: "lifeos-proxy";
  iat: number;
  exp: number;
}

export const TOKEN_LIFETIME_SECONDS = 24 * 3600;

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function signToken(
  claims: Omit<InstallClaims, "aud" | "iat" | "exp">,
  secret: string,
  nowMs: number,
): Promise<string> {
  const iat = Math.floor(nowMs / 1000);
  const body: InstallClaims = { ...claims, aud: "lifeos-proxy", iat, exp: iat + TOKEN_LIFETIME_SECONDS };
  const head = toBase64Url(utf8(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = toBase64Url(utf8(JSON.stringify(body)));
  const signature = await crypto.subtle.sign("HMAC", await hmacKey(secret), utf8(`${head}.${payload}`));
  return `${head}.${payload}.${toBase64Url(new Uint8Array(signature))}`;
}

/** The claims, or `null` for anything malformed, forged, expired or from another environment. */
export async function verifyToken(
  token: string,
  secret: string,
  env: string,
  nowMs: number,
): Promise<InstallClaims | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [head, payload, signature] = parts as [string, string, string];
  try {
    const header = JSON.parse(new TextDecoder().decode(fromBase64(head))) as { alg?: string };
    if (header.alg !== "HS256") return null;
    const valid = await crypto.subtle.verify(
      "HMAC",
      await hmacKey(secret),
      fromBase64(signature),
      utf8(`${head}.${payload}`),
    );
    if (!valid) return null;
    const claims = JSON.parse(new TextDecoder().decode(fromBase64(payload))) as InstallClaims;
    const now = Math.floor(nowMs / 1000);
    if (claims.aud !== "lifeos-proxy" || claims.env !== env) return null;
    if (typeof claims.exp !== "number" || claims.exp <= now) return null;
    if (typeof claims.sub !== "string" || !["attest", "devicecheck", "debug"].includes(claims.kind)) return null;
    return claims;
  } catch {
    return null;
  }
}
