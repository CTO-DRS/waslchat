import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/media_prefs.dart';
import 'package:wasl_chat/services/video_service.dart';

/// اختبارات وحدة: ضغط الفيديو والمصغّرة والتنزيل التلقائي
/// (بند المرحلة 1 — 0.4.8)
///
/// نختبر هنا الطبقة الصافية: قرارات الضغط، بنية meta المشفّرة وحدّها،
/// حسابات base64 للمصغّرة، ومصفوفة قرار التنزيل التلقائي. الضغط نفسه
/// (MediaCodec) والتنزيل الفعلي يُختبران ميدانياً وفق CHECKLIST §16.
void main() {
  group('قرارات الضغط', () {
    test('تحت الثمنة ميغابايت: بلا ضغط', () {
      expect(VideoService.shouldCompress(4 * 1024 * 1024), isFalse);
      expect(VideoService.shouldCompress(VideoService.compressThresholdBytes),
          isFalse); // الحد نفسه لا يضغط
      expect(
          VideoService.shouldCompress(VideoService.compressThresholdBytes + 1),
          isTrue);
    });

    test('الجودة: 720p حتى 16 م.ب ثم 540p فوقها', () {
      final q1 = VideoService.qualityFor(9 * 1024 * 1024);
      final q2 = VideoService.qualityFor(20 * 1024 * 1024);
      expect(q2.index, lessThan(q1.index)); // 540p أقل درجة من 720p
    });
  });

  group('بنية meta المشفّرة', () {
    test('بنية أساسية: الاسم والحجم', () {
      final j = VideoService.metaJson(name: 'عيد_الوطن.mp4', size: 1234567);
      final m = jsonDecode(j) as Map<String, dynamic>;
      expect(m['name'], 'عيد_الوطن.mp4');
      expect(m['size'], 1234567);
      expect(m.containsKey('orig'), isFalse);
      expect(m.containsKey('thumb'), isFalse);
    });

    test('المضغوط يحفظ حجم الأصل في orig فقط عند اختلافه', () {
      final same = VideoService.metaJson(name: 'a.mp4', size: 100, originalSize: 100);
      expect((jsonDecode(same) as Map).containsKey('orig'), isFalse);
      final diff =
          VideoService.metaJson(name: 'a.mp4', size: 100, originalSize: 9000);
      expect((jsonDecode(diff) as Map)['orig'], 9000);
    });

    test('المصغّرة تُدرج كما هي داخل بنية JSON', () {
      final b64 = base64Encode(List<int>.generate(100, (i) => i % 256));
      final j = VideoService.metaJson(
          name: 'a.mp4', size: 5, thumbBase64: b64);
      final m = jsonDecode(j) as Map<String, dynamic>;
      expect(m['thumb'], b64);
    });

    test('تجاوز السقف (29000) يرمي — طريق العودة بلا مصغّرة', () {
      final bigThumb =
          base64Encode(List<int>.generate(24000, (i) => i % 256)); // 32K حرفاً
      expect(
          () => VideoService.metaJson(
              name: 'a.mp4', size: 1, thumbBase64: bigThumb),
          throwsStateError);
      // بلا مصغّرة يمرّ
      expect(
          () => VideoService.metaJsonWithoutThumb(name: 'a.mp4', size: 1),
          returnsNormally);
    });

    test('حد المصغّرة بالبايت (18000) يبقي base64 تحت سقف المحتوى 30000', () async {
      // السيناريو الأسوأ المسموح: 18000 بايت → base64 = ceil(n/3)*4
      final bytes = List<int>.generate(VideoService.maxThumbBytes, (i) => i % 256);
      final b64 = base64Encode(bytes);
      expect(b64.length, lessThanOrEqualTo(24004));
      final j = VideoService.metaJson(
          name: 'فيديو_طويل_الاسم_للاختبار.mp4',
          size: 9999999,
          originalSize: 20000000,
          thumbBase64: b64);
      expect(j.length, lessThanOrEqualTo(30000));
      expect(j.length, lessThan(VideoService.maxMetaChars + 1000));
    });

    test('thumbBytesFromBase64Length: حساب صحيح ورفض الطويلة جداً', () {
      final b64 = base64Encode(List<int>.generate(18000, (i) => i % 256));
      final decoded = VideoService.thumbBytesFromBase64Length(b64);
      expect(decoded, 18000);
      // حشو بايت واحد
      final b64pad1 = base64Encode(List<int>.generate(17999, (i) => i % 256));
      expect(VideoService.thumbBytesFromBase64Length(b64pad1), 17999);
      // طويلة جداً تُرفض
      expect(VideoService.thumbBytesFromBase64Length('a' * 40001), isNull);
      expect(VideoService.thumbBytesFromBase64Length(''), isNull);
    });
  });

  group('مصفوفة قرار التنزيل التلقائي', () {
    test('لا أبداً: يرفض حتى على واي-فاي', () {
      expect(MediaPrefs.allows(AutoDownloadRule.never, onWifi: true), isFalse);
      expect(MediaPrefs.allows(AutoDownloadRule.never, onWifi: false), isFalse);
    });

    test('واي-فاي فقط: يسمح على واي-فاي ويرفض على البيانات', () {
      expect(MediaPrefs.allows(AutoDownloadRule.wifi, onWifi: true), isTrue);
      expect(MediaPrefs.allows(AutoDownloadRule.wifi, onWifi: false), isFalse);
    });

    test('دائماً: يسمح في الحالتين', () {
      expect(MediaPrefs.allows(AutoDownloadRule.always, onWifi: true), isTrue);
      expect(MediaPrefs.allows(AutoDownloadRule.always, onWifi: false), isTrue);
    });

    test('الافتراضي واي-فاي فقط والقيم معروفة بالأسماء', () {
      expect(MediaPrefs.autoDownload.value, AutoDownloadRule.wifi);
      expect(
          MediaPrefs.ruleFromString('never'), AutoDownloadRule.never);
      expect(
          MediaPrefs.ruleFromString('wifi'), AutoDownloadRule.wifi);
      expect(
          MediaPrefs.ruleFromString('always'), AutoDownloadRule.always);
      expect(MediaPrefs.ruleFromString('mystery'), isNull);
    });

    test('تسميات صادقة لكل قاعدة', () {
      expect(MediaPrefs.label(AutoDownloadRule.never), 'بالضغط فقط');
      expect(MediaPrefs.label(AutoDownloadRule.wifi), 'واي-فاي فقط');
      expect(MediaPrefs.label(AutoDownloadRule.always), contains('دائماً'));
    });
  });

  group('الثوابت الصادقة', () {
    test('حد المحتوى للفيديو في الترحيل 026 يضم المصغّرة بأمان', () {
      // السقف في الخدمة 29000 تحت سقف الترحيل 30000 بهامش
      expect(VideoService.maxMetaChars, lessThanOrEqualTo(29000));
      // المصغّرة المسموحة لا تتجاوز ما يستوعبه السقف
      expect(
          VideoService.maxThumbBytes * 4 ~/ 3, lessThan(26000));
    });
  });
}
