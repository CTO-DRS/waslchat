import 'package:flutter/material.dart';

/// مفتاح التنقّل الجذري للتطبيق — مشترك بين main.dart والخدمات
/// (مثل عرض اللافتة الداخلية للإشعارات فوق أي شاشة مفتوحة).
final navigatorKey = GlobalKey<NavigatorState>();
