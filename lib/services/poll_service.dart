import 'dart:convert';

/// استطلاعات الرأي المشفّرة (بند المرحلة 1 — 0.4.4).
///
/// المحتوى كله داخل التشفير بين الطرفين: رسالة `type='poll'` تحمل
/// JSON مشفّراً للسؤال والخيارات، ورسالة `type='poll_vote'` تحمل JSON
/// مشفّراً لرقم الخيار. الخادم لا يرى سوى رابط الصوت بالاستطلاع
/// (عمود poll_id — بيانات وصفية موثّقة في TRANSPARENCY.md).
///
/// فرز الأصوات: «الأحدث يفوز» — آخر صوت لكل مستخدم هو صوته النافذ
/// (تغيير الرأي = إرسال صوت جديد)، كما في واتساب.
class PollService {
  PollService._();

  static const int minOptions = 2;
  static const int maxOptions = 10;
  static const int maxQuestionLen = 280;
  static const int maxOptionLen = 100;

  /// حدّ الترميز قبل التشفير (حد التشفير 2900 بايت نصاً صريحاً)
  static const int maxPlainBytes = 2400;

  static const String _tag = 'wasl-poll-v1';
  static const String _voteTag = 'wasl-poll-vote-v1';

  // ---------- تأليف الاستطلاع ----------

  /// يرمّي [ArgumentError] عند أي تجاوز — الملحن يتحقق قبل الاستدعاء
  /// ويعرض الخطأ للمستخدم، وهذه طبقة ثانية تمنع محتوى فاسداً.
  static String encodePoll(String question, List<String> options) {
    final q = question.trim();
    final opts = options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (q.isEmpty || q.length > maxQuestionLen) {
      throw ArgumentError('poll question length');
    }
    if (opts.length < minOptions || opts.length > maxOptions) {
      throw ArgumentError('poll options count');
    }
    if (opts.any((o) => o.length > maxOptionLen)) {
      throw ArgumentError('poll option length');
    }
    return jsonEncode({'t': _tag, 'q': q, 'o': opts});
  }

  static PollContent? decodePoll(String plain) {
    try {
      final m = jsonDecode(plain);
      if (m is! Map || m['t'] != _tag) return null;
      final q = m['q'];
      final o = m['o'];
      if (q is! String || q.isEmpty || q.length > maxQuestionLen) return null;
      if (o is! List ||
          o.length < minOptions ||
          o.length > maxOptions ||
          o.any((e) => e is! String || e.isEmpty || e.length > maxOptionLen)) {
        return null;
      }
      return PollContent(question: q, options: List<String>.from(o));
    } catch (_) {
      return null;
    }
  }

  /// هل يمرّ المحتوى حدّ البايتات قبل التشفير؟
  static bool withinLimit(String plain) =>
      utf8.encode(plain).length <= maxPlainBytes;

  // ---------- التصويت ----------

  static String encodeVote(int index) {
    if (index < 0) throw ArgumentError('vote index');
    return jsonEncode({'t': _voteTag, 'c': index});
  }

  static int? decodeVote(String plain) {
    try {
      final m = jsonDecode(plain);
      if (m is! Map || m['t'] != _voteTag) return null;
      final c = m['c'];
      if (c is! int || c < 0) return null;
      return c;
    } catch (_) {
      return null;
    }
  }

  // ---------- الفرز ----------

  /// يحسب النتائج من صفوف رسائل poll_vote كما وصلت من الخادم.
  /// - يتجاهل المحذوفة والفاسدة والخارج عن نطاق الخيارات.
  /// - «الأحدث يفوز»: صوت كل مستخدم النافذ هو آخر صوت له زمنياً.
  /// - الترتيب الزمني يُطبَّق هنا حتى لو جاءت الصفوف بترتيب مختلف.
  static PollTally tally(
    Iterable<Map<String, dynamic>> voteRows, {
    required int optionCount,
    required String me,
  }) {
    final latest = <String, (String, int)>{}; // sender -> (sortKey, choice)
    for (final row in voteRows) {
      if (row['deleted_at'] != null) continue;
      final sender = row['sender_id'] as String?;
      if (sender == null || sender.isEmpty) continue;
      final plain = row['content'] as String? ?? '';
      final choice = decodeVote(plain);
      if (choice == null || choice >= optionCount) continue;
      final createdAt = row['created_at'];
      final key = createdAt is String ? createdAt : '';
      final prev = latest[sender];
      if (prev == null || key.compareTo(prev.$1) >= 0) {
        latest[sender] = (key, choice);
      }
    }
    final counts = List<int>.filled(optionCount, 0);
    final choiceByUser = <String, int>{};
    for (final e in latest.entries) {
      counts[e.value.$2]++;
      choiceByUser[e.key] = e.value.$2;
    }
    return PollTally(
      counts: counts,
      totalVoters: latest.length,
      choiceByUser: choiceByUser,
      myChoice: latest[me]?.$2,
    );
  }
}

class PollContent {
  const PollContent({required this.question, required this.options});
  final String question;
  final List<String> options;
}

class PollTally {
  const PollTally({
    required this.counts,
    required this.totalVoters,
    required this.choiceByUser,
    required this.myChoice,
  });

  /// عدد أصوات كل خيار (بنفس ترتيب خيارات الاستطلاع)
  final List<int> counts;

  /// عدد المصوّتين (وليس عدد الأصوات — آخر صوت فقط لكل شخص)
  final int totalVoters;

  /// اختيار كل مستخدم — لعرض الأسماء على الخيار مستقبلاً
  final Map<String, int> choiceByUser;

  /// صوتي النافذ (null إن لم أصوّت)
  final int? myChoice;
}
