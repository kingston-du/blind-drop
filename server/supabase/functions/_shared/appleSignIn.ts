// _shared/appleSignIn.ts — fresh reauthentication and token revocation for account deletion.

import { createRemoteJWKSet, jwtVerify } from "npm:jose@6.2.8";
import { ApiError } from "./http.ts";
import { jwtSegment, signEs256 } from "./es256.ts";

const APPLE = "https://appleid.apple.com";
const appleKeys = createRemoteJWKSet(new URL(`${APPLE}/auth/keys`));

function secret(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new ApiError("AUTH_PROVIDER_UNAVAILABLE");
  return value;
}

async function clientSecret(now = new Date()): Promise<string> {
  const issuedAt = Math.floor(now.getTime() / 1000);
  const clientID = secret("APPLE_SIGN_IN_CLIENT_ID");
  const header = jwtSegment({ alg: "ES256", kid: secret("APPLE_SIGN_IN_KEY_ID"), typ: "JWT" });
  const claims = jwtSegment({
    iss: secret("APPLE_SIGN_IN_TEAM_ID"),
    iat: issuedAt,
    exp: issuedAt + 5 * 60,
    aud: APPLE,
    sub: clientID,
  });
  const input = `${header}.${claims}`;
  return `${input}.${await signEs256(input, secret("APPLE_SIGN_IN_PRIVATE_KEY"))}`;
}

async function postForm(path: "token" | "revoke", form: URLSearchParams): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    return await fetch(`${APPLE}/auth/${path}`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: form,
      signal: controller.signal,
      redirect: "error",
    });
  } catch {
    throw new ApiError("AUTH_PROVIDER_UNAVAILABLE");
  } finally {
    clearTimeout(timer);
  }
}

interface AppleTokenResponse {
  id_token?: string;
  refresh_token?: string;
}

/** Exchanges one fresh code, proves it belongs to the current Apple identity, and revokes it. */
export async function revokeAppleAuthorization(
  authorizationCode: string,
  expectedSubject: string,
): Promise<void> {
  const clientID = secret("APPLE_SIGN_IN_CLIENT_ID");
  const signedSecret = await clientSecret();
  const exchange = await postForm("token", new URLSearchParams({
    client_id: clientID,
    client_secret: signedSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  }));

  if (exchange.status === 400) throw new ApiError("REAUTHENTICATION_FAILED");
  if (!exchange.ok) throw new ApiError("AUTH_PROVIDER_UNAVAILABLE");

  let tokens: AppleTokenResponse;
  try {
    tokens = await exchange.json() as AppleTokenResponse;
  } catch {
    throw new ApiError("AUTH_PROVIDER_UNAVAILABLE");
  }
  if (!tokens.id_token || !tokens.refresh_token) {
    throw new ApiError("REAUTHENTICATION_FAILED");
  }

  try {
    const { payload } = await jwtVerify(tokens.id_token, appleKeys, {
      issuer: APPLE,
      audience: clientID,
    });
    if (payload.sub !== expectedSubject) throw new ApiError("REAUTHENTICATION_FAILED");
  } catch (error) {
    if (error instanceof ApiError) throw error;
    throw new ApiError("REAUTHENTICATION_FAILED");
  }

  const revoked = await postForm("revoke", new URLSearchParams({
    client_id: clientID,
    client_secret: signedSecret,
    token: tokens.refresh_token,
    token_type_hint: "refresh_token",
  }));
  await revoked.body?.cancel();
  if (!revoked.ok) throw new ApiError("AUTH_PROVIDER_UNAVAILABLE");
}
