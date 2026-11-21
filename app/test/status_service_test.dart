import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/status_service.dart';

/// اختبارات وحدة للدوال النقية في خدمة الحالات (بدون شبكة)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('newId يولّد معرف UUID v4 صيغته صحيحة ومتفرّد', () {
    final re = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
    final seen = <String>{};
    for (var i = 0; i < 1000; i++) {
      final id = StatusService.newId();
      expect(re.hasMatch(id), isTrue, reason: 'صيغة غير صحيحة: $id');
      seen.add(id);
    }
    expect(seen.length, 1000, reason: 'تكرار في المعرفات المولّدة');
  });

  test('groupByAuthor: حالتي أولاً ثم الأحدث نشراً والحالات داخل المجموعة مرتّبة',
      () {
    final me = 'me-uuid';
    final rows = <Map<String, dynamic>>[
      {
        'status_id': 's1',
        'author_id': 'b-uuid',
        'author_name': 'ب',
        'created_at': '2026-11-12T09:00:00Z',
        'viewed': true,
      },
      {
        'status_id': 's2',
        'author_id': me,
        'author_name': 'أنا',
        'created_at': '2026-11-12T08:00:00Z',
        'viewed': false,
      },
      {
        'status_id': 's3',
        'author_id': 'b-uuid',
        'author_name': 'ب',
        'created_at': '2026-11-12T10:00:00Z',
        'viewed': false,
      },
      {
        'status_id': 's4',
        'author_id': 'a-uuid',
        'author_name': 'أ',
        'created_at': '2026-11-12T07:00:00Z',
        'viewed': true,
      },
    ];

    final groups = StatusService.groupByAuthor(rows, me);

    expect(groups.length, 3);
    // حالتي أولاً رغم أن أحدث حالات «ب» أحدث من حلاتي
    expect(groups[0]['author_id'], me);
    expect(groups[0]['is_me'], isTrue);
    // ثم «ب» (أحدث حالة 10:00) قبل «أ» (07:00)
    expect(groups[1]['author_id'], 'b-uuid');
    expect(groups[2]['author_id'], 'a-uuid');
    // الحالات داخل «ب» بأحدث نشر أولاً
    final bStatuses = groups[1]['statuses'] as List<Map<String, dynamic>>;
    expect(bStatuses.map((s) => s['status_id']).toList(), ['s3', 's1']);
  });

  test('groupByAuthor: علامة «شُوهد كله» تتحقق فقط عند مشاهدة كل حالات صاحبها', () {
    final me = 'me-uuid';
    final rows = <Map<String, dynamic>>[
      {
        'status_id': 'x1',
        'author_id': 'u1',
        'author_name': 'ع',
        'created_at': '2026-11-12T09:00:00Z',
        'viewed': true,
      },
      {
        'status_id': 'x2',
        'author_id': 'u1',
        'author_name': 'ع',
        'created_at': '2026-11-12T08:00:00Z',
        'viewed': false,
      },
    ];
    final groups = StatusService.groupByAuthor(rows, me);
    expect(groups.single['all_viewed'], isFalse);

    // بعد مشاهدة كل حالاته
    for (final r in rows) {
      r['viewed'] = true;
    }
    final groups2 = StatusService.groupByAuthor(rows, me);
    expect(groups2.single['all_viewed'], isTrue);
  });

  test('groupByAuthor: حالتي تُعتبر مشهودة دائماً (بادج غير مقروء لي لا يظهر)', () {
    final me = 'me-uuid';
    final rows = <Map<String, dynamic>>[
      {
        'status_id': 'm1',
        'author_id': me,
        'author_name': 'أنا',
        'created_at': '2026-11-12T09:00:00Z',
        'viewed': false,
      },
    ];
    final groups = StatusService.groupByAuthor(rows, me);
    expect(groups.single['is_me'], isTrue);
    expect(groups.single['all_viewed'], isTrue);
  });

  test('groupByAuthor: يتجاهل الصفوف بلا معرف صاحب ولا ينهار', () {
    final rows = <Map<String, dynamic>>[
      {'status_id': 'bad', 'created_at': '2026-11-12T09:00:00Z'},
      {'status_id': 'ok', 'author_id': 'u1', 'author_name': 'س',
          'created_at': '2026-11-12T09:00:00Z', 'viewed': true},
    ];
    final groups = StatusService.groupByAuthor(rows, 'me-uuid');
    expect(groups.length, 1);
    expect(groups.single['author_id'], 'u1');
    expect(groups.single['all_viewed'], isTrue);
    expect(groups.single['author_name'], 'س');
  });

  test('ageText: صياغة عربية مختصرة حسب قِدم الحالة', () {
    final now = DateTime.now();
    expect(StatusService.ageText(now.toIso8601String()), 'الآن');
    expect(
        StatusService.ageText(now.subtract(const Duration(minutes: 5)).toIso8601String()),
        'قبل 5 د');
    expect(
        StatusService.ageText(now.subtract(const Duration(hours: 3)).toIso8601String()),
        'قبل 3 س');
  });
}
