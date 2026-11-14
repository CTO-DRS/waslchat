import 'package:flutter/material.dart';

import '../config.dart';
import '../services/app_icon_service.dart';
import '../services/app_lock_service.dart';
import '../services/link_preview_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/smart_order_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../services/e2e_service.dart';
import '../widgets/common.dart';
import 'e2e_key_screen.dart';
import 'bots_screen.dart';
import 'feedback_screen.dart';
import 'linked_devices_screen.dart';
import 'profile_screen.dart';
import 'starred_screen.dart';
import 'security_screens.dart';

String _modeLabel(ThemeMode m) => switch (m) {
      ThemeMode.dark => 'داكن',
      ThemeMode.light => 'فاتح',
      ThemeMode.system => 'حسب النظام',
    };

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('الإعدادات', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          const _ProfileCard(),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.lock_outline, color: WaslColors.teal),
            title: Text('الرسائل محمية'),
            subtitle: Text('صلاحيات وصول على مستوى الصفوف (RLS)'),
          ),
          ListTile(
            leading: const Icon(Icons.star_outline_rounded, color: Colors.amber),
            title: const Text('الرسائل المميزة بنجمة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const StarredScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: WaslColors.indigo),
            title: const Text('التحقق بخطوتين'),
            subtitle: const Text('رمز من تطبيق المصادقة عند الدخول'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TwoFactorScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.key_outlined, color: WaslColors.violet),
            title: const Text('مفتاح التشفير'),
            subtitle: const Text('النسخة الاحتياطية واستعادتها على جوال جديد'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => checkE2eKeys(context, fromSettings: true),
          ),
          ListTile(
            leading: const Icon(Icons.devices_other_rounded, color: WaslColors.teal),
            title: const Text('الأجهزة المرتبطة'),
            subtitle: const Text('هواتف ومتصفحات تستخدم حسابك — لكل جهاز مفاتيحه'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const LinkedDevicesScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined, color: WaslColors.violet),
            title: const Text('البوتات وواجهة المطوّرين'),
            subtitle: const Text('أنشئ بوتات برمز وواجهة وويب هوك موقّع'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BotsScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.rate_review_outlined, color: WaslColors.teal),
            title: const Text('إرسال ملاحظات'),
            subtitle: const Text('خلل أو فكرة أو ملاحظة خصوصية — تصل لفريق وصل مباشرة'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FeedbackScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.password, color: WaslColors.teal),
            title: const Text('تغيير كلمة المرور'),
            onTap: () => openChangePassword(context),
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined, color: WaslColors.violet),
            title: const Text('المظهر'),
            subtitle: ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.mode,
              builder: (_, m, __) => Text(_modeLabel(m)),
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () async {
              final m = await showModalBottomSheet<ThemeMode>(
                context: context,
                backgroundColor: context.surfaceAlt,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (ctx) => SafeArea(
                  child: Wrap(children: [
                    const ListTile(
                      title: Text('المظهر',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    for (final m in ThemeMode.values)
                      ListTile(
                        leading: Icon(
                            ThemeService.mode.value == m
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: WaslColors.teal),
                        title: Text(_modeLabel(m)),
                        onTap: () => Navigator.pop(ctx, m),
                      ),
                  ]),
                ),
              );
              if (m != null) ThemeService.set(m);
            },
          ),
          const _FontSizeTile(),
          const _WallpaperTile(),
          const _AppLockTile(),
          const _NotificationsTile(),
          const _LinkPreviewTile(),
          const _SmartOrderTile(),
          const _AppIconTile(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('تسجيل الخروج'),
            onTap: () async {
              // بلا نسخة احتياطية سيضيع المفتاح عند الخروج: ننبّه أولاً
              final st = await E2eService.checkKeys();
              if (!context.mounted) return;
              if (st == E2eKeyState.needsBackup) {
                final go = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('مفتاح التشفير غير محفوظ'),
                    content: const Text(
                        'إن خرجت الآن فلن تقرأ رسائلك المشفّرة عند الدخول مجدداً. احفظ نسخة احتياطية أولاً؟'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('اخرج على أي حال')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('احفظ النسخة')),
                    ],
                  ),
                );
                if (!context.mounted) return;
                if (go != true) {
                  await checkE2eKeys(context, fromSettings: true);
                  return;
                }
              }
              await E2eService.wipeLocal();
              await PushService.unregister();
              await PresenceService.stop();
              await supabase.auth.signOut();
            },
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded, color: WaslColors.teal),
            title: const Text('فحص وجود تحديث'),
            subtitle: Text('الإصدار ${AppConfig.appVersion}+${AppConfig.appBuild}'),
            onTap: () async {
              final u = await UpdateService.check();
              if (!context.mounted) return;
              if (u == null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('لديك أحدث إصدار')));
                return;
              }
              final go = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('تحديث متوفر'),
                  content: Text(
                      'الإصدار ${u['version'] ?? ''} متاح الآن.${((u['notes'] as String?) ?? '').isEmpty ? '' : '\n\n${u['notes']}'}'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لاحقاً')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('تحميل الآن')),
                  ],
                ),
              );
              if (go == true) await UpdateService.openDownload();
            },
          ),
          const SizedBox(height: 8),
          Center(
              child: Text('وصل شات · الإصدار ${AppConfig.appVersion}+${AppConfig.appBuild}',
                  style: TextStyle(color: context.textFaint))),
        ],
      ),
    );
  }
}

/// بطاقة الملف الشخصي أعلى الإعدادات (اضغط للتعديل)
class _ProfileCard extends StatefulWidget {
  const _ProfileCard();

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  Map<String, dynamic>? _p;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final p = await supabase
          .from('profiles')
          .select('username, display_name, bio, avatar_url')
          .eq('id', uid)
          .single();
      if (mounted) setState(() => _p = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final name = (_p?['display_name'] ?? _p?['username'] ?? 'مستخدم') as String;
    final bio = _p?['bio'] as String?;
    return Material(
      color: context.glass,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            UserAvatar(name: name, url: _p?['avatar_url'] as String?, radius: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                    (bio != null && bio.isNotEmpty)
                        ? bio
                        : (supabase.auth.currentUser?.email ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textTertiary)),
              ]),
            ),
            Icon(Icons.edit_outlined, color: context.textFaint),
          ]),
        ),
      ),
    );
  }
}

/// بلاطة حجم الخط: صغير/عادي/كبير/أكبر — تطبق فوراً على كل التطبيق
class _FontSizeTile extends StatelessWidget {
  const _FontSizeTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.text_fields_rounded, color: WaslColors.indigo),
      title: const Text('حجم الخط'),
      subtitle: ValueListenableBuilder<double>(
        valueListenable: FontScaleService.scale,
        builder: (_, s, __) => Text(
            'حالياً: ${(FontScaleService.options.firstWhere((o) => o.$1 == s, orElse: () => (1.0, 'عادي')).$2)}'),
      ),
      trailing: const Icon(Icons.chevron_left),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: context.surfaceAlt,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => SafeArea(
            child: ValueListenableBuilder<double>(
              valueListenable: FontScaleService.scale,
              builder: (ctx, s, __) => Wrap(children: [
                const ListTile(
                  title: Text('حجم الخط',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                // عيّنة مباشرة بحجم المعاينة
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('هكذا ستبدو رسائلك بمقاس هذا الخيار',
                      style: TextStyle(
                          fontSize: 15 * s, color: ctx.textSecondary)),
                ),
                for (final (v, label) in FontScaleService.options)
                  ListTile(
                    leading: Icon(
                        s == v ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: WaslColors.teal),
                    title: Text(label),
                    onTap: () {
                      FontScaleService.set(v);
                      Navigator.pop(ctx);
                    },
                  ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// بلاطة خلفية المحادثة: خلفيات مضمنة (تدرج + نقاط) تُرسم خلف رسائل كل محادثة
class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.wallpaper_rounded, color: WaslColors.teal),
      title: const Text('خلفية المحادثة'),
      subtitle: ValueListenableBuilder<int>(
        valueListenable: WallpaperService.index,
        builder: (_, i, __) => Text(WallpaperService.wallpapers[i].name),
      ),
      trailing: const Icon(Icons.chevron_left),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          backgroundColor: context.surfaceAlt,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          builder: (ctx) => SafeArea(
            child: ValueListenableBuilder<int>(
              valueListenable: WallpaperService.index,
              builder: (ctx, sel, __) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('خلفية المحادثة',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('تُرسم خلف رسائل كل المحادثات — مضمنة داخل التطبيق',
                      style: TextStyle(fontSize: 12, color: ctx.textTertiary)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var i = 0; i < WallpaperService.wallpapers.length; i++)
                        _WallpaperPreview(
                          wp: WallpaperService.wallpapers[i],
                          dark: Theme.of(ctx).brightness == Brightness.dark,
                          selected: sel == i,
                          onTap: () {
                            WallpaperService.set(i);
                            Navigator.pop(ctx);
                          },
                        ),
                    ],
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WallpaperPreview extends StatelessWidget {
  const _WallpaperPreview(
      {required this.wp,
      required this.dark,
      required this.selected,
      required this.onTap});
  final WaslWallpaper wp;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? WaslColors.teal : context.hairline,
                width: selected ? 2.5 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CustomPaint(
              painter: WallpaperPainter(wp, dark: dark),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: Text(wp.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? WaslColors.teal : context.textSecondary)),
        ),
      ]),
    );
  }
}

/// بلاطة قفل التطبيق: بصمة الجهاز أو رمز قفله (المرحلة 2)
class _AppLockTile extends StatefulWidget {
  const _AppLockTile();

  @override
  State<_AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<_AppLockTile> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLockService.isEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool v) async {
    setState(() => _busy = true);
    final err = await AppLockService.setEnabled(v);
    if (mounted) {
      setState(() {
        _busy = false;
        if (err == null) _enabled = v;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ??
              (v ? 'فُعّل قفل التطبيق' : 'أُلغي قفل التطبيق'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.fingerprint_rounded, color: WaslColors.violet),
      title: const Text('قفل التطبيق'),
      subtitle: const Text('بصمة الإصبع أو رمز قفل الجهاز عند الفتح والعودة'),
      value: _enabled,
      onChanged: _busy ? null : _toggle,
    );
  }
}

/// مفتاح الإشعارات العام: إيقافه يحذف رمز الجهاز من الخادم فوراً
/// فلا تصل أي تنبيهات، وتشغيله يعيد التسجيل ويطلب الصلاحيات.
class _NotificationsTile extends StatelessWidget {
  const _NotificationsTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PushService.enabled,
      builder: (context, on, _) => SwitchListTile(
        secondary: Icon(
            on ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
            color: WaslColors.indigo),
        title: const Text('الإشعارات'),
        subtitle: Text(on
            ? 'تنبيهات الرسائل الجديدة مفعّلة على هذا الجهاز'
            : 'التنبيهات موقوفة — لن يصلك أي إشعار حتى تفعّلها'),
        value: on,
        onChanged: (v) => PushService.setEnabled(v),
      ),
    );
  }
}

/// بلاطة معاينة الروابط (0.21.0): مفتاح تعطيل عام + الإفصاح الصادق الحرفي
/// عن ما يمر عبر الخادم — مكتوب هنا لن يقرأه إلا من يريد.
class _LinkPreviewTile extends StatelessWidget {
  const _LinkPreviewTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: LinkPreviewService.enabled,
      builder: (context, on, _) => SwitchListTile(
        secondary: Icon(Icons.link_rounded,
            color: on ? WaslColors.teal : context.textFaint),
        title: const Text('معاينة الروابط'),
        subtitle: Text(on
            ? 'العنوان والصورة المصغرة للروابط العامة. إفصاح: الرابط يمر عبر '
                'خادم وصل عند توليد المعاينة فقط، ولا يُخزّن عنده إطلاقاً — '
                'والنتيجة تُحفظ على جهازك 24 ساعة ثم تُحذف'
            : 'المعاينة موقفة — لا يمر أي رابط عبر أي مكان'),
        value: on,
        onChanged: (v) async {
          await LinkPreviewService.setEnabled(v);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(v
                    ? 'فُعّلت معاينة الروابط'
                    : 'أُوقفت المعاينة ومُسح الكاش المحلي')));
          }
        },
      ),
    );
  }
}

/// بلاطة الترتيب الذكي للمحادثات (المرحلة 9 أ — 0.22.0): مفتاح تعطيل واحد
/// يعيد ترتيب الخادم الأصلي فوراً، والإفصاح الحرفي معروض في الوصف.
class _SmartOrderTile extends StatelessWidget {
  const _SmartOrderTile();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SmartOrderService.enabled,
      builder: (context, on, _) => SwitchListTile(
        secondary: Icon(Icons.low_priority_rounded,
            color: on ? WaslColors.teal : context.textFaint),
        title: const Text('الترتيب الذكي للمحادثات'),
        subtitle: Text(on
            ? SmartOrderService.disclosure
            : 'القائمة بترتيب الخادم الأصلي (الأحدث أولاً)'),
        value: on,
        onChanged: (v) async {
          await SmartOrderService.setEnabled(v);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(v
                    ? 'فُعّل الترتيب الذكي — المثبّت يبقى أولاً'
                    : 'عاد الترتيب الأصلي')));
          }
        },
      ),
    );
  }
}

/// بلاطة أيقونة التطبيق (0.21.0): البديل المتدرج أو الكلاسيكية —
/// التبديل يعيد إطلاق أيقونة المُشغّل على أندرويد (activity-alias).
class _AppIconTile extends StatefulWidget {
  const _AppIconTile();

  @override
  State<_AppIconTile> createState() => _AppIconTileState();
}

class _AppIconTileState extends State<_AppIconTile> {
  String _current = 'classic';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppIconService.current().then((v) {
      if (mounted) setState(() => _current = v);
    });
  }

  Future<void> _pick(String v) async {
    if (v == _current || _busy) return;
    setState(() => _busy = true);
    final ok = await AppIconService.set(v);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _current = v;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'تم تغيير أيقونة التطبيق'
            : 'تعذّر التغيير على هذا الجهاز')));
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.grid_view_rounded, color: WaslColors.violet),
      title: const Text('أيقونة التطبيق'),
      subtitle: Text(_busy
          ? 'جارٍ التغيير…'
          : _current == 'gradient'
              ? 'النمط الحالي: المتدرجة'
              : 'النمط الحالي: الكلاسيكية'),
      trailing: const Icon(Icons.chevron_left),
      onTap: _busy
          ? null
          : () => showModalBottomSheet<String>(
                context: context,
                backgroundColor: context.surfaceAlt,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
                builder: (ctx) => SafeArea(
                  child: Wrap(children: [
                    const ListTile(
                        title: Text('أيقونة التطبيق',
                            style: TextStyle(fontWeight: FontWeight.w800))),
                    for (final (v, label) in const [
                      ('classic', 'الكلاسيكية — الخضراء المعتمدة'),
                      ('gradient', 'المتدرجة — بديل ألوان وصل'),
                    ])
                      ListTile(
                        leading: Icon(
                            _current == v
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: WaslColors.teal),
                        title: Text(label),
                        onTap: () {
                          Navigator.pop(ctx, v);
                          _pick(v);
                        },
                      ),
                  ]),
                ),
              ),
    );
  }
}
