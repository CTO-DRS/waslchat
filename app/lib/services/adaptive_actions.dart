import 'package:flutter/material.dart';

/// محرك الإجراءات التكيفية (2.2.0) — Violet Adaptive Actions
/// يحدد الإجراءات المناسبة حسب نوع الرسالة وصلاحياتها، ويحلل النص محلياً
/// (بلا خادم ولا تنفيذ تلقائي) ليقترح إجراءات سياقية حقيقية فقط.
class AdaptiveAction {
  const AdaptiveAction(this.id, this.icon, this.label);
  final String id;
  final IconData icon;
  final String label;
}

class ContextSuggestion {
  const ContextSuggestion(this.kind, this.icon, this.label, this.value);
  final String kind; // call | email | link | reply
  final IconData icon;
  final String label;
  final String value;
}

/// سرعة تشغيل الصوتيات — مشتركة بين شريط الإجراءات وفقاعة الصوت
class VoiceRateService {
  VoiceRateService._();
  static const rates = [1.0, 1.5, 2.0];
  static double rate = 1.0;
  static void cycle() {
    final i = rates.indexOf(rate);
    rate = rates[(i + 1) % rates.length];
  }
}

class AdaptiveActions {
  AdaptiveActions._();

  static String kindOf(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return 'deleted';
    return m['type'] as String? ?? 'text';
  }

  /// الترتيب ديناميكي: الأنسب للنوع أولاً — «المزيد» يضيفه الشريط دائماً.
  /// الإجراءات تُقدَّم كرغبات؛ الشريط يرشّحها بصلاحيات الشاشة قبل العرض.
  static List<AdaptiveAction> actionsFor({
    required String kind,
    required bool mine,
    required bool canPost,
  }) {
    switch (kind) {
      case 'image':
      case 'video':
        return [
          const AdaptiveAction('react', Icons.emoji_emotions_outlined, 'تفاعل'),
          if (canPost) const AdaptiveAction('reply', Icons.reply_rounded, 'رد'),
          const AdaptiveAction('open', Icons.play_circle_outline_rounded, 'عرض/تشغيل'),
          const AdaptiveAction('share', Icons.ios_share_rounded, 'مشاركة/حفظ'),
          const AdaptiveAction('forward', Icons.shortcut_rounded, 'توجيه'),
        ];
      case 'voice':
        return [
          const AdaptiveAction('open', Icons.play_circle_outline_rounded, 'تشغيل'),
          const AdaptiveAction('speed', Icons.speed_rounded, 'تغيير السرعة'),
          const AdaptiveAction('share', Icons.ios_share_rounded, 'مشاركة/تنزيل'),
          if (canPost) const AdaptiveAction('reply', Icons.reply_rounded, 'رد'),
          const AdaptiveAction('react', Icons.emoji_emotions_outlined, 'تفاعل'),
        ];
      case 'file':
        return [
          const AdaptiveAction('open', Icons.open_in_new_rounded, 'فتح'),
          const AdaptiveAction('share', Icons.ios_share_rounded, 'مشاركة'),
          if (canPost) const AdaptiveAction('reply', Icons.reply_rounded, 'رد'),
          const AdaptiveAction('react', Icons.emoji_emotions_outlined, 'تفاعل'),
        ];
      default: // نص وأي نوع نصي-مستقبل
        return [
          const AdaptiveAction('react', Icons.emoji_emotions_outlined, 'تفاعل'),
          if (canPost) const AdaptiveAction('reply', Icons.reply_rounded, 'رد'),
          const AdaptiveAction('copy', Icons.copy_rounded, 'نسخ'),
          const AdaptiveAction('translate', Icons.translate_rounded, 'ترجمة'),
          if (mine) const AdaptiveAction('edit', Icons.edit_rounded, 'تعديل'),
          const AdaptiveAction('forward', Icons.shortcut_rounded, 'توجيه'),
        ];
    }
  }

  /// اقتراحات سياقية محلية: هاتف/بريد/رابط/سؤال — كل اقتراح مقترن بإجراء
  /// حقيقي، والتحليل regex محلي فقط ولا يرسل شيئاً لأي خادم ولا ينفذ تلقائياً.
  static List<ContextSuggestion> suggest(String? text) {
    if (text == null || text.isEmpty) return const [];
    final out = <ContextSuggestion>[];
    final phone = RegExp(r'\+?\d[\d\s-]{6,}\d');
    final email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
    final link = RegExp(r'https?://[^\s\u0600-\u06FF]+', caseSensitive: false);
    final pm = phone.firstMatch(text);
    if (pm != null) {
      out.add(ContextSuggestion('call', Icons.call_rounded, 'اتصال', pm.group(0)!));
    }
    final em = email.firstMatch(text);
    if (em != null) {
      out.add(ContextSuggestion('email', Icons.mail_outline_rounded, 'مراسلة', em.group(0)!));
    }
    final lm = link.firstMatch(text);
    if (lm != null) {
      out.add(ContextSuggestion('link', Icons.link_rounded, 'فتح الرابط', lm.group(0)!));
    }
    if (text.contains('؟') || text.contains('?')) {
      out.add(const ContextSuggestion('reply', Icons.bolt_rounded, 'رد سريع', ''));
    }
    return out.take(3).toList();
  }
}
