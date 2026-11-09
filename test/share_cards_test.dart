import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/contact_card_service.dart';
import 'package:wasl_chat/services/location_service.dart';

/// اختبارات وحدة: الموقع وبطاقات جهات الاتصال (بند المرحلة 1 — 0.4.6)
/// الطبقة المشفّرة (E2eService) مُختبرة في ملفها الخاص — هنا نختبر
/// ترميز المحتوى وفكّه وحدوده الصارمة.
void main() {
  group('الموقع: الترميز والفك', () {
    test('دورة كاملة بإحداثيات ودقة ووصف', () {
      final plain = LocationService.encode(
          lat: 24.7136, lng: 46.6753, accuracyM: 15.4, label: 'الرياض');
      final loc = LocationService.decode(plain);
      expect(loc, isNotNull);
      expect(loc!.lat, closeTo(24.7136, 0.0000001));
      expect(loc.lng, closeTo(46.6753, 0.0000001));
      expect(loc.accuracyM, 15);
      expect(loc.label, 'الرياض');
    });

    test('تدوير الإحداثيات إلى 6 كسور عشرية', () {
      final plain =
          LocationService.encode(lat: 24.123456789, lng: 46.987654321);
      expect(plain, contains('24.123457'));
      expect(plain, contains('46.987654'));
    });

    test('تثبيت النطاق: خط عرض > 90 يُقبَض إلى 90', () {
      final loc = LocationService.decode(
          LocationService.encode(lat: 120, lng: -200));
      expect(loc!.lat, 90);
      expect(loc.lng, -180);
    });

    test('geo URI بالصيغة القياسية', () {
      expect(LocationService.geoUri(24.7, 46.6), 'geo:24.7,46.6?q=24.7,46.6');
      expect(
          LocationService.decode(LocationService.encode(lat: 1, lng: 2))!
              .geoUri,
          'geo:1.0,2.0?q=1.0,2.0');
    });

    test('رفض توقيع خاطئ وJSON فاسد وقيم ناقصة', () {
      expect(LocationService.decode('{"t":"other"}'), isNull);
      expect(LocationService.decode('not json'), isNull);
      expect(
          LocationService.decode('{"t":"wasl-location-v1","la":5}'), isNull);
      expect(
          LocationService.decode(
              '{"t":"wasl-location-v1","la":95,"lo":0}'), // خارج النطاق
          isNull);
      expect(
          LocationService.decode(
              '{"t":"wasl-location-v1","la":0,"lo":0,"ac":-3}'), // دقة سالبة
          isNull);
    });

    test('دقة بلا وصف تُرمّز وتُفكّ بلا label', () {
      final loc =
          LocationService.decode(LocationService.encode(lat: 1, lng: 2));
      expect(loc!.label, isNull);
      expect(loc.accuracyM, isNull);
    });

    test('حد البايتات قبل التشفير', () {
      final plain = LocationService.encode(
          lat: 1, lng: 2, label: 'و' * LocationService.maxLabelLen);
      expect(LocationService.withinLimit(plain), isTrue);
    });
  });

  group('بطاقات جهات الاتصال: الترميز والفك', () {
    test('دورة كاملة باسم وأرقام وبريد', () {
      final plain = ContactCardService.encode(
        name: 'أحمد صالح',
        phones: ['+966 50 123 4567', '011 234 5678'],
        emails: ['ahmad@example.com'],
      );
      final c = ContactCardService.decode(plain);
      expect(c, isNotNull);
      expect(c!.name, 'أحمد صالح');
      expect(c.phones, ['+966 50 123 4567', '011 234 5678']);
      expect(c.emails, ['ahmad@example.com']);
    });

    test('بطاقة بأرقام فقط بلا بريد', () {
      final c = ContactCardService.decode(
          ContactCardService.encode(name: 'سارة', phones: ['0501234567']));
      expect(c!.emails, isEmpty);
    });

    test('نص النسخ: الاسم ثم كل قيمة سطراً', () {
      final text = ContactCardService.copyText(ContactCard(
          name: 'خالد',
          phones: ['0500000000'],
          emails: ['k@example.com']));
      expect(text, 'خالد\n0500000000\nk@example.com');
    });

    test('الأحرف الأولى للاسم العربي والمفرد', () {
      expect(ContactCardService.initials('أحمد صالح'), 'أص');
      expect(ContactCardService.initials('سارة'), 'سا');
      expect(ContactCardService.initials('   '), '؟');
    });

    test('رفض اسم فارغ أو طويل، وعدم أرقام، وأرقام زائدة', () {
      expect(() => ContactCardService.encode(name: '', phones: ['050123']),
          throwsArgumentError);
      expect(
          () => ContactCardService.encode(
              name: 'ن' * (ContactCardService.maxNameLen + 1),
              phones: ['050123']),
          throwsArgumentError);
      expect(() => ContactCardService.encode(name: 'ب', phones: []),
          throwsArgumentError);
      expect(
          () => ContactCardService.encode(name: 'ب', phones: ['abc!!']),
          throwsArgumentError);
      expect(
          () => ContactCardService.encode(
              name: 'ب',
              phones: List.generate(
                  ContactCardService.maxPhones + 1, (i) => '05012345$i')),
          throwsArgumentError);
    });

    test('رفض بريد مشوّه أو زائد عن الحد', () {
      expect(
          () => ContactCardService.encode(
              name: 'ب', phones: ['050123'], emails: ['بريد-غير-صالح']),
          throwsArgumentError);
      expect(
          () => ContactCardService.encode(
              name: 'ب',
              phones: ['050123'],
              emails: List.generate(
                  ContactCardService.maxEmails + 1, (i) => 'a$i@x.com')),
          throwsArgumentError);
    });

    test('رفض توقيع خاطئ وJSON فاسد وأرقام فاسدة', () {
      expect(ContactCardService.decode('{"t":"other"}'), isNull);
      expect(ContactCardService.decode('{{'), isNull);
      expect(
          ContactCardService.decode(
              '{"t":"wasl-contact-v1","n":"ب","p":[]}'), // بلا أرقام
          isNull);
      expect(
          ContactCardService.decode(
              '{"t":"wasl-contact-v1","n":"ب","p":["موبايل"]}'), // رقم فاسد
          isNull);
    });

    test('حد البايتات قبل التشفير', () {
      final plain = ContactCardService.encode(
          name: 'ع' * ContactCardService.maxNameLen,
          phones: ['+966500000000'],
          emails: ['long_name_here@example-domain.com']);
      expect(ContactCardService.withinLimit(plain), isTrue);
    });
  });
}
