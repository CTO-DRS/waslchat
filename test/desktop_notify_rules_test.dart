// اختبارات إشعارات سطح المكتب (المرحلة 12 — 0.28.0): القواعد النقية —
/// بوابة المنصة وقرار الإشعار بكل شروطه الصادقة ونصوص الخادم منسوخة.
import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/desktop_notify_service.dart';

void main() {
  group('DesktopNotifyRules.platformSupported', () {
    test('الويب ليس مستهدفاً — له مساره عبر Push API', () {
      expect(
        DesktopNotifyRules.platformSupported(
            kIsWeb: true, ioLabel: 'لينكس'),
        isFalse,
      );
    });

    test('المنصات المكتبية الثلاث مستهدفة', () {
      for (final p in ['ويندوز', 'لينكس', 'ماك']) {
        expect(
          DesktopNotifyRules.platformSupported(kIsWeb: false, ioLabel: p),
          isTrue,
        );
      }
    });

    test('الجوال ليس مستهدفاً — FCM يغطيه', () {
      for (final p in ['أندرويد', 'آيفون', 'جهاز']) {
        expect(
          DesktopNotifyRules.platformSupported(kIsWeb: false, ioLabel: p),
          isFalse,
        );
      }
    });
  });

  group('DesktopNotifyRules.shouldNotify — كل الشروط معاً', () {
    final base = {
      'enabled': true,
      'resumed': false,
      'visibleConversation': null as String?,
      'conversationId': 'conv-1',
      'fromSelf': false,
      'muted': false,
    };

    test('الشروط الست مكتملة = إشعار', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: base['enabled'] as bool,
          resumed: base['resumed'] as bool,
          visibleConversation: base['visibleConversation'] as String?,
          conversationId: base['conversationId'] as String,
          fromSelf: base['fromSelf'] as bool,
          muted: base['muted'] as bool,
        ),
        isTrue,
      );
    });

    test('التطبيق في المقدمة = بلا إشعار', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: true,
          resumed: true,
          visibleConversation: null,
          conversationId: 'conv-1',
          fromSelf: false,
          muted: false,
        ),
        isFalse,
      );
    });

    test('المحادثة المعروضة الآن = بلا إشعار', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: true,
          resumed: false,
          visibleConversation: 'conv-1',
          conversationId: 'conv-1',
          fromSelf: false,
          muted: false,
        ),
        isFalse,
      );
    });

    test('رسالتي أنا من جهاز آخر = بلا إشعار', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: true,
          resumed: false,
          visibleConversation: null,
          conversationId: 'conv-1',
          fromSelf: true,
          muted: false,
        ),
        isFalse,
      );
    });

    test('مكتومة = بلا إشعار (صمت حقيقي كما الخادم)', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: true,
          resumed: false,
          visibleConversation: null,
          conversationId: 'conv-1',
          fromSelf: false,
          muted: true,
        ),
        isFalse,
      );
    });

    test('المفتاح مطفأ = بلا إشعار حتى لو تحقق كل شيء', () {
      expect(
        DesktopNotifyRules.shouldNotify(
          enabled: false,
          resumed: false,
          visibleConversation: null,
          conversationId: 'conv-1',
          fromSelf: false,
          muted: false,
        ),
        isFalse,
      );
    });
  });

  group('DesktopNotifyRules.bodyOf — نصوص الخادم منسوخة حرفياً', () {
    test('الوسائط بأيقونتها', () {
      expect(DesktopNotifyRules.bodyOf({'type': 'image'}), '📷 صورة');
      expect(DesktopNotifyRules.bodyOf({'type': 'voice'}), '🎤 رسالة صوتية');
      expect(DesktopNotifyRules.bodyOf({'type': 'video'}), '🎬 فيديو');
      expect(DesktopNotifyRules.bodyOf({'type': 'file'}), '📎 ملف');
    });

    test('المشفر (v1/v2/v3) يُعلن مشفراً بلا فك — نفس الخادم', () {
      for (final v in ['v1.', 'v2.', 'v3.']) {
        expect(
          DesktopNotifyRules.bodyOf({'type': 'text', 'content': '${v}ABCDEF'}),
          '🔒 رسالة مشفرة',
        );
      }
    });

    test('النص الصريح يُقص عند 140 حرفاً بعلامة النهاية', () {
      final long = 'أ' * 200;
      final body = DesktopNotifyRules.bodyOf({'type': 'text', 'content': long});
      expect(body.length, 141); // 140 + علامة القطع
      expect(body.endsWith('…'), isTrue);
    });

    test('النص القصير يمر كما هو', () {
      expect(
        DesktopNotifyRules.bodyOf({'type': 'text', 'content': 'مرحبا'}),
        'مرحبا',
      );
    });

    test('أي غرابة = نص عام بلا استثناء', () {
      expect(DesktopNotifyRules.bodyOf({}), 'رسالة جديدة');
      expect(
        DesktopNotifyRules.bodyOf({'type': 'text', 'content': null}),
        'رسالة جديدة',
      );
    });
  });

  group('DesktopNotifyRules.titleOf', () {
    test('الفردية = اسم المرسل حصراً', () {
      expect(
        DesktopNotifyRules.titleOf(
            senderName: 'سالم', isGroup: false, groupTitle: 'أي شيء'),
        'سالم',
      );
    });

    test('المجموعة = «المرسل · العنوان»', () {
      expect(
        DesktopNotifyRules.titleOf(
            senderName: 'سالم', isGroup: true, groupTitle: 'العمل'),
        'سالم · العمل',
      );
    });

    test('المجموعة المشفرة (v1.) تظهر «مجموعة» كما يفعل الخادم', () {
      expect(
        DesktopNotifyRules.titleOf(
            senderName: 'سالم', isGroup: true, groupTitle: 'v1.ABCDEF'),
        'سالم · مجموعة',
      );
    });

    test('عنوان غائب = مجموعة', () {
      expect(
        DesktopNotifyRules.titleOf(
            senderName: 'سالم', isGroup: true, groupTitle: null),
        'سالم · مجموعة',
      );
    });
  });
}
