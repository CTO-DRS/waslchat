import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../services/backup_export_service.dart';
import '../services/e2e_service.dart';
import '../services/export_service.dart';
import '../services/webio/web_files.dart';
import '../theme.dart';

/// النسخة الاحتياطية الكاملة المشفرة (المرحلة 13 أ — 0.26.0)
///
/// عملتان على جهازك حصراً:
/// 1. **إنشاء نسخة**: جلب آخر 500 رسالة من كل محادثة، فك محلي، تشفير مجدد
///    بكلمة سر تختارها (PBKDF2 + AES-256-GCM) في ملف .waslbackup تشاركه أنت.
/// 2. **فتح نسخة**: اختيار ملف من جهازك وإدخال كلمة سره وقراءة محتواه
///    قراءةً فقط — ولا إعادة رفع لأي شيء إلى الخادم أبداً.
///
/// الصدق الموثق (معروض في الشاشة نفسها): النصوص حصراً — الوسائط سطر تسمية
/// لا ملف، والرسائل المختفية والمحذوفة لا تدخل، وكلمة السر لا تُستعاد لأحد
/// إن نسيتها، والخادم لا يرى الملف ولا كلمة السر ولا أي حرف.
class BackupExportScreen extends StatefulWidget {
  const BackupExportScreen({super.key});

  @override
  State<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends State<BackupExportScreen> {
  bool _busy = false;
  String _progress = '';

  // نتيجة فتح نسخة موجودة (قراءة فقط)
  final List<BackupConversation> _opened = [];
  String? _openedInfo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('النسخة الاحتياطية الكاملة',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          const _DisclosureCard(),
          const SizedBox(height: 16),
          if (_busy) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Center(
                child: Text(_progress,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14))),
            const SizedBox(height: 16),
          ],
          if (!_busy) ...[
            _ActionCard(
              icon: Icons.archive_outlined,
              color: WaslColors.teal,
              title: 'إنشاء نسخة جديدة',
              subtitle:
                  'يجلب آخر ${BackupExportService.messagesPerConversation} رسالة من كل محادثة '
                  'ويشفّرها بكلمة سر تختارها في ملف واحد تحفظه أنت',
              onTap: _createBackup,
            ),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.folder_open_outlined,
              color: WaslColors.violet,
              title: 'فتح نسخة موجودة',
              subtitle: 'اختر ملف نسخة من جهازك وأدخل كلمة سره لقراءته قراءةً فقط',
              onTap: _openBackup,
            ),
            if (_openedInfo != null) ...[
              const SizedBox(height: 16),
              Card(
                color: context.surfaceAlt,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_openedInfo!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
            ],
            for (final c in _opened) ...[
              const SizedBox(height: 10),
              _ConversationCard(conversation: c),
            ],
          ],
        ],
      ),
    );
  }

  // ---------- إنشاء النسخة ----------

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _progress = 'جلب المحادثات…';
    });
    try {
      final me = supabase.auth.currentUser!.id;
      final chats = await supabase.rpc('my_chats');
      final chatList = List<Map<String, dynamic>>.from(chats as List);
      // أسماء المرسلين لكل الرسائل (نمط البحث الموحد)
      final names = <String, String>{};
      try {
        final profs = await supabase
            .from('profiles')
            .select('id, display_name, username')
            .limit(500);
        for (final p in List<Map<String, dynamic>>.from(profs)) {
          names[p['id'] as String] =
              ((p['display_name'] as String?) ??
                      (p['username'] as String?) ??
                      '')
                  .trim();
        }
      } catch (_) {}

      final conversations = <BackupConversation>[];
      for (final c in chatList) {
        if (!mounted) return;
        final cid = c['conversation_id'] as String?;
        if (cid == null || cid.isEmpty) continue;
        final isGroup = c['is_group'] == true;
        final rawTitle = (c['title'] ?? '') as String;
        var title = rawTitle;
        if (isGroup && E2eService.isEncrypted(rawTitle)) {
          final t = await E2eService.groupTitle(cid, rawTitle);
          title = t.isEmpty ? 'مجموعة' : t;
        }
        if (title.trim().isEmpty) title = 'بدون عنوان';
        setState(() => _progress = 'فك رسائل «$title»…');

        final msgs = await supabase
            .from('messages')
            .select(
                'id, sender_id, content, type, created_at, deleted_at, view_once, duration_ms')
            .eq('conversation_id', cid)
            .order('created_at', ascending: false)
            .limit(BackupExportService.messagesPerConversation);
        final messages = <BackupMessage>[];
        for (final m in List<Map<String, dynamic>>.from(msgs)) {
          if ((m['deleted_at'] as String?) != null) continue; // المحذوفة لا تدخل
          final type = m['type'] as String? ?? 'text';
          final senderId = m['sender_id'] as String? ?? '';
          final sender = senderId == me
              ? 'أنت'
              : (names[senderId] ?? 'طرف');
          if (type == 'text') {
            final content = m['content'] as String? ?? '';
            if (content.trim().isEmpty) continue;
            var plain = content;
            if (E2eService.isEncrypted(content)) {
              final otherId = c['other_id'] as String?;
              String? opened;
              try {
                opened = isGroup
                    ? await E2eService.decryptGroupText(cid, content)
                    : (otherId == null
                        ? null
                        : await E2eService.decryptDmText(cid, otherId, content));
              } catch (_) {
                opened = null;
              }
              plain = opened ?? '🔒';
            }
            if (plain == '🔒' || plain.trim().isEmpty) continue; // ما لم يُفك لا يُكتب
            messages.add(BackupMessage(
              senderName: sender,
              text: plain,
              createdAtIso: m['created_at'] as String? ?? '',
              mine: senderId == me,
            ));
          } else if (type == 'image' && m['view_once'] == true) {
            continue; // عرض-مرة-واحدة لا يُصدَّر أبداً
          } else {
            // الوسائط سطر تسمية حصراً — الملف نفسه لا يُصدَّر (حد صادق)
            messages.add(BackupMessage(
              senderName: sender,
              text: ExportService.mediaLabel(m),
              createdAtIso: m['created_at'] as String? ?? '',
              mine: senderId == me,
              media: true,
            ));
          }
        }
        conversations.add(BackupConversation(
          id: cid,
          title: title,
          isGroup: isGroup,
          messages: messages.reversed.toList(), // الأقدم أولاً للقراءة
        ));
      }

      if (conversations.isEmpty) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لا توجد محادثات لإنشاء نسخة عنها')));
        }
        return;
      }

      final stats = BackupExportService.archiveStats(
          BackupExportService.buildArchive(
              appVersion: '1.5.0', conversations: conversations));
      if (!mounted) return;
      setState(() {
        _progress = '';
        _busy = false;
      });
      final pass = await _askNewPassphrase(stats);
      if (pass == null || !mounted) return;
      setState(() => _busy = true);
      setState(() => _progress = 'تشفير النسخة بكلمة سرها…');
      final archive = BackupExportService.buildArchive(
        appVersion: '1.5.0',
        conversations: conversations,
        ownerName: names[me] ?? '',
      );
      final bytes = await BackupExportService.encryptArchive(archive, pass);
      final name = BackupExportService.fileName(DateTime.now());
      if (kIsWeb) {
        webDownload(bytes, name, 'application/octet-stream');
      } else {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(f.path)],
          subject: 'نسخة احتياطية كاملة مشفرة — وصل شات',
        ));
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _openedInfo =
            'أُنشئت النسخة «$name» (${stats.$1} محادثة و${stats.$2} رسالة) — '
            'احفظ الملف وكلمة سره في مكان آمن: بلا كلمة السر لا يستفتح الملف أحد.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذّر إنشاء النسخة — تحقق من الاتصال')));
      }
    }
  }

  // ---------- فتح نسخة ----------

  Future<void> _openBackup() async {
    try {
      final r = await FilePicker.platform.pickFiles(withData: true);
      final file = r?.files.single;
      final rawBytes = file?.bytes;
      if (file == null || rawBytes == null) return;
      if (!mounted) return;
      final pass = await _askOpenPassphrase();
      if (pass == null || !mounted) return;
      setState(() => _busy = true);
      final conversations =
          await BackupExportService.conversationsOf(rawBytes, pass);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _opened.clear();
        if (conversations == null) {
          _openedInfo =
              'فشل فك الملف — كلمة السر خاطئة أو الملف معطوب أو من صيغة أخرى. '
              'بلا كلمة السر الصحيحة لا يُفتح الملف لدى أحد.';
        } else {
          _opened.addAll(conversations);
          final msgs =
              conversations.fold<int>(0, (s, c) => s + c.messages.length);
          _openedInfo =
              'فُتح الملف «${file.name}»: ${conversations.length} محادثة '
              'و$msgs رسالة — قراءة فقط، لا شيء يُرفع للخادم.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر فتح الملف')));
      }
    }
  }

  // ---------- نوافذ كلمة السر ----------

  Future<String?> _askNewPassphrase((int, int) stats) {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: ctx.surfaceAlt,
          title: const Text('كلمة سر النسخة',
              style: TextStyle(fontWeight: FontWeight.w800)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'ستُشفَّر ${stats.$2} رسالة في ${stats.$1} محادثة بكلمة سر '
                  'لا يعرفها أحد غيرك — والخادم لا يرى كلمة السر ولا الملف.',
                  style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(
                controller: c1,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(
                    labelText: 'كلمة السر (8 أحرف على الأقل)'),
                onChanged: (_) => setD(() => err = null),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: c2,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'تأكيد كلمة السر'),
                onChanged: (_) => setD(() => err = null),
              ),
              if (err != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(err!,
                      style: const TextStyle(color: Colors.red, fontSize: 13)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('إلغاء')),
            FilledButton(
                onPressed: () {
                  final p = c1.text;
                  if (!BackupExportService.passphraseOk(p)) {
                    setD(() =>
                        err = 'كلمة السر أقصر من ${BackupExportService.minPassphraseLength} أحرف');
                    return;
                  }
                  if (p != c2.text) {
                    setD(() => err = 'التأكيد لا يطابق كلمة السر');
                    return;
                  }
                  Navigator.pop(ctx, p);
                },
                child: const Text('تشفير وحفظ')),
          ],
        ),
      ),
    );
  }

  Future<String?> _askOpenPassphrase() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceAlt,
        title: const Text('كلمة سر الملف',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('أدخل كلمة السر التي شُفّر بها ملف النسخة',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'كلمة السر'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text),
              child: const Text('فتح')),
        ],
      ),
    );
  }
}

// ---------- مكونات العرض ----------

class _DisclosureCard extends StatelessWidget {
  const _DisclosureCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.verified_user_outlined, size: 20, color: WaslColors.teal),
              SizedBox(width: 8),
              Text('كل شيء على جهازك حصراً',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
            SizedBox(height: 8),
            Text(
              'النصوص تُفك محلياً وتُشفَّر بكلمة سر تختارها، والخادم لا يرى '
              'كلمة السر ولا الملف ولا أي حرف. والوسائط سطر تسمية لا ملف، '
              'والعرض-مرة-واحدة والمحذوفة لا تدخلان إطلاقاً، والفك بعد ذلك '
              'قراءة فقط — لا إعادة رفع لأي رسالة إلى الخادم. ونسيتَ كلمة '
              'السر؟ لا استعادة ممكنة لأحد — هذا هو التصميم.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left),
          ]),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({required this.conversation});

  final BackupConversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    return Card(
      color: context.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        title: Row(children: [
          Icon(
              c.isGroup ? Icons.groups_3_outlined : Icons.person_outline,
              size: 20,
              color: WaslColors.teal),
          const SizedBox(width: 8),
          Expanded(child: Text(c.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis)),
          Text('${c.messages.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        subtitle: Text(
            BackupExportService.conversationSummaryLine(c),
            style: const TextStyle(fontSize: 11)),
        children: [
          for (final m in c.messages)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Align(
                alignment: m.mine
                    ? AlignmentDirectional.centerStart
                    : AlignmentDirectional.centerEnd,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: m.mine
                        ? WaslColors.teal.withValues(alpha: 0.12)
                        : context.surfaceAlt.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m.senderName} · ${_shortTime(m.createdAtIso)}',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600)),
                      const SizedBox(height: 2),
                      Text(m.text,
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _shortTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.year)}-${two(t.month)}-${two(t.day)}';
  }
}
