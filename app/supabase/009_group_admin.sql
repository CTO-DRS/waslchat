-- وصل شات 0.1.5: إدارة أعضاء المجموعات + تدوير مفتاح المجموعة المشفّر
-- شغّله في SQL Editor بعد 008_key_backup.sql
--
-- الأدوار: owner (المؤسس) / admin (مشرف) / member.
-- عند إزالة عضو أو مغادرته تُعلَّم المجموعة needs_rekey = true، فيولّد أول عضو باقٍ يفتحها
-- مفتاحاً جديداً (إصدار +1) ويغلّفه للأعضاء الباقين فقط. الإصدارات القديمة تبقى على أجهزة
-- الأعضاء لقراءة الرسائل القديمة. المُزال لا يرى الرسائل الجديدة أصلاً (RLS)، ولا يملك المفتاح الجديد.

-- 1) إصدار المفتاح
alter table public.conversations
  add column if not exists group_key_version integer not null default 1,
  add column if not exists needs_rekey boolean not null default false;

alter table public.conversation_key_envelopes
  add column if not exists key_version integer not null default 1;

do $$ begin
  alter table public.conversation_key_envelopes drop constraint conversation_key_envelopes_pkey;
exception when undefined_object then null; end $$;
do $$ begin
  alter table public.conversation_key_envelopes
    add constraint conversation_key_envelopes_pkey primary key (conversation_id, user_id, key_version);
exception when duplicate_object or invalid_table_definition then null; end $$;

-- 2) المؤسس مالكٌ للمجموعات الخاصة القائمة
update public.conversation_participants p
   set role = 'owner'
  from public.conversations c
 where c.id = p.conversation_id
   and c.is_group and c.kind = 'chat' and c.community_id is null
   and c.created_by = p.user_id
   and p.role <> 'owner';

-- إنشاء مجموعة: المؤسس owner
create or replace function public.create_group_chat(p_title text, p_members uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;

  insert into conversations (is_group, title, created_by)
  values (true, left(trim(p_title), 80), auth.uid()) returning id into conv;

  insert into conversation_participants (conversation_id, user_id, role)
  select conv, s.u, case when s.u = auth.uid() then 'owner' else 'member' end
  from (select unnest(p_members) as u union select auth.uid()) s
  where exists (select 1 from profiles p where p.id = s.u);

  return conv;
end; $$;

-- 3) دوال مساعدة
-- دوري في مجموعة خاصة (null إن لم أكن عضواً أو لم تكن مجموعة خاصة)
create or replace function public.group_role(p_conv uuid)
returns text language sql security definer stable set search_path = public as $$
  select p.role from conversation_participants p
  join conversations c on c.id = p.conversation_id
  where p.conversation_id = p_conv and p.user_id = auth.uid()
    and c.is_group and c.kind = 'chat' and c.community_id is null;
$$;

-- 4) إعادة تعريف تثبيت المفتاح الأول (الإصدار 1) وتغليفه للأعضاء (الإصدار الحالي)
create or replace function public.e2e_set_group_key(p_conv uuid, p_envelopes jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_conv) then raise exception 'not member'; end if;
  if p_envelopes is null or jsonb_typeof(p_envelopes) <> 'array'
     or jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 500 then
    raise exception 'bad envelopes';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('e2e:' || p_conv::text, 7));
  if exists (select 1 from conversation_key_envelopes where conversation_id = p_conv) then
    return; -- للمجموعة مفتاح: لا يُستبدل
  end if;
  if exists (select 1 from conversations
             where id = p_conv and created_by is not null and created_by <> me) then
    raise exception 'only founder installs the first key';
  end if;
  update conversations set group_key_version = 1, needs_rekey = false where id = p_conv;
  insert into conversation_key_envelopes (conversation_id, user_id, wrapped_by, wrapped_key, key_version)
  select p_conv, (e->>'user_id')::uuid, me, e->>'wrapped_key', 1
  from jsonb_array_elements(p_envelopes) e
  where exists (select 1 from conversation_participants cp
                where cp.conversation_id = p_conv and cp.user_id = (e->>'user_id')::uuid)
  on conflict (conversation_id, user_id, key_version) do nothing;
end; $$;

create or replace function public.e2e_wrap_for_members(p_conv uuid, p_envelopes jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); v integer;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_conv) then raise exception 'not member'; end if;
  select group_key_version into v from conversations where id = p_conv;
  if not exists (select 1 from conversation_key_envelopes
                 where conversation_id = p_conv and user_id = me and key_version = v) then
    raise exception 'no key held';
  end if;
  if p_envelopes is null or jsonb_typeof(p_envelopes) <> 'array'
     or jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 500 then
    raise exception 'bad envelopes';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('e2e:' || p_conv::text, 7));
  insert into conversation_key_envelopes (conversation_id, user_id, wrapped_by, wrapped_key, key_version)
  select p_conv, (e->>'user_id')::uuid, me, e->>'wrapped_key', v
  from jsonb_array_elements(p_envelopes) e
  where exists (select 1 from conversation_participants cp
                where cp.conversation_id = p_conv and cp.user_id = (e->>'user_id')::uuid)
  on conflict (conversation_id, user_id, key_version) do nothing;
end; $$;

-- 5) تدوير المفتاح: مسموح فقط عندما needs_rekey = true ولإصدار = الحالي + 1
create or replace function public.e2e_rotate_group_key(p_conv uuid, p_version integer, p_envelopes jsonb)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); cur integer; pending boolean;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_conv) then raise exception 'not member'; end if;
  if p_envelopes is null or jsonb_typeof(p_envelopes) <> 'array'
     or jsonb_array_length(p_envelopes) = 0 or jsonb_array_length(p_envelopes) > 500 then
    raise exception 'bad envelopes';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('e2e:' || p_conv::text, 7));
  select group_key_version, needs_rekey into cur, pending from conversations where id = p_conv;
  if not pending or p_version <> cur + 1 then
    return false; -- سبقنا عضو آخر أو لا حاجة للتدوير
  end if;
  -- لا بد أن يشمل الظرف الجديد صاحبه
  if not exists (select 1 from jsonb_array_elements(p_envelopes) e
                 where (e->>'user_id')::uuid = me) then
    raise exception 'must include self';
  end if;
  insert into conversation_key_envelopes (conversation_id, user_id, wrapped_by, wrapped_key, key_version)
  select p_conv, (e->>'user_id')::uuid, me, e->>'wrapped_key', p_version
  from jsonb_array_elements(p_envelopes) e
  where exists (select 1 from conversation_participants cp
                where cp.conversation_id = p_conv and cp.user_id = (e->>'user_id')::uuid)
  on conflict (conversation_id, user_id, key_version) do nothing;
  update conversations set group_key_version = p_version, needs_rekey = false where id = p_conv;
  return true;
end; $$;

-- 6) إدارة الأعضاء
create or replace function public.group_add_members(p_conv uuid, p_members uuid[])
returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'admins only';
  end if;
  if coalesce(array_length(p_members, 1), 0) > 100 then raise exception 'too many'; end if;
  insert into conversation_participants (conversation_id, user_id, role)
  select p_conv, u, 'member' from unnest(p_members) u
  where exists (select 1 from profiles p where p.id = u)
  on conflict (conversation_id, user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end; $$;

create or replace function public.group_remove_member(p_conv uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare my_role text := public.group_role(p_conv); their_role text;
begin
  if coalesce(my_role, '') not in ('owner', 'admin') then raise exception 'admins only'; end if;
  if p_user = auth.uid() then raise exception 'use group_leave'; end if;
  select role into their_role from conversation_participants
   where conversation_id = p_conv and user_id = p_user;
  if their_role is null then return; end if;
  if their_role = 'owner' then raise exception 'cannot remove owner'; end if;
  if their_role = 'admin' and my_role <> 'owner' then raise exception 'owner only'; end if;
  delete from conversation_participants where conversation_id = p_conv and user_id = p_user;
  update conversations set needs_rekey = true where id = p_conv;
end; $$;

create or replace function public.group_leave(p_conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare my_role text := public.group_role(p_conv); heir uuid;
begin
  if my_role is null then raise exception 'not a group member'; end if;
  delete from conversation_participants where conversation_id = p_conv and user_id = auth.uid();
  if not exists (select 1 from conversation_participants where conversation_id = p_conv) then
    delete from conversations where id = p_conv; -- آخر عضو: تُحذف المجموعة
    return;
  end if;
  if my_role = 'owner' then
    select user_id into heir from conversation_participants
     where conversation_id = p_conv
     order by (role = 'admin') desc, joined_at, user_id limit 1;
    update conversation_participants set role = 'owner'
     where conversation_id = p_conv and user_id = heir;
    update conversations set created_by = heir where id = p_conv;
  end if;
  update conversations set needs_rekey = true where id = p_conv;
end; $$;

create or replace function public.group_set_role(p_conv uuid, p_user uuid, p_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.group_role(p_conv) is distinct from 'owner' then raise exception 'owner only'; end if;
  if p_role not in ('admin', 'member') then raise exception 'bad role'; end if;
  if p_user = auth.uid() then raise exception 'cannot change own role'; end if;
  update conversation_participants set role = p_role
   where conversation_id = p_conv and user_id = p_user and role <> 'owner';
end; $$;

create or replace function public.group_rename(p_conv uuid, p_title text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'admins only';
  end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;
  update conversations set title = left(trim(p_title), 80) where id = p_conv;
end; $$;

-- 7) الصلاحيات
do $$
declare f text;
begin
  foreach f in array array[
    'public.group_role(uuid)',
    'public.e2e_set_group_key(uuid, jsonb)',
    'public.e2e_wrap_for_members(uuid, jsonb)',
    'public.e2e_rotate_group_key(uuid, integer, jsonb)',
    'public.group_add_members(uuid, uuid[])',
    'public.group_remove_member(uuid, uuid)',
    'public.group_leave(uuid)',
    'public.group_set_role(uuid, uuid, text)',
    'public.group_rename(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
