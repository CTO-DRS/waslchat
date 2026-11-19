import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_keys.dart';
import '../config.dart';
import 'app_lock_service.dart';

/// إعدادات Wasl Shield للمستخدم (جدول shield_settings — 041).
class ShieldSettings {
  const ShieldSettings({
    this.enabled = false,
    this.secureScreens = true,
    this.protectMedia = true,
    this.captureAlerts = true,
  });
  final bool enabled;
  final bool secureScreens;
  final bool protectMedia;
  final bool captureAlerts;

  ShieldSettings copyWith({bool? enabled, bool? secureScreens, bool? protectMedia, bool? captureAlerts}) =>
      ShieldSettings(
        enabled: enabled ?? this.enabled,
        secureScreens: secureScreens ?? this.secureScreens,
        protectMedia: protectMedia ?? this.protectMedia,
        captureAlerts: captureAlerts ?? this.captureAlerts,
      );

  factory ShieldSettings.fromRow(Map<String, dynamic>? r) => r == null
      ? const ShieldSettings()
      : ShieldSettings(
          enabled: r['enabled'] == true,
          secureScreens: r['secure_screens'] != false,
          protectMedia: r['protect_media'] != false,
          captureAlerts: r['capture_alerts'] != false,
        );
}

/// أنواع البلاغ كما يقبلها الخادم
const shieldCategories = <String, String>{
  'blackmail': 'ابتزاز بالصور أو الفيديو',
  'threat': 'تهديد',
  'harassment': 'تحرّش أو مضايقة',
  'impersonation': 'انتحال شخصية',
  'other': 'أخرى',
};

const shieldSeverity = <String, String>{
  'critical': 'حرجة',
  'high': 'عالية',
  'medium': 'متوسطة',
  'low': 'منخفضة',
};

const shieldStatus = <String, String>{
  'new': 'جديد',
  'reviewing': 'قيد المراجعة',
  'action_taken': 'اتُّخذ إجراء',
  'closed': 'مغلق',
};

/// Wasl Shield (1.10.0): الحماية ومكافحة الابتزاز.
///
/// ما يفعله فعلاً، دون مبالغة:
///  - أندرويد: FLAG_SECURE يمنع لقطات الشاشة وتسجيلها من داخل الجهاز للشاشات المحمية،
///    وتنبيه عند لقطة (أندرويد 14+) أو تسجيل (أندرويد 15+).
///  - iOS: اكتشاف التسجيل/البث وإخفاء المحتوى أثناءه، وتنبيه بعد لقطة الشاشة (لا يمكن منعها على iOS).
///  - الويب: لا منع للالتقاط؛ الحماية هناك صلاحيات الخادم فقط.
///  - لا شيء يمنع تصوير الشاشة بكاميرا أخرى، ولا يمكن حذف ما حُفظ على جهاز آخر.
class ShieldService {
  ShieldService._();

  static const _channel = MethodChannel('wasl/shield');
  static final settings = ValueNotifier<ShieldSettings>(const ShieldSettings());

  /// الشاشة تُسجَّل أو تُبث الآن (حيث يدعم النظام الاكتشاف)
  static final captured = ValueNotifier<bool>(false);
  static String? _myTag;
  static bool _inited = false;

  static bool get globalSecure => settings.value.enabled && settings.value.secureScreens;

  static Future<void> init() async {
    if (!_inited) {
      _inited = true;
      if (!kIsWeb) {
        _channel.setMethodCallHandler((call) async {
          switch (call.method) {
            case 'onScreenshot':
              _alert('📸 تم التقاط لقطة شاشة. تذكّر: لا ترسل ما لا تريد انتشاره.');
            case 'onRecording':
              captured.value = call.arguments == true;
              if (captured.value) _alert('🔴 الشاشة تُسجَّل الآن — أخفينا المحتوى الحساس.');
          }
          return null;
        });
      }
    }
    await load();
  }

  static void _alert(String msg) {
    if (!settings.value.enabled || !settings.value.captureAlerts) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  static Future<void> load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final r = await supabase.from('shield_settings').select().eq('user_id', uid).maybeSingle();
      settings.value = ShieldSettings.fromRow(r);
      ScreenshotService.globalSecure = globalSecure;
      if (globalSecure) await ScreenshotService.setSecure(true);
    } catch (_) {}
  }

  static Future<void> save(ShieldSettings s) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final before = settings.value;
    settings.value = s;
    ScreenshotService.globalSecure = globalSecure;
    await ScreenshotService.setSecure(globalSecure);
    try {
      await supabase.from('shield_settings').upsert({
        'user_id': uid,
        'enabled': s.enabled,
        'secure_screens': s.secureScreens,
        'protect_media': s.protectMedia,
        'capture_alerts': s.captureAlerts,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      settings.value = before;
      ScreenshotService.globalSecure = globalSecure;
      await ScreenshotService.setSecure(globalSecure);
      rethrow;
    }
  }

  /// نص العلامة المائية المرتبط بالمستلم (من يشاهد الآن)
  static Future<String> watermarkTag() async {
    if (_myTag != null) return _myTag!;
    final uid = supabase.auth.currentUser?.id;
    var tag = 'وصل شات';
    try {
      final p = await supabase.from('profiles').select('username').eq('id', uid!).maybeSingle();
      final u = p?['username'] as String?;
      if (u != null) tag = '@$u';
    } catch (_) {}
    _myTag = tag;
    return tag;
  }

  static Future<String> _sha256Hex(Uint8List b) async {
    final h = await Sha256().hash(b);
    return h.bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  // ===================== المستخدم =====================

  /// يرسل البلاغ ثم الأدلة. يعيد رقم البلاغ (ref).
  static Future<String> report({
    required String category,
    required String description,
    required bool urgent,
    String? targetUserId,
    String? conversationId,
    bool block = true,
    String? messagesJson,
    List<({Uint8List bytes, String mime, String ext, String? sourceId})> media = const [],
    void Function(int done, int total)? onProgress,
  }) async {
    final res = await supabase.rpc('shield_report', params: {
      'p_category': category,
      'p_description': description,
      'p_urgent': urgent,
      'p_target': targetUserId,
      'p_conversation': conversationId,
      'p_block': block,
    });
    final row = (res as List).first as Map;
    final caseId = row['case_id'] as String;
    final ref = row['ref'] as String;

    final total = (messagesJson != null ? 1 : 0) + media.length;
    var done = 0;
    Future<void> put(Uint8List bytes, String kind, String mime, String ext, String? src) async {
      final path = '$caseId/${DateTime.now().microsecondsSinceEpoch}.$ext';
      await supabase.storage.from('shield-evidence').uploadBinary(
            path, bytes, fileOptions: FileOptions(contentType: mime));
      await supabase.rpc('shield_add_evidence', params: {
        'p_case': caseId,
        'p_kind': kind,
        'p_path': path,
        'p_mime': mime,
        'p_size': bytes.length,
        'p_sha256': await _sha256Hex(bytes),
        'p_source': src,
      });
      done++;
      onProgress?.call(done, total);
    }

    if (messagesJson != null) {
      await put(Uint8List.fromList(utf8.encode(messagesJson)), 'messages', 'application/json', 'json', null);
    }
    for (final m in media) {
      try {
        await put(m.bytes, 'media', m.mime, m.ext, m.sourceId);
      } catch (_) {/* دليل واحد فشل لا يُسقط البلاغ */}
    }
    return ref;
  }

  static Future<List<Map<String, dynamic>>> myCases() async {
    final r = await supabase.rpc('shield_my_cases');
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ===================== المدير العام =====================

  static Future<List<Map<String, dynamic>>> adminCases({String? status}) async {
    final r = await supabase.rpc('shield_admin_cases', params: {'p_status': status});
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> adminCase(String id) async =>
      Map<String, dynamic>.from(await supabase.rpc('shield_admin_case', params: {'p_case': id}) as Map);

  /// يسجّل الفتح في سجل التدقيق ثم ينزّل الدليل (سياسة التخزين تشترط ذلك)
  static Future<Uint8List> adminOpenEvidence(String evidenceId) async {
    final path = await supabase.rpc('shield_admin_open_evidence', params: {'p_evidence': evidenceId}) as String;
    return supabase.storage.from('shield-evidence').download(path);
  }

  static Future<void> adminSetStatus(String id, String status, String reason) =>
      supabase.rpc('shield_admin_set_status', params: {'p_case': id, 'p_status': status, 'p_reason': reason});

  static Future<void> adminMessageReporter(String id, String text) =>
      supabase.rpc('shield_admin_message_reporter', params: {'p_case': id, 'p_text': text});

  static Future<List<Map<String, dynamic>>> adminThread(String id) async {
    final r = await supabase.rpc('shield_admin_thread', params: {'p_case': id});
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> adminSuspend(String id, bool suspend, String reason) =>
      supabase.rpc('shield_admin_suspend', params: {'p_case': id, 'p_suspend': suspend, 'p_reason': reason});

  static Future<void> adminRestrictMedia(String id, bool restrict, String reason) =>
      supabase.rpc('shield_admin_restrict_media', params: {'p_case': id, 'p_restrict': restrict, 'p_reason': reason});

  static Future<List<Map<String, dynamic>>> adminCaseMedia(String id) async {
    final r = await supabase.rpc('shield_admin_case_media', params: {'p_case': id});
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// إبطال روابط الوسائط بنقلها للحجر (دالة shield-admin بصلاحية الخدمة)
  static Future<int> adminQuarantine(String id, List<String> messageIds, String reason) async {
    final r = await supabase.functions.invoke('shield-admin', body: {
      'action': 'quarantine',
      'case_id': id,
      'message_ids': messageIds,
      'reason': reason,
    });
    final data = r.data is Map ? r.data as Map : {};
    if (data['error'] != null) throw Exception(data['error']);
    return (data['quarantined'] as num?)?.toInt() ?? 0;
  }

  static Future<List<Map<String, dynamic>>> adminAudit(String? caseId) async {
    final r = await supabase.rpc('shield_admin_audit', params: {'p_case': caseId});
    return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> adminVerifyAudit() async =>
      Map<String, dynamic>.from(await supabase.rpc('shield_admin_verify_audit') as Map);
}

/// يغطي المحتوى أثناء تسجيل الشاشة حين تكون الحماية مفعّلة (iOS، وأندرويد 15+ للتنبيه)
class ShieldCaptureCover extends StatelessWidget {
  const ShieldCaptureCover({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ShieldService.captured,
      builder: (context, cap, _) => ValueListenableBuilder<ShieldSettings>(
        valueListenable: ShieldService.settings,
        builder: (context, s, _) {
          final hide = cap && s.enabled && s.secureScreens;
          return Stack(children: [
            child,
            if (hide)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFF0B1020),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.shield_rounded, color: Color(0xFF2DD4BF), size: 56),
                      SizedBox(height: 12),
                      Text('المحتوى مخفي أثناء تسجيل الشاشة',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(color: Colors.white, fontSize: 16, decoration: TextDecoration.none)),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// علامة مائية مكررة باسم المشاهد فوق الوسائط المحمية
class ShieldWatermark extends StatelessWidget {
  const ShieldWatermark({super.key, required this.child, required this.tag});
  final Widget child;
  final String tag;

  @override
  Widget build(BuildContext context) {
    final stamp = '$tag · ${DateTime.now().toString().substring(0, 16)}';
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRect(
            child: LayoutBuilder(builder: (context, c) {
              final rows = (c.maxHeight / 70).ceil().clamp(1, 40);
              return OverflowBox(
                maxWidth: c.maxWidth * 2,
                maxHeight: c.maxHeight * 2,
                child: Transform.rotate(
                  angle: -0.5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < rows * 2; i++)
                        Text(List.filled(4, stamp).join('     '),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.22),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                shadows: const [Shadow(color: Colors.black38, blurRadius: 2)])),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    ]);
  }
}
