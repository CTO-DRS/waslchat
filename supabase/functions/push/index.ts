// وصل شات: إرسال إشعار لكل عضو عند وصول رسالة جديدة
// يُستدعى من Database Webhook على جدول messages (Insert)
// الأسرار المطلوبة: FCM_SERVICE_ACCOUNT (ملف JSON من Firebase) و WEBHOOK_SECRET

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

Deno.serve(async (req) => {
  // حماية: لا يقبل إلا طلبات الـ Webhook التي تحمل السر
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
    return new Response("unauthorized", { status: 401 });
  }

  const payload = await req.json().catch(() => null);
  const id = payload?.record?.id;
  if (payload?.type !== "INSERT" || !id) return new Response("ignored");

  // نقرأ الرسالة من قاعدة البيانات بدل الثقة بمحتوى الطلب
  const { data: m } = await db.from("messages").select("*").eq("id", id).single();
  if (!m) return new Response("not found", { status: 404 });

  const [{ data: sender }, { data: conv }, { data: members }] = await Promise.all([
    db.from("profiles").select("username, display_name").eq("id", m.sender_id).single(),
    db.from("conversations").select("is_group, title").eq("id", m.conversation_id).single(),
    db.from("conversation_participants").select("user_id, muted_until")
      .eq("conversation_id", m.conversation_id).neq("user_id", m.sender_id),
  ]);

  // المكتومون لا يصلهم إشعار (muted_until في المستقبل، أو "infinity" = دائماً)
  const now = Date.now();
  const isMuted = (u: string | null) =>
    !!u && (u === "infinity" || new Date(u).getTime() > now);
  const ids = (members ?? []).filter((r) => !isMuted(r.muted_until)).map((r) => r.user_id);
  if (!ids.length) return new Response("no recipients");

  const { data: tokens } = await db.from("device_tokens").select("token").in("user_id", ids);
  if (!tokens?.length) return new Response("no devices");

  const name = sender?.display_name ?? sender?.username ?? "وصل شات";
  // اسم المجموعة مشفر من التطبيق (v1.) منذ 0.10.0 — السيرفر لا يفكه أبداً: نص عام بدله
  const encTitle = typeof conv?.title === "string" && /^v1\./.test(conv.title);
  const gTitle = encTitle ? "مجموعة" : conv?.title ?? "مجموعة";
  const title = conv?.is_group ? `${name} · ${gTitle}` : name;
  // الرسائل المشفرة بين الطرفين (v1 ثابت أو v2 متدرج) لا يفكها السيرفر أبداً: نص إشعار عام
  const encrypted = typeof m.content === "string" && /^v[123]\./.test(m.content);
  const body = m.type === "image"
    ? "📷 صورة"
    : m.type === "voice"
    ? "🎤 رسالة صوتية"
    : m.type === "video"
    ? "🎬 فيديو"
    : m.type === "file"
    ? "📎 ملف"
    : encrypted
    ? "🔒 رسالة مشفرة"
    : String(m.content ?? "").slice(0, 140);

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
            data: { conversation_id: m.conversation_id },
            android: {
              priority: "high",
              // تجميع إشعارات المحادثة الواحدة بدل تراكمها،
              // والتوجيه إلى قناة «الرسائل» التي يجهزها التطبيق بأهمية عالية
              collapse_key: m.conversation_id,
              notification: { channel_id: "messages", tag: m.conversation_id },
            },
            apns: {
              headers: { "apns-collapse-id": m.conversation_id },
              payload: { aps: { sound: "default", "thread-id": String(m.conversation_id) } },
            },
          },
        }),
      },
    );
    // جهاز لم يعد مسجلاً: نحذف رمزه
    if (r.status === 404) await db.from("device_tokens").delete().eq("token", token);
  }));

  return new Response("ok");
});
