import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// يُستخدم هنا لفتح إعدادات التطبيق فقط عند رفض الإذن نهائياً —
// openAppSettings دالة عامة تفتح صفحة إعدادات التطبيق (نفس نمط contact_picker_sheet)
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../config.dart';
import '../services/discovery_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// اكتشاف الأصدقاء من جهات الاتصال (بند المرحلة 1 — 0.4.7).
///
/// شاشة صادقة بالتصميم:
/// - المطابقة تُجزَّأ على جهازك (SHA-256) ولا تُرفع أرقام خام، ولا تُخزَّن
///   التجزئات على الخادم بعد لحظة المطابقة.
/// - بلا تسجيل رقمك لن يظهر حسابك لأحد عبر الاكتشاف — الافتراضي خفاء.
/// - إزالة رقمك في أي لحظة = خفاء فوري.
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _phoneCtrl = TextEditingController();
  String? _myNumber; // نسخة محلية للعرض فقط
  bool _declaredOnServer = false;
  bool _busyStatus = true;
  bool _searching = false;
  String? _error;
  bool _denied = false;
  List<Map<String, dynamic>> _results = [];
  int _scanned = 0;
  int _unique = 0;
  Set<String> _blocked = {};

  @override
  void initState() {
    super.initState();
    _loadStatus();
    _loadBlocked();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    setState(() => _busyStatus = true);
    String? num;
    bool declared = false;
    try {
      num = await DiscoveryService.myDeclaredNumber();
      declared = await DiscoveryService.isDeclaredOnServer();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _myNumber = num;
      _declaredOnServer = declared;
      _busyStatus = false;
    });
  }

  /// من حظرتهم أنا لا يظهروا في النتائج (الخادم يستبعدهم أيضاً —
  /// هذا حاجز ثانٍ كما في شاشة المحادثة الجديدة)
  Future<void> _loadBlocked() async {
    try {
      final ids = await supabase.rpc('my_blocked_ids');
      if (mounted) setState(() => _blocked = Set<String>.from(ids as List));
    } catch (_) {}
  }

  Future<void> _declare() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _busyStatus = true);
    try {
      await DiscoveryService.declareMyNumber(raw);
      _phoneCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم تسجيل رقمك (تجزئة فقط على الخادم) — من لديه رقمك في جهات اتصاله سيجدك عند المطابقة')));
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('رقم غير صالح — اكتبه بمفتاح دولي مثل ‎+9665XXXXXXXX')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر تسجيل الرقم')));
      }
    }
    await _loadStatus();
  }

  Future<void> _clear() async {
    setState(() => _busyStatus = true);
    try {
      await DiscoveryService.clearMyNumber();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إزالة رقمك — لن يجدك أحد عبر الاكتشاف من الآن')));
    await _loadStatus();
  }

  Future<void> _runDiscovery() async {
    setState(() {
      _searching = true;
      _error = null;
      _denied = false;
      _results = [];
    });
    try {
      final r = await DiscoveryService.discoverFromDeviceContacts(excludeIds: _blocked);
      if (!mounted) return;
      setState(() {
        _results = r.matches;
        _scanned = r.scannedNumbers;
        _unique = r.uniqueHashes;
        _searching = false;
      });
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() {
        _denied = e.message == 'permission_denied';
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذّرت المطابقة — تأكد من اتصالك وحاول مجدداً';
        _searching = false;
      });
    }
  }

  Future<void> _open(Map<String, dynamic> user) async {
    try {
      final convId =
          await supabase.rpc('create_direct_chat', params: {'other_id': user['id']});
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId as String,
            title: (user['display_name'] ?? user['username']) as String,
            otherId: user['id'] as String,
            encrypted: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().contains('blocked')
              ? 'لا يمكن بدء المحادثة: هذا المستخدم حظرك'
              : 'تعذّر بدء المحادثة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    return Scaffold(
      backgroundColor: wasl.bg,
      appBar: AppBar(title: const Text('اكتشاف الأصدقاء')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _privacyCard(wasl),
          const SizedBox(height: 16),
          _myNumberCard(wasl),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: WaslColors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: _searching ? null : _runDiscovery,
            icon: _searching
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.person_search),
            label: Text(_searching ? 'جارٍ المطابقة…' : 'مطابقة جهات اتصالي'),
          ),
          if (_denied) ...[
            const SizedBox(height: 12),
            Card(
              color: wasl.surface,
              child: ListTile(
                leading: Icon(Icons.lock_outline, color: wasl.accent),
                title: const Text('إذن جهات الاتصال مرفوض'),
                subtitle: const Text(
                    'المطابقة تحتاج إذن القراءة — يُستخدم محلياً على جهازك فقط',
                    style: TextStyle(fontSize: 12)),
                trailing: TextButton(
                    onPressed: Geolocator.openAppSettings,
                    child: const Text('الإعدادات')),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: wasl.textSecondary, fontSize: 13)),
          ],
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('من جهات اتصالك على وصل (${_results.length})',
                style: TextStyle(
                    color: wasl.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'مسحنا $_scanned رقماً ($_unique تجزئة فريدة) — قورنت لحظياً ثم هُملت بلا تخزين',
              style: TextStyle(color: wasl.textFaint, fontSize: 11),
            ),
            const SizedBox(height: 8),
            for (final u in _results)
              Card(
                color: wasl.surface,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: UserAvatar(
                      name: (u['display_name'] ?? u['username']) as String,
                      url: u['avatar_url'] as String?,
                      color: WaslColors.teal,
                      radius: 22),
                  title: Text((u['display_name'] ?? u['username']) as String),
                  subtitle: Text('@${u['username']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Icon(Icons.chat_bubble_outline,
                      color: wasl.accent, size: 20),
                  onTap: () => _open(u),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _privacyCard(WaslPalette wasl) {
    return Card(
      color: wasl.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.shield_outlined, color: wasl.accent, size: 20),
              const SizedBox(width: 8),
              Text('كيف تعمل المطابقة؟',
                  style: TextStyle(
                      color: wasl.textPrimary, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(
              '• أرقام جهات اتصالك تُجزَّأ على جهازك (SHA-256) ولا يُرفع رقم خام أبداً.\n'
              '• التجزئات تُرسل لحظة المطابقة فقط للمقارنة ثم تُهمل — لا تخزين لها على الخادم.\n'
              '• بلا تسجيل رقمك لن يظهر حسابك لمن لديه رقمك — الافتراضي الخفاء.\n'
              '• المطابقة تستبعد المحظورين من الطرفين تلقائياً.',
              style: TextStyle(color: wasl.textSecondary, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _myNumberCard(WaslPalette wasl) {
    return Card(
      color: wasl.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                _declaredOnServer ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: _declaredOnServer ? WaslColors.teal : wasl.textFaint,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _busyStatus
                      ? 'جارٍ التحقق…'
                      : _declaredOnServer
                          ? 'رقمك مسجّل: ${_myNumber ?? 'مسجّل على الخادم'} — من لديه رقمك سيجدك'
                          : 'رقمك غير مسجّل — لا يمكن لأحد اكتشافك (خفاء تام)',
                  style: TextStyle(color: wasl.textPrimary, fontSize: 13.5),
                ),
              ),
            ]),
            if (!_declaredOnServer) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]'))],
                decoration: InputDecoration(
                  hintText: '‎+9665XXXXXXXX',
                  prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: wasl.glass,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: wasl.border)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: wasl.border)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busyStatus ? null : _declare,
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('سجّل رقمي (تجزئة فقط)'),
                ),
              ),
            ] else ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busyStatus ? null : _clear,
                  icon: const Icon(Icons.visibility_off, size: 18),
                  label: const Text('إزالة رقمي (خفاء فوري)'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
