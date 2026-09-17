import { NextResponse } from "next/server";
import { getFetchConfig } from "@/lib/fetch-config";

export async function POST(request: Request) {
  const { refresh_token } = await request.json();

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
      grant_type: "refresh_token",
      client_id: "sas-ram-api",
      refresh_token,
    }),
  });

  if (!response.ok) {
    return new Response("Token refresh failed", { status: 401 });
  }

  const data = await response.json();
  return NextResponse.json(data);
}
