// وصل شات: إرسال إشعار لكل عضو عند وصول رسالة جديدة + إشعار «مكالمة واردة» (0.17.0)
// يُستدعى من Database Webhook على جدول messages وجدول calls (Insert)
// الأسرار المطلوبة: FCM_SERVICE_ACCOUNT (ملف JSON من Firebase) و WEBHOOK_SECRET
// صيغة الطلب: { type:'INSERT', table:'messages'|'calls', record:{id,...} }
// — جدول messages يتوافق مع الصيغة القديمة (بلا table أو table='messages').
//
// المرحلة 12 (0.28.0): إشعارات المتصفح الفورية — Web Push مستقل عن Firebase.
// بعد إرسال FCM تنبّه دالة notifyWebPushSubs اشتراكات web_push_subscriptions
// للمستلمين أنفسهم بنفس القرارات (الكتوم وجرس القنوات) وبحمولة نص إشعار عام
// حرفياً — المحتوى المشفر لا يمر هنا إطلاقاً («🔒 رسالة مشفرة» بدله).
// الأسرار الجديدة (وفق RUNBOOK §3.13): WEB_PUSH_VAPID_PRIVATE_KEY (PKCS8
// base64 من secrets/vapid_private_key.txt) و WEB_PUSH_VAPID_SUBJECT (mailto:).
// إن لم يُضبط السر: يُتخطى إرسال الويب بصمت — أندرويد يعمل كما كان.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");
const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";
const vapidPrivateB64 = Deno.env.get("WEB_PUSH_VAPID_PRIVATE_KEY") ?? "";
const vapidSubject = Deno.env.get("WEB_PUSH_VAPID_SUBJECT") ?? "";
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

  if (payload?.table === "calls") return notifyCall(id);
  return notifyMessage(id);
});

// ---------- إشعار رسالة جديدة (المنطق الأصلي كما هو) ----------
async function notifyMessage(id: string): Promise<Response> {
  // نقرأ الرسالة من قاعدة البيانات بدل الثقة بمحتوى الطلب
  const { data: m } = await db.from("messages").select("*").eq("id", id).single();
  if (!m) return new Response("not found", { status: 404 });

  const [{ data: sender }, { data: conv }, { data: members }] = await Promise.all([
    db.from("profiles").select("username, display_name").eq("id", m.sender_id).single(),
    db.from("conversations").select("is_group, title, kind").eq("id", m.conversation_id).single(),
    db.from("conversation_participants").select("user_id, muted_until, bell")
      .eq("conversation_id", m.conversation_id).neq("user_id", m.sender_id),
  ]);

  // المكتومون لا يصلهم إشعار (muted_until في المستقبل، أو "infinity" = دائماً)
  const now = Date.now();
  const isMuted = (u: string | null) =>
    !!u && (u === "infinity" || new Date(u).getTime() > now);
  // جرس القنوات (0.21.0 — ترحيل 032): يطبّق حصراً على القنوات المستقلة —
  // mute: لا بيانات تصل أصلاً (صمت حقيقي)، pinned: المنشورات المثبتة فقط.
  const isChannel = conv?.kind === "channel";
  const bellBlocked = (bell: string | null) =>
    isChannel && (bell === "mute" || (bell === "pinned" && m.pinned !== true));
  const ids = (members ?? [])
    .filter((r) => !isMuted(r.muted_until))
    .filter((r) => !bellBlocked(r.bell))
    .map((r) => r.user_id);
  if (!ids.length) return new Response("no recipients");

  const { data: tokens } = await db.from("device_tokens").select("token").in("user_id", ids);

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

  // إشعارات المتصفح لنفس المستلمين بنفس العنوان والنص (المرحلة 12) —
  // تُرسل حتى بلا رموز أندرويد (متصفح فقط = مستلم كامل) وفشلها لا يمنع أندرويد
  await notifyWebPushSubs(ids, title, body, String(m.conversation_id), "message");

  if (!tokens?.length) return new Response("no devices");

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
            // منذ 0.20.0: رسائل المحادثات لأندرويد «بيانات فقط» — التطبيق يعرضها
            // بإشعار محلي يحمل الإجراءات الممتدة (رد سريع/تفاعل/تمييز مقروء).
            // العنوان والنص يمران في data ليعرضهما العزل الخلفي بلا قاعدة بيانات.
            data: {
              conversation_id: m.conversation_id,
              message_id: id,
              title,
              body,
            },
            android: {
              priority: "high",
              // تجميع إشعارات المحادثة الواحدة بدل تراكمها (العرض المحلي في
              // التطبيق يجمّع بمفتاح المحادثة نفسه وينوب عن قناة «الرسائل»)
              collapse_key: m.conversation_id,
            },
            apns: {
              headers: { "apns-collapse-id": m.conversation_id },
              // iOS يبقى بإشعار النظام كما كان (حتى إصدار iOS الرسمي)
              payload: {
                aps: {
                  alert: { title, body },
                  sound: "default",
                  "thread-id": String(m.conversation_id),
                },
              },
            },
          },
        }),
      },
    );
    // جهاز لم يعد مسجلاً: نحذف رمزه
    if (r.status === 404) await db.from("device_tokens").delete().eq("token", token);
  }));

  return new Response("ok");
}

// ---------- إشعار «مكالمة واردة» (0.17.0) ----------
// نقرأ المكالمة من قاعدة البيانات بدل الثقة بمحتوى الطلب، ولا ننبّه إلا
// لمكالمة تُرن فعلاً (تكرار متأخر أو مكالمة انتهت قبل الإرسال = صمت).
async function notifyCall(id: string): Promise<Response> {
  const { data: c } = await db.from("calls").select("*").eq("id", id).single();
  if (!c) return new Response("not found", { status: 404 });
  if (c.status !== "ringing") return new Response("ignored");

  const [{ data: caller }, { data: tokens }] = await Promise.all([
    db.from("profiles").select("username, display_name").eq("id", c.caller_id).single(),
    db.from("device_tokens").select("token").eq("user_id", c.callee_id),
  ]);

  const name = caller?.display_name ?? caller?.username ?? "وصل شات";
  const title = "مكالمة واردة";
  const body = c.kind === "video"
    ? `🎬 ${name} يتصل بك مرئياً`
    : `📞 ${name} يتصل بك صوتياً`;

  // المتصفح يرن أيضاً (المرحلة 12) — بنفس نص أندرويد حرفياً
  await notifyWebPushSubs([c.callee_id], title, body, String(c.conversation_id), "call");

  if (!tokens?.length) return new Response("no devices");

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
            data: {
              type: "call",
              call_id: c.id,
              conversation_id: c.conversation_id,
              kind: c.kind,
            },
            android: {
              priority: "high",
              // مكالمات الطرف الواحد تُجمَّع بدل التراكم، وتُوجَّه إلى قناة
              // «المكالمات» التي يجهزها التطبيق بأهمية عالية
              collapse_key: c.conversation_id,
              notification: { channel_id: "calls", tag: `call-${c.conversation_id}` },
            },
            apns: {
              headers: { "apns-collapse-id": `call-${c.conversation_id}` },
              payload: { aps: { sound: "default", "thread-id": String(c.conversation_id) } },
            },
          },
        }),
      },
    );
    if (r.status === 404) await db.from("device_tokens").delete().eq("token", token);
  }));

  return new Response("ok");
}

// ============================================================
// Web Push (المرحلة 12 — 0.28.0): VAPID ES256 + تشفير RFC 8291/8188
// — تنفيذ نقي بWebCrypto دنو بلا أي حزمة جديدة.
// ============================================================

const enc = new TextEncoder();
const dec = new TextDecoder();

function b64uToBytes(s: string): Uint8Array {
  const t = s.replace(/-/g, "+").replace(/_/g, "/");
  const pad = "=".repeat((4 - (t.length % 4)) % 4);
  const bin = atob(t + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToB64u(b: Uint8Array): string {
  let s = "";
  for (const byte of b) s += String.fromCharCode(byte);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

let vapidKey: { priv: CryptoKey; pubRaw: Uint8Array } | null = null;

// استيراد المفتاح الخاص (PKCS8 base64 قياسي) واستخراج العام الخام (65 بايت
// 0x04 || X || Y) من JWK — مفتاح واحد فقط في الأسرار.
async function getVapidKey(): Promise<{ priv: CryptoKey; pubRaw: Uint8Array } | null> {
  if (vapidKey) return vapidKey;
  if (!vapidPrivateB64) return null;
  try {
    const pkcs8 = b64uToBytes(vapidPrivateB64.replace(/-/g, "+").replace(/_/g, "/"));
    const priv = await crypto.subtle.importKey(
      "pkcs8",
      pkcs8 as unknown as BufferSource,
      { name: "ECDSA", namedCurve: "P-256" },
      true,
      ["sign"],
    );
    const jwk = await crypto.subtle.exportKey("jwk", priv);
    const x = b64uToBytes(jwk.x!);
    const y = b64uToBytes(jwk.y!);
    const raw = new Uint8Array(65);
    raw[0] = 0x04;
    raw.set(x, 1);
    raw.set(y, 1 + x.length);
    vapidKey = { priv, pubRaw: raw };
    return vapidKey;
  } catch {
    return null;
  }
}

// توقيع VAPID: JWT بنفس إلزام المتصفح (aud = أصل خدمة الدفع، sub = mailto)
async function vapidJwt(endpoint: string, priv: CryptoKey): Promise<string> {
  const origin = new URL(endpoint).origin;
  const exp = Math.floor(Date.now() / 1000) + 12 * 3600;
  return await new SignJWT({ aud: origin, exp, sub: vapidSubject || "mailto:no-reply@waslchat.app" })
    .setProtectedHeader({ alg: "ES256", typ: "JWT" })
    .sign(priv);
}

// HKDF-SHA256 عبر WebCrypto (RFC 5869) — لبنة RFC 8291 الأساسية
async function hkdf(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, len: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey("raw", ikm as unknown as BufferSource, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt: salt as unknown as BufferSource, info: info as unknown as BufferSource },
    key,
    len * 8,
  );
  return new Uint8Array(bits);
}

function concat(...arrs: Uint8Array[]): Uint8Array {
  const total = arrs.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(total);
  let o = 0;
  for (const a of arrs) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}

// تشفير حمولة Web Push (aes128gcm — RFC 8291 + RFC 8188) بمفتاح الاشتراك
async function encryptPayload(subKey: Uint8Array, authSecret: Uint8Array, plaintext: string): Promise<Uint8Array> {
  // 1) زوج مؤقت ECDH P-256 وسره المشترك
  const ephem = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const ephPubRaw = new Uint8Array(
    await crypto.subtle.exportKey("raw", ephem.publicKey),
  );
  const subKeyImported = await crypto.subtle.importKey(
    "raw",
    subKey as unknown as BufferSource,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const shared = new Uint8Array(
    await crypto.subtle.deriveBits({ name: "ECDH", public: subKeyImported }, ephem.privateKey, 256),
  );

  // 2) PRK_key = HKDF(auth، صفر^32، "WebPush: info" || keyid)
  const zeroSalt = new Uint8Array(32);
  const keyInfo = concat(enc.encode("WebPush: info"), new Uint8Array([0]), subKey, ephPubRaw);
  const prkKey = await hkdf(authSecret, zeroSalt, keyInfo, 32);

  // 3) CEK وNONCE من السر المشترك بPRK_key
  const cekInfo = concat(enc.encode("Content-Encoding: aes128gcm"), new Uint8Array([0]), enc.encode("P-256"));
  const nonceInfo = concat(enc.encode("Content-Encoding: nonce"), new Uint8Array([0]), enc.encode("P-256"));
  const cek = await hkdf(shared, prkKey, cekInfo, 16);
  const nonce = await hkdf(shared, prkKey, nonceInfo, 12);

  // 4) الحمولة المبطّنة: النص || 0x02 (لا حشوة إضافية — حد أدنى مسموح)
  const rs = 4096;
  const body = concat(enc.encode(plaintext), new Uint8Array([0x02]));

  // 5) AAD = rs (2 بايت، القيمة 4096) || آخر سجل (0x01)
  const aad = new Uint8Array([(rs >> 8) & 0xff, rs & 0xff, 0x01]);
  const aesKey = await crypto.subtle.importKey("raw", cek as unknown as BufferSource, "AES-GCM", false, ["encrypt"]);
  const iv = nonce;
  const ct = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv as unknown as BufferSource, additionalData: aad as unknown as BufferSource, tagLength: 128 }, aesKey, body as unknown as BufferSource),
  );

  // 6) الترويسة: rs ثلاث بايتات || ملح عشوائي 16 || idlen=65 || المفتاح المؤقت
  // للمرسل — RFC 8291 §3.1: المفتاح المؤقت يُمرر في keyid كي يشتقه المتصفح،
  // فلا فك بغيه إطلاقاً (idlen=0 يعني مفتاحاً معلوماً مسبقاً فقط)
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const header = new Uint8Array(3 + 16 + 1 + 65);
  header[0] = 0x00;
  header[1] = (rs >> 8) & 0xff;
  header[2] = rs & 0xff;
  header.set(salt, 3);
  header[19] = 65;
  header.set(ephPubRaw, 20);
  return concat(header, ct);
}

// إرسال فعلي لاشتراك واحد — أي فشل غير 404/410 يُتجاهل بصمت (محاولة لاحقة)
async function sendWebPush(
  sub: { endpoint: string; p256dh: string; auth: string },
  title: string,
  body: string,
  conversationId: string,
  kind: string,
): Promise<void> {
  const key = await getVapidKey();
  if (!key) return; // السر غير مضبوط بعد — صمت صادق حتى خطوات المالك
  try {
    const payload = JSON.stringify({ title, body, conversationId, kind });
    const encrypted = await encryptPayload(
      b64uToBytes(sub.p256dh),
      b64uToBytes(sub.auth),
      payload,
    );
    const jwt = await vapidJwt(sub.endpoint, key.priv);
    const r = await fetch(sub.endpoint, {
      method: "POST",
      headers: {
        Authorization: `vapid t=${jwt}, k=${bytesToB64u(key.pubRaw)}`,
        "Content-Type": "application/octet-stream",
        "Content-Encoding": "aes128gcm",
        TTL: "3600",
        Urgency: kind === "call" ? "high" : "normal",
      },
      body: encrypted as unknown as BodyInit,
    });
    // الاشتراك الميت: نحذفه (المتصفح غير موجود أو ألغى)
    if (r.status === 404 || r.status === 410) {
      await db.from("web_push_subscriptions").delete().eq("endpoint", sub.endpoint);
    } else if (!r.ok) {
      // فشل مؤقت: نعلّم الوقت كي يحذفه التنظيف إن استمر 30 يوماً
      await db
        .from("web_push_subscriptions")
        .update({ last_failed_at: new Date().toISOString() })
        .eq("endpoint", sub.endpoint);
    }
  } catch {
    // غرابة شبكة أو تشفير: صمت صادق — لا يكسر الإشعار لأندرويد أبداً
  }
}

// اشتراكات المتصفح لمجموعة مستلمين — تتفرغ إن لم يوجد أحد
async function notifyWebPushSubs(
  userIds: string[],
  title: string,
  body: string,
  conversationId: string,
  kind: string,
): Promise<void> {
  try {
    if (!userIds.length) return;
    const { data: subs } = await db
      .from("web_push_subscriptions")
      .select("endpoint, p256dh, auth")
      .in("user_id", userIds);
    if (!subs?.length) return;
    await Promise.all(subs.map((s) => sendWebPush(s, title, body, conversationId, kind)));
  } catch {
    // جدول غير مُنشأ بعد (الترحيل لم يُشغَّل) — صمت صادق
  }
}
