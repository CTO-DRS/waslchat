import 'package:flutter/material.dart';

import '../config.dart';
import '../services/e2e_service.dart';
import '../services/smart_search_service.dart';
import '../services/unified_search_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'chat_screen.dart';

/// البحث الموحد فوق كل المحادثات (المرحلة 8 ب — 0.21.0)
///
/// يفتح من شريط القائمة الرئيسية: جلب رسائلك النصية الحديثة (مشفرة كما هي)
/// من الخادم، فك تشفيرها **على جهازك**، ثم بحث ذكي فوري أثناء الكتابة
/// بالمحرك نفسه المستخدم داخل المحادثة (تطبيع عربي + تسامح أخطاء + مرادفات).
///
/// الصدق الموثق: الاستعلام لا يغادر الجهاز — الخادم رأى النصوص المشفرة
/// أصلاً كما يرى القائمة، والفك والبحث يجريان محلياً حصراً.
class UnifiedSearchScreen extends StatefulWidget {
  const UnifiedSearchScreen({super.key});

  @override
  State<UnifiedSearchScreen> createState() => _UnifiedSearchScreenState();
}

class _UnifiedSearchScreenState extends State<UnifiedSearchScreen> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  String? _error;
  final List<UnifiedDoc> _docs = [];
  DateTime? _fetchedAt;

  // خريطة بيانات المحادثات لفتحها من النتيجة
  final Map<String, Map<String, dynamic>> _conv = {};
  // أسماء المرسلين (uid -> اسم)
  final Map<String, String> _names = {};

  static const int _fetchLimit = 1500;
  static const int _firstWave = 400; // الفوريات قبل الباقي بالخلفية

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
      // المحادثات: العناوين والأنواع والمقابل
      final chats = await supabase.rpc('my_chats');
      final chatList = List<Map<String, dynamic>>.from(chats as List);
      for (final c in chatList) {
        _conv[c['conversation_id'] as String] = c;
      }

      // أسماء المرسلين من my_chats نفسه للعناوين الفردية + جدول الملفات
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
      setState(() {
        _fetchedAt = DateTime.now();
        _loading = false;
      });
      // الموجة الأولى: الأحدث فك فوري ثم البحث متاح فوراً
      await _decryptWave(list.sublist(0, list.length > _firstWave ? _firstWave : list.length), me);
      if (!mounted) return;
      setState(() {});
      // الموجة الثانية بالخلفية (الأقدم) — النتائج تثرى وتبدو تلقائياً
      if (list.length > _firstWave) {
        await _decryptWave(list.sublist(_firstWave), me);
        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذّر جلب الرسائل للبحث — تحقق من الاتصال';
        });
      }
    }
  }

  /// فك دفعة رسائل إلى مستندات محلية — المحتوى الصريح يمر كما هو،
  /// والمشفر يفك حسب نوع المحادثة، والفاشل يُوثق «🔒» بلا ادعاء.
  Future<void> _decryptWave(List<Map<String, dynamic>> msgs, String me) async {
    for (final m in msgs) {
      final cid = m['conversation_id'] as String?;
      final content = m['content'] as String? ?? '';
      final c = _conv[cid];
      if (cid == null || c == null) continue; // رسالة محادثة أُغلقت؟ نتجاوز
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
      final senderId = m['sender_id'] as String? ?? '';
      final title = _titleOf(c);
      _docs.add(UnifiedDoc(
        conversationId: cid,
        title: title,
        messageId: m['id'] as String,
        text: plain,
        createdAtIso: m['created_at'] as String? ?? '',
        senderName: senderId == me ? 'أنت' : (_names[senderId] ?? ''),
        mine: senderId == me,
        isGroup: isGroup,
      ));
    }
  }

  String _titleOf(Map<String, dynamic> c) {
    final t = (c['title'] ?? '') as String;
    if (c['is_group'] != true) return t;
    if (E2eService.isEncrypted(t)) return 'مجموعة';
    return t;
  }

  /// فتح المحادثة من النتيجة — نفس بيانات صف القائمة
  void _openDoc(UnifiedDoc d) {
    final c = _conv[d.conversationId];
    if (c == null) return;
    final isGroup = c['is_group'] == true;
    final isBot = !isGroup && c['is_bot'] == true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: d.conversationId,
          title: d.title,
          isGroup: isGroup,
          otherId: c['other_id'] as String?,
          isBot: isBot,
          encrypted: isGroup || !isBot,
        ),
      ),
    );
  }

  /// مقتطف الرسالة مع إبراز الكلمات المطابقة
  Text _excerpt(UnifiedDoc d, String query, TextStyle base) {
    final text = d.text.length > 140 ? '${d.text.substring(0, 140)}…' : d.text;
    final spans2 = SmartSearchService.highlightSpans(text, query);
    if (spans2.isEmpty) return Text(text, style: base);
    final children = <TextSpan>[];
    var cursor = 0;
    for (final (start, len) in spans2) {
      if (start > cursor) {
        children.add(TextSpan(text: text.substring(cursor, start)));
      }
      children.add(TextSpan(
        text: text.substring(start, start + len),
        style: TextStyle(
          backgroundColor: WaslColors.teal.withValues(alpha: 0.18),
          fontWeight: FontWeight.w700,
          color: WaslColors.teal,
        ),
      ));
      cursor = start + len;
    }
    if (cursor < text.length) children.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: children, style: base),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _timeOf(String iso) {
    if (iso.isEmpty) return '';
    final d = DateTime.parse(iso).toLocal();
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}/${d.month}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text.trim();
    final hits = q.isEmpty ? const <UnifiedHit>[] : UnifiedSearchService.rank(_docs, q);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_forward),
          onPressed: () => Navigator.pop(context),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'ابحث في كل محادثاتك…',
            border: InputBorder.none,
            filled: false,
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {});
                    },
                  ),
          ),
        ),
      ),
      body: _loading
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 14),
                Text('يفك تشفير رسائلك محلياً للبحث…',
                    style: TextStyle(color: context.textTertiary, fontSize: 13)),
              ]),
            )
          : Column(children: [
              Expanded(
                child: q.isEmpty
                    ? _hintView()
                    : hits.isEmpty
                        ? _emptyView(q)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 40),
                            itemCount: hits.length,
                            itemBuilder: (context, i) {
                              final h = hits[i];
                              final d = h.doc;
                              final row = MotionStagger(
                                index: i.clamp(0, 10),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    radius: 22,
                                    backgroundColor: context.glass,
                                    child: Icon(
                                      d.isGroup
                                          ? Icons.groups_2
                                          : Icons.person_outline_rounded,
                                      size: 20,
                                      color: d.isGroup
                                          ? WaslColors.teal
                                          : WaslColors.indigo,
                                    ),
                                  ),
                                  title: Row(children: [
                                    Flexible(
                                      child: Text(d.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(_timeOf(d.createdAtIso),
                                        style: TextStyle(
                                            color: context.textFaint,
                                            fontSize: 11)),
                                  ]),
                                  subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (d.senderName.isNotEmpty &&
                                            !d.mine)
                                          Text(d.senderName,
                                              style: TextStyle(
                                                  color: WaslColors.teal,
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.w600)),
                                        _excerpt(
                                          d,
                                          q,
                                          TextStyle(
                                              color: context.textSecondary,
                                              fontSize: 13.5),
                                        ),
                                      ]),
                                  onTap: () => _openDoc(d),
                                ),
                              );
                              return row;
                            },
                          ),
              ),
              // الإفصاح الصادق أسفل الشاشة دائماً
              Material(
                color: context.glass,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: context.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        UnifiedSearchService.disclosure +
                            (_fetchedAt == null
                                ? ''
                                : ' · الجلب ${_timeOf(_fetchedAt!.toIso8601String())}'),
                        style: TextStyle(
                            color: context.textFaint, fontSize: 11, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }

  Widget _hintView() {
    return ListView(padding: const EdgeInsets.all(24), children: [
      GlassEmptyState(
        icon: Icons.search_rounded,
        title: 'ابحث في كل محادثاتك',
        subtitle: 'اكتب كلمة أو جزءاً منها — المحرك يفهم العربية:\n'
            'يتجاهل التشكيل والهمزات ويسامح الأخطاء المطبعية\nويوسّع بالمرادفات',
      ),
      const SizedBox(height: 12),
      Text(
        '${_docs.length} رسالة جاهزة للبحث على جهازك',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.textFaint, fontSize: 12),
      ),
    ]);
  }

  Widget _emptyView(String q) {
    if (_error != null) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        GlassEmptyState(
          icon: Icons.cloud_off_rounded,
          title: _error!,
          subtitle: 'البحث المحلي يعمل فوق رسائل جلبت سابقاً',
        ),
      ]);
    }
    return ListView(padding: const EdgeInsets.all(24), children: [
      GlassEmptyState(
        icon: Icons.search_off_rounded,
        title: 'لا نتائج عن «$q»',
        subtitle: SmartSearchService.capabilityHint,
      ),
    ]);
  }
}
