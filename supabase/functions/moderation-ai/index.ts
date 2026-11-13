// وصل شات: مساعد الإشراف الذكي للمجتمعات العامة (v0.15.0 — ترحيل 027)
// فحص عند الطلب من شاشة الإشراف: يجلب آخر الرسائل النصية لغرف المجتمع العام
// (نصوصها صريحة على الخادم أصلاً بالتصميم) ويرسلها إلى Gemini للتصنيف،
// ويخزّن الملاحظات في community_ai_flags — المساعد يقترح ولا ينفذ أي إجراء.
// الأسرار: GEMINI_API_KEY، واختياري GEMINI_MODEL (التحقق من JWT مفعّل افتراضياً)
// تنبيه صادق: نص الرسائل يمر إلى Gemini خلال الفحص فقط ولا يُخزَّن ولا يُسجَّل هنا.

import { createClient } from "npm:@supabase/supabase-js@2";

const KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3.8-flash";

const SCAN_LIMIT = 120; // سقف الرسائل في الفحص الواحد
const FLAGS_LIMIT = 40; // سقف الملاحظات المخزنة في الفحص الواحد

const CATEGORIES = ["spam", "abuse", "scam", "nsfw", "danger"] as const;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

const SYSTEM =
  "أنت مساعد إشراف داخل تطبيق مراسلة. تحقق من قائمة رسائل (معرّف + نص) وحدد ما يظهر خطراً فعلياً " +
  "في المجتمعات العامة فقط: spam (إزعاج وتكرار ودعاية)، abuse (إساءة وتشهير وسبّ)، " +
  "scam (احتيال وتصيّد ووعود مال)، nsfw (محتوى جنسي صريح)، danger (تهديد أو تحريض على العنف أو الإيذاء). " +
  "أعد JSON فقط بدون أي شرح أو أسوار كود: مصفوفة كائنات، كل كائن {\"message_id\": نص المعرّف كما ورد، " +
  "\"category\": أحد المفاتيح الخمسة بالإنجليزية، \"severity\": \"high\" إن كان خطراً واضحاً أو \"low\"، " +
  "\"reason\": سبب قصير بالعربية حتى 150 حرفاً}. لا تُشِر إلا لما فيه شبهة حقيقية، ولا تكرر الرسالة، " +
  "وإن لم يوجد شيء أعد [].";

async function gemini(system: string, prompt: string): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.1 },
      }),
    },
  );
  if (!res.ok) throw new Error(`gemini ${res.status}: ${await res.text()}`);
  const j = await res.json();
  return (j.candidates?.[0]?.content?.parts ?? [])
    .map((p: { text?: string }) => p.text ?? "")
    .join("")
    .trim();
}

/// إزالة أسوار الكود المحيطة إن وجدت ثم استخراج أول مصفوفة JSON سليمة
function extractArray(text: string): unknown[] | null {
  const t = text.trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
  const start = t.indexOf("[");
  const end = t.lastIndexOf("]");
  if (start < 0 || end <= start) return null;
  try {
    const parsed = JSON.parse(t.slice(start, end + 1));
    return Array.isArray(parsed) ? parsed : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!KEY) return json({ error: "GEMINI_API_KEY غير مضبوط" }, 500);

  try {
    const body = await req.json();
    const cid = String(body.community_id ?? "");
    if (!cid) return json({ error: "community_id مطلوب" }, 400);

    // عميل بهوية الطالب: التحقق من الإشراف والعضوية عبر RLS نفسها
    const auth = req.headers.get("Authorization") ?? "";
    const user = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } } },
    );

    const { data: meData } = await user.auth.getUser();
    const me = meData.user?.id ?? "";
    if (!me) return json({ error: "not authenticated" }, 401);

    const { data: membership, error: mErr } = await user
      .from("community_members")
      .select("role")
      .eq("community_id", cid)
      .eq("user_id", me)
      .maybeSingle();
    if (mErr) return json({ error: mErr.message }, 403);
    if (!membership || !["owner", "admin"].includes(membership.role ?? "")) {
      return json({ error: "not allowed" }, 403);
    }

    const { data: community, error: cErr } = await user
      .from("communities")
      .select("is_public, ai_moderation")
      .eq("id", cid)
      .maybeSingle();
    if (cErr) return json({ error: cErr.message }, 403);
    if (!community?.is_public) return json({ error: "not public" }, 400);
    if (!community.ai_moderation) return json({ error: "المساعد غير مفعّل لهذا المجتمع" }, 400);

    // عميل خدمة: جلب الرسائل وكتابة الملاحظات بعد انتهاء التحقق أعلاه
    const svc = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: convs } = await svc
      .from("conversations")
      .select("id")
      .eq("community_id", cid)
      .limit(50);
    const convIds = (convs ?? []).map((c: { id: string }) => c.id);
    if (!convIds.length) return json({ scanned: 0, flagged: 0, by_category: {} });

    const { data: msgs, error: qErr } = await svc
      .from("messages")
      .select("id, content, sender_id, conversation_id, created_at")
      .in("conversation_id", convIds)
      .eq("type", "text")
      .order("created_at", { ascending: false })
      .limit(SCAN_LIMIT);
    if (qErr) return json({ error: qErr.message }, 500);
    const texts = (msgs ?? []).filter((m: any) => (m.content ?? "").trim().length > 0);
    if (!texts.length) return json({ scanned: 0, flagged: 0, by_category: {} });

    const prompt =
      "رسائل الفحص (المعرف | النص):\n" +
      texts
        .map((m: any) => `${m.id} | ${String(m.content).slice(0, 300)}`)
        .join("\n");

    const raw = await gemini(SYSTEM, prompt);
    const arr = extractArray(raw);

    const byCategory: Record<string, number> = {};
    let inserted = 0;
    const seen = new Set<string>();
    if (arr) {
      const byId = new Map(texts.map((m: any) => [m.id, m]));
      for (const item of arr.slice(0, FLAGS_LIMIT * 2)) {
        if (inserted >= FLAGS_LIMIT) break;
        const mid = typeof item?.message_id === "string" ? item.message_id.trim() : "";
        const cat = typeof item?.category === "string" ? item.category.trim() : "";
        const msg = byId.get(mid);
        if (!msg || !CATEGORIES.includes(cat as any)) continue;
        const key = `${mid}:${cat}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const severity = item?.severity === "high" ? "high" : "low";
        const reason =
          typeof item?.reason === "string" && item.reason.trim().length
            ? item.reason.trim().slice(0, 300)
            : null;
        const excerpt = String(msg.content).slice(0, 200);
        const { error: iErr } = await svc.from("community_ai_flags").upsert(
          {
            community_id: cid,
            conversation_id: msg.conversation_id,
            message_id: msg.id,
            sender_id: msg.sender_id,
            category: cat,
            severity,
            reason,
            excerpt,
            triggered_by: me,
          },
          { onConflict: "message_id,category" },
        );
        // المكرر عبر الفهرس الفريد الجزئي لا يفشل الفحص — يُعدّ ضمن النتيجة فقط إن أُدرج
        if (!iErr) {
          inserted += 1;
          byCategory[cat] = (byCategory[cat] ?? 0) + 1;
        }
      }
    }

    return json({
      scanned: texts.length,
      flagged: inserted,
      by_category: byCategory,
      parsed: arr !== null,
    });
  } catch (e) {
    console.error(e);
    return json({ error: "تعذّر تشغيل المساعد الآن — جرّب لاحقاً" }, 500);
  }
});
