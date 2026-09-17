import { NextResponse } from "next/server";
import { getFetchConfig } from "@/lib/fetch-config";

interface TokenResponse {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
  scope: string;
}

interface ErrorResponse {
  error: string;
  error_description?: string;
}

/**
 * Poll the token endpoint to check if the user has authorized the device
 */
export async function POST(request: Request) {
  const { device_code, code_verifier } = await request.json();

  if (!device_code || !code_verifier) {
    return new Response("Missing device_code or code_verifier", {
      status: 400,
    });
  }

  const ramUrl = process.env.RAM_URL?.replace(/\/+$/, "");
  if (!ramUrl) {
    return new Response("RAM_URL not configured", {
      status: 500,
    });
  }
  const authBaseUrl = `${ramUrl}/SASRetrievalAgentManager`;

  const tokenUrl = `${authBaseUrl}/auth/realms/sas-iot/protocol/openid-connect/token`;

  const response = await fetch(tokenUrl, {
    ...getFetchConfig(),
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:device_code",
      device_code,
      client_id: "sas-ram-api",
      code_verifier,
    }),
  });

  const data = await response.json();

  if (!response.ok) {
    const errorData = data as ErrorResponse;
    // Return specific error codes that the client can handle
    // authorization_pending: user hasn't authorized yet
    // slow_down: client is polling too frequently
    // access_denied: user denied the authorization
    // expired_token: device code has expired
    return NextResponse.json(errorData, { status: response.status });
  }

  const tokenData = data as TokenResponse;

  return NextResponse.json(tokenData);
}
