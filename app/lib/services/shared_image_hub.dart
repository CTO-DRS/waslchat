/// مركز الصورة المشتركة (1.22.0) — إتمام حلقة Web Share Target: الصورة
/// التي أرسلها المتصفح إلى وصل (عامل الصفحة خزّنها كاشاً بوسم) تُجلب
/// **مرة واحدة عند الإقلاع** ثم تُستهلك عند فتح أول دردشة فتمر بمحرر
/// الصورة المحلي نفسه ثم مسار الإرسال القائم `_sendMedia` — بلا مسار
/// موازاة وبلا رفع بلا قرار.
///
/// العقد الصادق:
/// 1. الجلب على الويب حصراً (`pull` تحرسها kIsWeb) — المنصات الأصلية
///    لا هدف مشاركة لها إطلاقاً والـstub يعيد null.
/// 2. الاستهلاك الواحد: أول دردشة تفتح تأخذ البايتات وتمسحها — لا صورة
///    تُرفق مرتين ولا تبقى معلقة إلى الأبد: عمر معلن 10 دقائق يُسقطها
///    بصدق إن لم تُستهلك.
/// 3. بلا شبكة هنا حصراً — البايتات في الذاكرة فقط حتى تمر بالمحرر.
library;

import 'package:flutter/foundation.dart';

import 'pwa_service.dart';

class SharedImageHub {
  SharedImageHub._();

  /// العمر المعلن قبل إسقاط الصورة غير المستهلكة
  static const Duration expiry = Duration(minutes: 10);

  static List<int>? _bytes;
  static DateTime? _pulledAt;

  /// ساعة قابلة للحقن للاختبار فقط
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// الجلب عند الإقلاع — ويب فقط، وفاشله صمت صادق (لا صورة ولا ادعاء)
  static Future<void> pull() async {
    if (!kIsWeb) return;
    try {
      final b = await PwaService.readSharedImage();
      if (b != null && b.isNotEmpty) {
        _bytes = b;
        _pulledAt = now();
      }
    } catch (_) {
      _bytes = null;
    }
  }

  /// هل توجد صورة بانتظار الاستهلاك (وغير منتهية)؟
  static bool get hasPending {
    final b = _bytes;
    if (b == null) return false;
    if (now().difference(_pulledAt!) > expiry) {
      _bytes = null;
      return false;
    }
    return true;
  }

  /// الاستهلاك الواحد — أول من يفتح دردشة يأخذ البايتات ويصفرها
  static List<int>? consume() {
    if (!hasPending) return null;
    final b = _bytes;
    _bytes = null;
    return b;
  }

  /// إسقاط صريح — للاختبار ولإغلاق صادق
  static void drop() => _bytes = null;

  /// بذر مباشر للاختبار فقط — يمثل ما يفعله الجلب على الويب
  @visibleForTesting
  static void debugSeed(List<int> b) {
    _bytes = b;
    _pulledAt = now();
  }
}
