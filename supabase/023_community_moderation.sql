-- وصل شات 0.11.0: أدوات الإشراف في المجتمعات
-- شغّله في SQL Editor بعد 022_e2e_metadata.sql
--
-- الأدوات الأربعة (مرحلة 3 — مجتمعات بمستوى ديسكورد):
--   1) كتم مؤقت  — يمنع الرسائل النصية والوسائط في كل غرف المجتمع لمدة محددة (10 د → 30 يوماً).
--   2) طرد       — إزالة العضوية من المجتمع وكل غرفه، مع خيار «منع العودة» (حظر) يمنع الانضمام مجدداً.
--   3) فلتر كلمات — رفض أي رسالة جديدة أو معدّلة من الأعضاء تُعيد كلمة محجوبة (تطبيع عربي: بلا تشكيل
--                  وأشكال الهمزة الموحّدة)، والمشرفون والمالك يتجاوزونه.
--   4) سجل إشراف — سجل ثابت (append-only) لكل إجراء الإشراف: من فعل ماذا ومتى وعلى من.
--
-- مبادئ التصميم:
--   - الجداول الجديدة للقراءة فقط عبر RLS؛ كل الكتابة تمر عبر دوال security definer تتحقق
--     من التراتب (المالك يكتم/يطرد المشرفين والأعضاء، والمشرف يكتم/يطرد الأعضاء فقط).
--   - الفرض من الخادم لا من الواجهة: الكتم في can_post ومُحفّز الرسائل، الحظر في join_community،
--     الفلتر في مُحفّز الإدراج والتعديل، والكتم يمنع التعديل أيضاً.
--   - لا يمس هذا الترحيل المحادثات الخاصة والمجموعات الخاصة والقنوات المستقلة إطلاقاً.

-- ============================================================
-- 1) دالة الصلاحية: مشرف مجتمع؟
-- ============================================================
create or replace function public.is_community_admin(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from community_members
                 where community_id = cid and user_id = auth.uid()
                   and role in ('owner', 'admin'));
$$;

-- ============================================================
-- 2) الجداول
-- ============================================================

-- الكتم المؤقت: صف لكل عضو مكتوم في مجتمع
create table if not exists public.community_mutes (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_by uuid not null references auth.users(id) on delete cascade,
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 300),
  until_at timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index if not exists community_mutes_user on public.community_mutes (user_id);

-- الحظر (طرد بمنع العودة): يمنع الانضمام إلى المجتمع مجدداً
create table if not exists public.community_bans (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  banned_by uuid not null references auth.users(id) on delete cascade,
  reason text check (reason is null or char_length(btrim(reason)) between 1 and 300),
  created_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index if not exists community_bans_user on public.community_bans (user_id);

-- فلتر الكلمات: كلمة أو عبارة محجوبة في المجتمع
-- التفرد على كلمة مقنّنة (أحرف صغيرة بلا فراغات الطرفين) عبر فهرس فريد وظيفي —
-- قيود unique الجدولية لا تقبل التعبيرات.
create table if not exists public.community_word_filters (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  pattern text not null check (char_length(btrim(pattern)) between 1 and 100),
  added_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create unique index if not exists community_word_filters_word
  on public.community_word_filters (community_id, lower(btrim(pattern)));

-- سجل الإشراف: ثابت، لا تحديث ولا حذف
create table if not exists public.community_mod_log (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  actor_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in
    ('mute', 'unmute', 'kick', 'ban', 'unban', 'filter_add', 'filter_remove')),
  target_id uuid references auth.users(id) on delete set null,
  details text check (details is null or char_length(btrim(details)) between 1 and 300),
  until_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists community_mod_log_recent
  on public.community_mod_log (community_id, created_at desc);

-- ============================================================
-- 3) سياسات RLS — القراءة فقط للجداول؛ الكتابة عبر الدوال حصراً
-- ============================================================
alter table public.community_mutes enable row level security;
alter table public.community_bans enable row level security;
alter table public.community_word_filters enable row level security;
alter table public.community_mod_log enable row level security;

-- الكتم: يشاهده مشرفو المجتمع والمكتوم نفسه (ليعرف متى ينتهي)
create policy "mutes read admin or self" on public.community_mutes
  for select to authenticated
  using (public.is_community_admin(community_id) or user_id = auth.uid());

-- الحظر: مشرفو المجتمع فقط (المطرود يعرف بالخطأ عند الانضمام)
create policy "bans read admins" on public.community_bans
  for select to authenticated
  using (public.is_community_admin(community_id));

-- الفلتر: أعضاء المجتمع يشاهدونه (شفافية — ليعرفوا ما المحجوب)
create policy "filters read members" on public.community_word_filters
  for select to authenticated
  using (public.is_community_member(community_id));

-- السجل: مشرفو المجتمع فقط
create policy "mod log read admins" on public.community_mod_log
  for select to authenticated
  using (public.is_community_admin(community_id));

-- ============================================================
-- 4) تطبيع النص العربي للمطابقة: بلا تشكيل، همزات موحّدة، أصول الحروف
-- ============================================================
create or replace function public.wasl_norm_ar(t text)
returns text language sql immutable parallel safe as $$
  select lower(regexp_replace(
    translate(coalesce(t, ''),
      'أإآىةؤئًٌٍَُِّْٰـ',
      'ااايهيي'),
    '\s+', ' ', 'g'))
$$;

-- ============================================================
-- 5) الفرض من الخادم — مُحفّز على الرسائل: الكتم ثم الفلتر
--    (يشتغل على الإدراج والتعديل؛ يخرج فوراً إن لم تكن الرسالة في غرفة مجتمع)
-- ============================================================
create or replace function public.assert_community_rules()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cid uuid;
  role_ text;
begin
  if tg_op = 'UPDATE' and new.content is not distinct from old.content then
    return new;
  end if;
  if coalesce(new.content, '') = '' then
    return new;
  end if;

  select c.community_id into cid from conversations c where c.id = new.conversation_id;
  if cid is null then
    return new; -- المحادثات الخاصة والمجموعات الخاصة والقنوات المستقلة لا إشراف عليها هنا
  end if;

  -- الكتم: يمنع الرسائل الجديدة والتعديل معاً
  if exists (
    select 1 from community_mutes m
    where m.community_id = cid and m.user_id = new.sender_id and m.until_at > now()
  ) then
    raise exception 'COMMUNITY_MUTED';
  end if;

  -- فلتر الكلمات: على الأعضاء فقط (المالك والمشرفون يتجاوزونه)
  select m.role into role_ from community_members m
    where m.community_id = cid and m.user_id = new.sender_id;
  if role_ = 'member' and exists (
    select 1 from community_word_filters f
    where f.community_id = cid
      and strpos(public.wasl_norm_ar(new.content), public.wasl_norm_ar(f.pattern)) > 0
  ) then
    raise exception 'COMMUNITY_FILTER';
  end if;
  return new;
end; $$;

drop trigger if exists trg_community_rules on public.messages;
create trigger trg_community_rules
  before insert or update of content on public.messages
  for each row execute function public.assert_community_rules();

-- ============================================================
-- 6) الفرض في can_post: المكتوم لا ينشر في غرف مجتمعه
-- ============================================================
create or replace function public.can_post(conv uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants p
    join conversations c on c.id = p.conversation_id
    where p.conversation_id = conv and p.user_id = auth.uid()
      and (c.kind = 'chat' or p.role in ('owner', 'admin'))
  )
  and not exists (
    select 1 from conversations c
    join community_mutes m on m.community_id = c.community_id
    where c.id = conv and m.user_id = auth.uid() and m.until_at > now()
  );
$$;

-- ============================================================
-- 7) الفرض في join_community: المطرود المحظور لا يعود
-- ============================================================
create or replace function public.join_community(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if exists (select 1 from community_bans
             where community_id = cid and user_id = auth.uid()) then
    raise exception 'COMMUNITY_BANNED';
  end if;
  if not exists (select 1 from communities where id = cid and is_public) then
    raise exception 'community not found';
  end if;
  insert into community_members (community_id, user_id) values (cid, auth.uid())
  on conflict do nothing;
  insert into conversation_participants (conversation_id, user_id)
  select c.id, auth.uid() from conversations c where c.community_id = cid
  on conflict do nothing;
end; $$;

-- ============================================================
-- 8) edit_message: الكتم يمنع التعديل، والفلتر يسري على المحتوى الجديد
-- ============================================================
create or replace function public.edit_message(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = public as $$
declare
  cid uuid;
  role_ text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(char_length(p_content), 0) not between 1 and 4000 then raise exception 'bad content'; end if;

  select c.community_id into cid
  from messages m join conversations c on c.id = m.conversation_id
  where m.id = p_id and m.sender_id = auth.uid();
  if cid is not null then
    if exists (select 1 from community_mutes
               where community_id = cid and user_id = auth.uid() and until_at > now()) then
      raise exception 'COMMUNITY_MUTED';
    end if;
    select m.role into role_ from community_members m
      where m.community_id = cid and m.user_id = auth.uid();
    if role_ = 'member' and exists (
      select 1 from community_word_filters f
      where f.community_id = cid
        and strpos(public.wasl_norm_ar(p_content), public.wasl_norm_ar(f.pattern)) > 0
    ) then
      raise exception 'COMMUNITY_FILTER';
    end if;
  end if;

  update messages set content = p_content, edited_at = now()
   where id = p_id and sender_id = auth.uid() and type = 'text' and deleted_at is null
     and created_at > now() - interval '48 hours';
  if not found then raise exception 'cannot edit'; end if;
end; $$;

-- ============================================================
-- 9) دوال الإشراف — التراتب: المالك فوق المشرف فوق العضو
--    (لا أحد يكتم/يطرد نفسه أو المالك؛ المشرف لا يمس مشرفاً آخر)
-- ============================================================
create or replace function public.community_mute(
  cid uuid, uid uuid, p_minutes int, p_reason text default null
)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  my_role text;
  t_role text;
  until_ timestamptz;
  reason_ text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if me is null then raise exception 'not authenticated'; end if;
  select role into my_role from community_members
    where community_id = cid and user_id = me;
  if my_role is null or my_role not in ('owner', 'admin') then
    raise exception 'not allowed';
  end if;
  if uid = me then raise exception 'cannot moderate yourself'; end if;
  select role into t_role from community_members
    where community_id = cid and user_id = uid;
  if t_role is null then raise exception 'not a member'; end if;
  if t_role = 'owner' or (t_role = 'admin' and my_role <> 'owner') then
    raise exception 'not allowed';
  end if;
  if coalesce(p_minutes, 0) not between 1 and 43200 then raise exception 'bad duration'; end if;

  until_ := now() + make_interval(mins => p_minutes);
  insert into community_mutes (community_id, user_id, muted_by, reason, until_at)
  values (cid, uid, me, reason_, until_)
  on conflict (community_id, user_id) do update
    set muted_by = excluded.muted_by, reason = excluded.reason,
        until_at = excluded.until_at, created_at = now();
  insert into community_mod_log (community_id, actor_id, action, target_id, details, until_at)
  values (cid, me, 'mute', uid, reason_, until_);
  return until_;
end; $$;

create or replace function public.community_unmute(cid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  my_role text;
  t_role text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select role into my_role from community_members
    where community_id = cid and user_id = me;
  if my_role is null or my_role not in ('owner', 'admin') then
    raise exception 'not allowed';
  end if;
  select role into t_role from community_members
    where community_id = cid and user_id = uid;
  if t_role is null then raise exception 'not a member'; end if;
  if t_role = 'owner' or (t_role = 'admin' and my_role <> 'owner') then
    raise exception 'not allowed';
  end if;
  delete from community_mutes where community_id = cid and user_id = uid;
  insert into community_mod_log (community_id, actor_id, action, target_id)
  values (cid, me, 'unmute', uid);
end; $$;

-- الطرد: إزالة العضوية وكل غرفه + حذف كتمه، مع خيار منع العودة (حظر)
create or replace function public.community_kick(
  cid uuid, uid uuid, p_ban boolean default false, p_reason text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  my_role text;
  t_role text;
  reason_ text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if me is null then raise exception 'not authenticated'; end if;
  select role into my_role from community_members
    where community_id = cid and user_id = me;
  if my_role is null or my_role not in ('owner', 'admin') then
    raise exception 'not allowed';
  end if;
  if uid = me then raise exception 'cannot moderate yourself'; end if;
  select role into t_role from community_members
    where community_id = cid and user_id = uid;
  if t_role is null then raise exception 'not a member'; end if;
  if t_role = 'owner' or (t_role = 'admin' and my_role <> 'owner') then
    raise exception 'not allowed';
  end if;

  -- خروج من كل غرف المجتمع (الإعلانات والغرف النقاشية)
  delete from conversation_participants p
  using conversations c
  where p.conversation_id = c.id and c.community_id = cid and p.user_id = uid;
  delete from community_mutes where community_id = cid and user_id = uid;
  delete from community_members where community_id = cid and user_id = uid;
  if coalesce(p_ban, false) then
    insert into community_bans (community_id, user_id, banned_by, reason)
    values (cid, uid, me, reason_)
    on conflict (community_id, user_id) do update
      set banned_by = excluded.banned_by, reason = excluded.reason, created_at = now();
  end if;
  insert into community_mod_log (community_id, actor_id, action, target_id, details)
  values (cid, me, case when coalesce(p_ban, false) then 'ban' else 'kick' end, uid, reason_);
end; $$;

create or replace function public.community_unban(cid uuid, uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;
  delete from community_bans where community_id = cid and user_id = uid;
  insert into community_mod_log (community_id, actor_id, action, target_id)
  values (cid, me, 'unban', uid);
end; $$;

-- ============================================================
-- 10) فلتر الكلمات: إضافة وإزالة + سجل
-- ============================================================
create or replace function public.community_add_filter(cid uuid, p_pattern text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  word text := btrim(coalesce(p_pattern, ''));
  fid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;
  if char_length(word) not between 1 and 100 then raise exception 'bad pattern'; end if;
  insert into community_word_filters (community_id, pattern, added_by)
  values (cid, word, me)
  on conflict (community_id, lower(btrim(pattern))) do nothing
  returning id into fid;
  if fid is not null then
    insert into community_mod_log (community_id, actor_id, action, details)
    values (cid, me, 'filter_add', word);
  end if;
  return fid;
end; $$;

create or replace function public.community_remove_filter(fid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  word text;
  cid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select pattern, community_id into word, cid
    from community_word_filters where id = fid;
  if word is null then return; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;
  delete from community_word_filters where id = fid;
  insert into community_mod_log (community_id, actor_id, action, details)
  values (cid, me, 'filter_remove', word);
end; $$;

-- ============================================================
-- 11) قوائم القراءة: الأعضاء والمكتومون والمحظورون والسجل
-- ============================================================
create or replace function public.community_members_list(cid uuid)
returns table (
  user_id uuid, username text, name text, avatar_url text,
  role text, muted_until timestamptz, joined_at timestamptz
) language sql security definer stable set search_path = public as $$
  select m.user_id, p.username, coalesce(p.display_name, p.username), p.avatar_url,
         m.role,
         (select mu.until_at from community_mutes mu
           where mu.community_id = m.community_id and mu.user_id = m.user_id
             and mu.until_at > now() limit 1),
         m.joined_at
  from community_members m
  join profiles p on p.id = m.user_id
  where m.community_id = cid
  order by (m.role = 'owner') desc, (m.role = 'admin') desc, 3;
$$;

create or replace function public.community_mutes_list(cid uuid)
returns table (user_id uuid, username text, name text, reason text, until_at timestamptz)
language sql security definer stable set search_path = public as $$
  select mu.user_id, p.username, coalesce(p.display_name, p.username),
         mu.reason, mu.until_at
  from community_mutes mu
  join profiles p on p.id = mu.user_id
  where mu.community_id = cid and mu.until_at > now()
  order by mu.until_at;
$$;

create or replace function public.community_bans_list(cid uuid)
returns table (user_id uuid, username text, name text, reason text, created_at timestamptz)
language sql security definer stable set search_path = public as $$
  select b.user_id, p.username, coalesce(p.display_name, p.username),
         b.reason, b.created_at
  from community_bans b
  join profiles p on p.id = b.user_id
  where b.community_id = cid
  order by b.created_at desc;
$$;

create or replace function public.community_mod_log_list(cid uuid)
returns table (
  id uuid, action text, details text, until_at timestamptz, created_at timestamptz,
  actor_name text, target_name text
) language sql security definer stable set search_path = public as $$
  select l.id, l.action, l.details, l.until_at, l.created_at,
         coalesce(pa.display_name, pa.username),
         coalesce(pt.display_name, pt.username)
  from community_mod_log l
  join profiles pa on pa.id = l.actor_id
  left join profiles pt on pt.id = l.target_id
  where l.community_id = cid
  order by l.created_at desc
  limit 100;
$$;

-- هل أنا مكتوم في غرفة مجتمعٍ ما؟ للافتة داخل شاشة المحادثة
create or replace function public.my_mute_in_conversation(conv uuid)
returns timestamptz language sql security definer stable set search_path = public as $$
  select m.until_at
  from conversations c
  join community_mutes m on m.community_id = c.community_id
  where c.id = conv and m.user_id = auth.uid() and m.until_at > now()
  limit 1;
$$;

-- ============================================================
-- 12) صلاحيات التنفيذ: للمسجلين فقط (بأسلوب الترحيلات السابقة)
-- ============================================================
do $$
declare f text;
begin
  for f in select unnest(array[
    'public.community_mute(uuid, uuid, integer, text)',
    'public.community_unmute(uuid, uuid)',
    'public.community_kick(uuid, uuid, boolean, text)',
    'public.community_unban(uuid, uuid)',
    'public.community_add_filter(uuid, text)',
    'public.community_remove_filter(uuid)',
    'public.community_members_list(uuid)',
    'public.community_mutes_list(uuid)',
    'public.community_bans_list(uuid)',
    'public.community_mod_log_list(uuid)',
    'public.my_mute_in_conversation(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
