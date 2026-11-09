import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/contact_card_service.dart';
import '../theme.dart';

/// فقاعة بطاقة جهة اتصال مشفّرة (0.4.6).
///
/// - الاسم والأرقام والبريد مفكوكة التشفير قبل الوصول إلى هنا.
/// - الضغط على أي رقم أو بريد ينسخه للحافظة — بلا إذن كتابة جهات
///   الاتصال (أدنى صلاحيات ممكنة).
class ContactBubble extends StatelessWidget {
  const ContactBubble({super.key, required this.content, required this.mine});

  final ContactCard content;
  final bool mine;

  void _copy(BuildContext context, String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم نسخ $what')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    final fg = mine ? wasl.onBubbleMine : wasl.textPrimary;
    final faint = mine
        ? wasl.onBubbleMine.withValues(alpha: 0.75)
        : wasl.textSecondary;
    final avatarBg =
        mine ? Colors.white.withValues(alpha: 0.22) : wasl.violetSoft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarBg,
            ),
            child: Text(
              ContactCardService.initials(content.name),
              style: TextStyle(
                  color: fg, fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(content.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: fg, fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        if (content.phones.isNotEmpty) const SizedBox(height: 6),
        for (final p in content.phones)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _copy(context, p, 'الرقم'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.call_outlined, size: 15, color: faint),
                const SizedBox(width: 6),
                Text(p,
                    style: TextStyle(color: fg, fontSize: 13.5),
                    textDirection: TextDirection.ltr),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 12, color: faint),
              ]),
            ),
          ),
        for (final e in content.emails)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _copy(context, e, 'البريد'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mail_outline_rounded, size: 15, color: faint),
                const SizedBox(width: 6),
                Text(e,
                    style: TextStyle(color: fg, fontSize: 13.5),
                    textDirection: TextDirection.ltr),
                const SizedBox(width: 6),
                Icon(Icons.copy_rounded, size: 12, color: faint),
              ]),
            ),
          ),
        const SizedBox(height: 2),
        Text('اضغط على أي رقم لنسخه',
            style: TextStyle(color: faint, fontSize: 10.5)),
      ],
    );
  }
}
