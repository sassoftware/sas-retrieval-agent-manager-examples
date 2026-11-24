import { createHash, randomBytes } from "node:crypto";
import { cookies } from "next/headers";
import { getFetchConfig } from "@/lib/fetch-config";

const SESSION_COOKIE = "ram_sso_session";
const STATE_COOKIE = "ram_sso_state";
const VERIFIER_COOKIE = "ram_sso_verifier";
const SESSION_MAX_AGE = 60 * 60 * 24 * 30;

interface TokenResponse {
  access_token: string;
  id_token?: string;
  refresh_token?: string;
  expires_in: number;
  token_type: string;
  scope?: string;
}

interface Session {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  expiresAt: number;
}

export interface SsoUserInfo {
  name?: string;
  preferred_username?: string;
  email?: string;
}

/**
 * Server-side session store, keyed by an opaque random session ID.
 *
 * The `ram_sso_session` cookie holds only this small random ID rather than
 * the token bundle itself. Keycloak tokens can easily carry 1-2KB+ of claims
 * each, and once encoded, storing them directly in a cookie routinely blows
 * past browsers' ~4096-byte per-cookie limit. Browsers silently drop
 * oversized cookies — no error, no warning — which would make SSO logins
 * appear to succeed (the server-side exchange completes fine) while the user
 * gets bounced right back to the sign-in page because the cookie never
 * actually got stored.
 *
 * Caveat: this in-memory store does not survive a server restart and is not
 * shared across multiple instances/replicas. For a production, multi-instance
 * deployment this should be backed by a shared store (e.g. Redis) instead.
 */
// Next.js can evaluate route handlers in separate module contexts during
// `next dev`. Keep the store on globalThis so the callback route and API
// proxy see the same sessions within a single server process.
const globalForSso = globalThis as typeof globalThis & {
  __ramSsoSessionStore?: Map<string, Session>;
};
const sessionStore = (globalForSso.__ramSsoSessionStore ??= new Map<string, Session>());

function pruneExpiredSessions(): void {
  const now = Date.now();
  for (const [id, session] of sessionStore) {
    if (session.expiresAt <= now) sessionStore.delete(id);
  }
}

function storeSession(session: Session, existingId?: string): string {
  pruneExpiredSessions();
  const id = existingId ?? randomBytes(32).toString("base64url");
  sessionStore.set(id, session);
  return id;
}

function getAuthConfig() {
  const ramUrl = process.env.RAM_URL?.replace(/\/+$/, "");
  const secret = process.env.KEYCLOAK_SESSION_SECRET;
  if (!ramUrl || !secret) {
    throw new Error("RAM_URL and KEYCLOAK_SESSION_SECRET must be configured");
  }

  const baseUrl = `${ramUrl}/SASRetrievalAgentManager`;
  const configuredRedirectUri = process.env.KEYCLOAK_REDIRECT_URI || "http://localhost:3000/auth/callback";
  const redirectUri = addBasePathToUrl(configuredRedirectUri);
  return {
    clientId: process.env.KEYCLOAK_CLIENT_ID || "sas-ram-api",
    clientSecret: process.env.KEYCLOAK_CLIENT_SECRET,
    redirectUri,
    authorizationUrl: `${baseUrl}/auth/realms/sas-iot/protocol/openid-connect/auth`,
    tokenUrl: `${baseUrl}/auth/realms/sas-iot/protocol/openid-connect/token`,
    userInfoUrl: `${baseUrl}/auth/realms/sas-iot/protocol/openid-connect/userinfo`,
    logoutUrl: `${baseUrl}/auth/realms/sas-iot/protocol/openid-connect/logout`,
    secret,
  };
}

function addBasePathToUrl(value: string): string {
  const trimmed = (process.env.NEXT_PUBLIC_BASE_PATH || "").trim().replace(/\/+$/, "");
  const basePath = trimmed && !trimmed.startsWith("/") ? `/${trimmed}` : trimmed;
  if (!basePath) return value;

  const url = new URL(value);
  if (url.pathname === basePath || url.pathname.startsWith(`${basePath}/`)) return value;
  url.pathname = `${basePath}${url.pathname.startsWith("/") ? url.pathname : `/${url.pathname}`}`;
  return url.toString();
}

function secureCookie(): boolean {
  return (process.env.KEYCLOAK_REDIRECT_URI || "").startsWith("https://");
}

/**
 * The externally-reachable origin for this app, derived from the configured
 * `KEYCLOAK_REDIRECT_URI` rather than an incoming request's own URL. Behind a
 * reverse proxy/ingress, `request.url` inside a route handler can reflect an
 * internal host/port instead of the public hostname users are actually on,
 * which would send post-login/post-logout redirects to an unreachable
 * address. The redirect URI is the one value we know is the true public
 * origin, since it must exactly match what's registered with the identity
 * provider.
 */
export function getTrustedAppOrigin(): string {
  const { redirectUri } = getAuthConfig();
  return new URL(redirectUri).origin;
}

export function getTrustedAppBaseUrl(): string {
  const { redirectUri } = getAuthConfig();
  const callbackUrl = new URL(redirectUri);
  callbackUrl.pathname = callbackUrl.pathname.replace(/\/auth\/callback\/?$/, "") || "/";
  callbackUrl.search = "";
  callbackUrl.hash = "";
  return callbackUrl.toString().replace(/\/$/, "");
}

export function getConfiguredPostLogoutRedirectUri(): string {
  const configured = process.env.KEYCLOAK_POST_LOGOUT_REDIRECT_URI;
  return addBasePathToUrl(configured || `${getTrustedAppBaseUrl()}/`);
}

export function createPkceVerifier(): string {
  return randomBytes(32).toString("base64url");
}

export async function createPkceChallenge(verifier: string): Promise<string> {
  return createHash("sha256").update(verifier).digest("base64url");
}

export async function getSsoAuthorizationUrl(): Promise<string> {
  const config = getAuthConfig();
  const state = randomBytes(32).toString("base64url");
  const verifier = createPkceVerifier();
  const challenge = await createPkceChallenge(verifier);
  const cookieStore = await cookies();

  cookieStore.set(STATE_COOKIE, state, { httpOnly: true, secure: secureCookie(), sameSite: "lax", maxAge: 600, path: "/" });
  cookieStore.set(VERIFIER_COOKIE, verifier, { httpOnly: true, secure: secureCookie(), sameSite: "lax", maxAge: 600, path: "/" });

  return `${config.authorizationUrl}?${new URLSearchParams({
    client_id: config.clientId,
    response_type: "code",
    redirect_uri: config.redirectUri,
    scope: "openid",
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
  })}`;
}

export async function exchangeCode(code: string, state: string): Promise<void> {
  const config = getAuthConfig();
  const cookieStore = await cookies();
  const expectedState = cookieStore.get(STATE_COOKIE)?.value;
  const verifier = cookieStore.get(VERIFIER_COOKIE)?.value;
  if (!expectedState || expectedState !== state || !verifier) {
    throw new Error("Invalid SSO callback state");
  }

  const body: Record<string, string> = {
    grant_type: "authorization_code",
    client_id: config.clientId,
    code,
    redirect_uri: config.redirectUri,
    code_verifier: verifier,
  };
  if (config.clientSecret) body.client_secret = config.clientSecret;

  let response: Response;
  try {
    response = await fetch(config.tokenUrl, {
      ...getFetchConfig(),
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(body),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (fetchError) {
    throw new Error(`SSO token exchange request failed reaching ${config.tokenUrl}: ${(fetchError as Error).message}`);
  }
  if (!response.ok) {
    const errorBody = await response.text().catch(() => "<unreadable body>");
    throw new Error(`SSO token exchange failed (${response.status} ${response.statusText}): ${errorBody}`);
  }

  const tokens = (await response.json()) as TokenResponse;
  const sessionId = storeSession({
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    idToken: tokens.id_token,
    expiresAt: Date.now() + tokens.expires_in * 1000,
  });
  cookieStore.set(SESSION_COOKIE, sessionId, { httpOnly: true, secure: secureCookie(), sameSite: "lax", maxAge: SESSION_MAX_AGE, path: "/" });
  cookieStore.delete(STATE_COOKIE);
  cookieStore.delete(VERIFIER_COOKIE);
}

export async function getSsoSession(): Promise<Session | null> {
  const cookieStore = await cookies();
  const sessionId = cookieStore.get(SESSION_COOKIE)?.value;
  if (!sessionId) return null;
  pruneExpiredSessions();
  return sessionStore.get(sessionId) ?? null;
}

export async function getSsoAccessToken(): Promise<string | null> {
  const session = await getSsoSession();
  if (!session) return null;
  if (session.expiresAt > Date.now() + 60_000) return session.accessToken;
  if (!session.refreshToken) return null;

  const config = getAuthConfig();
  const body: Record<string, string> = {
    grant_type: "refresh_token",
    client_id: config.clientId,
    refresh_token: session.refreshToken,
  };
  if (config.clientSecret) body.client_secret = config.clientSecret;
  const response = await fetch(config.tokenUrl, {
    ...getFetchConfig(),
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(body),
  });
  if (!response.ok) return null;

  const tokens = (await response.json()) as TokenResponse;
  const cookieStore = await cookies();
  const existingSessionId = cookieStore.get(SESSION_COOKIE)?.value;
  const sessionId = storeSession(
    {
      accessToken: tokens.access_token,
      refreshToken: tokens.refresh_token || session.refreshToken,
      idToken: tokens.id_token || session.idToken,
      expiresAt: Date.now() + tokens.expires_in * 1000,
    },
    existingSessionId,
  );
  cookieStore.set(SESSION_COOKIE, sessionId, { httpOnly: true, secure: secureCookie(), sameSite: "lax", maxAge: SESSION_MAX_AGE, path: "/" });
  return tokens.access_token;
}

export async function getSsoLogoutUrl(postLogoutRedirectUri: string): Promise<string | null> {
  const session = await getSsoSession();
  const { clientId, logoutUrl } = getAuthConfig();
  const params = new URLSearchParams({
    client_id: clientId,
    post_logout_redirect_uri: postLogoutRedirectUri,
  });
  if (session?.idToken) params.set("id_token_hint", session.idToken);
  return `${logoutUrl}?${params.toString()}`;
}

export async function getSsoUserInfo(): Promise<SsoUserInfo | null> {
  const accessToken = await getSsoAccessToken();
  if (!accessToken) return null;

  const { userInfoUrl } = getAuthConfig();
  const response = await fetch(userInfoUrl, {
    ...getFetchConfig(),
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!response.ok) return null;

  const user = (await response.json()) as Record<string, unknown>;
  return {
    name: typeof user.name === "string" ? user.name : undefined,
    preferred_username: typeof user.preferred_username === "string" ? user.preferred_username : undefined,
    email: typeof user.email === "string" ? user.email : undefined,
  };
}

export async function clearSsoSession(): Promise<void> {
  const cookieStore = await cookies();
  const sessionId = cookieStore.get(SESSION_COOKIE)?.value;
  if (sessionId) sessionStore.delete(sessionId);
  for (const cookieName of [SESSION_COOKIE, STATE_COOKIE, VERIFIER_COOKIE]) {
    cookieStore.set(cookieName, "", {
      httpOnly: true,
      secure: secureCookie(),
      sameSite: "lax",
      expires: new Date(0),
      maxAge: 0,
      path: "/",
    });
  }
}
