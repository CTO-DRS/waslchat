import 'package:flutter/material.dart';

import '../services/poll_service.dart';
import '../theme.dart';

/// ناتج مُلحّن الاستطلاع: سؤال وخيارات نظيفة بعد التحقق
class PollDraft {
  const PollDraft({required this.question, required this.options});
  final String question;
  final List<String> options;
}

/// مُلحّن استطلاع الرأي (بند المرحلة 1 — 0.4.4).
/// يتحقق من الحدود قبل الإرسال: سؤال حتى 280 حرفاً، و2–10 خيارات،
/// كل خيار حتى 100 حرف، والمحتوى كله يُشفَّر قبل رفعه.
class PollComposerSheet extends StatefulWidget {
  const PollComposerSheet({super.key});

  /// يفتح الملحن ويعيد [PollDraft] أو null إن أُلغي
  static Future<PollDraft?> show(BuildContext context) =>
      showModalBottomSheet<PollDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.wasl.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => const PollComposerSheet(),
      );

  @override
  State<PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends State<PollComposerSheet> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= PollService.maxOptions) return;
    setState(() => _options.add(TextEditingController()));
  }

  void _removeOption(int i) {
    if (_options.length <= PollService.minOptions) return;
    setState(() {
      _options[i].dispose();
      _options.removeAt(i);
      _error = null;
    });
  }

  void _submit() {
    final q = _question.text.trim();
    final opts =
        _options.map((c) => c.text.trim()).where((e) => e.isNotEmpty).toList();
    if (q.isEmpty) {
      setState(() => _error = 'اكتب سؤال الاستطلاع');
      return;
    }
    if (q.length > PollService.maxQuestionLen) {
      setState(() => _error = 'السؤال أطول من ${PollService.maxQuestionLen} حرفاً');
      return;
    }
    if (opts.length < PollService.minOptions) {
      setState(() => _error = 'الاستطلاع يحتاج خيارين على الأقل');
      return;
    }
    if (opts.any((o) => o.length > PollService.maxOptionLen)) {
      setState(() => _error = 'كل خيار حتى ${PollService.maxOptionLen} حرفاً');
      return;
    }
    try {
      final plain = PollService.encodePoll(q, opts);
      if (!PollService.withinLimit(plain)) {
        setState(() => _error = 'الاستطلاع طويل جداً — اختصر السؤال أو الخيارات');
        return;
      }
    } catch (_) {
      setState(() => _error = 'تحقق من السؤال والخيارات');
      return;
    }
    Navigator.pop(context, PollDraft(question: q, options: opts));
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(children: [
                  Icon(Icons.poll_rounded, color: wasl.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('استطلاع رأي',
                        style: TextStyle(
                            color: wasl.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                      'السؤال والخيارات والأصوات مشفّرة بين الطرفين — يظهر للخادم من صوّت فقط، لا ما اختار',
                      style: TextStyle(color: wasl.textFaint, fontSize: 12)),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _question,
                        maxLength: PollService.maxQuestionLen,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                            labelText: 'السؤال',
                            hintText: 'مثال: ما أفضل وقت للقاء الأسبوعي؟'),
                        onChanged: (_) => setState(() => _error = null),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _options.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            Expanded(
                              child: TextField(
                                controller: _options[i],
                                maxLength: PollService.maxOptionLen,
                                textInputAction: i + 1 == _options.length
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                decoration: InputDecoration(
                                    labelText: 'الخيار ${i + 1}'),
                                onChanged: (_) => setState(() => _error = null),
                              ),
                            ),
                            if (_options.length > PollService.minOptions)
                              IconButton(
                                tooltip: 'حذف الخيار',
                                onPressed: () => _removeOption(i),
                                icon: Icon(Icons.remove_circle_outline,
                                    color: wasl.danger, size: 22),
                              ),
                          ]),
                        ),
                      if (_options.length < PollService.maxOptions)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _addOption,
                            icon: const Icon(Icons.add, size: 18),
                            label: Text(
                                'إضافة خيار (${_options.length}/${PollService.maxOptions})'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(_error!,
                        style: TextStyle(color: wasl.danger, fontSize: 13)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('إرسال الاستطلاع'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
