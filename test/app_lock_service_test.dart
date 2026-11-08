// اختبار قفل التطبيق: تجزئة رمز الـPIN (PBKDF2-SHA256) — دوال نقية بلا قنوات منصة
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wasl_chat/services/app_lock_service.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AppLockService: تجزئة رمز الـPIN', () {
    test('نفس الـPIN والملح يعيدان نفس التجزئة', () async {
      final salt = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final h1 = await AppLockService.hashPin('123456', salt);
      final h2 = await AppLockService.hashPin('123456', salt);
      expect(h1, equals(h2));
      expect(h1.length, 32); // 256 بت
    });

    test('ملح مختلف يعيد تجزئة مختلفة (حماية من جداول المبالغات)', () async {
      final h1 = await AppLockService.hashPin(
          '123456', Uint8List.fromList(List.filled(16, 1)));
      final h2 = await AppLockService.hashPin(
          '123456', Uint8List.fromList(List.filled(16, 2)));
      expect(h1, isNot(equals(h2)));
    });

    test('الـPIN الصحيح يطابق السجل salt:hash', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i * 3));
      final hash = await AppLockService.hashPin('987654', salt);
      final record = '${_hex(salt)}:${_hex(hash)}';
      expect(await AppLockService.checkPinRecord('987654', record), isTrue);
    });

    test('الـPIN الخاطئ لا يطابق السجل', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
      final hash = await AppLockService.hashPin('111111', salt);
      final record = '${_hex(salt)}:${_hex(hash)}';
      expect(await AppLockService.checkPinRecord('222222', record), isFalse);
    });

    test('سجل تالف يعيد فشلاً لا استثناء', () async {
      expect(await AppLockService.checkPinRecord('123456', 'garbage'), isFalse);
      expect(await AppLockService.checkPinRecord('123456', 'zz:zz'), isFalse);
      expect(await AppLockService.checkPinRecord('123456', ''), isFalse);
    });
  });
}
