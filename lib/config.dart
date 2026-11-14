import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

/// ضع هنا بيانات مشروعك من Supabase:
/// Project Settings > API > Project URL و anon public key
class AppConfig {
  /// إصدار هذا البناء — يُحدّث مع كل إصدار (وليس تلقائياً)
  static const appVersion = '0.24.0';
  static const appBuild = 54;

  /// رابط الموقع الرسمي (يُستخدم لروابط الدعوة وصفحات الويب)
  static const siteUrl = 'https://waslchat.app';

  /// رابط تحميل آخر إصدار APK (Release في المستودع العام)
  static const apkUrl =
      'https://github.com/CTO-DRS/waslchat/releases/latest/download/wasl_chat.apk';

  /// رابط العودة للتطبيق بعد الدخول بجوجل أو استعادة كلمة المرور
  static String get authRedirect =>
      kIsWeb ? 'https://waslchat.app/web/' : 'app.waslchat://login-callback';
  static const supabaseUrl = 'https://hplzbillnbdjtufazrlp.supabase.co';
  static const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhwbHpiaWxsbmJkanR1ZmF6cmxwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQwMTAyNjAsImV4cCI6MjEwOTU4NjI2MH0.EqWiUY_Pl70-RTJ-CM2mZqpI8Du1xuAIk8BagRpB9FI';

  /// خوادم مراوغة الشبكة للمكالمات (WebRTC — المرحلة 6):
  /// - STUN عام من Google مجاني بلا حساب: يكفي معظم الشبكات المنزلية والجوال.
  /// - TURN اختياري يملؤه المالك وفق RUNBOOK (مزوّد مجاني مثل Metered أو
  ///   coturn ذاتي الاستضافة) لينجح الاتصال خلف NAT متماثل وجدران حماية
  ///   صارمة. بلا TURN يفشل الاتصال في بعض الشبكات وتظهر «تعذر الاتصال» —
  ///   بصدق: أثقل استهلاك TURN هو نقل الوسائط نفسه، فلا خادم مجاني يكفي نمواً.
  static const List<Map<String, String?>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    // {'urls': 'turn:your-server.example.com:3478?transport=udp',
    //  'username': 'owner-fills', 'credential': 'owner-fills'},
  ];
}

SupabaseClient get supabase => Supabase.instance.client;
