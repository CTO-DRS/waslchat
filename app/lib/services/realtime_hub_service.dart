/// مركز Realtime الواحد (المرحلة 13 ب — 1.2.0): قناة postgres واحدة منظمة
/// تحمل كل المشاهدين طويلة العمر بدل قنوات متفرقة تُفتح وتُغلق مع كل زيارة
/// شاشة — أقل انضمامات للخادم، وبطارية وشبكة أقل، ومحاسبة صريحة للمستهلكين
/// فالتسريب يُكشف بالعدّ لا يُدَّعى.
///
/// التصميم الصادق:
/// - القنوات اللحظية العابرة (غرف الصوت، إشارات المكالمات، الحضور) تبقى
///   قنوات مستقلة — فهي غرف بدورة حياة خاصة لا تنتمي للمركز.
/// - أحداث postgres تصل كما كانت تماماً (RLS يطبَّق على الخادم لحظة الحدث) —
///   لا تغيير على ما يراه الخادم ولا على الخصوصية إطلاقاً؛ الدمج تنظيمي
///   للنقل لا للتوسع في ما يصل.
/// - الجريانات بثّية (broadcast) بلا تخزين: المستمع الحاضر يسمع فقط، وغيابه
///   لا يراكم شيئاً ولا يعيده المركز.
/// - القناة تُنشأ مرة عند الدخول وتُفك مرة عند الخروج — وزيارة الشاشة لا
///   تفتح قناة جديدة إطلاقاً (كانت كل زيارة انضماماً وتركاً للخادم).
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

// ==================== النقي المُختبَر ====================

/// سجل المستهلكين النقي: من حاضر الآن ومن مكرر (تسريب محتمل) وكم إلحاقاً —
/// أرقام حتمية تُعرض في ورقة المؤشرات كما هي بلا تجميل.
class HubRegistry {
  final Map<String, int> _attachCount = {};
  final Set<String> _active = {};

  /// تسجيلات مكررة لمالك حاضر أصلاً — كل واحدة تسرّب محتمل يُكشف
  int duplicates = 0;

  /// المستهلكون الحاضرون الآن
  int get activeCount => _active.length;
  bool isActive(String key) => _active.contains(key);

  /// عدد مرات إلحاق مالك معين عبر حياته (للتشخيص)
  int attachCount(String key) => _attachCount[key] ?? 0;

  /// إلحاق مستهلك بمفتاح مالكه — true إن كان جديداً، وfalse إن كان المالك
  /// حاضراً أصلاً (المكرر لا يُقبل ثانية — وهذا هو التقليم: التسجيل الثاني
  /// يُرفض ويُحسب بدل أن يتراكم صامتاً)
  bool attach(String key) {
    if (key.isEmpty) return false;
    if (_active.contains(key)) {
      duplicates++;
      return false;
    }
    _active.add(key);
    _attachCount[key] = (_attachCount[key] ?? 0) + 1;
    return true;
  }

  /// فك إلحاق — آمن التكرار: غير الحاضر لا يغيّر شيئاً
  bool detach(String key) => _active.remove(key);

  /// إيقاف كامل (عند الخروج): يفك كل الحاضرين ويعيد عددهم — بلا تسريب صامت
  int stopAll() {
    final n = _active.length;
    _active.clear();
    return n;
  }

  /// سطر تشخيص صادق: الحاضرون والمكررات بأسمائها
  String statsLabel() =>
      'مشاهدو المركز: ${_active.length} حاضر · مكررات مرفوضة: $duplicates';
}

// ==================== المركز — القناة الواحدة ====================

class RealtimeHubService {
  RealtimeHubService._();

  /// السجل النقي — يقرؤه التشخيص والاختبارات
  static final HubRegistry registry = HubRegistry();

  /// القناة الواحدة لكل مشاهدي postgres طويلة العمر
  static RealtimeChannel? _channel;
  static bool _started = false;

  // جرَيانات بثّ حية — المستهلك يلحق ويطفئ عند dispose حصراً
  // (الجريان بلا تخزين: المستمع الحاضر يسمع فقط وغيابه لا يراكم شيئاً)
  static final _messagesInsertedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  static final _callInsertedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  static final _callUpdatedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();
  static final _devicesRemovedCtrl =
      StreamController<Map<String, dynamic>>.broadcast();

  /// إدراج رسالة جديدة (تحديث قائمة المحادثات وإشعار سطح المكتب)
  static Stream<Map<String, dynamic>> get messagesInserted =>
      _messagesInsertedCtrl.stream;

  /// إدراج مكالمة (الواردات وسجل المكالمات)
  static Stream<Map<String, dynamic>> get callInserted =>
      _callInsertedCtrl.stream;

  /// تحديث مكالمة قائمة (حالة السجل: رُفضت/انتهت/فائتة…)
  static Stream<Map<String, dynamic>> get callUpdated =>
      _callUpdatedCtrl.stream;

  /// حذف جهاز (إزالة جهاز كاملة — إسقاط الجلسات الميتة)
  static Stream<Map<String, dynamic>> get devicesRemoved =>
      _devicesRemovedCtrl.stream;

  /// بدء القناة الواحدة بفلاترها الأربعة — مرة واحدة عند الدخول؛ الفشل
  /// يهبط للسلوك السابق ببدءٍ لاحق (نبضة إعادة من start مرة أخرى)
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _channel = supabase
          .channel('wasl-hub')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            callback: (p) => _emit(_messagesInsertedCtrl, p.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'calls',
            callback: (p) => _emit(_callInsertedCtrl, p.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            callback: (p) => _emit(_callUpdatedCtrl, p.newRecord),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'devices',
            callback: (p) => _emit(_devicesRemovedCtrl, p.oldRecord),
          )
          .subscribe();
    } catch (e) {
      debugPrint('realtime hub start failed: $e');
      _started = false; // يسمح بإعادة المحاولة عند الاستدعاء التالي
    }
  }

  /// فك القناة كلها عند الخروج — وتصفير السجل بصدق
  static Future<void> stop() async {
    _started = false;
    final ch = _channel;
    _channel = null;
    try {
      if (ch != null) {
        await ch.unsubscribe();
        await supabase.removeChannel(ch);
      }
    } catch (_) {}
    final leaked = registry.stopAll();
    if (leaked > 0) {
      debugPrint('realtime hub: $leaked مستهلكاً لم يفك إلحاقه قبل التوقف');
    }
  }

  /// هل القناة حية الآن؟ (للتشخيص الصادق)
  static bool get isLive => _started && _channel != null;

  static void _emit(StreamController<Map<String, dynamic>> sink,
      Map<String, dynamic> row) {
    try {
      if (!sink.hasListener) return; // لا أحد يسمع — لا شيء يُراكم ولا يُحسب
      sink.add(Map<String, dynamic>.from(row));
    } catch (_) {}
  }
}
