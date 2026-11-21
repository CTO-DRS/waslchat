// Wasl Shield — إجراءات المدير التي تحتاج صلاحية الخدمة (1.10.0)
//
// action = "quarantine": يُبطل روابط وسائط المبلَّغ عنه في محادثة البلاغ فوراً بنقل الملفات
//   من chat-media إلى الحجر shield-quarantine. أي رابط موقّع سابق يصبح 404 لأن الملف لم يعد
//   في مكانه، والنسخة تبقى محفوظة كدليل. المستدعي: مدير التطبيق (JWT) + مبرر مكتوب.
// action = "retention": يستدعيه pg_cron يومياً بسر الويب هوك — يحذف أدلة الحالات المغلقة
//   بعد انتهاء فترة الاحتفاظ (180 يوماً)، وسجل التدقيق يبقى.
//
// لا يوجد هنا ولا في أي مكان آخر ما يحذف أو يمسّ ملفات على أجهزة المستخدمين — هذا غير ممكن تقنياً.
import { createClient } from "npm:@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const service = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});
const webhookSecret = Deno.env.get("WEBHOOK_SECRET") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

function pathsOf(mediaUrl: string | null): string[] {
  if (!mediaUrl) return [];
  const t = mediaUrl.trim();
  if (t.startsWith("[")) {
    try {
      const a = JSON.parse(t);
      if (Array.isArray(a)) return a.filter((x) => typeof x === "string");
    } catch (_) { /* fallthrough */ }
  }
  if (t.startsWith("http")) return []; // روابط خارجية لا يملكها التطبيق
  return [t];
}

async function quarantine(req: Request, body: Record<string, unknown>) {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "");
  const { data: u } = await service.auth.getUser(token);
  const actor = u?.user?.id;
  if (!actor) return json({ error: "unauthorized" }, 401);
  const { data: adm } = await service.from("app_admins").select("user_id").eq("user_id", actor).maybeSingle();
  if (!adm) return json({ error: "not_admin" }, 403);

  const caseId = String(body.case_id ?? "");
  const reason = String(body.reason ?? "").trim();
  const ids = Array.isArray(body.message_ids) ? body.message_ids.map(String).slice(0, 200) : [];
  if (reason.length < 5) return json({ error: "SHIELD_REASON_REQUIRED" }, 400);
  if (!caseId || ids.length === 0) return json({ error: "bad_request" }, 400);

  const { data: c } = await service.from("shield_cases")
    .select("id, conversation_id, target_user").eq("id", caseId).maybeSingle();
  if (!c || !c.conversation_id || !c.target_user) return json({ error: "case_not_actionable" }, 400);

  // فقط وسائط المبلَّغ عنه داخل محادثة البلاغ — لا يستطيع المدير إبطال غيرها من هنا
  const { data: msgs } = await service.from("messages")
    .select("id, media_url, shield_removed")
    .in("id", ids).eq("conversation_id", c.conversation_id).eq("sender_id", c.target_user);

  const done: string[] = [];
  const failed: string[] = [];
  for (const m of msgs ?? []) {
    if (m.shield_removed) continue;
    for (const p of pathsOf(m.media_url)) {
      const q = `${caseId}/${p}`;
      const { error } = await service.storage.from("chat-media").move(p, q, { destinationBucket: "shield-quarantine" });
      if (error) {
        // بديل: نسخ ثم حذف
        const dl = await service.storage.from("chat-media").download(p);
        if (dl.error || !dl.data) { failed.push(p); continue; }
        const up = await service.storage.from("shield-quarantine").upload(q, dl.data, { upsert: true });
        if (up.error) { failed.push(p); continue; }
        await service.storage.from("chat-media").remove([p]);
      }
      const { error: rpcErr } = await service.rpc("shield_service_mark_quarantined", {
        p_actor: actor, p_case: caseId, p_message: m.id, p_original: p, p_qpath: q, p_reason: reason,
      });
      if (rpcErr) failed.push(p); else done.push(p);
    }
  }
  return json({ ok: true, quarantined: done.length, failed });
}

async function retention(req: Request) {
  if (!webhookSecret || req.headers.get("x-webhook-secret") !== webhookSecret) {
    return json({ error: "unauthorized" }, 401);
  }
  const { data: rows, error } = await service.rpc("shield_service_expired");
  if (error) return json({ error: error.message }, 500);
  const byCase = new Map<string, { bucket: string; path: string }[]>();
  for (const r of rows ?? []) {
    const list = byCase.get(r.case_id) ?? [];
    list.push({ bucket: r.bucket, path: r.path });
    byCase.set(r.case_id, list);
  }
  let purged = 0;
  for (const [caseId, list] of byCase) {
    for (const b of ["shield-evidence", "shield-quarantine"]) {
      const paths = list.filter((x) => x.bucket === b).map((x) => x.path);
      if (paths.length) await service.storage.from(b).remove(paths);
    }
    const { error: e2 } = await service.rpc("shield_service_purge_case", { p_case: caseId });
    if (!e2) purged++;
  }
  return json({ ok: true, purged });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch (_) { /* empty */ }
  try {
    if (body.action === "quarantine") return await quarantine(req, body);
    if (body.action === "retention") return await retention(req);
    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
