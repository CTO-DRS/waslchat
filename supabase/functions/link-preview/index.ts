// وصل شات: دالة «معاينة الروابط» (المرحلة 8 ب — 0.21.0)
// تجلب صفحة رابط عامة وتستخرج العنوان والوصف والصورة المصغرة (وسوم OpenGraph
// مع هبوط لوسوم HTML الأساسية) — ثم تتجاهل كل شيء: **لا تخزين إطلاقاً** هنا
// ولا في أي قاعدة بيانات. التخزين الوحيد للنتيجة هو جهاز المستخدم (24 ساعة).
//
// الصرامة المقصودة:
// - http/https حصراً، والروابط الخاصة محجوبة (localhost/عناوين داخلية/IP مباشرة)
//   حتى لا تتحول الدالة إلى باب فحص شبكات داخلية.
// - HTML بحد 300 ك.ب مهما بلغ حجم الصفحة، ومهلة 6 ثوانٍ للجلب.
// - لا تقبل إلا مستخدمين مسجلين (التحقق من JWT مفعّل افتراضياً).
//
// الأسرار: لا شيء — دالة بلا مفاتيح خارجية.

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

// الروابط المحجوبة: شبكات داخلية وlocalhost وIP مباشرة — لا فحص شبكات
const BLOCKED_HOST = /^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.|169\.254\.|\[?::1\]?$|\[?fe80|\[?fc|\[?fd)/i;

function safeUrl(raw: unknown): URL | null {
  if (typeof raw !== "string") return null;
  let u: URL;
  try {
    u = new URL(raw);
  } catch {
    return null;
  }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  if (BLOCKED_HOST.test(u.hostname)) return null;
  // لا IP مباشر (IPv4): لا يوجد سيناريو مشروع لفحص عنوان رقمي من المحادثة
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(u.hostname)) return null;
  if (u.username || u.password) return null;
  return u;
}

// تجريد النص من وسوم HTML وفك الكيانات الشائعة
function decodeEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&nbsp;/g, " ");
}

function stripTags(s: string): string {
  return decodeEntities(s.replace(/<[^>]*>/g, " ")).replace(/\s+/g, " ").trim();
}

// قيمة وسوم meta من HTML — مع أولوية og: ثم twitter: ثم القسم الأساسي
function metaContent(html: string, names: string[]): string | null {
  for (const name of names) {
    const re = new RegExp(
      `<meta[^>]+(?:property|name)=[\"']${name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\"'][^>]*>`,
      "i",
    );
    const tag = html.match(re)?.[0];
    if (!tag) continue;
    const content = tag.match(/content=[\"']([^\"']*)[\"']/i)?.[1];
    if (content && content.trim()) return decodeEntities(content.trim());
  }
  return null;
}

// أول عنوان <title> أو أول h1 عند غياب الوسوم
function titleFallback(html: string): string | null {
  const t = html.match(/<title[^>]*>([\s\S]{0,300}?)<\/title>/i)?.[1];
  if (t) {
    const s = stripTags(t);
    if (s) return s.slice(0, 120);
  }
  const h1 = html.match(/<h1[^>]*>([\s\S]{0,300}?)<\/h1>/i)?.[1];
  if (h1) {
    const s = stripTags(h1);
    if (s) return s.slice(0, 120);
  }
  return null;
}

// تحويل روابط نسبيّة في الصورة إلى مطلقة على نطاق الصفحة
function absoluteImage(img: string | null, base: URL): string | null {
  if (!img) return null;
  try {
    const u = new URL(img, base);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    return u.toString();
  } catch {
    return null;
  }
}

async function fetchWithTimeout(url: string, ms: number): Promise<Response> {
  const c = new AbortController();
  const t = setTimeout(() => c.abort(), ms);
  try {
    return await fetch(url, {
      signal: c.signal,
      redirect: "follow",
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; WaslChat-LinkPreview/1.0)",
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "ar, en;q=0.7",
      },
    });
  } finally {
    clearTimeout(t);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const body = await req.json();
    const url = safeUrl(body?.url);
    if (!url) return json({ error: "رابط غير مسموح" }, 400);

    const res = await fetchWithTimeout(url.toString(), 6000);
    if (!res.ok) return json({ error: `فشل الجلب (${res.status})` }, 502);
    const ctype = res.headers.get("content-type") ?? "";
    if (!/text\/html|application\/xhtml/i.test(ctype)) {
      // ليست صفحة HTML: الصور المباشرة تعرض مصغّرها نفسه، والباقي بلا معاينة
      if (/^image\//i.test(ctype)) {
        return json({ url: url.toString(), host: url.host, image: url.toString() });
      }
      return json({ error: "ليست صفحة HTML" }, 422);
    }
    const reader = res.body?.getReader();
    let html = "";
    if (reader) {
      const dec = new TextDecoder();
      let total = 0;
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        total += value.byteLength;
        html += dec.decode(value, { stream: true });
        if (total > 300_000) break; // حد 300 ك.ب — تكفي وسوم الرأس دائماً
      }
      try {
        await reader.cancel(); // نوقف الجلب فوراً — لا نستهلك البقية
      } catch { /* لا شيء */ }
    }
    if (!html) return json({ error: "صفحة فارغة" }, 422);

    const title =
      metaContent(html, ["og:title", "twitter:title"]) ?? titleFallback(html);
    const description = metaContent(html, [
      "og:description",
      "twitter:description",
      "description",
    ]);
    const image = absoluteImage(
      metaContent(html, ["og:image", "twitter:image", "og:image:secure_url"]),
      url,
    );

    return json({
      url: url.toString(),
      host: url.host,
      title: title?.slice(0, 120) ?? null,
      description: description?.slice(0, 200) ?? null,
      image,
    });
  } catch (e) {
    console.error("link-preview:", e);
    return json({ error: "تعذّر توليد المعاينة" }, 502);
  }
});
