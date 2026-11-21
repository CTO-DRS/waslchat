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
  final String kind; // call | email | link | reply | reminder | map | attach
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
      case 'location':
        // الموقع (2.3.1): فتح الخريطة، الإحداثيات، الحفظ، المشاركة، الرد، التفاعل، التوجيه
        return [
          const AdaptiveAction('open', Icons.map_rounded, 'فتح الخريطة'),
          const AdaptiveAction('copy', Icons.copy_rounded, 'نسخ الإحداثيات'),
          const AdaptiveAction('save', Icons.bookmark_add_outlined, 'حفظ'),
          const AdaptiveAction('share', Icons.ios_share_rounded, 'مشاركة'),
          if (canPost) const AdaptiveAction('reply', Icons.reply_rounded, 'رد'),
          const AdaptiveAction('react', Icons.emoji_emotions_outlined, 'تفاعل'),
          const AdaptiveAction('forward', Icons.shortcut_rounded, 'توجيه'),
        ];
      case 'file':
        return [
          const AdaptiveAction('open', Icons.open_in_new_rounded, 'فتح'),
          const AdaptiveAction('share', Icons.ios_share_rounded, 'مشاركة'),
          const AdaptiveAction('link', Icons.link_rounded, 'نسخ الرابط'),
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

  /// اقتراحات سياقية محلية: هاتف/بريد/رابط/موعد/عنوان/طلب ملف/سؤال —
  /// كل اقتراح مقترن بإجراء حقيقي، والتحليل regex محلي فقط بلا خادم
  /// ولا تنفيذ تلقائي ولا شرط لعمل الإجراءات الأساسية.
  static List<ContextSuggestion> suggest(String? text) {
    if (text == null || text.isEmpty) return const [];
    final out = <ContextSuggestion>[];
    final phone = RegExp(r'\+?\d[\d\s-]{6,}\d');
    final email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
    final link = RegExp(r'https?://[^\s\u0600-\u06FF]+', caseSensitive: false);
    // موعد: وقت مفهوم + كلمة يوم/موعد
    final wm = RegExp(r'(\d{1,2})\s*[:\.]\s*(\d{2})\s*(صباحا|ص|مساء|م|am|pm)?',
            caseSensitive: false)
        .firstMatch(text);
    final mentionsDay = RegExp(
            r'اليوم|غدا|بكرة|بكره|tomorrow|today|الساعة|موعد|appointment')
        .hasMatch(text);
    if (wm != null && mentionsDay) {
      out.add(ContextSuggestion(
          'reminder', Icons.alarm_rounded, 'أنشئ تذكير', wm.group(0)!));
    }
    // عنوان: كلمات مكانية + رقم في الجملة نفسها
    final addrLine = text.split(RegExp(r'[.!؟\n،]')).firstWhere(
          (s) =>
              RegExp(r'شارع|حي|قطعة|مبنى|زقاق|جادة|منطقة|عنوان|street|block')
                  .hasMatch(s) &&
              RegExp(r'\d').hasMatch(s),
          orElse: () => '',
        );
    if (addrLine.trim().isNotEmpty && addrLine.trim().length < 120) {
      out.add(ContextSuggestion(
          'map', Icons.map_rounded, 'فتح الخريطة', addrLine.trim()));
    }
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
    // طلب ملف: فعل إرسال/إرفاق قرب اسم ملف أو مستند
    final wantsFile = RegExp(
            r'(أرسل|ارسل|ابعت|بعت|اعمل|أرفق|ارفق|ممكن|send|attach).{0,30}(ملف|مستند|صورة|فيديو|تقرير|مخطط|file|document|report|pdf|image)',
            caseSensitive: false)
        .hasMatch(text);
    if (wantsFile) {
      out.add(const ContextSuggestion(
          'attach', Icons.attach_file_rounded, 'إرفاق ملف', ''));
    }
    if (text.contains('؟') || text.contains('?')) {
      out.add(const ContextSuggestion('reply', Icons.bolt_rounded, 'رد سريع', ''));
    }
    return out.take(3).toList();
  }

  /// فهم الوقت من نص عربي/إنجليزي: ساعة:دقيقة + ص/م + غداً/اليوم
  /// null = لا وقت مفهوم — والقرار النهائي للمستخدم في منتقي الوقت
  static WhenHint? parseWhen(String s) {
    final t = RegExp(r'(\d{1,2})\s*[:\.]\s*(\d{2})\s*(صباحا|ص|مساء|م|am|pm)?',
            caseSensitive: false)
        .firstMatch(s);
    if (t == null) return null;
    var h = int.parse(t.group(1)!);
    final min = int.parse(t.group(2)!);
    if (h < 0 || h > 23 || min > 59) return null;
    final suffix = (t.group(3) ?? '').toLowerCase();
    if (suffix == 'م' || suffix == 'مساء' || suffix == 'pm') {
      if (h < 12) h += 12;
    } else if (suffix == 'ص' || suffix == 'صباحا' || suffix == 'am') {
      if (h == 12) h = 0;
    }
    final tomorrow = RegExp(r'غدا|بكرة|بكره|tomorrow').hasMatch(s);
    // ساعة ودقيقة كأعداد صماء — تجنباً لازدواج صنف TimeOfDay بين
    // material_ui و material في هذا المشروع
    return WhenHint(h, min, tomorrow);
  }
}

/// وقت مفهوم من النص (ساعة 0-23 ودقيقة) + هل يشير إلى الغد
class WhenHint {
  const WhenHint(this.hour, this.minute, this.tomorrow);
  final int hour;
  final int minute;
  final bool tomorrow;
}
