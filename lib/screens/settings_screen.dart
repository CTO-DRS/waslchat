import 'package:flutter/material.dart';

import '../config.dart';
import '../services/app_lock_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../services/e2e_service.dart';
import '../widgets/common.dart';
import 'e2e_key_screen.dart';
import 'profile_screen.dart';
import 'starred_screen.dart';
import 'security_screens.dart';

String _modeLabel(ThemeMode m) => switch (m) {
      ThemeMode.dark => 'داكن',
      ThemeMode.light => 'فاتح (تجريبي)',
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
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? WaslColors.darkSurface
                    : null,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (ctx) => SafeArea(
                  child: Wrap(children: [
                    const ListTile(
                      title: Text('المظهر',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('الفاتح تجريبي: بعض الشاشات محسّنة للداكن حتى الآن'),
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
          const _AppLockTile(),
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
                  style: const TextStyle(color: Colors.white38))),
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
      color: WaslColors.glass,
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
                    style: const TextStyle(color: Colors.white60)),
              ]),
            ),
            const Icon(Icons.edit_outlined, color: Colors.white54),
          ]),
        ),
      ),
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
