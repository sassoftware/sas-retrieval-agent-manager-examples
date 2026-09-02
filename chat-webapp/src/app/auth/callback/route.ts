import { NextResponse } from "next/server";
import { exchangeCode, getTrustedAppBaseUrl } from "@/services/sso";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");
  // Build redirects from the trusted, configured app origin rather than
  // `request.url` — behind a reverse proxy the latter can reflect an
  // internal host that the browser can't reach.
  const appUrl = getTrustedAppBaseUrl();
  if (error || !code || !state) {
    return NextResponse.redirect(new URL("?error=sso_failed", `${appUrl}/`));
  }

  try {
    await exchangeCode(code, state);
    return NextResponse.redirect(new URL(".", `${appUrl}/`));
  } catch (callbackError) {
    console.error("SSO callback failed:", callbackError instanceof Error ? callbackError.stack ?? callbackError.message : callbackError);
    return NextResponse.redirect(new URL("?error=sso_failed", `${appUrl}/`));
  }
}
