import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;

import '../config.dart';
import 'e2e_service.dart';
import 'media_service.dart';

/// إعادة توجيه رسالة إلى محادثة أخرى من قائمة «المحادثات».
/// المحتوى يُفك على الجهاز ثم يُشفَّر من جديد بمفتاح المحادثة الهدف — الخادم لا يرى شيئاً.
/// في المحادثات الخاصة: النص والميتا يُشفَّران عبر الجلسة المتدرجة (سرية أمامية)،
/// والوسائط أيضاً من المرحلة 10 (0.24.0): مفتاح محتوى عشوائي للوسيط يُغلَّف داخل
/// ميتا الرسالة المتدرجة — والمجموعات تبقى على مفتاحها المغلَّف كما هي.
class ForwardService {
  ForwardService._();

  /// مفتاح محادثة هدف (صف من my_chats) — للوسائط والمجموعات
  static Future<SecretKey?> _keyFor(Map<String, dynamic> chat) {
    final conv = chat['conversation_id'] as String;
    if (chat['is_group'] == true) return E2eService.groupKey(conv);
    final other = chat['other_id'] as String?;
    if (other == null) return Future.value(null);
    return E2eService.dmKey(conv, other);
  }

  static bool _isDm(Map<String, dynamic> chat) =>
      chat['is_group'] != true && (chat['other_id'] as String?) != null;

  /// يرسل نصاً أو وسيطاً (بايتات صريحة) إلى المحادثة الهدف. يعيد false عند الفشل.
  static Future<bool> send({
    required Map<String, dynamic> target,
    required String type,
    String? text,
    Uint8List? bytes,
    int? durationMs,
  }) async {
    try {
      final conv = target['conversation_id'] as String;
      final me = supabase.auth.currentUser!.id;
      final dm = _isDm(target);
      final key = await _keyFor(target);
      if (key == null) return false;
      if (type == 'text') {
        if (text == null || !E2eService.withinPlainLimit(text)) return false;
        final String payload;
        if (dm) {
          final p = await E2eService.encryptDmText(
              conv, target['other_id'] as String, text);
          if (p == null) return false;
          payload = p;
        } else {
          payload = await E2eService.encryptText(key, conv, text);
        }
        await supabase.from('messages').insert({
          'conversation_id': conv,
          'sender_id': me,
          'type': 'text',
          'content': payload,
        });
        return true;
      }
      if (bytes == null) return false;
      final Uint8List enc;
      String meta = '';
      if (dm) {
        // المرحلة 10: وسائط الخاص المعاد توجيهها تدخل الجلسة المتدرجة كالمرسلة
        // مباشرة — مفتاح محتوى عشوائي يُغلَّف داخل الميتا المتدرجة (مع الاسم إن وجد)
        final mk = await E2eService.newContentKey();
        enc = await E2eService.encryptBytes(mk, conv, bytes);
        final metaMap = <String, dynamic>{
          'mk': base64Encode(await mk.extractBytes()),
          if (text != null && text.isNotEmpty) 'name': text,
        };
        meta = (await E2eService.encryptDmText(
                conv, target['other_id'] as String, jsonEncode(metaMap))) ??
            '';
      } else {
        enc = await E2eService.encryptBytes(key, conv, bytes);
        if (text != null && text.isNotEmpty) {
          meta = await E2eService.encryptText(key, conv, text);
        }
      }
      final path = await MediaService.upload(
        conversationId: conv,
        bytes: enc,
        ext: 'enc.bin',
        contentType: 'application/octet-stream',
      );
      await supabase.from('messages').insert({
        'conversation_id': conv,
        'sender_id': me,
        'type': type,
        'content': meta,
        'media_url': path,
        'duration_ms': durationMs,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
