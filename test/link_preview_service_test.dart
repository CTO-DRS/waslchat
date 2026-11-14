import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/link_preview_service.dart';

void main() {
  group('كشف الروابط', () {
    test('يستخرج أول رابط من نص عربي مختلط', () {
      expect(
        LinkPreviewService.extractFirstUrl('شوف هذا https://example.com/article?q=1 وانظر الباقي'),
        'https://example.com/article?q=1',
      );
    });

    test('يقص علامات الترقيم الملاصقة للرابط', () {
      expect(
        LinkPreviewService.extractFirstUrl('راجع https://example.com/notes.'),
        'https://example.com/notes',
      );
      expect(
        LinkPreviewService.extractFirstUrl('(انظر https://example.com/x)'),
        'https://example.com/x',
      );
    });

    test('لا رابط في نص خالص أو فارغ أو null', () {
      expect(LinkPreviewService.extractFirstUrl('سلام عليكم فقط'), isNull);
      expect(LinkPreviewService.extractFirstUrl(''), isNull);
      expect(LinkPreviewService.extractFirstUrl(null), isNull);
    });

    test('يرفض نصف الروابط الناقصة (أقل من الطول الأدنى)', () {
      expect(LinkPreviewService.extractFirstUrl('https://a'), isNull);
    });

    test('اسم النطاق من رابط صالح وفارغ للفاسد', () {
      expect(LinkPreviewService.hostOf('https://news.example.com/a/b'), 'news.example.com');
      expect(LinkPreviewService.hostOf('لا رابط هنا'), '');
      expect(LinkPreviewService.hostOf('ftp://example.com/f'), '');
    });
  });

  group('فك استجابة الدالة الخادمية', () {
    test('قبول استجابة كاملة (عنوان ووصف وصورة)', () {
      final d = LinkPreviewService.parseResponse({
        'url': 'https://example.com/x',
        'host': 'example.com',
        'title': 'عنوان تجريبي',
        'description': 'وصف قصير',
        'image': 'https://example.com/img.png',
      }, 'https://example.com/x');
      expect(d, isNotNull);
      expect(d!.title, 'عنوان تجريبي');
      expect(d.host, 'example.com');
    });

    test('رفض رابط لا يطابق المطلوب (لا ثقة بأي توجيه)', () {
      final d = LinkPreviewService.parseResponse({
        'url': 'https://evil.example/x',
        'title': 'احتيال',
      }, 'https://example.com/x');
      expect(d, isNull);
    });

    test('رفض الخطأ والفارغ وغير الخريطة', () {
      expect(
        LinkPreviewService.parseResponse({'error': 'فشل الجلب'}, 'https://a.com'),
        isNull,
      );
      expect(
        LinkPreviewService.parseResponse({'url': 'https://a.com'}, 'https://a.com'),
        isNull, // بلا عنوان ولا صورة = فارغة تُرفض
      );
      expect(LinkPreviewService.parseResponse('نص', 'https://a.com'), isNull);
      expect(LinkPreviewService.parseResponse(null, 'https://a.com'), isNull);
    });

    test('قبول صورة مباشرة بلا عنوان (بطاقة صورة فقط)', () {
      final d = LinkPreviewService.parseResponse(
          {'url': 'https://a.com/i.png', 'host': 'a.com', 'image': 'https://a.com/i.png'},
          'https://a.com/i.png');
      expect(d, isNotNull);
      expect(d!.image, 'https://a.com/i.png');
    });
  });

  group('الكاش المحلي 24 ساعة', () {
    test('pruneCache يبقي الصالحة فقط ويحذف المنتهية والفاسدة', () {
      final now = DateTime.now();
      final raw = <String, dynamic>{
        'https://alive.com/': {
          'data': {'url': 'https://alive.com/', 'host': 'alive.com', 'title': 'حي'},
          'exp': now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        },
        'https://dead.com/': {
          'data': {'url': 'https://dead.com/', 'title': 'ميت'},
          'exp': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        },
        'https://noexp.com/': {'data': {'url': 'https://noexp.com/'}},
        'not-a-map': 'جunk',
      };
      final ok = LinkPreviewService.pruneCache(raw, now);
      expect(ok.keys, ['https://alive.com/']);
    });

    test('cacheKey يوحّد السلاش الأخير', () {
      expect(LinkPreviewService.cacheKey('https://a.com/page/'),
          'https://a.com/page');
      expect(LinkPreviewService.cacheKey('https://a.com/page'),
          'https://a.com/page');
      // الجذر لا يتأثر (طوله محمي)
      expect(LinkPreviewService.cacheKey('https://a.com/'), 'https://a.com/');
    });

    test('دوران كامل: toJson ثم fromJson يحفظ الحقول', () {
      final d = LinkPreviewData(
          url: 'https://a.com/', host: 'a.com', title: 'ع', description: 'و');
      final j = d.toJson();
      final back = LinkPreviewData.fromJson(j);
      expect(back!.url, d.url);
      expect(back.title, d.title);
      expect(back.description, d.description);
      expect(back.image, isNull);
    });
  });
}
