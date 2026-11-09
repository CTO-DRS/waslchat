import 'package:supabase_flutter/supabase_flutter.dart';

/// ضع هنا بيانات مشروعك من Supabase:
/// Project Settings > API > Project URL و anon public key
class AppConfig {
  /// رابط العودة للتطبيق بعد الدخول بجوجل أو استعادة كلمة المرور
  static const authRedirect = 'app.waslchat://login-callback';
  static const supabaseUrl = 'https://hplzbillnbdjtufazrlp.supabase.co';
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhwbHpiaWxsbmJkanR1ZmF6cmxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwMTAyNjAsImV4cCI6MjEwOTU4NjI2MH0.EqWiUY_Pl70-RTJ-CM2mZqpI8Du1xuAIk8BagRpB9FI';

  /// إصدار هذا البناء — حدّثه مع كل إصدار (يجب أن يطابق pubspec.yaml)
  /// يُقارن بجدول app_releases لإظهار شاشة «تحديث متوفر»
  static const int versionCode = 28;
  static const String versionName = '0.4.9';
}

SupabaseClient get supabase => Supabase.instance.client;
