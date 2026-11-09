-- وصل شات 0.4.8: ضغط الفيديو ومصغّراته داخل التشفير (بند المرحلة 1)
-- شغّله في SQL Editor بعد 025_contact_discovery.sql
--
-- التصميم الصادق:
-- - الضغط والمصغّرة كلها على جهاز المرسل بمُرمّزات المنصة (بلا ffmpeg
--   وبلا مكتبات C).
-- - المصغّرة (إطار JPEG ≤ 18000 بايت ≈ ≤ 24000 حرف base64) تُدرج داخل
--   meta الرسالة المشفّرة نفسها — الخادم يرى نصاً مشفراً يبدأ بـ`v1.`
--   ولا يرى بيكسلات المصغّرة إطلاقاً.
-- - هذا الترحيل يوسّع قيد طول المحتوى لرسائل الفيديو فقط (30000 حرفاً)
--   ليتسع للمصغّرة مع الاسم والأحجام — بقية الأنواع تبقى على 4000 كما
--   هي دون أي فكّ.
-- - لا أعمدة جديدة ولا دالات جديدة ولا تغيير في الإشعارات.

alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (type = 'text' and char_length(content) between 1 and 4000)
  or (type in ('poll', 'poll_vote', 'location', 'contact')
      and media_url is null and char_length(content) between 1 and 4000)
  or (type in ('image', 'voice', 'file')
      and media_url is not null and char_length(coalesce(content, '')) <= 4000)
  -- الفيديو فقط: سقف أعلى ليتسع للمصغّرة المشفّرة داخل meta
  or (type = 'video'
      and media_url is not null and char_length(coalesce(content, '')) <= 30000));
