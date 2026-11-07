# وصل شات — الإصدار 0.4

تطبيق مراسلة حقيقي يعمل على أندرويد وآيفون والويب بكود واحد (Flutter) مع خادم مجاني (Supabase).

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
- الوسائط مخزنة بشكل خاص: لا يراها إلا أعضاء المحادثة
- حماية: لا يقرأ الرسائل إلا أطراف المحادثة (RLS)
- واجهة عربية كاملة (RTL) ووضع داكن وشريط سفلي زجاجي
- تبويب المكالمات جاهز للمرحلة القادمة

## التشغيل خطوة بخطوة (مجاناً)
تحتاج كمبيوتر (ويندوز أو ماك أو لينكس).

1. **ثبّت Flutter**: من flutter.dev > Get started، ثم شغّل `flutter doctor`.
2. **أنشئ مشروع Supabase مجاني**: supabase.com > New project.
3. **قاعدة البيانات**: افتح SQL Editor، الصق `supabase/001_schema.sql` واضغط Run، ثم `002_groups_media.sql`، ثم `003_receipts_push.sql`، ثم `004_communities_channels.sql` (كل ملف وحده ثم Run).
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
1. ✅ المجموعات والصور والرسائل الصوتية
2. ✅ حالة الاتصال و"يكتب الآن" وعلامات القراءة (Realtime Presence)
3. ✅ الإشعارات (Firebase Cloud Messaging مجاني)
4. المكالمات الصوتية والمرئية (LiveKit / WebRTC)
5. ✅ المجتمعات والقنوات والمساعد الذكي
6. التشفير التام بين الطرفين
