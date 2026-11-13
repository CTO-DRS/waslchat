/// منطق المكالمات النقي (المرحلة 6 — 0.17.0).
///
/// كل ما يُقرَّر هنا محلي بلا شبكة وبلا WebRTC — ليُختبر مباشرة، ويتطابق
/// حرفياً مع انتقالات الحالة المفروضة من الخادم في `supabase/028_calls.sql`
/// (دالة call_update security definer): ما يرفضه الخادم يرفضه هذا الملف
/// قبل أن يحاول، وما يسمح به الخادم لوحده يُسمح هنا وحدّه.
import 'package:flutter/material.dart';

/// نوع المكالمة
enum CallKind { voice, video }

CallKind callKindFrom(String? s) => s == 'video' ? CallKind.video : CallKind.voice;

String callKindLabel(CallKind k) => k == CallKind.video ? 'مرئية' : 'صوتية';

IconData callKindIcon(CallKind k) =>
    k == CallKind.video ? Icons.videocam_outlined : Icons.call_outlined;

/// حالة المكالمة كما يعرفها الخادم (028_calls.sql)
enum CallStatus { ringing, answered, declined, missed, cancelled, failed, ended }

CallStatus? callStatusFrom(String? s) => switch (s) {
      'ringing' => CallStatus.ringing,
      'answered' => CallStatus.answered,
      'declined' => CallStatus.declined,
      'missed' => CallStatus.missed,
      'cancelled' => CallStatus.cancelled,
      'failed' => CallStatus.failed,
      'ended' => CallStatus.ended,
      _ => null,
    };

/// دور الطرف في المكالمة
enum CallRole { caller, callee }

/// آلة الحالة النقية — مرآة call_update في الخادم.
class CallFlow {
  /// مهلة الرنين: إن لم يُرد خلالها صنّف الطالبها «فائتة» (caller→missed)
  static const ringTimeout = Duration(seconds: 45);

  /// مهلة إقامة الاتصال بعد الرد (جاهزية الطرف الآخر، تدفق SDP/ICE)
  static const connectTimeout = Duration(seconds: 20);

  /// هل الانتقال من [from] إلى [to] مسموح لـ[role]؟ (مرآة call_update حرفياً)
  static bool canTransition(CallStatus from, CallStatus to, CallRole role) {
    return switch (to) {
      CallStatus.ringing => false, // لا عودة إلى الرنين أبداً
      CallStatus.answered => from == CallStatus.ringing && role == CallRole.callee,
      CallStatus.declined => from == CallStatus.ringing && role == CallRole.callee,
      CallStatus.cancelled => from == CallStatus.ringing && role == CallRole.caller,
      CallStatus.missed => from == CallStatus.ringing && role == CallRole.caller,
      CallStatus.failed =>
        from == CallStatus.ringing || from == CallStatus.answered,
      CallStatus.ended => from == CallStatus.answered,
    };
  }

  /// حالة نهائية لا تُعاد بعدها — أي تحديث متأخر صمت لا خطأ
  static bool terminal(CallStatus s) =>
      s == CallStatus.ended ||
      s == CallStatus.declined ||
      s == CallStatus.missed ||
      s == CallStatus.cancelled;

  /// هل الاتصال نشط (الوسائط وصلت ويجري التحدث)؟
  static bool live(CallStatus s) => s == CallStatus.answered;

  /// نص حالة شاشة المكالمة: ماذا يظهر تحت اسم الطرف الآخر
  static String phaseLabel(CallStatus s, CallRole role) {
    return switch (s) {
      CallStatus.ringing =>
        role == CallRole.caller ? 'جارٍ الاتصال…' : 'مكالمة واردة',
      CallStatus.answered => 'متصلان',
      CallStatus.ended => 'انتهت المكالمة',
      CallStatus.declined => 'مرفوضة',
      CallStatus.missed => 'لم يُجب',
      CallStatus.cancelled => 'أُلغيت',
      CallStatus.failed => 'تعذر الاتصال',
    };
  }
}

/// رسالة إشارة عبر قناة بثّ Realtime لحظية — لا تُخزَّن في أي قاعدة بيانات
/// وتبدد بالبث. الحقول قصيرة مقصودة لتقليل ما يمر عبر الوسيط.
enum SignalType { ready, offer, answer, ice, bye }

class CallSignal {
  const CallSignal({
    required this.type,
    this.sdp,
    this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });
  final SignalType type;
  final String? sdp; // offer/answer
  final String? candidate; // ice
  final String? sdpMid;
  final int? sdpMLineIndex;

  /// تحليل دفاعي: أي غرابة أو حقل ناقص → null تُتجاهل بلا انهيار
  static CallSignal? tryParse(Object? payload) {
    if (payload is! Map) return null;
    final type = switch (payload['t']) {
      'ready' => SignalType.ready,
      'offer' => SignalType.offer,
      'answer' => SignalType.answer,
      'ice' => SignalType.ice,
      'bye' => SignalType.bye,
      _ => null,
    };
    if (type == null) return null;
    final sdp = payload['sdp'] is String && (payload['sdp'] as String).isNotEmpty
        ? payload['sdp'] as String
        : null;
    final candidate =
        payload['candidate'] is String && (payload['candidate'] as String).isNotEmpty
            ? payload['candidate'] as String
            : null;
    // عرض/جواب بلا SDP أو ICE بلا مرشح = رسالة معطوبة
    if ((type == SignalType.offer || type == SignalType.answer) && sdp == null) {
      return null;
    }
    if (type == SignalType.ice && candidate == null) return null;
    final mid = payload['sdpMid'] is String ? payload['sdpMid'] as String : null;
    final mline =
        payload['sdpMLineIndex'] is int ? payload['sdpMLineIndex'] as int : null;
    return CallSignal(
      type: type,
      sdp: sdp,
      candidate: candidate,
      sdpMid: mid,
      sdpMLineIndex: mline,
    );
  }

  Map<String, Object?> toPayload() => {
        't': switch (type) {
          SignalType.ready => 'ready',
          SignalType.offer => 'offer',
          SignalType.answer => 'answer',
          SignalType.ice => 'ice',
          SignalType.bye => 'bye',
        },
        if (sdp != null) 'sdp': sdp,
        if (candidate != null) 'candidate': candidate,
        if (sdpMid != null) 'sdpMid': sdpMid,
        if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
      };
}

/// صف سجل مكالمة كما يعود من الخادم (select على جدول calls)
class CallRecord {
  const CallRecord({
    required this.id,
    required this.conversationId,
    required this.callerId,
    required this.calleeId,
    required this.kind,
    required this.status,
    required this.duration,
    required this.createdAt,
  });
  final String id;
  final String conversationId;
  final String callerId;
  final String calleeId;
  final CallKind kind;
  final CallStatus status;
  final int duration; // ثوانٍ
  final DateTime createdAt;

  factory CallRecord.fromRow(Map<String, dynamic> r) => CallRecord(
        id: (r['id'] ?? '') as String,
        conversationId: (r['conversation_id'] ?? '') as String,
        callerId: (r['caller_id'] ?? '') as String,
        calleeId: (r['callee_id'] ?? '') as String,
        kind: callKindFrom(r['kind'] as String?),
        status: callStatusFrom(r['status'] as String?) ?? CallStatus.failed,
        duration: (r['duration'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.tryParse((r['created_at'] ?? '') as String)?.toLocal() ??
            DateTime.now(),
      );

  /// الطرف الآخر من منظور [me]
  String peerId(String me) => callerId == me ? calleeId : callerId;

  /// صادرة أم واردة من منظور [me]
  bool outgoing(String me) => callerId == me;

  /// هل الرنين حيّ ووارد وليس صفّاً قديماً عالقاً؟
  /// حارس وصول المكالمات: صف عمره أكثر من ثانيتين من لحظة الوصول لا يُرنّ —
  /// الخادم قد يعيد إرسال بثّ قديم أو مكالمة أُغلقت قبل لحظة.
  bool freshIncomingRing(String me, DateTime now) =>
      status == CallStatus.ringing &&
      !outgoing(me) &&
      now.difference(createdAt).inSeconds.abs() <= 2;
}

/// عرض سجل المكالمات: تسميات وأيقونات صادقة لحالة كل صف من منظور [me]
class CallHistoryView {
  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// مدة المكالمة نصاً: «0:00» / «2:35» / «1:04:10»
  static String formatDuration(int s) {
    if (s < 0) s = 0;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final two = (int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
  }

  /// تسمية حالة الصف عربياً من منظور صاحب السجل
  static String statusLabel(CallRecord r, String me) => switch (r.status) {
        CallStatus.ended || CallStatus.answered =>
          r.outgoing(me) ? 'صادرة' : 'واردة',
        CallStatus.missed => 'فائتة',
        CallStatus.declined => 'مرفوضة',
        CallStatus.cancelled => 'ملغاة',
        CallStatus.failed => 'فشلت',
        CallStatus.ringing => r.outgoing(me) ? 'تُرن…' : 'واردة',
      };

  /// أيقونة الصف: اتجاه للسليمة، وعبارة حمراء للمنقطعة
  static IconData statusIcon(CallRecord r, String me) => switch (r.status) {
        CallStatus.ended ||
        CallStatus.answered ||
        CallStatus.ringing =>
          r.outgoing(me)
              ? Icons.call_made_rounded
              : Icons.call_received_rounded,
        CallStatus.missed || CallStatus.declined => Icons.call_missed_rounded,
        CallStatus.cancelled => Icons.call_end_rounded,
        CallStatus.failed => Icons.phone_disabled_rounded,
      };

  /// هل الصف يُعرض بلون الإنذار الأحمر؟
  static bool negative(CallRecord r) => switch (r.status) {
        CallStatus.missed ||
        CallStatus.declined ||
        CallStatus.cancelled ||
        CallStatus.failed =>
          true,
        _ => false,
      };

  /// وقت الصف نصاً: «اليوم 14:32» / «أمس 09:05» / «5 نوفمبر» / «20 نوفمبر 2025»
  static String timeLabel(DateTime created, DateTime now) {
    final today = now;
    final two = (int n) => n.toString().padLeft(2, '0');
    final time = '${two(created.hour)}:${two(created.minute)}';
    final sameDay = created.year == today.year &&
        created.month == today.month &&
        created.day == today.day;
    if (sameDay) return 'اليوم $time';
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final isYesterday = created.year == yesterday.year &&
        created.month == yesterday.month &&
        created.day == yesterday.day;
    if (isYesterday) return 'أمس $time';
    final dayMonth = '${created.day} ${_months[created.month - 1]}';
    return created.year == today.year ? dayMonth : '$dayMonth ${created.year}';
  }
}
