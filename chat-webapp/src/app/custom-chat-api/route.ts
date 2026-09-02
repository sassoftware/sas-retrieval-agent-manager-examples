import { NextRequest } from "next/server";
import { getFetchConfig } from "@/lib/fetch-config";
import { getSsoAccessToken } from "@/services/sso";

/**
 * Extract and forward only necessary headers to the backend API
 */
function getForwardHeaders(request: NextRequest): Headers {
  const headers = new Headers({
    "Content-Type": "application/json",
  });

  // Forward the Authorization header if present
  const authHeader = request.headers.get("authorization");
  if (authHeader) {
    headers.set("Authorization", authHeader);
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
  if (!request.headers.get("authorization")) {
    const token = await getSsoAccessToken();
    if (token) forwardHeaders.set("Authorization", `Bearer ${token}`);
  }

  const response = await fetch(url, {
    ...getFetchConfig(),
    headers: forwardHeaders,
    redirect: "manual",
  });

  // The RAM backend's oauth2-proxy gateway responds with a redirect to the
  // identity provider's login page (rather than a 401) when the request is
  // missing a valid Authorization header. `fetch` follows redirects by
  // default, so without `redirect: "manual"` this would silently end up
  // forwarding the login page's HTML back to the client as if it were a
  // `200` API response — the caller then fails to parse it as JSON with no
  // indication of what actually went wrong. Treat any redirect here as an
  // auth failure instead.
  if (response.type === "opaqueredirect" || (response.status >= 300 && response.status < 400)) {
    console.error("Chat API request redirected (likely unauthenticated) - Location:", response.headers.get("location"));
    return new Response(JSON.stringify({ error: "Not authenticated with RAM backend" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

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

  const forwardHeaders = getForwardHeaders(request);
  if (!request.headers.get("authorization")) {
    const token = await getSsoAccessToken();
    if (token) forwardHeaders.set("Authorization", `Bearer ${token}`);
  }

  const response = await fetch(fullUrl, {
    ...getFetchConfig(),
    method: "POST",
    headers: forwardHeaders,
    body: body,
    redirect: "manual",
  });

  // See the comment in GET() above: treat a redirect (the RAM gateway's way
  // of saying "not authenticated") as a 401 instead of silently following it
  // and forwarding the resulting login-page HTML as a bogus `200`.
  if (response.type === "opaqueredirect" || (response.status >= 300 && response.status < 400)) {
    console.error("Chat API request redirected (likely unauthenticated) - Location:", response.headers.get("location"));
    return new Response(JSON.stringify({ error: "Not authenticated with RAM backend" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

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
