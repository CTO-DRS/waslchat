import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:material_ui/material_ui.dart';

import '../services/shield_service.dart';
import '../theme.dart';
import '../widgets/wasl_sheet.dart';

/// Wasl Shield — إعدادات الحماية وبلاغاتي (1.10.0)
class ShieldScreen extends StatefulWidget {
  const ShieldScreen({super.key});

  @override
  State<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends State<ShieldScreen> {
  List<Map<String, dynamic>> _cases = [];

  @override
  void initState() {
    super.initState();
    ShieldService.load();
    _loadCases();
  }

  Future<void> _loadCases() async {
    try {
      final c = await ShieldService.myCases();
      if (mounted) setState(() => _cases = c);
    } catch (_) {}
  }

  Future<void> _set(ShieldSettings s) async {
    try {
      await ShieldService.save(s);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تعذّر الحفظ، تحقق من الاتصال')));
      }
    }
  }

  String get _platformNote {
    if (kIsWeb) {
      return 'على المتصفح لا يمكن منع لقطات الشاشة؛ الحماية هنا عبر صلاحيات الخادم والروابط المؤقتة.';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'على iOS: نخفي المحتوى أثناء تسجيل الشاشة وننبّهك بعد اللقطات (iOS لا يسمح بمنعها).';
    }
    return 'على أندرويد: نمنع لقطات الشاشة وتسجيلها داخل الجهاز للشاشات المحمية، وننبّهك عند المحاولة في الأنظمة الحديثة.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          ShaderMask(
            shaderCallback: (r) => WaslColors.gradient.createShader(r),
            child: const Icon(Icons.shield_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
          const Text('Wasl Shield', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
      ),
      body: ValueListenableBuilder<ShieldSettings>(
        valueListenable: ShieldService.settings,
        builder: (context, s, _) => RefreshIndicator(
          onRefresh: _loadCases,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    WaslColors.indigo.withValues(alpha: 0.30),
                    WaslColors.teal.withValues(alpha: 0.18),
                  ]),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('حمايتك من الابتزاز والتهديد',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('بلاغ سرّي يصل للمدير مباشرة، وحماية لصورك ومقاطعك داخل وصل شات.',
                      style: TextStyle(color: context.textSecondary, height: 1.5)),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.enabled,
                    onChanged: (v) => _set(s.copyWith(enabled: v)),
                    title: Text(s.enabled ? 'الحماية مفعّلة' : 'تفعيل الحماية',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ]),
              ),
              const SheetSectionLabel('خيارات الحماية'),
              Opacity(
                opacity: s.enabled ? 1 : 0.5,
                child: AbsorbPointer(
                  absorbing: !s.enabled,
                  child: GlassGroup([
                    SwitchListTile(
                      value: s.secureScreens,
                      onChanged: (v) => _set(s.copyWith(secureScreens: v)),
                      secondary: TintIcon(Icon(Icons.screenshot_monitor_rounded, color: WaslColors.indigo)),
                      title: const Text('حماية الشاشات', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('منع لقطات الشاشة وتسجيلها في كل المحادثات'),
                    ),
                    SwitchListTile(
                      value: s.protectMedia,
                      onChanged: (v) => _set(s.copyWith(protectMedia: v)),
                      secondary: TintIcon(Icon(Icons.photo_library_rounded, color: WaslColors.teal)),
                      title: const Text('حماية صوري ومقاطعي', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('ما ترسله: بلا توجيه ولا فتح خارج التطبيق، وبعلامة مائية باسم من يشاهده'),
                    ),
                    SwitchListTile(
                      value: s.captureAlerts,
                      onChanged: (v) => _set(s.copyWith(captureAlerts: v)),
                      secondary: TintIcon(Icon(Icons.notifications_active_rounded, color: WaslColors.violet)),
                      title: const Text('تنبيهات الالتقاط', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('تنبيه عند لقطة أو تسجيل الشاشة حيث يدعم نظامك'),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                child: Text(_platformNote, style: TextStyle(color: context.textFaint, fontSize: 12.5, height: 1.5)),
              ),
              const SheetSectionLabel('عند الابتزاز أو التهديد'),
              GlassGroup([
                ListTile(
                  leading: TintIcon(Icon(Icons.shield_rounded, color: Colors.redAccent)),
                  title: const Text('بلاغ عاجل', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('افتح المحادثة ← المزيد ← «بلاغ عاجل». تُرفق الأدلة من المحادثة نفسها.'),
                ),
                ListTile(
                  leading: TintIcon(Icon(Icons.do_not_disturb_on_rounded, color: Color(0xFFF59E0B))),
                  title: const Text('لا تدفع ولا تحذف', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('الدفع لا يوقف المبتز غالباً، والمحادثة دليلك. اترك الباقي لنا وللجهات المختصة.'),
                ),
              ]),
              if (_cases.isNotEmpty) ...[
                const SheetSectionLabel('بلاغاتي'),
                GlassGroup([
                  for (final c in _cases)
                    ListTile(
                      leading: TintIcon(Icon(Icons.description_rounded, color: WaslColors.indigo)),
                      title: Text('${shieldCategories[c['category']] ?? c['category']} · ${c['ref']}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${c['evidence']} دليل · ${(c['created_at'] as String).substring(0, 10)}'),
                      trailing: _StatusChip(c['status'] as String),
                    ),
                ]),
              ],
              const SheetSectionLabel('حدود صريحة'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '• لا يستطيع أي تطبيق منع تصوير الشاشة بكاميرا هاتف آخر.\n'
                  '• لا يمكن حذف ما حفظه شخص على جهازه؛ نستطيع إبطال نسخ وصل شات على خوادمنا فقط.\n'
                  '• الأدلة تُحفظ مشفّرة على خوادمنا، لا يطّلع عليها إلا المدير العام، ولا تُستخدم لتدريب أي ذكاء اصطناعي.\n'
                  '• تُحذف أدلة البلاغ بعد 180 يوماً من إغلاقه، ولا تُحذف ما دام مفتوحاً.',
                  style: TextStyle(color: context.textTertiary, height: 1.7, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      'new' => const Color(0xFF0EA5E9),
      'reviewing' => const Color(0xFFF59E0B),
      'action_taken' => WaslColors.teal,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(shieldStatus[status] ?? status,
          style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }
}
