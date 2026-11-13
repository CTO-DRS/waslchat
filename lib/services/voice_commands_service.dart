/// الأوامر الصوتية بلا لمس (المرحلة 5 — v0.14.0): تجربة صوتية عبر خدمة
/// التعرّف الصوتي على الجهاز (speech_to_text) بالعربية — تنتقل بين التبويبات
/// وتفتح الشاشات بأمر منك دون لمس الشاشة.
///
/// الصدق التصميمي: التعرّف يُنفَّذ بخدمة النظام على جهازك (على أندرويد قد تمر
/// الصوتية عبر خدمة Google حسب الجهاز) — هذه الخدمة تعالج الأوامر نفسها محلياً
/// ولا يُرسل أي شيء إلى خادم وصل. غير مدعوم على سطح المكتب حالياً.
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../theme.dart';
import 'local_ai_service.dart';

/// أمر صوتي مُفهوم: الرمز (tab index أو إجراء) والتسمية للعرض.
class VoiceCommand {
  const VoiceCommand(this.action, this.label);
  final String action;
  final String label;
}

class VoiceCommandsService {
  VoiceCommandsService._();
  static final VoiceCommandsService instance = VoiceCommandsService._();

  final _speech = stt.SpeechToText();
  bool _initialized = false;

  /// متاح على الجهاز؟ (الويب وأندرويد وiOS — سطح المكتب لا)
  Future<bool> available() async {
    try {
      _initialized = await _speech.initialize(onStatus: (_) {}, onError: (_) {});
      return _initialized;
    } catch (_) {
      return false;
    }
  }

  /// يطابق نصاً منطوقاً مع أمر — تطبيع عربي متسامح.
  static VoiceCommand? parse(String spoken) {
    final n = LocalAiService.normalize(spoken).trim();
    if (n.isEmpty) return null;
    bool has(List<String> keys) => keys.any(n.contains);
    if (has(['المحادثات', 'المحادثه', 'الشات'])) {
      return const VoiceCommand('tab:0', 'المحادثات');
    }
    if (has(['المجتمعات', 'المجتمع'])) {
      return const VoiceCommand('tab:1', 'المجتمعات');
    }
    if (has(['القنوات', 'القناه'])) {
      return const VoiceCommand('tab:2', 'القنوات');
    }
    if (has(['المكالمات', 'المكالمه', 'الاتصالات'])) {
      return const VoiceCommand('tab:3', 'المكالمات');
    }
    if (has(['الاعدادات', 'الضبط'])) {
      return const VoiceCommand('tab:4', 'الإعدادات');
    }
    if (has(['وصل اي', 'الذكاء', 'المساعد'])) {
      return const VoiceCommand('ai', 'وصل AI');
    }
    if (has(['محادثه جديده', 'رساله جديده'])) {
      return const VoiceCommand('newchat', 'محادثة جديدة');
    }
    return null;
  }

  /// يستمع لمرة واحدة (حتى ~4.5 ثانية) ويعيد الأمر المفهوم أو null.
  /// [onHeard] يستقبل ما سُمع لحظياً لعرضه في الواجهة.
  /// التوقف تلقائي عند سكون 2 ثانية (pauseFor) — نقرأ آخر ما عُرف بعدها.
  Future<VoiceCommand?> listenOnce({void Function(String)? onHeard}) async {
    if (!_initialized) {
      _initialized = await available();
      if (!_initialized) return null;
    }
    try {
      await _speech.listen(
        onResult: (r) => onHeard?.call(r.recognizedWords),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          localeId: 'ar_SA',
          listenFor: const Duration(seconds: 4),
          pauseFor: const Duration(seconds: 2),
        ),
      );
      // نمنح التعرف مدته القصوى ثم نقرأ آخر نص معروف
      await Future.delayed(const Duration(milliseconds: 4600));
      final words = _speech.lastRecognizedWords;
      await _speech.stop();
      return parse(words);
    } catch (_) {
      try {
        await _speech.stop();
      } catch (_) {}
      return null;
    }
  }
}

/// ورقة الأوامر الصوتية: تشرح الأوامر المتاحة وتعرض ما سُمع.
/// تُستدعى من الشاشة الرئيسية بزر الميكروفون.
class VoiceCommandsSheet extends StatefulWidget {
  const VoiceCommandsSheet({super.key, required this.onCommand});
  final void Function(VoiceCommand command) onCommand;

  @override
  State<VoiceCommandsSheet> createState() => _VoiceCommandsSheetState();
}

class _VoiceCommandsSheetState extends State<VoiceCommandsSheet> {
  String _heard = '';
  String? _error;
  bool _listening = false;
  VoiceCommand? _result;

  static const _examples = <(String, String)>[
    ('«افتح المحادثات»', 'تبويب المحادثات'),
    ('«افتح المجتمعات»', 'تبويب المجتمعات'),
    ('«افتح القنوات»', 'تبويب القنوات'),
    ('«افتح المكالمات»', 'تبويب المكالمات'),
    ('«افتح الإعدادات»', 'تبويب الإعدادات'),
    ('«وصل الذكاء»', 'فتح مساعد وصل AI'),
    ('«محادثة جديدة»', 'بدء محادثة جديدة'),
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _listening = true;
      _error = null;
      _result = null;
      _heard = '';
    });
    final cmd = await VoiceCommandsService.instance.listenOnce(
      onHeard: (w) {
        if (mounted) setState(() => _heard = w);
      },
    );
    if (!mounted) return;
    setState(() {
      _listening = false;
      _result = cmd;
      if (cmd == null && _heard.isEmpty) {
        _error = 'لم أسمع شيئاً — تأكد من صلاحية الميكروفون ثم أعد المحاولة';
      } else if (cmd == null) {
        _error = 'لم أفهم الأمر — جرّب أحد الأوامر التالية';
      }
    });
    if (cmd != null) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        Navigator.pop(context);
        widget.onCommand(cmd);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('الأوامر الصوتية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('تحدث باقتضاب دون لمس الشاشة. التعرّف بخدمة جهازك — لا يُرسل شيء إلى خادم وصل',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.textTertiary)),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(minHeight: 84),
            decoration: BoxDecoration(
              color: context.glass,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.hairline),
            ),
            child: _listening
                ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text(_heard.isEmpty ? 'أستمع إليك…' : _heard,
                            style: const TextStyle(fontSize: 15))),
                  ])
                : _result != null
                    ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.check_circle, color: Color(0xFF2FBE63)),
                        const SizedBox(width: 8),
                        Text('تم: ${_result!.label}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ])
                    : Text(_error ?? '',
                        textAlign: TextAlign.center,
                        style:
                            const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _listening ? null : _start,
            icon: const Icon(Icons.mic_rounded),
            label: Text(_listening ? 'أستمع…' : 'تحدّث الآن'),
          ),
          const SizedBox(height: 14),
          for (final (say, does) in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.chevron_left, size: 16, color: WaslColors.teal),
                const SizedBox(width: 6),
                Text(say,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(does,
                    style: TextStyle(fontSize: 12, color: context.textTertiary)),
              ]),
            ),
        ]),
      ),
    );
  }
}
