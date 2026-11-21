/// التخطيط الواسع (1.21.0) — بند الخارطة «تخطيط ثنائي الأعمدة للوحات
/// والويندوز الكبير (قائمة + دردشة)»: قواعد نقية وحالة اللوحة المفتوحة.
///
/// العتبة 900dp منطقية: الجوال والتابلت العمودي عمود واحد كما هم، والتابلت
/// الأفقي وسطح المكتب والويب الواسع يفتح الدردشة **بجوار القائمة** لا فوقها.
/// القرار نقية مُختبَرة (`isWide`) والحالة `ValueNotifier` واحدة يصغي لها
/// الغلاف في `home_screen` — وبلا دردشة مفتوحة يعود العمود الواحد صادقاً.
///
/// الحد الصادق: الانقسام يعمل في تبويب المحادثات حصراً (وهو بند الخارطة
/// حرفياً: قائمة + دردشة) — بقية التبويبات تبقى عموداً واحداً كما هي.
library;

import 'package:flutter/foundation.dart';

/// مواصفات دردشة مفتوحة في اللوحة الثانية — مرآة حرفية لمعاملات
/// `ChatScreen` كي يبنيها الغلاف كما فتحها المستخدم من القائمة.
class TwoPaneSpec {
  const TwoPaneSpec({
    required this.conversationId,
    required this.title,
    this.isGroup = false,
    this.otherId,
    this.isChannel = false,
    this.canPost = true,
    this.encrypted = false,
    this.starredOnly = false,
    this.isSaved = false,
    this.isBot = false,
    this.officialVerified = false,
    this.initialAvatar,
  });

  final String conversationId;
  final String title;
  final bool isGroup;
  final String? otherId;
  final bool isChannel;
  final bool canPost;
  final bool encrypted;
  final bool starredOnly;
  final bool isSaved;
  final bool isBot;
  final bool officialVerified;
  final String? initialAvatar;
}

class WideLayoutService {
  WideLayoutService._();

  /// العتبة المعلنة — نفس رقم الخارطة: تحت 900 عمود واحد، من 900 لوحتان
  static const double threshold = 900;

  /// القرار النقي — بلا سياق ولا منصة، يُختبَر على VM مباشرة
  static bool isWide(double width) => width >= threshold;

  /// اللوحة الثانية المفتوحة (null = عمود واحد صادق)
  static final ValueNotifier<TwoPaneSpec?> activeChat =
      ValueNotifier<TwoPaneSpec?>(null);

  /// فتح دردشة في اللوحة الثانية — استبدال ما فتح سابقاً طبيعي
  static void open(TwoPaneSpec spec) => activeChat.value = spec;

  /// إغلاق اللوحة الثانية — من شريط القوقعة
  static void clear() => activeChat.value = null;
}
