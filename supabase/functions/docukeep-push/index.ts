import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-docukeep-webhook-secret" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const expected = Deno.env.get("DOCUKEEP_WEBHOOK_SECRET");
    if (!expected || req.headers.get("x-docukeep-webhook-secret") !== expected) return new Response("Unauthorized", { status: 401 });
    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const publicKey = Deno.env.get("VAPID_PUBLIC_KEY")!;
    const privateKey = Deno.env.get("VAPID_PRIVATE_KEY")!;
    const subject = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com";
    const supabase = createClient(url, serviceKey, { auth: { persistSession: false } });
    webpush.setVapidDetails(subject, publicKey, privateKey);

    const payload = await req.json();
    const row = payload.record || payload;
    if (!row?.id || !row?.user_id) return new Response("Missing notification record", { status: 400 });
    const { data: subscriptions, error } = await supabase.from("docukeep_push_subscriptions").select("id,endpoint,subscription").eq("user_id", row.user_id);
    if (error) throw error;
    const SITE_URL = "https://docukeep.pages.dev/";

    const message = JSON.stringify({
        title: row.title || "DocuKeep update",
        body: row.message || "You have a new notification.",
        notification_id: row.id,
        tag: `docukeep-${row.id}`,
        url: row.related_document_id
            ? `${SITE_URL}?page=documents&document=${row.related_document_id}`
            : `${SITE_URL}?page=notifications`
    });
    const expired: string[] = [];
    let sent = 0;
    for (const sub of subscriptions || []) {
      try { await webpush.sendNotification(sub.subscription, message); sent++; }
      catch (e) { const status = (e as { statusCode?: number }).statusCode; if (status === 404 || status === 410) expired.push(sub.id); else console.error("Push send failed", status, e); }
    }
    if (expired.length) await supabase.from("docukeep_push_subscriptions").delete().in("id", expired);
    return new Response(JSON.stringify({ ok: true, sent, removedExpired: expired.length }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: error instanceof Error ? error.message : "Push delivery failed" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
