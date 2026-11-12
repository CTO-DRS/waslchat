import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
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
    _CallsScreen(),
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
                        icon: _NavBadge(icon: Icons.chat_bubble_outline),
                        selectedIcon: _NavBadge(icon: Icons.chat_bubble, selected: true),
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

/// شارة عدد غير المقروء فوق أيقونة تبويب «المحادثات» في الشريط السفلي
/// — تقرأ من UnreadHub وتختفي تلقائياً عند تصفير كل المحادثات.
class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.icon, this.selected = false});
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final base = Icon(icon, size: 24);
    return ValueListenableBuilder<int>(
      valueListenable: UnreadHub.total,
      builder: (context, total, _) {
        if (total <= 0) return base;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            base,
            PositionedDirectional(
              top: -5,
              end: -9,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: WaslColors.teal,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                ),
                child: Text(total > 99 ? '99+' : '$total',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// شاشة المكالمات: الميزة قادمة في المرحلة القادمة — عرض ترويجي
/// يشرح ما ينتظر المستخدم (اتصال صوتي، مكالمة مرئية، تشفير طرف-لطرف)
/// بدل شاشة فراغ جامدة.
class _CallsScreen extends StatelessWidget {
  const _CallsScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('المكالمات',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 150),
        children: [
          const SizedBox(height: 14),
          Center(
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: WaslColors.gradient,
                boxShadow: [
                  BoxShadow(
                    color: WaslColors.indigo.withValues(alpha: 0.35),
                    blurRadius: 42,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: const Icon(Icons.call_outlined, size: 54, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('المكالمات الصوتية والمرئية',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'بشفرتك نفسها: مكالمات مشفّرة طرف-لطرف\nداخل وصل شات، بلا وسيط يسمعكم',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.7, color: context.textTertiary, fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 28),
          _CallFeature(
            icon: Icons.mic_none_rounded,
            color: WaslColors.indigo,
            title: 'اتصال صوتي نقي',
            desc: 'أحاديث صوتية واضحة تتكيف مع سرعة شبكتك تلقائياً',
          ),
          _CallFeature(
            icon: Icons.videocam_outlined,
            color: WaslColors.teal,
            title: 'مكالمة مرئية',
            desc: 'شاهد من تحادثك وجهاً لوجه بجودة تناسب اتصالك',
          ),
          _CallFeature(
            icon: Icons.lock_outline_rounded,
            color: WaslColors.violet,
            title: 'تشفير طرف-لطرف',
            desc: 'مفاتيح المكالمة على جهازيكما وحدكما، لا حتى الخادم',
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: context.glass,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: context.hairline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      size: 16, color: WaslColors.teal),
                  const SizedBox(width: 8),
                  Text('سنوافيك فور جاهزيتها في تحديث قادم',
                      style: TextStyle(color: context.textSecondary, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة ميزة قادمة في شاشة المكالمات: أيقونة ملونة + عنوان + سطر شرح
class _CallFeature extends StatelessWidget {
  const _CallFeature({
    required this.icon,
    required this.color,
    required this.title,
    required this.desc,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 3),
                Text(desc,
                    style: TextStyle(height: 1.5, color: context.textTertiary, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
