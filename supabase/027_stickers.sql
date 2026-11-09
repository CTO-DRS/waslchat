-- وصل شات 0.4.9: الملصقات والصور المتحركة (بند المرحلة 1 — الاختياري الأخير)
-- شغّله في SQL Editor بعد 026_video_meta.sql
--
-- التصميم الصادق:
-- - الحزمة مدمجة داخل التطبيق (بلا خادم بلا كتالوج بلا إحصاء استخدام)،
--   وبايتات الملصق تُرفع في تخزين المحادثة داخل التشفير مثل أي صورة —
--   فالطرف الآخر يراها دون أن تكون لديه الحزمة أصلاً.
-- - meta الملصق (pack/id) نص صغير ثابت البنية يُشفَّر مع نص الرسالة.
-- - هذا الترحيل يضيف النوع 'sticker' فقط إلى قيد النوع، ويقبل صفوفه
--   بشرط وجود وسط + سقف المحتوى 4000 كما باقي أنواع الوسائط.
-- - لا أعمدة جديدة ولا دالات جديدة ولا تغيير في الإشعارات.

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'voice', 'video', 'file',
                  'poll', 'poll_vote', 'location', 'contact', 'sticker'));

alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (type = 'text' and char_length(content) between 1 and 4000)
  or (type in ('poll', 'poll_vote', 'location', 'contact')
      and media_url is null and char_length(content) between 1 and 4000)
  or (type in ('image', 'voice', 'file')
      and media_url is not null and char_length(coalesce(content, '')) <= 4000)
  -- الفيديو فقط: سقف أعلى ليتسع للمصغّرة المشفّرة داخل meta
  or (type = 'video'
      and media_url is not null and char_length(coalesce(content, '')) <= 30000)
  -- الملصق: وسط إلزامي ومحتوى صغير (pack/id المشفّر)
  or (type = 'sticker'
      and media_url is not null and char_length(coalesce(content, '')) <= 4000));
