/**
 * PKCE (Proof Key for Code Exchange) utility functions for OAuth 2.0 device code flow
 */

/**
 * Generate a cryptographically random PKCE code verifier
 * @returns A base64url-encoded random string
 */
export function generateCodeVerifier(): string {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64UrlEncode(array);
}

/**
 * Generate a code challenge from a code verifier using SHA-256
 * @param verifier The code verifier
 * @returns A promise that resolves to the base64url-encoded code challenge
 */
export async function generateCodeChallenge(verifier: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return base64UrlEncode(new Uint8Array(digest));
}

/**
 * Base64url encode a byte array (without padding)
 * @param buffer The byte array to encode
 * @returns The base64url-encoded string
 */
function base64UrlEncode(buffer: Uint8Array): string {
  const base64 = btoa(String.fromCharCode(...buffer));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}
