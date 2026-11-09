-- وصل شات 0.4.1: الحالات/القصص (24 ساعة) مشفّرة لجهات الاتصال — المرحلة 1 (سد الفجوة مع واتساب)
-- شغّله في SQL Editor بعد 018_group_invites.sql
--
-- الفكرة: الحالة محتواها مشفّر بين الطرفين بمفتاح عشوائي لكل حالة (AES-256-GCM)،
-- ويُغلَّف هذا المفتاح لكل جهة اتصال بنمط أظرف المجموعات (007):
--   HKDF( X25519(الناشر↔جهة الاتصال), salt = story_id, info = 'wasl-story-v1' )
-- «جهات الاتصال» = من تربطك به محادثة فردية قائمة (تُفحص على الخادم بـ are_contacts،
-- لا يثق بالعميل). الانتهاء بعد 24 ساعة مفروض من مشغّل BEFORE INSERT، والصفوف المنتهية
-- يحذفها مجدول pg_cron كل 15 دقيقة، وملفاتها تُسجَّل في media_trash فتحذفها دالة
-- media-cleanup الموجودة خلال ساعة (نفس مسار الرسائل المحذوفة/المختفية).
--
-- ما يراه الخادم بصراحة (موثّق في TRANSPARENCY.md): مَن نشر حالة ومتى ولمتى، نوعها
-- (صورة/فيديو/نص) ولون خلفية النصية وحجم الملف المشفّر، وقائمة المشاهدين وأوقات مشاهدهم.
-- المحتوى نفسه (الصورة/الفيديو/التعليق) لا يراه الخادم.

-- 1) جدول الحالات
create table if not exists public.stories (
  id uuid primary key, -- يولّده العميل (v4) لأن AAD للتشفير = المعرّف نفسه
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('image', 'video', 'text')),
  media_path text, -- مسار في bucket stories بالصيغة <user_id>/<story_id>.enc.bin (null للنصية)
  caption text check (char_length(caption) between 1 and 4000), -- مشفّرة v1.* (تعليق أو نص الحالة)
  bg text check (bg in ('indigo', 'teal', 'violet', 'sunset', 'night')), -- خلفية النصية فقط
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  check ((type in ('image', 'video') and media_path is not null)
      or (type = 'text' and caption is not null and bg is not null))
);
create index if not exists stories_author_time on public.stories (user_id, created_at desc);
create index if not exists stories_expires_idx on public.stories (expires_at);

-- الوقت والانتهاء يضبطهما الخادم دائماً: 24 ساعة من النشر، ولا يثق بتاريخ العميل
create or replace function public.stories_force_ttl()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  new.expires_at := now() + interval '24 hours';
  return new;
end; $$;
drop trigger if exists stories_force_ttl on public.stories;
create trigger stories_force_ttl before insert on public.stories
  for each row execute function public.stories_force_ttl();

-- حذف أي حالة يسجّل ملفها في سلة الوسائط (نفس مسار 013)
create or replace function public.stories_trash_media()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.media_path is not null then
    insert into media_trash (path) values (old.media_path) on conflict do nothing;
  end if;
  return old;
end; $$;
drop trigger if exists stories_trash_media on public.stories;
create trigger stories_trash_media after delete on public.stories
  for each row execute function public.stories_trash_media();

-- 2) جهات الاتصال: من تربطك به محادثة فردية قائمة
create or replace function public.are_contacts(a uuid, b uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants x
    join conversation_participants y on y.conversation_id = x.conversation_id
    join conversations c on c.id = x.conversation_id
    where x.user_id = a and y.user_id = b and c.is_group = false
      and c.kind = 'chat' and c.community_id is null
  );
$$;

-- قائمة جهات اتصالي (لنشر حالة: مَن سيُغلَّف له المفتاح، ولعدّاد المعاينة)
create or replace function public.my_contacts()
returns table (id uuid, name text, avatar_url text)
language sql security definer stable set search_path = public as $$
  select distinct p.id, coalesce(p.display_name, p.username), p.avatar_url
  from conversation_participants me
  join conversation_participants o
    on o.conversation_id = me.conversation_id and o.user_id <> me.user_id
  join conversations c on c.id = me.conversation_id
  join profiles p on p.id = o.user_id
  where me.user_id = auth.uid() and c.is_group = false
    and c.kind = 'chat' and c.community_id is null
  order by 2;
$$;

-- 3) أظرف مفاتيح الحالات (نمط 007): ظرف واحد لكل (حالة، جهة)
create table if not exists public.story_key_envelopes (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  wrapped_key text not null check (char_length(wrapped_key) between 10 and 700),
  wrapped_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (story_id, user_id)
);
create index if not exists story_envelopes_user on public.story_key_envelopes (user_id);
alter table public.story_key_envelopes enable row level security;
-- الناشر وحده يضيف أظرفاً لحالته، وكل مستخدم يقرأ ظرفه هو فقط
drop policy if exists "story envelopes read own" on public.story_key_envelopes;
create policy "story envelopes read own" on public.story_key_envelopes
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "story envelopes insert by author" on public.story_key_envelopes;
create policy "story envelopes insert by author" on public.story_key_envelopes
  for insert to authenticated with check (
    wrapped_by = auth.uid()
    and exists (select 1 from stories s where s.id = story_id and s.user_id = auth.uid()));

-- 4) المشاهدات: صاحب الحالة يرى من شاهد، والمشاهد يرى مشاهده هو
create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);
alter table public.story_views enable row level security;
drop policy if exists "story views read" on public.story_views;
create policy "story views read" on public.story_views
  for select to authenticated
  using (viewer_id = auth.uid()
         or exists (select 1 from stories s
                     where s.id = story_id and s.user_id = auth.uid()));
drop policy if exists "story views insert" on public.story_views;
create policy "story views insert" on public.story_views
  for insert to authenticated with check (
    viewer_id = auth.uid()
    and exists (select 1 from stories s where s.id = story_id
                 and s.expires_at > now()
                 and (s.user_id = auth.uid() or public.are_contacts(s.user_id, auth.uid()))));

-- 5) سياسات الحالات نفسها
alter table public.stories enable row level security;
drop policy if exists "stories read" on public.stories;
create policy "stories read" on public.stories
  for select to authenticated
  using (user_id = auth.uid()
         or (expires_at > now() and public.are_contacts(user_id, auth.uid())));
drop policy if exists "stories insert own" on public.stories;
create policy "stories insert own" on public.stories
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "stories delete own" on public.stories;
create policy "stories delete own" on public.stories
  for delete to authenticated using (user_id = auth.uid());
-- (لا سياسة update: الحالة غير قابلة للتعديل بعد النشر)

-- 6) تغذية الحالات: حالات جهات الاتصال النشطة مع ظرفي أنا (استعلام واحد)
create or replace function public.stories_feed()
returns table (
  story_id uuid, author_id uuid, author_name text, author_avatar text,
  type text, media_path text, caption text, bg text,
  created_at timestamptz, expires_at timestamptz, wrapped_key text
) language sql security definer stable set search_path = public as $$
  select s.id, s.user_id, coalesce(p.display_name, p.username), p.avatar_url,
         s.type, s.media_path, s.caption, s.bg,
         s.created_at, s.expires_at, e.wrapped_key
  from stories s
  join story_key_envelopes e on e.story_id = s.id and e.user_id = auth.uid()
  join profiles p on p.id = s.user_id
  where s.expires_at > now()
    and s.user_id <> auth.uid()
    and public.are_contacts(s.user_id, auth.uid())
  order by s.created_at asc;
$$;

-- حالاتي النشطة مع عدد المشاهدين (أعرضها في عارض حالاتي)
create or replace function public.my_stories()
returns table (
  story_id uuid, author_id uuid, type text, media_path text, caption text, bg text,
  created_at timestamptz, expires_at timestamptz, wrapped_key text,
  views bigint
) language sql security definer stable set search_path = public as $$
  select s.id, auth.uid(), s.type, s.media_path, s.caption, s.bg,
         s.created_at, s.expires_at, e.wrapped_key,
         (select count(*) from story_views v where v.story_id = s.id)
  from stories s
  join story_key_envelopes e on e.story_id = s.id and e.user_id = auth.uid()
  where s.user_id = auth.uid() and s.expires_at > now()
  order by s.created_at asc;
$$;

-- مشاهدة حالة (لصاحبها فقط بعد فحص الملكية) — تتجاهل التكرار
create or replace function public.story_viewers(p_story uuid)
returns table (viewer_id uuid, name text, avatar_url text, viewed_at timestamptz)
language sql security definer stable set search_path = public as $$
  select v.viewer_id, coalesce(p.display_name, p.username), p.avatar_url, v.viewed_at
  from story_views v join profiles p on p.id = v.viewer_id
  where v.story_id = p_story
    and exists (select 1 from stories s where s.id = p_story and s.user_id = auth.uid())
  order by v.viewed_at desc;
$$;

revoke execute on function public.my_contacts() from public, anon;
revoke execute on function public.stories_feed() from public, anon;
revoke execute on function public.my_stories() from public, anon;
revoke execute on function public.story_viewers(uuid) from public, anon;
grant execute on function public.my_contacts() to authenticated;
grant execute on function public.stories_feed() to authenticated;
grant execute on function public.my_stories() to authenticated;
grant execute on function public.story_viewers(uuid) to authenticated;

-- 7) التخزين الخاص للحالات (bucket مستقل عن وسائط المحادثات)
insert into storage.buckets (id, name, public)
values ('stories', 'stories', false)
on conflict (id) do nothing;
update storage.buckets set file_size_limit = 26214400 where id = 'stories'; -- 24 م.ب

drop policy if exists "stories bucket read" on storage.objects;
create policy "stories bucket read" on storage.objects
  for select to authenticated
  using (bucket_id = 'stories'
         and ((storage.foldername(name))[1] = auth.uid()::text
              or public.are_contacts(((storage.foldername(name))[1])::uuid, auth.uid())));

drop policy if exists "stories bucket upload own" on storage.objects;
create policy "stories bucket upload own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'stories'
              and (storage.foldername(name))[1] = auth.uid()::text);
-- (بلا سياسة حذف للعميل: الحذف عبر media_trash بدور الخدمة فقط)

-- 8) حذف الحالات المنتهية كل 15 دقيقة (صفوفها مخفية أصلاً بـRLS قبل حذفها)
create or replace function public.purge_expired_stories()
returns void language sql security definer set search_path = public as $$
  delete from stories where expires_at < now();
$$;
revoke execute on function public.purge_expired_stories() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule('wasl-purge-stories');
exception when others then null; end $$;
select cron.schedule('wasl-purge-stories', '*/15 * * * *', 'select public.purge_expired_stories()');
