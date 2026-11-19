import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/shield_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/wasl_sheet.dart';

Color _sevColor(String s) => switch (s) {
      'critical' => Colors.redAccent,
      'high' => const Color(0xFFF97316),
      'medium' => const Color(0xFFF59E0B),
      _ => Colors.grey,
    };

/// لوحة Wasl Shield للمدير العام: البلاغات والأدلة والإجراءات وسجل التدقيق.
/// الشاشة محمية من الالتقاط طوال فتحها؛ وكل إجراء يتحقق منه الخادم مستقلاً.
class ShieldAdminScreen extends StatefulWidget {
  const ShieldAdminScreen({super.key});

  @override
  State<ShieldAdminScreen> createState() => _ShieldAdminScreenState();
}

class _ShieldAdminScreenState extends State<ShieldAdminScreen> {
  String? _filter;
  List<Map<String, dynamic>> _cases = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    ScreenshotService.setSecure(true);
    _load();
  }

  @override
  void dispose() {
    ScreenshotService.setSecure(false);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ShieldService.adminCases(status: _filter);
      if (mounted) setState(() {
        _cases = c;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyAudit() async {
    try {
      final r = await ShieldService.adminVerifyAudit();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['ok'] == true
              ? '✅ سجل التدقيق سليم (${r['checked']} قيداً)'
              : '⚠️ انكسار في السلسلة عند القيد ${r['broken_at']}')));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('بلاغات Wasl Shield', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'سجل التدقيق',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const _AuditScreen(caseId: null)))),
          IconButton(tooltip: 'تحقق من سلامة السجل', icon: const Icon(Icons.fact_check_rounded), onPressed: _verifyAudit),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
          children: [
            Wrap(spacing: 8, children: [
              for (final f in <String?>[null, 'new', 'reviewing', 'action_taken', 'closed'])
                ChoiceChip(
                  label: Text(f == null ? 'الكل' : shieldStatus[f]!),
                  selected: _filter == f,
                  onSelected: (_) {
                    setState(() => _filter = f);
                    _load();
                  },
                ),
            ]),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_cases.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: Text('لا توجد بلاغات', style: TextStyle(color: context.textFaint))),
              )
            else
              GlassGroup([
                for (final c in _cases)
                  ListTile(
                    leading: Container(
                      width: 10,
                      height: 44,
                      decoration: BoxDecoration(
                          color: _sevColor(c['severity'] as String), borderRadius: BorderRadius.circular(6)),
                    ),
                    title: Text('${shieldCategories[c['category']] ?? c['category']} · ${c['ref']}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                        '${shieldSeverity[c['severity']]}${c['urgent'] == true ? ' · عاجل' : ''} · '
                        '${shieldStatus[c['status']]} · ${c['evidence']} دليل\n'
                        'من ${c['reporter_name'] ?? '—'} ضد ${c['target_name'] ?? 'غير محدد'}',
                        style: TextStyle(fontSize: 12.5, color: context.textTertiary, height: 1.4)),
                    isThreeLine: true,
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ShieldCaseScreen(caseId: c['id'] as String)));
                      _load();
                    },
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}

class ShieldCaseScreen extends StatefulWidget {
  const ShieldCaseScreen({super.key, required this.caseId});
  final String caseId;

  @override
  State<ShieldCaseScreen> createState() => _ShieldCaseScreenState();
}

class _ShieldCaseScreenState extends State<ShieldCaseScreen> {
  Map<String, dynamic>? _d;
  List<Map<String, dynamic>> _thread = [];
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    ScreenshotService.setSecure(true);
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _load() async {
    try {
      final d = await ShieldService.adminCase(widget.caseId);
      final t = await ShieldService.adminThread(widget.caseId);
      if (mounted) setState(() {
        _d = d;
        _thread = t;
      });
    } catch (_) {
      _snack('تعذّر تحميل البلاغ');
    }
  }

  /// كل إجراء يطلب مبرراً مكتوباً يُحفظ في سجل التدقيق
  Future<String?> _reason(String title, {String hint = 'المبرر (إلزامي — يُسجَّل في سجل التدقيق)'}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () {
                if (c.text.trim().length < 5) return;
                Navigator.pop(ctx, c.text.trim());
              },
              child: const Text('تنفيذ')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<void> _act(Future<void> Function() f, String ok) async {
    try {
      await f();
      _snack(ok);
      _load();
    } catch (e) {
      final s = e.toString();
      _snack(s.contains('protected')
          ? 'الحساب محمي (مدير أو رسمي)'
          : s.contains('no target')
              ? 'لا يوجد طرف محدد في هذا البلاغ'
              : 'تعذّر التنفيذ');
    }
  }

  Future<void> _openEvidence(Map<String, dynamic> e) async {
    try {
      final bytes = await ShieldService.adminOpenEvidence(e['id'] as String);
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => _EvidenceViewer(bytes: bytes, mime: (e['mime'] as String?) ?? '')));
    } catch (_) {
      _snack('تعذّر فتح الدليل');
    }
  }

  Future<void> _quarantine() async {
    final media = await ShieldService.adminCaseMedia(widget.caseId);
    final live = media.where((m) => m['quarantined'] != true).toList();
    if (!mounted) return;
    if (live.isEmpty) {
      _snack('لا توجد وسائط نشطة من الطرف المبلَّغ عنه في هذه المحادثة');
      return;
    }
    final r = await _reason('إبطال روابط ${live.length} وسيط',
        hint: 'تُنقل للحجر فتتعطل كل الروابط السابقة خلال دقيقة تقريباً، وتبقى نسخة محفوظة كدليل. المبرر:');
    if (r == null) return;
    await _act(() async {
      final n = await ShieldService.adminQuarantine(widget.caseId, [for (final m in live) m['message_id'] as String], r);
      if (n == 0) throw Exception('none');
    }, 'تم إبطال الروابط ونقل الوسائط للحجر');
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    if (d == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final c = Map<String, dynamic>.from(d['case'] as Map);
    final rep = d['reporter'] as Map?;
    final tgt = d['target'] as Map?;
    final ev = (d['evidence'] as List).cast<Map>();
    final q = (d['quarantine'] as List).cast<Map>();
    final status = c['status'] as String;
    return Scaffold(
      appBar: AppBar(
        title: Text('بلاغ ${c['ref']}', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'سجل هذا البلاغ',
              icon: const Icon(Icons.receipt_long_rounded),
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => _AuditScreen(caseId: widget.caseId)))),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _sevColor(c['severity'] as String).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _sevColor(c['severity'] as String).withValues(alpha: 0.35)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${shieldCategories[c['category']]} · خطورة ${shieldSeverity[c['severity']]}'
                    '${c['urgent'] == true ? ' · عاجل' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text('الحالة: ${shieldStatus[status]} · ${(c['created_at'] as String).substring(0, 16)}',
                    style: TextStyle(color: context.textTertiary, fontSize: 12.5)),
                const SizedBox(height: 10),
                Text(c['description'] as String, style: const TextStyle(height: 1.6)),
              ]),
            ),
            const SheetSectionLabel('الأطراف'),
            GlassGroup([
              ListTile(
                leading: UserAvatar(name: (rep?['name'] ?? '?') as String, url: rep?['avatar_url'] as String?),
                title: Text('${rep?['name'] ?? '—'}  (المبلِّغ)'),
                subtitle: Text('@${rep?['username'] ?? ''}'),
              ),
              if (tgt != null)
                ListTile(
                  leading: UserAvatar(name: (tgt['name'] ?? '?') as String, url: tgt['avatar_url'] as String?),
                  title: Text('${tgt['name'] ?? '—'}  (المبلَّغ عنه)'),
                  subtitle: Text('@${tgt['username'] ?? ''}'
                      '${tgt['banned'] == true ? ' · معلَّق' : ''}'
                      '${tgt['media_restricted'] == true ? ' · ممنوع من الوسائط' : ''}'),
                ),
            ]),
            SheetSectionLabel('الأدلة (${ev.length}) — كل فتح يُسجَّل'),
            if (ev.isEmpty)
              Text('لم تُرفق أدلة', style: TextStyle(color: context.textFaint))
            else
              GlassGroup([
                for (final e in ev)
                  ListTile(
                    leading: TintIcon(Icon(
                        e['kind'] == 'messages' ? Icons.forum_rounded : Icons.perm_media_rounded,
                        color: WaslColors.indigo)),
                    title: Text(e['kind'] == 'messages' ? 'سجل رسائل' : (e['mime'] as String? ?? 'وسيط')),
                    subtitle: Text('${((e['size_bytes'] as num? ?? 0) / 1024).toStringAsFixed(1)} ك.ب · '
                        'SHA-256 ${(e['sha256'] as String? ?? '').padRight(12).substring(0, 12)}…'),
                    trailing: const Icon(Icons.lock_open_rounded),
                    onTap: () => _openEvidence(Map<String, dynamic>.from(e)),
                  ),
              ]),
            const SheetSectionLabel('إجراءات الحماية'),
            GlassGroup([
              SheetTile(
                icon: Icons.link_off_rounded,
                color: Colors.redAccent,
                title: 'إبطال روابط الوسائط',
                subtitle: 'وسائط المبلَّغ عنه في هذه المحادثة → الحجر${q.isEmpty ? '' : ' (${q.length} منقول)'}',
                onTap: _quarantine,
              ),
              if (tgt != null)
                SheetTile(
                  icon: Icons.no_photography_rounded,
                  color: const Color(0xFFF97316),
                  title: tgt['media_restricted'] == true ? 'رفع منع الوسائط' : 'منع إرسال الوسائط',
                  subtitle: 'يمنعه من إرسال أي صورة أو فيديو أو ملف في التطبيق',
                  onTap: () async {
                    final r = await _reason(tgt['media_restricted'] == true ? 'رفع المنع' : 'منع الوسائط');
                    if (r != null) {
                      await _act(() => ShieldService.adminRestrictMedia(widget.caseId, tgt['media_restricted'] != true, r),
                          'تم');
                    }
                  },
                ),
              if (tgt != null)
                SheetTile(
                  icon: tgt['banned'] == true ? Icons.lock_open_rounded : Icons.block_rounded,
                  danger: tgt['banned'] != true,
                  color: WaslColors.teal,
                  title: tgt['banned'] == true ? 'رفع تعليق الحساب' : 'تعليق الحساب فوراً',
                  subtitle: 'يُسجَّل خروجه من كل الأجهزة ولا يستطيع الدخول',
                  onTap: () async {
                    final r = await _reason(tgt['banned'] == true ? 'رفع التعليق' : 'تعليق الحساب');
                    if (r != null) {
                      await _act(() => ShieldService.adminSuspend(widget.caseId, tgt['banned'] != true, r), 'تم');
                    }
                  },
                ),
            ]),
            const SheetSectionLabel('حالة البلاغ'),
            Wrap(spacing: 8, children: [
              for (final s in ['reviewing', 'action_taken', 'closed'])
                ActionChip(
                  label: Text(shieldStatus[s]!),
                  avatar: status == s ? const Icon(Icons.check_rounded, size: 16) : null,
                  onPressed: status == s
                      ? null
                      : () async {
                          final r = await _reason('تغيير الحالة إلى «${shieldStatus[s]}»');
                          if (r != null) await _act(() => ShieldService.adminSetStatus(widget.caseId, s, r), 'تم');
                        },
                ),
            ]),
            const SheetSectionLabel('التواصل مع المبلِّغ (باسم «دعم وصل شات»)'),
            GlassGroup([
              for (final m in _thread.take(30).toList().reversed)
                ListTile(
                  dense: true,
                  leading: Icon(m['from_support'] == true ? Icons.support_agent_rounded : Icons.person_rounded,
                      color: m['from_support'] == true ? WaslColors.teal : context.textTertiary),
                  title: Text((m['content'] as String?)?.isNotEmpty == true ? m['content'] as String : '📎 وسيط'),
                  subtitle: Text((m['created_at'] as String).substring(0, 16), style: const TextStyle(fontSize: 11)),
                ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'اكتب للمبلِّغ…',
                    filled: true,
                    fillColor: context.glass,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send_rounded),
                onPressed: () async {
                  final t = _reply.text.trim();
                  if (t.isEmpty) return;
                  _reply.clear();
                  await _act(() => ShieldService.adminMessageReporter(widget.caseId, t), 'أُرسلت');
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _EvidenceViewer extends StatelessWidget {
  const _EvidenceViewer({required this.bytes, required this.mime});
  final Uint8List bytes;
  final String mime;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (mime.startsWith('image/')) {
      body = InteractiveViewer(child: Center(child: Image.memory(bytes)));
    } else if (mime.contains('json')) {
      String text;
      try {
        final j = jsonDecode(utf8.decode(bytes)) as Map;
        final msgs = (j['messages'] as List?) ?? [];
        text = msgs
            .map((m) => '[${(m['at'] as String? ?? '').replaceAll('T', ' ').padRight(16).substring(0, 16)}] '
                '${m['from'] == 'reported' ? '⚠️ ' : ''}${m['sender']}: ${m['text'] ?? '(${m['media'] ?? '—'})'}')
            .join('\n\n');
      } catch (_) {
        text = utf8.decode(bytes, allowMalformed: true);
      }
      body = SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(text));
    } else {
      body = Center(
          child: Text('ملف ${mime.isEmpty ? '' : '($mime)'} · ${(bytes.length / 1024).toStringAsFixed(1)} ك.ب\n'
              'المعاينة متاحة للصور وسجلات الرسائل.',
              textAlign: TextAlign.center));
    }
    return Scaffold(appBar: AppBar(title: const Text('دليل')), body: body);
  }
}

class _AuditScreen extends StatefulWidget {
  const _AuditScreen({required this.caseId});
  final String? caseId;

  @override
  State<_AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<_AuditScreen> {
  List<Map<String, dynamic>>? _rows;

  static const _labels = {
    'case_created': 'إنشاء البلاغ',
    'case_viewed': 'عرض البلاغ',
    'evidence_added': 'إضافة دليل',
    'evidence_open': 'فتح دليل',
    'thread_viewed': 'عرض المراسلة',
    'message_reporter': 'رسالة للمبلِّغ',
    'media_quarantined': 'إبطال وسيط',
    'media_restricted': 'منع الوسائط',
    'media_unrestricted': 'رفع منع الوسائط',
    'target_suspended': 'تعليق حساب',
    'target_unsuspended': 'رفع تعليق',
    'retention_purged': 'حذف بانتهاء الاحتفاظ',
  };

  @override
  void initState() {
    super.initState();
    ShieldService.adminAudit(widget.caseId).then((r) {
      if (mounted) setState(() => _rows = r);
    }).catchError((_) {
      if (mounted) setState(() => _rows = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.caseId == null ? 'سجل التدقيق' : 'سجل البلاغ')),
      body: _rows == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: _rows!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _rows![i];
                final a = r['action'] as String;
                return ListTile(
                  dense: true,
                  title: Text(_labels[a] ?? (a.startsWith('status_') ? 'تغيير الحالة' : a),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '#${r['seq']} · ${(r['at'] as String).substring(0, 19)} · ${r['actor_name']}'
                      '${r['reason'] != null ? '\nالمبرر: ${r['reason']}' : ''}',
                      style: const TextStyle(fontSize: 12)),
                );
              },
            ),
    );
  }
}
