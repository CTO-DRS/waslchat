/// سلاسل الردود (Threads) والمنشورات المثبّتة — المرحلة 3 بند 2 (0.5.1).
///
/// الصادق: الربط معرّفات فقط — الخادم يعرف أي رسالة تتبع أي سلسلة، وأي
/// رسالة مثبّتة ومن ثبّتها، بلا نص ولا وسائط (داخل التشفير دائماً).
/// المنطق المحلي هنا خالص (بلا Flutter) ليُختبر وحدوياً، وwrappers الخادم
/// استدعاءات RPC مباشرة تحاكي نمط بقية الخدمات.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// السقف المفروض من الخادم في 029_threads_pins.sql — يجب أن يبقى مطابقاً
/// (اختبار الوحدة يتحقق من الثابت)
const int kMaxPinsPerRoom = 10;

/// منطق السلاسل والمثبتات على العميل: تصفية وعدّ محلي فوق رسائل البثّ
class ThreadService {
  const ThreadService._();

  /// مفتاح العمود كما يصل من الخادم في صف الرسالة
  static const String rootKey = 'thread_root_id';

  /// عدد ردود كل سلسلة: خريطة {معرف الجذر: عدد الردود}
  /// الرسالة داخل سلسلة = صف له thread_root_id. الردود المكررة مستحيلة
  /// (صف واحد لكل رسالة) لكن الخريطة تحسب كل صف ردٍّ صفّاً.
  static Map<String, int> threadCounts(List<Map<String, dynamic>> msgs) {
    final counts = <String, int>{};
    for (final m in msgs) {
      final root = m[rootKey];
      if (root is String && root.isNotEmpty) {
        counts[root] = (counts[root] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// التدفق الرئيسي: رسائل السلاسل لا تُعرض في القائمة — تعاد على الجذر
  /// كمصفوفة «N رد» قابلة للنقر. حذف الجذر فيزيائياً (set null على
  /// الخادم) يفتح ردوده هنا تلقائياً لأن ربطها يصبح null.
  static List<Map<String, dynamic>> mainFlow(List<Map<String, dynamic>> msgs) {
    return msgs.where((m) {
      final root = m[rootKey];
      return root is! String || root.isEmpty;
    }).toList();
  }

  /// رسائل سلسلة واحدة: الجذر أولاً (بأي ثبات وصل به) ثم ردودها
  /// بترتيب القائمة الواردة (مرتبة زمنياً من البثّ).
  static List<Map<String, dynamic>> threadMessages(
      List<Map<String, dynamic>> msgs, String rootId) {
    final root = msgs.where((m) => m['id'] == rootId).toList();
    final replies = msgs.where((m) => m[rootKey] == rootId).toList();
    return [...root, ...replies];
  }

  /// ملصق مصفوفة السلسلة: مفرد/جمع عربي سليم
  static String threadLabel(int count) {
    if (count <= 0) return 'سلسلة فارغة';
    if (count == 1) return 'ردّ واحد';
    if (count == 2) return 'ردّان';
    return '$count ردود';
  }

  /// نص استثناء الخادم لرسالة عربية واضحة
  static String pinErrorText(Object e) {
    final s = e.toString();
    if (s.contains('MAX_PINS')) return 'الحد الأقصى $kMaxPinsPerRoom مثبتات لكل محادثة';
    if (s.contains('admins only')) return 'التثبيت للمشرفين فقط في المجموعات';
    if (s.contains('message not found')) return 'الرسالة غير متاحة للتثبيت';
    return 'تعذّر تنفيذ العملية';
  }
}

/// wrappers الخادم — استدعاءات RPC مباشرة (نمط RoomPermissionsService)
class PinApi {
  const PinApi._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// تثبيت رسالة. يرمي استثناء الخادم (MAX_PINS / admins only / ...)
  static Future<void> pin(String messageId) async {
    await _c.rpc('pin_message', params: {'p_message': messageId});
  }

  /// إزالة تثبيت رسالة (idempotent على الخادم)
  static Future<void> unpin(String messageId) async {
    await _c.rpc('unpin_message', params: {'p_message': messageId});
  }

  /// مثبتات الغرفة (حتى [kMaxPinsPerRoom]) مرتبة أحدث تثبيتاً أولاً.
  /// كل صف يحمل message_id وsender_id وtype وcontent (يُفكّ محلياً)
  static Future<List<Map<String, dynamic>>> list(String conversationId) async {
    final rows = await _c.rpc('list_pins', params: {'p_conv': conversationId});
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  /// دوري في الغرفة كما يراه الخادم — لإظهار/إخفاء زر التثبيت محلياً
  /// (الفرض الحقيقي خادمي في can_pin). يعيد '' عند الفشل.
  static Future<String> myRole(String conversationId) async {
    try {
      final raw = await _c.rpc('my_room_perms', params: {'p_conv': conversationId});
      if (raw is Map<String, dynamic>) {
        final r = raw['role'];
        return r is String ? r : '';
      }
    } catch (_) {}
    return '';
  }
}
