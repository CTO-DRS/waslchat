/// بديل غير الويب لإشعارات المتصفح: أندرويد/iOS/سطح المكتب إشعاراتها عبر
/// PushService (FCM وflutter_local_notifications) — لا PushManager هنا.
import 'package:flutter/foundation.dart';

final ValueNotifier<String> _status =
    ValueNotifier<String>('لا يطبق — هذه المنصة إشعاراتها عبر FCM');
final ValueNotifier<bool> _subscribed = ValueNotifier<bool>(false);
final ValueNotifier<String> _permission =
    ValueNotifier<String>('لا يطبق — منصة أصلية');

class WebPushService {
  static ValueNotifier<String> get status => _status;
  static ValueNotifier<bool> get subscribed => _subscribed;
  static ValueNotifier<String> get permission => _permission;
  static bool get ready => false;

  static void init() {}

  static Future<bool> enable() async => false;

  static Future<void> disable() async {}
}
