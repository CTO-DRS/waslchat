import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../services/ask_wasl_service.dart';
import '../services/e2e_service.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// «اسأل وصل» — أرشيفك يجيبك محلياً (المرحلة 14 أ — 1.3.0)
///
/// سؤالك عن رسائلك يجاب من المقاطع ذات الصلة التي ينتقيها البحث الدلالي
/// المتجهي على جهازك حصراً: الخادم رأى النصوص مشفرة كما يراها في القائمة،
/// والسؤال والفك والانتقاء والبناء كلها محلية — ولا يغادر أي حرف لأي مكان.
/// كل إجابة تعلن مصدرها (المحادثة والتاريخ) والفشل الصادق يعلن «لا أجد».
class AskWaslScreen extends StatefulWidget {
  const AskWaslScreen({super.key});

  @override
  State<AskWaslScreen> createState() => _AskWaslScreenState();
}

class _AskWaslScreenState extends State<AskWaslScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _thinking = false;
  String? _error;
  AskAnswer? _answer;

  final List<AskPassage> _passages = [];
  // بيانات المحادثات لأسماء المصادر وفتحها من الإجابة
  final Map<String, Map<String, dynamic>> _conv = {};
  final Map<String, String> _names = {};
  final Map<String, String> _titles = {};

  static const int _fetchLimit = 1200;
  static const int _firstWave = 400;

  static const _examples = [
    'متى اتفقنا على الموعد؟',
    'من أرسل العنوان؟',
    'ماذا قلنا عن المشروع؟',
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    try {
      final me = supabase.auth.currentUser!.id;
      final chats = await supabase.rpc('my_chats');
      final chatList = List<Map<String, dynamic>>.from(chats as List);
      for (final c in chatList) {
        final cid = c['conversation_id'] as String?;
        if (cid == null) continue;
        _conv[cid] = c;
        _titles[cid] = _titleOf(c);
      }
      try {
        final profs = await supabase
            .from('profiles')
            .select('id, display_name, username')
            .inFilter(
                'id',
                (chatList
                        .map((c) => c['other_id'] as String?)
                        .whereType<String>()
                        .toList()))
            .limit(200);
        for (final p in List<Map<String, dynamic>>.from(profs)) {
          _names[p['id'] as String] =
              (p['display_name'] as String?) ?? (p['username'] as String?) ?? '';
        }
      } catch (_) {}

      // الرسائل النصية الحديثة — الخادم يعيدها مشفرة كما هي
      final msgs = await supabase
          .from('messages')
          .select('id, conversation_id, sender_id, content, type, created_at, deleted_at')
          .eq('type', 'text')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false)
          .limit(_fetchLimit);
      final list = List<Map<String, dynamic>>.from(msgs);
      if (!mounted) return;
      setState(() => _loading = false);
      // الموجة الأولى: الأحدث فك فوري ثم السؤال متاح
      await _decryptWave(list.sublist(0, list.length > _firstWave ? _firstWave : list.length), me);
      if (!mounted) return;
      setState(() {});
      // الموجة الثانية بالخلفية — الأرشيف يثرى تلقائياً
      if (list.length > _firstWave) {
        await _decryptWave(list.sublist(_firstWave), me);
        if (mounted) setState(() {});
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر جلب الرسائل للسؤال — تحقق من الاتصال';
        });
      }
    }
  }

  /// فك دفعة رسائل إلى مقاطع محلية — المشفر يفك حسب نوع المحادثة
  /// والفاشل يُوثق «🔒» ويُسقط بلا ادعاء.
  Future<void> _decryptWave(List<Map<String, dynamic>> msgs, String me) async {
    for (final m in msgs) {
      final cid = m['conversation_id'] as String?;
      final content = m['content'] as String? ?? '';
      final c = _conv[cid];
      if (cid == null || c == null) continue;
      final isGroup = c['is_group'] == true;
      final otherId = c['other_id'] as String?;
      String plain = content;
      if (E2eService.isEncrypted(content)) {
        try {
          final p = isGroup
              ? await E2eService.decryptGroupText(cid, content)
              : (otherId == null
                  ? null
                  : await E2eService.decryptDmText(cid, otherId, content));
          plain = p ?? '🔒';
        } catch (_) {
          plain = '🔒';
        }
      }
      if (plain == '🔒' || plain.trim().isEmpty) continue;
      _passages.add(AskPassage(
        conversationId: cid,
        text: plain,
        createdAtIso: m['created_at'] as String? ?? '',
      ));
    }
  }

  String _titleOf(Map<String, dynamic> c) {
    final t = (c['title'] ?? '') as String;
    if (c['is_group'] != true) return t;
    if (E2eService.isEncrypted(t)) return 'مجموعة';
    return t;
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _ctrl.text).trim();
    if (q.isEmpty || _thinking) return;
    if (preset != null) _ctrl.text = preset;
    setState(() {
      _thinking = true;
      _answer = null;
    });
    // مهلة إطار واحد لتظهر حالة التفكير قبل الحساب المحلي السريع
    await Future<void>.delayed(const Duration(milliseconds: 24));
    if (!mounted) return;
    final a = AskWaslService.answer(_passages, q);
    setState(() {
      _answer = a;
      _thinking = false;
    });
  }

  /// فتح المحادثة من سطر الإجابة — نفس بيانات صف القائمة
  void _openLine(AskLine l) {
    final c = _conv[l.conversationId];
    if (c == null) return;
    final isGroup = c['is_group'] == true;
    final isBot = !isGroup && c['is_bot'] == true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: l.conversationId,
          title: _titles[l.conversationId] ?? 'محادثة',
          isGroup: isGroup,
          otherId: c['other_id'] as String?,
          isBot: isBot,
          encrypted: isGroup || !isBot,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'رجوع من اسأل وصل',
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: const Row(children: [
          CircleAvatar(
            backgroundColor: WaslColors.teal,
            child: Icon(Icons.question_answer_rounded, color: Colors.white, size: 20),
          ),
          SizedBox(width: 10),
          Text('اسأل وصل', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: _loading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text('يفك تشفير أرشيفك محلياً للسؤال…',
                    style: TextStyle(color: context.textTertiary, fontSize: 13)),
              ]),
            )
          : (_error != null
              ? Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textTertiary))))
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _ask(),
                      decoration: InputDecoration(
                        hintText: 'اسأل عن شيء في رسائلك…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                        suffixIcon: IconButton(
                          tooltip: 'اسأل وصل',
                          icon: const Icon(Icons.arrow_upward_rounded,
                              color: WaslColors.teal),
                          onPressed: () => _ask(),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 15, color: context.textTertiary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          AskWaslService.disclosure,
                          style: TextStyle(
                              color: context.textTertiary, fontSize: 11.5),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: _thinking
                        ? const Center(child: CircularProgressIndicator())
                        : _answer == null
                            ? (_answerEmptyAsked ? _noAnswerView() : _hintView())
                            : _answerView(_answer!),
                  ),
                ])),
    );
  }

  bool get _answerEmptyAsked => _ctrl.text.trim().isNotEmpty;

  Widget _hintView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 30),
        const Icon(Icons.question_answer_rounded, size: 54, color: WaslColors.teal),
        const SizedBox(height: 12),
        const Text('أرشيفك يجيبك',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('اسأل عن شيء ورد في رسائلك — يجيب وصل من رسائلك المفكوكة على جهازك حصراً ويعلن مصدر كل جواب',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textTertiary, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: _examples
              .map((s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => _ask(s)))
              .toList(),
        ),
      ],
    );
  }

  Widget _noAnswerView() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 30),
        Icon(Icons.search_off_rounded, size: 54, color: context.textTertiary),
        const SizedBox(height: 12),
        const Text('لا أجد ما يكفي في أرشيفك لهذا السؤال',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('جرّب كلمات أخرى من رسائلك — الإجابة استخلاص من رسائلك لا تخمين، فلا أقول ما ليس في أرشيفك',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textTertiary, fontSize: 13, height: 1.5)),
      ],
    );
  }

  Widget _answerView(AskAnswer a) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Text('بناءً على أرشيفك — ${a.lines.length} مقطع ذو صلة:',
            style: TextStyle(color: context.textTertiary, fontSize: 12.5)),
        const SizedBox(height: 10),
        for (final l in a.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openLine(l),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.bubbleOther,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x2294A3B8)),
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('«${l.text}»',
                          style: const TextStyle(
                              fontSize: 14.5, height: 1.55)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.chat_bubble_outline_rounded,
                            size: 13,
                            color: WaslColors.teal),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${_titles[l.conversationId] ?? 'محادثة'}'
                            ' · ${_whenOf(l.atIso)}',
                            style: TextStyle(
                                color: context.textTertiary, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_left_rounded,
                            size: 16, color: context.textTertiary),
                      ]),
                    ]),
              ),
            ),
          ),
        Text('الإجابة استخلاص من رسائلك على جهازك حصراً — انقر أي مقطع لفتح محادثته',
            style: TextStyle(color: context.textTertiary, fontSize: 11)),
      ],
    );
  }

  String _whenOf(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.year}/${d.month}/${d.day}';
  }
}
