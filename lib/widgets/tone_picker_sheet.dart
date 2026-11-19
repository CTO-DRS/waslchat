import 'package:flutter/material.dart';

import '../services/tone_service.dart';
import '../theme.dart';
import 'wasl_sheet.dart';

/// ورقة اختيار نغمة الإشعار (1.11.0). بلا [conversationId] تغيّر النغمة
/// العامة لكل المحادثات، ومعه تغيّر نغمة هذه المحادثة وحدها.
/// كل ضغطة تُسمعك النغمة فوراً وتحفظها.
Future<void> showTonePicker(BuildContext context, {String? conversationId}) async {
  String? chat = conversationId == null ? null : await ToneService.chatTone(conversationId);
  if (!context.mounted) return;
  await showWaslSheet<void>(
    context,
    title: conversationId == null ? 'نغمة الإشعارات' : 'نغمة هذه المحادثة',
    titleIcon: Icons.music_note_rounded,
    children: (ctx) => [
      StatefulBuilder(builder: (ctx, setS) {
        final current = conversationId == null ? ToneService.global.value : chat;
        Widget tile(String? id, String title, String sub) {
          final on = current == id;
          return SheetTile(
            icon: id == null
                ? Icons.settings_suggest_rounded
                : id == 'system'
                    ? Icons.phone_android_rounded
                    : Icons.graphic_eq_rounded,
            color: on ? WaslColors.teal : WaslColors.indigo,
            title: title,
            subtitle: sub,
            trailing: on
                ? const Icon(Icons.check_circle_rounded, color: WaslColors.teal)
                : const Icon(Icons.play_circle_outline_rounded),
            onTap: () async {
              ToneService.preview(id ?? ToneService.global.value);
              if (conversationId == null) {
                await ToneService.setGlobal(id!);
              } else {
                await ToneService.setChatTone(conversationId, id);
                chat = id;
              }
              setS(() {});
            },
          );
        }

        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (conversationId != null)
            tile(null, 'مثل الإعدادات العامة',
                'الحالية: ${ToneService.byId(ToneService.global.value).label}'),
          for (final t in ToneService.tones) tile(t.id, t.label, t.hint),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
            child: Text('اضغط أي نغمة لتسمعها وتختارها.',
                style: TextStyle(fontSize: 12, color: context.textFaint)),
          ),
        ]);
      }),
    ],
  );
}
