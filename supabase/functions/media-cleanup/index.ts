// وصل شات: حذف ملفات الرسائل المحذوفة والمختفية من التخزين
// يستدعيه pg_cron كل ساعة (013_files_video_cleanup.sql) بالسر WEBHOOK_SECRET

import { createClient } from "npm:@supabase/supabase-js@2";

const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// مقارنة سرّية بزمن ثابت
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

Deno.serve(async (req) => {
  const provided = req.headers.get("x-webhook-secret") ?? "";
  if (!webhookSecret || !(await timingSafeEqual(provided, webhookSecret))) {
    return new Response("unauthorized", { status: 401 });
  }
  let removed = 0;
  for (let round = 0; round < 10; round++) {
    const { data: rows, error } = await db.from("media_trash").select("path").limit(100);
    if (error) return new Response(error.message, { status: 500 });
    if (!rows?.length) break;
    const paths = rows.map((r) => r.path as string);
    const { error: rmErr } = await db.storage.from("chat-media").remove(paths);
    if (rmErr) return new Response(rmErr.message, { status: 500 });
    await db.from("media_trash").delete().in("path", paths);
    removed += paths.length;
  }
  return new Response(JSON.stringify({ removed }), {
    headers: { "Content-Type": "application/json" },
  });
});
