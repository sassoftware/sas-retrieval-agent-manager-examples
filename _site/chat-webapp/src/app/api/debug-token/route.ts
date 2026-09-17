import { NextRequest, NextResponse } from "next/server";

/**
 * Debug endpoint to decode and display JWT token contents
 * This helps troubleshoot group membership and other claims
 */
export async function GET(request: NextRequest) {
  const authHeader = request.headers.get("authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return NextResponse.json(
      { error: "No authorization header found" },
      { status: 401 },
    );
  }

  const token = authHeader.substring(7);

  try {
    // Decode JWT (note: this doesn't verify signature, just decodes)
    const parts = token.split(".");
    if (parts.length !== 3) {
      return NextResponse.json(
        { error: "Invalid JWT format" },
        { status: 400 },
      );
    }

    const header = JSON.parse(
      Buffer.from(parts[0], "base64url").toString("utf-8"),
    );
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf-8"),
    );

    return NextResponse.json({
      header,
      payload,
      note: "Check the 'groups', 'realm_access', or 'resource_access' fields for group membership",
    });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to decode token", details: String(error) },
      { status: 500 },
    );
  }
}
