-- وصل شات v0.7.0: الحالات/القصص المشفّرة بين الطرفين (24 ساعة) — المرحلة 1
-- شغّله في SQL Editor بعد 017_group_invites.sql
--
-- الفكرة: كل حالة تحمل مفتاح محتوى عشوائياً (32 بايت) يبقى على الأجهزة فقط.
--   يشفَّر النص/الوسيط بـ AES-256-GCM بسياق معرف الحالة، ويُغلَّف المفتاح لكل مشاهد
--   بـ HKDF-SHA256( X25519(خاصي صاحب الحالة، عامُ المشاهد), salt = status_id, info = 'wasl-group-v1' )
--   — نفس دوال تغليف مفاتيح المجموعات (007)، والسياق هنا معرف الحالة بدل المحادثة.
--   صاحب الحالة يغلّف المفتاح لنفسه أيضاً ليبقى قابلاً للعرض بعد إعادة تشغيل التطبيق.
-- المشاهدون: شركاء المحادثات الفردية الحاليون فقط، بلا حظر بينهم — يحددهم الخادم نهائياً.
-- الخادم لا يرى إلا نصوصاً مشفّرة وأظرفةً مغلقة، وتواريخ النشر وانتهاء العرض.
-- انتهاء العرض من الخادم: كل حالة تنتهي بعد 24 ساعة وتُحذف دورياً (pg_cron)، ووسائطها تمر
--   بسلة الوسائط (media_trash) فتنظّفها دالة media-cleanup الساعية القائمة.

-- 1) الجداول --------------------------------------------------------------

create table if not exists public.statuses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('text', 'image')),
  body text not null default '' check (char_length(body) <= 4000),
  media_path text,
  media_mime text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  constraint statuses_media_check check (
    (kind = 'text' and media_path is null)
    or (kind = 'image' and media_path is not null)
  )
);
create index if not exists statuses_author_time on public.statuses (user_id, created_at desc);

create table if not exists public.status_key_envelopes (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  wrapped_key text not null check (char_length(wrapped_key) between 20 and 700),
  created_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

create table if not exists public.status_views (
  status_id uuid not null references public.statuses(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_id)
);

alter table public.statuses enable row level security;
alter table public.status_key_envelopes enable row level security;
alter table public.status_views enable row level security;

-- 2) وظائف مساعدة ----------------------------------------------------------

-- هل يشارك المستخدمان محادثة فردية؟ (أو هما نفس الشخص)
create or replace function public.share_dm(a uuid, b uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select a = b or exists (
    select 1
    from conversation_participants x
    join conversation_participants y on y.conversation_id = x.conversation_id
    join conversations c on c.id = x.conversation_id and c.is_group = false
    where x.user_id = a and y.user_id = b
  );
$$;

-- 3) سياسات RLS ------------------------------------------------------------

-- الحالة: يقرأها صاحبها، أو شريك محادثة فردية بلا حظر بينهم ولم تنتهِ
drop policy if exists "statuses read by audience" on public.statuses;
create policy "statuses read by audience" on public.statuses
  for select to authenticated
  using (
    user_id = auth.uid()
    or (
      expires_at > now()
      and public.share_dm(user_id, auth.uid())
      and not exists (select 1 from blocks b
          where (b.blocker = auth.uid() and b.blocked = user_id)
             or (b.blocker = user_id and b.blocked = auth.uid()))
    )
  );

drop policy if exists "statuses insert own" on public.statuses;
create policy "statuses insert own" on public.statuses
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "statuses delete own" on public.statuses;
create policy "statuses delete own" on public.statuses
  for delete to authenticated
  using (user_id = auth.uid());

-- الأظرفة: المشاهد يقرأ ظرفه؛ الصاحب يقرأ أظرفة حالته ويضيف أظرفةً لجمهوره فقط
drop policy if exists "status envelopes read" on public.status_key_envelopes;
create policy "status envelopes read" on public.status_key_envelopes
  for select to authenticated
  using (
    viewer_id = auth.uid()
    or exists (select 1 from statuses s where s.id = status_id and s.user_id = auth.uid())
  );

drop policy if exists "status envelopes insert by author" on public.status_key_envelopes;
create policy "status envelopes insert by author" on public.status_key_envelopes
  for insert to authenticated
  with check (
    exists (select 1 from statuses s where s.id = status_id and s.user_id = auth.uid())
    and public.share_dm(viewer_id, auth.uid())
  );

-- المشاهدات: المشاهد يسجّل مشاهدته على حالة شاهدها فعلاً (شريك بلا حظر، لم تنتهِ)
drop policy if exists "status views insert by viewer" on public.status_views;
create policy "status views insert by viewer" on public.status_views
  for insert to authenticated
  with check (
    viewer_id = auth.uid()
    and exists (select 1 from statuses s
        where s.id = status_id and s.expires_at > now()
        and public.share_dm(s.user_id, auth.uid()))
  );

drop policy if exists "status views read by author or viewer" on public.status_views;
create policy "status views read by author or viewer" on public.status_views
  for select to authenticated
  using (
    viewer_id = auth.uid()
    or exists (select 1 from statuses s where s.id = status_id and s.user_id = auth.uid())
  );

-- 4) وسائط الحالات في حاوية chat-media: المجلد الأول = معرف الحالة ------------

drop policy if exists "status media read by audience" on storage.objects;
create policy "status media read by audience" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'chat-media'
    and exists (select 1 from public.statuses s
        where s.id = ((storage.foldername(name))[1])::uuid
        and (s.user_id = auth.uid()
             or (s.expires_at > now()
                 and public.share_dm(s.user_id, auth.uid())
                 and not exists (select 1 from blocks b
                     where (b.blocker = auth.uid() and b.blocked = s.user_id)
                        or (b.blocker = s.user_id and b.blocked = auth.uid())))))
  );

drop policy if exists "status media upload by author" on storage.objects;
create policy "status media upload by author" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and exists (select 1 from public.statuses s
        where s.id = ((storage.foldername(name))[1])::uuid
        and s.user_id = auth.uid())
  );

-- 5) تغذية الحالات: دالة واحدة تجلب كل شيء في نداء واحد ---------------------
-- حالتي + حالات شركاء المحادثات الفردية النشطة، مع ظرفي المفتاح وعلامة المشاهدة
-- وعدّاد المشاهدات لحالاتي.

create or replace function public.my_status_feed()
returns table (
  status_id uuid,
  author_id uuid,
  author_name text,
  author_avatar text,
  kind text,
  body text,
  media_path text,
  media_mime text,
  created_at timestamptz,
  expires_at timestamptz,
  wrapped_key text,
  viewed boolean,
  views_count int
) language sql security definer stable set search_path = public as $$
  with dmp as (
    select distinct o.user_id as uid
    from conversation_participants me
    join conversations c on c.id = me.conversation_id and c.is_group = false
    join conversation_participants o
      on o.conversation_id = me.conversation_id and o.user_id <> me.user_id
    where me.user_id = auth.uid()
  ),
  allowed as (
    select uid from dmp
    union select auth.uid()
  )
  select
    s.id,
    s.user_id,
    coalesce(p.display_name, p.username, 'مستخدم'),
    p.avatar_url,
    s.kind,
    s.body,
    s.media_path,
    s.media_mime,
    s.created_at,
    s.expires_at,
    (select e.wrapped_key from status_key_envelopes e
      where e.status_id = s.id and e.viewer_id = auth.uid()),
    exists (select 1 from status_views v
      where v.status_id = s.id and v.viewer_id = auth.uid()),
    (select count(*)::int from status_views v where v.status_id = s.id)
  from statuses s
  join profiles p on p.id = s.user_id
  where s.user_id in (select uid from allowed)
    and s.expires_at > now()
    and not exists (select 1 from blocks b
        where (b.blocker = auth.uid() and b.blocked = s.user_id)
           or (b.blocker = s.user_id and b.blocked = auth.uid()))
  order by s.created_at desc
$$;

revoke execute on function public.my_status_feed() from public, anon;
grant execute on function public.my_status_feed() to authenticated;

revoke execute on function public.share_dm(uuid, uuid) from public, anon;
grant execute on function public.share_dm(uuid, uuid) to authenticated;

-- 6) حذف الحالات المنتهية دورياً + تنظيف وسائطها ----------------------------
-- حذف الحالة يحذف أظرفها ومشاهداتها (تتالي)، ومُحفّز الحذف يسجّل الوسيط في
-- media_trash فتنظّفه دالة media-cleanup الساعية (المنشورة في 013).

create or replace function public.statuses_trash_media()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.media_path is not null then
    insert into media_trash (path) values (old.media_path) on conflict do nothing;
  end if;
  return old;
end; $$;

drop trigger if exists statuses_trash_media on public.statuses;
create trigger statuses_trash_media after delete on public.statuses
  for each row execute function public.statuses_trash_media();

do $$
begin
  begin perform cron.unschedule('wasl-status-expiry'); exception when others then null; end;
  perform cron.schedule('wasl-status-expiry', '*/20 * * * *',
    'delete from public.statuses where expires_at < now()');
end $$;
