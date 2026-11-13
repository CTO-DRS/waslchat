/// شاشة سجل المكالمات (المرحلة 6 — 0.17.0) — تبويب «المكالمات» الرئيسي.
///
/// سجل صادق: صادرة/واردة/فائتة/مرفوضة/ملغاة/فشلت، والمدة للمكتملة منها،
/// والطرفان وحدهما يقرآن هذا السجل عبر RLS (028_calls.sql) ويُنظَّف
/// من الخادم بعد 90 يوماً. الضغط على أي سطر يعيد الاتصال بنفس الشخص
/// وبنوع المكالمة نفسه.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/call_logic.dart';
import '../services/call_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import 'call_screen.dart';

class CallsHistoryScreen extends StatefulWidget {
  const CallsHistoryScreen({super.key});

  @override
  State<CallsHistoryScreen> createState() => _CallsHistoryScreenState();
}

class _CallsHistoryScreenState extends State<CallsHistoryScreen> {
  bool _loading = true;
  List<CallRecord> _calls = [];
  final Map<String, (String, String?)> _peers = {}; // id → (الاسم، الصورة)
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = supabase
        .channel('call-history')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final ch = _channel;
    _channel = null;
    if (ch != null) supabase.removeChannel(ch);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final calls = await CallService.history();
      final me = supabase.auth.currentUser?.id ?? '';
      final ids = calls.map((c) => c.peerId(me)).toSet().toList();
      final peers = <String, (String, String?)>{};
      if (ids.isNotEmpty) {
        final rows = await supabase
            .from('profiles')
            .select('id, display_name, username, avatar_url')
            .inFilter('id', ids);
        for (final r in (rows as List)) {
          final id = (r as Map)['id'] as String;
          final name = (r['display_name'] as String?)?.isNotEmpty == true
              ? r['display_name'] as String
              : ((r['username'] as String?) ?? 'وصل');
          final avatar = (r['avatar_url'] as String?);
          peers[id] = (name, (avatar?.isNotEmpty ?? false) ? avatar : null);
        }
      }
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _peers.addAll(peers);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  (String, String?) _peerOf(CallRecord r) {
    final me = supabase.auth.currentUser?.id ?? '';
    return _peers[r.peerId(me)] ?? ('وصل', null);
  }

  Future<void> _callAgain(CallRecord r) async {
    final me = supabase.auth.currentUser?.id ?? '';
    final (name, avatar) = _peerOf(r);
    final s = await CallService.start(
      conversationId: r.conversationId,
      peerId: r.peerId(me),
      peerName: name,
      peerAvatar: avatar,
      kind: r.kind,
    );
    if (!mounted) return;
    if (s == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('لا يمكن بدء مكالمة الآن — أغلق المكالمة الجارية أو حاول لاحقاً')));
      return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CallScreen(session: s)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('المكالمات',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _calls.isEmpty
                ? _emptyState()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
                    itemCount: _calls.length,
                    itemBuilder: (context, i) => MotionStagger(
                      index: i,
                      child: _row(_calls[i]),
                    ),
                  ),
      ),
    );
  }

  Widget _row(CallRecord r) {
    final me = supabase.auth.currentUser?.id ?? '';
    final (name, avatar) = _peerOf(r);
    final negative = CallHistoryView.negative(r);
    final tint = negative ? const Color(0xFFEF4444) : WaslColors.teal;
    final answered = r.status == CallStatus.answered || r.status == CallStatus.ended;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.glass,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.hairline),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        onTap: () => _callAgain(r),
        leading: UserAvatar(name: name, url: avatar, radius: 23,
            color: WaslColors.indigo),
        title: Text(name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Row(children: [
          Icon(CallHistoryView.statusIcon(r, me), size: 14, color: tint),
          const SizedBox(width: 5),
          Text(CallHistoryView.statusLabel(r, me),
              style: TextStyle(color: tint, fontSize: 12.5)),
          if (answered) ...[
            const SizedBox(width: 5),
            Text('· ${CallHistoryView.formatDuration(r.duration)}',
                style: TextStyle(color: context.textTertiary, fontSize: 12.5)),
          ],
          const SizedBox(width: 8),
          Icon(callKindIcon(r.kind), size: 13, color: context.textTertiary),
        ]),
        trailing: Text(CallHistoryView.timeLabel(r.createdAt, DateTime.now()),
            style: TextStyle(color: context.textTertiary, fontSize: 11.5)),
      ),
    );
  }

  /// فراغ صادق: المكالمات بدأت — أول مكالمة من شريط أي محادثة خاصة
  Widget _emptyState() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 130),
      children: [
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: WaslColors.gradient,
              boxShadow: [
                BoxShadow(
                  color: WaslColors.indigo.withValues(alpha: 0.35),
                  blurRadius: 38,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: const Icon(Icons.call_outlined, size: 50, color: Colors.white),
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text('لا مكالمات بعد',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'ابدأ أول مكالمة صوتية أو مرئية من شريط\nأي محادثة خاصة — وسيظهر سجلها هنا',
            textAlign: TextAlign.center,
            style: TextStyle(height: 1.7, color: context.textTertiary, fontSize: 13.5),
          ),
        ),
        const SizedBox(height: 26),
        _feature(Icons.mic_none_rounded, WaslColors.indigo, 'اتصال صوتي نقي',
            'الاتصال مباشر بين الجهازين — الصوت لا يعبر أي خادم'),
        _feature(Icons.videocam_outlined, WaslColors.teal, 'مكالمة مرئية',
            'شاهد من تحادثك وجهاً لوجه بجودة تناسب شبكتك'),
        _feature(Icons.lock_outline_rounded, WaslColors.violet, 'تشفير DTLS-SRTP',
            'مفاتيح الوسائط تُتفاوض بين جهازيكما حصراً — لا حتى الخادم'),
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: context.glass,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.hairline),
            ),
            child: Text(
              'بصدق: الإشارة الأولية تعبر خادم وصل، وبعض الشبكات الصارمة\nتحتاج خادم TURN يُعدّه المالك — عندها تظهر «تعذر الاتصال»',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textSecondary, fontSize: 11.5, height: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _feature(IconData icon, Color color, String title, String desc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hairline),
      ),
      child: Row(children: [
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            const SizedBox(height: 3),
            Text(desc,
                style: TextStyle(height: 1.5, color: context.textTertiary, fontSize: 12.5)),
          ]),
        ),
      ]),
    );
  }
}
