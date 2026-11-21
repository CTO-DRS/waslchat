/// اسم المنصة الحالية بالعربية — يُستخدم لتسمية الجهاز في «الأجهزة المرتبطة».
/// التطبيق الشرطي: النسخ الأصلية (لها dart:io) تقرأ dart:io، والويب يستخدم البديل.
export 'platform_name_stub.dart' if (dart.library.io) 'platform_name_io.dart';
