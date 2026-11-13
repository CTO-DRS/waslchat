/// شاشة المكالمة الملء — صوتية أو مرئية (المرحلة 6 — 0.17.0).
///
/// الحالة كلها ValueNotifier من [CallSession] فتتحدث لحظياً بلا setState
/// يدوي. الصوت والصورة يعرضان من تدفقات WebRTC مباشرة؛ في المكالمة الصوتية
/// رأس دائري بهوية الطرف الآخر، وفي المرئية تدفقه ملء الشاشة وتدفقك بطاقة
/// صغيرة. لا زر رجوع يهرب من المكالمة: الرجوع يعني الإنهاء الصريح.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_logic.dart';
import '../services/call_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.session});
  final CallSession session;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallSession get _s => widget.session;

  final _remoteRenderer = RTCVideoRenderer();
  final _localRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _s.status.addListener(_onStatus);
    _s.remoteStream.addListener(_attachRemote);
    _s.localStreamView.addListener(_attachLocal);
  }

  Future<void> _initRenderers() async {
    try {
      await _remoteRenderer.initialize();
      await _localRenderer.initialize();
      if (mounted) setState(() => _renderersReady = true);
    } catch (_) {}
    _attachRemote();
    _attachLocal();
  }

  void _attachRemote() {
    if (_renderersReady) _remoteRenderer.srcObject = _s.remoteStream.value;
  }

  void _attachLocal() {
    if (_renderersReady) _localRenderer.srcObject = _s.localStreamView.value;
  }

  /// حالة نهائية → لحظة وداع ثم عودة تلقائية
  void _onStatus() {
    if (!CallFlow.terminal(_s.status.value)) return;
    if (!_finished && mounted) {
      setState(() => _finished = true);
      Timer(const Duration(milliseconds: 1100), () {
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _s.status.removeListener(_onStatus);
    _s.remoteStream.removeListener(_attachRemote);
    _s.localStreamView.removeListener(_attachLocal);
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? WaslColors.darkBg : const Color(0xFF101524);
    return PopScope(
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // الرجوع من التطبيق = إنهاء صريح لا هروب صامت
        if (!_finished) widget.session.hangUp();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: ValueListenableBuilder<CallStatus>(
            valueListenable: _s.status,
            builder: (context, st, _) {
              final live = CallFlow.live(st);
              return Stack(children: [
                // خلفية المرئية: تدفق الطرف الآخر ملء الشاشة
                if (_s.isVideo) _remoteVideoLayer(live),
                Column(children: [
                  _header(st),
                  const Spacer(),
                  if (!_s.isVideo) _voiceFace(st),
                  if (_s.isVideo) const Spacer(),
                  if (_s.error.value != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      child: Text(
                        _s.error.value!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade300, fontSize: 13),
                      ),
                    ),
                  _controls(st),
                ]),
                // بطاقتك الصغيرة فوق تدفق الطرف الآخر
                if (_s.isVideo && live) _localCard(),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _remoteVideoLayer(bool live) {
    return Positioned.fill(
      child: _renderersReady
          ? RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : const SizedBox.expand(),
    );
  }

  /// بطاقة تدفقك المحلي (يمكن تكبيرها بالضغط لتفقّد الكاميرا)
  Widget _localCard() {
    return PositionedDirectional(
      bottom: 150,
      start: 16,
      child: GestureDetector(
        onTap: () => setState(() => _bigLocal = !_bigLocal),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: _bigLocal ? 140 : 108,
          height: _bigLocal ? 200 : 152,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_bigLocal ? 18 : 14),
            border: Border.all(color: Colors.white24, width: 1),
            color: Colors.black45,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_bigLocal ? 17 : 13),
            child: _renderersReady && _s.localStreamView.value != null
                ? RTCVideoView(_localRenderer, mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : const Center(
                    child: Icon(Icons.videocam_off_outlined, color: Colors.white38)),
          ),
        ),
      ),
    );
  }

  bool _bigLocal = false;

  Widget _header(CallStatus st) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_s.peerName,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ValueListenableBuilder<int>(
          valueListenable: _s.duration,
          builder: (context, dur, _) => Text(
            CallFlow.live(st)
                ? CallHistoryView.formatDuration(dur)
                : CallFlow.phaseLabel(st, _s.role),
            style: TextStyle(
                color: CallFlow.live(st) ? WaslColors.teal : Colors.white70,
                fontSize: 14.5),
          ),
        ),
        const SizedBox(height: 4),
        Text('مكالمة ${callKindLabel(_s.kind)} · تشفير مباشر بين الجهازين',
            style: TextStyle(color: Colors.white38, fontSize: 11.5)),
      ]),
    );
  }

  /// وجه المكالمة الصوتية: هالة نابضة حول صورة الطرف الآخر
  Widget _voiceFace(CallStatus st) {
    return Column(children: [
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.85, end: 1),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOut,
        builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: st == CallStatus.ringing
                    ? WaslColors.teal.withValues(alpha: 0.55)
                    : Colors.white24,
                width: 2),
          ),
          child: UserAvatar(
            name: _s.peerName,
            url: _s.peerAvatar,
            radius: 56,
            color: WaslColors.indigo,
          ),
        ),
      ),
      if (st == CallStatus.ringing && _s.role == CallRole.caller) ...[
        const SizedBox(height: 18),
        Text('تُرن لدى الطرف الآخر…',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      ],
      const SizedBox(height: 40),
    ]);
  }

  Widget _controls(CallStatus st) {
    final incomingRing = st == CallStatus.ringing && _s.role == CallRole.callee;
    if (incomingRing) {
      // مكالمة واردة: قبول أخضر ورفض أحمر فقط
      return Padding(
        padding: const EdgeInsets.only(bottom: 34),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _bigButton(
            icon: Icons.call_end_rounded,
            color: const Color(0xFFEF4444),
            tooltip: 'رفض',
            onTap: () => _s.decline(),
          ),
          const SizedBox(width: 56),
          _bigButton(
            icon: Icons.call_rounded,
            color: const Color(0xFF22C55E),
            tooltip: 'قبول',
            onTap: () {
              HapticFeedback.mediumImpact();
              _s.accept();
            },
          ),
        ]),
      );
    }
    if (CallFlow.terminal(st)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 34),
        child: Center(
          child: Text('عودة تلقائية…',
              style: TextStyle(color: Colors.white38, fontSize: 12.5)),
        ),
      );
    }
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
        const SizedBox(width: 14),
        if (_s.isVideo)
          ValueListenableBuilder<bool>(
            valueListenable: _s.cameraOn,
            builder: (context, on, __) => _roundButton(
              icon: on ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: on ? Colors.white24 : const Color(0xFFEF4444),
              tooltip: on ? 'إيقاف الكاميرا' : 'تشغيل الكاميرا',
              onTap: () => _s.toggleCamera(),
            ),
          ),
        if (_s.isVideo) const SizedBox(width: 14),
        if (_s.isVideo)
          _roundButton(
            icon: Icons.flip_camera_android_rounded,
            color: Colors.white24,
            tooltip: 'قلب الكاميرا',
            onTap: () => _s.flipCamera(),
          ),
        if (_s.isVideo) const SizedBox(width: 14),
        _bigButton(
          icon: Icons.call_end_rounded,
          color: const Color(0xFFEF4444),
          tooltip: 'إنهاء المكالمة',
          onTap: () => _s.hangUp(),
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
