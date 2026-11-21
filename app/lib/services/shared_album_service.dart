/// الألبومات المشتركة — بند 1.20.0 «ألبومات مشتركة داخل الغرف المسموحة»
/// (المرحلة 22 — 1.20.0): قواعد نقية بلا شبكة ولا واجهة — تُختبَر حصرياً
/// في `shared_album_service_test.dart`، والترحيل الخادمي `043_shared_albums.sql`
/// يحمل الجداول بسياسات عضوية القائمة والخادم وسيط شفاف لا يفك محتوى.
///
/// القواعد الصادقة:
/// - الغرف المسموحة = الجماعية حصراً (`is_group = true`) — الخاصة أظرفتها
///   ثنائية وألبومها المشترك هو فقاعة الوسائط القائمة (album_service).
/// - لا صلاحية جديدة: من أضاف قطعة يملك إزالتها، ومنشئ الألبوم يملك حذفه —
///   نفس عُادة الصلاحيات في ترحيل 039 (الفاعل هو صاحب الفعل).
/// - القطع مراجع رسائل وسائط قائمة لا نسخ محتوى — بترتيب الإضافة، وأقصى
///   قطع للألبوم 50 وأقصى ألبومات للغرفة 5 (حدود معلنة).
/// - الفشل يعيد أسبابه مجمعة لا أولها — بلا استثناءات مسربة.
library;

// ————— النماذج —————

class SharedAlbum {
  SharedAlbum({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    required this.items,
  });

  final String id;
  final String conversationId;
  final String title;
  final String createdBy;
  final DateTime createdAt;
  final List<SharedAlbumItem> items;
}

class SharedAlbumItem {
  SharedAlbumItem({
    required this.messageId,
    required this.addedBy,
    required this.addedAt,
  });

  final String messageId;
  final String addedBy;
  final DateTime addedAt;
}

/// محصلة أي قاعدة — إما قيمة أو أسباب مجمعة.
class AlbumOutcome<T> {
  AlbumOutcome.ok(T this._value) : _reasons = const [];
  AlbumOutcome.refused(this._reasons) : _value = null;

  final T? _value;
  final List<String> _reasons;

  bool get isOk => _value != null;
  bool get isRefused => _reasons.isNotEmpty;
  T get value => _value as T;
  List<String> get reasons => _reasons;
}

// ————— القواعد النقية —————

class SharedAlbumService {
  SharedAlbumService._();

  /// حدود معلنة قبل التنفيذ
  static const int maxAlbumsPerConversation = 5;
  static const int maxItemsPerAlbum = 50;
  static const int maxTitleChars = 60;

  /// الغرف المسموحة: الجماعية حصراً
  static bool canHostAlbums({required bool isGroup}) => isGroup;

  /// إنشاء ألبوم داخل غرفة — كل الشروط تفحص والأسباب تجمع لا أولها
  static AlbumOutcome<SharedAlbum> createAlbum({
    required bool isGroup,
    required bool isMember,
    required String memberId,
    required String title,
    required int currentAlbumCount,
    required String albumId,
    required DateTime now,
  }) {
    final reasons = <String>[];
    if (!isMember) reasons.add('ليست عضواً في الغرفة — لا إنشاء ولا رؤية');
    if (!canHostAlbums(isGroup: isGroup)) {
      reasons.add('الألبومات المشتركة في الغرف الجماعية حصراً');
    }
    final t = title.trim();
    if (t.isEmpty) {
      reasons.add('العنوان فارغ');
    } else if (t.length > maxTitleChars) {
      reasons.add('العنوان ${t.length} حرفاً فوق الحد $maxTitleChars');
    }
    if (currentAlbumCount >= maxAlbumsPerConversation) {
      reasons.add('عدد الألبومات $currentAlbumCount بلغ الحد '
          '$maxAlbumsPerConversation');
    }
    if (reasons.isNotEmpty) return AlbumOutcome.refused(reasons);
    return AlbumOutcome.ok(SharedAlbum(
      id: albumId,
      conversationId: '',
      title: t,
      createdBy: memberId,
      createdAt: now,
      items: <SharedAlbumItem>[],
    ));
  }

  /// إضافة قطعة (مرجع رسالة وسائط قائمة) — بلا تكرار وبضمن الحد
  static AlbumOutcome<List<SharedAlbumItem>> addItem({
    required bool isMember,
    required String memberId,
    required String messageId,
    required List<SharedAlbumItem> currentItems,
    required DateTime now,
  }) {
    final reasons = <String>[];
    if (!isMember) reasons.add('ليست عضواً في الغرفة — لا إضافة');
    if (currentItems.any((i) => i.messageId == messageId)) {
      reasons.add('القطعة موجودة في الألبوم أصلاً — بلا تكرار');
    }
    if (currentItems.length >= maxItemsPerAlbum) {
      reasons.add('عدد القطع ${currentItems.length} بلغ الحد '
          '$maxItemsPerAlbum');
    }
    if (reasons.isNotEmpty) return AlbumOutcome.refused(reasons);
    final next = [...currentItems,
      SharedAlbumItem(messageId: messageId, addedBy: memberId, addedAt: now)];
    return AlbumOutcome.ok(next);
  }

  /// إزالة قطعة — من أضافها حصراً (لا صلاحية جديدة)
  static AlbumOutcome<List<SharedAlbumItem>> removeItem({
    required String memberId,
    required String messageId,
    required List<SharedAlbumItem> currentItems,
  }) {
    final idx = currentItems.indexWhere((i) => i.messageId == messageId);
    if (idx < 0) {
      return AlbumOutcome.refused(['القطعة ليست في الألبوم']);
    }
    if (currentItems[idx].addedBy != memberId) {
      return AlbumOutcome.refused(['قطعة عضو آخر — إزالتها لمن أضافها حصراً']);
    }
    final next = [...currentItems]..removeAt(idx);
    return AlbumOutcome.ok(next);
  }

  /// حذف ألبوم كامل — منشئه حصراً
  static AlbumOutcome<bool> deleteAlbum({
    required String memberId,
    required SharedAlbum album,
  }) {
    if (album.createdBy != memberId) {
      return AlbumOutcome.refused(['حذف الألبوم لمنشئه حصراً']);
    }
    return AlbumOutcome.ok(true);
  }

  /// قائمة قطع الألبوم بترتيب الإضافة (الأقدم أولاً) — القراءة لا تغيّر
  static List<SharedAlbumItem> orderedItems(SharedAlbum album) {
    final items = [...album.items];
    items.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    return items;
  }
}
