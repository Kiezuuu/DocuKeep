import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...cors, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes))
  .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");

function canonicalDeviceJwk(jwk: JsonWebKey) {
  return JSON.stringify({ crv: jwk.crv, kty: jwk.kty, x: jwk.x, y: jwk.y });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);

    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const privateJwkText = Deno.env.get("DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK");
    if (!url || !anon || !serviceKey || !privateJwkText) throw new Error("Required server configuration is missing.");

    const authClient = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user || !authData.user.email_confirmed_at) {
      return json({ error: "A verified Supabase session is required." }, 401);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from("profiles")
      .select("id,full_name,email,role,status").eq("id", authData.user.id).maybeSingle();
    if (profileError) throw profileError;
    const role = String(profile?.role || "").toLowerCase();
    const status = String(profile?.status || "").toLowerCase();
    if (!profile || status !== "approved" || !["student", "teacher", "staff"].includes(role)) {
      return json({ error: "This account is not approved for offline access." }, 403);
    }
    if (role === "student" && !String(authData.user.email || "").toLowerCase().endsWith("@gmail.com")) {
      return json({ error: "Student account email does not meet the existing account policy." }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const devicePublicKey = body?.devicePublicKey as JsonWebKey | undefined;
    if (!devicePublicKey || devicePublicKey.kty !== "EC" || devicePublicKey.crv !== "P-256" ||
        typeof devicePublicKey.x !== "string" || typeof devicePublicKey.y !== "string" ||
        devicePublicKey.d || devicePublicKey.x.length < 40 || devicePublicKey.y.length < 40) {
      return json({ error: "A valid device public key is required." }, 400);
    }
    // Importing validates that the supplied point is a valid P-256 public key.
    await crypto.subtle.importKey("jwk", devicePublicKey, { name: "ECDH", namedCurve: "P-256" }, true, []);
    const thumbprintBytes = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonicalDeviceJwk(devicePublicKey))));
    const now = Math.floor(Date.now() / 1000);
    const claims = {
      iss: "docukeep-offline-access",
      aud: "docukeep-browser",
      version: 2,
      jti: crypto.randomUUID(),
      sub: authData.user.id,
      email: authData.user.email,
      full_name: profile.full_name,
      role: profile.role,
      status: "approved",
      deviceKeyThumbprint: b64url(thumbprintBytes),
      permissions: ["cached_documents:read"],
      iat: now,
      exp: now + 7 * 86400,
    };

    const signingKey = await crypto.subtle.importKey("jwk", JSON.parse(privateJwkText), { name: "Ed25519" }, false, ["sign"]);
    const payload = new TextEncoder().encode(JSON.stringify(claims));
    const signature = new Uint8Array(await crypto.subtle.sign("Ed25519", signingKey, payload));
    return json({
      payload: b64url(payload),
      signature: b64url(signature),
      algorithm: "Ed25519",
      keyId: "docukeep-offline-v2",
      expiresAt: claims.exp,
    });
  } catch (error) {
    console.error("docukeep-offline-access error", error);
    return json({ error: "Could not provision offline authorization." }, 500);
  }
});
