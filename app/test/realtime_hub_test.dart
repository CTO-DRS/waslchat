/// اختبارات مركز Realtime الواحد النقية (المرحلة 13 ب — 1.2.0).
///
/// كل الاختبارات على HubRegistry: الحضور والمكررات (كشف التسريب) والتقليم
/// والإيقاف الكامل — بلا شبكة ولا قناة حقيقية.
import 'package:flutter_test/flutter_test.dart';

import 'package:wasl_chat/services/realtime_hub_service.dart';

void main() {
  group('HubRegistry — الحضور والمكررات', () {
    test('إلحاق جديد يعيد true ويزيد الحاضرين', () {
      final r = HubRegistry();
      expect(r.attach('chats-list'), isTrue);
      expect(r.activeCount, 1);
      expect(r.isActive('chats-list'), isTrue);
    });

    test('التسجيل المكرر لمالك حاضر يُرفض ويُحسب — لا تراكم صامت', () {
      final r = HubRegistry();
      expect(r.attach('chats-list'), isTrue);
      expect(r.attach('chats-list'), isFalse); // تسريب محتمل يُكشف
      expect(r.attach('chats-list'), isFalse);
      expect(r.activeCount, 1); // لم يزد — التقليم بالرفض
      expect(r.duplicates, 2);
    });

    test('مفاتيح متعددة تسكن جنباً إلى جنب', () {
      final r = HubRegistry();
      expect(r.attach('chats-list'), isTrue);
      expect(r.attach('call-watch'), isTrue);
      expect(r.attach('device-security'), isTrue);
      expect(r.attach('calls-history'), isTrue);
      expect(r.activeCount, 4);
    });

    test('المفتاح الفارغ يُرفض بلا حال', () {
      final r = HubRegistry();
      expect(r.attach(''), isFalse);
      expect(r.activeCount, 0);
      expect(r.duplicates, 0);
    });

    test('الفك يحذف من الحاضرين وإعادة الإلحاق تعمل بعده', () {
      final r = HubRegistry();
      r.attach('chats-list');
      expect(r.detach('chats-list'), isTrue);
      expect(r.isActive('chats-list'), isFalse);
      expect(r.attach('chats-list'), isTrue); // زيارة جديدة بعد dispose سليمة
      expect(r.attachCount('chats-list'), 2); // محاسبة الإلحاقات بصدق
    });

    test('فك غير الحاضر آمن ولا يغيّر شيئاً', () {
      final r = HubRegistry();
      expect(r.detach('غائب'), isFalse);
      expect(r.activeCount, 0);
    });

    test('stopAll يفك الجميع ويعيد عددهم', () {
      final r = HubRegistry();
      r.attach('a');
      r.attach('b');
      r.attach('c');
      expect(r.stopAll(), 3);
      expect(r.activeCount, 0);
      expect(r.duplicates, 0);
    });

    test('سطر التشخيص يذكر الحاضرون والمكررات بأرقامهم', () {
      final r = HubRegistry();
      r.attach('call-watch');
      r.attach('call-watch'); // مكرر
      final label = r.statsLabel();
      expect(label, contains('1 حاضر'));
      expect(label, contains('مكررات مرفوضة: 1'));
    });
  });

  group('مفاتيح المالك الأربعة الثابتة — عقد المركز', () {
    test('كل مشاهدي postgres الظروف الأربعة مفتاحها موحد ومحسوب', () {
      final r = HubRegistry();
      const owners = ['chats-list', 'call-watch', 'device-security', 'calls-history'];
      for (final o in owners) {
        expect(r.attach(o), isTrue, reason: 'المالك $o يجب أن يلحق بلا تعارض');
      }
      expect(r.activeCount, 4);
    });
  });
}
