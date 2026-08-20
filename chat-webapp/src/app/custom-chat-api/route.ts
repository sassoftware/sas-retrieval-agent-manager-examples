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

function logQueryRequest(body: unknown, endpoint: string, queryParams: string) {
  if (!body || typeof body !== "object") {
    console.log("[chat-api] POST", JSON.stringify({ endpoint, queryParams, body }));
    return;
  }

  const loggedBody = JSON.parse(JSON.stringify(body, (_key, value) => {
    if (typeof value === "string" && value.startsWith("data:image/") && value.includes(";base64,")) {
      const [prefix, base64] = value.split(";base64,", 2);
      return `${prefix};base64,[redacted ${base64.length} chars]`;
    }
    return value;
  }));

  const redactedBody = JSON.parse(JSON.stringify(loggedBody, (key, value) => {
    if ((key === "data" || key === "base64") && typeof value === "string") {
      return `[redacted ${value.length} chars]`;
    }
    return value;
  }));

  console.log("[chat-api] POST", JSON.stringify({
    endpoint,
    queryParams,
    body: redactedBody,
  }, null, 2));
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'\\''`)}'`;
}

function logCurlRequest(url: string, requestBody: unknown, authorization: string | null) {
  const loggedBody = JSON.parse(JSON.stringify(requestBody, (_key, value) => {
    if (typeof value === "string" && value.startsWith("data:image/") && value.includes(";base64,")) {
      const [prefix, base64] = value.split(";base64,", 2);
      return `${prefix};base64,[redacted ${base64.length} chars]`;
    }
    return value;
  }));

  const redactedBody = JSON.parse(JSON.stringify(loggedBody, (key, value) => {
    if ((key === "data" || key === "base64") && typeof value === "string") {
      return `[redacted ${value.length} chars]`;
    }
    return value;
  }));

  const curl = [
    "curl -X POST",
    shellQuote(url),
    "-H 'Content-Type: application/json'",
    `-H ${shellQuote(authorization ? "Authorization: Bearer [redacted]" : "Authorization: [missing]")}`,
    `--data-raw ${shellQuote(JSON.stringify(redactedBody))}`,
  ].join(" ");

  console.log("[chat-api] curl (credentials and image data redacted):", curl);
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
  const requestBody = await request.json();
  logQueryRequest(requestBody, endpoint, queryString);
  logCurlRequest(fullUrl, requestBody, request.headers.get("authorization"));
  const body = JSON.stringify(requestBody);

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
