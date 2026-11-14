/// خدمة الألبوم المتعدد (المرحلة 8 — 0.20.0): تجميع رسائل الوسائط المتسلسلة
/// التي تحمل `media_group_id` واحداً في فقاعة ألبوم واحدة.
///
/// منطق نقي بلا شبكة ولا واجهة — يُختبَر حصرياً في `album_service_test.dart`.
/// القواعد:
/// - القطع المتتالية (بترتيب العرض من الأقدم للأحدث) ذات المعرّف الواحد
///   والمرسل الواحد تجتمع في ألبوم واحد.
/// - أقصى قطع في الألبوم 10 (حد الإرسال من الواجهة؛ الأقدم تُعرض).
/// - الرسائل المحذوفة والمعاينة «عرض مرة واحدة» تكسر التتابع وتُعرض منفردة
///   (لأن فقاعتها الخاصة تتصرف بشكل مختلف).
/// - رسالة بلا معرّف = عنصر منفرد كالسابق تماماً.
class AlbumService {
  /// حد الألبوم عند الإرسال والعرض
  static const int maxItems = 10;

  /// يولّد معرّف مجموعة وسائط جديد (يستدعى من شاشة الإرسال)
  static String newGroupId() =>
      'alg_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  /// هل تصلح هذه الرسالة للانضمام لألبوم؟
  static bool isGroupable(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return false;
    if (m['view_once'] == true) return false;
    final t = m['type'] as String? ?? 'text';
    return t == 'image' || t == 'video';
  }

  /// تجميع قائمة الرسائل (الأقدم أولاً) إلى عناصر عرض:
  /// عنصر إما رسالة منفردة أو ألبوم (قائمة رسائل).
  /// العناصر تحفظ ترتيب أقدم عضو في المجموعة.
  static List<List<Map<String, dynamic>>> group(List<Map<String, dynamic>> msgs) {
    final out = <List<Map<String, dynamic>>>[];
    for (final m in msgs) {
      final gid = m['media_group_id'] as String?;
      if (gid == null || !isGroupable(m)) {
        out.add([m]);
        continue;
      }
      final last = out.isEmpty ? null : out.last;
      if (last != null && last.length < maxItems) {
        final head = last.first;
        // الرأس نفسه يجب أن يكون قابلاً للتجميع — المحذوفة وعرض-مرة-واحدة
        // كسرت التتابع ولا تفتح مجموعة
        final same = head['media_group_id'] == gid &&
            head['sender_id'] == m['sender_id'] &&
            isGroupable(m) &&
            isGroupable(head);
        if (same) {
          last.add(m);
          continue;
        }
      }
      out.add([m]);
    }
    return out;
  }

  /// عدد القطع القابلة للإرسال من المختارات (لعرضه في الواجهة)
  static String counterLabel(int picked) =>
      picked > maxItems ? 'أقصى المسموح $maxItems وسائط' : '$picked / $maxItems';
}
