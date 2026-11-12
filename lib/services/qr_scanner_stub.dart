import 'package:flutter/material.dart';

/// بديل الويب: مسح الكاميرا غير مفعّل هنا — رسالة تعتمد المقارنة اليدوية لرمز الأمان.
Future<String?> scanQrCode(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('المسح غير متاح على الويب'),
      content: const Text(
          'كاميرا المسح تعمل على تطبيق الجوال. على الويب قارن رقمي رمز الأمان وجهاً لوجه أو بمكالمة، أو افتح وصل شات من جوالك وامسح الرمز هناك.',
          style: TextStyle(height: 1.6)),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
      ],
    ),
  );
  return null;
}
