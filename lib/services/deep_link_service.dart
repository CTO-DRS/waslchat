import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// خدمة روابط الدعوة العميقة: `app.waslchat://join/CODE` (المرحلة 1).
/// لا تفتح شاشات بنفسها — تضع الرمز في [pendingCode] وتستهلكه الشاشة الرئيسية
/// بعد تسجيل الدخول، فيعمل الرابط حتى لو فُتح التطبيق قبل الدخول.
class DeepLinkService {
  static StreamSubscription<Uri>? _sub;
  static bool _initialized = false;

  /// رمز الدعوة المنتظر (يُستهلك مرة واحدة من HomeScreen)
  static final ValueNotifier<String?> pendingCode = ValueNotifier(null);

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final links = AppLinks();
      // الرابط الذي فتح التطبيق أصلاً (من مغلقاً)
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
      // الروابط أثناء عمل التطبيق في الخلفية
      _sub = links.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {
      // لا مشكلة إن فشل الالتقاط — الانضمام يدوياً بالرمز متاح دائماً
    }
  }

  static void _handle(Uri uri) {
    final code = parseInvite(uri);
    if (code != null) pendingCode.value = code;
  }

  /// يستخرج رمز الدعوة من رابط waslchat://join/CODE — وإلا null
  static String? parseInvite(Uri uri) {
    if (uri.scheme != 'app.waslchat' || uri.host != 'join') return null;
    final seg = uri.pathSegments;
    if (seg.isEmpty || seg.first.trim().isEmpty) return null;
    return seg.first.trim().toUpperCase();
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
