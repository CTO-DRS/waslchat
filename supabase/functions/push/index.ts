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

// مقارنة سرّية بزمن ثابت (تمنع تسريب السر حرفاً حرفاً عبر قياس زمن الاستجابة)
async function timingSafeEqual(a: string, b: string): Promise<boolean> {
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest("SHA-256", enc.encode(a)),
    crypto.subtle.digest("SHA-256", enc.encode(b)),
  ]);
  const va = new Uint8Array(ha);
  const vb = new Uint8Array(hb);
  let diff = 0;
  for (let i = 0; i < va.length; i++) diff |= va[i] ^ vb[i];
  return diff === 0;
}

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
  // حماية: لا يقبل إلا طلبات الـ Webhook التي تحمل السر (مقارنة بزمن ثابت)
  const provided = req.headers.get("x-webhook-secret") ?? "";
  if (!webhookSecret || !(await timingSafeEqual(provided, webhookSecret))) {
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

  // أصوات الاستطلاعات صامتة: لا إشعار لها إطلاقاً (المشغّل في ترحيل 022
  // يستثنيها أصلاً — هذا حاجز ثانٍ إن تغيّر المشغّل يوماً)
  if (m.type === "poll_vote") return new Response("ignored");

  // المكتومون لا يصلهم إشعار (muted_until في المستقبل، أو "infinity" = دائماً)
  const now = Date.now();
  const isMuted = (u: string | null) =>
    !!u && (u === "infinity" || new Date(u).getTime() > now);
  const ids = (members ?? []).filter((r) => !isMuted(r.muted_until)).map((r) => r.user_id);
  if (!ids.length) return new Response("no recipients");

  const { data: tokens } = await db.from("device_tokens").select("token, user_id").in("user_id", ids);
  if (!tokens?.length) return new Response("no devices");

  const name = sender?.display_name ?? sender?.username ?? "وصل شات";
  const title = conv?.is_group ? `${name} · ${conv.title ?? "مجموعة"}` : name;
  // الرسائل المشفرة بين الطرفين (بادئة v1.) لا يفكها السيرفر أبداً: نص إشعار عام
  const encrypted = typeof m.content === "string" && m.content.startsWith("v1.");
  const body = m.type === "poll"
    ? "📊 استطلاع رأي"
    : m.type === "image"
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

  // جسم مخصّص لكل مستقبل — بيانات وصفية فقط، بلا قراءة أي محتوى:
  // mentions (ترحيل 023): الخادم يعرف من أُشير إليه دون نص الإشارة
  // reply_to: موجود أصلاً — الخادم يعرف من ردّ على من
  const mentions: string[] = Array.isArray(m.mentions) ? m.mentions : [];
  let replySender: string | null = null;
  if (m.reply_to) {
    const { data } = await db.from("messages").select("sender_id")
      .eq("id", m.reply_to).maybeSingle();
    replySender = data?.sender_id ?? null;
  }
  const bodyFor = (uid: string) =>
    mentions.includes(uid)
      ? `🔔 أشار إليك ${name}`
      : replySender === uid
      ? "↩️ ردّ على رسالتك"
      : body;

  const access = await googleAccessToken();
  await Promise.all(tokens.map(async ({ token, user_id }) => {
    let r: Response;
    try {
      r = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token,
              notification: { title, body: bodyFor(user_id) },
              data: { conversation_id: m.conversation_id },
              android: { priority: "high" },
              apns: { payload: { aps: { sound: "default" } } },
            },
          }),
        },
      );
    } catch (e) {
      // انقطاع مؤقت مع Google: لا نحذف الرمز، ولا نُفشل بقية الأجهزة
      console.error("fcm fetch failed:", e);
      return;
    }
    // جهاز لم يعد مسجلاً (404/410) أو رمز غير صالح (400 UNREGISTERED/INVALID_ARGUMENT):
    // نحذف رمزه حتى لا تتكرر محاولات الفشل وتتراكم التكلفة
    if (r.status === 404 || r.status === 410) {
      await db.from("device_tokens").delete().eq("token", token);
      return;
    }
    if (r.status === 400) {
      const t = await r.text().catch(() => "");
      if (t.includes("UNREGISTERED") || t.includes("INVALID_ARGUMENT")) {
        await db.from("device_tokens").delete().eq("token", token);
      }
    }
  }));

  return new Response("ok");
});
