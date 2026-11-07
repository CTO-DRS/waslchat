-- وصل شات 0.1.8: رسائل الملفات والفيديو، وتنظيف ملفات الرسائل المحذوفة والمختفية
-- شغّله بعد 012_disappearing_stars.sql. ثم انشر الدالة supabase/functions/media-cleanup.

-- 1) أنواع جديدة. بيانات الملف (الاسم والحجم) داخل content، مشفّرة في المحادثات المشفّرة
alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'voice', 'video', 'file'));
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (type = 'text' and char_length(content) between 1 and 4000)
  or (type <> 'text' and media_url is not null and char_length(coalesce(content, '')) <= 4000));

-- حد حجم الملف في التخزين الخاص (25 ميغابايت)
update storage.buckets set file_size_limit = 26214400 where id = 'chat-media';

-- 2) سلة الملفات: كل وسيط لرسالة حُذفت أو اختفت يُسجَّل هنا ثم تحذفه الدالة
create table if not exists public.media_trash (
  path text primary key,
  created_at timestamptz not null default now()
);
alter table public.media_trash enable row level security; -- بلا سياسات: للخادم فقط

create or replace function public.messages_trash_media()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    if old.media_url is not null then
      insert into media_trash (path) values (old.media_url) on conflict do nothing;
    end if;
    return old;
  end if;
  if new.deleted_at is not null and old.deleted_at is null and old.media_url is not null then
    insert into media_trash (path) values (old.media_url) on conflict do nothing;
  end if;
  return new;
end; $$;
drop trigger if exists messages_trash_media on public.messages;
create trigger messages_trash_media after delete or update of deleted_at on public.messages
  for each row execute function public.messages_trash_media();

-- ما حُذف قبل هذا الترحيل ولم يُنظَّف
insert into media_trash (path)
  select media_url from messages where deleted_at is not null and media_url is not null
  on conflict do nothing;

-- 3) استدعاء الدالة كل ساعة بنفس سر الـWebhook المستخدم في إشعارات الدفع
do $$
declare src text; secret text;
begin
  select prosrc into src from pg_proc where proname = 'notify_push' limit 1;
  secret := substring(src from '''x-webhook-secret''\s*,\s*''([^'']+)''');
  if secret is null then raise exception 'webhook secret not found'; end if;
  begin perform cron.unschedule('wasl-media-cleanup'); exception when others then null; end;
  perform cron.schedule('wasl-media-cleanup', '7 * * * *', format(
    $f$select net.http_post(url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/media-cleanup',
       headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', %L),
       body := '{}'::jsonb)$f$, secret));
end $$;
