import { NextResponse } from "next/server";
import { clearSsoSession, getConfiguredPostLogoutRedirectUri, getSsoLogoutUrl } from "@/services/sso";

export async function POST() {
  const redirectUri = getConfiguredPostLogoutRedirectUri();
  const logoutUrl = await getSsoLogoutUrl(redirectUri);
  await clearSsoSession();
  return NextResponse.json({ ok: true, logoutUrl }, { headers: { "Cache-Control": "no-store" } });
}
