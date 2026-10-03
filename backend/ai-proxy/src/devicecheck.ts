// DeviceCheck fallback (BE-02) for devices where App Attest isn't supported.
// Apple only confirms the token came from a genuine Apple device running an
// app on our team, so these installs get a smaller quota.

import { fromBase64, toBase64Url, utf8 } from "./bytes";

export interface DeviceCheckCredentials {
  teamId: string;
  keyId: string;
  /** The .p8 key's PEM (PKCS #8). */
  privateKey: string;
}

async function bearer(credentials: DeviceCheckCredentials, nowMs: number): Promise<string> {
  const der = fromBase64(credentials.privateKey.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const head = toBase64Url(utf8(JSON.stringify({ alg: "ES256", kid: credentials.keyId })));
  const claims = toBase64Url(utf8(JSON.stringify({ iss: credentials.teamId, iat: Math.floor(nowMs / 1000) })));
  // WebCrypto's ECDSA output is already r‖s, the JWS format.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(`${head}.${claims}`));
  return `${head}.${claims}.${toBase64Url(new Uint8Array(signature))}`;
}

/** `true` when Apple accepts the device token. */
export async function validateDeviceToken(
  deviceToken: string,
  credentials: DeviceCheckCredentials,
  production: boolean,
  fetcher: typeof fetch,
  nowMs: number,
): Promise<boolean> {
  const host = production ? "api.devicecheck.apple.com" : "api.development.devicecheck.apple.com";
  const response = await fetcher(`https://${host}/v1/validate_device_token`, {
    method: "POST",
    headers: { authorization: `Bearer ${await bearer(credentials, nowMs)}`, "content-type": "application/json" },
    body: JSON.stringify({ device_token: deviceToken, transaction_id: crypto.randomUUID(), timestamp: nowMs }),
  });
  await response.body?.cancel();
  return response.status === 200;
}
