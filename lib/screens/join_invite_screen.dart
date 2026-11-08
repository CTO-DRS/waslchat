import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../theme.dart';
import 'chat_screen.dart';

/// شاشة الانضمام إلى مجموعة برمز دعوة (المرحلة 1: روابط دعوة المجموعات).
/// تُفتح من «محادثة جديدة» أو من رابط عميق app.waslchat://join/CODE.
class JoinInviteScreen extends StatefulWidget {
  const JoinInviteScreen({super.key, this.initialCode});
  final String? initialCode;

  @override
  State<JoinInviteScreen> createState() => _JoinInviteScreenState();
}

class _JoinInviteScreenState extends State<JoinInviteScreen> {
  final _code = TextEditingController();
  Map<String, dynamic>? _preview; // {title, members}
  bool _checking = false;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCode;
    if (initial != null && initial.trim().isNotEmpty) {
      _code.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// معاينة الرمز: اسم المجموعة وعدد الأعضاء قبل الانضمام
  Future<void> _check() async {
    final c = _code.text.trim().toUpperCase();
    if (c.isEmpty || _checking || _joining) return;
    setState(() {
      _checking = true;
      _error = null;
      _preview = null;
    });
    try {
      final rows = await supabase
          .rpc('group_invite_preview', params: {'p_code': c}) as List;
      if (!mounted) return;
      if (rows.isNotEmpty) {
        setState(
            () => _preview = Map<String, dynamic>.from(rows.first as Map));
      } else {
        setState(() => _error = 'رمز الدعوة غير صالح أو مُبطل');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذّر التحقق من الرمز');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// الانضمام الفعلي ثم فتح المحادثة
  Future<void> _join() async {
    final p = _preview;
    if (p == null || _joining) return;
    setState(() => _joining = true);
    try {
      final convId = await supabase.rpc('group_join_by_invite',
          params: {'p_code': _code.text.trim()});
      if (!mounted) return;
      _snack('تم الانضمام إلى «${p['title'] ?? 'المجموعة'}»');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId as String,
            title: (p['title'] ?? 'مجموعة') as String,
            isGroup: true,
            encrypted: true,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = e.toString().contains('invalid invite')
              ? 'رمز الدعوة غير صالح أو مُبطل'
              : 'تعذّر الانضمام — حاول مجدداً';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('الانضمام إلى مجموعة')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.group_add_rounded,
              size: 64, color: context.wasl.accent),
          const SizedBox(height: 12),
          Text('أدخل رمز الدعوة الذي أرسله لك صاحب المجموعة',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.wasl.textSecondary)),
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(10),
            ],
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                letterSpacing: 3,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: 'XXXXXXXXXX',
              counterText: '',
              suffixIcon: IconButton(
                  tooltip: 'تحقق من الرمز',
                  icon: const Icon(Icons.check_circle_outline),
                  onPressed: _checking ? null : _check),
            ),
            onSubmitted: (_) => _check(),
            maxLength: 10,
          ),
          const SizedBox(height: 12),
          if (_checking) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.wasl.danger)),
            ),
          if (p != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.wasl.glass,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: WaslColors.teal,
                  child: Icon(Icons.groups_2, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 10),
                Text((p['title'] ?? '') as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${p['members'] ?? 0} أعضاء',
                    style: TextStyle(color: context.wasl.textFaint)),
                const SizedBox(height: 12),
                Text(
                  'ستقرأ الرسائل الجديدة بعد أن يُدار مفتاح التشفير تلقائياً '
                  'لأول مرة تُفتح فيها المجموعة، ولن ترى الرسائل القديمة.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: context.wasl.textFaint),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _joining ? null : _join,
                icon: _joining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login_rounded),
                label: Text(_joining ? 'جارٍ الانضمام…' : 'انضم الآن'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
