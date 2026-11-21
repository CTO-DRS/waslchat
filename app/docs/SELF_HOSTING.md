# دليل الاستضافة الذاتية — شغّل وصل بخادمك أنت

> **السؤال الصادق:** «أين بياناتنا؟» — والإجابة القابلة للتحقق لا الوعد:
> كل ما يحتاجه وصل من خادم هو Supabase (قاعدة + تخزين + مصادقة + realtime)
> ودوال Edge سبع، وكلها برمجيات مفتوحة تشغّلها بنفسك. هذا الدليل يأخذك من
> صفر إلى خادم كامل، بصدق كامل عن ما يعمل وما يحتاج حساباتك الخاصة.

آخر تحديث: 2026-11-20 · يعادل وصل **2.0.0+90** · الترحيلات: **001 → 043**

---

## 1) ماذا ستحتاج فعلاً

| المتطلب | لماذا | الحد الأدنى المجاني العملي |
|---|---|---|
| خادم VPS | Supabase ذاتي الاستضافة + coturn | 2 vCPU و4 ج.ب رام و40 ج.ب قرص (Ubuntu 24.04 مثلاً) |
| دومين + TLS | وصول التطبيق وrealtime عبر wss وHTTPS | نطاق خاص بك وسجلّا A/AAAA وشهادة Let's Encrypt |
| Docker + Compose | توزيعة Supabase الرسمية self-hosted | أحدث إصدار ثابت |
| حساب Firebase (اختياري) | إشعارات FCM لأندرويد — **بلا حساب لا إشعارات، وكل الباقي يعمل** | مجاني |
| مفتاح Gemini (اختياري) | وصل AI السحابي (الترجمة والملخص السحابي والتفريغ) — بلا مفتاح تبقى المحركات على الجهاز فقط | طبقة مجانية |

**حدّان صادقان قبل أن تبدأ:**
1. **حزمة APK العامة موجّهة للخادم الرسمي** — لتوصيل تطبيقك بخادمك: خذ الكود من هذا المستودع، عدّل `lib/config.dart` (§4)، وابنِ APK بتوقيعك أنت (`secrets/` مفتاحك أو مفتاحك الخاص). لا يمكن توجيه الحزمة المنشورة لخادم آخر بعد التثبيت — القرار وقت البناء.
2. **realtime وRLS يعملان كما هما حرفياً** — لا شيء في الترحيلات يفترض خادم وصل تحديداً؛ كل السياسات `auth.uid()` معيارية.

## 2) Supabase ذاتي الاستضافة

```sh
# على خادمك
git clone --depth 1 https://github.com/supabase/supabase.git
cd supabase/docker
cp .env.example .env   # ثم عدّل القيم (أنظر أدناه)
docker compose up -d
```

في `.env` ضع كلمات مرور قوية وأسراراً مولّدة (`openssl rand -base64 32`):
- `POSTGRES_PASSWORD` و`JWT_SECRET` و`ANON_KEY` و`SERVICE_ROLE_KEY` (الأخيران تُولَّد من `JWT_SECRET` بصفحة supabase الأدواتية أو بأي أداة JWT HS256 بclaims الدور الصحيحة).
- `SITE_URL` دومينك، و`SMTP_*` لتأكيد البريد (Brevo أو ما شابه — لا تترك القالب الافتراضي للإنتاج).

بعد الإقلاع: Studio على المنفذ 3000 (خلف وكيل عكسي بTLS حصراً)، وURL الخدمة دومينك عبر 8000/443.

## 3) الترحيلات بالترتيب (001 → 039 — إلزاميّ الترتيب)

نفّذ كل ملف من `supabase/` بالترتيب عبر SQL Editor أو `psql`:

```sh
psql "postgres://postgres:كلمة_المرور@خادمك:5432/postgres" \
  -f supabase/001_schema.sql
# ... ثم 002 حتى 039 بالترتيب نفسه
```

القائمة الكاملة بترتيبها:
`001_schema.sql` · `002_groups_media.sql` · `003_receipts_push.sql` · `004_communities_channels.sql` · `005_push_trigger.sql` · `006_e2e_keys.sql` · `007_group_keys.sql` · `008_key_backup.sql` · `009_group_admin.sql` · `010_message_features.sql` · `011_profile_chat_prefs.sql` · `012_disappearing_stars.sql` · `013_files_video_cleanup.sql` · `014_site_admin.sql` · `015_blocks_reports.sql` · `016_app_version.sql` · `017_group_invites.sql` · `018_statuses.sql` · `019_view_once.sql` · `020_e2e_prekeys.sql` · `021_linked_devices.sql` · `022_e2e_metadata.sql` · `023_community_moderation.sql` · `024_community_events.sql` · `025_phase4.sql` · `026_verification.sql` · `027_ai_moderation.sql` · `028_calls.sql` · `029_feedback.sql` · `031_album_clear.sql` · `032_channel_bells.sql` · `033_pq_prekeys.sql` · `034_key_transparency.sql` · `035_status_video_reply.sql` · `036_web_push_subscriptions.sql` · `037_prekey_signing.sql` · `038_key_log_witness.sql` · `039_bot_ecosystem.sql`

> **ملاحظة صادقة:** الرقم 030 مُخط تاريخياً — القفزة من 029 إلى 031 مقصودة وموثقة في GRAND_PLAN.
>
> **تحقق بعد كل ترحيل:** كل ملف يحمّل تحققات SQL أسفله (استعلام يجب أن ينجح أو أن يفشل عمداً) — نفّذها واحداً واحداً قبل الانتقال.

## 4) توجيه التطبيق لخادمك

في `lib/config.dart`:

```dart
static const supabaseUrl = 'https://supabase.دومينك.example';
static const supabaseAnonKey = 'مفتاح_anon_الذي_ولّدته_في_§2';
```

وعند إعداد TURN (§6) املأ `iceServers` بسرّتك بدل التعليق المعلّق. ثم ابنِ:

```sh
flutter build apk --release --target-platform android-arm64
```

التوقيع: ضع ملف `wasl-release.jks` الخاص بك وكلماته في `android/key.properties` وفق `secrets/README` القائم بنفس البنية.

## 5) دوال Edge السبع

القائمة: `push` · `ai` · `moderation-ai` · `bots-api` · `event-reminders` · `link-preview` · `media-cleanup`

**الطريقان الصادقان لنشر الدوال:**

1. **Edge Runtime ذاتي الاستضافة (الاكتمال الكامل)** — حاوية `supabase/edge-runtime` من توزيعة الدوكر نفسها تدير `supabase/functions/` (دليل Supabase الرسمي: Self-hosting Edge Functions). تُضبط أسرار كل دالة كمتغيرات الحاوية، ويوجّه وكيلك العكسي مسار `/functions/v1/*` إليها. **أسرار الدوال يوفرها مالك الخادم الذاتي بنفسه — لا توجد أي أسرار مضمّنة في الكود** (تحقق: `scripts/scrub_engines.py` والفحص الآلي على كل الملفات المتتبعة).
2. **مشروع سحابي كامل بدل الذاتي** — إن أردت أبسط طريق مقبول: أنشئ مشروعك الخاص على supabase.com (الخطة المجانية)، ونفّذ الترحيلات ونشر الدوال بـ`supabase functions deploy` عليه، ووجّه تطبيقك إليه. بياناتك عندهم حينها — لكن بـ**مشروعك أنت**: حسابك ومفاتيحك ونسخك الاحتياطية وحدودك — وهذا «الاستضافة شبه الذاتية» بصدق نسميه اسمه ولا نبيعه كذاتي.

**أسرار كل دالة (تُضبط بـ`supabase secrets set` أو متغيرات الحاوية):**

| الدالة | الأسرار |
|---|---|
| `push` | `FCM_SERVICE_ACCOUNT` (ملف JSON من Firebase Console → Service Accounts)، `WEBHOOK_SECRET`، `WEB_PUSH_VAPID_PRIVATE_KEY` و`WEB_PUSH_VAPID_SUBJECT` لإشعارات المتصفح (036)، و`SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` |
| `event-reminders` | `FCM_SERVICE_ACCOUNT` و`WEBHOOK_SECRET` و`SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` نفسها |
| `ai` و`moderation-ai` | `GEMINI_API_KEY` واختياري `GEMINI_MODEL` — بلا مفتاح تعمل المحركات المحلية فقط وترد الدالة بخطأ واضح |
| `bots-api` | `SUPABASE_URL` و`SUPABASE_SERVICE_ROLE_KEY` حصراً |
| `link-preview` | لا أسرار — تجلب الصفحات العامة وتحجب الداخلية |
| `media-cleanup` | بلا أسرار بيئية — يعمل بجدولة داخلية |

**مصدر الحقيقة للفحص:** `supabase/functions/*/index.ts` ترويسة كل دالة تذكر أسرارها نصاً.

## 6) TURN (coturn) — المكالمات خلف NAT المتماثل

```sh
docker run -d --network host coturn/coturn \
  -n --realm=دومينك --listening-port=3478 \
  --min-port=49160 --max-port=49200 \
  --lt-cred-mech --user=وصل:كلمة_قوية \
  --no-cli --no-tls --no-dtls
```

افتح في الجدار: UDP/TCP 3478 وUDP 49160-49200. ثم في `lib/config.dart` ألغِ تعليق سطر TURN واملأ بياناتك:

```dart
{'urls': 'turn:turn.دومينك.example:3478?transport=udp',
 'username': 'وصل', 'credential': 'كلمة_المرور'},
```

تحقق الاتصال من جهازين على شبكات مختلفة — بلا TURN تبقى معظم الشبكات تعمل بSTUN العام، والصارمة تفشل برسالة صادقة.

## 7) الإشعارات — ما يعمل وما يحتاج حسابك

- **أندرويد FCM:** يحتاج مشروع Firebase أنت (مجاني) + `google-services.json` في `android/app/` + `firebase_options.dart` مولّد (`flutterfire configure`) + مفتاح الخدمة لدالة `push`. **بلا هذا الحساب: كل التطبيق يعمل والإشعارات فقط لا تصل.**
- **ويب Web Push (036):** يحتاج زوج VAPID منك (`WEB_PUSH_VAPID_PRIVATE_KEY` و`WEB_PUSH_VAPID_SUBJECT`) — توليد بمكتبة web-push القياسية.
- **iOS:** إشعاراته APNs عبر FCM نفسه بعد حساب Apple Developer (بند 99$ بيد المالك في خارطة القمة الثانية).

## 8) النسخ الاحتياطي — لا تشغّل خادماً بلاها

```sh
# يومياً عبر cron على خادمك
pg_dump "postgres://postgres:كلمة_المرور@127.0.0.1:5432/postgres" \
  -Fc -f /backups/wasl-$(date +\%F).dump
```

واحذف ما عداه 14 يوماً (`find /backups -mtime +14 -delete`)، وانسخ دورياً خارج الخادم (rclone إلى قرصك). **مجلد الوسائط المشفرة** في تخزين Supabase ذاتي الاستضافة على القرص نفسه — انسخه مع القاعدة، فبلا بايتات الوسائط تبقى الرسائل النصية فقط مفهومة.

> صدق التشفير: الوسائط والنصوص مخزّنة مشفرة لا يفكها خادمك أصلاً — النسخة الاحتياطية تحمل نفس التشفير، ولا يحتاج استرجاعها سوى قاعدة البيانات نفسها وملفات `.enc.bin` كما هي.

## 9) الصيانة الدورية

1. **الترحيلات الجديدة مع كل إصدار:** راقب `supabase/` في المستودع — كل إصدار يضيف ترحيلاً مرقماً بتحققاته (نفّذ بترتيب الأرقام حصراً).
2. **تحديث الصورة:** `docker compose pull && docker compose up -d` شهرياً.
3. **إعادة نشر الدوال عند تحديث الكود:** انسخ `supabase/functions/` الجديدة إلى حاوية edge-runtime وأعد تشغيلها.
4. **مراقبة:** سجلات حاوية `db` و`edge-runtime` و`realtime` — أي خطأ RLS متكرر يعني ترحيلاً فاتك.

## 10) ما لا يغطيه هذا الدليل بصدق

- **توقيع المتجر:** نشر Google Play / App Store لحزمة خادمك الخاص قرار تجاري مستقل بمالكه (25$/99$) — لا علاقة للبنية هنا.
- **الويب PWA** المستضاف على waslchat.app يخدم الخادم الرسمي — استضافة نسختك الويبية تكملة طبيعية (بناء `flutter build web` ورفعه على دومينك).
- **الأداء والسعة:** أرقام التحميل تعتمد خادمك أنت — لا ننسب لأداء وصل أي رقم عن بنيتك الخاصة حتى تقيسه بنفسك.

## 11) حزمة الضغطة الواحدة — `self-hosting/` (2.0.0)

بنود «وصل سيرفر» من المرحلة 20 صار **حزمة ناشِرة** لا دليلاً يُتتبع يدوياً:

| الملف | ماذا يفعل |
|---|---|
| `self-hosting/docker-compose.yml` | طبقة وصل فوق توزيعة Supabase الرسمية: **edge-runtime** بدوال وصل السبع من `supabase/functions/` مباشرة، و**coturn** بمتغيرات موثقة، و**backup** بنسخة يومية للقاعدة ومجلد الوسائط باحتجاز 14 يوماً |
| `self-hosting/.env.example` | كل المتغيرات بجدول §5 نفسه — الفارغ يعني «الميزة معطلة بصدق» ولا انفجار |
| `self-hosting/deploy.sh` | فحص Docker، توليد `.env` بكلمات مولدة إن غاب، تنفيذ الترحيلات **بترتيبها الرقمي حصراً** عبر حاوية postgres مؤقتة (فجوة 030 مقصودة)، ثم `docker compose up -d` وحالة صادقة |
| `self-hosting/README.md` | صفحة الحزمة: ماذا تنشر وماذا لا تفعل — الحدود الصادقة الأربعة |

```sh
cd self-hosting && ./deploy.sh        # أو SKIP_MIGRATIONS=1 ./deploy.sh
```

**الحدود الصادقة للحزمة نفسها:** لا تستبدل توزيعة Supabase (شغّلها أولاً وفق §2)؛ لا TLS — وكيلك العكسي على `/functions/v1/*` → `127.0.0.1:9099`؛ لا أسرار مضمّنة — كل قيمة من `.env` الذي تملكه؛ لا توجيه تلقائي للتطبيق — `config.dart` وبناء APK بتوقيعك قرارك وفق §4.
