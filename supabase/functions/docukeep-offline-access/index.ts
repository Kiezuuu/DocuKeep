import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!token) return json({ error: "Authentication required" }, 401);
    const url = Deno.env.get("SUPABASE_URL")!;
    const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user || !authData.user.email_confirmed_at) return json({ error: "A verified, active Supabase session is required." }, 401);
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from("profiles").select("id,full_name,email,role,status").eq("id", authData.user.id).maybeSingle();
    if (profileError) throw profileError;
    const role = String(profile?.role || "").toLowerCase();
    const status = String(profile?.status || "").toLowerCase();
    if (!profile || status !== "approved" || !["student", "teacher", "staff"].includes(role)) return json({ error: "This account is not approved for offline access." }, 403);
    if (role === "student" && !String(authData.user.email || "").toLowerCase().endsWith("@gmail.com")) return json({ error: "Student account email does not meet the existing account policy." }, 403);
    const body = await req.json().catch(() => ({}));
    const requestedDays = Number(body.days);
    const lifetime = Number.isFinite(requestedDays) ? Math.min(7, Math.max(1, Math.floor(requestedDays))) : 7;
    const now = new Date();
    const claims = { iss: "docukeep-offline-access", aud: "docukeep-browser", version: 1, packageId: crypto.randomUUID(), sub: authData.user.id, email: authData.user.email, full_name: profile.full_name, role: profile.role, status: "approved", permissions: ["cached_documents:read"], iat: Math.floor(now.getTime()/1000), exp: Math.floor(now.getTime()/1000)+lifetime*86400 };
    const privateJwkText = Deno.env.get("DOCUKEEP_OFFLINE_ED25519_PRIVATE_JWK");
    if (!privateJwkText) throw new Error("Offline signing key is not configured.");
    const signingKey = await crypto.subtle.importKey("jwk", JSON.parse(privateJwkText), { name: "Ed25519" }, false, ["sign"]);
    const payload = new TextEncoder().encode(JSON.stringify(claims));
    const signature = new Uint8Array(await crypto.subtle.sign("Ed25519", signingKey, payload));
    return json({ payload: b64url(payload), signature: b64url(signature), algorithm: "Ed25519", keyId: "docukeep-offline-v1" });
  } catch (error) { console.error("docukeep-offline-access error", error); return json({ error: "Could not prepare offline authorization." }, 500); }
});
