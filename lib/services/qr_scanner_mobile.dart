import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// صفحة مسح رمز QR بالكاميرا — تعيد نص أول رمز مقروء أو null عند الإلغاء.
class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('امسح رمز الطرف الآخر'),
        backgroundColor: Colors.black,
      ),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v == null || v.isEmpty) continue;
              _done = true;
              Navigator.of(context).pop(v);
              return;
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'تعذّر تشغيل الكاميرا. تأكد من منح صلاحية الكاميرا للتطبيق ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), height: 1.6),
              ),
            ),
          ),
        ),
        // إطار إرشادي
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
                'وجّه الكاميرا نحو رمز QR الظاهر في شاشة «رمز الأمان» عند الطرف الآخر',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.85))),
          ),
        ),
      ]),
    );
  }
}

/// يفتح صفحة المسح ويعيد نص الرمز أو null
Future<String?> scanQrCode(BuildContext context) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScannerPage()),
    );
