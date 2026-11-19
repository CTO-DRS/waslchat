import 'package:flutter/material.dart';

import '../screens/voice_studio_screen.dart';
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
                : switch (ToneService.byId(id).group) {
                    ToneGroup.system => Icons.phone_android_rounded,
                    ToneGroup.melody => Icons.music_note_rounded,
                    ToneGroup.custom => Icons.auto_awesome_rounded,
                    ToneGroup.voice => Icons.record_voice_over_rounded,
                  },
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
          SheetTile(
            icon: Icons.graphic_eq_rounded,
            color: WaslColors.violet,
            title: 'استوديو الصوت',
            subtitle: 'اصنع نغمتك من صوت ولحن أو بصوتك أنت',
            trailing: const Icon(Icons.chevron_left_rounded),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VoiceStudioScreen()));
            },
          ),
          for (final sec in ToneService.sectionOrder)
            if (ToneService.tones.any((t) => ToneService.sectionOf(t) == sec)) ...[
              SheetSectionLabel(sec),
              for (final t in ToneService.tones.where((t) => ToneService.sectionOf(t) == sec))
                tile(t.id, t.label, t.hint),
            ],
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
