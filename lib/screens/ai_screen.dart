import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_service.dart';
import '../theme.dart';

/// محادثة مع «وصل AI» (لا تُحفظ على الخادم)
class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _text = TextEditingController();
  final _turns = <Map<String, String>>[];
  bool _thinking = false;

  static const _ideas = [
    'اكتب لي رسالة تهنئة لصديق',
    'لخّص لي فكرة في ثلاث نقاط',
    'ترجم: See you tomorrow at 5',
    'اقترح اسماً لمجموعة العائلة',
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _text.text).trim();
    if (q.isEmpty || _thinking) return;
    _text.clear();
    setState(() {
      _turns.add({'role': 'user', 'text': q});
      _thinking = true;
    });
    try {
      final reply = await AiService.chat(_turns);
      if (mounted) setState(() => _turns.add({'role': 'model', 'text': reply}));
    } catch (_) {
      if (mounted) {
        setState(() => _turns.add({'role': 'model', 'text': 'تعذّر الوصول للمساعد الآن، حاول بعد قليل.'}));
      }
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _turns.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(children: [
          CircleAvatar(
            backgroundColor: WaslColors.violet,
            child: Icon(Icons.auto_awesome, color: Colors.white),
          ),
          SizedBox(width: 10),
          Text('وصل AI', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        actions: [
          if (_turns.isNotEmpty)
            IconButton(
              tooltip: 'محادثة جديدة',
              onPressed: () => setState(_turns.clear),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _turns.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const SizedBox(height: 40),
                    const Icon(Icons.auto_awesome, size: 56, color: WaslColors.violet),
                    const SizedBox(height: 12),
                    const Text('كيف أقدر أساعدك؟',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _ideas
                          .map((s) => ActionChip(label: Text(s), onPressed: () => _send(s)))
                          .toList(),
                    ),
                  ],
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length + (_thinking ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_thinking && i == 0) {
                      return const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('يفكّر...', style: TextStyle(color: WaslColors.violet)),
                        ),
                      );
                    }
                    final t = items[_thinking ? i - 1 : i];
                    final mine = t['role'] == 'user';
                    return Align(
                      alignment:
                          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                      child: GestureDetector(
                        onLongPress: () {
                          Clipboard.setData(ClipboardData(text: t['text']!));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('تم النسخ')));
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints:
                              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          decoration: BoxDecoration(
                            gradient: mine ? WaslColors.gradient : null,
                            color: mine ? null : WaslColors.darkSurface,
                            border: mine ? null : Border.all(color: const Color(0x33A855F7)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: SelectableText(t['text']!,
                              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5)),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(hintText: 'اسأل وصل AI...'),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration:
                    const BoxDecoration(shape: BoxShape.circle, gradient: WaslColors.gradient),
                child: IconButton(
                  onPressed: _thinking ? null : _send,
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
