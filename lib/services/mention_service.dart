import 'dart:convert';

/// الإشارة @ في المجموعات (بند المرحلة 1 — 0.4.5).
///
/// طبقتان منفصلتان قابلتان للاختبار:
/// - [MentionCodec]: ترميز/فك بنية النص المُشار فيه. الرسائل بلا إشارات
///   تبقى نصاً عادياً كما هي (توافق كامل مع الرسائل القديمة)، وعند وجود
///   إشارات يصير المحتوى JSON `{"t":tag,"x":النص,"m":[{u,s,e}]}` —
///   يُشفَّر كأي نص في المحادثات المشفّرة.
/// - [MentionTracker]: منطق التحرير — ضبط مدى كل إشارة عند أي تغيير
///   في النص (إدراج/حذف قبلها أو بعدها أو داخلها)، واستخراج استعلام
///   '@...' عند المؤشر لعرض منتقي الأعضاء.
class MentionCodec {
  MentionCodec._();

  static const String tag = 'wasl-text-v1';

  /// هل النص (الصريح بعد فك التشفير) من بنية الإشارات؟
  static bool isStructured(String plain) => plain.startsWith('{"t":"$tag"');

  /// بلا إشارات: يعيد النص كما هو حرفياً — صفر تغيير على المسار العادي.
  static String encode(String text, List<MentionSpan> mentions) {
    if (mentions.isEmpty) return text;
    return jsonEncode({
      't': tag,
      'x': text,
      'm': [
        for (final m in mentions)
          {'u': m.userId, 's': m.start, 'e': m.end}
      ],
    });
  }

  /// يفك البنية؛ يعيد null لأي نص عادي أو فاسد أو معبوث (تُعرض كما هي).
  /// المدى غير الصالح (خارج النص أو معكوس) يُهمَل فرادى.
  static StructuredText? decode(String plain) {
    if (!isStructured(plain)) return null;
    try {
      final m = jsonDecode(plain);
      if (m is! Map || m['t'] != tag) return null;
      final x = m['x'];
      if (x is! String) return null;
      final spans = <MentionSpan>[];
      final raw = m['m'];
      if (raw is List) {
        for (final e in raw) {
          if (e is! Map) continue;
          final u = e['u'];
          final s = e['s'];
          final en = e['e'];
          if (u is String && s is int && en is int) {
            if (s >= 0 && en <= x.length && s < en) {
              spans.add(MentionSpan(u, s, en));
            }
          }
        }
      }
      return StructuredText(text: x, mentions: spans);
    } catch (_) {
      return null;
    }
  }

  /// النص المعروض من أي محتوى صريح: يفك البنية إن وُجدت وإلا يعيد الأصل.
  static String displayText(String plain) => decode(plain)?.text ?? plain;
}

class StructuredText {
  const StructuredText({required this.text, required this.mentions});
  final String text;
  final List<MentionSpan> mentions;
}

/// إشارة داخل نص مرسَم: النص من [start] إلى [end) هو «@اسم».
class MentionSpan {
  const MentionSpan(this.userId, this.start, this.end);
  final String userId;
  final int start;
  final int end;
}

/// توكن حي أثناء التحرير — يُعدَّل مداه مع كل تغيير في النص.
class MentionToken {
  MentionToken(this.userId, this.name, this.start, this.end);
  final String userId;
  final String name;
  int start;
  int end;
  bool dead = false;
}

class MentionTracker {
  MentionTracker._();

  /// يضبط التوكنات بعد تغيّر النص من [oldText] إلى [newText]
  /// (خوارزمية أطول بادئة/لاحقة مشتركة):
  /// - إدراج أو حذف كامل قبل التوكن أو بعده: يُزاح المدى أو يبقى.
  /// - أي تقاطع مع المنطقة المتغيرة (تعديل داخل الاسم): توكن ميت —
  ///   إزالة حرف من «@اسم» تلغي الإشارة عمداً (نفس سلوك المحررات).
  static void adjust(List<MentionToken> tokens, String oldText, String newText) {
    if (tokens.isEmpty || oldText == newText) return;
    var p = 0;
    final minLen =
        oldText.length < newText.length ? oldText.length : newText.length;
    while (p < minLen && oldText.codeUnitAt(p) == newText.codeUnitAt(p)) {
      p++;
    }
    var s = 0;
    while (s < oldText.length - p &&
        s < newText.length - p &&
        oldText.codeUnitAt(oldText.length - 1 - s) ==
            newText.codeUnitAt(newText.length - 1 - s)) {
      s++;
    }
    final removedEnd = oldText.length - s; // نهاية المنطقة المتغيرة في القديم
    final delta = newText.length - oldText.length;
    for (final t in tokens) {
      if (t.dead) continue;
      // تقاطع مع المنطقة المتغيرة [p, removedEnd) (جزئي أو كامل) → توكن ميت
      if (t.end > p && t.start < removedEnd) {
        t.dead = true;
        continue;
      }
      if (t.start >= removedEnd) {
        t.start += delta;
        t.end += delta;
        if (t.start < 0 || t.end > newText.length) t.dead = true;
      }
    }
    tokens.removeWhere((t) => t.dead || t.end <= t.start);
  }

  /// استعلام الإشارة عند المؤشر: يعيد ما بعد آخر «@» قبل المؤشر
  /// (بلا فراغ/سطر جديد بينهما، و«@» ليست في وسط كلمة أو بريد).
  static String? queryAt(String text, int cursor) {
    if (cursor <= 0 || cursor > text.length) return null;
    var i = cursor - 1;
    while (i >= 0) {
      final ch = text[i];
      if (ch == ' ' || ch == '\n' || ch == '\t') return null;
      if (ch == '@') {
        if (i > 0) {
          final prev = text[i - 1];
          if (prev != ' ' && prev != '\n' && prev != '\t') return null;
        }
        return text.substring(i + 1, cursor);
      }
      i--;
    }
    return null;
  }
}
