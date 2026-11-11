import 'dart:typed_data';

/// غير مدعوم خارج الويب
void webDownload(Uint8List bytes, String name, String mime) {}

/// غير مدعوم خارج الويب
String webBlobUrl(Uint8List bytes, String mime) => '';

void webRevoke(String url) {}
