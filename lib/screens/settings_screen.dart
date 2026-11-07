import 'package:flutter/material.dart';

import '../config.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../services/e2e_service.dart';
import 'e2e_key_screen.dart';
import 'security_screens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;
    return Scaffold(
      appBar: AppBar(
          title: const Text('الإعدادات', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: WaslColors.glass,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: WaslColors.indigo,
                child: Icon(Icons.person, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user?.userMetadata?['username']?.toString() ?? 'مستخدم',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(user?.email ?? '', style: const TextStyle(color: Colors.white60)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const ListTile(
            leading: Icon(Icons.lock_outline, color: WaslColors.teal),
            title: Text('الرسائل محمية'),
            subtitle: Text('صلاحيات وصول على مستوى الصفوف (RLS)'),
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
          const Center(
              child: Text('وصل شات · الإصدار 0.1.5', style: TextStyle(color: Colors.white38))),
        ],
      ),
    );
  }
}
