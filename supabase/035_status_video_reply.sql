-- وصل شات v0.27.0 (المرحلة 11 ب): فيديو الحالات والرد بحالة — ترحيل 035
-- شغّله في SQL Editor بعد 034_key_transparency.sql
--
-- الفكرة الصادقة:
-- 1) فيديو الحالات: نفس نمط التشفير القائم حرفياً — مفتاح محتوى عشوائي لكل
--    حالة، والبايتات تُشفَّر AES-256-GCM بسياق معرف الحالة وتُرفع .enc.bin،
--    والمفتاح يُغلَّف لكل مشاهد بنمط أظرفة المجموعات. الخادم لا يرى إلا
--    بايتات مشفرة — ما يتغير هنا فقط هو سماح «kind = video» بجوار نص وصورة.
-- 2) الرد بحالة: عمود reply_to يشير لحالة أصلية حية يشترك رادُها وصاحبها
--    بمحادثة فردية بلا حظر — يُفرض في سياسة RLS للإدراج (قيود CHECK لا
--    تقبل استعلامات فرعية في PostgreSQL)، ويموت مرجعاً بحذف الأصل
--    (on delete set null) فتصبح الحالة عادية بلا ادعاء ردّ ميت.

-- 1) توسيع نوع الحالة -------------------------------------------------------

alter table public.statuses drop constraint if exists statuses_kind_check;
alter table public.statuses add constraint statuses_kind_check
  check (kind in ('text', 'image', 'video'));

alter table public.statuses drop constraint if exists statuses_media_check;
alter table public.statuses add constraint statuses_media_check check (
  (kind = 'text' and media_path is null)
  or (kind in ('image', 'video') and media_path is not null)
);

-- 2) عمود الرد بحالة ---------------------------------------------------------

alter table public.statuses add column if not exists reply_to uuid
  references public.statuses(id) on delete set null;
create index if not exists statuses_reply_to_idx on public.statuses (reply_to);

-- 3) سياسة الإدراج تتحقق من حيّة الأصل وعضوته --------------------------------

drop policy if exists "statuses insert own" on public.statuses;
create policy "statuses insert own" on public.statuses
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and (
      reply_to is null
      or exists (
        select 1 from public.statuses s
        where s.id = statuses.reply_to
          and s.expires_at > now()
          and public.share_dm(s.user_id, auth.uid())
          and not exists (
            select 1 from public.blocks b
            where (b.blocker = auth.uid() and b.blocked = s.user_id)
               or (b.blocker = s.user_id and b.blocked = auth.uid())
          )
      )
    )
  );

-- 4) تغذية الحالات تعيد مرجع الرد --------------------------------------------

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
  reply_to uuid,
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
    s.reply_to,
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
