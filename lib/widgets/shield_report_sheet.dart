import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/shield_service.dart';
import '../theme.dart';
import 'wasl_sheet.dart';

/// عنصر يمكن إرفاقه كدليل (رسالة من المحادثة كما يراها المبلِّغ على جهازه)
class ShieldEvidenceItem {
  ShieldEvidenceItem({
    required this.id,
    required this.fromTarget,
    required this.senderName,
    required this.at,
    this.text,
    this.mediaType,
    this.loader,
  });
  final String id;
  final bool fromTarget;
  final String senderName;
  final String at;
  final String? text;
  final String? mediaType; // image | video | file | voice
  final Future<Uint8List?> Function()? loader;
}

/// ورقة «بلاغ عاجل» — Wasl Shield
Future<void> showShieldReportSheet(
  BuildContext context, {
  required String conversationId,
  required String? targetUserId,
  required String targetName,
  required List<ShieldEvidenceItem> items,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ShieldReportScreen(
      conversationId: conversationId,
      targetUserId: targetUserId,
      targetName: targetName,
      items: items,
    ),
  ));
}

class _ShieldReportScreen extends StatefulWidget {
  const _ShieldReportScreen({
    required this.conversationId,
    required this.targetUserId,
    required this.targetName,
    required this.items,
  });
  final String conversationId;
  final String? targetUserId;
  final String targetName;
  final List<ShieldEvidenceItem> items;

  @override
  State<_ShieldReportScreen> createState() => _ShieldReportScreenState();
}

class _ShieldReportScreenState extends State<_ShieldReportScreen> {
  String _category = 'blackmail';
  bool _urgent = true;
  bool _block = true;
  final _desc = TextEditingController();
  late final Set<String> _picked = {
    // افتراضياً: آخر 30 رسالة من الطرف الآخر
    ...widget.items.where((e) => e.fromTarget).take(30).map((e) => e.id),
  };
  bool _sending = false;
  String _progress = '';

  @override
  void dispose() {
    _desc.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_desc.text.trim().length < 3) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اكتب وصفاً مختصراً لما حدث')));
      return;
    }
    setState(() {
      _sending = true;
      _progress = 'جارٍ تجهيز الأدلة…';
    });
    try {
      final chosen = widget.items.where((e) => _picked.contains(e.id)).toList();
      final transcript = [
        for (final e in chosen)
          {
            'id': e.id,
            'from': e.fromTarget ? 'reported' : 'reporter',
            'sender': e.senderName,
            'at': e.at,
            if (e.text != null) 'text': e.text,
            if (e.mediaType != null) 'media': e.mediaType,
          }
      ];
      final media = <({Uint8List bytes, String mime, String ext, String? sourceId})>[];
      for (final e in chosen.where((x) => x.loader != null && x.mediaType != null).take(20)) {
        final b = await e.loader!();
        if (b == null) continue;
        final (mime, ext) = switch (e.mediaType) {
          'image' => ('image/jpeg', 'jpg'),
          'video' => ('video/mp4', 'mp4'),
          'voice' => ('audio/mp4', 'm4a'),
          _ => ('application/octet-stream', 'bin'),
        };
        media.add((bytes: b, mime: mime, ext: ext, sourceId: e.id));
      }
      final ref = await ShieldService.report(
        category: _category,
        description: _desc.text.trim(),
        urgent: _urgent,
        targetUserId: widget.targetUserId,
        conversationId: widget.conversationId,
        block: _block && widget.targetUserId != null,
        messagesJson: transcript.isEmpty
            ? null
            : const JsonEncoder.withIndent(' ').convert({
                'conversation': widget.conversationId,
                'exported_at': DateTime.now().toUtc().toIso8601String(),
                'messages': transcript,
              }),
        media: media,
        onProgress: (d, t) => mounted ? setState(() => _progress = 'رفع الأدلة $d من $t') : null,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.verified_user_rounded, color: WaslColors.teal, size: 40),
          title: const Text('وصل بلاغك'),
          content: Text('رقم البلاغ $ref.\n'
              'يراجعه المدير العام مباشرة، والطرف الآخر لا يعلم بالبلاغ ولا بهويتك. '
              'سنتواصل معك عبر «دعم وصل شات».\n\n'
              'إن كنت في خطر مباشر فاتصل بالجهات الأمنية فوراً.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً'))],
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final s = e.toString();
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(s.contains('RATE_LIMIT')
              ? 'وصلت للحد اليومي من البلاغات. تواصل مع «دعم وصل شات» مباشرة.'
              : 'تعذّر إرسال البلاغ، تحقق من الاتصال وحاول مجدداً')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_rounded, color: Colors.redAccent),
          SizedBox(width: 8),
          Text('بلاغ عاجل', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: AbsorbPointer(
        absorbing: _sending,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'يصل بلاغك مباشرة للمدير العام لوصل شات. لن يعرف الطرف الآخر بالبلاغ ولا بهويتك.\n'
                'لا تحذف المحادثة ولا تدفع أي مبلغ — الأدلة تساعدنا على حمايتك.',
                style: TextStyle(height: 1.5),
              ),
            ),
            const SheetSectionLabel('ما الذي يحدث؟'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in shieldCategories.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _category == e.key,
                  onSelected: (_) => setState(() => _category = e.key),
                ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _desc,
              maxLines: 4,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: 'صف ما حدث باختصار (مثال: يهددني بنشر صوري إن لم أدفع)',
                filled: true,
                fillColor: context.glass,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            GlassGroup([
              SwitchListTile(
                value: _urgent,
                onChanged: (v) => setState(() => _urgent = v),
                title: const Text('عاجل', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('يرفع أولوية البلاغ عند المدير'),
              ),
              if (widget.targetUserId != null)
                SwitchListTile(
                  value: _block,
                  onChanged: (v) => setState(() => _block = v),
                  title: Text('حظر ${widget.targetName}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('حظر عادي صامت — لا يكشف وجود بلاغ'),
                ),
            ]),
            SheetSectionLabel('الأدلة (${_picked.length} محددة)'),
            if (widget.items.isEmpty)
              Text('لا توجد رسائل محمّلة في هذه المحادثة', style: TextStyle(color: context.textFaint))
            else
              GlassGroup([
                for (final e in widget.items.take(150))
                  CheckboxListTile(
                    dense: true,
                    value: _picked.contains(e.id),
                    onChanged: (v) => setState(() => v == true ? _picked.add(e.id) : _picked.remove(e.id)),
                    title: Text(
                      e.text?.isNotEmpty == true
                          ? e.text!
                          : switch (e.mediaType) {
                              'image' => '📷 صورة',
                              'video' => '🎬 فيديو',
                              'voice' => '🎤 رسالة صوتية',
                              'file' => '📎 ملف',
                              _ => '—',
                            },
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('${e.senderName} · ${e.at}',
                        style: TextStyle(fontSize: 11.5, color: e.fromTarget ? Colors.redAccent : context.textFaint)),
                  ),
              ]),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(_sending ? _progress : 'إرسال البلاغ للمدير',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}
