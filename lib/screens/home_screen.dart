import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/shield_service.dart';
import '../services/call_service.dart';
import '../services/device_security_service.dart';
import '../services/l10n.dart';
import '../services/locale_service.dart';
import '../services/presence_service.dart';
import '../services/push_service.dart';
import '../services/realtime_hub_service.dart';
import '../services/update_service.dart';
import '../services/voice_commands_service.dart';
import '../services/voice_room_service.dart';
import '../services/app_studio_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'ai_screen.dart';
import 'call_screen.dart';
import 'voice_room_screen.dart';
import 'calls_history_screen.dart';
import 'channels_screen.dart';
import 'chats_screen.dart';
import 'communities_screen.dart';
import 'e2e_key_screen.dart';
import 'new_chat_screen.dart';
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
    // Wasl Shield (1.10.0): الإعدادات + اكتشاف الالتقاط حيث يدعم النظام
    unawaited(ShieldService.init());
    // مركز Realtime الواحد (1.2.0): قناة postgres واحدة لكل المشاهدين
    // طويلة العمر بدل قنوات لكل شاشة — أقل انضمامات للخادم وبطارية أقل
    unawaited(RealtimeHubService.start());
    // المرحلة 10: إزالة جهاز كاملة — إصغاء لحظي لإزالة الأجهزة فتسقط الجلسات
    // الميتة محلياً فوراً + مطابقة دورية شبكة أمان
    DeviceSecurityService.attach();
    // المكالمات (0.17.0): الاستماع للواردات وفتح شاشة المكالمة فوراً
    CallService.onIncoming = _openIncomingCall;
    CallService.watchIncoming();
    // المكالمة الجماعية (0.27.0): إصغاء الدعوات اللحظية وعرض ورقة انضمام
    VoiceRoomService.watchInvites();
    VoiceRoomService.incomingInvite.addListener(_showGroupCallInvite);
    // فحص مفتاح التشفير: توليد أول مرة، أو استعادة من النسخة الاحتياطية على جهاز جديد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) checkE2eKeys(context);
      _checkUpdates();
      _resumeInitialCall(); // المرحلة 11 أ: فتح بنقرة رن مكالمة فوق القفل
    });
  }

  /// المرحلة 11 أ: فتح التطبيق بنقرة إشعار الرن — إن كانت المكالمة ما تزال
  /// تُرن نعرض شاشتها، وإلا لا شيء صادق (لا شاشة شبح)
  Future<void> _resumeInitialCall() async {
    final data = await PushService.initialCallData();
    if (data == null || !mounted) return;
    final s = await CallService.resumeFromCallData(data);
    if (s != null && mounted) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => CallScreen(session: s)));
    }
  }

  /// مكالمة واردة — شاشة ملء فوق كل شيء
  void _openIncomingCall(CallSession session) {
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(session: session)));
  }

  /// دعوة مكالمة جماعية وصلت (0.27.0): ورقة انضمام صادقة — والانضمام
  /// يمر بالبوابة نفسها (عضوية RLS وسعة 8) فلا حلول وهمية
  bool _inviteSheetOpen = false;

  Future<void> _showGroupCallInvite() async {
    final inv = VoiceRoomService.incomingInvite.value;
    if (inv == null || _inviteSheetOpen || !mounted) return;
    _inviteSheetOpen = true;
    VoiceRoomService.incomingInvite.value = null;
    try {
      final join = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.groups_rounded, color: WaslColors.teal),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(inv.bannerText(),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15.5)),
                ),
              ]),
              const SizedBox(height: 8),
              Text('صوت مباشر بين الأجهزة بلا خادم يسمع — الدعوة لحظية لا تُخزَّن',
                  style: TextStyle(
                      fontSize: 12.5, color: context.textSecondary)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('تجاهل'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: WaslColors.teal),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: const Text('انضمام'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );
      if (join == true && mounted) {
        await showVoiceRoomIntro(
          context,
          conversationId: inv.conversationId,
          title: 'مكالمة جماعية',
          asCall: true,
        );
      }
    } finally {
      _inviteSheetOpen = false;
    }
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

  /// الأوامر الصوتية متاحة على الويب والجوال — سطح المكتب لا (خدمة النظام غير موجودة)
  static bool get _voiceSupported => kIsWeb || Platform.isAndroid || Platform.isIOS;

  void _handleVoiceCommand(VoiceCommand cmd) {
    final action = cmd.action;
    if (action.startsWith('tab:')) {
      final i = int.tryParse(action.substring(4));
      if (i != null && i >= 0 && i < _pages.length && mounted) {
        setState(() => _index = i);
      }
      return;
    }
    if (action == 'ai') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const AiScreen()));
      return;
    }
    if (action == 'newchat') {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const NewChatScreen()));
    }
  }

  /// ورقة الأوامر الصوتية (المرحلة 5)
  void _openVoiceCommands() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: VoiceCommandsSheet(onCommand: _handleVoiceCommand),
      ),
    );
  }

  @override
  void dispose() {
    DeviceSecurityService.detach();
    PresenceService.stop();
    CallService.onIncoming = null;
    CallService.stopWatching();
    VoiceRoomService.incomingInvite.removeListener(_showGroupCallInvite);
    VoiceRoomService.stopWatchingInvites();
    unawaited(RealtimeHubService.stop()); // فك القناة الواحدة عند الخروج
    super.dispose();
  }

  static const _pages = <Widget>[
    ChatsScreen(),
    CommunitiesScreen(),
    ChannelsScreen(),
    CallsHistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(children: [
        IndexedStack(index: _index, children: _pages),
        // زر الأوامر الصوتية (المرحلة 5): تجربة صوتية بلا لمس
        // يظهر في تبويب المحادثات فقط، فوق زر القلم بمسافة واضحة
        // (كان يتراكب خلف زر الإضافة في كل التبويبات)
        if (_voiceSupported && _index == 0)
          PositionedDirectional(
            end: 25,
            bottom: 178,
            child: MotionScaleIn(
              child: FloatingActionButton.small(
                heroTag: 'voice-commands',
                tooltip: 'الأوامر الصوتية',
                backgroundColor: context.glass,
                foregroundColor: context.textPrimary,
                elevation: 0,
                onPressed: _openVoiceCommands,
                child: const Icon(Icons.mic_rounded),
              ),
            ),
          ),
      ]),
      // الشريط السفلي حسب «استوديو التطبيق»: عائم (الأصل) أو كلاسيكي أو بسيط
      bottomNavigationBar: ValueListenableBuilder<StudioStyle>(
        valueListenable: AppStudioService.style,
        builder: (context, studio, _) {
          final bar = NavigationBar(
                  height: studio.navLabels ? 68 : 60,
                  backgroundColor: Colors.transparent,
                  indicatorColor: studio.accentColor.withValues(alpha: 0x55 / 255),
                  labelBehavior: studio.navLabels
                      ? NavigationDestinationLabelBehavior.alwaysShow
                      : NavigationDestinationLabelBehavior.alwaysHide,
                  selectedIndex: _index,
                  onDestinationSelected: (i) {
                    AppStudioService.tick();
                    setState(() => _index = i);
                  },
                  destinations: [
                    NavigationDestination(
                        icon: _NavBadge(icon: Icons.chat_bubble_outline),
                        selectedIcon: _NavBadge(icon: Icons.chat_bubble, selected: true),
                        label: l10nT('nav_chats', LocaleService.lang.value)),
                    NavigationDestination(
                        icon: const Icon(Icons.groups_2_outlined),
                        selectedIcon: const Icon(Icons.groups_2),
                        label: l10nT('nav_communities', LocaleService.lang.value)),
                    NavigationDestination(
                        icon: const Icon(Icons.campaign_outlined),
                        selectedIcon: const Icon(Icons.campaign),
                        label: l10nT('nav_channels', LocaleService.lang.value)),
                    NavigationDestination(
                        icon: const Icon(Icons.call_outlined),
                        selectedIcon: const Icon(Icons.call),
                        label: l10nT('nav_calls', LocaleService.lang.value)),
                    NavigationDestination(
                        icon: const Icon(Icons.settings_outlined),
                        selectedIcon: const Icon(Icons.settings),
                        label: l10nT('nav_settings', LocaleService.lang.value)),
                  ],
                );
          switch (studio.nav) {
            case StudioNav.floating:
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(studio.r(28)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.glass,
                          borderRadius: BorderRadius.circular(studio.r(28)),
                          border: Border.all(color: context.hairline),
                        ),
                        child: bar,
                      ),
                    ),
                  ),
                ),
              );
            case StudioNav.classic:
              return Container(
                decoration: BoxDecoration(
                  color: context.surfaceAlt,
                  border: Border(top: BorderSide(color: context.hairline)),
                ),
                child: SafeArea(top: false, child: bar),
              );
            case StudioNav.minimal:
              return ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: SafeArea(top: false, child: bar),
                ),
              );
          }
        },
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

