import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/e2e_service.dart';
import '../services/media_service.dart';
import '../theme.dart';

/// صورة المجموعة المشفرة: تنزّل بايتات الملف من التخزين الخاص وتفكها
/// بمفتاح المجموعة (كل الإصدارات) وتعرضها. الفشل يعيد الأيقونة الافتراضية.
///
/// المسار في conversations.avatar_url هو مسار تخزين (لا رابط عام) —
/// الملف بايتات مشفرة AES-GCM بصيغة nonce+نص+mac مثل بقية وسائط chat-media.
class GroupAvatar extends StatefulWidget {
  const GroupAvatar({
    super.key,
    required this.conversationId,
    required this.path,
    required this.name,
    this.radius = 26,
    this.color = WaslColors.teal,
    this.icon = Icons.groups_2,
  });

  final String conversationId;

  /// مسار الملف المشفر في التخزين (فارغ أو null ← الأيقونة الافتراضية)
  final String? path;
  final String name;
  final double radius;
  final Color color;
  final IconData? icon;

  /// ذاكرة بايتات مفكوكة: المسار ← البايتات (تُشارك بين كل المواضع في الجلسة)
  static final Map<String, Uint8List> _bytesCache = {};
  static final Set<String> _loading = {};

  static void evict(String path) => _bytesCache.remove(path);

  @override
  State<GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = GroupAvatar._bytesCache[widget.path ?? ''];
    if (_bytes == null && (widget.path ?? '').isNotEmpty) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant GroupAvatar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _bytes = GroupAvatar._bytesCache[widget.path ?? ''];
      if (_bytes == null && (widget.path ?? '').isNotEmpty) _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    if (path == null || path.isEmpty) return;
    if (!GroupAvatar._loading.add(path)) return;
    try {
      final raw = await MediaService.download(path);
      final plain = await E2eService.decryptGroupBytes(widget.conversationId, raw);
      if (plain != null) GroupAvatar._bytesCache[path] = plain;
      if (mounted && path == widget.path) setState(() => _bytes = plain);
    } catch (_) {
      // فشل التنزيل/فك التشفير: تبقى الأيقونة الافتراضية (بلا تخزين مؤقت للفشل)
    } finally {
      GroupAvatar._loading.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.color,
      foregroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
      child: widget.icon != null
          ? Icon(widget.icon, color: Colors.white, size: widget.radius)
          : Text(widget.name.isNotEmpty ? widget.name.characters.first : '?',
              style: TextStyle(color: Colors.white, fontSize: widget.radius * 0.75)),
    );
  }
}
