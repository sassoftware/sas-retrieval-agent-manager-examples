import { NextResponse } from "next/server";
import { getSsoAuthorizationUrl } from "@/services/sso";

export async function GET() {
  try {
    return NextResponse.redirect(await getSsoAuthorizationUrl());
  } catch (error) {
    console.error("Unable to start SSO login:", error);
    return new Response("SSO is not configured", { status: 500 });
  }
}
