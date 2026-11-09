import 'package:flutter/material.dart';

import '../config.dart';
import '../services/app_lock_service.dart';
import '../services/media_cache.dart';
import '../services/media_prefs.dart';
import '../services/presence_service.dart';
import '../services/privacy_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../services/e2e_service.dart';
import '../widgets/common.dart';
import 'app_lock_screen.dart';
import 'e2e_key_screen.dart';
import 'profile_screen.dart';
import 'starred_screen.dart';
import 'security_screens.dart';

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
          const _AppearanceCard(),
          const SizedBox(height: 16),
          _MediaCard(),
          const SizedBox(height: 16),
          const _PrivacyCard(),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.lock_outline, color: WaslColors.teal),
            title: Text('الرسائل محمية'),
            subtitle: Text('صلاحيات وصول على مستوى الصفوف (RLS)'),
          ),
          ListTile(
            leading: Icon(Icons.star_outline_rounded, color: context.wasl.warning),
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
          const AppLockCard(),
          ListTile(
            leading: const Icon(Icons.password, color: WaslColors.teal),
            title: const Text('تغيير كلمة المرور'),
            onTap: () => openChangePassword(context),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: context.wasl.danger),
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
              PrivacyService.reset();
              await supabase.auth.signOut();
            },
          ),
          const SizedBox(height: 24),
          Center(
              child: Text('وصل شات · الإصدار ${AppConfig.versionName}',
                  style: TextStyle(color: context.wasl.textFaint))),
        ],
      ),
    );
  }
}

/// بطاقة المظهر (بند المرحلة 1: الوضع الفاتح وحجم الخط)
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: Icon(Icons.palette_outlined, color: context.wasl.accent),
        title: const Text('المظهر',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: const Text('الوضع وحجم الخط — محفوظ على جهازك'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: ThemeService.mode,
          builder: (context, mode, _) => SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('فاتح'),
                  icon: Icon(Icons.light_mode_outlined, size: 18)),
              ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('داكن'),
                  icon: Icon(Icons.dark_mode_outlined, size: 18)),
              ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('النظام'),
                  icon: Icon(Icons.settings_suggest_outlined, size: 18)),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ThemeService.setMode(s.first),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ValueListenableBuilder<double>(
          valueListenable: ThemeService.fontScale,
          builder: (context, scale, _) => Wrap(
            spacing: 8,
            runSpacing: 4,
            children: ThemeService.fontLevels.entries
                .map((e) => ChoiceChip(
                      label: Text(e.key,
                          style: TextStyle(fontSize: 13 * e.value)),
                      selected: scale == e.value,
                      onSelected: (_) => ThemeService.setFontScale(e.value),
                    ))
                .toList(),
          ),
        ),
      ),
    ]);
  }
}

/// بطاقة الوسائط (بند المرحلة 1: ضغط الفيديو والتنزيل التلقائي 0.4.8)
/// كل شيء محلي على الجهاز — لا يُرفع أي إعداد للخادم
class _MediaCard extends StatefulWidget {
  const _MediaCard();

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
  bool _clearing = false;

  Future<void> _pickRule() async {
    final current = MediaPrefs.autoDownload.value;
    final picked = await showDialog<AutoDownloadRule>(
      context: context,
      builder: (ctx) => RadioGroup<AutoDownloadRule>(
        groupValue: current,
        onChanged: (v) {
          if (v != null) Navigator.pop(ctx, v);
        },
        child: SimpleDialog(
          title: const Text('التنزيل التلقائي للفيديو'),
          children: [
            for (final r in AutoDownloadRule.values)
              RadioListTile<AutoDownloadRule>(
                value: r,
                title: Text(MediaPrefs.label(r)),
                subtitle: Text(MediaPrefs.description(r),
                    style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await MediaPrefs.setRule(picked);
    if (mounted) setState(() {});
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    final n = await MediaCache.clear();
    if (!mounted) return;
    setState(() => _clearing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0
            ? 'مُسحت $n من الوسائط المؤقتة المفكوكة'
            : 'لا وسائط مؤقتة الآن')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: Icon(Icons.video_library_outlined, color: context.wasl.accent),
        title: const Text('الوسائط',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: const Text(
            'الفيديو يُضغط على جهازك قبل الإرسال (بمُرمّزات المنصة)، ومصغّره تصل مشفّرة'),
      ),
      ListTile(
        leading: const Icon(Icons.wifi_rounded, color: WaslColors.teal, size: 22),
        title: const Text('التنزيل التلقائي للفيديو'),
        subtitle: Text(MediaPrefs.description(MediaPrefs.autoDownload.value),
            style: const TextStyle(fontSize: 12)),
        trailing: Text(MediaPrefs.label(MediaPrefs.autoDownload.value),
            style: TextStyle(color: context.wasl.accent, fontSize: 13)),
        onTap: _pickRule,
      ),
      ListTile(
        leading: const Icon(Icons.cleaning_services_outlined,
            color: WaslColors.violet, size: 22),
        title: const Text('مسح الوسائط المؤقتة'),
        subtitle: const Text('تحذف النسخ المفكوكة على جهازك من الكاش',
            style: TextStyle(fontSize: 12)),
        trailing: _clearing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_left),
        onTap: _clearing ? null : _clearCache,
      ),
    ]);
  }
}

/// بطاقة الخصوصية (بند المرحلة 1: إخفاء «متصل الآن» وعلامات القراءة اختيارياً)
class _PrivacyCard extends StatefulWidget {
  const _PrivacyCard();

  @override
  State<_PrivacyCard> createState() => _PrivacyCardState();
}

class _PrivacyCardState extends State<_PrivacyCard> {
  bool _busy = false;

  Future<void> _set({bool? presence, bool? receipts}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await PrivacyService.save(
        hidePresenceValue:
            presence ?? PrivacyService.hidePresence.value,
        hideReceiptsValue:
            receipts ?? PrivacyService.hideReceipts.value,
      );
      // إعادة تشكيل قناة الحضور فوراً حسب الإعداد الجديد
      if (presence != null) await PresenceService.apply();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: Icon(Icons.visibility_off_outlined, color: context.wasl.accent),
        title: const Text('الخصوصية',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: const Text('ما تخفيه لا يراه الآخرون — وبالمقابل لن ترى مثله'),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.circle, color: WaslColors.teal, size: 22),
        title: const Text('إخفاء حالة الاتصال'),
        subtitle: const Text(
            'لن يراك أحد «متصل الآن» — ولن ترى حالة الآخرين (قاعدة المبادلة)'),
        value: PrivacyService.hidePresence.value,
        onChanged: _busy ? null : (v) => _set(presence: v),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.done_all_rounded,
            color: WaslColors.indigo, size: 22),
        title: const Text('إخفاء علامات القراءة ✓✓'),
        subtitle: const Text(
            'لن يعرف أحد متى قرأت رسائله — ولن تعرف أنت متى قرأ (قاعدة المبادلة)'),
        value: PrivacyService.hideReceipts.value,
        onChanged: _busy ? null : (v) => _set(receipts: v),
      ),
    ]);
  }
}

/// بطاقة قفل التطبيق (بند المرحلة 2: قفل بالبصمة أو الرمز)
class AppLockCard extends StatefulWidget {
  const AppLockCard({super.key});

  @override
  State<AppLockCard> createState() => _AppLockCardState();
}

class _AppLockCardState extends State<AppLockCard> {
  bool _biometricAvailable = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    AppLockService.biometricAvailable().then((v) {
      if (mounted) setState(() => _biometricAvailable = v);
    });
  }

  Future<void> _toggle(bool want) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!want) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('إيقاف قفل التطبيق؟'),
            content: const Text(
                'سيتمكن من يفتح جوالك من قراءة رسائلك مباشرة بدون رمز أو بصمة.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('إلغاء')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: context.wasl.danger),
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('أوقف القفل')),
            ],
          ),
        );
        if (ok == true) await AppLockService.disable();
      } else {
        // 1) رمز PIN إلزامي (طريق احتياطي دائماً حتى لا يُقفل المستخدم خارجاً)
        final pin = await showPinSetupDialog(context);
        if (pin == null) return;
        await AppLockService.enable(pin);
        // 2) بصمة اختيارية إن كان الجهاز يدعمها
        if (_biometricAvailable && mounted) {
          final wantBio = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('الفتح بالبصمة؟'),
              content: const Text(
                  'يمكنك فتح القفل بالبصمة أو رمز الجهاز بدل كتابة الرمز في كل مرة. يمكنك تغيير ذلك لاحقاً من هنا.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('لا، الرمز فقط')),
                FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('نعم، فعّلها')),
              ],
            ),
          );
          if (wantBio == true) {
            final ok = await AppLockService.verifyBiometric();
            await AppLockService.setBiometric(ok);
          }
        }
      }
      if (mounted) setState(() {});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBiometric(bool want) async {
    if (want) {
      final ok = await AppLockService.verifyBiometric();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تعذّر التحقق من البصمة — لم تُفعّل')));
        return;
      }
      await AppLockService.setBiometric(true);
    } else {
      await AppLockService.setBiometric(false);
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    final pin = await showPinSetupDialog(context);
    if (pin == null) return;
    await AppLockService.setPin(pin);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تغيير رمز القفل')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = AppLockService.enabled;
    return Column(children: [
      SwitchListTile(
        secondary: const Icon(Icons.lock_clock_outlined, color: WaslColors.teal),
        title: const Text('قفل التطبيق'),
        subtitle: Text(on
            ? 'يُقفل عند الخروج للخلفية أو فتح التطبيق'
            : 'رمز أو بصمة قبل قراءة الرسائل عند العودة للتطبيق'),
        value: on,
        onChanged: _busy ? null : _toggle,
      ),
      if (on) ...[
        if (_biometricAvailable)
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint, color: WaslColors.indigo),
            title: const Text('الفتح بالبصمة أو رمز الجهاز'),
            subtitle: const Text('طريق مختصر فوق رمز الـPIN'),
            value: AppLockService.useBiometric,
            onChanged: _busy ? null : _toggleBiometric,
          ),
        ListTile(
          leading: const Icon(Icons.password, color: WaslColors.violet),
          title: const Text('تغيير رمز القفل'),
          onTap: _busy ? null : _changePin,
        ),
      ],
    ]);
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
      color: context.wasl.glass,
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
                    style: TextStyle(color: context.wasl.textFaint)),
              ]),
            ),
            Icon(Icons.edit_outlined, color: context.wasl.textFaint),
          ]),
        ),
      ),
    );
  }
}
