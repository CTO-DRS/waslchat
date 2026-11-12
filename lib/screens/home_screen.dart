import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import 'channels_screen.dart';
import 'chats_screen.dart';
import 'communities_screen.dart';
import 'e2e_key_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    PresenceService.start();
    PushService.register();
    // فحص مفتاح التشفير: توليد أول مرة، أو استعادة من النسخة الاحتياطية على جهاز جديد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkE2eKeys(context);
      _checkUpdates();
    });
  }

  /// فحص «تحديث متوفر» بعد فتح التطبيق بثوانٍ (حتى لا يزاحم حوار المفاتيح)
  Future<void> _checkUpdates() async {
    await Future.delayed(const Duration(seconds: 4));
    final update = await UpdateService.check();
    if (update == null || !mounted) return;
    final notes = (update['notes'] as String?) ?? '';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تحديث متوفر'),
        content: Text(
            'الإصدار ${update['version'] ?? ''} متاح الآن.${notes.isEmpty ? '' : '\n\n$notes'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateService.openDownload();
            },
            child: const Text('تحميل الآن'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    PresenceService.stop();
    super.dispose();
  }

  static const _pages = <Widget>[
    ChatsScreen(),
    CommunitiesScreen(),
    ChannelsScreen(),
    _ComingSoon(title: 'المكالمات', icon: Icons.call_outlined),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                decoration: BoxDecoration(
                  color: context.glass,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: context.hairline),
                ),
                child: NavigationBar(
                  height: 68,
                  backgroundColor: Colors.transparent,
                  indicatorColor: const Color(0x556366F1),
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.chat_bubble_outline),
                        selectedIcon: Icon(Icons.chat_bubble),
                        label: 'المحادثات'),
                    NavigationDestination(
                        icon: Icon(Icons.groups_2_outlined),
                        selectedIcon: Icon(Icons.groups_2),
                        label: 'المجتمعات'),
                    NavigationDestination(
                        icon: Icon(Icons.campaign_outlined),
                        selectedIcon: Icon(Icons.campaign),
                        label: 'القنوات'),
                    NavigationDestination(
                        icon: Icon(Icons.call_outlined),
                        selectedIcon: Icon(Icons.call),
                        label: 'المكالمات'),
                    NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'الإعدادات'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(title, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: WaslColors.teal),
            const SizedBox(height: 12),
            Text('قريباً في المرحلة القادمة', style: TextStyle(color: context.textTertiary)),
          ],
        ),
      ),
    );
  }
}
