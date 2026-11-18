import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/beta_program_service.dart';
import '../services/platform_name.dart';
import '../theme.dart';
import 'feedback_screen.dart';

/// شاشة برنامج الاختبار الميداني (المرحلة 16 — النمو والاستدامة، 1.8.0+70).
///
/// قناة الانضمام لعائِل صادق: ما الذي يُختبر وما الذي لا يزال ناقصاً —
/// وانضمام محلي بلا أي صف خادم، وتقرير اختبار مبني على نظام الملاحظات
/// القائم بتصنيفه نفسه. بوابة إصدار النضج 2.0.0.
class BetaScreen extends StatefulWidget {
  const BetaScreen({super.key});

  @override
  State<BetaScreen> createState() => _BetaScreenState();
}

class _BetaScreenState extends State<BetaScreen> {
  String? _pickedScope;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    BetaProgramService.load().then((_) {
      if (!mounted) return;
      setState(() => _pickedScope = BetaProgramService.scope.value);
    });
  }

  Future<void> _join() async {
    final scopeId = _pickedScope ?? 'all';
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    await BetaProgramService.join(scopeId);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('أنت في برنامج الاختبار — تقرير ملاحظاتك هيأ بقالب مجالك')));
  }

  Future<void> _leave() async {
    setState(() => _busy = true);
    await BetaProgramService.leave();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pickedScope = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('غادرت برنامج الاختبار — ومسحنا أثره المحلي')));
  }

  Future<void> _openTestReport() async {
    final scopeId = BetaProgramService.scope.value ?? 'all';
    final template = BetaProgramService.reportTemplate(
      scopeId: scopeId,
      version: '${AppConfig.appVersion}+${AppConfig.appBuild}',
      platform: devicePlatformLabel(),
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FeedbackScreen(
              initialText: template,
              initialCategory: 'bug',
            )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('برنامج الاختبار الميداني',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800))),
      body: ValueListenableBuilder<bool>(
        valueListenable: BetaProgramService.joined,
        builder: (context, joined, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            _intro(),
            const SizedBox(height: 14),
            _section('ما الذي يُختبر في هذه المرحلة',
                Icons.checklist_rounded, WaslColors.teal, BetaProgramService.whatIsTested),
            const SizedBox(height: 14),
            _section('ما الذي لا يزال ناقصاً — بصدق',
                Icons.info_outline_rounded, const Color(0xFFF59E0B),
                BetaProgramService.whatIsMissing),
            const SizedBox(height: 14),
            if (!joined) _joinCard() else _joinedCard(),
            const SizedBox(height: 14),
            _channelNote(),
          ],
        ),
      ),
    );
  }

  Widget _intro() {
    return Card(
      color: context.surfaceAlt,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.science_outlined, color: WaslColors.violet, size: 24),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'مستخدمو وصل هنا هم من يصنع إصدار النضج 2.0.0: ما يجرّبه هذا البرنامج يُصلَح بأولوية، وكل تقرير يقرؤه فريق وصل حصراً. العائِل بالكامل معروض في هذه الشاشة — لا وعود خلفها.',
              style: TextStyle(fontSize: 13.5, height: 1.55),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<String> points) {
    return Card(
      color: context.surfaceAlt,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(p, style: const TextStyle(fontSize: 12.8, height: 1.5))),
              ]),
            ),
        ]),
      ),
    );
  }

  /// بطاقة الانضمام: اختيار المجال بRadioGroup الحديثة ثم زر انضمام
  Widget _joinCard() {
    return Card(
      elevation: 0,
      color: context.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('انضم واختر مجالك',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _pickedScope,
            onChanged: (v) => setState(() => _pickedScope = v),
            child: Column(children: [
              for (final s in BetaProgramService.scopes)
                RadioListTile<String>(
                  value: s.id,
                  title: Text(s.label,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  subtitle: Text(s.hint, style: const TextStyle(fontSize: 12, height: 1.4)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(BetaProgramService.joinDisclosure,
              style: TextStyle(fontSize: 12, height: 1.5, color: context.textFaint)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _join,
            icon: _busy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.how_to_reg_rounded),
            label: Text(_busy ? 'جارٍ الانضمام…' : 'انضم للاختبار الميداني'),
          ),
        ]),
      ),
    );
  }

  /// بطاقة الحالة بعد الانضمام: المجال والتاريخ والتقرير والمغادرة
  Widget _joinedCard() {
    final s = BetaProgramService.scopeFrom(BetaProgramService.scope.value);
    final at = BetaProgramService.joinedAt;
    return Card(
      elevation: 0,
      color: WaslColors.teal.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.verified_outlined, color: WaslColors.teal, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('أنت في برنامج الاختبار الميداني',
                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
            if (at != null)
              Text(BetaProgramService.joinedAtLabel(at, DateTime.now()),
                  style: TextStyle(fontSize: 11.5, color: context.textFaint)),
          ]),
          const SizedBox(height: 8),
          Text('مجالك: ${s.label} — ${s.hint}',
              style: const TextStyle(fontSize: 12.8, height: 1.5)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _openTestReport,
                icon: const Icon(Icons.rate_review_outlined, size: 19),
                label: const Text('تقرير اختبار'),
              ),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: _busy ? null : _leave,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('مغادرة'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _channelNote() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(BetaProgramService.channelNote,
          style: TextStyle(fontSize: 12, height: 1.5, color: context.textFaint)),
    );
  }
}
