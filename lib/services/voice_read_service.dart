/// القراءة الصوتية للرسائل (TTS عربي على الجهاز — المرحلة 8 ب، 0.21.0)
///
/// الفرصة العربية الفريدة: زر واحد يقرأ لك آخر رسائل المحادثة صوتياً
/// عربياً — أثناء القيادة أو ضعف البصر أو الكسل عن القراءة.
///
/// الخصوصية بالصدق: المحرك flutter_tts يعمل **على جهازك حصراً** عبر محرك
/// النطق المثبت بالنظام — لا يُرسل أي حرف لأي مكان ولا عبر وصل ولا لطرف
/// ثالث. إن لم يكن محرك عربي مثبتاً على الجهاز يعمل بأفضل ما يوفره النظام
/// (وهبوط لا خطأ).
///
/// بناء النص المراد قراءته نقي بالكامل (مُختبَر): تنظيف روابط وميات
/// وتسمية المرسل وحدود واضحة للطول.
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceReadService {
  VoiceReadService._();

  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  /// الحالة للواجهة: يقرأ الآن؟ (زر الإيقاف/التشغيل يرسم على أساسه)
  static final ValueNotifier<bool> speaking = ValueNotifier<bool>(false);

  static const int maxMessages = 10;
  static const int maxCharsPerMessage = 300;
  static const int maxTotalChars = 1500;

  /// يبني النص المراد قراءته من أسطر (اسم المرسل، النص المفكوك).
  /// - الرسائل تُمرَّر بالترتيب الزمني التصاعدي (الأقدم أولاً) وستُقرأ هكذا.
  /// - الروابط تُستبدل بكلمة «رابط» حتى لا تُنطق عناوينها الطويلة.
  /// - اسم المرسل يُنطق في المجموعات فقط (في الفردية يشتت).
  /// - علامات الترميز النصية تُسطّح (* _ ~ # `) حتى لا تُنطق.
  static String buildSpokenText(
    List<(String, String)> lines, {
    required bool isGroup,
  }) {
    final parts = <String>[];
    var total = 0;
    for (final (sender, raw) in lines.take(maxMessages)) {
      var text = _clean(raw);
      if (text.isEmpty) continue;
      if (text.length > maxCharsPerMessage) {
        text = '${text.substring(0, maxCharsPerMessage)}…';
      }
      final line = isGroup && sender.isNotEmpty ? '$sender: $text' : text;
      if (total + line.length > maxTotalChars) break;
      parts.add(line);
      total += line.length;
    }
    return parts.join('. ');
  }

  /// تنظيف نص للنطق: بلا روابط ولا ميتا ولا علامات ترميز ولا فراغات زائدة
  static String _clean(String raw) {
    var t = raw.trim();
    if (t.startsWith('{')) return ''; // ميتا ملف/فيديو — لا تُنطق
    // الروابط → «رابط»
    t = t.replaceAll(
        RegExp(r'https?://\S+', caseSensitive: false), 'رابط');
    // علامات الترميز النصية الشائعة
    t = t.replaceAll(RegExp(r'[*_~`#>]'), '');
    // إيموجي متكررة مشتتة للنطق: نكتفي بحذف رموز زخرفية شائعة
    // (unicode: true مطلوبة لفهم نطاقات \u{...} داخل فئة المحارف)
    t = t.replaceAll(
        RegExp('[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true), '');
    // فراغات متتالية
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  /// تهيئة المحرك واختيار العربية إن توفرت (بأفضل الجهد — لا رميات)
  static Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      try {
        final langs = await _tts.getLanguages;
        final list = langs is List ? langs : const [];
        final ar = list.where((l) => l.toString().toLowerCase().startsWith('ar')).toList();
        if (ar.isNotEmpty) {
          await _tts.setLanguage(ar.first.toString());
        } else {
          await _tts.setLanguage('ar');
        }
      } catch (_) {
        await _tts.setLanguage('ar');
      }
      await _tts.setSpeechRate(0.45); // وتيرة مريحة عربياً
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _ready = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// يقرأ نصاً جاهزاً (يجب أن يكون قد مر عبر buildSpokenText)
  static Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    if (!await ensureReady()) return false;
    try {
      speaking.value = true;
      final ok = await _tts.speak(text);
      if (ok != true) speaking.value = false;
      return ok == true;
    } catch (_) {
      speaking.value = false;
      return false;
    }
  }

  /// إيقاف فوري
  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }
}
