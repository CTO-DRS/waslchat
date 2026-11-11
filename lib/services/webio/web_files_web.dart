import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// يحفظ البايتات (المفكوكة) كملف عبر المتصفح
void webDownload(Uint8List bytes, String name, String mime) {
  final url = webBlobUrl(bytes, mime);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(const Duration(seconds: 30), () => webRevoke(url));
}

/// رابط blob مؤقت لتشغيل صوت أو فيديو داخل الصفحة
String webBlobUrl(Uint8List bytes, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  return web.URL.createObjectURL(blob);
}

void webRevoke(String url) => web.URL.revokeObjectURL(url);
