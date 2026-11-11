# البنية التحتية والحسابات — وصل شات

> مستودع خاص. لا كلمات مرور هنا (إلا ما في `secrets/`). آخر تحديث: 2026-11-11.

## التواصل
- بريد المطوّر/المالك: **cto.drs@gmail.com**
- البريد التجاري: **contact@waslchat.app** (تحويل مجاني من Spaceship > Email Forwarding إلى cto.drs@gmail.com، استقبال فقط؛ الرد يكون من Gmail). هو المعروض في الموقع.
- مرسل رسائل التطبيق المستقبلي: `no-reply@waslchat.app` (عبر Brevo، لم يُفعَّل بعد)

## الدومين `waslchat.app`
| البند | القيمة |
|---|---|
| المسجّل | Spaceship (spaceship.com) |
| حساب Spaceship | اسم المستخدم `ctodrs` (الدخول باسم المستخدم لا بالإيميل) |
| تاريخ التسجيل | 2026-11-11 |
| تاريخ الانتهاء/التجديد | 2027-11-11 (فعّل التجديد التلقائي لتجنّب فقدانه) |
| Nameservers | `launch1.spaceship.net`, `launch2.spaceship.net` |
| ملاحظة | نطاق `.app` يفرض HTTPS دائماً (HSTS preload) |

### سجلات DNS (Spaceship > Advanced DNS)
| النوع | المضيف | القيمة |
|---|---|---|
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| AAAA | @ | 2606:50c0:8000::153 |
| AAAA | @ | 2606:50c0:8001::153 |
| AAAA | @ | 2606:50c0:8002::153 |
| AAAA | @ | 2606:50c0:8003::153 |
| CNAME | www | cto-drs.github.io |
| MX (مُدار) | @ | mx1.efwd.spaceship.net, mx2.efwd.spaceship.net (أولوية 0) |
| TXT (مُدار) | @ | v=spf1 include:spf.efwd.spaceship.net ~all |

## الموقع https://waslchat.app
- مستضاف على GitHub Pages من المستودع **العام** `CTO-DRS/waslchat` (فرع main، الجذر). الصفحة الرئيسية `index.html` (موقع تعريفي بأسلوب واتساب) مع `hark.css` و`hark-hero.css` و`hark.js` والصور، وسياسة الخصوصية والشروط في `privacy/index.html` (https://waslchat.app/privacy/)، و`CNAME`.
- رابط التحميل الثابت: https://github.com/CTO-DRS/waslchat/releases/latest/download/wasl_chat.apk (ارفع APK كل إصدار كـRelease جديد في `CTO-DRS/waslchat` باسم `wasl_chat.apk`).
- مصدر الصفحة الرئيسية: صفحة Hark «Wasl Chat Official Site».
- الدومين المخصص `waslchat.app`، الشهادة من GitHub (تتجدد تلقائياً)، Enforce HTTPS مفعّل.
- `www.waslchat.app` والرابط القديم `cto-drs.github.io/waslchat` يحوّلان تلقائياً إلى https://waslchat.app/.
- للتعديل: عدّل `index.html` في `CTO-DRS/waslchat`.

## المستودعات
- `CTO-DRS/wasl-chat` (خاص): كود التطبيق، CI يبني APK عند كل دفع إلى main (`.github/workflows/build-apk.yml`). أسرار Actions: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`.
- `CTO-DRS/waslchat` (عام): الموقع فقط.

## Supabase (الخادم)
- مشروع `wasl-chat`، ref `hplzbillnbdjtufazrlp`، منطقة Frankfurt، خطة Free.
- URL: https://hplzbillnbdjtufazrlp.supabase.co — حساب Supabase: cto.drs@gmail.com.
- الترحيلات 001–013 مطبّقة (`supabase/`). التالي 014.
- Edge Functions: `ai`، `push`، `media-cleanup`.
- pg_cron: `wasl-purge-expired` (كل 15 دقيقة)، `wasl-media-cleanup` (كل ساعة).
- Auth: بريد + Google + TOTP. `mailer_autoconfirm` مفعّل مؤقتاً حتى ربط SMTP (Brevo).
- تنبيه: الخطة المجانية توقف المشروع بعد أسبوع خمول.

## Google Cloud / Firebase
- مشروع `wasl-chat-ac7d3` (حساب drsorb@gmail.com).
- OAuth consent «Wasl Chat» منشور (In production). روابط الـbranding ما زالت على github.io (تحوّل للدومين). نقلها للدومين يحتاج توثيق الدومين في Google Search Console (سجل TXT).
- Firebase (Spark): تطبيق أندرويد `app.waslchat.wasl_chat`، FCM V1 للإشعارات.

## خدمات أخرى
- Gemini API (طبقة مجانية) لميزات وصل AI، الموديل في سرّ `GEMINI_MODEL`.
- Brevo (SMTP مجاني): حساب cto.drs@gmail.com، الإعداد لم يكتمل.
- PayPal للدعم: الرابط في README و`.github/FUNDING.yml`.

## التطبيق
- معرّف الحزمة: `app.waslchat.wasl_chat`. الإصدار الحالي 0.1.8+15.
- مفتاح التوقيع: `secrets/wasl-release.jks` (alias `wasl`). **لا تفقده.**
- رابط الدخول العميق: `app.waslchat://login-callback`.

## أمان معلّق
- إلغاء رمز GitHub القديم المكشوف وإنشاء رمز جديد.
- تغيير كلمة مرور قاعدة بيانات Supabase.
- إبقاء المستودع `wasl-chat` خاصاً دائماً.
