/// طابور الإرسال بلا شبكة — الرسائل offline-first (المرحلة 13 أ — 1.1.0).
///
/// رسالة فشل إرسالها لغياب الشبكة لا تضيع ولا تُعاد كتابتها: تُحفظ على
/// جهازك بحالة «بانتظار الشبكة» صادقة تُعرض على الشاشة، وتُعاد محاولة
/// إرسالها تلقائياً **بالترتيب نفسه** عند عودة الاتصال (عند فتح قناة
/// Realtime، وعند بدء التطبيق، وعند كل نبضة دورية) — فلا تكرار ولا فساد
/// ترتيب ولا استثناء هارب.
///
/// التصميم الصادق:
/// - ما يُخزَّن محلياً هو **النص المشفر بالفعل** (كما يراه الخادم أصلاً)
///   وبايتات الوسائط المشفرة في ملف مؤقت — لا نص واضح ولا مفتاح جوهر
///   يُكتب للقراءة على الجهاز أبداً.
/// - طابور مرتّب صارم: الفشل يوقف الطابور عند أول عنصر (لن تُرسل رسالة
///   لاحقة قبل سابقتها)، والنجاح يحذف العنصر والملف المؤقت معاً —
///   الرسالة تُحذف من الطابور بعد تأكيد الخادم حصراً، فلا تكرار.
/// - الأخطاء التي لا علاقة لها بالشبكة (حظر بينكما، كتم مشرف، سياسة
///   إرسال) لا تدخل الطابور إطلاقاً — إعادة محاولتها إساءة.
/// - سقف الطابور 50 رسالة ومحاولات تلقائية حتى 8 لكل رسالة: ما فوقه
///   يتوقف عن المحاولة الآلية ويبقى محفوظاً معروضاً — لا ضمير يتكتم.
/// - بلا ترحيل خادمي وبلا صلاحية جديدة: المخزن الآمن القائم وملفات
///   مؤقتة على جهازك حصراً.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'e2e_service.dart';
import 'media_service.dart';

// ==================== المنطق النقي (قابل للاختبار) ====================

/// رسالة بانتظار الشبكة — كل حقولها كما تُرسل بالضبط عند عودة الاتصال
class PendingSend {
  const PendingSend({
    required this.id,
    required this.conversationId,
    required this.kind, // 'text' | 'media'
    required this.type, // text | image | video | file | voice
    required this.content, // النص/الميتا المشفرة كما تُدرج في messages
    required this.createdAtMs,
    this.mediaFile, // ملف مؤقت بالبايتات المشفرة (الوسائط)
    this.uploadPath, // المسار على التخزين إن رُفع قبل أن تنقطع الشبكة
    this.ext,
    this.contentType,
    this.durationMs,
    this.viewOnce = false,
    this.groupId,
    this.replyTo,
    this.rememberKey, // mk JSON لوسائط الخاص — يُخزَّن برسالتك بعد النجاح
    this.attempts = 0,
  });

  final String id;
  final String conversationId;
  final String kind;
  final String type;
  final String content;
  final int createdAtMs;
  final String? mediaFile;
  final String? uploadPath;
  final String? ext;
  final String? contentType;
  final int? durationMs;
  final bool viewOnce;
  final String? groupId;
  final String? replyTo;
  final String? rememberKey;
  final int attempts;

  PendingSend withAttempt() => PendingSend(
        id: id,
        conversationId: conversationId,
        kind: kind,
        type: type,
        content: content,
        createdAtMs: createdAtMs,
        mediaFile: mediaFile,
        uploadPath: uploadPath,
        ext: ext,
        contentType: contentType,
        durationMs: durationMs,
        viewOnce: viewOnce,
        groupId: groupId,
        replyTo: replyTo,
        rememberKey: rememberKey,
        attempts: attempts + 1,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'kind': kind,
        'type': type,
        'content': content,
        'created_at_ms': createdAtMs,
        if (mediaFile != null) 'media_file': mediaFile,
        if (uploadPath != null) 'upload_path': uploadPath,
        if (ext != null) 'ext': ext,
        if (contentType != null) 'content_type': contentType,
        if (durationMs != null) 'duration_ms': durationMs,
        if (viewOnce) 'view_once': true,
        if (groupId != null) 'group_id': groupId,
        if (replyTo != null) 'reply_to': replyTo,
        if (rememberKey != null) 'remember_key': rememberKey,
        'attempts': attempts,
      };

  /// تحليل دفاعي: ناقص جوهري أو نوع غريب → null تُسقط بلا انهيار
  static PendingSend? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final conv = raw['conversation_id'];
    final kind = raw['kind'];
    final type = raw['type'];
    final content = raw['content'];
    if (id is! String ||
        id.isEmpty ||
        conv is! String ||
        conv.isEmpty ||
        content is! String) {
      return null;
    }
    if ((kind != 'text' && kind != 'media') || type is! String || type.isEmpty) {
      return null;
    }
    return PendingSend(
      id: id,
      conversationId: conv,
      kind: kind,
      type: type,
      content: content,
      createdAtMs: raw['created_at_ms'] is int
          ? raw['created_at_ms'] as int
          : DateTime.now().millisecondsSinceEpoch,
      mediaFile: raw['media_file'] is String && (raw['media_file'] as String).isNotEmpty
          ? raw['media_file'] as String
          : null,
      uploadPath:
          raw['upload_path'] is String && (raw['upload_path'] as String).isNotEmpty
              ? raw['upload_path'] as String
              : null,
      ext: raw['ext'] is String ? raw['ext'] as String : null,
      contentType:
          raw['content_type'] is String ? raw['content_type'] as String : null,
      durationMs: raw['duration_ms'] is int ? raw['duration_ms'] as int : null,
      viewOnce: raw['view_once'] == true,
      groupId: raw['group_id'] is String ? raw['group_id'] as String : null,
      replyTo: raw['reply_to'] is String ? raw['reply_to'] as String : null,
      rememberKey:
          raw['remember_key'] is String ? raw['remember_key'] as String : null,
      attempts: raw['attempts'] is int ? raw['attempts'] as int : 0,
    );
  }
}

/// نواة الطابور النقية: ترتيب FIFO صارم وتفريد بالمعرّف وسقوف مثبتة
class OfflineQueueCore {
  static const maxPending = 50;
  static const maxAttempts = 8;

  final List<PendingSend> items = [];

  /// إدخال بنهاية الطابور — مكرر بالمعرّف مرفوض، وفوق السقف مرفوض
  bool enqueue(PendingSend p) {
    if (items.any((x) => x.id == p.id)) return false;
    if (items.length >= maxPending) return false;
    items.add(p);
    return true;
  }

  bool remove(String id) {
    final before = items.length;
    items.removeWhere((x) => x.id == id);
    return items.length < before;
  }

  /// هل تستحق هذه الرسالة محاولة آلية أخرى؟ (ما بعد السقف يبقى محفوظاً
  /// معروضاً — المحاولة الآلية تتوقف ولا يُحذف شيء بلا إخطار)
  static bool shouldAutoRetry(int attempts) => attempts < maxAttempts;

  /// أقدم رسالة قابلة لإعادة المحاولة الآلية — بلا إزالة (الإزالة بعد
  /// تأكيد النجاح حصراً كي لا تضيع رسالة لو مات التطبيق بين الخطوتين)
  PendingSend? next() {
    for (final x in items) {
      if (shouldAutoRetry(x.attempts)) return x;
    }
    return null;
  }

  String encode() => jsonEncode([for (final x in items) x.toJson()]);

  /// تحليل دفاعي: الغريب يُسقط والصالح يبقى بترتيبه الأصلي
  static OfflineQueueCore decode(String? raw) {
    final q = OfflineQueueCore();
    if (raw == null || raw.isEmpty) return q;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return q;
      for (final x in list) {
        final p = PendingSend.fromJson(x);
        if (p != null) q.enqueue(p);
      }
    } catch (_) {}
    return q;
  }
}

// ==================== طبقة الخزن والجسر ====================

/// مُرسِل طابور: يعيد true عند تأكيد الخادم — false عند أي فشل (يتوقف
/// الطابور عنده فوراً حفظاً للترتيب)
typedef QueueSender = Future<bool> Function(PendingSend p);

class OfflineQueueService {
  OfflineQueueService._();

  static const _key = 'offline_queue_v1';
  static const _storage = FlutterSecureStorage();

  static OfflineQueueCore _core = OfflineQueueCore();
  static bool _ready = false;
  static Timer? _tick;
  static bool _flushing = false;

  /// حالة حية للواجهة: عدد المحفوظات وهل يجري إرسالها الآن
  static final ValueNotifier<int> count = ValueNotifier<int>(0);
  static final ValueNotifier<bool> draining = ValueNotifier<bool>(false);

  /// المرسل الفعلي — يُضبط في start (المسار الواقعي: insert/upload)،
  /// ويمكن استبداله للاختبار
  static QueueSender sender = _defaultSender;

  /// تحميل ما نجت من قتل التطبيق، وتنظيف الوسائط بلا ملف، وربط نبض الشبكة
  static Future<void> start() async {
    if (_ready) return;
    try {
      final raw = await _storage.read(key: _key);
      _core = OfflineQueueCore.decode(raw);
    } catch (_) {
      _core = OfflineQueueCore();
    }
    // وسائط ملفها المؤقت ضاع (إعادة تشغيل الجهاز تمسح الملفات المؤقتة)
    // لا يمكن إرسالها — تُسقط بصدق بدل ادعاء بأنها بانتظار الإرسال
    for (final p in List<PendingSend>.from(_core.items)) {
      if (p.mediaFile != null && !File(p.mediaFile!).existsSync()) {
        _core.remove(p.id);
      }
    }
    _ready = true;
    _notify();

    // نبضة عودة الشبكة: فتح قناة Realtime = اتصال عاد — جرّب الإرسال
    try {
      supabase.realtime.onOpen(() => flush('socket-open'));
    } catch (_) {}
    // نبضة دورية شبكة أمان لمن فوّت حدث الفتح
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_core.items.isNotEmpty) flush('tick');
    });
    // من مت بثقاته معلقة والاتصال عاد أثناء الإغلاق — جرب فوراً
    flush('start');
  }

  static void stop() {
    _tick?.cancel();
    _tick = null;
  }

  static void _notify() => count.value = _core.items.length;

  /// عدد المحفوظات لمحادثة بعينها (شريط المحادثة)
  static int queuedIn(String conversationId) => _core
      .items
      .where((x) => x.conversationId == conversationId)
      .length;

  /// إدخال رسالة نصية (payload مشفر بالفعل قبل الطابور) — false عند السقف
  static Future<bool> enqueueText({
    required String conversationId,
    required String content,
    String? replyTo,
  }) async {
    final ok = _core.enqueue(PendingSend(
      id: _newId(),
      conversationId: conversationId,
      kind: 'text',
      type: 'text',
      content: content,
      replyTo: replyTo,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (ok) await _persist();
    return ok;
  }

  /// إدخال رسالة وسيط: بايتات مشفرة تُكتب ملفاً مؤقتاً على جهازك
  static Future<bool> enqueueMedia({
    required String conversationId,
    required Uint8List bytes,
    required String type,
    required String content,
    required String ext,
    required String contentType,
    String? uploadPath,
    int? durationMs,
    bool viewOnce = false,
    String? groupId,
    String? replyTo,
    String? rememberKey,
  }) async {
    final id = _newId();
    String? filePath;
    if (uploadPath == null) {
      // البايتات المشفرة حصراً — لا شيء واضح يُكتب
      try {
        final dir = await getTemporaryDirectory();
        final dir0 = Directory('${dir.path}/offline_media');
        if (!dir0.existsSync()) dir0.createSync(recursive: true);
        filePath = '${dir0.path}/$id.bin';
        File(filePath).writeAsBytesSync(bytes, flush: true);
      } catch (e) {
        debugPrint('offline media save failed: $e');
        return false; // بلا ملف لا وسيط — لا ادعاء حفظ
      }
    }
    final ok = _core.enqueue(PendingSend(
      id: id,
      conversationId: conversationId,
      kind: 'media',
      type: type,
      content: content,
      mediaFile: filePath,
      uploadPath: uploadPath,
      ext: ext,
      contentType: contentType,
      durationMs: durationMs,
      viewOnce: viewOnce,
      groupId: groupId,
      replyTo: replyTo,
      rememberKey: rememberKey,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    if (ok) await _persist();
    return ok;
  }

  /// إرسال الطابور بالترتيب حتى أول فشل — السبب للتوثيق فقط
  static Future<void> flush(String reason) async {
    if (!_ready || _flushing) return;
    if (_core.items.isEmpty) return;
    _flushing = true;
    draining.value = true;
    try {
      while (true) {
        final p = _core.next();
        if (p == null) break;
        final ok = await sender(p);
        if (!ok) {
          // الترتيب الصارم: الرسالة الفاشلة تبقى موضعها الأول مع عدّ
          // محاولتها — فلا تُرسل رسالة لاحقة قبلها، ولا تُكرر ولا تُحذف
          final idx = _core.items.indexOf(p);
          if (idx >= 0) _core.items[idx] = p.withAttempt();
          break;
        }
        _core.remove(p.id);
        if (p.mediaFile != null) {
          try {
            File(p.mediaFile!).deleteSync();
          } catch (_) {}
        }
        await _persist();
        _notify();
      }
    } catch (e) {
      debugPrint('offline flush error ($reason): $e');
    } finally {
      _flushing = false;
      draining.value = false;
      _notify();
    }
  }

  static Future<void> _persist() async {
    try {
      await _storage.write(key: _key, value: _core.encode());
    } catch (_) {}
  }

  static String _newId() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(0x1000000).toRadixString(16))
        .join();
  }

  /// المرسل الواقعي: نص = إدراج مباشر — وسيط = رفع (أو مسار محفوظ سلفاً)
  /// ثم إدراج ثم تخزين mk رسائلك — أي استثناء يعني false بلا انهيار
  static Future<bool> _defaultSender(PendingSend p) async {
    try {
      final me = supabase.auth.currentUser?.id;
      if (me == null) return false;
      if (p.kind == 'text') {
        await supabase.from('messages').insert({
          'conversation_id': p.conversationId,
          'sender_id': me,
          'type': 'text',
          'content': p.content,
          if (p.replyTo != null) 'reply_to': p.replyTo,
        });
        return true;
      }
      var path = p.uploadPath;
      if (path == null) {
        final bytes = File(p.mediaFile!).readAsBytesSync();
        path = await MediaService.upload(
          conversationId: p.conversationId,
          bytes: bytes,
          ext: p.ext ?? 'bin',
          contentType: p.contentType ?? 'application/octet-stream',
        );
      }
      await supabase.from('messages').insert({
        'conversation_id': p.conversationId,
        'sender_id': me,
        'type': p.type,
        'content': p.content,
        'media_url': path,
        'duration_ms': p.durationMs,
        if (p.viewOnce) 'view_once': true,
        if (p.groupId != null) 'media_group_id': p.groupId,
        if (p.replyTo != null) 'reply_to': p.replyTo,
      });
      if (p.rememberKey != null) {
        await E2eService.rememberMediaKey(
            p.conversationId, null, p.rememberKey!);
      }
      return true;
    } catch (e) {
      debugPrint('offline send failed: $e');
      return false;
    }
  }
}
