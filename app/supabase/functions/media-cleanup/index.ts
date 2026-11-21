// وصل شات: حذف ملفات الرسائل المحذوفة والمختفية من التخزين
// يستدعيه pg_cron كل ساعة (013_files_video_cleanup.sql) بالسر WEBHOOK_SECRET

import { createClient } from "npm:@supabase/supabase-js@2";

const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";
const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
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
