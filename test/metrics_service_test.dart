import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/metrics_service.dart';

/// اختبارات مخزن المؤشرات النقي (المرحلة 12 ب — 0.29.0): نوافذ متدحرجة
/// بأحجام مثبتة، مئينات حتمية، ترميز وفك دفاعي — بلا شبكة ولا خزن حقيقي.
/// المؤشر صادق أو صامت: العينة الغريبة تُسقط ولا تُخترع أرقام.
void main() {
  group('النوافذ المتدحرجة', () {
    test('نافذة التسليم تُقص عند 50 أحدث أولاً', () {
      final s = MetricsStore();
      for (var i = 0; i < 60; i++) {
        s.addDelivery(i);
      }
      expect(s.deliveries.length, 50);
      expect(s.deliveries.first, 59, reason: 'الأحدث في المقدمة');
      expect(s.deliveries.last, 10, reason: 'الأقدم يُقص');
    });

    test('نافذة الفتح البارد تُقص عند 20', () {
      final s = MetricsStore();
      for (var i = 0; i < 30; i++) {
        s.addColdStart(i * 10);
      }
      expect(s.coldStarts.length, 20);
      expect(s.coldStarts.first, 290);
    });

    test('العيّنات السالبة تُسقط بلا اختراع والمتعالية تُقص لسقف 10 دقائق', () {
      final s = MetricsStore();
      s.addDelivery(-5);
      expect(s.deliveries, isEmpty, reason: 'السالبة تسقط');
      s.addDelivery(999999999); // فوق سقف 600000
      expect(s.deliveries.single, 600000, reason: 'العينة العالقة تُقص لا تفسد المعدل');
    });

    test('العدّادات محمية بسقف عددي لا يرقى', () {
      final s = MetricsStore();
      for (var i = 0; i < 200001; i++) {
        s.addError();
      }
      expect(s.errors, 100000);
      s.addOpen();
      expect(s.opens, 1);
    });
  });

  group('المعدلات والمئينات', () {
    test('المتوسط البسيط حتمي', () {
      expect(MetricsStore.avg([]), 0);
      expect(MetricsStore.avg([100, 200, 300]), 200);
      expect(MetricsStore.avg([7]), 7);
    });

    test('المئين 95 يرتب صاعداً ويأخذ الأدنى الأقرب', () {
      expect(MetricsStore.percentile([], 0.95), 0);
      final xs = [900, 100, 500, 300, 700, 200, 800, 400, 600, 1000];
      // مرتبة: 100..1000 — p95: floor(0.95*10)=9 → العنصر العاشر 1000
      expect(MetricsStore.percentile(xs, 0.95), 1000);
      // p50: floor(0.5*10)=5 → العنصر السادس 600
      expect(MetricsStore.percentile(xs, 0.5), 600);
      expect(MetricsStore.percentile([42], 0.99), 42);
    });

    test('اللقطة تجمع كل شيء بأصفار صادقة عند الفراغ', () {
      final s = MetricsStore()..addDelivery(120)..addColdStart(800)..addError();
      final snap = s.snapshot();
      expect(snap.deliverCount, 1);
      expect(snap.deliverAvgMs, 120);
      expect(snap.deliverP95Ms, 120);
      expect(snap.coldLastMs, 800);
      expect(snap.coldAvgMs, 800);
      expect(snap.errors, 1);
      expect(snap.opens, 0);
      expect(MetricsStore().snapshot().deliverAvgMs, 0);
    });
  });

  group('الترميز والفك الدفاعي', () {
    test('ذهاباً وإياباً محفوظ بالكامل', () {
      final s = MetricsStore();
      s.addDelivery(120);
      s.addDelivery(340);
      s.addColdStart(950);
      s.addError();
      s.addError();
      s.addOpen();
      final back = MetricsStore.decode(s.encode());
      expect(back.deliveries, [120, 340]);
      expect(back.coldStarts, [950]);
      expect(back.errors, 2);
      expect(back.opens, 1);
    });

    test('كل غرابة تُسقط ولا تنهار — null وفراغ وأجزاء ناقصة وقيم فاسدة', () {
      expect(MetricsStore.decode(null).deliveries, isEmpty);
      expect(MetricsStore.decode('').errors, 0);
      expect(MetricsStore.decode('a|b').errors, 0, reason: 'أقل من 4 أجزاء');
      final weird = MetricsStore.decode('1,x,3|y|notanum|-9|extra');
      // التسليم: 1 و3 قُبلا وx سقط — والإدراج بالأحدث أولاً فترتيبهما 3 ثم 1
      expect(weird.deliveries, [3, 1],
          reason: 'الأحدث في المقدمة كما في النافذة المتدحرجة');
      expect(weird.coldStarts, isEmpty);
      expect(weird.errors, 0);
      expect(weird.opens, 0, reason: 'السالب يُقص لصفر');
    });
  });
}
