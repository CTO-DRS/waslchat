// ملف مؤقت. شغّل `flutterfire configure` وسيستبدله تلقائياً بإعدادات مشروعك.
// قبل ذلك يعمل التطبيق طبيعياً لكن بدون إشعارات.
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase غير مُعدّ بعد: شغّل flutterfire configure');
}
