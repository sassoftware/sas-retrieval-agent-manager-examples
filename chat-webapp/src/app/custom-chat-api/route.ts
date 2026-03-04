import { NextRequest } from "next/server";
import { getFetchConfig } from "@/lib/fetch-config";

/**
 * Extract and forward only necessary headers to the backend API
 */
function getForwardHeaders(request: NextRequest): HeadersInit {
  const headers: HeadersInit = {
    "Content-Type": "application/json",
  };

  // Forward the Authorization header if present
  const authHeader = request.headers.get("authorization");
  if (authHeader) {
    headers["Authorization"] = authHeader;
  }

  return headers;
}

export async function GET(request: NextRequest) {
  const ramUrl = process.env.RAM_URL?.replace(/\/+$/, "");
  if (!ramUrl) {
    return new Response("RAM_URL not configured", { status: 500 });
  }
  const apiUrl = `${ramUrl}/SASRetrievalAgentManager/api/v1`;
  const url = apiUrl + request.nextUrl.searchParams.get("endpoint");

  const forwardHeaders = getForwardHeaders(request);

  const response = await fetch(url, {
    ...getFetchConfig(),
    headers: forwardHeaders,
  });

  if (!response.ok) {
    console.error("Chat API request failed - Status:", response.status);
    const errorText = await response.text();
    console.error("Response:", errorText);
    return new Response(errorText, {
      status: response.status,
      headers: response.headers,
    });
  }

  return response;
}

export async function POST(request: NextRequest) {
  const ramUrl = process.env.RAM_URL?.replace(/\/+$/, "");
  if (!ramUrl) {
    return new Response("RAM_URL not configured", { status: 500 });
  }
  const apiUrl = `${ramUrl}/SASRetrievalAgentManager/api/v1`;
  const endpoint = request.nextUrl.searchParams.get("endpoint");
  if (!endpoint) {
    return new Response("Endpoint not specified", { status: 400 });
  }
  const url = apiUrl + endpoint;

  const searchParams = new URLSearchParams(request.nextUrl.searchParams);
  searchParams.delete("endpoint");
  const queryString = searchParams.toString();
  const fullUrl = queryString ? `${url}?${queryString}` : url;
  const body = JSON.stringify(await request.json());

  const response = await fetch(fullUrl, {
    ...getFetchConfig(),
    method: "POST",
    headers: getForwardHeaders(request),
    body: body,
  });

  if (!response.ok) {
    console.error("Chat API request failed - Status:", response.status);
    const errorText = await response.text();
    console.error("Response:", errorText);
    return new Response(errorText, {
      status: response.status,
      headers: response.headers,
    });
  }

  return response;
}
