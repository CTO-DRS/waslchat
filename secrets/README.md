# أسرار وصل شات (مستودع خاص فقط)

- `wasl-release.jks`: مفتاح توقيع الإصدارات. alias `wasl`. SHA-1 `A3:27:55:B2:55:F2:CF:32:9D:05:D4:08:0A:2E:07:19:50:88:10:2E`.
  **إن فُقد لا يمكن تحديث التطبيق على المتجر.** احتفظ بنسخة خارج GitHub أيضاً.
- `key.properties`: كلمة مرور المفتاح.
- `wasl-debug.jks`: مفتاح التطوير القديم (غير مهم).

## أسرار مخزّنة في أماكن أخرى (القيم غير موجودة هنا)
- GitHub Actions secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`.
- Supabase Edge Function secrets (مشروع hplzbillnbdjtufazrlp): `GEMINI_API_KEY`, `GEMINI_MODEL`, `FCM_SERVICE_ACCOUNT`, `WEBHOOK_SECRET`.
- Supabase: كلمة مرور قاعدة البيانات، ومفتاح service_role (من لوحة Supabase > Settings > API).
- Google Cloud `wasl-chat-ac7d3`: OAuth client secret (من Credentials).
- Firebase: حساب الخدمة (Project settings > Service accounts).

## الحسابات (أسماء الدخول فقط — كلمات المرور في خزنة Hark ولا يمكن تصديرها)
| الخدمة | اسم الدخول | ملاحظة |
|---|---|---|
| Spaceship (الدومين waslchat.app) | `ctodrs` | الدخول باسم المستخدم لا بالإيميل. التجديد 2027-11-11 |
| Supabase | cto.drs@gmail.com | مشروع wasl-chat، ref hplzbillnbdjtufazrlp |
| Supabase قاعدة البيانات | `postgres` | كلمة المرور في الخزنة (يُنصح بتغييرها) |
| GitHub | CTO-DRS | مستودعا wasl-chat (خاص) وwaslchat (عام) |
| Google Cloud / Firebase | drsorb@gmail.com | مشروع wasl-chat-ac7d3 |
| Brevo (SMTP) | cto.drs@gmail.com | الإعداد غير مكتمل |
| PayPal (التبرعات) | cto.drs@gmail.com | |
| Porkbun | pr.drs.rs@gmail.com | غير مستخدم (الدومين اشتُري من Spaceship) |
| البريد التجاري | contact@waslchat.app | تحويل مجاني إلى cto.drs@gmail.com |

> لعرض كلمة مرور: من خزنة Hark أو من «نسيت كلمة المرور» في الخدمة نفسها. إن أردت حفظها هنا، أضفها بنفسك في ملف `secrets/passwords.md` من GitHub.
