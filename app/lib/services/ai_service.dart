import 'dart:convert';
import 'dart:typed_data';

import '../config.dart';

/// الاتصال بدالة «وصل AI» على Supabase
class AiService {
  static Future<String> _call(Map<String, dynamic> body) async {
    final res = await supabase.functions.invoke('ai', body: body);
    final data = res.data;
    if (data is Map && data['reply'] is String) return data['reply'] as String;
    if (data is Map && data['error'] != null) throw Exception(data['error']);
    throw Exception('رد غير متوقع');
  }

  /// turns: [{'role': 'user'|'model', 'text': '...'}]
  static Future<String> chat(List<Map<String, String>> turns) =>
      _call({'mode': 'chat', 'messages': turns});

  static Future<String> summarize(String conversationId) =>
      _call({'mode': 'summarize', 'conversation_id': conversationId});

  /// التلخيص بعد E2E: التطبيق يفك التشفير محلياً ويرسل الأسطر جاهزة
  static Future<String> summarizeLines(List<String> lines) =>
      _call({'mode': 'summarize_lines', 'lines': lines});

  /// target: 'ar' أو 'en'
  static Future<String> translate(String text, String target) =>
      _call({'mode': 'translate', 'text': text, 'target': target});

  /// تفريغ رسالة صوتية نصاً (المرحلة 5): يُرسل الصوت بترميز base64 بعد موافقة
  /// المستخدم الصريحة — يمر عبر خادم وصل إلى Gemini ولا يُخزَّن في أي منهما.
  /// [mime]: 'audio/mp4' (جوال/سطح مكتب) أو 'audio/webm' (ويب).
  static Future<String> transcribe(Uint8List bytes, {required String mime}) async {
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception('الصوت أطول من الحد المسموح');
    }
    return _call({
      'mode': 'transcribe',
      'audio_b64': base64Encode(bytes),
      'mime': mime,
    });
  }
}
