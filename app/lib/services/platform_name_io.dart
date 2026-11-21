import 'dart:io';

/// اسم منصة الجوال/سطح المكتب بالعربية (يُستدعى فقط حيث يتوفر dart:io)
String devicePlatformLabel() {
  try {
    if (Platform.isAndroid) return 'أندرويد';
    if (Platform.isIOS) return 'آيفون';
    if (Platform.isMacOS) return 'ماك';
    if (Platform.isWindows) return 'ويندوز';
    if (Platform.isLinux) return 'لينكس';
  } catch (_) {}
  return 'جهاز';
}
