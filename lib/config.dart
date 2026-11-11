import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// ضع هنا بيانات مشروعك من Supabase:
/// Project Settings > API > Project URL و anon public key
class AppConfig {
  /// إصدار هذا البناء — يُحدّث مع كل إصدار (وليس تلقائياً)
  static const appVersion = '0.6.0';
  static const appBuild = 31;

  /// رابط تحميل آخر إصدار APK (Release في المستودع العام)
  static const apkUrl =
      'https://github.com/CTO-DRS/waslchat/releases/latest/download/wasl_chat.apk';

  /// رابط العودة للتطبيق بعد الدخول بجوجل أو استعادة كلمة المرور
  static String get authRedirect =>
      kIsWeb ? 'https://waslchat.app/web/' : 'app.waslchat://login-callback';
  static const supabaseUrl = 'https://hplzbillnbdjtufazrlp.supabase.co';
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhwbHpiaWxsbmJkanR1ZmF6cmxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwMTAyNjAsImV4cCI6MjEwOTU4NjI2MH0.EqWiUY_Pl70-RTJ-CM2mZqpI8Du1xuAIk8BagRpB9FI';
}

SupabaseClient get supabase => Supabase.instance.client;
