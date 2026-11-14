/// خدمة غرف الصوت الجماعية (المرحلة 6 ب — 0.18.0): mesh WebRTC فوق إشارات
/// Realtime — بلا أي خادم إضافي ولا ترحيل قاعدة بيانات إطلاقاً.
///
/// التصميم الصادق:
/// - الصوت اتصال مباشر P2P مشفّر DTLS-SRTP بين كل جهازَين في الغرفة — خادم
///   وصل لا يسمع شيئاً ولا يمكنه ذلك.
/// - الإشارات (SDP/ICE) وقائمة الحضور تمر عبر قناة لحظية لا تُخزَّن في أي
///   قاعدة بيانات وتبدد بالبث، وقد تكشف عنوان شبكتك لبقية المشاركين — مطلوب
///   اتصالياً لأي WebRTC وموثق في TRANSPARENCY.md.
/// - الغرفة حية فقط ما دام أعضاؤها متصلين: لا سجل مكالمات ولا صف خادم —
///   حاجز السعة (8 مشاركين) تعاوني محلي لا إجبار قهرياً عليه بلا خادم.
/// - بوابة العضوية من جدول المحادثة المحمي بـRLS: presence وإشارة من خارج
///   الأعضاء تُسقط قبل أي معالجة.
/// - بلا TURN: نفس حدود المكالمات الفردية (STUN فقط) — الشبكات الصارمة
///   قد تفشل وتظهر «تعذر الاتصال» حتى يضيف المالك TURN وفق RUNBOOK.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'call_logic.dart'; // CallSignal — نفس رسائل الإشارة القياسية
import 'voice_room_logic.dart';

/// جلسة غرفة صوت حية — حالة واحدة تلاحظها الواجهة وتدفعها الخدمة.
class VoiceRoomSession {
  VoiceRoomSession({
    required this.conversationId,
    required this.title,
    required this.meId,
    required this.meName,
    this.meAvatar,
  });

  final String conversationId;
  final String title;
  final String meId;
  final String meName;
  final String? meAvatar;

  final phase = ValueNotifier<RoomPhase>(RoomPhase.joining);
  final duration = ValueNotifier<int>(0);
  final micOn = ValueNotifier<bool>(true);
  final speakerOn = ValueNotifier<bool>(true); // الغرفة اجتماع — مكبر افتراضياً
  final error = ValueNotifier<String?>(null);

  /// دفعة إعادة بناء قائمة المشاركين (يتغير مع كل presence sync)
  final rosterVersion = ValueNotifier<int>(0);

  /// حالة وصلة كل مشارك: 'connecting' / 'connected' / 'lost'
  final peerLinks = ValueNotifier<Map<String, String>>({});

  /// مستوى التحدث لكل مشارك 0..1 (مفتاحك 'me') من إحصاءات الاتصال على
  /// جهازك حصراً — صفر للمشاركين الصامتين وغياب القياس (المرحلة 11 أ)
  final speakingMap = ValueNotifier<Map<String, double>>({});

  RoomRoster? _roster;
  RealtimeChannel? _ch;
  MediaStream? _local;
  final Map<String, RTCPeerConnection> _pcs = {};
  final Map<String, List<CallSignal>> _pendingIce = {};
  final Map<String, Timer> _peerTimers = {};
  final Map<String, SpeakingWave> _waves = {};
  Timer? _ticker;
  Timer? _voiceTimer;
  bool _closing = false;

  int get participantCount => _roster?.count ?? 1;
  List<VoicePeer> get others => _roster?.others ?? const [];
  VoicePeer? peerOf(String id) => _roster?.peerOf(id);

  // ================= الانضمام =================

  /// الانضمام: بوابة العضوية ← الميكروفون ← القناة والحضور ← العروض الحتمية.
  /// يعيد true عند «الغرفة حية» وfalse عند فشل صادق برسالة في [error].
  Future<bool> join() async {
    if (phase.value != RoomPhase.joining) return false;

    // 1) بوابة العضوية من جدول محمي بـRLS — من خارج الأعضاء لا شيء يُقبل
    Set<String> gate;
    try {
      final rows = await supabase
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId);
      gate = {
        for (final r in (rows as List).whereType<Map<String, dynamic>>())
          if (r['user_id'] is String) r['user_id'] as String,
      };
    } catch (e) {
      debugPrint('voice room gate failed: $e');
      return _fail('تعذر التحقق من عضوية المحادثة — تحقق من اتصالك');
    }
    if (!gate.contains(meId)) {
      return _fail('لست عضواً في هذه المحادثة');
    }

    // 2) الميكروفون قبل القناة: لا حضور قبل جهوز وسائطنا
    try {
      _local = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
    } catch (_) {
      return _fail('تعذر الوصول إلى الميكروفون — تحقق من صلاحيات التطبيق');
    }
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(speakerOn.value);
      } catch (_) {}
    }

    _roster = RoomRoster(
        meId: meId, meName: meName, meAvatar: meAvatar)
      ..gate = gate;

    // 3) القناة: بثّ الإشارات + مرآة الحضور — لا تخزين في أي مكان
    try {
      _ch = supabase.channel('voice-room:$conversationId')
        ..onBroadcast(event: 'vsig', callback: (payload) {
          final sig = RoomSignal.tryParse(payload);
          if (sig != null && RoomSignal.addressedTo(sig, meId)) {
            _onSignal(sig);
          }
        })
        ..onPresenceSync((_) => _onPresence())
        ..subscribe((status, err) {
          if (status == RealtimeSubscribeStatus.channelError) {
            debugPrint('voice room channel error: $err');
          }
        });
      await _ch!.track(_meMeta());
    } catch (e) {
      debugPrint('voice room channel failed: $e');
      return _fail('تعذر فتح قناة الغرفة — تحقق من اتصالك');
    }

    phase.value = RoomPhase.live;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      duration.value = duration.value + 1;
    });
    _startVoiceWatch(); // المرحلة 11 أ: مؤشر «يتحدث» من إحصاءات الاتصال
    return true;
  }

  // ============== مؤشر «يتحدث» (المرحلة 11 أ — 0.26.0) ==============

  /// قياس محلي كل 700ms: مستوى صوتي من إحصاءات الوصلات على جهازك حصراً —
  /// لا شيء من الخادم ولا يُرسل لأحد. جهاز لا يعيد الإحصاءات يبقى بلا موجة
  /// له صادقاً (الحد معلن في الشاشة)، والمكالمة نفسها لا تتأثر إطلاقاً.
  void _startVoiceWatch() {
    _voiceTimer ??= Timer.periodic(const Duration(milliseconds: 700), (_) async {
      if (_closing || phase.value != RoomPhase.live) return;
      try {
        await _pollSpeaking();
      } catch (_) {}
    });
  }

  Future<void> _pollSpeaking() async {
    double? localLevel;
    final updated = <String, double>{};
    for (final entry in _pcs.entries) {
      final reports = await entry.value.getStats();
      double? remote;
      for (final r in reports) {
        final v = r.values;
        final t = r.type; // النوع على التقرير نفسه في النمط الأصلي
        if (t == 'inbound-rtp') {
          final a = audioLevelFromStats(v);
          if (a != null && a > (remote ?? -1)) remote = a;
        } else if ((t == 'outbound-rtp' || t == 'media-source') &&
            localLevel == null) {
          localLevel = audioLevelFromStats(v);
        }
      }
      final wave = _waves.putIfAbsent(entry.key, SpeakingWave.new);
      wave.add(remote);
      if (wave.speaking) updated[entry.key] = wave.level;
    }
    // مستواك أنت: من إحصاءات الإرسال المحلي (مكتوم = صفر تلقائياً)
    if (localLevel != null) {
      final wave = _waves.putIfAbsent('me', SpeakingWave.new);
      wave.add(localLevel);
      if (wave.speaking) updated['me'] = wave.level;
    } else if (_waves.containsKey('me')) {
      _waves['me']!.add(0.0);
    }
    final current = speakingMap.value;
    final changed = current.length != updated.length ||
        updated.entries.any((e) => (current[e.key] ?? 0) != e.value);
    if (changed) speakingMap.value = updated;
  }

  Map<String, Object?> _meMeta() => {
        'uid': meId,
        'name': meName,
        if (meAvatar != null) 'avatar': meAvatar,
        'mic': micOn.value,
      };

  /// مرآة الحضور: بناء قائمة الآخرين من الصفر كل مرة — الأدق والأبسط
  void _onPresence() {
    final roster = _roster;
    final ch = _ch;
    if (roster == null || ch == null || _closing) return;

    // الحاضرون الآن من البوابة فقط، بلا أنا، وبسعة الغرفة
    final present = <VoicePeer>[];
    for (final state in ch.presenceState()) {
      for (final p in state.presences) {
        final peer = VoicePeer.fromPresence(p.payload);
        if (peer == null) continue;
        if (peer.id == meId || !roster.isMember(peer.id)) continue;
        present.add(peer);
      }
    }
    if (present.length + 1 > RoomFlow.maxParticipants) {
      // حاجز السعة: غرفة ممتلئة لا نضيف إليها — من خارجها يُرفض انضمامه
      if (phase.value == RoomPhase.joining) {
        _fail('الغرفة ممتلئة — الحد الأقصى ${RoomFlow.maxParticipants} مشاركين');
        return;
      }
      present.removeWhere((p) => !roster.contains(p.id));
    }

    roster.clear();
    for (final p in present) {
      roster.add(p);
    }
    rosterVersion.value++;

    // وصلة قائمة: من في الحضور وبلا اتصال حي؟ — الحتمية تحسم مَن يقدّم
    for (final p in roster.others) {
      if (_pcs.containsKey(p.id)) continue;
      _link(p.id);
      if (RoomFlow.shouldOffer(meId, p.id)) {
        _negotiate(p.id);
      }
      // غير المُقدم ينتظر عرض نظيره — حضوره وصله قبل كل شيء بتصميم القناة
    }
    // من اختفى من الحضور وأُغلق؟
    for (final id in _pcs.keys.toList()) {
      if (!roster.contains(id)) _closePeer(id);
    }
  }

  // ================= WebRTC mesh =================

  void _link(String peerId) {
    final links = Map<String, String>.from(peerLinks.value);
    links[peerId] = 'connecting';
    peerLinks.value = links;
    _peerTimers[peerId]?.cancel();
    _peerTimers[peerId] = Timer(RoomFlow.connectTimeout, () {
      if (peerLinks.value[peerId] == 'connected') return;
      _noteFor(peerId, 'تعذر الاتصال بـ${_nameOf(peerId)} — غالباً شبكة محجوبة');
      _closePeer(peerId);
    });
  }

  Future<void> _negotiate(String peerId) async {
    try {
      final pc = await _makePc(peerId);
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await pc.setLocalDescription(offer);
      final local = await pc.getLocalDescription();
      _send(RoomSignal(
        from: meId,
        to: peerId,
        sig: CallSignal(type: SignalType.offer, sdp: local?.sdp),
      ));
    } catch (e) {
      debugPrint('voice room offer failed: $e');
      _noteFor(peerId, 'تعذر تجهيز الاتصال مع ${_nameOf(peerId)}');
      _closePeer(peerId);
    }
  }

  Future<RTCPeerConnection> _makePc(String peerId) async {
    final pc = await createPeerConnection({
      'iceServers': [
        for (final s in AppConfig.iceServers)
          {
            'urls': s['urls'],
            if (s['username'] != null) 'username': s['username'],
            if (s['credential'] != null) 'credential': s['credential'],
          },
      ],
      'sdpSemantics': 'unified-plan',
    });
    _pcs[peerId] = pc;
    pc.onIceCandidate = (cand) {
      if (cand.candidate == null) return;
      _send(RoomSignal(
        from: meId,
        to: peerId,
        sig: CallSignal(
          type: SignalType.ice,
          candidate: cand.candidate,
          sdpMid: cand.sdpMid,
          sdpMLineIndex: cand.sdpMLineIndex,
        ),
      ));
    };
    // الصوت البعيد يُشغَّل تلقائياً بمجرد وصوله — الغرفة صوتية بلا معرضين
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) _mark(peerId, 'connected');
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _mark(peerId, 'connected');
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _noteFor(peerId, 'انقطع الاتصال مع ${_nameOf(peerId)}');
        _closePeer(peerId);
      }
    };
    final local = _local;
    if (local != null) {
      for (final t in local.getTracks()) {
        await pc.addTrack(t, local);
      }
    }
    return pc;
  }

  // ================= الإشارات الواردة =================

  Future<void> _onSignal(RoomSignal rs) async {
    try {
      final roster = _roster;
      if (roster == null || !roster.isMember(rs.from)) return;
      switch (rs.sig.type) {
        case SignalType.ready: // لا يستخدم في الغرف — احتياط لا ضرر
          break;
        case SignalType.offer:
          if (rs.sig.sdp == null) return;
          if (RoomFlow.shouldOffer(meId, rs.from)) return; // حتمية الصامتة
          var pc = _pcs[rs.from];
          pc ??= await _makePc(rs.from);
          await pc.setRemoteDescription(
              RTCSessionDescription(rs.sig.sdp!, 'offer'));
          final answer = await pc.createAnswer({
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': 0,
          });
          await pc.setLocalDescription(answer);
          final local = await pc.getLocalDescription();
          _send(RoomSignal(
            from: meId,
            to: rs.from,
            sig: CallSignal(type: SignalType.answer, sdp: local?.sdp),
          ));
        case SignalType.answer:
          final pc = _pcs[rs.from];
          if (pc == null || rs.sig.sdp == null) return;
          await pc.setRemoteDescription(
              RTCSessionDescription(rs.sig.sdp!, 'answer'));
        case SignalType.ice:
          final pc = _pcs[rs.from];
          if (pc == null || rs.sig.candidate == null) {
            // وصلت قبل تجهيز وصلة النظير — تُخزَّن وتُصبّ بعده
            (_pendingIce[rs.from] ??= []).add(rs.sig);
            return;
          }
          await pc.addCandidate(RTCIceCandidate(
              rs.sig.candidate, rs.sig.sdpMid, rs.sig.sdpMLineIndex));
        case SignalType.bye:
          _closePeer(rs.from);
      }
    } catch (e) {
      debugPrint('voice room signal error: $e');
    }
  }

  /// تصريف المرشحات المخزنة بعد تجهيز وصلة النظير
  Future<void> _drainPendingIce(String peerId) async {
    final pc = _pcs[peerId];
    final list = _pendingIce.remove(peerId);
    if (pc == null || list == null || list.isEmpty) return;
    for (final sig in list) {
      try {
        await pc.addCandidate(RTCIceCandidate(
            sig.candidate, sig.sdpMid, sig.sdpMLineIndex));
      } catch (_) {}
    }
  }

  // ================= مفاتيح حية =================

  Future<void> toggleMic() async {
    micOn.value = !micOn.value;
    try {
      for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = micOn.value;
      }
    } catch (_) {}
    try {
      await _ch?.track(_meMeta()); // علم الكتم يصل لبقية الغرفة
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    speakerOn.value = !speakerOn.value;
    if (kIsWeb) return; // توجيه الصوت على الويب قرار متصفحك
    try {
      await Helper.setSpeakerphoneOn(speakerOn.value);
    } catch (_) {}
  }

  // ================= المغادرة =================

  Future<void> leave() async {
    if (_closing) return;
    _closing = true;
    phase.value = RoomPhase.left;
    await _teardown(sendBye: true);
    VoiceRoomService.clearActive(this);
  }

  /// تحرير كل الموارد: القناة والحضور والاتصالات والمسارات والمؤقتات —
  /// بلا استثناءات هاربة. تعمل من المغادرة ومن الفشل على السواء.
  Future<void> _teardown({required bool sendBye}) async {
    _ticker?.cancel();
    _voiceTimer?.cancel();
    _voiceTimer = null;
    _waves.clear();
    speakingMap.value = {};
    for (final t in _peerTimers.values) {
      t.cancel();
    }
    _peerTimers.clear();
    if (sendBye) {
      // وداع جماعي: بثّ للجميع قبل إغلاق كل شيء
      _send(RoomSignal(
          from: meId, sig: const CallSignal(type: SignalType.bye)));
    }
    try {
      await _ch?.untrack();
    } catch (_) {}
    for (final id in _pcs.keys.toList()) {
      await _closePeer(id);
    }
    try {
      final ch = _ch;
      _ch = null;
      if (ch != null) {
        await ch.unsubscribe();
        await supabase.removeChannel(ch);
      }
    } catch (_) {}
    try {
      final local = _local;
      _local = null;
      if (local != null) {
        for (final t in local.getTracks()) {
          try {
            await t.stop();
          } catch (_) {}
        }
        await local.dispose();
      }
    } catch (_) {}
    _roster?.clear();
    rosterVersion.value++;
  }

  // ================= مساعدات =================

  Future<void> _send(RoomSignal rs) async {
    final ch = _ch;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: 'vsig', payload: rs.toPayload());
    } catch (_) {}
  }

  void _mark(String peerId, String state) {
    final links = Map<String, String>.from(peerLinks.value);
    links[peerId] = state;
    peerLinks.value = links;
    if (state == 'connected') {
      _peerTimers[peerId]?.cancel();
      _drainPendingIce(peerId);
    }
  }

  String _nameOf(String id) => _roster?.peerOf(id)?.name ?? 'مشارك';

  void _noteFor(String peerId, String note) {
    _mark(peerId, 'lost');
    if (error.value == null) error.value = note;
  }

  Future<void> _closePeer(String peerId) async {
    _peerTimers.remove(peerId)?.cancel();
    _pendingIce.remove(peerId);
    final pc = _pcs.remove(peerId);
    if (pc != null) {
      try {
        pc.onIceCandidate = null;
        pc.onTrack = null;
        pc.onConnectionState = null;
        await pc.close();
        await pc.dispose();
      } catch (_) {}
    }
    _roster?.remove(peerId);
    final links = Map<String, String>.from(peerLinks.value);
    links.remove(peerId);
    peerLinks.value = links;
    rosterVersion.value++;
  }

  /// فشل صادق: رسالة واضحة ثم تحرير كل ما أُنشئ من موارد قبل العودة
  bool _fail(String message) {
    error.value = message;
    phase.value = RoomPhase.failed;
    _closing = true;
    _teardown(sendBye: false); // وداع لا معنى له: لم نكتمل بغرفة
    VoiceRoomService.clearActive(this);
    return false;
  }
}

/// خدمة غرف الصوت — الجسر الوحيد بين الواجهة وSupabase وWebRTC.
class VoiceRoomService {
  /// الغرفة النشطة الوحيدة (غرفة واحدة في كل مرة)
  static final ValueNotifier<VoiceRoomSession?> active =
      ValueNotifier<VoiceRoomSession?>(null);

  /// الانضمام لغرفة محادثة — null عند وجود غرفة أخرى أو غياب الدخول.
  /// الجلسة تعود دائماً حتى الفاشلة (لِيَعرض الخطأ صادقاً ثم يخرج).
  static Future<VoiceRoomSession?> join({
    required String conversationId,
    required String title,
  }) async {
    if (active.value != null) return null;
    final me = supabase.auth.currentUser?.id;
    if (me == null) return null;
    final profile = await _myProfile(me);
    final s = VoiceRoomSession(
      conversationId: conversationId,
      title: title,
      meId: me,
      meName: profile.$1,
      meAvatar: profile.$2,
    );
    active.value = s;
    final ok = await s.join();
    if (!ok) return s; // فشل صادق — الشاشة تعرضه ثم تخرج
    return s;
  }

  static void clearActive(VoiceRoomSession s) {
    if (identical(active.value, s)) active.value = null;
  }

  static Future<(String, String?)> _myProfile(String me) async {
    try {
      final r = await supabase
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', me)
          .single();
      final name = (r['display_name'] as String?)?.isNotEmpty == true
          ? r['display_name'] as String
          : ((r['username'] as String?) ?? 'أنت');
      final av = r['avatar_url'];
      return (name, av is String && av.isNotEmpty ? av : null);
    } catch (_) {
      return ('أنت', null);
    }
  }
}
