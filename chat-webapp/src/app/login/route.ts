import { NextResponse } from "next/server";
import { generateCodeVerifier, generateCodeChallenge } from "@/lib/pkce";
import { getFetchConfig } from "@/lib/fetch-config";

interface DeviceAuthResponse {
  device_code: string;
  user_code: string;
  verification_uri: string;
  verification_uri_complete?: string;
  expires_in: number;
  interval: number;
}

/**
 * Initiate device code authorization flow
 */
export async function POST() {
  const ramUrl = process.env.RAM_URL?.replace(/\/+$/, "");
  if (!ramUrl) {
    return new Response("RAM_URL not configured", {
      status: 500,
    });
  }
  const authBaseUrl = `${ramUrl}/SASRetrievalAgentManager`;

  // Generate PKCE parameters
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);

  const deviceAuthUrl = `${authBaseUrl}/auth/realms/sas-iot/protocol/openid-connect/auth/device`;

  const response = await fetch(deviceAuthUrl, {
    ...getFetchConfig(),
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: "sas-ram-api",
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
      scope: "openid",
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error("Device authorization failed:", errorText);
    return new Response("Device authorization failed", {
      status: response.status,
    });
  }

  const data: DeviceAuthResponse = await response.json();

  // Return the device code info along with the code verifier (needed for token exchange)
  return NextResponse.json({
    ...data,
    code_verifier: codeVerifier,
  });
}
