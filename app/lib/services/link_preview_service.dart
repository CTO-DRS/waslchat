/// معاينة الروابط (المرحلة 8 ب — 0.21.0)
///
/// كيف تعمل، بالصدق الكامل:
/// 1) كشف أول رابط عام (http/https حصراً) في نص الرسالة المفكوك محلياً.
/// 2) الجلب عبر دالة الخادم `link-preview` حصراً: الرابط يمر عبر خادم وصل
///    **عند توليد المعاينة فقط** — الدالة تجلب الصفحة العامة وتستخرج
///    العنوان والوصف والصورة المصغرة، **ولا تخزّن شيئاً على الخادم إطلاقاً**.
///    (الإفصاح الحرفي نفسه معروض في الإعدادات بجوار مفتاح الميزة.)
/// 3) النتيجة تُخزَّن **على جهازك حصراً** 24 ساعة ثم تُحذف — التنظيف يجري
///    تلقائياً عند كل قراءة وكتابة.
/// 4) مفتاح تعطيل عام في الإعدادات: التعطيل يوقف كل الطلبات فوراً ويمسح الكاش.
/// 5) أي فشل (شبكة/رابط خاص/صفحة بلا وسوم) يهبط للسلوك السابق: بلا بطاقة.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config.dart';

class LinkPreviewData {
  const LinkPreviewData({
    required this.url,
    required this.host,
    this.title,
    this.description,
    this.image,
  });

  final String url;
  final String host;
  final String? title;
  final String? description;
  final String? image;

  bool get isEmpty => (title ?? '').isEmpty && (image ?? '').isEmpty;

  Map<String, dynamic> toJson() => {
        'url': url,
        'host': host,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (image != null) 'image': image,
      };

  static LinkPreviewData? fromJson(Map<String, dynamic> j) {
    final url = j['url'] as String?;
    if (url == null || url.isEmpty) return null;
    return LinkPreviewData(
      url: url,
      host: j['host'] as String? ?? '',
      title: j['title'] as String?,
      description: j['description'] as String?,
      image: j['image'] as String?,
    );
  }
}

class LinkPreviewService {
  LinkPreviewService._();

  static const _cacheKey = 'link_previews_cache_v1';
  static const _enabledKey = 'link_preview_enabled';
  static const _ttl = Duration(hours: 24);

  /// مفتاح الميزة العام (الإعدادات): الافتراضي مفعّل
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static const _storage = FlutterSecureStorage();
  static final Map<String, LinkPreviewData> _mem = {};
  static final Set<String> _busy = {};

  // ---------- كشف الروابط ----------

  static final _urlRe = RegExp(
      r'https?://[^\s<>"\u0600-\u06FF]{6,}',
      caseSensitive: false);

  /// أول رابط عام في النص (null إن لم يوجد) — الروابط تُقص عند حرف مسافة
  /// أو علامة ترقيم إغلاق شائعة حتى لا تلتهم نهاية الجملة.
  static String? extractFirstUrl(String? text) {
    if (text == null) return null;
    final m = _urlRe.firstMatch(text);
    if (m == null) return null;
    var u = m.group(0)!;
    while (u.isNotEmpty && '.,;:!?)]}»«"'.contains(u[u.length - 1])) {
      u = u.substring(0, u.length - 1);
    }
    return u.length >= 9 ? u : null;
  }

  /// اسم النطاق لعرضه بالبطاقة (يعاد فارغاً للروابط الفاسدة)
  static String hostOf(String url) {
    try {
      final u = Uri.parse(url);
      if (u.scheme != 'http' && u.scheme != 'https') return '';
      return u.host;
    } catch (_) {
      return '';
    }
  }

  // ---------- فك استجابة الدالة (نقي — مُختبَر) ----------

  /// يفك استجابة دالة `link-preview` إلى بيانات بطاقة، أو null للرفض.
  /// الرابط المعاد يجب أن يطابق المطلوب حرفياً (لا يثق العميل بأي توجيه).
  static LinkPreviewData? parseResponse(Object? data, String requestedUrl) {
    if (data is! Map) return null;
    if (data['error'] != null) return null;
    final url = data['url'] as String?;
    if (url == null || url != requestedUrl) return null;
    String? s(Object? v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final d = LinkPreviewData(
      url: url,
      host: s(data['host']) ?? hostOf(url),
      title: s(data['title']),
      description: s(data['description']),
      image: s(data['image']),
    );
    return d.isEmpty ? null : d;
  }

  // ---------- الكاش (نقي — مُختبَر) ----------

  /// مفتاح الكاش: الرابط كما هو مع تطبيع طفيف — سلاش الصفحات الداخلية
  /// الأخير يُقص، أما الجذر (المسار فارغ أو «/») فيبقى كما هو.
  static String cacheKey(String url) {
    if (!url.endsWith('/') || url.length <= 8) return url;
    final u = Uri.tryParse(url);
    if (u == null) return url;
    final path = u.path;
    if (path.isEmpty || path == '/') return url; // الجذر كما هو
    return url.substring(0, url.length - 1);
  }

  /// تنظيف الكاش من المنتهية قبل 24 ساعة — يعيد الخريطة الصالحة حصراً.
  /// صيغة الخريطة الخام: url -> {data: {...}, exp: epochMilli}
  static Map<String, Map<String, dynamic>> pruneCache(
      Map<String, dynamic> raw, DateTime now) {
    final out = <String, Map<String, dynamic>>{};
    raw.forEach((k, v) {
      if (v is! Map) return;
      final exp = (v['exp'] as num?)?.toInt();
      if (exp == null || exp <= now.millisecondsSinceEpoch) return;
      out[k] = Map<String, dynamic>.from(v);
    });
    return out;
  }

  // ---------- التخزين المحلي ----------

  static Future<Map<String, dynamic>> _readCache() async {
    try {
      final v = await _storage.read(key: _cacheKey);
      if (v == null || v.isEmpty) return {};
      final j = jsonDecode(v);
      return j is Map ? Map<String, dynamic>.from(j) : {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeCache(Map<String, dynamic> raw) async {
    try {
      var out = raw;
      if (raw.length > 60) {
        out = Map<String, dynamic>.of(raw);
        out.remove(out.keys.first); // الأقدم أول من يسقط عند التجاوز
      }
      await _storage.write(key: _cacheKey, value: jsonEncode(out));
    } catch (_) {}
  }

  static LinkPreviewData? _fromCacheEntry(Map<String, dynamic> entry) {
    final d = entry['data'];
    if (d is! Map) return null;
    return LinkPreviewData.fromJson(Map<String, dynamic>.from(d));
  }

  // ---------- الواجهة العامة ----------

  /// يحمّل مفتاح التعطيل والكاش الصالح إلى الذاكرة (يُستدعى عند بدء التطبيق)
  static Future<void> init() async {
    try {
      final v = await _storage.read(key: _enabledKey);
      enabled.value = v != 'off';
      final raw = await _readCache();
      final ok = pruneCache(raw, DateTime.now());
      _mem.clear();
      ok.forEach((k, e) {
        final d = _fromCacheEntry(e);
        if (d != null) _mem[k] = d;
      });
      // حذف المنتهية فعلياً من التخزين
      if (ok.length != raw.length) await _writeCache(ok);
    } catch (_) {}
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _enabledKey, value: v ? 'on' : 'off');
    } catch (_) {}
    if (!v) await clearCache();
  }

  /// مسح الكاش المحلي كاملاً (زر في الإعدادات أو عند التعطيل)
  static Future<void> clearCache() async {
    _mem.clear();
    try {
      await _storage.delete(key: _cacheKey);
    } catch (_) {}
  }

  /// عدد معاينات مخزنة محلياً (لعرضها في الإعدادات)
  static int get cachedCount => _mem.length;

  /// يجلب المعاينة: الكاش أولاً (فوري)، وإلا الدالة الخادمية مرة واحدة.
  /// أي فشل يعيد null — بلا بطاقة، وبلا سلوك غريب.
  static Future<LinkPreviewData?> get(String url) async {
    if (!enabled.value) return null;
    final key = cacheKey(url);
    final hit = _mem[key];
    if (hit != null) return hit;
    if (!_busy.add(key)) return null; // طلب واحد لكل رابط في اللحظة
    try {
      final res = await supabase.functions.invoke('link-preview', body: {'url': url});
      final d = parseResponse(res.data, url);
      if (d == null) return null;
      _mem[key] = d;
      await _persist(key, d);
      return d;
    } catch (_) {
      return null;
    } finally {
      _busy.remove(key);
    }
  }

  static Future<void> _persist(String key, LinkPreviewData d) async {
    final raw = await _readCache();
    final ok = pruneCache(raw, DateTime.now());
    ok[key] = {
      'data': d.toJson(),
      'exp': DateTime.now().add(_ttl).millisecondsSinceEpoch,
    };
    // سقف كاش 60 رابطاً: الأقدم أول من يسقط (لا يوجد ترتيب خريطة داكوتا —
    // نحذف عشوائياً أول مفتاح زائد، التأثير عملياً معدوم)
    while (ok.length > 60) {
      ok.remove(ok.keys.first);
    }
    await _writeCache(ok);
  }
}
