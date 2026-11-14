import 'package:flutter/material.dart';

import '../services/key_transparency_service.dart';
import '../theme.dart';

String _fpGroups(String fp) {
  if (fp.isEmpty) return '—';
  if (fp.length < 16) return fp.toUpperCase();
  final h = fp.substring(0, 16).toUpperCase();
  return '${h.substring(0, 4)} ${h.substring(4, 8)} ${h.substring(8, 12)} ${h.substring(12, 16)}';
}

String _when(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inDays == 0) return 'اليوم ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'identity_publish':
      return Icons.badge_outlined;
    case 'device_register':
      return Icons.add_moderator_outlined;
    case 'device_remove':
      return Icons.remove_moderator_outlined;
    case 'key_reset':
      return Icons.restart_alt_rounded;
    default:
      return Icons.vpn_key_outlined;
  }
}

Color _kindColor(String kind) {
  switch (kind) {
    case 'device_remove':
      return Colors.redAccent;
    case 'key_reset':
      return Colors.deepOrangeAccent;
    case 'device_register':
      return WaslColors.teal;
    default:
      return WaslColors.indigo;
  }
}

/// سجل مفاتيحي — شفافية المفاتيح (المرحلة 10 ب — 0.25.0، ترحيل 034).
///
/// تاريخ كامل لأحداث مفاتيح الحساب بنُفاذ بسلسلة تجزئة: التطبيق يعيد حساب
/// السلسلة محلياً على جهازك حصراً ويعلن سلامتها أو أول محطة مكسورة — فأي
/// حذف أو تعديل أو إعادة ترتيب صف يكشفه، ولا تحتاج للثقة بمن يقول لك إن
/// التاريخ سليم.
class KeyLogScreen extends StatefulWidget {
  const KeyLogScreen({super.key});

  @override
  State<KeyLogScreen> createState() => _KeyLogScreenState();
}

class _KeyLogScreenState extends State<KeyLogScreen> {
  bool _loading = true;
  List<KeyLogEntry> _rows = const [];
  bool? _chainOk;
  int _brokenAt = -1;
  String? _note;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await KeyTransparencyService.fetch();
    if (rows.isEmpty) {
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _chainOk = null;
        _note = 'السجل فارغ — يبدأ الامتلاء من لحظة تشغيل الترحيل 034 وتحديث التطبيق؛ التاريخ قبل 0.25.0 غير مسجَّل (موثق بصدق). إن كنت قد شغّلت الترحيل وتحديثت فافتح الشاشة مرة أخرى بعد أول تغيير مفاتيح.';
        _loading = false;
      });
      return;
    }
    final (ok, at) = await KeyTransparencyService.verifyChain(rows);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _chainOk = ok;
      _brokenAt = at;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل مفاتيحي'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Card(
                  color: context.surfaceAlt,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'كل حدث يغير مفاتيح حسابك — نشر الهوية، تسجيل جهاز، إزالة جهاز، مفتاح جديد — يُلحَّص هنا ببصمة المفتاح وسلسلة تجزئة: كل صف يحمل تجزئة الصف قبله، فأي حذف أو تعديل أو إعادة ترتيب في التاريخ يكسر السلسلة. التحقق يجري على جهازك حصراً — لا نطلب منك الثقة بمن يقول إن التاريخ سليم.',
                      style: const TextStyle(height: 1.6),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_chainOk == true)
                  Card(
                    color: Colors.teal.withValues(alpha: 0.10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: const ListTile(
                      leading: Icon(Icons.verified_user_rounded,
                          color: Colors.teal),
                      title: Text('السلسلة سليمة — التاريخ كامل بلا عبث',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          'أُعيد حساب كل تجزئة محلياً وتطابقت مع الخادم حرفياً'),
                    ),
                  ),
                if (_chainOk == false)
                  Card(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                      leading: const Icon(Icons.gpp_bad_rounded,
                          color: Colors.redAccent),
                      title: const Text(
                          'السلسلة مكسورة — التاريخ لم يعد مكتملًا كما أُلحِح',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, height: 1.4)),
                      subtitle: Text(
                          'أول محطة مكسورة: الحدث رقم ${_brokenAt + 1} من ${_rows.length} — عبث جزئي أو حذف أو تعديل. راجع أجهزتك والتحقق QR مع أطرافك، وأبلغ إن لم تدخل أنت التغيير.',
                          style: const TextStyle(height: 1.5)),
                    ),
                  ),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_note!,
                        style: const TextStyle(height: 1.6, fontSize: 13)),
                  ),
                const SizedBox(height: 6),
                for (var i = 0; i < _rows.length; i++)
                  _entryTile(_rows[i], i),
                const SizedBox(height: 12),
                const Text(
                  'حدود صادقة: السجل مُستضاف على خادم وصل نفسه — من يستطيع إعادة كتابة القاعدة كلها يستطيع نظرياً بناء سلسلة كاذبة متسقة (الشفافية الكاملة ب شهود خارجيين بعد 1.0). ما يكشفه السجل اليوم: أي عبث جزئي — حذف حدث، تعديل بصمة، إعادة ترتيب، استبدال تاريخي.',
                  style: TextStyle(height: 1.6, fontSize: 12.5),
                ),
              ],
            ),
    );
  }

  Widget _entryTile(KeyLogEntry e, int index) {
    final broken = _chainOk == false && _brokenAt == index;
    return Card(
      color: broken ? Colors.redAccent.withValues(alpha: 0.08) : context.surfaceAlt,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: broken
              ? const BorderSide(color: Colors.redAccent)
              : BorderSide.none),
      child: ListTile(
        leading: Icon(_kindIcon(e.kind), color: _kindColor(e.kind), size: 26),
        title: Text(
          '${index + 1}. ${KeyTransparencyService.kindLabel(e.kind)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${KeyTransparencyService.kindDetail(e.kind)}\n'
          'بصمة المفتاح ${_fpGroups(e.fingerprint)}'
          '${e.deviceId == null ? '' : ' · جهاز …${e.deviceId!.substring(e.deviceId!.length > 8 ? e.deviceId!.length - 8 : 0)}'}\n'
          '${_when(e.createdAtIso)}',
          style: const TextStyle(height: 1.5, fontSize: 12.5),
        ),
        isThreeLine: true,
      ),
    );
  }
}
