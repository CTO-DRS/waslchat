import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/call_logic.dart';
import 'package:wasl_chat/services/voice_room_logic.dart';

/// اختبارات نقية لمنطق غرف الصوت الجماعية (المرحلة 6 ب — 0.18.0) —
/// بلا شبكة ولا WebRTC ولا Supabase. حسم المُقدم وبوابة العضوية وآلة
/// الحالة وتوجيه الإشارات كلها قرارات محلية تُثبت هنا قبل أي اتصال حقيقي.
void main() {
  group('آلة حالة الغرفة', () {
    test('الانضمام ← الحياة مسموح، وما بعدها لا عودة للانضمام أبداً', () {
      expect(RoomFlow.canTransition(RoomPhase.joining, RoomPhase.live), isTrue);
      for (final from in RoomPhase.values) {
        expect(RoomFlow.canTransition(from, RoomPhase.joining), isFalse,
            reason: 'من $from لا عودة إلى الانضمام');
      }
    });

    test('المغادرة ممكنة من أي حالة — محايدة دائماً', () {
      for (final from in RoomPhase.values) {
        expect(RoomFlow.canTransition(from, RoomPhase.left), isTrue);
      }
    });

    test('الفشل من الانضمام أو الحياة فقط', () {
      expect(RoomFlow.canTransition(RoomPhase.joining, RoomPhase.failed), isTrue);
      expect(RoomFlow.canTransition(RoomPhase.live, RoomPhase.failed), isTrue);
      expect(RoomFlow.canTransition(RoomPhase.left, RoomPhase.failed), isFalse);
      expect(RoomFlow.canTransition(RoomPhase.failed, RoomPhase.failed), isFalse);
    });

    test('الحياة لا تُعاد ولا تُدخل إلا من الانضمام', () {
      expect(RoomFlow.canTransition(RoomPhase.live, RoomPhase.live), isFalse);
      expect(RoomFlow.canTransition(RoomPhase.left, RoomPhase.live), isFalse);
      expect(RoomFlow.canTransition(RoomPhase.failed, RoomPhase.live), isFalse);
    });

    test('terminal وlive يعرفان حصصهما', () {
      expect(RoomFlow.terminal(RoomPhase.left), isTrue);
      expect(RoomFlow.terminal(RoomPhase.failed), isTrue);
      for (final s in [RoomPhase.joining, RoomPhase.live]) {
        expect(RoomFlow.terminal(s), isFalse);
        if (s != RoomPhase.live) expect(RoomFlow.live(s), isFalse);
      }
      expect(RoomFlow.live(RoomPhase.live), isTrue);
    });

    test('نص حالة الشاشة لكل الحالات', () {
      expect(RoomFlow.phaseLabel(RoomPhase.joining), 'جارٍ الانضمام…');
      expect(RoomFlow.phaseLabel(RoomPhase.live), 'الغرفة حية');
      expect(RoomFlow.phaseLabel(RoomPhase.left), 'غادرت الغرفة');
      expect(RoomFlow.phaseLabel(RoomPhase.failed), 'تعذر الانضمام');
    });

    test('مهلة الاتصال لكل نظير ثابتة موثقة والسعة 8', () {
      expect(RoomFlow.connectTimeout, const Duration(seconds: 20));
      expect(RoomFlow.maxParticipants, 8);
    });
  });

  group('حسم المُقدم الحتمي — بلا اصطدام عروض', () {
    const a = '11111111-1111-1111-1111-111111111111';
    const b = '22222222-2222-2222-2222-222222222222';
    const c = '33333333-3333-3333-3333-333333333333';

    test('من كل زوج واحد فقط يقدّم العرض — بأي ترتيب', () {
      expect(RoomFlow.shouldOffer(a, b), isTrue);
      expect(RoomFlow.shouldOffer(b, a), isFalse);
      expect(RoomFlow.shouldOffer(a, c), isTrue);
      expect(RoomFlow.shouldOffer(c, a), isFalse);
      expect(RoomFlow.shouldOffer(b, c), isTrue);
      expect(RoomFlow.shouldOffer(c, b), isFalse);
    });

    test('التناظر: لا كلاهما يقدّم ولا كلاهما ينتظر', () {
      for (final pair in [
        [a, b], [a, c], [b, c],
      ]) {
        final x = pair[0], y = pair[1];
        expect(RoomFlow.shouldOffer(x, y) || RoomFlow.shouldOffer(y, x), isTrue,
            reason: 'أحدهما يقدّم حتماً');
        expect(RoomFlow.shouldOffer(x, y) && RoomFlow.shouldOffer(y, x), isFalse,
            reason: 'لا كلاهما يقدّم معاً');
      }
    });

    test('نفس النفس لا يقدّم شيئاً والفراغ مرفوض', () {
      expect(RoomFlow.shouldOffer(a, a), isFalse);
      expect(RoomFlow.shouldOffer('', b), isFalse);
      expect(RoomFlow.shouldOffer(a, ''), isFalse);
    });

    test('خصائص شاملة: التحوّلية والتناظر عبر ثالوث كامل', () {
      final ids = [a, b, c];
      for (final x in ids) {
        for (final y in ids) {
          if (x == y) continue;
          // التحوّلية: من قدّم لـy لا يقدّم له الآخر — والقرار مستقل بمن دخل أولاً
          final whoOffersX = RoomFlow.shouldOffer(x, y);
          expect(whoOffersX, RoomFlow.shouldOffer(x, y),
              reason: 'القرار حتمي لا يتغير بالتكرار');
        }
      }
    });
  });

  group('السعة والانضمام', () {
    test('canJoin: يُقبل دون السعة ويُرفض عند الامتلاء أو التكرار', () {
      expect(RoomFlow.canJoin(currentParticipants: 1, alreadyJoined: false), isTrue);
      expect(RoomFlow.canJoin(currentParticipants: 7, alreadyJoined: false), isTrue);
      expect(RoomFlow.canJoin(currentParticipants: 8, alreadyJoined: false), isFalse,
          reason: 'الغرفة ممتلئة — الحد الأقصى 8');
      expect(RoomFlow.canJoin(currentParticipants: 3, alreadyJoined: true), isFalse,
          reason: 'لا انضمام مرتين');
    });
  });

  group('إشارات الغرفة — التغليف والتوجيه', () {
    test('التغليف والتضفير كامل الحقول: عرض موجه لنظير', () {
      final rs = RoomSignal(
        from: 'a',
        to: 'b',
        sig: CallSignal(type: SignalType.offer, sdp: 'v=0...'),
      );
      final parsed = RoomSignal.tryParse(rs.toPayload());
      expect(parsed, isNotNull);
      expect(parsed!.from, 'a');
      expect(parsed.to, 'b');
      expect(parsed.sig.type, SignalType.offer);
      expect(parsed.sig.sdp, 'v=0...');
    });

    test('البثّ العام بلا مستهدف يصل للجميع — والوداع نموذجاً', () {
      final rs = RoomSignal(
          from: 'x', sig: const CallSignal(type: SignalType.bye));
      final map = rs.toPayload();
      expect(map.containsKey('t'), isFalse, reason: 'بلا مستهدف يُحذف الحقل');
      final parsed = RoomSignal.tryParse(map);
      expect(parsed!.to, isNull);
      expect(RoomSignal.addressedTo(parsed, 'anyone'), isTrue);
    });

    test('التوجيه: الموجهة إليّ أو بثّ عام تُقبل، والموجّهة لغيري ومشتتاتي تُرفض', () {
      RoomSignal mk(String from, String? to) => RoomSignal(
          from: from, to: to, sig: const CallSignal(type: SignalType.bye));
      expect(RoomSignal.addressedTo(mk('a', 'me'), 'me'), isTrue);
      expect(RoomSignal.addressedTo(mk('a', null), 'me'), isTrue);
      expect(RoomSignal.addressedTo(mk('a', 'other'), 'me'), isFalse);
      expect(RoomSignal.addressedTo(mk('me', 'me'), 'me'), isFalse,
          reason: 'صدى إشارتي نفسها لا يُعالج');
      expect(RoomSignal.addressedTo(mk('me', null), 'me'), isFalse,
          reason: 'بثّي العام لا يعود إليّ');
    });

    test('التحليل الدفاعي: الغريب لا يفجّر شيئاً', () {
      expect(RoomSignal.tryParse(null), isNull);
      expect(RoomSignal.tryParse('hello'), isNull);
      expect(RoomSignal.tryParse(42), isNull);
      expect(RoomSignal.tryParse({}), isNull);
      expect(RoomSignal.tryParse({'f': ''}), isNull);
      expect(RoomSignal.tryParse({'f': 'a'}), isNull, reason: 'بلا إشارة داخلية');
      expect(RoomSignal.tryParse({'f': 'a', 's': {'t': 'hack'}}), isNull,
          reason: 'إشارة داخلية غريبة تُسقط');
      expect(RoomSignal.tryParse({'f': 7, 's': {'t': 'bye'}}), isNull);
      expect(RoomSignal.tryParse({'f': 'a', 't': 9, 's': {'t': 'bye'}}), isNull);
    });

    test('عرض داخلي بلا SDP يسقط عبر التحقق الداخلي المتوارث', () {
      expect(RoomSignal.tryParse({'f': 'a', 't': 'b', 's': {'t': 'offer'}}), isNull);
      expect(
          RoomSignal.tryParse(
              {'f': 'a', 't': 'b', 's': {'t': 'ice', 'candidate': ''}}),
          isNull);
    });
  });

  group('المشاركون وتحليل الحضور', () {
    test('من presence سليم: الاسم والصورة والكتم كما هي', () {
      final p = VoicePeer.fromPresence({
        'uid': 'u1',
        'name': 'سالم',
        'avatar': 'https://x/y.png',
        'mic': false,
      });
      expect(p, isNotNull);
      expect(p!.id, 'u1');
      expect(p.name, 'سالم');
      expect(p.avatar, 'https://x/y.png');
      expect(p.micOn, isFalse);
    });

    test('الافتقارات تهبط بأمانة: بلا اسم → عضو، بلا كتم → صوت مفعّل', () {
      final p = VoicePeer.fromPresence({'uid': 'u1'});
      expect(p!.name, 'عضو');
      expect(p.micOn, isTrue);
      expect(p.avatar, isNull);
    });

    test('بلا معرف صالح → null تُتجاهل بلا انهيار', () {
      expect(VoicePeer.fromPresence({}), isNull);
      expect(VoicePeer.fromPresence({'uid': ''}), isNull);
      expect(VoicePeer.fromPresence({'uid': 42}), isNull);
      expect(VoicePeer.fromPresence({'uid': null}), isNull);
    });

    test('ذهاباً وإياباً عبر toPresence', () {
      final p = VoicePeer(id: 'u9', name: 'نورة', avatar: 'a.png', micOn: false);
      final back = VoicePeer.fromPresence(p.toPresence());
      expect(back!.id, 'u9');
      expect(back.name, 'نورة');
      expect(back.avatar, 'a.png');
      expect(back.micOn, isFalse);
      // الاسم الفارغ لا يُصدّر ليهبط «عضو» عند العودة
      final empty = VoicePeer(id: 'u2', name: '');
      expect(empty.toPresence().containsKey('name'), isFalse);
    });

    test('copyWith يغيّر الكتم ويحفظ البقية', () {
      final p = VoicePeer(id: 'u1', name: 'علي');
      final q = p.copyWith(micOn: false);
      expect(q.micOn, isFalse);
      expect(q.name, 'علي');
      expect(q.id, 'u1');
    });
  });

  group('قائمة المشاركين RoomRoster', () {
    const me = '11111111-1111-1111-1111-111111111111';
    late RoomRoster r;

    setUp(() {
      r = RoomRoster(meId: me, meName: 'أنا')..gate = {'p0', 'p1', 'p2'};
    });

    test('العدد يشملك دائماً — وحدك في البداية', () {
      expect(r.count, 1);
      expect(r.others, isEmpty);
    });

    test('إضافة أعضاء البوابة تعمل والعدد يتصاعد', () {
      expect(r.add(const VoicePeer(id: 'p1', name: 'بدر')), isTrue);
      expect(r.add(const VoicePeer(id: 'p2', name: 'أسماء')), isTrue);
      expect(r.count, 3);
      expect(r.contains('p1'), isTrue);
      expect(r.contains(me), isTrue);
    });

    test('بوابة العضوية: من خارجها يُسقط قبل أي شيء', () {
      expect(r.add(const VoicePeer(id: 'stranger', name: 'غريب')), isFalse);
      // وبوابة فارغة تعني «بلا فحص» — سلوك مفتوح صريح لا انسداد صامت
      final open = RoomRoster(meId: me, meName: 'أنا');
      expect(open.add(const VoicePeer(id: 'p3', name: 'x')), isTrue);
    });

    test('لا تكرار ولا أنت نفسك في الآخرين', () {
      expect(r.add(const VoicePeer(id: 'p1', name: 'بدر')), isTrue);
      expect(r.add(const VoicePeer(id: 'p1', name: 'بدر')), isFalse);
      expect(r.add(VoicePeer(id: me, name: 'أنا')), isFalse);
      expect(r.count, 2);
    });

    test('سعة الغرفة قاصمة عند 8 مشاركين', () {
      final full = RoomRoster(meId: me, meName: 'أنا');
      for (var i = 0; i < 7; i++) {
        expect(full.add(VoicePeer(id: 'p$i', name: 'x$i')), isTrue);
      }
      expect(full.count, 8);
      expect(full.add(const VoicePeer(id: 'p8', name: 'x8')), isFalse,
          reason: 'الغرفة ممتلئة');
    });

    test('الترتيب أبجدي بالاسم ثم بالمعرف لتسوية التساوي', () {
      r.add(const VoicePeer(id: 'p2', name: 'أسماء'));
      r.add(const VoicePeer(id: 'p1', name: 'بدر'));
      r.add(const VoicePeer(id: 'p0', name: 'أسماء'));
      expect(r.others.map((p) => p.id).toList(), ['p0', 'p2', 'p1']);
    });

    test('الكتم يُحدَّث لقائم فقط وينكث للغائب', () {
      r.add(const VoicePeer(id: 'p1', name: 'بدر'));
      expect(r.setMic('p1', false), isTrue);
      expect(r.peerOf('p1')!.micOn, isFalse);
      expect(r.setMic('ghost', false), isFalse);
    });

    test('الإزالة تعيد المشارك وتفريغ القائمة يعيد العد لأنا وحدك', () {
      r.add(const VoicePeer(id: 'p1', name: 'بدر'));
      expect(r.remove('p1')!.id, 'p1');
      expect(r.remove('p1'), isNull);
      expect(r.count, 1);
      r.add(const VoicePeer(id: 'p2', name: 'أسماء'));
      r.clear();
      expect(r.count, 1);
    });

    test('سطر العدّ صادق بالأعداد', () {
      expect(RoomRoster.countLabel(1), 'أنت وحدك في الغرفة — انتظر انضمام الأعضاء');
      expect(RoomRoster.countLabel(2), 'أنت و1 عضو آخر في الغرفة');
      expect(RoomRoster.countLabel(4), 'أنت و3 أعضاء آخرين في الغرفة');
    });
  });

  group('الحدود والنصوص الصادقة', () {
    test('أيقونة الغرفة والنص التوضيحي قبل الانضمام يذكر التشفير والسعة', () {
      final d = roomDisclaimer();
      expect(d, contains('8'));
      expect(d, contains('تشفير'));
      expect(d, contains('لا يسمعه خادم وصل'));
    });

    test('تحليل نص حالة غريب → null لا انهيار', () {
      expect(roomPhaseFrom('live'), RoomPhase.live);
      expect(roomPhaseFrom('stolen'), isNull);
      expect(roomPhaseFrom(null), isNull);
    });
  });
}
