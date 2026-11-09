import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
// يُستخدم هنا لفتح إعدادات التطبيق فقط عند رفض الإذن نهائياً —
// openAppSettings دالة عامة تفتح صفحة إعدادات التطبيق (بلا علاقة بالموقع)
import 'package:geolocator/geolocator.dart' show Geolocator;

import '../services/contact_card_service.dart';
import '../theme.dart';
/// منتقي بطاقة جهة اتصال (0.4.6 — بند المرحلة 1).
///
/// يقرأ دفتر الجهاز محلياً (إذن قراءة فقط — لا مزامنة ولا رفع)،
/// ويعرض قائمة ببحث فوري، ثم اختيار الأرقام المطلوبة (وبريد اختياري)
/// ويعيد [ContactCard] للإرسال المشفّر.
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet({super.key, required this.encrypted});

  /// هل هذه المحادثة مشفّرة بين الطرفين؟ (لعرض الحالة الصادقة)
  final bool encrypted;

  /// يفتح المنتقي ويعيد [ContactCard] أو null إن أُلغي
  static Future<ContactCard?> show(BuildContext context,
          {required bool encrypted}) =>
      showModalBottomSheet<ContactCard>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.wasl.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => ContactPickerSheet(encrypted: encrypted),
      );

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  bool _loading = true;
  String? _error;
  bool _denied = false;
  List<Contact> _contacts = [];
  String _query = '';

  // الاختيار الحالي
  Contact? _picked;
  final Set<String> _phones = {};
  final Set<String> _emails = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _denied = false;
    });
    try {
      if (!await FlutterContacts.requestPermission(readonly: true)) {
        setState(() {
          _loading = false;
          _denied = true;
          _error = 'إذن جهات الاتصال مرفوض — اسمح به لاختيار بطاقة';
        });
        return;
      }
      // أسماء وأرقام وبريد فقط — بلا صور ولا حقول أخرى (أدنى قراءة)
      final list = await FlutterContacts.getContacts(
          withProperties: true, withPhoto: false);
      list.sort((a, b) => a.displayName.compareTo(b.displayName));
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذّرت قراءة جهات الاتصال';
      });
    }
  }

  List<Contact> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _contacts;
    return _contacts.where((c) {
      final name = c.displayName.toLowerCase();
      if (name.contains(q)) return true;
      return c.phones.any((p) => p.number.replaceAll(' ', '').contains(q));
    }).toList();
  }

  void _pick(Contact c) {
    setState(() {
      _picked = c;
      _phones
        ..clear()
        ..addAll(c.phones.map((p) => p.number));
      _emails
        ..clear()
        ..addAll(c.emails.map((e) => e.address));
    });
  }

  void _send() {
    final c = _picked;
    if (c == null || _phones.isEmpty) return;
    try {
      final card = ContactCardService.encode(
        name: c.displayName,
        phones: _phones.toList(),
        emails: _emails.toList(),
      );
      if (!ContactCardService.withinLimit(card)) {
        setState(() => _error = 'البطاقة كبيرة — قلّل الأرقام المختارة');
        return;
      }
      Navigator.pop(
          context,
          ContactCard(
            name: c.displayName,
            phones: _phones.toList(),
            emails: _emails.toList(),
          ));
    } catch (_) {
      setState(() => _error = 'تحقق من الأرقام المختارة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final wasl = context.wasl;
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Icon(Icons.person_add_alt_1_rounded, color: wasl.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text('مشاركة جهة اتصال',
                    style: TextStyle(
                        color: wasl.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                widget.encrypted
                    ? 'الاسم والأرقام تُشفَّر قبل رفعها — القراءة من جهازك فقط'
                    : '⚠️ هذه القناة غير مشفّرة — البطاقة ستكون صريحة فيها',
                style: TextStyle(
                    color: widget.encrypted ? wasl.textFaint : wasl.danger,
                    fontSize: 12),
              ),
            ),
          ),
          if (_picked == null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'ابحث بالاسم أو الرقم…',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: _buildList(wasl),
            ),
          ] else ...[
            Flexible(child: _buildChoose(wasl)),
          ],
        ]),
      ),
    );
  }

  Widget _buildList(WaslPalette wasl) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: wasl.danger, fontSize: 14)),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (_denied)
              OutlinedButton.icon(
                onPressed: Geolocator.openAppSettings,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('الإعدادات'),
              ),
            const SizedBox(width: 10),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة'),
            ),
          ]),
        ]),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(30),
        child: Text('لا نتائج في دفتر جهات الاتصال',
            style: TextStyle(color: wasl.textFaint)),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final c = list[i];
        final phones = c.phones.map((p) => p.number).where((p) => p.isNotEmpty).toList();
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: wasl.violetSoft,
            child: Text(
              ContactCardService.initials(c.displayName),
              style: TextStyle(
                  color: wasl.textPrimary, fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(c.displayName,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: phones.isEmpty
              ? const Text('بلا أرقام هاتف')
              : Text(phones.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr),
          onTap: phones.isEmpty ? null : () => _pick(c),
        );
      },
    );
  }

  /// خطوة اختيار الأرقام بعد التقاط جهة الاتصال
  Widget _buildChoose(WaslPalette wasl) {
    final c = _picked!;
    final phones = c.phones.map((p) => p.number).where((p) => p.isNotEmpty).toList();
    final emails = c.emails.map((e) => e.address).where((e) => e.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CircleAvatar(
            backgroundColor: wasl.violetSoft,
            child: Text(ContactCardService.initials(c.displayName),
                style: TextStyle(
                    color: wasl.textPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(c.displayName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ),
          IconButton(
            tooltip: 'رجوع',
            onPressed: () => setState(() {
              _picked = null;
              _error = null;
            }),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ]),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text('اختر ما سيُشارك (رقم واحد على الأقل)',
              style: TextStyle(color: wasl.textFaint, fontSize: 12)),
        ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(children: [
              for (final p in phones)
                CheckboxListTile(
                  dense: true,
                  value: _phones.contains(p),
                  onChanged: (v) => setState(() {
                    v == true ? _phones.add(p) : _phones.remove(p);
                  }),
                  title: Text(p,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 14)),
                  secondary: const Icon(Icons.call_outlined, size: 18),
                ),
              for (final e in emails)
                CheckboxListTile(
                  dense: true,
                  value: _emails.contains(e),
                  onChanged: (v) => setState(() {
                    v == true ? _emails.add(e) : _emails.remove(e);
                  }),
                  title: Text(e,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 14)),
                  secondary: const Icon(Icons.mail_outline_rounded, size: 18),
                ),
            ]),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(_error!,
                  style: TextStyle(color: wasl.danger, fontSize: 13)),
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _phones.isEmpty ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text('إرسال البطاقة (${_phones.length + _emails.length} قيمة)'),
          ),
        ),
        const SizedBox(height: 8),
      ]),
    );
  }
}
