import 'package:supabase_flutter/supabase_flutter.dart';

/// ضع هنا بيانات مشروعك من Supabase:
/// Project Settings > API > Project URL و anon public key
class AppConfig {
  static const supabaseUrl = 'https://YOUR-PROJECT.supabase.co';
  static const supabaseAnonKey = 'YOUR-ANON-KEY';
}

SupabaseClient get supabase => Supabase.instance.client;
