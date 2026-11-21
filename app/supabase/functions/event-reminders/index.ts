// وصل شات: تذكيرات أحداث المجتمع — إشعار FCM لأعضاء المجتمع قبل بدء الحدث بالمدة المحددة
// يستدعيه pg_cron كل 10 دقائق (024_community_events.sql) بالسر WEBHOOK_SECRET نفسه.
// الحدث المستحق: لديه تذكير (remind_minutes > 0)، ولم يُذكَّر بعد (reminded_at null)،
// وبلغ وقت تذكيره (الآن ≥ البدء − التذكير) ولم يبدأ بعد — يُؤشَّر مرة واحدة فلا يتكرر الإشعار.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

let cached: { token: string; exp: number } | null = null;

async function googleAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const j = await res.json();
  cached = { token: j.access_token, exp: now + (j.expires_in ?? 3600) };
  return cached.token;
}

/// «بعد X» بالعربية — دقة الدقائق تكفي (دورة cron كل 10 دقائق)
function afterText(ms: number): string {
  const m = Math.max(0, Math.round(ms / 60000));
  if (m < 1) return "الآن";
  if (m === 1) return "بعد دقيقة واحدة";
  if (m === 2) return "بعد دقيقتين";
  if (m <= 10) return `بعد ${m} دقائق`;
  if (m < 60) return `بعد ${m} دقيقة`;
  const h = Math.round(m / 60);
  if (h === 1) return "بعد ساعة واحدة";
  if (h === 2) return "بعد ساعتين";
  if (h <= 10) return `بعد ${h} ساعات`;
  if (h < 24) return `بعد ${h} ساعة`;
  const d = Math.round(h / 24);
  return d === 1 ? "بعد يوم" : `بعد ${d} يوم`;
}

Deno.serve(async (req) => {
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("unauthorized", { status: 401 });
  }

  const now = new Date();
  // نافذة الاستحقاق: البدء خلال الساعات القادمة (أقصى تذكير 24 ساعة) أو بدأ حديثاً ولم يُذكَّر
  const from = new Date(now.getTime() - 2 * 86400_000).toISOString();
  const to = new Date(now.getTime() + 25 * 3600_000).toISOString();
  const { data: due, error } = await db
    .from("community_events")
    .select("id, community_id, title, starts_at, remind_minutes")
    .isNull("reminded_at")
    .gt("remind_minutes", 0)
    .gte("starts_at", from)
    .lte("starts_at", to);
  if (error) return new Response(error.message, { status: 500 });

  let sent = 0;
  for (const ev of due ?? []) {
    const starts = new Date(ev.starts_at as string);
    const lead = (ev.remind_minutes as number) ?? 0;
    const fireAt = starts.getTime() - lead * 60_000;
    if (Date.now() < fireAt) continue; // تذكيره لم يحِن بعد — لا نؤشر

    // نؤشر التذكير أولاً (مرة واحدة لكل حدث) — بدأ الحدث بلا تذكير؟ نغلقه بلا إشعار
    const { error: markErr } = await db
      .from("community_events")
      .update({ reminded_at: now.toISOString() })
      .eq("id", ev.id as string)
      .isNull("reminded_at");
    if (markErr || starts.getTime() <= Date.now()) continue;

    const { data: members } = await db
      .from("community_members")
      .select("user_id")
      .eq("community_id", ev.community_id as string);
    const ids = (members ?? []).map((r) => r.user_id as string);
    if (!ids.length) continue;

    const { data: tokens } = await db.from("device_tokens").select("token").in("user_id", ids);
    if (!tokens?.length) continue;

    const { data: comm } = await db
      .from("communities")
      .select("name")
      .eq("id", ev.community_id as string)
      .single();
    const commName = comm?.name ?? "مجتمع";
    const title = `📅 ${ev.title}`;
    const body = `${commName} · يبدأ ${afterText(starts.getTime() - Date.now())}`;

    const access = await googleAccessToken();
    await Promise.all(tokens.map(async ({ token }) => {
      const r = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body },
              data: { event_id: String(ev.id), community_id: String(ev.community_id) },
              android: {
                priority: "high",
                collapse_key: `event-${ev.id}`,
                notification: { channel_id: "messages", tag: `event-${ev.id}` },
              },
              apns: {
                headers: { "apns-collapse-id": `event-${ev.id}` },
                payload: { aps: { sound: "default", "thread-id": `event-${ev.id}` } },
              },
            },
          }),
        },
      );
      // جهاز لم يعد مسجلاً: نحذف رمزه (نمط دالة push)
      if (r.status === 404) await db.from("device_tokens").delete().eq("token", token);
      else if (r.ok) sent++;
    }));
  }

  return new Response(JSON.stringify({ due: (due ?? []).length, sent }), {
    headers: { "Content-Type": "application/json" },
  });
});
