import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' show SecretKey;

import '../config.dart';
import 'e2e_service.dart';
import 'media_service.dart';

/// إعادة توجيه رسالة إلى محادثة أخرى من قائمة «المحادثات».
/// المحتوى يُفك على الجهاز ثم يُشفَّر من جديد بمفتاح المحادثة الهدف — الخادم لا يرى شيئاً.
class ForwardService {
  ForwardService._();

  /// مفتاح محادثة هدف (صف من my_chats) — fresh لأن إعادة التوجيه إرسال
  static Future<SecretKey?> _keyFor(Map<String, dynamic> chat) {
    final conv = chat['conversation_id'] as String;
    if (chat['is_group'] == true) return E2eService.groupKey(conv, fresh: true);
    final other = chat['other_id'] as String?;
    if (other == null) return Future.value(null);
    return E2eService.dmKey(conv, other);
  }

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
      final me = supabase.auth.currentUser?.id;
      if (me == null) return false;
      final key = await _keyFor(target);
      if (key == null) return false;
      if (type == 'text') {
        if (text == null || !E2eService.withinPlainLimit(text)) return false;
        final payload = await E2eService.encryptText(key, conv, text);
        await supabase.from('messages').insert({
          'conversation_id': conv,
          'sender_id': me,
          'type': 'text',
          'content': payload,
        });
        return true;
      }
      if (bytes == null) return false;
      final enc = await E2eService.encryptBytes(key, conv, bytes);
      final meta = (text != null && text.isNotEmpty)
          ? await E2eService.encryptText(key, conv, text)
          : '';
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
