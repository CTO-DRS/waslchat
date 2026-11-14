import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'e2e_service.dart';

/// أمن الأجهزة المرتبطة — إزالة جهاز كاملة (المرحلة 10 — 0.24.0).
///
/// إزالة جهاز من شاشة «الأجهزة المرتبطة» تحذف سجله ومخزون مفاتيحه الأولي
/// (والمكمم ML-KEM) من الخادم فوراً. هذا الملف يكمل الصورة محلياً:
///
/// 1. **بث الإزالة**: كل جهاز يصغي لحظياً لأحداث حذف صفوف `devices`
///    (المفاتيح في الجدول عامة أصلاً وسياسة القراءة تسمح للجميع)، فعند إزالة
///    أي جهاز — من أي حساب — تسقط جلساته v3 المخزّنة محلياً على من كان يملك
///    جلسة معه: أجهزة الحساب المُزال وأجهزة الأطراف معاً. لا انتظار ولا جلسة
///    يتيمة تشير إلى مفتاح لم يعد موجوداً.
/// 2. **المطابقة الدورية**: شبكة أمان إن فوّت جهازٌ حدث البث (انقطاع لحظي):
///    كل 10 دقائق وعند التسجيل تُقابل الجلسات المخزنة مع الأجهزة الحية
///    في الخادم ويُسقط كل ما لم يعد له سجل.
///
/// الفشل كله صامت ويهبط للسلوك السابق: جلسة لم تُسقط لا تُستخدم أصلاً لأن
/// المرسل لن يجد مفاتيحاً أولية للجهاز المُزال — الإسقاط نظافة أمنية لا شرط تشغيل.
class DeviceSecurityService {
  DeviceSecurityService._();

  static RealtimeChannel? _channel;
  static Timer? _reconcileTimer;
  static bool _busy = false;

  /// معرف الجهاز في مفتاح جلسة v3 مخزن — نقية وصرّاحة: «e2e_r3_<محادثة>#<جهاز>»
  /// والمحادثة نفسها لا تحمل # — null إن كان الشكل غير سليم (لا يُسقط أبداً على تخمين).
  static String? sessionDeviceId(String storageKey) {
    const prefix = 'e2e_r3_';
    if (!storageKey.startsWith(prefix)) return null;
    final rest = storageKey.substring(prefix.length);
    final i = rest.lastIndexOf('#');
    if (i <= 0 || i == rest.length - 1) return null;
    if (rest.substring(0, i).contains('#')) return null; // أكثر من فاصل — شكل غريب
    final dev = rest.substring(i + 1);
    if (dev.isEmpty) return null;
    return dev;
  }

  /// أي مفاتيح الجلسات المخزنة تعود لأجهزة لم تعد حية؟ — نقية للاختبار:
  /// المفتاح غير السليم يبقى كما هو (لا نلمس ما لا نفهمه)، والمفتاح السليم
  /// لجهاز حي يبقى، ولجهاز ميت يُسقط.
  static List<String> staleSessionKeys(
          List<String> keys, Set<String> liveDevices) =>
      keys.where((k) {
        final d = sessionDeviceId(k);
        return d != null && !liveDevices.contains(d);
      }).toList();

  /// تسجيل الإصغاء اللحظي + مطابقة أولى + دورية. صامتة دائماً (ناريَ ونسيان).
  static Future<void> attach() async {
    if (_channel != null) return;
    try {
      _channel = supabase
          .channel('wasl-device-security')
          .onPostgresChanges(
            event: PostgresChangeEvent.delete,
            schema: 'public',
            table: 'devices',
            callback: (payload) {
              final id = payload.oldRecord['id'];
              if (id is String && id.isNotEmpty) {
                unawaited(E2eService.dropDeviceSessions({id}));
              }
            },
          )
          .subscribe();
      unawaited(reconcile());
      _reconcileTimer =
          Timer.periodic(const Duration(minutes: 10), (_) => reconcile());
    } catch (_) {}
  }

  /// إلغاء الإصغاء (عند الخروج من الحساب)
  static Future<void> detach() async {
    _reconcileTimer?.cancel();
    _reconcileTimer = null;
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      try {
        await supabase.removeChannel(ch);
      } catch (_) {}
    }
  }

  /// مطابقة الجلسات المخزنة مع الأجهزة الحية (شبكة أمان البث اللحظي)
  static Future<int> reconcile() async {
    if (_busy) return 0;
    _busy = true;
    try {
      return await E2eService.reconcileDeviceSessions();
    } finally {
      _busy = false;
    }
  }
}
