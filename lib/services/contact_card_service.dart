import 'dart:convert';

import 'package:characters/characters.dart';

/// بطاقات جهات الاتصال المشفّرة (بند المرحلة 1 — 0.4.6).
///
/// المحتوى كله داخل التشفير بين الطرفين: رسالة `type='contact'` تحمل
/// JSON مشفّراً بالاسم والأرقام والبريد. الخادم يرى النوع فقط — لا
/// بيانات وصفية جديدة، ومعاينة القائمة نص عام «👤 جهة اتصال».
///
/// الخصوصية: أرقام جهة الاتصال لا تُرفع للخادم إطلاقاً إلا داخل بطاقة
/// يختار المستخدم إرسالها صراحةً — وقراءة دفتر الجهاز تبقى على الجهاز
/// (إذن قراءة فقط، بلا أي مزامنة).
class ContactCardService {
  ContactCardService._();

  static const String tag = 'wasl-contact-v1';

  static const int maxNameLen = 120;
  static const int maxPhones = 5;
  static const int maxPhoneLen = 32;
  static const int maxEmails = 3;
  static const int maxEmailLen = 120;

  /// حدّ الترميز قبل التشفير (حد التشفير 2900 بايت نصاً صريحاً)
  static const int maxPlainBytes = 2400;

  /// أرقام هاتف مقبولة: أرقام و + - ( ) مسافات — تكفي الأنماط العالمية
  static final RegExp _phoneRe = RegExp(r'^\+?[0-9 \-()]{5,32}$');

  /// بريد مقبول: تحقق مبسّط x@y.z يكفي لبطاقة يقرؤها إنسان
  static final RegExp _emailRe =
      RegExp(r'^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$');

  /// يرمّي [ArgumentError] عند أي تجاوز — المنتقي يتحقق قبل الإرسال
  /// وهذه طبقة ثانية تمنع محتوى فاسداً.
  static String encode({
    required String name,
    required List<String> phones,
    List<String> emails = const [],
  }) {
    final n = name.trim();
    final ps = phones.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final es = emails.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (n.isEmpty || n.length > maxNameLen) {
      throw ArgumentError('contact name');
    }
    if (ps.isEmpty || ps.length > maxPhones) {
      throw ArgumentError('contact phones count');
    }
    if (ps.any((p) => !_phoneRe.hasMatch(p))) {
      throw ArgumentError('contact phone format');
    }
    if (es.length > maxEmails || es.any((e) => !_emailRe.hasMatch(e))) {
      throw ArgumentError('contact emails');
    }
    return jsonEncode({'t': tag, 'n': n, 'p': ps, if (es.isNotEmpty) 'e': es});
  }

  static ContactCard? decode(String plain) {
    try {
      final m = jsonDecode(plain);
      if (m is! Map || m['t'] != tag) return null;
      final n = m['n'];
      final p = m['p'];
      if (n is! String || n.isEmpty || n.length > maxNameLen) return null;
      if (p is! List ||
          p.isEmpty ||
          p.length > maxPhones ||
          p.any((e) => e is! String || !_phoneRe.hasMatch(e))) {
        return null;
      }
      final e = m['e'];
      if (e != null &&
          (e is! List ||
              e.length > maxEmails ||
              e.any((x) => x is! String || !_emailRe.hasMatch(x)))) {
        return null;
      }
      return ContactCard(
        name: n,
        phones: List<String>.from(p),
        emails: e is List ? List<String>.from(e) : const [],
      );
    } catch (_) {
      return null;
    }
  }

  /// هل يمرّ المحتوى حدّ البايتات قبل التشفير؟
  static bool withinLimit(String plain) =>
      utf8.encode(plain).length <= maxPlainBytes;

  /// نص نسخ البطاقة: الاسم ثم الأرقام ثم البريد — سطراً لكل قيمة
  static String copyText(ContactCard c) {
    final b = StringBuffer(c.name);
    for (final p in c.phones) {
      b.write('\n$p');
    }
    for (final e in c.emails) {
      b.write('\n$e');
    }
    return b.toString();
  }

  /// الأحرف الأولى للصورة الرمزية (حرفان كأقصى تقدير)
  static String initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts.last.characters.first}';
  }
}

class ContactCard {
  const ContactCard({
    required this.name,
    required this.phones,
    this.emails = const [],
  });

  final String name;
  final List<String> phones;
  final List<String> emails;
}
