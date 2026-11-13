import 'package:flutter/material.dart';

import '../config.dart';
import '../services/feedback_service.dart';
import '../services/platform_name.dart';
import '../theme.dart';

/// شاشة «إرسال ملاحظات» (المرحلة 7 — برنامج المجرّبين، 0.19.0).
///
/// صدق كامل قبل أي إرسال: الملاحظة تصل نصاً صريحاً لفريق وصل — لا تشفير هنا
/// ولا مفاجآت، ومَن يراها صاحبها وإدارة التطبيق حصراً (RLS ترحيل 029).
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _body = TextEditingController();
  String _category = 'bug';
  bool _sending = false;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pre = FeedbackService.validationError(_body.text);
    if (pre != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(pre)));
      return;
    }
    setState(() => _sending = true);
    try {
      await FeedbackService.send(
        category: _category,
        body: _body.text,
        appVersion: '${AppConfig.appVersion}+${AppConfig.appBuild}',
        platform: devicePlatformLabel(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('وصلت ملاحظتك — شكراً لك، هذا ما يصنع وصل')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final hint = FeedbackService.sendErrorHint(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(hint ?? 'تعذّر الإرسال الآن — حاول لاحقاً')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              const Text('إرسال ملاحظات', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            color: context.surfaceAlt,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded,
                    color: WaslColors.teal, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ملاحظتك تصل نصاً صريحاً (غير مشفّرة) إلى فريق وصل مع إصدار التطبيق واسم المنصة، وتقرأها إدارة التطبيق حصراً — لا تكتب فيها محتوى محادثاتك أو بيانات حساسة. المحادثات ورسائلها تبقى مشفّرة كما هي.',
                    style: TextStyle(fontSize: 13.5, height: 1.5),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          const Text('التصنيف',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in FeedbackService.categories)
                ChoiceChip(
                  label: Text(c.$2),
                  avatar: Icon(c.$3, size: 18, color: c.$4),
                  selected: _category == c.$1,
                  onSelected: (_) => setState(() => _category = c.$1),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _body,
            maxLines: 7,
            maxLength: FeedbackService.maxLen,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'اكتب ملاحظتك هنا… ماذا حدث؟ ماذا تتمنى أن يضيف وصل؟',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'الحد الأقصى ${FeedbackService.maxLen} حرفاً · يمكن إرسال ${FeedbackService.limitPerHour} ملاحظات كل ساعة',
            style: TextStyle(fontSize: 12, color: context.textFaint),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _sending ? null : _submit,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(_sending ? 'جارٍ الإرسال…' : 'إرسال الملاحظة'),
          ),
        ],
      ),
    );
  }
}
