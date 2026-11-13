import '../config.dart';

/// اسم المستخدم العام (المرحلة 4): روابط waslchat.app/@user
///
/// القواعد موحّدة مع ترحيل 025: 4–24 حرفاً إنجليزياً صغيراً ورقماً وشرطة
/// سفلية، مع كلمات محجوزة يفرضها الخادم. التغيير حر أول مرة ثم مرة كل
/// 24 ساعة (username_set يرفض ما دون ذلك بكلمة username cooldown).
class UsernameService {
  UsernameService._();

  static const minLength = 4;
  static const maxLength = 24;

  /// صيغة الاسم (بعد إزالة @ إن وُجدت) — مطابقة لقيد profiles_username_format
  static final RegExp format =
      RegExp('^[a-z0-9_]{$minLength,$maxLength}\$');

  /// إزالة @ من البداية إن وُجدت (قبل التحقق بالصيغة)
  static String stripAt(String raw) {
    final t = raw.trim().toLowerCase();
    return t.startsWith('@') ? t.substring(1) : t;
  }

  /// التطبيع كما يفعله الخادم: صغير + استبدال غير المسموح بشرطة سفلية
  static String normalize(String raw) =>
      stripAt(raw).replaceAll(RegExp('[^a-z0-9_]'), '_');

  /// رسالة خطأ عربية للصيغة، أو null إن كانت الصيغة سليمة
  static String? validationError(String raw) {
    final u = normalize(raw);
    if (u.length < minLength) {
      return 'قصير جداً — الحد الأدنى $minLength أحرف';
    }
    if (u.length > maxLength) {
      return 'طويل جداً — الحد الأعلى $maxLength حرفاً';
    }
    if (!format.hasMatch(u)) {
      return 'الأحرف الإنجليزية الصغيرة والأرقام والشرطة السفلية فقط';
    }
    return null;
  }

  /// رابط الملف الشخصي العام للمستخدم
  static String profileLink(String username) =>
      '${AppConfig.siteUrl}/@$username';

  /// يقبل: user، @user، https://waslchat.app/@user — يعيد الاسم أو null
  static String? parseFromInput(String input) {
    var t = input.trim().toLowerCase();
    if (t.isEmpty) return null;
    final m = RegExp(r'(?:https?://)?waslchat\.app/@([a-z0-9_]{4,24})/?$')
        .firstMatch(t);
    if (m != null) return m.group(1);
    t = stripAt(t);
    if (format.hasMatch(t)) return t;
    return null;
  }

  // ---------- استدعاءات الخادم ----------

  /// هل الاسم متاح؟ (الصيغة + غير محجوز + غير مستخدم — الخادم يقرر)
  static Future<bool> available(String raw) async {
    try {
      final r = await supabase.rpc('username_available',
          params: {'p_username': normalize(raw)});
      return r == true;
    } catch (_) {
      return false;
    }
  }

  /// تعيين اسم المستخدم. عند الفشل ترجم الرسالة مع errorLabel.
  static Future<String> set(String raw) async {
    final u = await supabase.rpc('username_set',
        params: {'p_username': normalize(raw)});
    return u as String;
  }

  /// ملف مستخدم باسمه بالضبط (لفتح محادثة من الرابط waslchat.app/@user)
  static Future<Map<String, dynamic>?> lookup(String raw) async {
    final data = await supabase.rpc('profile_by_username',
        params: {'p_username': normalize(raw)});
    final list = List<Map<String, dynamic>>.from(data as List);
    return list.isEmpty ? null : list.first;
  }

  /// ترجمة أخطاء username_set إلى عربية
  static String errorLabel(Object e) {
    final s = e.toString();
    if (s.contains('bad username format')) {
      return 'الصيغة غير صحيحة — إنجليزي صغير وأرقام وشرطة سفلية فقط';
    }
    if (s.contains('username taken')) return 'هذا الاسم محجوز أو مستخدم';
    if (s.contains('username cooldown')) {
      return 'يمكن تغيير اسم المستخدم مرة كل 24 ساعة';
    }
    return 'تعذّر حفظ اسم المستخدم';
  }
}
