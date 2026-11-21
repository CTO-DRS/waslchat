import '../config.dart';
import 'e2e_service.dart';

/// «رسائلي المحفوظة» (المرحلة 4): سحابة شخصية لكل مستخدم.
///
/// محادثة kind='saved' عضوها الوحيد صاحبها، تُظهر مرة واحدة أعلى قائمة
/// المحادثات. رسائلها تُشفَّر بمفتاح محادثة يُغلَّف لنفسه بنفس تقنية
/// المجموعات — الخادم يخزّن نصاً مشفراً كأي مجموعة خاصة، والنص يقرؤه
/// من يحمل مفتاحك فقط.
class SavedService {
  SavedService._();

  static const title = 'رسائلي المحفوظة';

  /// جلب (أو إنشاء عند أول استخدام) معرّف محادثة المحفوظة
  static Future<String> id() async {
    final r = await supabase.rpc('saved_chat_get');
    return r as String;
  }

  /// آخر رسالة في المحفوظة: (content, type, created_at) أو null إن كانت فارغة
  static Future<Map<String, dynamic>?> lastMessage() async {
    final data = await supabase.rpc('saved_chat_preview');
    final list = List<Map<String, dynamic>>.from(data as List);
    return list.isEmpty ? null : list.first;
  }

  /// سطر المعاينة: نوع الوسيط برمزته، والنص يُفك إن كان مشفراً
  static Future<String> previewLine(Map<String, dynamic>? last) async {
    if (last == null) return 'احفظ رسائلك وملفاتك هنا';
    switch (last['type']) {
      case 'image':
        return '📷 صورة';
      case 'voice':
        return '🎤 رسالة صوتية';
      case 'video':
        return '🎬 فيديو';
      case 'file':
        return '📎 ملف';
    }
    final raw = (last['message'] as String?) ?? '';
    if (!E2eService.isEncrypted(raw)) return raw;
    try {
      final cid = await id();
      return await E2eService.previewGroup(conversationId: cid, content: raw);
    } catch (_) {
      return '🔒 رسالة مشفرة';
    }
  }
}
