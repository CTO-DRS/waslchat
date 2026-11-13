-- وصل شات 0.14.0: شارة التوثيق للمجتمعات والقنوات الرسمية (المرحلة 3 — مجتمعات بمستوى ديسكورد)
-- شغّله في SQL Editor بعد 025_phase4.sql.
--
-- الفكرة:
--   - المجتمعات والقنوات الرسمية تأخذ علامة تحقق زرقاء تظهر في القوائم والاكتشاف ورؤوس الشاشات.
--   - الشارة لا يعطيها أحد لنفسه: منحها وسحبها لمسؤولي التطبيق حصراً (جدول app_admins من ترحيل 014)
--     عبر دوال security definer — مالك المجتمع أو القناة مهما كان دوره لا يستطيع كتابة العمود إطلاقاً
--     (لا سياسات INSERT/UPDATE على الأعمدة، والدالتان تتحققان من is_app_admin قبل أي شيء).
--   - التوثيق يعني: أن إدارة وصل شات تحققت من هوية مالك المجتمع/القناة رسمياً.
--     لا يعني اعتماد المحتوى ولا مراقبته — وهذا ما يُعلن للمستخدم في تلميح الشارة.
--
-- مبادئ التصميم:
--   - بلا جداول جديدة: عمودان منطقيان verified (على communities، وعلى conversations للقنوات المستقلة)
--     يُقرآن عبر سياسات RLS القائمة كما هي — ظهور العمود يتبع ظهور الصف نفسه.
--   - قنوات المجتمع لا تحمل الشارة بنفسها: ترث شارة مجتمعها في واجهة التطبيق،
--     وعمود conversations.verified يخدم القنوات المستقلة فقط (community_id is null).
--   - قوائم القراءة (my_communities وdiscover_communities وmy_channels وdiscover_channels)
--     تُعاد تعريفها بنفس استعلاماتها حرفياً مع عمود واحد زائد.

-- ============================================================
-- 1) الأعمدة
-- ============================================================
alter table public.communities add column if not exists verified boolean not null default false;
alter table public.conversations add column if not exists verified boolean not null default false;

-- ============================================================
-- 2) المنح والسحب — لمسؤولي التطبيق حصراً (app_admins من ترحيل 014)
-- ============================================================
create or replace function public.verify_community(cid uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_app_admin() then raise exception 'not allowed'; end if;
  update communities set verified = coalesce(p_verified, false) where id = cid;
end; $$;

-- القنوات المستقلة فقط: قنوات المجتمع ترث شارة مجتمعها ولا تُوثَّق بنفسها
create or replace function public.verify_channel(conv uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_app_admin() then raise exception 'not allowed'; end if;
  update conversations set verified = coalesce(p_verified, false)
  where id = conv and kind = 'channel' and community_id is null;
end; $$;

-- ============================================================
-- 3) قوائم القراءة تُضمّن الشارة (نفس الاستعلامات السابقة + عمود واحد)
-- ============================================================
create or replace function public.my_communities()
returns table (id uuid, name text, description text, role text, members bigint, verified boolean)
language sql security definer stable set search_path = public as $$
  select c.id, c.name, c.description, m.role,
         (select count(*) from community_members x where x.community_id = c.id),
         c.verified
  from communities c
  join community_members m on m.community_id = c.id and m.user_id = auth.uid()
  order by m.joined_at desc;
$$;

create or replace function public.discover_communities(q text default '')
returns table (id uuid, name text, description text, members bigint, verified boolean)
language sql security definer stable set search_path = public as $$
  select c.id, c.name, c.description,
         (select count(*) from community_members x where x.community_id = c.id) as members,
         c.verified
  from communities c
  where c.is_public
    and not exists (select 1 from community_members m
                    where m.community_id = c.id and m.user_id = auth.uid())
    and (coalesce(q, '') = '' or c.name ilike '%' || q || '%')
  order by members desc
  limit 30;
$$;

create or replace function public.my_channels()
returns table (
  conversation_id uuid, title text, description text, role text, subscribers bigint,
  last_message text, last_type text, last_at timestamptz, unread bigint, verified boolean
) language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.description, me.role,
         (select count(*) from conversation_participants x where x.conversation_id = c.id),
         lm.content, lm.type, coalesce(lm.created_at, c.created_at),
         (select count(*) from messages u
           where u.conversation_id = c.id and u.sender_id <> auth.uid()
             and u.created_at > me.last_read_at),
         c.verified
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select m.content, m.type, m.created_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'channel' and c.community_id is null
  order by 8 desc;
$$;

create or replace function public.discover_channels(q text default '')
returns table (conversation_id uuid, title text, description text, subscribers bigint, verified boolean)
language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.description,
         (select count(*) from conversation_participants x where x.conversation_id = c.id) as subscribers,
         c.verified
  from conversations c
  where c.kind = 'channel' and c.is_public and c.community_id is null
    and not public.is_member(c.id)
    and (coalesce(q, '') = '' or c.title ilike '%' || q || '%')
  order by subscribers desc
  limit 30;
$$;

-- ============================================================
-- 4) صلاحيات التنفيذ: المنح والسحب للمسجلين (الدالة نفسها تتحقق من مسؤولية التطبيق)
-- ============================================================
do $$
declare f text;
begin
  for f in select unnest(array[
    'public.verify_community(uuid, boolean)',
    'public.verify_channel(uuid, boolean)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
