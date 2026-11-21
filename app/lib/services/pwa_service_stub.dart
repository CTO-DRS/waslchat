/// بديل غير الويب لخدمة PWA: كل المنصات الأصلية (أندرويد/iOS/سطح المكتب)
/// مثبّتة أصلاً — لا تثبيت متصفح ولا Service Worker، والتقارير تُعلن ذلك بصدق.
import 'package:flutter/foundation.dart';

final ValueNotifier<String> _workerStatus =
    ValueNotifier<String>('لا يطبق — منصة أصلية مثبّتة أصلاً');
final ValueNotifier<bool> _installable = ValueNotifier<bool>(false);
final ValueNotifier<bool> _standalone = ValueNotifier<bool>(true);

class PwaService {
  static ValueNotifier<String> get workerStatus => _workerStatus;
  static ValueNotifier<bool> get installable => _installable;
  static ValueNotifier<bool> get standalone => _standalone;
  static bool get supported => false;

  static void init() {}

  static Future<String?> install() async => null;

  /// Web Share Target (1.21.0): لا هدف مشاركة على المنصات الأصلية —
  /// الصورة المشتركة من المتصفح لا تمر هنا إطلاقاً، والـnull صادق بلا ادعاء.
  static Future<List<int>?> readSharedImage() async => null;

  static void dispose() {}
}
