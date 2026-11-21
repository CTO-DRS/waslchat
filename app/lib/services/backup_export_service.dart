import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// النسخة الاحتياطية الكاملة المشفرة (المرحلة 13 أ — 0.26.0)
///
/// القرار المفتوح من جرد الخارطة (GRAND_PLAN §1): «لا تصدير محادثات مشفرة
/// كامل» كان مؤجلاً بعد القمة — يُفتح هنا بالشكل الصادق الوحيد المتوافق مع
/// خصوصية وصل: **التصدير يجري على جهازك حصراً** — كل رسالة تُفك محلياً ثم
/// تُشفَّر مجدداً بكلمة سر تختارها أنت في ملف واحد تحفظه أينما شئت، والخادم
/// لا يرى كلمة السر ولا الملف ولا أي حرف من محتواه. والإعادة **استعراض محلي
/// حصراً**: فك الملف بكلمة سره على أي جهاز وقراءة المحتوى — ولا إعادة رفع
/// لأي رسالة إلى الخادم أبداً (ما لا نفعله موثق في الشاشة نفسها).
///
/// صيغة الملف الثنائية (تطابق تحققها الاختبار النقي حرفاً بحرف):
///   'WASLBK1' (7 بايت) + salt(32) + nonce(12) + ciphertext || mac(16)
///   المحتوى الداخلي JSON بصيغة format:1 — والتفاصيل في buildArchive.
///   المشتق: PBKDF2-SHA256 (310000 دورة) بنمط نسخة المفاتيح في e2e_service،
///   والتشفير AES-256-GCM بـ AAD = الترويسة السحرية نفسها — فتبديل بايت
///   واحد من الترويسة أو العلب يفشل الفك كلياً بلا جزئيات.
///
/// حدود صادقة معروضة في الشاشة:
///   - النصوص حصراً: الوسائط لا تدخل الملف (حجمها لا يسمح محلياً) وتُسجل
///     بسطر تسمية من ExportService.mediaLabel.
///   - آخر 500 رسالة لكل محادثة (سقف موثق) — تُذكر في ترويسة الملف.
///   - ملف بلا كلمة سر = ملف معطل عملياً — لا استعادة ممكنة لأحد، ولا
///     خادم يقدّم استعادة (كلمة السر لا تغادر جهازك).
class BackupExportService {
  BackupExportService._();

  /// الترويسة السحرية — أول بايتات الملف وتعمل أيضاً AAD للتشفير
  static const magic = 'WASLBK1';
  static const formatVersion = 1;

  /// دورات الاشتقاق — نفس نمط نسخة المفاتيح (e2e_service._backupIterations)
  static const kdfIterations = 310000;

  /// حد الرسائل لكل محادثة في الملف (موثق في الشاشة والترويسة)
  static const messagesPerConversation = 500;

  /// أقل طول كلمة سر مقبول — بلا استثناء
  static const minPassphraseLength = 8;

  static final AesGcm _aes = AesGcm.with256bits();

  // ---------- بناء الأرشيف ----------

  /// يبني خريطة الأرشيف الداخلية (قبل التشفير) — نقية ومتحققة
  static Map<String, dynamic> buildArchive({
    required String appVersion,
    required List<BackupConversation> conversations,
    String? ownerName,
  }) {
    return {
      'format': formatVersion,
      'app': appVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (ownerName != null && ownerName.isNotEmpty) 'owner': ownerName,
      'limit_per_conversation': messagesPerConversation,
      'conversations':
          conversations.map((c) => c.toJson()).toList(growable: false),
    };
  }

  /// إحصاءات الأرشيف للعرض الصادق في الشاشة قبل الحفظ وبعده
  static (int conversations, int messages) archiveStats(
      Map<String, dynamic> archive) {
    final cs = (archive['conversations'] as List?) ?? const [];
    var msgs = 0;
    for (final c in cs.whereType<Map>()) {
      msgs += ((c['messages'] as List?) ?? const []).length;
    }
    return (cs.length, msgs);
  }

  /// الترويسة المختصرة للمحادثة داخل الملف (بلا نصوص — للعرض السريع)
  static String conversationSummaryLine(BackupConversation c) {
    final kind = c.isGroup ? 'مجموعة' : 'محادثة';
    return '$kind «${c.title}» — ${c.messages.length} رسالة';
  }

  // ---------- كلمة السر ----------

  /// كلمة السر تُقبل بأدنى طول موثق — لا قواعد أخرى مفاجئة
  static bool passphraseOk(String pass) => pass.length >= minPassphraseLength;

  // ---------- التشفير والفك ----------

  static Future<SecretKey> _kek(String passphrase, List<int> salt) {
    final kdf = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: kdfIterations,
        bits: 256);
    return kdf.deriveKeyFromPassword(
        password: passphrase, nonce: salt);
  }

  /// يشفّر الأرشيف إلى بايتات الملف النهائية:
  /// magic + salt(32) + nonce(12) + ciphertext + mac — مع AAD = magic.
  static Future<Uint8List> encryptArchive(
      Map<String, dynamic> archive, String passphrase) async {
    if (!passphraseOk(passphrase)) {
      throw ArgumentError('passphrase too short');
    }
    final salt = Uint8List(32);
    final rnd = Random.secure();
    for (var i = 0; i < salt.length; i++) {
      salt[i] = rnd.nextInt(256);
    }
    final kek = await _kek(passphrase, salt);
    final plain = utf8.encode(jsonEncode(archive));
    final box = await _aes.encrypt(
      plain,
      secretKey: kek,
      nonce: _aes.newNonce(),
      aad: utf8.encode(magic),
    );
    final out = BytesBuilder();
    out.add(utf8.encode(magic));
    out.add(salt);
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// يفك ملف النسخة الاحتياطية بكلمة سره — null عند أي فشل (كلمة سر خاطئة،
  /// ملف معبوث، ترويسة غريبة، صيغة مستقبلية): لا استثناءات تتصاعد.
  static Future<Map<String, dynamic>?> decryptArchive(
      List<int> bytes, String passphrase) async {
    try {
      final magicBytes = utf8.encode(magic);
      if (bytes.length <= magicBytes.length + 32 + 12 + 16) return null;
      for (var i = 0; i < magicBytes.length; i++) {
        if (bytes[i] != magicBytes[i]) return null;
      }
      final salt = bytes.sublist(magicBytes.length, magicBytes.length + 32);
      final nonce = bytes.sublist(
          magicBytes.length + 32, magicBytes.length + 32 + 12);
      final body =
          bytes.sublist(magicBytes.length + 32 + 12);
      final cipher = Uint8List.sublistView(
          Uint8List.fromList(body), 0, body.length - 16);
      final mac = Uint8List.sublistView(Uint8List.fromList(body),
          body.length - 16);
      final kek = await _kek(passphrase, salt);
      final plain = await _aes.decrypt(
        SecretBox(cipher, nonce: Uint8List.fromList(nonce), mac: Mac(mac)),
        secretKey: kek,
        aad: magicBytes,
      );
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['format'] != formatVersion) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// فك ثم استخراج قائمة المحادثات — null عند الفشل
  static Future<List<BackupConversation>?> conversationsOf(
      List<int> bytes, String passphrase) async {
    final archive = await decryptArchive(bytes, passphrase);
    if (archive == null) return null;
    final cs = (archive['conversations'] as List?) ?? const [];
    return cs
        .whereType<Map>()
        .map((c) =>
            BackupConversation.fromJson(Map<String, dynamic>.from(c)))
        .toList();
  }

  /// اسم ملف مقترح بالتاريخ
  static String fileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'wasl_backup_${now.year}-${two(now.month)}-${two(now.day)}'
        '.waslbackup';
  }
}

/// محادثة في النسخة الاحتياطية — بياناتها مفكوكة بالفعل (الواجهة تفك)
class BackupConversation {
  const BackupConversation({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.messages,
  });

  final String id;
  final String title;
  final bool isGroup;
  final List<BackupMessage> messages;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'is_group': isGroup,
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  static BackupConversation fromJson(Map<String, dynamic> j) =>
      BackupConversation(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        isGroup: j['is_group'] == true,
        messages: ((j['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => BackupMessage.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// رسالة في النسخة الاحتياطية — نص مفكوك أو تسمية وسيط
class BackupMessage {
  const BackupMessage({
    required this.senderName,
    required this.text,
    required this.createdAtIso,
    required this.mine,
    this.media = false,
  });

  final String senderName;
  final String text;
  final String createdAtIso;
  final bool mine;
  final bool media; // تسمية وسيط لا نص حرفي

  Map<String, dynamic> toJson() => {
        's': senderName,
        'x': text,
        't': createdAtIso,
        'mine': mine,
        if (media) 'm': 1,
      };

  static BackupMessage fromJson(Map<String, dynamic> j) => BackupMessage(
        senderName: (j['s'] as String?) ?? '',
        text: (j['x'] as String?) ?? '',
        createdAtIso: (j['t'] as String?) ?? '',
        mine: j['mine'] == true,
        media: j['m'] == 1,
      );
}
