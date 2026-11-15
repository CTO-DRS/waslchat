/// كتالوج الترجمة النقي (المرحلة 12 ب — 0.29.0): تعدد اللغات بلا حزم خارجية
/// ولا توليد كود — خرائط ثابتة مفحوصة بالاختبارات.
///
/// التصميم الصادق:
/// - العربية لغة التصميم الأم: مفتاح غائب في غير العربية يهبط إلى العربية
///   لا إلى نص إنجليزي مكسور، والمفتاح الغائب عن الجميع يظهر باسمه — لا فراغات.
/// - التغطية في 0.29.0: الأسطح الرئيسية (التنقل، المحادثات، المكالمات، الحالات،
///   الدخول، الإعدادات، الأزرار المشتركة، غرف الصوت) — والبقية تتوالى حتى 1.0.0
///   (موثق في GRAND_PLAN وTRANSPARENCY).
/// - أير: en وfr يساران (LTR) والعربية يميناً (RTL) — وDirectionality يأتي من
///   MaterialApp مع locale المختار تلقائياً.
library;

/// اللغات المدعومة — العربية أولاً دائماً
const List<String> l10nSupported = ['ar', 'en', 'fr'];

/// أسماء اللغات تعرض بلغتها نفسها (لا تُترجم أبداً)
const Map<String, String> l10nLanguageNames = {
  'ar': 'العربية',
  'en': 'English',
  'fr': 'Français',
};

/// هل اللغة يمين-لليسار؟ (العربية فقط)
bool l10nIsRtl(String lang) => lang == 'ar';

const Map<String, Map<String, String>> _catalog = {
  // ============ التنقل الرئيسي ============
  'nav_chats': {
    'ar': 'المحادثات', 'en': 'Chats', 'fr': 'Discussions',
  },
  'nav_communities': {
    'ar': 'المجتمعات', 'en': 'Communities', 'fr': 'Communautés',
  },
  'nav_channels': {
    'ar': 'القنوات', 'en': 'Channels', 'fr': 'Chaînes',
  },
  'nav_calls': {
    'ar': 'المكالمات', 'en': 'Calls', 'fr': 'Appels',
  },
  'nav_settings': {
    'ar': 'الإعدادات', 'en': 'Settings', 'fr': 'Réglages',
  },

  // ============ أزرار وأفعال مشتركة ============
  'act_cancel': {
    'ar': 'إلغاء', 'en': 'Cancel', 'fr': 'Annuler',
  },
  'act_save': {
    'ar': 'حفظ', 'en': 'Save', 'fr': 'Enregistrer',
  },
  'act_delete': {
    'ar': 'حذف', 'en': 'Delete', 'fr': 'Supprimer',
  },
  'act_send': {
    'ar': 'إرسال', 'en': 'Send', 'fr': 'Envoyer',
  },
  'act_confirm': {
    'ar': 'تأكيد', 'en': 'Confirm', 'fr': 'Confirmer',
  },
  'act_done': {
    'ar': 'تم', 'en': 'Done', 'fr': 'Terminé',
  },
  'act_retry': {
    'ar': 'إعادة المحاولة', 'en': 'Retry', 'fr': 'Réessayer',
  },
  'act_join': {
    'ar': 'انضمام', 'en': 'Join', 'fr': 'Rejoindre',
  },
  'act_accept': {
    'ar': 'قبول', 'en': 'Accept', 'fr': 'Accepter',
  },
  'act_decline': {
    'ar': 'رفض', 'en': 'Decline', 'fr': 'Refuser',
  },
  'act_end_call': {
    'ar': 'إنهاء المكالمة', 'en': 'End call', 'fr': 'Terminer l’appel',
  },
  'act_leave_room': {
    'ar': 'مغادرة الغرفة', 'en': 'Leave room', 'fr': 'Quitter la salle',
  },
  'act_publish': {
    'ar': 'نشر الحالة', 'en': 'Post status', 'fr': 'Publier',
  },

  // ============ المحادثات ============
  'chats_new': {
    'ar': 'محادثة جديدة', 'en': 'New chat', 'fr': 'Nouvelle discussion',
  },
  'chats_search_hint': {
    'ar': 'ابحث باسم المستخدم', 'en': 'Search by username', 'fr': 'Rechercher un utilisateur',
  },
  'chats_search_in_conv': {
    'ar': 'ابحث في المحادثة…', 'en': 'Search in chat…', 'fr': 'Rechercher dans la discussion…',
  },
  'chats_type_message': {
    'ar': 'اكتب رسالة…', 'en': 'Type a message…', 'fr': 'Écrire un message…',
  },
  'chats_today': {
    'ar': 'اليوم', 'en': 'Today', 'fr': 'Aujourd’hui',
  },
  'chats_yesterday': {
    'ar': 'أمس', 'en': 'Yesterday', 'fr': 'Hier',
  },
  'chats_encrypted_msg': {
    'ar': '🔒 رسالة مشفرة', 'en': '🔒 Encrypted message', 'fr': '🔒 Message chiffré',
  },
  'chats_typing': {
    'ar': 'يكتب الآن…', 'en': 'typing…', 'fr': 'écrit…',
  },
  'chats_empty': {
    'ar': 'لا محادثات بعد — ابدأ أول محادثة لك',
    'en': 'No chats yet — start your first conversation',
    'fr': 'Aucune discussion — commencez la première',
  },
  'chats_send_failed': {
    'ar': 'تعذّر إرسال الرسالة', 'en': 'Failed to send message', 'fr': 'Échec de l’envoi',
  },
  'chats_too_long': {
    'ar': 'الرسالة طويلة جداً', 'en': 'Message is too long', 'fr': 'Message trop long',
  },
  'chats_msg_deleted': {
    'ar': 'رسالة محذوفة', 'en': 'Deleted message', 'fr': 'Message supprimé',
  },

  // ============ المكالمات ============
  'call_voice': {
    'ar': 'مكالمة صوتية', 'en': 'Voice call', 'fr': 'Appel audio',
  },
  'call_video': {
    'ar': 'مكالمة مرئية', 'en': 'Video call', 'fr': 'Appel vidéo',
  },
  'call_incoming': {
    'ar': 'مكالمة واردة', 'en': 'Incoming call', 'fr': 'Appel entrant',
  },
  'call_connecting': {
    'ar': 'جارٍ الاتصال…', 'en': 'Connecting…', 'fr': 'Connexion…',
  },
  'call_connected': {
    'ar': 'متصلان', 'en': 'Connected', 'fr': 'Connecté',
  },
  'call_ended': {
    'ar': 'انتهت المكالمة', 'en': 'Call ended', 'fr': 'Appel terminé',
  },
  'call_missed': {
    'ar': 'لم يُجب', 'en': 'No answer', 'fr': 'Sans réponse',
  },
  'call_declined': {
    'ar': 'مرفوضة', 'en': 'Declined', 'fr': 'Refusé',
  },
  'call_failed': {
    'ar': 'تعذر الاتصال', 'en': 'Connection failed', 'fr': 'Connexion échouée',
  },
  'call_history_title': {
    'ar': 'سجل المكالمات', 'en': 'Call history', 'fr': 'Historique des appels',
  },
  'call_quality_excellent': {
    'ar': 'الشبكة ممتازة', 'en': 'Network excellent', 'fr': 'Réseau excellent',
  },
  'call_quality_good': {
    'ar': 'الشبكة جيدة', 'en': 'Network good', 'fr': 'Réseau bon',
  },
  'call_quality_weak': {
    'ar': 'الشبكة متقطعة', 'en': 'Network unstable', 'fr': 'Réseau instable',
  },
  'call_quality_poor': {
    'ar': 'الشبكة ضعيفة', 'en': 'Network poor', 'fr': 'Réseau faible',
  },

  // ============ غرف الصوت والمكالمة الجماعية ============
  'room_intro_title': {
    'ar': 'غرفة صوت جماعية', 'en': 'Group voice room', 'fr': 'Salon vocal de groupe',
  },
  'group_call_title': {
    'ar': 'مكالمة جماعية صوتية', 'en': 'Group voice call', 'fr': 'Appel vocal de groupe',
  },
  'group_call_action': {
    'ar': 'اتصال', 'en': 'Call', 'fr': 'Appeler',
  },
  'room_live': {
    'ar': 'الغرفة حية', 'en': 'Room is live', 'fr': 'Salon actif',
  },

  // ============ الحالات ============
  'status_mine': {
    'ar': 'حالتي', 'en': 'My status', 'fr': 'Mon statut',
  },
  'status_new': {
    'ar': 'حالة جديدة', 'en': 'New status', 'fr': 'Nouveau statut',
  },
  'status_think_hint': {
    'ar': 'بماذا تفكر اليوم؟', 'en': 'What’s on your mind today?',
    'fr': 'Quoi de neuf aujourd’hui ?',
  },
  'status_encrypted_note': {
    'ar': 'مشفّرة بين الطرفين — تظهر لشركاء محادثاتك الفردية 24 ساعة',
    'en': 'End-to-end encrypted — visible to your direct-chat partners for 24 hours',
    'fr': 'Chiffré de bout en bout — visible à vos partenaires directs 24 h',
  },
  'status_locked': {
    'ar': 'تعذّر فك تشفير هذه الحالة على هذا الجهاز',
    'en': 'This status can’t be decrypted on this device',
    'fr': 'Ce statut n’a pas pu être déchiffré ici',
  },

  // ============ الدخول والحساب ============
  'auth_login': {
    'ar': 'تسجيل الدخول', 'en': 'Sign in', 'fr': 'Connexion',
  },
  'auth_register': {
    'ar': 'إنشاء حساب', 'en': 'Create account', 'fr': 'Créer un compte',
  },
  'auth_email': {
    'ar': 'البريد الإلكتروني', 'en': 'Email', 'fr': 'Adresse e-mail',
  },
  'auth_password': {
    'ar': 'كلمة المرور', 'en': 'Password', 'fr': 'Mot de passe',
  },
  'auth_forgot': {
    'ar': 'نسيت كلمة المرور؟', 'en': 'Forgot password?', 'fr': 'Mot de passe oublié ?',
  },
  'auth_welcome_back': {
    'ar': 'أهلاً بعودتك', 'en': 'Welcome back', 'fr': 'Bon retour',
  },

  // ============ الإعدادات ============
  'settings_appearance': {
    'ar': 'المظهر', 'en': 'Appearance', 'fr': 'Apparence',
  },
  'settings_notifications': {
    'ar': 'الإشعارات', 'en': 'Notifications', 'fr': 'Notifications',
  },
  'settings_privacy': {
    'ar': 'الخصوصية والأمان', 'en': 'Privacy & security', 'fr': 'Confidentialité et sécurité',
  },
  'settings_devices': {
    'ar': 'الأجهزة المرتبطة', 'en': 'Linked devices', 'fr': 'Appareils liés',
  },
  'settings_about': {
    'ar': 'عن التطبيق', 'en': 'About', 'fr': 'À propos',
  },
  'settings_help': {
    'ar': 'مركز المساعدة', 'en': 'Help center', 'fr': 'Centre d’aide',
  },
  'settings_logout': {
    'ar': 'تسجيل الخروج', 'en': 'Log out', 'fr': 'Se déconnecter',
  },
  'settings_language': {
    'ar': 'لغة التطبيق', 'en': 'App language', 'fr': 'Langue de l’app',
  },
  'settings_language_note': {
    'ar': 'العربية لغة التصميم الأم — الترجمة تغطي الأسطح الرئيسية وتتوالى مع كل إصدار',
    'en': 'Arabic is the design language — translation covers the main surfaces and grows every release',
    'fr': 'L’arabe est la langue de conception — la traduction couvre les surfaces principales et grandit',
  },
  'settings_metrics': {
    'ar': 'مؤشرات الأداء على جهازك', 'en': 'Performance on your device', 'fr': 'Performances sur votre appareil',
  },
};

/// ترجمة مفتاح بلغة معينة — الصادق: الغائب في اللغة يهبط للعربية،
/// والغائب عن الجميع يعود باسمه كي يُكتشف بالاختبارات لا يظهر فراغاً
String l10nT(String key, String lang) {
  final entry = _catalog[key];
  if (entry == null) return key;
  return entry[lang] ?? entry['ar'] ?? key;
}

/// هل المفتاح مترجم في كل اللغات المدعومة؟ (أداة اختبار)
bool l10nComplete(String key) {
  for (final lang in l10nSupported) {
    if (_catalog[key]?[lang] == null) return false;
  }
  return true;
}

/// كل المفاتيح المعرفة في الكتالوج
List<String> l10nKeys() => _catalog.keys.toList()..sort();
