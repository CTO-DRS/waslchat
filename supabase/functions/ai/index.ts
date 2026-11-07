// وصل شات: مساعد «وصل AI» (محادثة، تلخيص محادثة، ترجمة رسالة)
// يعمل بمفتاح Gemini المجاني من Google AI Studio
// الأسرار: GEMINI_API_KEY، واختياري GEMINI_MODEL
// لا يقبل إلا مستخدمين مسجلين (التحقق من JWT مفعّل افتراضياً)

import { createClient } from "npm:@supabase/supabase-js@2";

const KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_ANON_KEY")!,
);

// حد معدل بسيط لكل مستخدم (لحماية حصة Gemini المجانية من الاستنزاف)
// ملاحظة: الذاكرة تُصفَّر عند إعادة تشغيل العزلة — هي سدّ أولي وليس حداً صارماً.
const rate = new Map<string, number[]>();
function allow(uid: string, max = 30, windowMs = 60_000): boolean {
  const now = Date.now();
  const arr = (rate.get(uid) ?? []).filter((t) => now - t < windowMs);
  if (arr.length >= max) {
    rate.set(uid, arr);
    return false;
  }
  arr.push(now);
  rate.set(uid, arr);
  return true;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

type Turn = { role: "user" | "model"; text: string };

async function gemini(system: string, turns: Turn[]): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: turns.map((t) => ({ role: t.role, parts: [{ text: t.text }] })),
      }),
    },
  );
  if (!res.ok) {
    // لا نُسجّل نص الاستجابة (قد يحتوي محتوى المستخدم في سجلات المنصة)
    console.error(`gemini error: ${res.status}`);
    throw new Error(`gemini ${res.status}`);
  }
  const j = await res.json();
  return (j.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "")
    .join("")
    .trim();
}

const SYSTEM_CHAT =
  "أنت «وصل AI»، مساعد ذكي داخل تطبيق المراسلة وصل شات. أجب بالعربية الواضحة وباختصار ما لم يطلب المستخدم غير ذلك، وبلغة المستخدم إن كتب بلغة أخرى. كن مفيداً ولطيفاً ودقيقاً، وقل لا أعرف إن لم تكن متأكداً.";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!KEY) return json({ error: "GEMINI_API_KEY غير مضبوط" }, 500);

  // التحقق الفعلي من هوية المستخدم: verify_jwt يقبل أي JWT موقّع بمفتاح المشروع
  // (بما فيه مفتاح anon العام) — هنا نضمن أن المتصل حساب حقيقي.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  const { data: userData } = await db.auth.getUser(jwt);
  const user = userData?.user;
  if (!user) return json({ error: "غير مصرح" }, 401);
  if (!allow(user.id)) return json({ error: "طلبات كثيرة، انتظر قليلاً ثم أعد المحاولة" }, 429);

  try {
    const body = await req.json();
    const mode = body.mode ?? "chat";

    if (mode === "chat") {
      const turns: Turn[] = (body.messages ?? [])
        .slice(-20)
        .map((m: Turn) => ({ role: m.role === "model" ? "model" : "user", text: String(m.text).slice(0, 4000) }));
      if (!turns.length) return json({ error: "no messages" }, 400);
      return json({ reply: await gemini(SYSTEM_CHAT, turns) });
    }

    if (mode === "translate") {
      const target = body.target === "en" ? "الإنجليزية" : "العربية";
      const text = String(body.text ?? "").slice(0, 4000);
      const reply = await gemini(
        `ترجم النص إلى ${target} بدقة وطبيعية. أعد الترجمة فقط بدون أي شرح.`,
        [{ role: "user", text }],
      );
      return json({ reply });
    }

    if (mode === "summarize") {
      // (توافق رجعي مع النسخ القديمة) نقرأ الرسائل بصلاحيات المستخدم نفسه
      const db = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
      );
      const { data, error } = await db
        .from("messages")
        .select("content, type, created_at, profiles(username, display_name)")
        .eq("conversation_id", body.conversation_id)
        .order("created_at", { ascending: false })
        .limit(80);
      if (error) return json({ error: "لا يمكنك تلخيص هذه المحادثة" }, 403);
      const lines = (data ?? []).reverse().map((m: any) => {
        const who = m.profiles?.display_name ?? m.profiles?.username ?? "؟";
        const what = m.type === "image" ? "[صورة]" : m.type === "voice" ? "[رسالة صوتية]" : m.content;
        return `${who}: ${what}`;
      });
      if (!lines.length) return json({ reply: "لا توجد رسائل لتلخيصها بعد." });
      const reply = await gemini(
        "لخّص هذه المحادثة بالعربية في نقاط قصيرة: أهم ما قيل، والقرارات، وأي مهام أو مواعيد مطلوبة. لا تخترع شيئاً غير موجود.",
        [{ role: "user", text: lines.join("\n") }],
      );
      return json({ reply });
    }

    if (mode === "summarize_lines") {
      // التشفير بين الطرفين: التطبيق يفك التشفير محلياً ويرسل الأسطر جاهزة بعد موافقة المستخدم.
      // تنبيه: هذه الأسطر نص صريح يمر عبر هذه الدالة إلى Gemini — لا تُخزَّن ولا تُسجَّل هنا.
      const lines: string[] = (Array.isArray(body.lines) ? body.lines : [])
        .map((l: unknown) => String(l).slice(0, 500))
        .slice(0, 200);
      if (!lines.length) return json({ reply: "لا توجد رسائل لتلخيصها بعد." });
      const reply = await gemini(
        "لخّص هذه المحادثة بالعربية في نقاط قصيرة: أهم ما قيل، والقرارات، وأي مهام أو مواعيد مطلوبة. لا تخترع شيئاً غير موجود.",
        [{ role: "user", text: lines.join("\n") }],
      );
      return json({ reply });
    }

    return json({ error: "unknown mode" }, 400);
  } catch (e) {
    console.error(e);
    return json({ error: "تعذّر الوصول للمساعد الآن" }, 500);
  }
});
