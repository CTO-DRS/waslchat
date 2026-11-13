import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/call_logic.dart';

/// اختبارات نقية لمنطق المكالمات (المرحلة 6 — 0.17.0) — بلا شبكة ولا WebRTC.
/// آلة الحالة هنا مرآة حرفية لدالة call_update في ترحيل 028_calls.sql:
/// ما يرفضه الخادم يرفضه هذا الملف قبل أن يحاول، وما يسمح به الخادم لوحده يُسمح هنا وحدّه.
void main() {
  group('آلة حالة المكالمة — مرآة call_update', () {
    test('من الرنين: المُستدعى يرد ويرفض، والمُستدعي يلغي ويصنّف فائتة، والفشل من أي طرف', () {
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.answered, CallRole.callee), isTrue);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.declined, CallRole.callee), isTrue);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.cancelled, CallRole.caller), isTrue);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.missed, CallRole.caller), isTrue);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.failed, CallRole.caller), isTrue);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.failed, CallRole.callee), isTrue);
    });

    test('من الرنين: ما يرفضه الخادم يُرفض هنا — الأدوار لا تُقلب', () {
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.answered, CallRole.caller), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.declined, CallRole.caller), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.cancelled, CallRole.callee), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.missed, CallRole.callee), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.ended, CallRole.caller), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.ended, CallRole.callee), isFalse);
      expect(CallFlow.canTransition(CallStatus.ringing, CallStatus.ringing, CallRole.caller), isFalse);
    });

    test('بعد الرد: الإنهاء والفشل محتمَلان من الطرفين ولا شيء غيرهما', () {
      for (final role in CallRole.values) {
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.ended, role), isTrue);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.failed, role), isTrue);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.answered, role), isFalse);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.declined, role), isFalse);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.cancelled, role), isFalse);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.missed, role), isFalse);
        expect(CallFlow.canTransition(CallStatus.answered, CallStatus.ringing, role), isFalse);
      }
    });

    test('الحالات النهائية مغلقة تماماً — أي تحديث متأخر مرفوض من أي طرف', () {
      for (final from in [CallStatus.ended, CallStatus.declined, CallStatus.missed, CallStatus.cancelled]) {
        for (final to in CallStatus.values) {
          for (final role in CallRole.values) {
            expect(CallFlow.canTransition(from, to, role), isFalse,
                reason: '$from → $to ($role) يجب أن يرفضه الخادم والتطبيق معاً');
          }
        }
      }
    });

    test('terminal وlive يعرفان حصصهما', () {
      expect(CallFlow.terminal(CallStatus.ended), isTrue);
      expect(CallFlow.terminal(CallStatus.declined), isTrue);
      expect(CallFlow.terminal(CallStatus.missed), isTrue);
      expect(CallFlow.terminal(CallStatus.cancelled), isTrue);
      expect(CallFlow.terminal(CallStatus.ringing), isFalse);
      expect(CallFlow.terminal(CallStatus.answered), isFalse);
      expect(CallFlow.terminal(CallStatus.failed), isFalse); // الفشل ليس نهائياً بالتصميم
      expect(CallFlow.live(CallStatus.answered), isTrue);
      for (final s in CallStatus.values) {
        if (s != CallStatus.answered) expect(CallFlow.live(s), isFalse);
      }
    });

    test('مهلة الرنين ومهلة الاتصال ثابتتان موثقتان', () {
      expect(CallFlow.ringTimeout, const Duration(seconds: 45));
      expect(CallFlow.connectTimeout, const Duration(seconds: 20));
    });

    test('نص حالة الشاشة لكل الأدوار والحالات', () {
      expect(CallFlow.phaseLabel(CallStatus.ringing, CallRole.caller), 'جارٍ الاتصال…');
      expect(CallFlow.phaseLabel(CallStatus.ringing, CallRole.callee), 'مكالمة واردة');
      expect(CallFlow.phaseLabel(CallStatus.answered, CallRole.caller), 'متصلان');
      expect(CallFlow.phaseLabel(CallStatus.ended, CallRole.callee), 'انتهت المكالمة');
      expect(CallFlow.phaseLabel(CallStatus.failed, CallRole.caller), 'تعذر الاتصال');
    });
  });

  group('تنسيق المدة', () {
    test('دقائق وثوانٍ دون ساعة', () {
      expect(CallHistoryView.formatDuration(0), '0:00');
      expect(CallHistoryView.formatDuration(59), '0:59');
      expect(CallHistoryView.formatDuration(60), '1:00');
      expect(CallHistoryView.formatDuration(155), '2:35');
    });
    test('ساعات بصيغتها', () {
      expect(CallHistoryView.formatDuration(3600), '1:00:00');
      expect(CallHistoryView.formatDuration(3850), '1:04:10');
      expect(CallHistoryView.formatDuration(86400), '24:00:00');
    });
    test('السالبة تُحصر إلى صفر', () {
      expect(CallHistoryView.formatDuration(-7), '0:00');
    });
  });

  group('سجل المكالمات', () {
    CallRecord rec({
      required CallStatus status,
      required bool outgoing,
      CallKind kind = CallKind.voice,
      int duration = 0,
      DateTime? createdAt,
    }) {
      final me = '11111111-1111-1111-1111-111111111111';
      final peer = '22222222-2222-2222-2222-222222222222';
      return CallRecord(
        id: 'c1',
        conversationId: 'conv1',
        callerId: outgoing ? me : peer,
        calleeId: outgoing ? peer : me,
        kind: kind,
        status: status,
        duration: duration,
        createdAt: createdAt ?? DateTime(2026, 11, 13, 14, 30),
      );
    }

    const me = '11111111-1111-1111-1111-111111111111';

    test('التسمية الصادقة لكل حالة من منظور الطرف', () {
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.ended, outgoing: true), me), 'صادرة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.ended, outgoing: false), me), 'واردة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.answered, outgoing: false), me), 'واردة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.missed, outgoing: false), me), 'فائتة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.missed, outgoing: true), me), 'فائتة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.declined, outgoing: false), me), 'مرفوضة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.cancelled, outgoing: true), me), 'ملغاة');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.failed, outgoing: true), me), 'فشلت');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.ringing, outgoing: true), me), 'تُرن…');
      expect(CallHistoryView.statusLabel(rec(status: CallStatus.ringing, outgoing: false), me), 'واردة');
    });

    test('الأيقونات: اتجاه للسليمة وعبارة للمنقطعة', () {
      final out = CallHistoryView.statusIcon(rec(status: CallStatus.ended, outgoing: true), me);
      final inc = CallHistoryView.statusIcon(rec(status: CallStatus.ended, outgoing: false), me);
      expect(out == inc, isFalse, reason: 'الاتجاهان أيقونتان مختلفتان');
      expect(CallHistoryView.statusIcon(rec(status: CallStatus.missed, outgoing: true), me), Icons.call_missed_rounded);
      expect(CallHistoryView.statusIcon(rec(status: CallStatus.declined, outgoing: false), me), Icons.call_missed_rounded);
      expect(CallHistoryView.statusIcon(rec(status: CallStatus.cancelled, outgoing: true), me), Icons.call_end_rounded);
      expect(CallHistoryView.statusIcon(rec(status: CallStatus.failed, outgoing: false), me), Icons.phone_disabled_rounded);
    });

    test('اللون الإنذاري حمراء للمنقطعة وسكينة للسليمة', () {
      expect(CallHistoryView.negative(rec(status: CallStatus.missed, outgoing: true)), isTrue);
      expect(CallHistoryView.negative(rec(status: CallStatus.declined, outgoing: false)), isTrue);
      expect(CallHistoryView.negative(rec(status: CallStatus.cancelled, outgoing: true)), isTrue);
      expect(CallHistoryView.negative(rec(status: CallStatus.failed, outgoing: true)), isTrue);
      expect(CallHistoryView.negative(rec(status: CallStatus.ended, outgoing: true)), isFalse);
      expect(CallHistoryView.negative(rec(status: CallStatus.answered, outgoing: false)), isFalse);
    });

    test('الطرف الآخر والاتجاه من منظور مالك السجل', () {
      const peer = '22222222-2222-2222-2222-222222222222';
      final out = rec(status: CallStatus.ended, outgoing: true);
      final inc = rec(status: CallStatus.ended, outgoing: false);
      expect(out.peerId(me), peer);
      expect(inc.peerId(me), peer);
      expect(out.outgoing(me), isTrue);
      expect(inc.outgoing(me), isFalse);
    });

    test('حارس الواردات الحية: رنين وصلني وجديد فقط يرنّ', () {
      final now = DateTime(2026, 11, 13, 14, 30, 5);
      expect(rec(status: CallStatus.ringing, outgoing: false,
          createdAt: now.subtract(const Duration(seconds: 1)))
          .freshIncomingRing(me, now), isTrue);
      // رنين قديم (متأخر عن لحظة الوصول بأكثر من ثانيتين) لا يرنّ
      expect(rec(status: CallStatus.ringing, outgoing: false,
          createdAt: now.subtract(const Duration(seconds: 30)))
          .freshIncomingRing(me, now), isFalse);
      // مكالمتي الصادرة لا تُرنّ لي
      expect(rec(status: CallStatus.ringing, outgoing: true,
          createdAt: now)
          .freshIncomingRing(me, now), isFalse);
      // غير الرنين لا يُرنّ أبداً
      expect(rec(status: CallStatus.ended, outgoing: false, createdAt: now)
          .freshIncomingRing(me, now), isFalse);
    });

    test('وقت الصف: اليوم وأمس والشهر وسنة أخرى', () {
      final now = DateTime(2026, 11, 13, 20, 0);
      expect(CallHistoryView.timeLabel(DateTime(2026, 11, 13, 14, 30), now), 'اليوم 14:30');
      expect(CallHistoryView.timeLabel(DateTime(2026, 11, 12, 9, 5), now), 'أمس 09:05');
      expect(CallHistoryView.timeLabel(DateTime(2026, 11, 5, 8, 0), now), '5 نوفمبر');
      expect(CallHistoryView.timeLabel(DateTime(2025, 1, 20, 8, 0), now), '20 يناير 2025');
    });
  });

  group('تحليل رسائل الإشارة', () {
    test('العرض والجواب بصيغتهما السليمة', () {
      final offer = CallSignal.tryParse({'t': 'offer', 'sdp': 'v=0...'});
      expect(offer, isNotNull);
      expect(offer!.type, SignalType.offer);
      expect(offer.sdp, 'v=0...');
      final answer = CallSignal.tryParse({'t': 'answer', 'sdp': 'v=1...'});
      expect(answer!.type, SignalType.answer);
    });

    test('العرض والجواب بلا SDP أو نص فارغ = رسالة معطوبة تُتجاهل', () {
      expect(CallSignal.tryParse({'t': 'offer'}), isNull);
      expect(CallSignal.tryParse({'t': 'answer', 'sdp': ''}), isNull);
    });

    test('المرشح ICE بمخاليفه يمرّ، وبلا مرشح يُرفض', () {
      final ice = CallSignal.tryParse({'t': 'ice', 'candidate': 'candidate:1 udp', 'sdpMid': '0', 'sdpMLineIndex': 0});
      expect(ice, isNotNull);
      expect(ice!.candidate, 'candidate:1 udp');
      expect(ice.sdpMid, '0');
      expect(ice.sdpMLineIndex, 0);
      expect(CallSignal.tryParse({'t': 'ice'}), isNull);
      expect(CallSignal.tryParse({'t': 'ice', 'candidate': ''}), isNull);
    });

    test('الأنواع غير المعروفة والحمولات الغريبة لا تُفجّر شيئاً', () {
      expect(CallSignal.tryParse(null), isNull);
      expect(CallSignal.tryParse('hello'), isNull);
      expect(CallSignal.tryParse(42), isNull);
      expect(CallSignal.tryParse({'t': 'hack'}), isNull);
      expect(CallSignal.tryParse({}), isNull);
    });

    test('جاهزية المُستدعى ووداع الطرفين تدخلان وتخرجان كما هما', () {
      expect(CallSignal.tryParse({'t': 'ready'})!.type, SignalType.ready);
      expect(CallSignal.tryParse({'t': 'bye'})!.type, SignalType.bye);
      for (final t in ['ready', 'bye']) {
        final sig = CallSignal.tryParse({'t': t});
        expect(sig!.toPayload(), {'t': t});
      }
      final ice = CallSignal.tryParse({'t': 'ice', 'candidate': 'c1', 'sdpMid': 'audio'});
      expect(ice!.toPayload(), {'t': 'ice', 'candidate': 'c1', 'sdpMid': 'audio'});
    });
  });

  group('تحليل الصفوف والأنواع', () {
    test('حالة غريبة أو نوع غريب → سلوك محدد لا انهيار', () {
      expect(callStatusFrom('stolen'), isNull);
      expect(callStatusFrom(null), isNull);
      expect(callKindFrom('video'), CallKind.video);
      expect(callKindFrom('voice'), CallKind.voice);
      expect(callKindFrom(null), CallKind.voice);
      expect(callKindLabel(CallKind.voice), 'صوتية');
      expect(callKindLabel(CallKind.video), 'مرئية');
    });

    test('صف من الخادم بأعمدته العربية يجيب كاملاً', () {
      final r = CallRecord.fromRow({
        'id': 'x1',
        'conversation_id': 'cv',
        'caller_id': 'a',
        'callee_id': 'b',
        'kind': 'video',
        'status': 'answered',
        'duration': 155,
        'created_at': '2026-11-13T14:30:00.000Z',
      });
      expect(r.kind, CallKind.video);
      expect(r.status, CallStatus.answered);
      expect(r.duration, 155);
      expect(r.id, 'x1');
      // صف تالف: أعمدة ناقصة → قيم أمانة لا انهيار
      final broken = CallRecord.fromRow({});
      expect(broken.status, CallStatus.failed);
      expect(broken.duration, 0);
    });
  });
}
