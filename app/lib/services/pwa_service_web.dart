/// تنفيذ الويب الحي لخدمة PWA — يُستدعى حصراً على kIsWeb عبر التوجيه الشرطي.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'share_target_rules.dart';

/// حالة الـService Worker المعروضة في الإعدادات (نص التقرير الصادق)
final ValueNotifier<String> _workerStatus = ValueNotifier<String>('جارٍ الفحص…');

/// هل المتصفح يقدّم التثبيت الآن (beforeinstallprompt وصل)؟
final ValueNotifier<bool> _installable = ValueNotifier<bool>(false);

/// التطبيق يعمل نافذة مثبّتة (display-mode: standalone)؟
final ValueNotifier<bool> _standalone = ValueNotifier<bool>(false);

bool _swSupported = false;
JSObject? _deferredPrompt;
Timer? _poll;

class PwaService {
  static ValueNotifier<String> get workerStatus => _workerStatus;
  static ValueNotifier<bool> get installable => _installable;
  static ValueNotifier<bool> get standalone => _standalone;

  /// هل الميزة متاحة في هذا المتصفح أصلاً؟
  static bool get supported => _swSupported;

  static void init() {
    try {
      final sw = (web.window.navigator as JSObject)
          .getProperty('serviceWorker'.toJS);
      _swSupported = sw != null;
    } catch (_) {
      _swSupported = false;
    }
    if (!_swSupported) {
      _workerStatus.value = 'المتصفح لا يدعم وضع العمل دون اتصال';
      return;
    }
    try {
      final mq = web.window.matchMedia('(display-mode: standalone)');
      _standalone.value = mq.matches;
      mq.addEventListener('change', _onModeChange.toJS);
    } catch (_) {
      _standalone.value = false;
    }
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    _check();
  }

  static void _onModeChange(web.Event _) {
    try {
      _standalone.value =
          web.window.matchMedia('(display-mode: standalone)').matches;
    } catch (_) {}
  }

  /// حدث التثبيت يحفظه index.html على النافذة، وتقرير الـworker من
  /// getRegistration حصراً — أي غرابة تُسقط بصدق لا تُخمَّن.
  static Future<void> _check() async {
    try {
      final p = web.window.getProperty('__waslDeferredPrompt'.toJS);
      if (p != null && p.isA<JSObject>()) _deferredPrompt = p as JSObject;
      final can = web.window.getProperty('__waslCanInstall'.toJS);
      if (can != null && can.isA<JSBoolean>()) {
        _installable.value =
            (can as JSBoolean).toDart && _deferredPrompt != null;
      }
    } catch (_) {}

    try {
      final reg = await _getRegistration();
      if (reg == null) {
        _workerStatus.value = 'لم يُسجَّل بعد — أعد فتح الصفحة';
      } else {
        final waiting = reg.getProperty('waiting'.toJS);
        _workerStatus.value = waiting != null
            ? 'يوجد تحديث جاهز — أعد فتح التطبيق ليُفعَّل'
            : 'يعمل دون اتصال جزئياً — الواجهة تُفتح بلا شبكة';
        _poll?.cancel(); // التقرير استقر — أوقف الفحص الدوري
      }
    } catch (_) {
      _workerStatus.value = 'المتصفح لا يدعم وضع العمل دون اتصال';
      _poll?.cancel();
    }
  }

  static Future<web.ServiceWorkerRegistration?> _getRegistration() async {
    try {
      return await web.window.navigator.serviceWorker.getRegistration().toDart;
    } catch (_) {
      return null;
    }
  }

  /// تثبيت التطبيق — يستدعي prompt() على حدث beforeinstallprompt المُلتقط.
  /// يُعاد «accepted» أو «dismissed» أو null إن لم يوجد حدث (متصفح لا يدعم).
  static Future<String?> install() async {
    final p = _deferredPrompt;
    if (p == null) return null;
    try {
      p.callMethod('prompt'.toJS);
      final choice = await (p.getProperty('userChoice'.toJS) as JSPromise)
          .toDart
          .then((r) => (r as JSObject).getProperty('outcome'.toJS) as JSString?)
          .then((s) => s?.toDart);
      _deferredPrompt = null;
      _installable.value = false;
      return choice;
    } catch (_) {
      return null;
    }
  }

  /// Web Share Target (1.21.0): قراءة الصورة المشتركة من كاش عامل الصفحة
  /// بعد العودة بوسم ?share= — الوسم يُتحقق بقواعد `ShareTargetRules`
  /// **قبل أي جلب**، والملف كاش محلي حصراً لا يغادر الجهاز. يُعاد
  /// بايتات الصورة أو null بصدق (لا وسم صالح أو فشل جلب)، ويُمسح الوسم
  /// من العنوان بعد القراءة كي لا يُعاد جلبه عند التحديث.
  static Future<List<int>?> readSharedImage() async {
    List<int>? bytes;
    try {
      final uri = Uri.parse(web.window.location.href);
      final token = ShareTargetRules.tokenFromQuery(uri.queryParameters);
      if (token != null) {
        final resp = web.window
                .callMethod('fetch'.toJS, '__share__/$token'.toJS)
            as JSObject;
        final status = resp.getProperty('status'.toJS).dartify();
        if (status == 200) {
          final blob =
              await (resp.callMethod('blob'.toJS) as JSPromise).toDart
                  as JSObject;
          final buf = await (blob.callMethod('arrayBuffer'.toJS) as JSPromise)
                  .toDart as JSArrayBuffer;
          bytes = buf.toDart.asUint8List();
        }
      }
    } catch (_) {
      bytes = null;
    } finally {
      try {
        // تنظيف الوسم من العنوان — التحديث لا يعيد قراءة ما قُرئ
        web.window.history.callMethod(
            'replaceState'.toJS, null, ''.toJS, '/web/'.toJS);
      } catch (_) {}
    }
    return bytes;
  }

  static void dispose() => _poll?.cancel();
}
