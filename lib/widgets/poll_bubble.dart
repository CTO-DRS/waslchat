import 'package:flutter/material.dart';

import '../services/poll_service.dart';
import '../theme.dart';

/// فقاعة استطلاع الرأي المشفّر (0.4.4).
///
/// - السؤال والخيارات مفكوكة التشفير قبل الوصول إلى هنا.
/// - الأصوات تُجمع من مصدرين ويُدمجان بالمعرّف: جلب أوليّ موجّه
///   (`loadVotes` — يغطي أصواتاً خارج نافذة الرسائل المحمّلة) والبث
///   الحي من شاشة المحادثة (`votes`).
/// - الفرز «الأحدث يفوز» في [PollService.tally].
class PollBubble extends StatefulWidget {
  const PollBubble({
    super.key,
    required this.content,
    required this.mine,
    required this.myId,
    required this.votes,
    required this.loadVotes,
    required this.onVote,
  });

  final PollContent content;
  final bool mine;
  final String myId;

  /// أصوات البث الحي (صفوف messages من نوع poll_vote)
  final List<Map<String, dynamic>> votes;

  /// جلب أوليّ موجّه لكل أصوات هذا الاستطلاع من الخادم
  final Future<List<Map<String, dynamic>>> Function() loadVotes;

  /// إرسال صوت (رقم الخيار) — تُدار كتابته وشاشته في شاشة المحادثة
  final void Function(int optionIndex) onVote;

  @override
  State<PollBubble> createState() => _PollBubbleState();
}

class _PollBubbleState extends State<PollBubble> {
  final Map<String, Map<String, dynamic>> _fetched = {}; // id -> row
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final rows = await widget.loadVotes();
      if (!mounted) return;
      setState(() {
        _fetched
          ..clear()
          ..addEntries(rows.map((r) => MapEntry(r['id'] as String, r)));
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _vote(int i) {
    if (_sending) return;
    final tally = _tally;
    if (tally.myChoice == i) return; // نفس الاختيار — لا صوت مكرر
    setState(() => _sending = true);
    widget.onVote(i);
    // إرسال صوت جديد يستبدل القديم («الأحدث يفوز») — يصل عبر البث الحي
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _sending = false);
    });
  }

  Map<String, Map<String, dynamic>> get _mergedVotes {
    final merged = <String, Map<String, dynamic>>{..._fetched};
    for (final r in widget.votes) {
      final id = r['id'] as String?;
      if (id != null) merged[id] = r;
    }
    return merged;
  }

  PollTally get _tally => PollService.tally(
        _mergedVotes.values,
        optionCount: widget.content.options.length,
        me: widget.myId,
      );

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    final mainText =
        widget.mine ? wasl.onBubbleMine : wasl.textPrimary;
    final subText = widget.mine
        ? wasl.onBubbleMine.withValues(alpha: 0.75)
        : wasl.textSecondary;
    final faintText = widget.mine
        ? wasl.onBubbleMine.withValues(alpha: 0.6)
        : wasl.textFaint;
    final tally = _tally;
    final maxCount =
        tally.counts.fold<int>(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(Icons.poll_rounded, size: 18, color: mainText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(widget.content.question,
                  style: TextStyle(
                      color: mainText,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          for (var i = 0; i < widget.content.options.length; i++)
            _optionRow(i, tally, maxCount, mainText, subText),
          const SizedBox(height: 6),
          Row(children: [
            Text(
              _loading ? '…' : _votersLabel(tally.totalVoters),
              style: TextStyle(color: subText, fontSize: 12),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tally.myChoice == null
                    ? 'اضغط على خيار للتصويت'
                    : 'صوتك: ${widget.content.options[tally.myChoice!]} — اضغط خياراً آخر لتغييره',
                style: TextStyle(color: faintText, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  /// صيغة الجمع العربية لعدد المصوّتين
  String _votersLabel(int n) {
    if (n == 0) return 'لا أصوات بعد';
    if (n == 1) return 'صوت واحد';
    if (n == 2) return 'صوتان';
    if (n >= 3 && n <= 10) return '$n أصوات';
    return '$n صوتاً';
  }

  Widget _optionRow(int i, PollTally tally, int maxCount,
      Color mainText, Color subText) {
    final wasl = context.wasl;
    final count = tally.counts[i];
    final isMine = tally.myChoice == i;
    final fraction =
        tally.totalVoters == 0 ? 0.0 : count / tally.totalVoters;
    // شريط مرجعي أدنى حتى يظهر الخيار بلا أصوات
    final width = maxCount == 0
        ? 0.0
        : (count == 0 ? 0.0 : (fraction * 100).clamp(12.0, 100.0));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _vote(i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isMine
                ? (widget.mine
                    ? wasl.onBubbleMine.withValues(alpha: 0.18)
                    : wasl.accent.withValues(alpha: 0.14))
                : (widget.mine
                    ? wasl.onBubbleMine.withValues(alpha: 0.08)
                    : wasl.glass),
            border: Border.all(
              color: isMine
                  ? (widget.mine
                      ? wasl.onBubbleMine.withValues(alpha: 0.7)
                      : wasl.accent.withValues(alpha: 0.8))
                  : (widget.mine
                      ? wasl.onBubbleMine.withValues(alpha: 0.25)
                      : wasl.border),
              width: isMine ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              // شريط النسبة في الخلفية
              if (width > 0)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  child: FractionallySizedBox(
                    widthFactor: width / 100,
                    child: Container(
                      decoration: BoxDecoration(
                        color: widget.mine
                            ? wasl.onBubbleMine.withValues(alpha: 0.14)
                            : wasl.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(widget.content.options[i],
                        style: TextStyle(
                            color: mainText,
                            fontSize: 15,
                            fontWeight:
                                isMine ? FontWeight.w700 : FontWeight.w500)),
                  ),
                  if (isMine)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Icon(Icons.check_circle_rounded,
                          size: 16,
                          color: widget.mine
                              ? wasl.onBubbleMine
                              : wasl.accent),
                    ),
                  const SizedBox(width: 6),
                  Text('$count',
                      style: TextStyle(
                          color: subText,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
