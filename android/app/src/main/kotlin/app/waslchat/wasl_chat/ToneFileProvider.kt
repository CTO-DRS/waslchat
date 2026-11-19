package app.waslchat.wasl_chat

import androidx.core.content.FileProvider

/// مزوّد ملفات نغماتك من استوديو الصوت (1.12.0): يتيح لنظام الإشعارات
/// قراءة ملف النغمة من مجلد التطبيق الخاص بلا صلاحيات تخزين.
class ToneFileProvider : FileProvider()
