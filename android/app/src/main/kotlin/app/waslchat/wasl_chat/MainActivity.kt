package app.waslchat.wasl_chat

import android.app.Activity
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
    private var tonePlayer: android.media.MediaPlayer? = null

    // Wasl Shield (1.10.0): اكتشاف الالتقاط حيث يدعم النظام — يبلّغ Flutter فقط،
    // والمنع الفعلي هو FLAG_SECURE عبر قناة wasl/secure.
    private var shieldChannel: MethodChannel? = null
    private var captureCallback: Any? = null
    private var recordingCallback: java.util.function.Consumer<Int>? = null

    override fun onStart() {
        super.onStart()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val cb = Activity.ScreenCaptureCallback {
                    runOnUiThread { shieldChannel?.invokeMethod("onScreenshot", null) }
                }
                registerScreenCaptureCallback(mainExecutor, cb)
                captureCallback = cb
            }
        } catch (e: Exception) {
        }
        try {
            if (Build.VERSION.SDK_INT >= 35) {
                val cb = java.util.function.Consumer<Int> { state ->
                    runOnUiThread {
                        shieldChannel?.invokeMethod(
                            "onRecording",
                            state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
                        )
                    }
                }
                val initial = windowManager.addScreenRecordingCallback(mainExecutor, cb)
                recordingCallback = cb
                shieldChannel?.invokeMethod(
                    "onRecording",
                    initial == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
                )
            }
        } catch (e: Exception) {
        }
    }

    override fun onStop() {
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                (captureCallback as? Activity.ScreenCaptureCallback)?.let {
                    unregisterScreenCaptureCallback(it)
                }
            }
            if (Build.VERSION.SDK_INT >= 35) {
                recordingCallback?.let { windowManager.removeScreenRecordingCallback(it) }
            }
        } catch (e: Exception) {
        }
        captureCallback = null
        recordingCallback = null
        super.onStop()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shieldChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "wasl/shield")
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
                    // معاينة نغمة «وصل شات» من res/raw (1.11.0)
                    "playTone" -> {
                        try {
                            val name = call.argument<String>("name") ?: ""
                            tonePlayer?.release()
                            tonePlayer = null
                            if (name == "system") {
                                val uri = android.media.RingtoneManager.getDefaultUri(
                                    android.media.RingtoneManager.TYPE_NOTIFICATION)
                                android.media.RingtoneManager.getRingtone(this, uri)?.play()
                            } else {
                                val id = resources.getIdentifier(name, "raw", packageName)
                                if (id != 0) {
                                    tonePlayer = android.media.MediaPlayer.create(this, id)
                                    tonePlayer?.setOnCompletionListener { it.release(); if (tonePlayer === it) tonePlayer = null }
                                    tonePlayer?.start()
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    // استوديو الصوت (1.12.0): تشغيل ملف نغمة من الجهاز
                    "playFile" -> {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            tonePlayer?.release()
                            tonePlayer = android.media.MediaPlayer().apply {
                                setDataSource(path)
                                setOnCompletionListener { it.release(); if (tonePlayer === it) tonePlayer = null }
                                prepare()
                                start()
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    // تسجيل نغمة من الاستوديو: رابط محتوى يقرؤه النظام + قناتان بصوتها
                    "registerTone" -> {
                        try {
                            val path = call.argument<String>("path") ?: ""
                            val uri = androidx.core.content.FileProvider.getUriForFile(
                                this, "$packageName.tones", java.io.File(path))
                            for (pkg in listOf("com.android.systemui", "android")) {
                                try {
                                    grantUriPermission(pkg, uri, android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                } catch (_: Exception) {}
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                val attrs = android.media.AudioAttributes.Builder()
                                    .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                    .build()
                                val name = call.argument<String>("name") ?: "الرسائل"
                                val msg = NotificationChannel(
                                    call.argument<String>("msgChannel"), name,
                                    NotificationManager.IMPORTANCE_HIGH)
                                msg.description = "تنبيهات الرسائل الجديدة في محادثاتك"
                                msg.setSound(uri, attrs)
                                nm.createNotificationChannel(msg)
                                val rem = NotificationChannel(
                                    call.argument<String>("remChannel"), "التذكيرات المحلية",
                                    NotificationManager.IMPORTANCE_HIGH)
                                rem.description = "تذكيرات المواعيد على جهازك من وصل شات"
                                rem.setSound(uri, attrs)
                                nm.createNotificationChannel(rem)
                            }
                            result.success(uri.toString())
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "deleteTone" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                call.argument<String>("msgChannel")?.let { nm.deleteNotificationChannel(it) }
                                call.argument<String>("remChannel")?.let { nm.deleteNotificationChannel(it) }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
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
