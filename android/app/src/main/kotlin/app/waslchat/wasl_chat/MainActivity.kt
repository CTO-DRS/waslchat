package app.waslchat.wasl_chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/// FlutterFragmentActivity بدل FlutterActivity: مطلوب لقفل التطبيق بالبصمة
/// (BiometricPrompt في local_auth) — نفس سلوك التطبيق دون تغيير.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wasl/secure")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        if (secure) {
                            window.setFlags(
                                WindowManager.LayoutParams.FLAG_SECURE,
                                WindowManager.LayoutParams.FLAG_SECURE
                            )
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        // تبديل أيقونة التطبيق (0.21.0): البديل المتدرج أو الكلاسيكية عبر
        // activity-alias في AndroidManifest — تفعيل واحد وإعطاب الآخر.
        // الاسم الوافي: MainActivityGradient / MainActivityClassic.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wasl/appicon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setAlias" -> {
                        try {
                            val alias = call.argument<String>("alias") ?: "MainActivityClassic"
                            val pkg = packageName
                            val pm = packageManager // موروث من النشاط مباشرة — لا حاجة لـgetSystemService
                            val enableOne = { name: String, enabled: Boolean ->
                                pm.setComponentEnabledSetting(
                                    ComponentName(pkg, "$pkg.$name"),
                                    if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                                    else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                    PackageManager.DONT_KILL_APP
                                )
                            }
                            // كلا الالقبين تُضبط دفعة واحدة — لا حالة وسطية
                            if (alias == "MainActivityGradient") {
                                enableOne("MainActivityGradient", true)
                                enableOne("MainActivityClassic", false)
                            } else {
                                enableOne("MainActivityClassic", true)
                                enableOne("MainActivityGradient", false)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // قناة إشعارات أندرويد «الرسائل» باسم عربي وأهمية عالية — يوجه إليها
        // الخادم عبر channel_id في رسالة FCM (واجهة القنوات أزيلت من
        // firebase_messaging فأصبح الإنشاء الأصلي هو الطريق الموثوق).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wasl/notify")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "createMessageChannel" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val channel = NotificationChannel(
                                "messages",
                                "الرسائل",
                                NotificationManager.IMPORTANCE_HIGH
                            )
                            channel.description = "تنبيهات الرسائل الجديدة في محادثاتك"
                            nm.createNotificationChannel(channel)
                            // قناة «المكالمات» (0.17.0): إشعارات المكالمة الواردة
                            // بأهمية عالية تظهر فوراً — صوت الرنين داخل التطبيق
                            val calls = NotificationChannel(
                                "calls",
                                "المكالمات",
                                NotificationManager.IMPORTANCE_HIGH
                            )
                            calls.description = "تنبيهات المكالمات الصوتية والمرئية الواردة"
                            nm.createNotificationChannel(calls)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
