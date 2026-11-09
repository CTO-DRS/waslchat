import 'dart:math';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wasl_chat/services/sticker_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('validKey — مفاتيح صارمة', () {
    test('مفاتيح صالحة', () {
      expect(StickerService.validKey('basics'), isTrue);
      expect(StickerService.validKey('smile'), isTrue);
      expect(StickerService.validKey('heart_pulse'), isTrue);
      expect(StickerService.validKey('a-b_c01'), isTrue);
    });
    test('مرفوضة: فارغة/طويلة/أحرف كبيرة/رموز/مسافات/عربية', () {
      expect(StickerService.validKey(''), isFalse);
      expect(StickerService.validKey('a' * 33), isFalse);
      expect(StickerService.validKey('Basics'), isFalse);
      expect(StickerService.validKey('sm ile'), isFalse);
      expect(StickerService.validKey('smile/../../etc'), isFalse);
      expect(StickerService.validKey('smile.png'), isFalse);
      expect(StickerService.validKey('ملصق'), isFalse);
    });
  });

  group('assetPath', () {
    test('مسار صحيح للساكن والمتحرك', () {
      expect(StickerService.assetPath('basics', 'smile'),
          'assets/stickers/basics/smile.webp');
      expect(StickerService.assetPath('basics', 'heart_pulse'),
          'assets/stickers/basics/heart_pulse.gif');
      expect(StickerService.assetPath('basics', 'star_spin'),
          'assets/stickers/basics/star_spin.gif');
    });
    test('مفتاح تلاعب يرمي ArgumentError', () {
      expect(() => StickerService.assetPath('../etc', 'passwd'),
          throwsArgumentError);
      expect(() => StickerService.assetPath('basics', 'Smile'),
          throwsArgumentError);
    });
  });

  group('metaJson/decodeMeta — دائرية كاملة ورفض التلاعب', () {
    test('دائرية: نص ثم خريطة مفكوكة', () {
      final raw = StickerService.metaJson('basics', 'smile');
      expect(StickerService.decodeMeta(raw), ('basics', 'smile'));
      expect(StickerService.decodeMeta(raw), ('basics', 'smile'));
    });
    test('المتحركة تحمل ext=gif وanimated=true', () {
      final raw = StickerService.metaJson('basics', 'heart_pulse');
      expect(raw, contains('"gif"'));
      expect(raw, contains('"animated":true'));
      expect(StickerService.decodeMeta(raw), ('basics', 'heart_pulse'));
    });
    test('قبول خريطة مفكوكة مسبقاً (من _metaOf)', () {
      final raw = StickerService.metaJson('basics', 'wink');
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      expect(StickerService.decodeMeta(map), ('basics', 'wink'));
    });
    test('رفض: pack كبير الحرف / id غير موجود / ext مخالف / مفتاح غريب', () {
      expect(StickerService.decodeMeta('{"pack":"Basics","id":"smile"}'), isNull);
      expect(StickerService.decodeMeta('{"pack":"basics","id":"nope"}'), isNull);
      expect(StickerService.decodeMeta('{"pack":"basics","id":"smile","ext":"png"}'),
          isNull);
      expect(StickerService.decodeMeta('{"pack":"basics","id":"smile/x"}'), isNull);
      expect(StickerService.decodeMeta('{"pack":"basics"}'), isNull);
    });
    test('رفض: نص طويل/غير json/فارغ/null/نوع خاطئ', () {
      expect(StickerService.decodeMeta('x' * 301), isNull);
      expect(StickerService.decodeMeta('not json at all'), isNull);
      expect(StickerService.decodeMeta(''), isNull);
      expect(StickerService.decodeMeta(null), isNull);
      expect(StickerService.decodeMeta(42), isNull);
      expect(StickerService.decodeMeta(['a']), isNull);
    });
  });

  group('آخر المستخدمة — محلية بالكامل', () {
    test('remember يضيف ويتقدم للتقدم بلا تكرار', () async {
      await StickerService.remember('basics', 'smile');
      await StickerService.remember('basics', 'star');
      await StickerService.remember('basics', 'smile'); // يتقدم للأمام
      final r = await StickerService.recent();
      expect(r, [('basics', 'smile'), ('basics', 'star')]);
    });
    test('سقف 16 آخر استخدام', () async {
      final ids = StickerService.basicsOrder;
      for (var i = 0; i < ids.length && i < 20; i++) {
        await StickerService.remember('basics', ids[i]);
      }
      final r = await StickerService.recent();
      expect(r.length, StickerService.maxRecent);
      // الأحدث أولها
      expect(r.first, ('basics', ids[min(ids.length, 20) - 1]));
    });
    test('إدخالات تالفة في التخزين تُهمس بصمت', () async {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('sticker_recent',
          ['garbage', 'basics|NOPE', 'a|b|c', 'basics|wave', 'basics|fire']);
      final r = await StickerService.recent();
      // الصالحان فقط يبقيان بالترتيب، والتالف يُهمل دون انهيار
      expect(r, [('basics', 'wave'), ('basics', 'fire')]);
    });
    test('remember لمفتاح غير صالح لا يخزن شيئاً', () async {
      await StickerService.remember('basics', 'HACK');
      await StickerService.remember('../etc', 'passwd');
      expect(await StickerService.recent(), isEmpty);
    });
    test('clearRecent يفرّغ', () async {
      await StickerService.remember('basics', 'smile');
      await StickerService.clearRecent();
      expect(await StickerService.recent(), isEmpty);
    });
  });

  group('الحزمة المدمجة نفسها — تناسق داخلي', () {
    test('كل ملصقات basicsOrder بامتداد معروف ومفتاح صالح', () {
      for (final id in StickerService.basicsOrder) {
        expect(StickerService.validKey(id), isTrue, reason: id);
        expect(['webp', 'gif'], contains(StickerService.extOf(id)),
            reason: id);
      }
    });
    test('لا مكرر في الترتيب', () {
      expect(StickerService.basicsOrder.toSet().length,
          StickerService.basicsOrder.length);
    });
    test('المتحركة اثنتان بالضبط', () {
      final animated = StickerService.basicsOrder
          .where((id) => StickerService.animatedOf(id))
          .toList();
      expect(animated, ['heart_pulse', 'star_spin']);
    });
  });
}
