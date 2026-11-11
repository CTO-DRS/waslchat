import 'package:flutter/material.dart';

import '../services/block_service.dart';
import '../theme.dart';

/// حوار الإبلاغ عن مستخدم أو رسالة، مع خيار الحظر معاً.
/// يعيد true إذا حظر المستخدم الطرف الآخر (لكي تُحدّث الشاشة).
Future<bool> showReportDialog(
  BuildContext context, {
  String? targetUser,
  String? messageId,
  String? targetName,
}) async {
  final reason = TextEditingController();
  var blockToo = targetUser != null;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('الإبلاغ'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(targetName == null
              ? 'صف المشكلة باختصار (سب، مضايقة، محتوى غير لائق…).'
              : 'ستُرسل شكوى عن «$targetName» إلى إدارة التطبيق. صف المشكلة باختصار.'),
          const SizedBox(height: 12),
          TextField(
            controller: reason,
            maxLines: 3,
            maxLength: 500,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: 'سبب الإبلاغ', hintText: 'اكتب السبب هنا…'),
          ),
          if (targetUser != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: blockToo,
              onChanged: (v) => setD(() => blockToo = v ?? false),
              title: const Text('حظر المستخدم أيضاً'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إرسال'),
          ),
        ],
      ),
    ),
  );

  final submitted = ok == true;
  final reasonText = reason.text.trim();
  reason.dispose();

  if (!submitted) return false;
  if (reasonText.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('اكتب سبب الإبلاغ أولاً')));
    }
    return false;
  }

  try {
    await BlockService.report(
      targetUser: targetUser,
      messageId: messageId,
      reason: reasonText,
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال الإبلاغ — حاول مجدداً')));
    }
    return false;
  }

  var blocked = false;
  if (blockToo && targetUser != null) {
    try {
      await BlockService.block(targetUser);
      blocked = true;
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('حُفظ الإبلاغ وتعذّر الحظر')));
      }
    }
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: WaslColors.teal,
        content: Text(blocked ? 'أُرسل الإبلاغ وحُظر المستخدم' : 'أُرسل الإبلاغ، شكراً لك')));
  }
  return blocked;
}
