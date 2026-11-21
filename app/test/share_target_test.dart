/// اختبارات Web Share Target (1.21.0): الـmanifest البنيوي (POST وmultipart
/// وقبول الصور والأيقونات القابلة للتحديث)، عامل الصفحة البنيوي (فرع
/// المشاركة وكاشها وإعادة التوجيه ورفع نسخة القوقعة)، وقواعد الوسم
/// النقية (صالح/فاسد/غائب).
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/share_target_rules.dart';

void main() {
  group('الـmanifest البنيوي — هدف المشاركة معلن', () {
    final manifest = json
        .decode(io.File('web/manifest.json').readAsStringSync())
        as Map<String, dynamic>;

    test('share_target موجود: POST على share-target.html بمتعدد الأجزاء', () {
      final st = manifest['share_target'] as Map<String, dynamic>;
      expect(st['method'], 'POST');
      expect(st['enctype'], 'multipart/form-data');
      expect((st['action'] as String).endsWith('/share-target.html'), isTrue);
    });

    test('ملف مقبول: حقل image يقبل الصور حصراً — بند الخارطة حرفياً', () {
      final files =
          (manifest['share_target']['params']['files'] as List)
              .cast<Map<String, dynamic>>();
      expect(files, isNotEmpty);
      expect(files.first['name'], 'image');
      expect((files.first['accept'] as List), contains('image/*'));
    });

    test('أيقونات قابلة للتحديث: maskable بجانب any — تثبيت أعمق', () {
      final icons = (manifest['icons'] as List)
          .cast<Map<String, dynamic>>();
      final purposes =
          icons.map((i) => i['purpose'] as String).toSet();
      expect(purposes, containsAll(['any', 'maskable']));
      expect(icons.length, greaterThanOrEqualTo(4),
          reason: '192 و512 بأي الغرضين');
    });
  });

  group('عامل الصفحة البنيوي — المشاركة تُخزن محلياً وتُعاد للواجهة', () {
    final sw = io.File('web/sw.js').readAsStringSync();

    test('فرع POST لهدف المشاركة قبل بوابة GET', () {
      expect(sw, contains("req.method === 'POST'"));
      expect(sw, contains("/share-target.html"));
      expect(sw, contains('handleSharePost(req)'));
    });

    test('التخزين كاش محلي بوسم فريد وإعادة توجيه بوسم ?share=', () {
      expect(sw, contains("caches.open(SHARE_CACHE)"));
      expect(sw, contains("'__share__/' + token"));
      expect(sw, contains("Response.redirect('./?share=' + token, 303)"));
      // الملف لا يغادر الجهاز: لا fetch داخل معالج المشاركة
      final shareBlock =
          sw.substring(sw.indexOf('async function handleSharePost'),
              sw.indexOf('/* الأصول الثابتة'));
      expect(shareBlock.contains('fetch('), isFalse,
          reason: 'معالج المشاركة شبكة-صفر: كاش محلي حصراً');
    });

    test('رفع نسخة قوقعة الواجهة — أيقونات قابلة للتحديث عند النشر', () {
      expect(sw, contains("const SHELL_CACHE = 'wasl-shell-v2'"));
      expect(sw, contains('k !== SHARE_CACHE'),
          reason: 'كاش المشاركة لا يُمحى عند التنشيط');
    });
  });

  group('قواعد الوسم النقية — التحقق قبل أي جلب', () {
    test('وسم صالح بمعايير الصيغة', () {
      expect(ShareTargetRules.isValidToken('s1abc9xy'), isTrue);
      expect(ShareTargetRules.isValidToken('a' * 32), isTrue);
    });

    test('وسم فاسد: فارغ أو أطول من الحد أو بمحارف مسارات', () {
      expect(ShareTargetRules.isValidToken(''), isFalse);
      expect(ShareTargetRules.isValidToken('a' * 33), isFalse);
      expect(ShareTargetRules.isValidToken('../../etc'), isFalse);
      expect(ShareTargetRules.isValidToken('AB-12'), isFalse);
      expect(ShareTargetRules.isValidToken('a.b/c'), isFalse);
    });

    test('tokenFromQuery: موجود صالحاً يُستخرج وغائباً أو كاذباً null', () {
      expect(
          ShareTargetRules.tokenFromQuery({'share': 's1abc9xy'}),
          's1abc9xy');
      expect(ShareTargetRules.tokenFromQuery({}), isNull);
      expect(
          ShareTargetRules.tokenFromQuery({'share': '../x'}), isNull);
    });
  });
}
