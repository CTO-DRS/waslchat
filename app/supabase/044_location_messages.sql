-- 044: نوع رسالة «الموقع» (2.3.0)
-- الإحداثيات تُخزَّن في content وتُشفَّر كالنص تماماً في الخاص والمجموعات،
-- بلا media_url — لذا يُمدَّد قيدا type وcontent ليشملان location.

alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'voice', 'video', 'file', 'location'));

alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages add constraint messages_body_check
  check ((type = 'text' and char_length(content) between 1 and 4000)
      or (type = 'location' and char_length(content) between 1 and 4000)
      or (type <> 'text' and type <> 'location' and media_url is not null));
