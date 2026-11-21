import 'dart:async';

import 'package:app_links/app_links.dart';

/// 2.0.2: روابط waslchat.app/@user — تفتح محادثة المستخدم مباشرة.
/// يغطي الفتح البارد (getInitialLink) والروابط أثناء التشغيل (uriLinkStream).
/// الاستهلاك: main.dart يستدعي init ويمرر معالجاً يستقبل اسم المستخدم المطبَّع.
class DeepLinkService {
  DeepLinkService._();
  static final _links = AppLinks();
  static StreamSubscription<Uri>? _sub;

  static void init(void Function(String username) onProfileLink) {
    _sub?.cancel();
    _sub = _links.uriLinkStream.listen((uri) {
      final u = parse(uri);
      if (u != null) onProfileLink(u);
    }, onError: (_) {});
    // الفتح البارد: الرابط الذي شغّل التطبيق أصلاً
    _links.getInitialLink().then((uri) {
      if (uri == null) return;
      final u = parse(uri);
      if (u != null) onProfileLink(u);
    }).catchError((_) {});
  }

  /// يقبل https://waslchat.app/@user — يعيد الاسم أو null لغير روابط الملف
  static String? parse(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final m = RegExp(r'^/@([a-z0-9_]{4,24})/?$').firstMatch(uri.path);
    return m?.group(1);
  }
}
