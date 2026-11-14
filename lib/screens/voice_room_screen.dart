/// شاشة غرفة الصوت الجماعية — ملء الشاشة (المرحلة 6 ب — 0.18.0).
///
/// الحالة كلها ValueNotifier من [VoiceRoomSession] فتتحدث لحظياً بلا setState
/// يدوي. الغرفة mesh: كل مشارك وصلة مباشرة مشفّرة DTLS-SRTP مع كل الآخرين —
/// لا خادم يسمع شيئاً. لا زر رجوع يهرب من الغرفة: الرجوع يعني مغادرة صريحة
/// تُبلّغ بقية الغرفة بوداع جماعي فوري.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/call_logic.dart'; // CallHistoryView.formatDuration
import '../services/voice_room_logic.dart';
import '../services/voice_room_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class VoiceRoomScreen extends StatefulWidget {
  const VoiceRoomScreen({super.key, required this.session});
  final VoiceRoomSession session;

  @override
  State<VoiceRoomScreen> createState() => _VoiceRoomScreenState();
}

class _VoiceRoomScreenState extends State<VoiceRoomScreen> {
  VoiceRoomSession get _s => widget.session;

  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _s.phase.addListener(_onPhase);
  }

  /// حالة نهائية → لحظة وداع ثم عودة تلقائية
  void _onPhase() {
    if (!RoomFlow.terminal(_s.phase.value)) return;
    if (!_finished && mounted) {
      setState(() => _finished = true);
      Timer(const Duration(milliseconds: 1100), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _s.phase.removeListener(_onPhase);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // الرجوع من التطبيق = مغادرة صريحة لا هروب صامت
        if (!_finished) _s.leave();
      },
      child: Scaffold(
        backgroundColor: WaslColors.darkBg,
        body: SafeArea(
          child: Column(children: [
            _header(),
            const Spacer(),
            _roster(),
            const Spacer(),
            if (_s.error.value != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Text(
                  _s.error.value!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade300, fontSize: 13),
                ),
              ),
            _controls(),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: ValueListenableBuilder<RoomPhase>(
        valueListenable: _s.phase,
        builder: (context, ph, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ValueListenableBuilder<int>(
                valueListenable: _s.duration,
                builder: (context, dur, _) => Text(
                  RoomFlow.live(ph)
                      ? '${CallHistoryView.formatDuration(dur)} · ${RoomRoster.countLabel(_s.participantCount)}'
                      : RoomFlow.phaseLabel(ph),
                  style: TextStyle(
                      color: RoomFlow.live(ph)
                          ? WaslColors.teal
                          : Colors.white70,
                      fontSize: 14.5),
                ),
              ),
              const SizedBox(height: 4),
              Text('غرفة صوت · تشفير مباشر بين الأجهزة · بلا خادم يسمع',
                  style: TextStyle(color: Colors.white38, fontSize: 11.5)),
              const SizedBox(height: 2),
              Text('موجة التحدث من إحصاءات جهازك — جهاز لا يوفّرها يبقى بلا موجة',
                  style: TextStyle(color: Colors.white24, fontSize: 10)),
            ]),
      ),
    );
  }

  /// شبكة المشاركين: أنت أولاً ثم الآخرون بأسمائهم وأعلام كتمهم وحالة وصلاتهم
  /// وموجات «يتحدث» الحية من إحصاءات جهازك (المرحلة 11 أ)
  Widget _roster() {
    return ValueListenableBuilder<int>(
      valueListenable: _s.rosterVersion,
      builder: (context, __, ___) => ValueListenableBuilder<Map<String, String>>(
        valueListenable: _s.peerLinks,
        builder: (context, links, __) => ValueListenableBuilder<Map<String, double>>(
          valueListenable: _s.speakingMap,
          builder: (context, speaking, ___) {
            final others = _s.others;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 14,
                runSpacing: 18,
                alignment: WrapAlignment.center,
                children: [
                  _chip(
                    name: '${_s.meName} (أنت)',
                    avatar: _s.meAvatar,
                    micOn: _s.micOn.value,
                    link: null,
                    indigo: true,
                    level: speaking['me'] ?? 0,
                  ),
                  for (final p in others)
                    _chip(
                      name: p.name,
                      avatar: p.avatar,
                      micOn: p.micOn,
                      link: links[p.id],
                      indigo: false,
                      level: speaking[p.id] ?? 0,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chip({
    required String name,
    required String? avatar,
    required bool micOn,
    required String? link,
    required bool indigo,
    required double level,
  }) {
    final connecting = link == 'connecting';
    final lost = link == 'lost';
    final talking = level > 0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: connecting
                    ? Colors.white24
                    : (lost
                        ? Colors.red.shade400.withValues(alpha: 0.6)
                        : WaslColors.teal.withValues(alpha: 0.55)),
                width: 2),
          ),
          child: UserAvatar(
            name: name,
            url: avatar,
            radius: 34,
            color: indigo ? WaslColors.indigo : WaslColors.teal,
          ),
        ),
        if (!micOn)
          PositionedDirectional(
            bottom: -2,
            end: -2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444),
                border: Border.all(color: WaslColors.darkBg, width: 2),
              ),
              child: const Icon(Icons.mic_off_rounded,
                  size: 13, color: Colors.white),
            ),
          ),
      ]),
      const SizedBox(height: 8),
      // الموجة الحية (11 أ): أربع قضبان بارتفاعات من المستوى المُنعَّم —
      // من إحصاءات جهازك حصراً؛ غياب القياس يعني بلا موجة ولا ادعاء
      SizedBox(
        height: 14,
        child: talking
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                for (final b in waveBars(level))
                  Container(
                    width: 4,
                    height: 5 + 9 * b,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: WaslColors.teal,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ])
            : const SizedBox.shrink(),
      ),
      const SizedBox(height: 2),
      Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white70, fontSize: 12.5, height: 1.2)),
      const SizedBox(height: 3),
      Text(
        connecting
            ? 'يتصل…'
            : (lost ? 'انقطع' : (talking ? 'يتحدث…' : 'متصل')),
        style: TextStyle(
            fontSize: 10.5,
            color: connecting
                ? Colors.white38
                : (lost
                    ? Colors.red.shade300
                    : (talking ? WaslColors.teal : Colors.white38))),
      ),
    ]);
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        ValueListenableBuilder<bool>(
          valueListenable: _s.micOn,
          builder: (context, on, __) => _roundButton(
            icon: on ? Icons.mic_rounded : Icons.mic_off_rounded,
            color: on ? Colors.white24 : const Color(0xFFEF4444),
            tooltip: on ? 'كتم الميكروفون' : 'إلغاء الكتم',
            onTap: () => _s.toggleMic(),
          ),
        ),
        const SizedBox(width: 14),
        ValueListenableBuilder<bool>(
          valueListenable: _s.speakerOn,
          builder: (context, on, __) => _roundButton(
            icon: on ? Icons.volume_up_rounded : Icons.hearing_disabled_rounded,
            color: on ? WaslColors.teal : Colors.white24,
            tooltip: on ? 'إلى سماعة الجهاز' : 'إلى مكبر الصوت',
            onTap: () => _s.toggleSpeaker(),
          ),
        ),
        const SizedBox(width: 26),
        _bigButton(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFEF4444),
          tooltip: 'مغادرة الغرفة',
          onTap: () => _s.leave(),
        ),
      ]),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _bigButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: color.withValues(alpha: 0.4),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(child: Icon(icon, color: Colors.white, size: 30)),
            ),
          ),
        ),
      ),
    );
  }
}

/// حوار قبل الانضمام: يوضح الحدود صادقاً ثم يفتح الغرفة — يُستدعى من شريط
/// المحادثات الخاصة.
Future<void> showVoiceRoomIntro(BuildContext context,
    {required String conversationId, required String title}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Row(children: [
        Icon(roomIcon(), size: 22, color: WaslColors.teal),
        const SizedBox(width: 8),
        const Expanded(child: Text('غرفة صوت جماعية')),
      ]),
      content: Text(roomDisclaimer(), style: const TextStyle(height: 1.7)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('انضمام')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final s = await VoiceRoomService.join(
      conversationId: conversationId, title: title);
  if (!context.mounted) return;
  if (s == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('لا يمكن الانضمام الآن — أنت في غرفة أخرى بالفعل')));
    return;
  }
  await Navigator.push(
      context, MaterialPageRoute(builder: (_) => VoiceRoomScreen(session: s)));
}
