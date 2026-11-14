package app.waslchat.wasl_chat

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/// ويدجت «آخر المحادثات» (0.21.0): يرث مزود home_widget ويقرأ ما كتبه
/// التطبيق عبر HomeWidget.saveWidgetData — آخر 3 محادثات بمعاينتها،
/// والنقر على الويدجت يفتح التطبيق. لا شبكة ولا خدمة خلفية هنا إطلاقاً:
/// عرض نقي لبيانات الجهاز، وتحديثه من التطبيق عند فتح القائمة.
class WaslChatWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        appWidgetIds.forEach { id ->
            appWidgetManager.updateAppWidget(id, buildViews(context, widgetData))
        }
    }

    private fun buildViews(
        context: Context,
        data: android.content.SharedPreferences
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.wasl_widget)
        val count = data.getInt("rows_count", 0)
        // ثلاثة صفوف ثابتة البنية: عنوان + معاينة + وقت + شارة غير مقروء
        val rowIds = intArrayOf(R.id.row1, R.id.row2, R.id.row3)
        val titleIds = intArrayOf(R.id.r1_title, R.id.r2_title, R.id.r3_title)
        val previewIds = intArrayOf(R.id.r1_preview, R.id.r2_preview, R.id.r3_preview)
        val timeIds = intArrayOf(R.id.r1_time, R.id.r2_time, R.id.r3_time)
        val badgeIds = intArrayOf(R.id.r1_badge, R.id.r2_badge, R.id.r3_badge)

        for (i in 0..2) {
            val title = data.getString("r${i}_title", null)
            if (i < count && !title.isNullOrEmpty()) {
                views.setViewVisibility(rowIds[i], View.VISIBLE)
                views.setTextViewText(titleIds[i], title)
                views.setTextViewText(previewIds[i], data.getString("r${i}_preview", null) ?: "")
                views.setTextViewText(timeIds[i], data.getString("r${i}_time", null) ?: "")
                val unread = data.getString("r${i}_unread", null) ?: ""
                if (unread.isNotEmpty()) {
                    views.setViewVisibility(badgeIds[i], View.VISIBLE)
                    views.setTextViewText(badgeIds[i], unread)
                } else {
                    views.setViewVisibility(badgeIds[i], View.GONE)
                }
            } else {
                views.setViewVisibility(rowIds[i], View.GONE)
            }
        }
        // كل الصفوف فارغة: رسالة ترحيب هادئة
        views.setViewVisibility(R.id.empty_state, if (count == 0) View.VISIBLE else View.GONE)

        // النقر يفتح التطبيق (اللقب المفعّل حالياً يحدد أيقونة المشغّل فقط)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (launch != null) {
            val pi = PendingIntent.getActivity(
                context, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)
        }
        return views
    }
}
