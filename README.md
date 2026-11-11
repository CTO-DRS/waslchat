# وصل شات — الإصدار 0.1.8

تطبيق مراسلة حقيقي يعمل على أندرويد وآيفون والويب بكود واحد (Flutter) مع خادم مجاني (Supabase).

[![ادعم وصل شات / Support Wasl Chat](https://img.shields.io/badge/PayPal-ادعم%20وصل%20شات%20%2F%20Support%20Wasl%20Chat-0070ba?logo=paypal)](https://www.paypal.com/ncp/payment/9QVZ2Y7A5X3GN)

سياسة الخصوصية والشروط: https://waslchat.app/


### الجديد في 0.1.8
- إرسال الفيديو والملفات حتى 24 ميغابايت، مشفّرة بين الطرفين، واسم الملف وحجمه مشفّران أيضاً. الفيديو يُشغَّل داخل التطبيق، والملفات تُفتح بالتطبيق المناسب.
- تنظيف تلقائي: ملفات الرسائل المحذوفة والمختفية تُحذف من التخزين كل ساعة (جدول `media_trash` + دالة `media-cleanup` + pg_cron).
- ترحيل `supabase/013_files_video_cleanup.sql`.

### الجديد في 0.1.7
- الرسائل المختفية: 24 ساعة أو 7 أيام أو 90 يوماً لكل محادثة (في المجموعة: المالك والمشرفون). تُخفى فور انتهائها وتُحذف من الخادم كل 15 دقيقة عبر pg_cron. ملفات الوسائط المشفّرة تبقى في التخزين حالياً.
- الرسائل المميزة بنجمة: داخل المحادثة ومن الإعدادات.
- صفحة ملف الطرف الآخر (الصورة والنبذة ورمز الأمان والكتم)، والصور في رأس المحادثة ونتائج البحث.
- ترحيل `supabase/012_disappearing_stars.sql`.

### الجديد في 0.1.6
- تعديل الملف الشخصي: الصورة والاسم الظاهر والنبذة (الصورة عامة في bucket `avatars`).
- تثبيت المحادثات (حتى 5) وكتمها (8 ساعات، أسبوع، دائماً) وأرشفتها بالضغط المطوّل في قائمة المحادثات. المكتوم لا يصله إشعار.
- البحث داخل المحادثة (في الرسائل النصية المفكوكة على الجهاز).
- إعادة توجيه الرسائل والوسائط، مع إعادة التشفير بمفتاح المحادثة الهدف.
- ترحيل `supabase/011_profile_chat_prefs.sql`.

## ما يعمل الآن
- إنشاء حساب وتسجيل دخول بالبريد وكلمة المرور
- البحث عن مستخدمين باسم المستخدم وبدء محادثة خاصة
- رسائل لحظية (تصل فوراً بدون تحديث)
- قائمة محادثات مع آخر رسالة ووقتها
- **جديد 0.2:** المجموعات (اسم + أعضاء، واسم المرسل فوق رسالته)
- **جديد 0.2:** إرسال صور من المعرض أو الكاميرا، وفتحها بملء الشاشة مع التكبير
- **جديد 0.2:** رسائل صوتية بالضغط المطوّل على الميكروفون، مع تشغيل وشريط تقدم
- **جديد 0.3:** «يكتب الآن...» لحظياً، وعلامات ✓ أُرسلت و ✓✓ قُرئت
- **جديد 0.3:** نقطة خضراء لمن هو «متصل الآن»، وعداد الرسائل غير المقروءة
- **جديد 0.3:** إشعارات فورية على الجوال (اختيارية، تحتاج إعداد Firebase المجاني)
- **جديد 0.4:** المجتمعات: أنشئ مجتمعاً فيه قناة «الإعلانات» وغرفة «عام»، وأضف غرفاً، واكتشف المجتمعات وانضم إليها
- **جديد 0.4:** القنوات العامة: أنشئ قناة ينشر فيها المشرفون فقط، واكتشف القنوات وتابعها
- **جديد 0.4:** «وصل AI»: مساعد ذكي، وتلخيص أي محادثة بزر ✨، وترجمة أي رسالة بالضغط المطوّل عليها
- **جديد 0.1.5:** إدارة المجموعات: معلومات المجموعة، إضافة أعضاء، إزالة عضو، مغادرة، مشرفون، تغيير الاسم. يتغيّر مفتاح التشفير تلقائياً عند خروج أي عضو
- **جديد 0.1.5:** الرد على رسالة، تعديل رسالتك (خلال 48 ساعة)، حذف للجميع، تفاعلات بالإيموجي، نسخ — تعمل مع الرسائل المشفّرة (التفاعلات نفسها غير مشفّرة)
- الوسائط مخزنة بشكل خاص: لا يراها إلا أعضاء المحادثة
- حماية: لا يقرأ الرسائل إلا أطراف المحادثة (RLS)
- واجهة عربية كاملة (RTL) ووضع داكن وشريط سفلي زجاجي
- تبويب المكالمات جاهز للمرحلة القادمة

## التشغيل خطوة بخطوة (مجاناً)
تحتاج كمبيوتر (ويندوز أو ماك أو لينكس).

1. **ثبّت Flutter**: من flutter.dev > Get started، ثم شغّل `flutter doctor`.
2. **أنشئ مشروع Supabase مجاني**: supabase.com > New project.
3. **قاعدة البيانات**: افتح SQL Editor، الصق `supabase/001_schema.sql` واضغط Run، ثم `002_groups_media.sql`، ثم `003_receipts_push.sql`، ثم `004_communities_channels.sql`، ثم `005_push_trigger.sql` (بقيم حقيقية)، ثم `006_e2e_keys.sql` (كل ملف وحده ثم Run).
   (إذا شغّلت إصداراً سابقاً، شغّل الملفات الجديدة فقط.)
4. **للتجربة السريعة**: Authentication > Providers > Email، أطفئ "Confirm email".
5. **اربط التطبيق**: من Project Settings > API انسخ Project URL و anon key وضعهما في `lib/config.dart`.
6. **جهّز المجلد** (داخل مجلد المشروع):
   ```
   flutter create . --project-name wasl_chat --platforms=android,ios,web
   flutter pub get
   ```
7. **الأذونات** (مرة واحدة بعد الخطوة 6):
   - أندرويد: في `android/app/src/main/AndroidManifest.xml` أضف فوق `<application`:
     ```
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.RECORD_AUDIO"/>
     ```
   - آيفون: في `ios/Runner/Info.plist` أضف داخل `<dict>`:
     ```
     <key>NSMicrophoneUsageDescription</key><string>لتسجيل الرسائل الصوتية</string>
     <key>NSCameraUsageDescription</key><string>لالتقاط الصور وإرسالها</string>
     <key>NSPhotoLibraryUsageDescription</key><string>لإرسال الصور من المعرض</string>
     ```
8. **شغّل**: `flutter run` (على جوال موصول أو `flutter run -d chrome`).
9. **جرّب**: أنشئ حسابين (مثلاً من المتصفح والجوال) وابدأ محادثة بينهما.

> ملاحظة: التسجيل الصوتي يعمل على تطبيق الجوال، والصور تعمل على الجوال والويب.

## وصل AI (مجاني)
1. خذ مفتاحاً مجانياً من aistudio.google.com/apikey (بدون بطاقة).
2. من مجلد المشروع:
   ```
   npx supabase secrets set GEMINI_API_KEY=مفتاحك
   npx supabase functions deploy ai
   ```
   (إذا لم تربط المشروع بعد: `npx supabase login` ثم `npx supabase link --project-ref رمز-مشروعك`.)
3. النموذج الافتراضي `gemini-3.8-flash`. لتغييره: `npx supabase secrets set GEMINI_MODEL=اسم-النموذج`.
> الطبقة المجانية لها حد يومي للطلبات، وجوجل قد تستخدم بياناتها لتحسين منتجاتها. للخصوصية الكاملة لاحقاً ننتقل للطبقة المدفوعة أو نموذج مفتوح.

## الإشعارات (اختياري، مجاني على أندرويد)
بدونها يعمل التطبيق كاملاً، فقط لا تصل تنبيهات والتطبيق مغلق.
1. أنشئ مشروعاً مجانياً في console.firebase.google.com.
2. على كمبيوترك:
   ```
   npm install -g firebase-tools
   firebase login
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
   (يستبدل `lib/firebase_options.dart` تلقائياً.)
3. في Firebase: Project settings > Service accounts > Generate new private key. احفظ الملف باسم `sa.json`.
4. انشر دالة الإشعارات على Supabase (من مجلد المشروع):
   ```
   npx supabase login
   npx supabase link --project-ref رمز-مشروعك
   npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat sa.json)" WEBHOOK_SECRET=اختر-كلمة-سرية-طويلة
   npx supabase functions deploy push --no-verify-jwt
   ```
5. في Supabase: Database > Webhooks > Create: الجدول `messages`، الحدث Insert، النوع Supabase Edge Functions، الدالة `push`، وأضف Header باسم `x-webhook-secret` وقيمته نفس الكلمة السرية.
6. أندرويد 13+: أضف في AndroidManifest:
   `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`

> آيفون: الإشعارات تتطلب حساب Apple Developer المدفوع (99$ سنوياً)، لذلك نبدأ بأندرويد.
> لا تشارك `sa.json` مع أحد ولا ترفعه على GitHub.

## النشر المجاني
- **ويب**: `flutter build web` ثم ارفع مجلد `build/web` على Vercel أو Netlify أو Cloudflare Pages.
- **أندرويد**: `flutter build apk` ثم شارك ملف APK مباشرة مع المجربين.

## المراحل القادمة
انظر خارطة الطريق الكاملة في `docs/ROADMAP.md`.

## مستندات المطوّر
- `docs/ROADMAP.md` — خارطة الطريق الكاملة: المنجز، والمراحل حتى الإطلاق 1.0، والأولويات.
- `docs/INFRASTRUCTURE.md` — الدومين وDNS والموقع والحسابات والخدمات وبريد التواصل.
- `docs/RUNBOOK_URGENT.md` — مهام المالك العاجلة: تدوير رموز GitHub/Supabase، ربط Brevo SMTP، إضافة بصمات Firebase، قائمة اختبار الجهاز الحقيقي.
- `docs/E2EE_PLAN.md` — خطة التشفير بين الطرفين (X25519 + AES-GCM): الحالة والحدود والمراحل القادمة.
