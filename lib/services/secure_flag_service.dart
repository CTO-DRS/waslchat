import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// منع لقطات الشاشة (FLAG_SECURE) على أندرويد بعدّاد مراجع:
/// محادثة واحدة محمية تكفي لإخفاء التطبيق من المشاركة ولقطات الشاشة،
/// ولا يُرفع العلم إلا بعد مغادرة كل المحادثات المحمية (دفع المحادثات فوق بعضها).
class SecureFlag {
  static const _channel = MethodChannel('app.waslchat.wasl_chat/secure');
  static int _refs = 0;

  /// فعّل الحماية (استدعِه عند دخول محادثة محمية)
  static Future<void> acquire() async {
    _refs++;
    if (_refs == 1) await _apply(true);
  }

  /// أعِل الحماية عند المغادرة — لا يُرفع العلم إلا إذا لم تبقَ محادثة محمية
  static Future<void> release() async {
    if (_refs > 0) _refs--;
    if (_refs == 0) await _apply(false);
  }

  static Future<void> _apply(bool secure) async {
    try {
      if (kIsWeb) return;
      if (defaultTargetPlatform != TargetPlatform.android) return;
      await _channel.invokeMethod('setSecure', {'secure': secure});
    } catch (_) {
      // فشل القناة لا يوقف الاستخدام (إصدارات أخرى من التطبيق مثلاً)
    }
  }
}
