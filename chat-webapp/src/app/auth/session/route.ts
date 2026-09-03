import { NextResponse } from "next/server";
import { getSsoSession, getSsoUserInfo } from "@/services/sso";

export async function GET() {
  const headers = { "Cache-Control": "no-store" };
  try {
    const session = await getSsoSession();
    if (!session) return NextResponse.json({ authenticated: false, user: null }, { headers });

    let user = null;
    try {
      user = await getSsoUserInfo();
    } catch {
      // User profile data is optional; a valid token still authenticates the app.
    }

    return NextResponse.json({ authenticated: true, user }, { headers });
  } catch {
    return NextResponse.json({ authenticated: false, user: null }, { headers });
  }
}
