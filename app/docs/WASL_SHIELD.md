# Wasl Shield — نظام الحماية ومكافحة الابتزاز (1.10.0)

> النسخة العربية أولاً، ثم English summary.

## 1. الهدف
حماية مستخدمي وصل شات من الابتزاز والتهديد بالصور والفيديو والتحرّش وانتحال الشخصية،
مع بلاغ سرّي يصل **مباشرة للمدير العام** (بلا فريق وسيط)، وإجراءات حماية عاجلة موثّقة بسجل تدقيق.

## 2. البنية
| الطبقة | المكوّن |
|---|---|
| قاعدة البيانات | `supabase/041_wasl_shield.sql` |
| الخادم (Edge) | `supabase/functions/shield-admin` (حجر الوسائط + الاحتفاظ) |
| الخدمة في التطبيق | `lib/services/shield_service.dart` |
| واجهة المستخدم | `lib/screens/shield_screen.dart`، `lib/widgets/shield_report_sheet.dart`، تعديلات `chat_screen.dart` و`media_bubbles.dart` |
| لوحة المدير | `lib/screens/shield_admin_screen.dart` (من الإعدادات ← لوحة الإدارة) |
| أندرويد | `MainActivity.kt` قناة `wasl/shield` + صلاحيتا `DETECT_SCREEN_CAPTURE`/`DETECT_SCREEN_RECORDING` |
| iOS | `AppDelegate.swift` (UIScreen.isCaptured + إشعار لقطة الشاشة) — **لم يُبنَ/يُختبر بعد** |
| الاختبارات | `supabase/tests/shield_security_test.py` |

## 3. قاعدة البيانات
- `shield_settings` (لكل مستخدم، RLS: صاحبها فقط).
- `shield_cases` البلاغات: النوع، الخطورة (يحسبها الخادم)، الحالة، الاحتفاظ. RLS: المبلِّغ يقرأ بلاغاته فقط؛ المبلَّغ عنه لا يرى شيئاً.
- `shield_evidence` الأدلة (مسار، نوع، حجم، SHA-256). بلا سياسات — عبر الدوال فقط.
- `shield_quarantine` الوسائط المنقولة للحجر.
- `shield_restrictions` منع إرسال الوسائط.
- `shield_audit` سجل تدقيق **إضافة فقط**: مُشغِّلات تمنع UPDATE/DELETE/TRUNCATE، وكل قيد مسلسل بتجزئة SHA-256 للقيد السابق.
- أعمدة جديدة في `messages`: `protected` (يضعه الخادم إن كانت حماية المرسل مفعّلة)، `shield_removed`.
- مخزنان خاصان: `shield-evidence` (رفع للمبلِّغ في مجلد بلاغه، قراءة للمدير **فقط بعد قيد تدقيق "فتح دليل" خلال دقيقتين**)، `shield-quarantine` (لا قراءة من التطبيق إطلاقاً).

## 4. واجهات API (RPC)
**المستخدم:** `shield_report`، `shield_add_evidence`، `shield_my_cases`.
**المدير (is_app_admin):** `shield_admin_cases`، `shield_admin_case`، `shield_admin_open_evidence`، `shield_admin_set_status`، `shield_admin_message_reporter`، `shield_admin_thread`، `shield_admin_suspend`، `shield_admin_restrict_media`، `shield_admin_case_media`، `shield_admin_audit`، `shield_admin_verify_audit`.
**الخدمة فقط:** `shield_service_mark_quarantined`، `shield_service_expired`، `shield_service_purge_case`.
**Edge:** `POST /functions/v1/shield-admin` بـ`action=quarantine` (JWT مدير + مبرر) أو `action=retention` (سر الويب هوك من pg_cron يومياً 03:17 UTC).
كل إجراء إداري يتطلب مبرراً (5 أحرف على الأقل) ويُسجَّل.

## 5. استقبال البلاغ
1. المستخدم: المحادثة ← المزيد ← «بلاغ عاجل» (أو من خيارات رسالة: «بلاغ عاجل عن المرسل»).
2. يختار النوع ويكتب الوصف ويحدد الرسائل والوسائط (تُفك على جهازه لأن الخادم لا يقرأ المشفّر).
3. الخادم يتحقق: علاقة حقيقية بالمبلَّغ عنه (محادثة خاصة مشتركة أو رسالة منه في محادثة مشتركة — الغرف الرسمية لا تكفي)، حد 5 بلاغات/24 ساعة، صحة الحقول.
4. حظر صامت اختياري (نفس الحظر العادي).
5. إشعار فوري للمدير: رسالة من «دعم وصل شات» في محادثته (خط FCM القائم) — دون أسماء.
6. تأكيد للمبلِّغ في محادثة الدعم؛ والمدير يراسله من اللوحة باسم «دعم وصل شات».

## 6. إبطال روابط الوسائط
- روابط Supabase الموقّعة لا تُلغى قبل انتهائها، لذلك الإبطال = **نقل الملف** من `chat-media` إلى `shield-quarantine`.
- كل رابط سابق يتعطل؛ الاختبار الفعلي أظهر بقاءه ~40 ثانية بسبب ذاكرة CDN، ثم 404.
- الرسالة تُعلَّم `shield_removed` فتظهر «أُزيلت هذه الوسائط للحماية».
- النسخة في الحجر تبقى دليلاً، ولا يقرؤها التطبيق.
- **لا يمكن** حذف ما حُفظ على أجهزة الآخرين، ولا تدّعي الواجهة ذلك.

## 7. حماية الوسائط والشاشة
- أندرويد: `FLAG_SECURE` لكل الشاشات عند تفعيل «حماية الشاشات»، ولعارض الوسائط المحمية ولوحة البلاغات دائماً. تنبيه لقطة الشاشة (API 34+) وتسجيلها (API 35+).
- iOS: إخفاء المحتوى أثناء التسجيل/البث، تنبيه بعد اللقطة (لا يمكن منعها).
- الويب: لا منع للالتقاط؛ صلاحيات الخادم فقط.
- الوسائط المحمية: لا توجيه، لا فتح خارج التطبيق، علامة مائية باسم المشاهد ووقت العرض.
- لا شيء يمنع التصوير بكاميرا خارجية.

## 8. الخصوصية والاحتفاظ
- التشفير أثناء النقل (TLS) والتخزين (تشفير Supabase/AWS AES-256 عند السكون). **ليس** تشفيراً طرفياً بمفتاح المدير — قيد معروف (انظر 10).
- الاطلاع: المدير فقط، وكل فتح دليل يُسجَّل قبل السماح به.
- الاحتفاظ: لا حذف والبلاغ مفتوح؛ بعد الإغلاق 180 يوماً ثم حذف تلقائي للأدلة والحجر (سجل التدقيق يبقى).
- لا تُرسل الأدلة لأي خدمة ذكاء اصطناعي.

## 9. التشغيل والنشر والتراجع
- تطبيق الترحيل: تشغيل `041_wasl_shield.sql` في SQL Editor (طُبّق على الإنتاج 2026-11-19 — إضافي فقط).
- نشر الدالة: `shield-admin` بـ`verify_jwt=false` (تتحقق من JWT بنفسها).
- البناء: فرع `feature/wasl-shield` يُبنى بلا نشر؛ الدمج في `app` ينشر الإصدار.
- التراجع: إسقاط المشغّلين `messages_shield_defaults` و`messages_shield_guard` يعيد سلوك الرسائل كما كان؛ الجداول الجديدة لا تؤثر على غيرها. لا تحذف `shield_audit`.

## 10. القيود والثغرات المتبقية
1. الأدلة ليست مشفّرة طرفياً لمفتاح المدير (مقترح لاحق: تغليف بمفتاح X25519 لجهاز المدير).
2. المدير يملك صلاحية is_app_admin؛ الحماية من مدير خبيث هي سجل التدقيق فقط.
3. الروابط السابقة تبقى صالحة ~دقيقة بعد الإبطال (CDN).
4. منع الحفظ والتوجيه للوسائط المحمية يُطبَّق في التطبيق؛ عميل معدّل يستطيع تجاوزه.
5. iOS لم يُبنَ في CI بعد؛ كود Swift غير مُختبر.
6. اكتشاف التسجيل على أندرويد يحتاج 15+، واللقطة 14+.

---

# English summary
Wasl Shield adds an opt-in protection layer and a confidential reporting flow that routes every report **directly to the general admin**.
- **DB:** `041_wasl_shield.sql` — cases, evidence, quarantine, restrictions, settings, and an append-only, SHA-256 hash-chained audit log (UPDATE/DELETE/TRUNCATE blocked by triggers).
- **Evidence:** uploaded by the reporter from their device (E2E text is unreadable server-side) into a private bucket; the admin can read an object only after an audited `evidence_open` entry within the last 2 minutes (enforced by storage RLS).
- **Revocation:** signed URLs can't be revoked early, so media is moved to a quarantine bucket via the `shield-admin` Edge Function; old links died after ~40 s in testing (CDN cache).
- **Client:** settings screen, urgent-report screen with evidence picker, protected media (no forward/external open, viewer watermark, FLAG_SECURE), capture detection (Android 14/15+, iOS isCaptured), admin dashboard (cases by severity, evidence, actions with mandatory justification, reporter messaging, audit viewer and chain verification).
- **Limits:** no remote deletion from other devices, no camera blocking, evidence not E2E-sealed to the admin key yet, client-side enforcement of no-save/forward, iOS code not yet built.
- **Tests:** `supabase/tests/shield_security_test.py` (real API calls with throwaway accounts).
