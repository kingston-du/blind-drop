// _shared/es256.ts — the small piece shared by Apple's two token-authenticated services.
//
// MusicKit and APNs both issue P-256 `.p8` keys and both expect a raw ES256 JWS signature.
// Keeping the PEM parser and signing operation here avoids two implementations drifting on
// escaped newlines, DER input, or the raw-r‖s signature format Web Crypto returns.

/** Bytes to unpadded base64url, as required by JWS. */
export function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** UTF-8 JSON to an unpadded base64url JWS segment. */
export function jwtSegment(value: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(value)));
}

/**
 * PEM to the DER bytes Web Crypto's `pkcs8` import expects.
 *
 * Supabase secrets and the local Docker env both carry newlines as the literal characters
 * `\\n`, because env files cannot safely carry a multiline value. Real newlines are accepted
 * too, which keeps the parser useful in direct tests and one-off local tooling.
 */
export function pemToPkcs8(pem: string): Uint8Array<ArrayBuffer> {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN [A-Z ]+-----/, "")
    .replace(/-----END [A-Z ]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Sign a JWS header-and-claims string and return its base64url signature segment. */
export async function signEs256(signingInput: string, privateKeyPem: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // Web Crypto returns the raw r‖s pair JWS wants; no ASN.1/DER unwrapping is needed.
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    ),
  );
  return base64url(signature);
}
