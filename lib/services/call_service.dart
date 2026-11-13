/// خدمة المكالمات (المرحلة 6 — 0.17.0): تكامل WebRTC مع إشارات Realtime.
///
/// التصميم الصادق:
/// - الوسائط (الصوت والصورة) اتصال مباشر P2P مشفّر DTLS-SRTP بين الجهازين —
///   خادم وصل لا يسمع المكالمة ولا يراها ولا يمكنه ذلك.
/// - الإشارات (SDP/ICE) تمر عبر قناة بثّ Realtime لحظية لا تُخزَّن في أي
///   قاعدة بيانات وتبدد بالبث، وقد تكشف عنوان شبكتك للطرف الآخر — مطلوب
///   اتصالياً لأي WebRTC وموثق في TRANSPARENCY.md.
/// - الخادم يعرف «أيضاً» المكالمة: مَن صلى مَن ومتى وكيف انتهت — سجل مكالمات
///   يقرؤه الطرفان فقط عبر RLS وينظف بعد 90 يوماً (028_calls.sql).
/// - بلا TURN: معظم الشبكات تعمل بـSTUN، وبعض الشبكات الصارمة تفشل وتظهر
///   «تعذر الاتصال» — إعداد TURN قرار مالك وفق RUNBOOK.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, ValueNotifier;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'call_logic.dart';

/// جلسة مكالمة حية — حالة واحدة تلاحظها الواجهة وتدفعها الخدمة.
/// كل الحقول ValueNotifier فتتحدث الشاشة لحظياً بلا setState يدوي.
class CallSession {
  CallSession({
    required this.callId,
    required this.conversationId,
    required this.kind,
    required this.role,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
  });

  final String callId;
  final String conversationId;
  final CallKind kind;
  final CallRole role;
  final String peerId;
  final String peerName;
  final String? peerAvatar;

  /// الحالة — مرآة صف الخادم، وتطبَّق من الإشارات أو تغيّرات postgres
  final status = ValueNotifier<CallStatus>(CallStatus.ringing);

  /// مدة المكالمة بالثواني منذ الرد (تتقدم كل ثانية أما «متصلان»)
  final duration = ValueNotifier<int>(0);

  /// تدفق الطرف البعيد للعرض (يصل بعد اكتمال التفاوض)
  final remoteStream = ValueNotifier<MediaStream?>(null);

  /// تدفقك المحلي (لمعاينتك الصغيرة في المكالمات المرئية)
  final localStreamView = ValueNotifier<MediaStream?>(null);

  /// مفاتيح التبديل الحية
  final micOn = ValueNotifier<bool>(true);
  final cameraOn = ValueNotifier<bool>(true);

  /// مكبر الصوت: مفعّل افتراضياً للمرئية، وسمعة الجهاز للصوتية (عرف المحادثات)
  final speakerOn = ValueNotifier<bool>(false);

  /// رسالة فشل صادقة للعرض (صلاحيات، شبكة، إلغاء طرف…)
  final error = ValueNotifier<String?>(null);

  RealtimeChannel? _ch;
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final List<CallSignal> _pendingIce = [];
  Timer? _ringTimer;
  Timer? _connectTimer;
  Timer? _ticker;
  bool _closing = false;

  bool get isVideo => kind == CallKind.video;

  // ================= تدفق المُستدعي =================

  /// بدء مكالمة صادرة: قناة الإشارات + الوسائط + مهلة الرنين.
  /// الصلاحيات تُطلب هنا ( getUserMedia ) أثناء الرنين لا بعده.
  Future<void> beginOutgoing() async {
    await _openChannel();
    try {
      await _setupMediaAndPc();
    } catch (_) {
      await _fail('تعذر الوصول إلى الميكروفون أو الكاميرا — تحقق من صلاحيات التطبيق');
      return;
    }
    _ringTimer = Timer(CallFlow.ringTimeout, () async {
      if (status.value != CallStatus.ringing) return;
      // لم يُجب الطرف الآخر خلال المهلة — الطالب يصنّفها «فائتة»
      try {
        await supabase.rpc('call_update',
            params: {'call_id': callId, 'new_status': 'missed'});
      } catch (_) {}
      await _sendSignal(const CallSignal(type: SignalType.bye));
      status.value = CallStatus.missed;
      await teardown();
      CallService.clearActive(this);
    });
  }

  // ================= تدفق المُستدعى =================

  /// استقبال مكالمة واردة: قناة الإشارات تُفتح فوراً (لتلقّي إلغاء الطالب
  /// عبر تغيّر صف الخادم) — لا وسائط ولا صلاحيات إلا بعد القبول.
  Future<void> beginIncoming() async {
    await _openChannel();
    _connectTimer = Timer(CallFlow.ringTimeout, () {
      // توقف الطالب عن الرنين قبل قرارك: نغلق الواجهة بلا كتابة —
      // تصنيف «فائتة» من صاحبها فقط (مرآة call_update)
      if (status.value == CallStatus.ringing) {
        status.value = CallStatus.missed;
        teardown();
        CallService.clearActive(this);
      }
    });
  }

  /// قبول المكالمة: حالة الخادم أولاً ثم الوسائط ثم «جاهز» للطالب.
  Future<void> accept() async {
    if (status.value != CallStatus.ringing || role != CallRole.callee) return;
    try {
      await supabase.rpc('call_update',
          params: {'call_id': callId, 'new_status': 'answered'});
    } catch (e) {
      // تأخر الطالب عن الحقيقة (ألغى أو صنّفها فائتة) — بلا وسائط
      await _fail('انتهت المكالمة قبل قبولك');
      return;
    }
    _connectTimer?.cancel();
    status.value = CallStatus.answered;
    try {
      await _setupMediaAndPc();
    } catch (_) {
      await _fail('تعذر الوصول إلى الميكروفون أو الكاميرا — تحقق من صلاحيات التطبيق');
      return;
    }
    await _sendSignal(const CallSignal(type: SignalType.ready));
    await _drainPendingIce(); // مرشحات وصلت أثناء تجهيز قناتنا
    _armConnectTimeout();
  }

  /// رفض المكالمة الواردة
  Future<void> decline() async {
    if (status.value != CallStatus.ringing) return;
    try {
      await supabase.rpc('call_update',
          params: {'call_id': callId, 'new_status': 'declined'});
    } catch (_) {}
    await _sendSignal(const CallSignal(type: SignalType.bye));
    status.value = CallStatus.declined;
    await teardown();
    CallService.clearActive(this);
  }

  /// إنهاء المكالمة من الطرف الذي يضغط الإنهاء
  Future<void> hangUp() async {
    final st = status.value;
    if (!CallFlow.terminal(st)) {
      try {
        if (CallFlow.live(st)) {
          await supabase.rpc('call_update', params: {
            'call_id': callId,
            'new_status': 'ended',
            'dur': duration.value,
          });
        } else if (role == CallRole.caller) {
          await supabase.rpc('call_update',
              params: {'call_id': callId, 'new_status': 'cancelled'});
        } else {
          // المُستدعى يضغط الإنهاء قبل القبول = رفض
          await supabase.rpc('call_update',
              params: {'call_id': callId, 'new_status': 'declined'});
        }
      } catch (_) {}
      await _sendSignal(const CallSignal(type: SignalType.bye));
    }
    status.value = CallFlow.live(st)
        ? CallStatus.ended
        : (st == CallStatus.ringing
            ? (role == CallRole.caller ? CallStatus.cancelled : CallStatus.declined)
            : st);
    await teardown();
    CallService.clearActive(this);
  }

  // ================= مفاتيح حية =================

  Future<void> toggleMic() async {
    micOn.value = !micOn.value;
    try {
      for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = micOn.value;
      }
    } catch (_) {}
  }

  Future<void> toggleCamera() async {
    if (!isVideo) return;
    cameraOn.value = !cameraOn.value;
    try {
      for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
        t.enabled = cameraOn.value;
      }
    } catch (_) {}
  }

  Future<void> toggleSpeaker() async {
    speakerOn.value = !speakerOn.value;
    if (kIsWeb) return; // توجيه الصوت على الويب قرار متصفحك
    try {
      await Helper.setSpeakerphoneOn(speakerOn.value);
    } catch (_) {}
  }

  Future<void> flipCamera() async {
    if (!isVideo) return;
    try {
      final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
      if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
    } catch (_) {
      // كاميرا واحدة أو متصفح لا يسمح — تبقى الكاميرا الحالية
    }
  }

  // ================= WebRTC والإشارات =================

  Future<void> _openChannel() async {
    if (_ch != null) return;
    try {
      _ch = supabase
          .channel('call:$callId')
          // بثّ الإشارات اللحظي: SDP/ICE تمر هنا ولا تُخزَّن إطلاقاً
          .onBroadcast(event: 'sig', callback: (payload) {
            final sig = CallSignal.tryParse(payload);
            if (sig != null) _onSignal(sig);
          })
          // مرآة صف الخادم: إلغاء/رفض/انتهاء الطرف الآخر يصل وإن فشل البثّ
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'calls',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'id', value: callId),
            callback: (payload) {
              final st = callStatusFrom(payload.newRecord['status'] as String?);
              if (st != null) _onServerStatus(st);
            },
          )
          .subscribe((status, err) {
        if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('call channel error: $err');
        }
      });
    } catch (_) {
      _ch = null;
    }
  }

  Future<void> _setupMediaAndPc() async {
    if (_pc != null) return;
    final media = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': isVideo
          ? {'facingMode': 'user', 'width': {'ideal': 1280}, 'height': {'ideal': 720}}
          : false,
    });
    _local = media;
    localStreamView.value = media;
    if (!kIsWeb) {
      // سمعة الجهاز أو مكبر الصوت حسب نوع المكالمة (أندرويد)
      try {
        await Helper.setSpeakerphoneOn(speakerOn.value);
      } catch (_) {}
    }

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
    _pc = pc;

    pc.onIceCandidate = (cand) {
      if (cand.candidate == null) return;
      _sendSignal(CallSignal(
        type: SignalType.ice,
        candidate: cand.candidate,
        sdpMid: cand.sdpMid,
        sdpMLineIndex: cand.sdpMLineIndex,
      ));
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteStream.value ??= event.streams.first;
        _startTicker(); // الوسائط وصلت — تبدأ مدة المكالمة
      }
    };
    pc.onConnectionState = (state) {
      if (status.value == CallStatus.answered &&
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail('انقطع الاتصال بين الشبكتين — أغلقناها بأمان');
      }
    };

    // إضافة مساراتنا (متحدة التخطيط)
    for (final t in media.getTracks()) {
      await pc.addTrack(t, media);
    }
  }

  Future<void> _onSignal(CallSignal sig) async {
    try {
      switch (sig.type) {
        case SignalType.ready:
          // الطرف الآخر قبل وقناته جاهزة — المُستدعي يرسل العرض الآن
          if (role != CallRole.caller || status.value != CallStatus.ringing) return;
          await _sendOffer();
        case SignalType.offer:
          if (role != CallRole.callee) return;
          final pc = _pc;
          if (pc == null) return;
          await pc.setRemoteDescription(RTCSessionDescription(sig.sdp!, 'offer'));
          final answer = await pc.createAnswer({
            'offerToReceiveAudio': 1,
            'offerToReceiveVideo': isVideo ? 1 : 0,
          });
          await pc.setLocalDescription(answer);
          final local = await pc.getLocalDescription();
          await _sendSignal(CallSignal(type: SignalType.answer, sdp: local?.sdp));
          _armConnectTimeout();
        case SignalType.answer:
          final pc = _pc;
          if (pc == null || sig.sdp == null) return;
          if (status.value == CallStatus.ringing) {
            _ringTimer?.cancel();
            status.value = CallStatus.answered;
            _armConnectTimeout();
          }
          await pc.setRemoteDescription(RTCSessionDescription(sig.sdp!, 'answer'));
        case SignalType.ice:
          final pc = _pc;
          if (pc == null || sig.candidate == null) {
            // وصلت قبل تجهيز الاتصال — تُخزَّن وتُصبّ بعده
            _pendingIce.add(sig);
            return;
          }
          await pc.addCandidate(
              RTCIceCandidate(sig.candidate, sig.sdpMid, sig.sdpMLineIndex));
        case SignalType.bye:
          // الطرف الآخر أنهى — مصدر الحقيقة يظل صف الخادم، وهذا التسريع
          if (!CallFlow.terminal(status.value)) {
            final st = status.value;
            if (CallFlow.live(st)) {
              try {
                await supabase.rpc('call_update', params: {
                  'call_id': callId,
                  'new_status': 'ended',
                  'dur': duration.value,
                });
              } catch (_) {}
              status.value = CallStatus.ended;
            } else {
              status.value = role == CallRole.caller
                  ? CallStatus.cancelled
                  : CallStatus.missed;
            }
            await teardown();
            CallService.clearActive(this);
          }
      }
    } catch (e) {
      debugPrint('signal error: $e');
    }
  }

  Future<void> _sendOffer() async {
    try {
      final pc = _pc;
      if (pc == null) return;
      final offer = await pc.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': isVideo ? 1 : 0,
      });
      await pc.setLocalDescription(offer);
      final local = await pc.getLocalDescription();
      await _sendSignal(CallSignal(type: SignalType.offer, sdp: local?.sdp));
      _armConnectTimeout();
    } catch (_) {
      await _fail('تعذر تجهيز الاتصال — حاول مجدداً');
    }
  }

  /// إسقاط المرشحات المخزنة بعد تجهيز الاتصال
  Future<void> _drainPendingIce() async {
    final pc = _pc;
    if (pc == null || _pendingIce.isEmpty) return;
    final list = List<CallSignal>.from(_pendingIce);
    _pendingIce.clear();
    for (final sig in list) {
      try {
        await pc.addCandidate(
            RTCIceCandidate(sig.candidate, sig.sdpMid, sig.sdpMLineIndex));
      } catch (_) {}
    }
  }

  /// تغيّر حالة صف الخادم — مصدر الحقيقة عند كل غموض
  Future<void> _onServerStatus(CallStatus st) async {
    if (CallFlow.terminal(st) && !CallFlow.terminal(status.value)) {
      status.value = st;
      await teardown();
      CallService.clearActive(this);
      return;
    }
    if (st == CallStatus.answered && status.value == CallStatus.ringing) {
      _ringTimer?.cancel();
      status.value = CallStatus.answered;
      _drainPendingIce();
    }
  }

  /// فشل صادق مع رسالة واضحة — الخادم يُصنّفها «فشلت» إن أمكن
  Future<void> _fail(String message) async {
    error.value = message;
    try {
      await supabase.rpc('call_update',
          params: {'call_id': callId, 'new_status': 'failed'});
    } catch (_) {}
    status.value = CallStatus.failed;
    await teardown();
    CallService.clearActive(this);
  }

  /// مهلة إقامة الاتصال بعد الرد: بلا تدفق وسائط خلالها → فشل بأمانة
  void _armConnectTimeout() {
    _connectTimer?.cancel();
    _connectTimer = Timer(CallFlow.connectTimeout, () {
      if (status.value == CallStatus.answered && remoteStream.value == null) {
        _fail('تعذر إكمال الاتصال بين الشبكتين — غالباً محجوب بجدار حماية');
      } else {
        _drainPendingIce();
      }
    });
  }

  Future<void> _sendSignal(CallSignal sig) async {
    final ch = _ch;
    if (ch == null) return;
    try {
      await ch.sendBroadcastMessage(event: 'sig', payload: sig.toPayload());
    } catch (_) {}
  }

  /// تحرير كل الموارد: القناة والاتصال والمسارات والمؤقتات — بلا استثناءات هاربة
  Future<void> teardown() async {
    if (_closing) return;
    _closing = true;
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _ticker?.cancel();
    try {
      final ch = _ch;
      _ch = null;
      if (ch != null) {
        await ch.unsubscribe();
        await supabase.removeChannel(ch);
      }
    } catch (_) {}
    try {
      final pc = _pc;
      _pc = null;
      if (pc != null) {
        pc.onIceCandidate = null;
        pc.onTrack = null;
        await pc.close();
        await pc.dispose();
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
  }

  /// عدّاد المدة كل ثانية طالما المكالمة متصلة — يشغّله وصول أول مسار بعيد
  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (status.value != CallStatus.answered) return;
      duration.value = duration.value + 1;
    });
  }
}

/// خدمة المكالمات — الجسر الوحيد بين الواجهة وSupabase وWebRTC.
class CallService {
  /// الجلسة النشطة الوحيدة (لا مكالمات متوازية في النسخة الأولى)
  static final ValueNotifier<CallSession?> active = ValueNotifier<CallSession?>(null);

  /// تُضبطها الشاشة الرئيسية: ماذا تفعل عند مكالمة واردة (فتح شاشة المكالمة)
  static void Function(CallSession session)? onIncoming;

  static RealtimeChannel? _watch;
  static bool _watching = false;

  /// الاستماع للواردات: إدراج صف مكالمة أعني أن أحداً يتصل بي الآن
  static Future<void> watchIncoming() async {
    if (_watching) return;
    _watching = true;
    try {
      _watch = supabase
          .channel('call-watch')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'calls',
            callback: (payload) => _onIncomingRow(payload.newRecord),
          )
          .subscribe();
    } catch (e) {
      debugPrint('call watch failed: $e');
      _watching = false;
    }
  }

  static Future<void> stopWatching() async {
    final ch = _watch;
    _watch = null;
    _watching = false;
    try {
      if (ch != null) {
        await ch.unsubscribe();
        await supabase.removeChannel(ch);
      }
    } catch (_) {}
  }

  static Future<void> _onIncomingRow(Map<String, dynamic> row) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return;
      final rec = CallRecord.fromRow(row);
      // صف قديم أو ليس لي أو مشغول بمكالمة — بلا رنين
      if (!rec.freshIncomingRing(me, DateTime.now())) return;
      if (active.value != null) return;
      final name = await _profileName(rec.callerId);
      final avatar = await _profileAvatar(rec.callerId);
      final s = CallSession(
        callId: rec.id,
        conversationId: rec.conversationId,
        kind: rec.kind,
        role: CallRole.callee,
        peerId: rec.callerId,
        peerName: name,
        peerAvatar: avatar,
      );
      active.value = s;
      await s.beginIncoming();
      onIncoming?.call(s);
    } catch (_) {}
  }

  /// بدء مكالمة صادرة — null إن كان هناك خطأ أو مكالمة جارية
  static Future<CallSession?> start({
    required String conversationId,
    required String peerId,
    required String peerName,
    String? peerAvatar,
    required CallKind kind,
  }) async {
    if (active.value != null) return null;
    final me = supabase.auth.currentUser?.id;
    if (me == null || peerId == me || peerId.isEmpty) return null;
    try {
      final rows = await supabase
          .from('calls')
          .insert({
            'conversation_id': conversationId,
            'caller_id': me,
            'callee_id': peerId,
            'kind': kind == CallKind.video ? 'video' : 'voice',
          })
          .select();
      final row = (rows as List).first as Map<String, dynamic>;
      final s = CallSession(
        callId: row['id'] as String,
        conversationId: conversationId,
        kind: kind,
        role: CallRole.caller,
        peerId: peerId,
        peerName: peerName,
        peerAvatar: peerAvatar,
      );
      active.value = s;
      await s.beginOutgoing();
      return s;
    } catch (e) {
      debugPrint('call start failed: $e');
      return null;
    }
  }

  /// جلب سجل المكالمات (طرفا المكالمة فقط يقرآنها عبر RLS)
  static Future<List<CallRecord>> history({int limit = 120}) async {
    final me = supabase.auth.currentUser?.id;
    if (me == null) return [];
    try {
      final data = await supabase
          .from('calls')
          .select()
          .or('caller_id.eq.$me,callee_id.eq.$me')
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List)
          .whereType<Map<String, dynamic>>()
          .map(CallRecord.fromRow)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void clearActive(CallSession s) {
    if (identical(active.value, s)) active.value = null;
  }

  static Future<String> _profileName(String id) async {
    try {
      final r = await supabase
          .from('profiles')
          .select('display_name, username')
          .eq('id', id)
          .single();
      return (r['display_name'] as String?)?.isNotEmpty == true
          ? r['display_name'] as String
          : ((r['username'] as String?) ?? 'وصل');
    } catch (_) {
      return 'وصل';
    }
  }

  static Future<String?> _profileAvatar(String id) async {
    try {
      final r = await supabase.from('profiles').select('avatar_url').eq('id', id).single();
      final v = r['avatar_url'];
      return v is String && v.isNotEmpty ? v : null;
    } catch (_) {
      return null;
    }
  }
}
