import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'e2e_service.dart';

/// الإجراءات السريعة من شريط الإشعار (المرحلة 8 — 0.20.0):
/// تمييز مقروء، تفاعل بإيموجي، ورد سريع من شريط الإشعار نفسه.
///
/// ترميز الحمولة (Payload) نصي ثابت يُفكَّ محلياً — الجزء النقي منه
/// يُختبَر حصرياً في `quick_action_service_test.dart`.
/// كل إجراء شبكي «بالأفضل الجهد»: فشله الصامت يبقي السلوك السابق
/// (النقر على الإشعار يفتح التطبيق).
enum QuickActionKind { open, markRead, react, reply }

class QuickAction {
  const QuickAction(this.kind, this.conversationId, {this.messageId, this.emoji});
  final QuickActionKind kind;
  final String conversationId;
  final String? messageId;
  final String? emoji;
}

class QuickActionService {
  // ---------- الترميز والفك (نقي) ----------
  /// حمولة فتح الإشعار الافتراضية — تحمل معرّف الرسالة إن توفر
  /// (يستخدمه إجراء التفاعل من الشريط نفسه)
  static String encodeOpen(String convId, {String? messageId}) =>
      'open|$convId|${messageId ?? ''}';
  static String encodeMarkRead(String convId) => 'read|$convId';
  static String encodeReact(String convId, String msgId, String emoji) =>
      'react|$convId|$msgId|$emoji';
  static String encodeReply(String convId) => 'reply|$convId';

  static QuickAction? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final parts = payload.split('|');
    if (parts.length < 2) return null;
    final kind = switch (parts[0]) {
      'open' => QuickActionKind.open,
      'read' => QuickActionKind.markRead,
      'react' => QuickActionKind.react,
      'reply' => QuickActionKind.reply,
      _ => null,
    };
    if (kind == null) return null;
    final conv = parts[1];
    if (conv.isEmpty) return null;
    final msgId = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
    return switch (kind) {
      // التفاعل يتطلب معرّف الرسالة والإيموجي معاً — والبقية تولد بحمولة ناقصة
      QuickActionKind.react when parts.length >= 4 =>
        QuickAction(kind, conv, messageId: parts[2], emoji: parts.sublist(3).join('|')),
      QuickActionKind.react => null,
      _ => QuickAction(kind, conv, messageId: msgId),
    };
  }

  // ---------- سياق المحادثة ----------

  /// يجلب نوع المحادثة وشريكها ويحدد وضع التشفير كما تعهده شاشة المحادثة:
  /// خاص غير بوت = متدرج، مجموعة = مفتاح ثابت، بوت/قناة = صريح.
  static Future<_ConvCtx?> _ctx(String convId) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return null;
    try {
      final rows = await supabase
          .from('conversation_participants')
          .select('user_id, profiles!inner(is_bot)')
          .eq('conversation_id', convId);
      String? other;
      var otherIsBot = false;
      for (final r in rows) {
        final uid = r['user_id'] as String?;
        if (uid == me) continue;
        other = uid;
        final p = r['profiles'];
        otherIsBot = p is Map ? (p['is_bot'] == true) : false;
      }
      final conv = await supabase
          .from('conversations')
          .select('is_group')
          .eq('id', convId)
          .maybeSingle();
      if (conv == null) return null;
      final isGroup = conv['is_group'] == true;
      return _ConvCtx(
        convId: convId,
        isGroup: isGroup,
        otherId: other,
        e2e: isGroup || (!isGroup && other != null && !otherIsBot),
      );
    } catch (_) {
      return null;
    }
  }

  // ---------- الإجراءات (بالأفضل الجهد) ----------

  /// تهيئة العزل الخلفي: Supabase ثم فحص مفاتيح هذا الجهاز.
  /// يُستدعى من معالج الاستجابة للإشعار في الخلفية قبل أي إجراء يحتاج تشفيراً.
  static Future<bool> ensureBackend() async {
    if (kIsWeb) return false;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (supabase.auth.currentSession == null) {
        await Supabase.initialize(
            url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
      }
      if (supabase.auth.currentSession == null) return false;
      await E2eService.checkKeys();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// تمييز المحادثة كمقروءة من شريط الإشعار
  static Future<bool> markRead(String convId) async {
    try {
      await supabase.rpc('mark_read', params: {'conv': convId});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// تفاعل بإيموجي من شريط الإشعار (التشفير بمفتاح المحادثة الثابت كما في الشاشة)
  static Future<bool> react(String convId, String messageId, String emoji) async {
    try {
      final c = await _ctx(convId);
      if (c == null) return false;
      var out = emoji;
      if (c.e2e) {
        final key = c.isGroup
            ? await E2eService.groupKey(convId)
            : await E2eService.dmKey(convId, c.otherId!);
        if (key == null) return false;
        out = await E2eService.encryptText(key, convId, emoji);
      }
      await supabase.rpc('react_message', params: {'p_id': messageId, 'p_emoji': out});
      return true;
    } catch (_) {
      return false;
    }
  }

  /// رد سريع من شريط الإشعار — نفس مسار إرسال نص المحادثة تماماً:
  /// الخاص بالجلسة المتدرجة، المجموعة بمفتاحها، والبوت صريحاً.
  static Future<bool> reply(String convId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      final c = await _ctx(convId);
      if (c == null) return false;
      final me = supabase.auth.currentUser!.id;
      var payload = trimmed;
      if (c.e2e) {
        if (!c.isGroup && c.otherId != null) {
          final lim = await E2eService.dmPlainLimit(c.otherId!);
          if (utf8.encode(trimmed).length > lim) return false;
          final p = await E2eService.encryptDmText(convId, c.otherId!, trimmed);
          if (p == null) return false;
          payload = p;
        } else {
          if (!E2eService.withinPlainLimit(trimmed)) return false;
          final key = await E2eService.groupKey(convId);
          if (key == null) return false;
          payload = await E2eService.encryptText(key, convId, trimmed);
        }
      }
      await supabase.from('messages').insert({
        'conversation_id': convId,
        'sender_id': me,
        'type': 'text',
        'content': payload,
      });
      return true;
    } catch (_) {
      // الحظر بين الطرفين والبقية صمت — السلوك السابق: فتح التطبيق
      return false;
    }
  }
}

class _ConvCtx {
  const _ConvCtx({
    required this.convId,
    required this.isGroup,
    required this.otherId,
    required this.e2e,
  });
  final String convId;
  final bool isGroup;
  final String? otherId;
  final bool e2e;
}
