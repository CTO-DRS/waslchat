import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/call_logic.dart';
import 'package:wasl_chat/services/voice_room_logic.dart';

/// اختبارات نقية للمرحلة 11 ب — مشاركة الشاشة والمكالمة الجماعية بلا شبكة
/// ولا WebRTC: قرارات المشاركة المحلية وتحليل الدعوة وعمرها وبوابة الانضمام
/// والإفصاحات الصادقة كلها تُثبت هنا قبل أي اتصال حقيقي.
void main() {
  group('مشاركة الشاشة — القرارات المحلية', () {
    test('المنصات المدعومة: أندرويد والويب نعم، وiOS لا — بلا وعود زائفة', () {
      expect(
        ScreenShareFlow.platformSupported(isWeb: false, isIos: false),
        isTrue,
      ); // أندرويد
      expect(
        ScreenShareFlow.platformSupported(isWeb: true, isIos: true),
        isTrue,
      ); // الويب يتقدم على المنصة
      expect(
        ScreenShareFlow.platformSupported(isWeb: false, isIos: true),
        isFalse,
      ); // iOS
    });

    test('البداية تتطلب حيّة + مرئية + ليست مشاركة بالفعل', () {
      expect(
        ScreenShareFlow.canStart(
            live: true, isVideo: true, alreadySharing: false),
        isTrue,
      );
      expect(
        ScreenShareFlow.canStart(
            live: false, isVideo: true, alreadySharing: false),
        isFalse,
      );
      expect(
        ScreenShareFlow.canStart(
            live: true, isVideo: false, alreadySharing: false),
        isFalse,
      );
      expect(
        ScreenShareFlow.canStart(
            live: true, isVideo: true, alreadySharing: true),
        isFalse,
      );
    });

    test('الاستعادة: نجاح بلا ملاحظة وفشل بملاحظة صادقة قابلة للعمل', () {
      expect(ScreenShareFlow.restoreNote(reacquired: true), isNull);
      final note = ScreenShareFlow.restoreNote(reacquired: false);
      expect(note, isNotNull);
      expect(note, contains('الكاميرا'));
    });

    test('سطر الإفصاح أثناء المشاركة يعلن أن كل ما يظهر يراه الطرف الآخر', () {
      final note = ScreenShareFlow.sharingNote();
      expect(note, contains('تشارك شاشتك'));
      expect(note, contains('يراه الطرف الآخر'));
    });
  });

  group('دعوة المكالمة الجماعية', () {
    GroupCallInvite inv({int ageMs = 0}) => GroupCallInvite(
          conversationId: 'conv-1',
          by: 'user-a',
          byName: 'سالم',
          at: DateTime.now().toUtc().subtract(Duration(milliseconds: ageMs)),
        );

    test('التحليل يقبل حمولة سليمة ويعيد كل الحقول', () {
      final parsed =
          GroupCallInvite.tryParse(inv().toPayload());
      expect(parsed, isNotNull);
      expect(parsed!.conversationId, 'conv-1');
      expect(parsed.by, 'user-a');
      expect(parsed.byName, 'سالم');
    });

    test('أي غرابة → null تُتجاهل: حمولة غير خريطة وحقول ناقصة أو خاطئة', () {
      expect(GroupCallInvite.tryParse(null), isNull);
      expect(GroupCallInvite.tryParse('not-a-map'), isNull);
      expect(GroupCallInvite.tryParse({'c': '', 'f': 'a', 'n': 'x', 'at': 1}),
          isNull);
      expect(GroupCallInvite.tryParse({'c': 'c1', 'f': '', 'n': 'x', 'at': 1}),
          isNull);
      expect(GroupCallInvite.tryParse({'c': 'c1', 'f': 'a', 'n': '', 'at': 1}),
          isNull);
      expect(
        GroupCallInvite.tryParse({'c': 'c1', 'f': 'a', 'n': 'x', 'at': 'ليس رقم'}),
        isNull,
      );
    });

    test('عمر الدعوة: حية داخل النافذة وميتة بعدها — لا مكالمة شبح', () {
      expect(inv(ageMs: 0).isFresh(DateTime.now().toUtc()), isTrue);
      expect(
        inv(ageMs: GroupCallInvite.lifetime.inMilliseconds - 1000)
            .isFresh(DateTime.now().toUtc()),
        isTrue,
      );
      expect(
        inv(ageMs: GroupCallInvite.lifetime.inMilliseconds + 1000)
            .isFresh(DateTime.now().toUtc()),
        isFalse,
      );
    });

    test('بوابة الانضمام: مغلق في جلسة أخرى — لا جلسات متوازية', () {
      expect(GroupCallInvite.canJoin(inAnotherSession: false), isTrue);
      expect(GroupCallInvite.canJoin(inAnotherSession: true), isFalse);
    });

    test('سطر اللافتة صادق بالاسم وبالحد الثمانية من RoomFlow', () {
      final text = inv().bannerText();
      expect(text, contains('سالم'));
      expect(text, contains('${RoomFlow.maxParticipants}'));
    });
  });

  group('نمط الجلسة والإفصاح', () {
    test('تسمية النمطين صادقة', () {
      expect(roomModeLabel(RoomMode.call), 'مكالمة جماعية');
      expect(roomModeLabel(RoomMode.room), 'غرفة صوت');
    });

    test('إفصاح المكالمة الجماعية يعلن الحدود الصادقة كاملة', () {
      final d = groupCallDisclaimer();
      expect(d, contains('${RoomFlow.maxParticipants}'));
      expect(d, contains('بلا خادم'));
      expect(d, contains('لا تُخزَّن'));
      // الحد الصادق الأهم: من حال عليه لا يصلته رن
      expect(d, contains('لا يصلته رن'));
    });
  });
}
