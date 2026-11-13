// وصل شات 0.13.0 — واجهة البوتات البرمجية (واجهة المطوّرين)
// نشرها: npx supabase functions deploy bots-api --no-verify-jwt
//
// المصادقة: ترويسة Authorization: Bearer <token> حيث token رمز البوت
// الذي ظهر مرة واحدة عند الإنشاء (يبدأ بـ wasl_) — نتحقق من مجزئه SHA-256
// في جدول bots ولا يُخزَّن الرمز الخام في أي مكان.
//
// كل الطلبات POST بجسم JSON: { "method": "...", ...معاملات }
// الرد: { "ok": true, "result": ... } أو { "ok": false, "error_code": "...", "description": "..." }
//
// التوثيق الكامل للمطوّرين: docs/BOTS_API.md

import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}

function fail(code: string, description: string) {
  return json(200, { ok: false, error_code: code, description });
}

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return json(405, { ok: false, error_code: "method_not_allowed", description: "POST only" });
  }

  const auth = req.headers.get("authorization") ?? "";
  const token = auth.replace(/^Bearer\s+/i, "").trim();
  if (!token.startsWith("wasl_")) {
    return json(401, { ok: false, error_code: "unauthorized", description: "رمز البوت مفقود أو غير صالح" });
  }
  const tokenHash = await sha256Hex(token);

  const { data: bot, error: botErr } = await db
    .from("bots")
    .select("id, username, name, description, is_active, webhook_url")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (botErr || !bot) {
    return json(401, { ok: false, error_code: "unauthorized", description: "رمز البوت غير معروف" });
  }
  if (!bot.is_active) {
    return fail("bot_inactive", "البوت معطّل من مالكه حالياً");
  }

  const body = await req.json().catch(() => null);
  const method = body?.method;
  const args = body ?? {};

  try {
    switch (method) {
      // ----- معلومات البوت نفسه -----
      case "getMe":
        return json(200, {
          ok: true,
          result: {
            id: bot.id,
            username: bot.username,
            name: bot.name,
            description: bot.description,
            webhook_url: bot.webhook_url,
          },
        });

      // ----- إرسال رسالة نصية -----
      case "sendMessage": {
        const chatId = args.chat_id;
        const text = typeof args.text === "string" ? args.text : "";
        if (typeof chatId !== "string" || !text.trim()) {
          return fail("bad_request", "الحقول المطلوبة: chat_id و text");
        }
        const { data: mid, error } = await db.rpc("bot_send_message", {
          p_bot: bot.id,
          p_conv: chatId,
          p_text: text,
          p_reply_to: typeof args.reply_to === "string" ? args.reply_to : null,
        });
        if (error) return fail(mapSqlError(error.message), arabicError(error.message));
        return json(200, { ok: true, result: { message_id: mid, chat_id: chatId } });
      }

      // ----- تعديل رسالة سابقة للبوت (خلال 48 ساعة) -----
      case "editMessageText": {
        const msgId = args.message_id;
        const text = typeof args.text === "string" ? args.text : "";
        if (typeof msgId !== "string" || !text.trim()) {
          return fail("bad_request", "الحقول المطلوبة: message_id و text");
        }
        const { error } = await db.rpc("bot_edit_message", {
          p_bot: bot.id,
          p_msg: msgId,
          p_text: text,
        });
        if (error) return fail(mapSqlError(error.message), arabicError(error.message));
        return json(200, { ok: true, result: true });
      }

      // ----- حذف رسالة أرسلها البوت -----
      case "deleteMessage": {
        const msgId = args.message_id;
        if (typeof msgId !== "string") {
          return fail("bad_request", "الحقل المطلوب: message_id");
        }
        const { error } = await db.rpc("bot_delete_message", { p_bot: bot.id, p_msg: msgId });
        if (error) return fail(mapSqlError(error.message), arabicError(error.message));
        return json(200, { ok: true, result: true });
      }

      // ----- معلومات محادثة البوت عضو فيها -----
      case "getChat": {
        const chatId = args.chat_id;
        if (typeof chatId !== "string") {
          return fail("bad_request", "الحقل المطلوب: chat_id");
        }
        const { data: info, error } = await db.rpc("bot_chat_info", {
          p_bot: bot.id,
          p_conv: chatId,
        });
        if (error) return fail(mapSqlError(error.message), arabicError(error.message));
        return json(200, { ok: true, result: info });
      }

      default:
        return fail(
          "unknown_method",
          "الطرق المتاحة: getMe و sendMessage و editMessageText و deleteMessage و getChat",
        );
    }
  } catch (e) {
    return json(500, {
      ok: false,
      error_code: "internal",
      description: `خطأ غير متوقع: ${String(e)}`,
    });
  }
});

function mapSqlError(msg: string): string {
  if (msg.includes("chat not found")) return "chat_not_found";
  if (msg.includes("bot not in chat")) return "bot_not_in_chat";
  if (msg.includes("admins only")) return "not_allowed";
  if (msg.includes("bot is muted")) return "bot_muted";
  if (msg.includes("rate limit")) return "rate_limited";
  if (msg.includes("bad text length")) return "bad_text_length";
  if (msg.includes("message not editable")) return "message_not_editable";
  if (msg.includes("message not found")) return "message_not_found";
  return "server_error";
}

function arabicError(msg: string): string {
  if (msg.includes("chat not found")) return "المحادثة غير موجودة";
  if (msg.includes("bot not in chat")) return "البوت ليس عضواً في هذه المحادثة";
  if (msg.includes("admins only")) return "النشر في القنوات لمشرفيها فقط";
  if (msg.includes("bot is muted")) return "البوت مكتوم في هذه المحادثة";
  if (msg.includes("rate limit")) return "تجاوزت حد 20 رسالة في الدقيقة — انتظر قليلاً";
  if (msg.includes("bad text length")) return "النص يجب أن يكون بين 1 و 4000 حرف";
  if (msg.includes("message not editable")) return "لا يمكن التعديل — للبوت رسائله فقط وضمن 48 ساعة";
  if (msg.includes("message not found")) return "الرسالة غير موجودة أو ليست لبوتك";
  return msg;
}
