/// منطق غرف الصوت الجماعية النقي (المرحلة 6 ب — 0.18.0).
///
/// غرفة صوت mesh بلا أي خادم إضافي: كل مشارك يفتح اتصالاً WebRTC مباشراً
/// مشفّراً DTLS-SRTP مع كل مشارك آخر، والإشارات تمر عبر قناة بثّ لحظية لا
/// تُخزَّن في أي قاعدة بيانات وتبدد بالبث — نفس نموذج المكالمات الفردية
/// (call_logic.dart) بلا صف خادم ولا ترحيل جديد إطلاقاً.
///
/// كل ما يُقرَّر هنا محلي بلا شبكة بلا WebRTC — ليُختبر مباشرة. حسم «مَن يقدّم
/// العرض» قاعدي حتمي بمعرّف المستخدم لمنع اصطدام العرضين (glare) عند انضمام
/// اثنين في اللحظة نفسها.
import 'package:flutter/material.dart';

import 'call_logic.dart'; // CallSignal — تغليفها في RoomSignal

/// حالة الغرفة من منظور جهازك
enum RoomPhase { joining, live, left, failed }

RoomPhase? roomPhaseFrom(String? s) => switch (s) {
      'joining' => RoomPhase.joining,
      'live' => RoomPhase.live,
      'left' => RoomPhase.left,
      'failed' => RoomPhase.failed,
      _ => null,
    };

/// آلة حالة الغرفة — قرارات محلية صارمة (لا خادم يحكم هنا؛ الغرفة حية فقط
/// ما دمت متصلاً بقناتها).
class RoomFlow {
  /// الحد الأقصى للمشاركين في غرفة mesh: فوقه يتدهور الصوت على كل الأجهزة
  /// (كل مشارك يرفع N-1 تدفقاً). حاجز تعاوني محلي — بلا خادم لا إجبار قهر.
  static const maxParticipants = 8;

  /// مهلة إقامة الاتصال مع كل مشارك (تدفق SDP/ICE)
  static const connectTimeout = Duration(seconds: 20);

  /// هل الانتقال من [from] إلى [to] مسموح؟
  static bool canTransition(RoomPhase from, RoomPhase to) {
    return switch (to) {
      RoomPhase.joining => false, // لا عودة للانضمام أبداً
      RoomPhase.live => from == RoomPhase.joining,
      RoomPhase.left => true, // المغادرة ممكنة من أي حالة
      RoomPhase.failed =>
        from == RoomPhase.joining || from == RoomPhase.live,
    };
  }

  /// حالة نهائية: بعد المغادرة لا شيء يعيد الغرفة إلا انضماماً جديداً
  static bool terminal(RoomPhase s) =>
      s == RoomPhase.left || s == RoomPhase.failed;

  /// هل الغرفة حية وأنت فيها؟
  static bool live(RoomPhase s) => s == RoomPhase.live;

  /// نص حالة شاشة الغرفة
  static String phaseLabel(RoomPhase s) => switch (s) {
        RoomPhase.joining => 'جارٍ الانضمام…',
        RoomPhase.live => 'الغرفة حية',
        RoomPhase.left => 'غادرت الغرفة',
        RoomPhase.failed => 'تعذر الانضمام',
      };

  /// حسم المُقدم حتمياً: صاحب المعرّف الأصغر معجمياً يقدّم العرض لنظيره.
  /// يمنع اصطدام عرضين متوازيين — كلاهما لا يقدّم ولا كلاهما ينتظر.
  static bool shouldOffer(String myId, String peerId) {
    if (myId.isEmpty || peerId.isEmpty || myId == peerId) return false;
    return myId.compareTo(peerId) < 0;
  }

  /// هل يمكن الانضمام؟ (سعة الغرفة + عدم التكرار)
  static bool canJoin({
    required int currentParticipants,
    required bool alreadyJoined,
  }) {
    if (alreadyJoined) return false;
    return currentParticipants < maxParticipants;
  }
}

/// إشارة غرفة عبر قناة البثّ اللحظي: تغلّف إشارة المكالمة القياسية
/// (CallSignal) بحقلَي المرسل والمستهدف — المستهدف null يعني «للجميع»
/// (الوداع الجماعي مثلاً). لا تُخزَّن في أي قاعدة بيانات.
class RoomSignal {
  const RoomSignal({required this.from, this.to, required this.sig});
  final String from;
  final String? to; // null = بثّ للجميع
  final CallSignal sig;

  /// تحليل دفاعي: أي غرابة (بلا مرسل، بلا إشارة داخلية سليمة، مرسل فارغ)
  /// → null تُتجاهل بلا انهيار
  static RoomSignal? tryParse(Object? payload) {
    if (payload is! Map) return null;
    final f = payload['f'];
    if (f is! String || f.isEmpty) return null;
    final t = payload['t'];
    if (t != null && t is! String) return null;
    final inner = CallSignal.tryParse(payload['s']);
    if (inner == null) return null;
    return RoomSignal(
      from: f,
      to: t is String && t.isNotEmpty ? t : null,
      sig: inner,
    );
  }

  Map<String, Object?> toPayload() => {
        'f': from,
        if (to != null) 't': to,
        's': sig.toPayload(),
      };

  /// هل تصلح لمعالجتي أنا؟ (موجهة إليّ أو بثّ عام) — والمشتتات من نفسي تُرفض
  static bool addressedTo(RoomSignal s, String me) =>
      s.from != me && (s.to == null || s.to == me);
}

/// مشارك في الغرفة كما يصل عبر presence القناة — تحليل دفاعي صادق.
class VoicePeer {
  const VoicePeer({
    required this.id,
    required this.name,
    this.avatar,
    this.micOn = true,
  });
  final String id;
  final String name;
  final String? avatar;
  final bool micOn;

  /// تحليل بيانات presence: بلا معرّف صالح → null تُتجاهل.
  /// الاسم الفارغ يهبط إلى «عضو» والكتم غائب يُفهم صوتاً مفعّلاً.
  static VoicePeer? fromPresence(Map<Object?, Object?> meta) {
    final uid = meta['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final name = meta['name'];
    final av = meta['avatar'];
    final mic = meta['mic'];
    return VoicePeer(
      id: uid,
      name: name is String && name.isNotEmpty ? name : 'عضو',
      avatar: av is String && av.isNotEmpty ? av : null,
      micOn: mic is! bool || mic,
    );
  }

  Map<String, Object?> toPresence() => {
        'uid': id,
        if (name.isNotEmpty) 'name': name, // الفارغ يهبط «عضو» عند المستقبل
        if (avatar != null && avatar!.isNotEmpty) 'avatar': avatar,
        'mic': micOn,
      };

  VoicePeer copyWith({bool? micOn}) => VoicePeer(
        id: id,
        name: name,
        avatar: avatar,
        micOn: micOn ?? this.micOn,
      );
}

/// إدارة قائمة المشاركين النقية: ترتيب ثابت (أنت أولاً ثم أبجدياً بالاسم
/// ثم بالمعرّف لتسوية التساوي)، بلا تكرار، وبوابة عضوية تُسقط الغرباء.
class RoomRoster {
  RoomRoster({required this.meId, required this.meName, this.meAvatar});
  final String meId;
  final String meName;
  final String? meAvatar;

  final Map<String, VoicePeer> _peers = {};
  Set<String> _gate = {};

  /// بوابة العضوية: معرفات أعضاء المحادثة من جدول محمي بـRLS —
  /// أي presence أو إشارة من خارج البوابة تُسقط قبل أي معالجة
  set gate(Set<String> ids) => _gate = ids;
  Set<String> get gate => _gate;

  bool isMember(String id) => _gate.contains(id);

  bool contains(String id) => id == meId || _peers.containsKey(id);

  /// عدد المشاركين في الغرفة بأني (أنت + الآخرون)
  int get count => _peers.length + 1;

  /// الآخرون فقط (بلا أنت)
  List<VoicePeer> get others {
    final list = _peers.values.toList()
      ..sort((a, b) {
        final n = a.name.compareTo(b.name);
        return n != 0 ? n : a.id.compareTo(b.id);
      });
    return list;
  }

  /// إضافة مشارك بعد البوابة — false إن كان أنت أو مكرراً أو خارج البوابة
  /// أو يكسر سعة الغرفة
  bool add(VoicePeer p) {
    if (p.id == meId) return false;
    if (_gate.isNotEmpty && !_gate.contains(p.id)) return false;
    if (_peers.containsKey(p.id)) return false;
    if (count >= RoomFlow.maxParticipants) return false;
    _peers[p.id] = p;
    return true;
  }

  VoicePeer? remove(String id) => _peers.remove(id);

  /// تحديث حالة كتم مشارك قائم — false إن لم يكن موجوداً
  bool setMic(String id, bool on) {
    final p = _peers[id];
    if (p == null) return false;
    _peers[id] = p.copyWith(micOn: on);
    return true;
  }

  VoicePeer? peerOf(String id) => _peers[id];

  void clear() => _peers.clear();

  /// سطر حالة: «أنت و3 آخرين في الغرفة» — صادق بالأعداد
  static String countLabel(int count) {
    if (count <= 1) return 'أنت وحدك في الغرفة — انتظر انضمام الأعضاء';
    return 'أنت و${count - 1} ${count - 1 == 1 ? 'عضو آخر' : 'أعضاء آخرين'} في الغرفة';
  }
}

/// أيقونة ووجه الغرفة في واجهات الاختيار
IconData roomIcon() => Icons.spatial_audio_off_rounded;

/// سطر توضيحي صادق لحدود الغرفة يظهر قبل الانضمام
String roomDisclaimer() =>
    'غرفة صوت جماعية بتشفير مباشر بين الأجهزة — حتى ${RoomFlow.maxParticipants} مشاركين. '
    'الصوت يمر بين جهازك وأجهزة المشاركين مباشرة ولا يسمعه خادم وصل، '
    'وإشارات الاتصال تمر لحظياً ولا تُخزَّن.';
