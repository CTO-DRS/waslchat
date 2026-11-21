// إعدادات Firebase لمشروع wasl-chat-ac7d3 (أندرويد).
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError('Firebase مُعدّ لأندرويد فقط حالياً');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAbsPINNSb5kg1NTm9fNQ1pjFaMqK6yB1U',
    appId: '1:556011433659:android:96ae8ac5cca4b42227439e',
    messagingSenderId: '556011433659',
    projectId: 'wasl-chat-ac7d3',
    storageBucket: 'wasl-chat-ac7d3.firebasestorage.app',
  );
}
