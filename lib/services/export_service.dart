/// خدمة تصدير المحادثة نصاً (المرحلة 8 — 0.20.0): تبني ملفاً نصياً من
/// الرسائل المفكوكة محلياً على جهاز صاحبها — لا شيء يُرفع لأي خادم.
///
/// منطق نقي بلا شبكة ولا واجهة — يُختبَر في `export_service_test.dart`.
class ExportService {
  /// تسميات أنواع الوسائط في التصدير (تطابق معاينات الشاشة)
  static String mediaLabel(Map<String, dynamic> m) {
    switch (m['type'] as String? ?? 'text') {
      case 'image':
        return m['view_once'] == true ? '📷 صورة (عرض مرة واحدة)' : '📷 صورة';
      case 'voice':
        final ms = (m['duration_ms'] as num?)?.toInt() ?? 0;
        return '🎤 رسالة صوتية (${_dur(ms)})';
      case 'video':
        return m['view_once'] == true ? '🎬 فيديو (عرض مرة واحدة)' : '🎬 فيديو';
      case 'file':
        return '📎 ملف';
      default:
        return '💬';
    }
  }

  static String _dur(int ms) {
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// بناء نص التصدير:
  /// [title] اسم المحادثة، [senderOf] اسم المرسل لمعرّفه («أنت» للمستخدم نفسه
  /// تُمرَّر عبر النص «أنت» من الواجهة)، [textOf] النص المفكوك لرسالة نصية
  /// أو وصف JSON للملف (تُمرَّر دالة الشاشة)، [now] تاريخ التصدير.
  /// الرسائل المحذوفة تُكتب كتسمية حذف، والمحذوف عمره معروض.
  static String buildText({
    required String title,
    required List<Map<String, dynamic>> msgs,
    required String Function(String userId) senderOf,
    required String? Function(Map<String, dynamic> m) textOf,
    required String myId,
    required DateTime now,
    required String appVersion,
  }) {
    final b = StringBuffer();
    b.writeln('تصدير محادثة «$title» — وصل شات');
    b.writeln('تاريخ التصدير: ${_date(now)}');
    b.writeln('عدد الرسائل: ${msgs.length}');
    b.writeln('الإصدار: $appVersion');
    b.writeln('──────────────────────');
    String? lastDay;
    for (final m in msgs) {
      final created = DateTime.tryParse(m['created_at'] as String? ?? '');
      final day = created == null ? null : _date(created);
      if (day != null && day != lastDay) {
        b.writeln();
        b.writeln('— $day —');
        lastDay = day;
      }
      final who = m['sender_id'] == myId ? 'أنت' : senderOf(m['sender_id'] as String? ?? '');
      final time = created == null ? '' : _time(created);
      final deleted = m['deleted_at'] != null;
      final body = deleted
          ? '🚫 حُذفت هذه الرسالة'
          : ((m['type'] as String? ?? 'text') == 'text'
              ? (textOf(m) ?? '🔒 رسالة مشفرة')
              : mediaLabel(m));
      b.writeln('[$time] $who: $body');
    }
    return b.toString();
  }

  /// اسم ملف التصدير الآمن (يزيل محارف المسمى الخطر ويقلم الطول)
  static String fileName(String title, DateTime now) {
    final safe = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r]'), '_')
        .trim();
    final t = safe.isEmpty ? 'محادثة' : (safe.length > 40 ? safe.substring(0, 40) : safe);
    final d = now.toIso8601String().substring(0, 10);
    return 'wasl_${t}_$d.txt';
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
