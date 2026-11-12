/// اختيار ماسح QR حسب المنصة:
/// - الجوال (له dart:io): كاميرا حقيقية عبر mobile_scanner.
/// - الويب: بديل رسالة يعتمد المقارنة اليدوية (لا سلاسل كاميرا على الويب هنا).
export 'qr_scanner_stub.dart' if (dart.library.io) 'qr_scanner_mobile.dart';
