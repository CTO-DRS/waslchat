import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/e2e_service.dart';
import '../services/qr_scanner.dart';
import '../theme.dart';

const _verifiedGreen = Color(0xFF2FBE63);

/// التحقق من رمز الأمان بمسح QR — يوثّق مفتاح الطرف الآخر محلياً على هذا الجهاز.
/// التوثيق لا يُرفع للخادم، ويتلغى تلقائياً إذا غيّر الطرف مفتاحه.
class VerifyQrScreen extends StatefulWidget {
  const VerifyQrScreen({super.key, required this.otherUserId});
  final String otherUserId;

  @override
  State<VerifyQrScreen> createState() => _VerifyQrScreenState();
}

class _VerifyQrScreenState extends State<VerifyQrScreen> {
  String? _payload;
  String? _safety;
  bool _verified = false;
  bool _changed = false;
  bool _busy = false;
  bool _showDigits = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final payload = await E2eService.myVerifyPayload();
    final safety = await E2eService.safetyNumber(widget.otherUserId);
    final verified = await E2eService.isVerified(widget.otherUserId);
    final changed = E2eService.peerKeyChanged(widget.otherUserId);
    if (!mounted) return;
    setState(() {
      _payload = payload;
      _safety = safety;
      _verified = verified;
      _changed = changed;
    });
  }

  Future<void> _doneDialog(bool ok, String title, String body) =>
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Row(children: [
            Icon(ok ? Icons.verified_rounded : Icons.gpp_bad_rounded,
                color: ok ? _verifiedGreen : Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17))),
          ]),
          content: Text(body, style: const TextStyle(height: 1.6)),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: const Text('حسناً'))
          ],
        ),
      );

  Future<void> _scan() async {
    final raw = await scanQrCode(context);
    if (raw == null || !mounted) return;
    setState(() => _busy = true);
    final result =
        await E2eService.applyScannedVerify(raw, widget.otherUserId);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (result) {
      case VerifyScanResult.verified:
        await _doneDialog(
            true,
            'تم التوثيق بنجاح',
            'رمزا الأمان متطابقان، ومفتاح الطرف الآخر أصبح موثوقاً على هذا الجهاز. ستظهر علامة توثيق خضراء في شريط المحادثة.');
      case VerifyScanResult.mismatch:
        await _doneDialog(
            false,
            'تحذير أمني: لا توثّق',
            'المفتاح الموجود في الرمز الممسوح لا يطابق المفتاح المنشور لحساب هذا الشخص على الخادم. قد يكون الرمز مزيّفاً — تأكد من الطرف الآخر بطريقة موثوقة أخرى قبل أي توثيق.');
      case VerifyScanResult.foreign:
        await _doneDialog(false, 'رمز لحساب آخر',
            'الرمز الممسوح يعود لحساب مختلف عن محادثتك الحالية. افتح محادثة الشخص الصحيح ثم امسح رمزه من هناك.');
      case VerifyScanResult.invalid:
        await _doneDialog(false, 'رمز غير صالح',
            'ما تم مسحه ليس رمز تحقق من وصل شات.');
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final (statusIcon, statusColor, statusText) = _changed
        ? (
            Icons.warning_amber_rounded,
            Colors.amber,
            'تغيّر مفتاح هذا الشخص مؤخراً — تحقق منه قبل المواصلة'
          )
        : _verified
            ? (
                Icons.verified_rounded,
                _verifiedGreen,
                'موثّق: مفتاح هذا الشخص موثوق على جهازك'
              )
            : (
                Icons.verified_user_outlined,
                WaslColors.teal,
                'غير موثّق بعد: امسح رمز الطرف الآخر للتأكد من عدم وجود وسيط'
              );
    return Scaffold(
      appBar: AppBar(title: const Text('التحقق من رمز الأمان')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        // بطاقة الحالة
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: context.glass, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Icon(statusIcon, color: statusColor, size: 30),
            const SizedBox(width: 12),
            Expanded(
                child: Text(statusText,
                    style: const TextStyle(height: 1.5, fontSize: 14.5))),
          ]),
        ),
        const SizedBox(height: 20),
        // رمز QR الخاص بي
        Card(
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text('رمز QR الخاص بك',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('اعرض هذا الرمز على الطرف الآخر ليمسحه من شاشة رمز الأمان لديه',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, height: 1.5)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: _payload == null
                    ? const SizedBox(
                        width: 200,
                        height: 200,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : QrImageView(data: _payload!, size: 210),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        // مسح رمز الطرف الآخر
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          icon: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('مسح رمز الطرف الآخر'),
        ),
        if (_verified) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              await E2eService.unverify(widget.otherUserId);
              if (mounted) _refresh();
            },
            icon: const Icon(Icons.gpp_maybe_outlined, size: 20),
            label: const Text('إلغاء التوثيق'),
          ),
        ],
        const SizedBox(height: 12),
        // المقارنة الرقمية كخيار احتياطي
        TextButton.icon(
          onPressed: () => setState(() => _showDigits = !_showDigits),
          icon: Icon(_showDigits
              ? Icons.expand_less_rounded
              : Icons.pin_outlined),
          label: const Text('أو قارن رمز الأمان الرقمي (60 خانة)'),
        ),
        if (_showDigits && _safety != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: context.glass, borderRadius: BorderRadius.circular(14)),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(_safety!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      letterSpacing: 1.2,
                      height: 1.7)),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'التوثيق محفوظ على جهازك فقط ولا يُرفع للخادم، ويتلغى تلقائياً إذا غيّر الطرف مفتاحه وسيظهر لك تنبيه حينها.',
          style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
    );
  }
}
