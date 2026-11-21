/// برنامج الاختبار الميداني داخل التطبيق (المرحلة 16 — النمو والاستدامة، 1.8.0+70).
///
/// بوابة إصدار النضج 2.0.0 هي اختبار ميداني واسع — وهذه الشاشة هي قناة
/// الانضمام: عائِل صادق (ما الذي يُختبر وما الذي لا يزال ناقصاً)، وانضمام
/// محلي بلا أي صف خادم يبصم تقرير ملاحظاتك ويهيئه، وتقرير اختبار مبني على
/// نظام الملاحظات القائم بترحيل 029 بتصنيفه نفسه.
///
/// الصدق التصميمي:
/// - الانضمام تسجيل محلي حصراً (مخزن آمن على جهازك): لا قائمة خادمية،
///   لا إشعارات جديدة، ولا تغيير سلوكي غير بصمة التقرير المعبأة.
/// - قناة الاختبار الرسمية (لو وُجدت) تفتحها الإدارة برمز دعوة عادي —
///   والشاشة تقول ذلك بلا ادعاء بوجودها.
/// - ما لا يزال ناقصاً معلَن هنا كما في TRANSPARENCY.md حرفياً — لا
///   برنامج اختبار يبيع وعداً لا تملكه الوثائق.
import 'package:material_ui/material_ui.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'feedback_service.dart';

/// مجال اختبار يختاره المجرّب
class BetaScope {
  const BetaScope(this.id, this.label, this.hint);
  final String id;
  final String label;
  final String hint;
}

class BetaProgramService {
  BetaProgramService._();

  static final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  static const _keyJoined = 'beta_joined';
  static const _keyScope = 'beta_scope';
  static const _keyJoinedAt = 'beta_joined_at';

  /// مجالات الاختبار الخمسة — تغطي محاور خارطة الفعل الفعلية
  static const List<BetaScope> scopes = [
    BetaScope('messages', 'الرسائل والتشفير',
        'النصوص والوسائط على الجلسة المتدرجة وما بعد الكم وشفافية المفاتيح'),
    BetaScope('calls', 'المكالمات والغرف',
        'المكالمات الفردية والمرئية وغرف الصوت حتى 8 والموجات والرن فوق القفل'),
    BetaScope('communities', 'المجتمعات والبوتات',
        'الغرف والقنوات والأدوار والإشراف الآلي وواجهة المطوّرين والمقترحات'),
    BetaScope('ai', 'وصل AI',
        'الردود والملخصات والبحث الدلالي والصياغة والتذكيرات — كلها على الجهاز'),
    BetaScope('all', 'كل شيء',
        'التطبيق كاملاً من أول فتح إلى آخر بوت — الاختبار الواسع قبل إصدار النضج'),
  ];

  /// استعادة مجال من قيمة مخزنة — أي غرابة تعود «كل شيء» (الأوسع والأصدق)
  static BetaScope scopeFrom(String? id) {
    for (final s in scopes) {
      if (s.id == id) return s;
    }
    return scopes.last;
  }

  /// ما الذي يُختبر في هذه المرحلة — نقاط فعلية من خارطة الطريق لا شعارات
  static const List<String> whatIsTested = [
    'الرسائل في الخاص والمجموعات بتشفير متدرج ووسائط بمفاتيح عشوائية لكل وسيط',
    'بدء الجلسات الهجين الكلاسيكي + ما بعد الكم (ML-KEM-768) والترقية بين الأجهزة',
    'شفافية المفاتيح بسجل إلحاقي بشهود خارجيون تحققها محلياً',
    'المكالمات الفردية الصوتية والمرئية وغرف الصوت الجماعية حتى 8 بموجات حية',
    'الرن فوق القفل بصوت حلقي وبطاقة ملء شاشة وشارة جودة الاتصال',
    'المجتمعات والقنوات العامة والأدوار والإشراف الآلي بمقترحات البوتات',
    'وصل AI على الجهاز: البحث الدلالي والملخص اليومي والصياغة والتذكيرات',
    'تعدد الأجهزة وسطح المكتب وويب PWA والإشعارات بإجراءاتها',
  ];

  /// ما الذي لا يزال ناقصاً — من الحدود الصادقة الموثقة لا من الافتراض
  static const List<String> whatIsMissing = [
    'Google Play وiOS غير منشورين بعد — قرارا المالك الماليان (25 و99 دولاراً) والمواد جاهزة',
    'TURN ذاتي الاستضافة غير منشور — بعض الشبكات الصارمة تفشل مكالماتها وتظهر «تعذر الاتصال»',
    'غرف الصوت فوق 8 تحتاج LiveKit — مؤجلة بوعي لقرار الميزانية',
    'الترحيلات الجديدة تحتاج تشغيلها من مالك الخادم في SQL Editor — من لم يشغّلها يجد ميزة ناقصة بصدق',
  ];

  /// إفصاح الانضمام الحرفي — يُعرض قبل الضغط وبعده
  static const joinDisclosure =
      'الانضمام تسجيل محلي على جهازك حصراً: يهيئ تقرير ملاحظاتك بقالب الاختبار ويبصمه بمجالك — '
      'لا يضيفك لأي قائمة على الخادم، ولا يغيّر أي إعداد، ولا يرسل شيئاً بنفسه. '
      'مغادرته ممكنة في أي لحظة من الشاشة نفسها.';

  /// قناة الاختبار الرسمية — بصدق لا ادعاء بوجودها
  static const channelNote =
      'قناة الاختبار الرسمية إن وُجدت تفتحها الإدارة برمز دعوة عادي تدخله من شاشة الدعوة — '
      'وملاحظاتك من هنا تصل فوراً بتصنيفها حتى بدون قناة.';

  /// حالة الانضمام — تقرؤها الشاشة لحظياً
  static final joined = ValueNotifier<bool>(false);
  static final scope = ValueNotifier<String?>(null);
  static String? _joinedAtIso;

  static DateTime? get joinedAt =>
      _joinedAtIso == null ? null : DateTime.tryParse(_joinedAtIso!);

  /// قراءة الحالة من المخزن الآمن عند فتح الشاشة
  static Future<void> load() async {
    try {
      final v = await _secure.read(key: _keyJoined);
      final on = v == 'on';
      scope.value = on ? await _secure.read(key: _keyScope) : null;
      _joinedAtIso = on ? await _secure.read(key: _keyJoinedAt) : null;
      joined.value = on;
    } catch (_) {
      // مخزن غير متاح — حالة «غير منضم» صادقة لا انهيار
      joined.value = false;
      scope.value = null;
      _joinedAtIso = null;
    }
  }

  /// الانضمام بمجال — يخزن محلياً ولا يلمس الخادم إطلاقاً
  static Future<void> join(String scopeId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    joined.value = true;
    scope.value = scopeFrom(scopeId).id;
    _joinedAtIso = now;
    try {
      await _secure.write(key: _keyJoined, value: 'on');
      await _secure.write(key: _keyScope, value: scopeFrom(scopeId).id);
      await _secure.write(key: _keyJoinedAt, value: now);
    } catch (_) {}
  }

  /// المغادرة — تمسح الأثر المحلي كله
  static Future<void> leave() async {
    joined.value = false;
    scope.value = null;
    _joinedAtIso = null;
    try {
      await _secure.delete(key: _keyJoined);
      await _secure.delete(key: _keyScope);
      await _secure.delete(key: _keyJoinedAt);
    } catch (_) {}
  }

  /// قالب تقرير الاختبار المعبأ مسبقاً — يفتح في شاشة الملاحظات بتصنيفها.
  /// نقية بحقن الإصدار والمنصة، ضمن حد الخادم 1500 حرفاً بعد التنظيف،
  /// وبلا أي محتوى حساس: حقول فراغ يملؤها المجرّب بنفسه.
  static String reportTemplate({
    required String scopeId,
    required String version,
    required String platform,
  }) {
    final s = scopeFrom(scopeId);
    final b = StringBuffer()
      ..writeln('[اختبار ميداني — ${s.label}]')
      ..writeln('إصدار التطبيق: $version · المنصة: $platform')
      ..writeln()
      ..writeln('مجال الاختبار: ${s.hint}')
      ..writeln()
      ..writeln('الخطوة التي كنت فيها: ')
      ..writeln('ما توقعته أن يحدث: ')
      ..writeln('ما حدث فعلاً: ')
      ..writeln()
      ..writeln('(ملاحظة خصوصية: لن أكتب هنا محتوى محادثاتي أو بيانات حساسة — كما ينصح الإفصاح أعلى الشاشة)');
    var out = b.toString();
    if (out.length > FeedbackService.maxLen) {
      out = out.substring(0, FeedbackService.maxLen).trim();
    }
    return out;
  }

  /// تسمية تاريخ الانضمام عربياً — «انضممت في 18 نوفمبر 2026»
  static String joinedAtLabel(DateTime joinedAt, DateTime now) {
    const months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    final d = joinedAt.toLocal();
    final sameYear = d.year == now.toLocal().year;
    return 'انضممت في ${d.day} ${months[d.month - 1]}'
        '${sameYear ? '' : ' ${d.year}'}';
  }
}
