import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/bot_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// شاشة «البوتات وواجهة المطوّرين» (المرحلة 4):
/// إنشاء بوتات، رمز الواجهة (يظهر مرة واحدة)، الويب هوك الموقّع،
/// إضافة البوت للمجموعات والقنوات، ومحادثة مباشرة معه.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key});

  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bots = await BotService.list();
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _create() async {
    if (_bots.length >= BotService.maxPerOwner) {
      _snack('الحد الأقصى ${BotService.maxPerOwner} بوتات لكل حساب');
      return;
    }
    final nameCtrl = TextEditingController();
    final userCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final created = await showDialog<(String, String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceAlt,
        title: const Text('بوت جديد'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: nameCtrl,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'اسم البوت الظاهر'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'اكتب اسم البوت' : null,
              ),
              TextFormField(
                controller: userCtrl,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    hintText: 'مثال: store_helper',
                    suffixText: '_bot'),
                validator: (v) => BotService.usernameError(
                    '${BotService.normalizeUsername(v ?? '')}_bot'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: descCtrl,
                maxLength: 300,
                decoration:
                    const InputDecoration(labelText: 'وصف قصير (اختياري)'),
              ),
              const SizedBox(height: 8),
              Text('رابط الويب هوك ورمز الواجهة تضبطهما من تفاصيل البوت بعد الإنشاء.',
                  style: TextStyle(fontSize: 12, color: context.textTertiary)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, (
                nameCtrl.text.trim(),
                '${BotService.normalizeUsername(userCtrl.text)}_bot',
                descCtrl.text.trim(),
              ));
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    userCtrl.dispose();
    descCtrl.dispose();
    if (created == null) return;
    try {
      final (_, token) = await BotService.create(
        name: created.$1,
        username: created.$2,
        description: created.$3.isEmpty ? null : created.$3,
        webhookUrl: null,
      );
      await _load();
      if (!mounted) return;
      _showTokenOnce(token, firstTime: true);
    } catch (e) {
      _snack(BotService.errorLabel(e));
    }
  }

  /// عرض رمز الواجهة مرة واحدة — بعد إغلاق الورقة لا يُعرض أبداً
  Future<void> _showTokenOnce(String token, {bool firstTime = false}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(firstTime ? 'رمز بوتك الجديد' : 'الرمز الجديد'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              firstTime
                  ? 'هذه هي المرة الوحيدة التي يظهر فيها الرمز. احفظه الآن في مكان آمن:'
                  : 'الرمز القديم أُلغي فوراً. هذا هو الرمز الجديد — يظهر مرة واحدة:',
              style: const TextStyle(height: 1.6)),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.glass,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(token,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              Navigator.pop(context);
              _snack('نُسخ الرمز — احفظه الآن، لن يظهر مجدداً');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ وحفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _openBotChat(String botId) async {
    try {
      final convId = await BotService.startChat(botId);
      if (!mounted) return;
      final bot = _bots.firstWhere((b) => b['id'] == botId, orElse: () => {});
      final title = (bot['name'] ?? 'بوت') as String;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId,
            title: title,
            isGroup: false,
            otherId: botId,
            isBot: true,
            encrypted: false,
          ),
        ),
      );
      _load();
    } catch (e) {
      _snack(BotService.errorLabel(e));
    }
  }

  Future<void> _addToChat(String botId) async {
    // المجموعات والقنوات المستقلة التي أنا مشرفها (غرف المجتمعات تُدار ببوتات مجتمعها لاحقاً)
    List<Map<String, dynamic>> targets;
    try {
      final parts = await supabase
          .from('conversation_participants')
          .select('conversation_id, role')
          .eq('user_id', supabase.auth.currentUser!.id);
      final ids = [
        for (final r in List<Map<String, dynamic>>.from(parts))
          if (r['role'] == 'owner' || r['role'] == 'admin')
            r['conversation_id'] as String
      ];
      targets = const [];
      if (ids.isNotEmpty) {
        final convs = await supabase
            .from('conversations')
            .select('id, title, kind, is_group, community_id')
            .inFilter('id', ids);
        targets = [
          for (final c in List<Map<String, dynamic>>.from(convs))
            if (c['community_id'] == null &&
                ((c['kind'] == 'chat' && c['is_group'] == true) ||
                    c['kind'] == 'channel'))
              {'id': c['id'], 'title': c['title'] ?? 'مجموعة'}
        ];
      }
    } catch (_) {
      _snack('تعذّر تحميل المحادثات');
      return;
    }
    if (!mounted) return;
    final target = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.5,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('إضافة البوت إلى…',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: targets.isEmpty
                  ? Center(
                      child: Text('لا توجد مجموعات أو قنوات أنت مشرفها',
                          style: TextStyle(color: ctx.textTertiary)))
                  : ListView(children: [
                      for (final t in targets)
                        ListTile(
                          leading: const Icon(Icons.group_outlined, color: WaslColors.teal),
                          title: Text((t['title'] ?? '') as String),
                          onTap: () => Navigator.pop(ctx, t),
                        ),
                    ]),
            ),
          ]),
        ),
      ),
    );
    if (target == null) return;
    try {
      await BotService.addToChat(botId, target['id'] as String);
      _snack('أُضيف البوت إلى ${target['title']}');
    } catch (e) {
      _snack(BotService.errorLabel(e));
    }
  }

  Future<void> _details(Map<String, dynamic> bot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surfaceAlt,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _BotDetailsSheet(
        bot: bot,
        onChanged: _load,
        onAddToChat: () {
          Navigator.pop(ctx);
          _addToChat(bot['id'] as String);
        },
        onOpenChat: () {
          Navigator.pop(ctx);
          _openBotChat(bot['id'] as String);
        },
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البوتات وواجهة المطوّرين')),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: WaslFab(onPressed: _create, icon: Icons.smart_toy_outlined),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 140),
                children: [
                  Material(
                    color: context.glass,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                          'البوتات حسابات آلية تعمل عبر واجهة برمجية موقّعة. '
                          'في القنوات وغرف المجتمعات تقرأ الرسائل مباشرة، وفي '
                          'المجموعات الخاصة المشفرة يصلها النص مشفراً لا يفكّه، '
                          'ومحادثتها المباشرة غير مشفرة طرف-لطرف لأن البوت نفسه يقرأها.',
                          style: TextStyle(height: 1.7, color: context.textSecondary, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_bots.isEmpty)
                    const GlassEmptyState(
                      icon: Icons.smart_toy_outlined,
                      title: 'لا توجد بوتات بعد',
                      subtitle: 'أنشئ أول بوت لك بزر + واربطه بخادمك عبر Webhook',
                    ),
                  for (final b in _bots)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: WaslColors.violet.withValues(alpha: 0.18),
                        child: Icon(Icons.smart_toy_outlined,
                            color: b['is_active'] == true
                                ? WaslColors.violet
                                : context.textFaint),
                      ),
                      title: Row(children: [
                        Flexible(child: Text((b['name'] ?? '') as String,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700))),
                        const SizedBox(width: 4),
                        Text('@${b['username']}',
                            style: TextStyle(color: context.textTertiary, fontSize: 12)),
                      ]),
                      subtitle: Text(
                          b['is_active'] == true
                              ? ((b['webhook_url'] as String?)?.isNotEmpty == true
                                  ? 'نشط · Webhook موصول'
                                  : 'نشط · بلا Webhook')
                              : 'معطّل',
                          style: TextStyle(
                              color: b['is_active'] == true
                                  ? WaslColors.teal
                                  : context.textFaint,
                              fontSize: 12.5)),
                      onTap: () => _details(b),
                    ),
                ],
              ),
            ),
    );
  }
}

/// ورقة تفاصيل البوت: التفعيل، الرمز، الويب هوك، الإضافة لمحادثة، الحذف
class _BotDetailsSheet extends StatefulWidget {
  const _BotDetailsSheet({
    required this.bot,
    required this.onChanged,
    required this.onAddToChat,
    required this.onOpenChat,
  });
  final Map<String, dynamic> bot;
  final VoidCallback onChanged;
  final VoidCallback onAddToChat;
  final VoidCallback onOpenChat;

  @override
  State<_BotDetailsSheet> createState() => _BotDetailsSheetState();
}

class _BotDetailsSheetState extends State<_BotDetailsSheet> {
  late bool _active = widget.bot['is_active'] == true;
  bool _busy = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _resetToken() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تجديد رمز الواجهة؟'),
        content: const Text('الرمز القديم يُلغى فوراً ويتوقف أي سكربت يستخدمه حتى تحدّثه.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تجديد')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final t = await BotService.resetToken(widget.bot['id'] as String);
      if (!mounted) return;
      Navigator.pop(context);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('الرمز الجديد — يظهر مرة واحدة'),
          content: SelectableText(t, style: const TextStyle(fontFamily: 'monospace')),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: t));
                Navigator.pop(ctx);
              },
              child: const Text('نسخ'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack(BotService.errorLabel(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setWebhook() async {
    final ctrl = TextEditingController(text: (widget.bot['webhook_url'] ?? '') as String);
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: context.surfaceAlt,
        title: const Text('رابط Webhook'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'https://example.com/wasl'),
          ),
          const SizedBox(height: 10),
          Text('تصلك رسائل المحادثات التي يشارك فيها البوت إلى هذا الرابط '
                  'موقّعة بترويسة X-Wasl-Signature بسرّ مخصص لا يُشارك مع الرمز.',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: context.textTertiary)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(c, ''),
              child: const Text('مسح الرابط')),
          FilledButton(
            onPressed: () {
              final err = BotService.webhookError(ctrl.text);
              if (err != null) {
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(err)));
                return;
              }
              Navigator.pop(c, ctrl.text.trim());
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url == null) return;
    setState(() => _busy = true);
    try {
      final secret = await BotService.setWebhook(widget.bot['id'] as String, url);
      if (!mounted) return;
      if (secret != null) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('سرّ توقيع الويب هوك'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('تحقّق من توقيع كل طلب وصول إليك بهذا السر:'),
              const SizedBox(height: 10),
              SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
            ]),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: secret));
                  Navigator.pop(ctx);
                },
                child: const Text('نسخ'),
              ),
            ],
          ),
        );
      } else {
        _snack('مُسح رابط الويب هوك');
      }
    } catch (e) {
      _snack(BotService.errorLabel(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showSecret() async {
    final secret = (widget.bot['webhook_secret'] ?? '') as String;
    if (secret.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('سرّ توقيع الويب هوك'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('X-Wasl-Signature: sha256=HMAC(جسم الطلب، هذا السرّ)'),
          const SizedBox(height: 10),
          SelectableText(secret, style: const TextStyle(fontFamily: 'monospace')),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: secret));
              Navigator.pop(ctx);
            },
            child: const Text('نسخ'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف البوت نهائياً؟'),
        content: const Text('يُحذف حسابه ورسائله وعضوياته ولا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BotService.remove(widget.bot['id'] as String);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onChanged();
    } catch (e) {
      _snack(BotService.errorLabel(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bot;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((b['name'] ?? '') as String,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text('@${b['username']}',
                    style: TextStyle(color: context.textTertiary, fontSize: 13)),
                if ((b['description'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(b['description'] as String,
                        style: TextStyle(fontSize: 13, color: context.textSecondary)),
                  ),
              ]),
            ),
            Switch(
              value: _active,
              // توافق 3.47.9+: activeColor مهجورة بعد 3.31 والبديل activeThumbColor متاح في الإصدارين
              activeThumbColor: WaslColors.teal,
              onChanged: _busy
                  ? null
                  : (v) async {
                      setState(() => _active = v);
                      try {
                        await BotService.setActive(b['id'] as String, v);
                      } catch (e) {
                        setState(() => _active = !v);
                        _snack(BotService.errorLabel(e));
                      }
                    },
            ),
          ]),
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.key_rounded, color: WaslColors.violet),
            title: const Text('تجديد رمز الواجهة'),
            subtitle: Text('ينتهي بـ …${b['token_tail']}',
                style: TextStyle(color: context.textTertiary, fontSize: 12)),
            onTap: _busy ? null : _resetToken,
          ),
          ListTile(
            leading: const Icon(Icons.webhook_rounded, color: WaslColors.teal),
            title: const Text('رابط الويب هوك'),
            subtitle: Text(
                (b['webhook_url'] as String?)?.isNotEmpty == true
                    ? b['webhook_url'] as String
                    : 'غير موصول — الرسائل لا تُرسل لأي خادم',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.textTertiary, fontSize: 12)),
            onTap: _busy ? null : _setWebhook,
          ),
          if ((b['webhook_url'] as String?)?.isNotEmpty == true)
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded, color: WaslColors.indigo),
              title: const Text('سرّ التوقيع'),
              onTap: _showSecret,
            ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline_rounded, color: WaslColors.teal),
            title: const Text('إضافة إلى مجموعة أو قناة أنت مشرفها'),
            onTap: _busy ? null : widget.onAddToChat,
          ),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline_rounded, color: WaslColors.indigo),
            title: const Text('محادثة البوت مباشرة'),
            subtitle: Text('غير مشفرة طرف-لطرف — البوت يقرأها عبر واجهته',
                style: TextStyle(color: context.textFaint, fontSize: 12)),
            onTap: _busy ? null : widget.onOpenChat,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            title: const Text('حذف البوت', style: TextStyle(color: Colors.redAccent)),
            onTap: _busy ? null : _delete,
          ),
        ]),
      ),
    );
  }
}
