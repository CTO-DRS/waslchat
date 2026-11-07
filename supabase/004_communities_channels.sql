-- وصل شات v0.4: المجتمعات والقنوات
-- شغّله في SQL Editor بعد 003_receipts_push.sql

-- 1) المجتمعات
create table if not exists public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  description text,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index if not exists community_members_user on public.community_members (user_id);

-- 2) أنواع المحادثات: chat (محادثة/مجموعة/غرفة) أو channel (قناة: النشر للمشرفين فقط)
alter table public.conversations add column if not exists kind text not null default 'chat';
alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations add constraint conversations_kind_check
  check (kind in ('chat', 'channel'));
alter table public.conversations
  add column if not exists community_id uuid references public.communities(id) on delete cascade;
alter table public.conversations add column if not exists is_public boolean not null default false;
alter table public.conversations add column if not exists description text;
create index if not exists conversations_community on public.conversations (community_id);

alter table public.conversation_participants
  add column if not exists role text not null default 'member';
alter table public.conversation_participants drop constraint if exists participants_role_check;
alter table public.conversation_participants add constraint participants_role_check
  check (role in ('owner', 'admin', 'member'));

-- 3) دوال الصلاحيات
create or replace function public.is_community_member(cid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (select 1 from community_members
                 where community_id = cid and user_id = auth.uid());
$$;

-- يحق لي النشر؟ في المحادثات نعم، وفي القنوات للمالك والمشرفين فقط
create or replace function public.can_post(conv uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants p
    join conversations c on c.id = p.conversation_id
    where p.conversation_id = conv and p.user_id = auth.uid()
      and (c.kind = 'chat' or p.role in ('owner', 'admin'))
  );
$$;

drop policy if exists "members send messages" on public.messages;
create policy "members send messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.can_post(conversation_id));

drop policy if exists "members read conversations" on public.conversations;
create policy "members read conversations" on public.conversations
  for select to authenticated using (public.is_member(id) or is_public);

alter table public.communities enable row level security;
alter table public.community_members enable row level security;

drop policy if exists "read communities" on public.communities;
create policy "read communities" on public.communities
  for select to authenticated using (is_public or public.is_community_member(id));

drop policy if exists "read community members" on public.community_members;
create policy "read community members" on public.community_members
  for select to authenticated using (public.is_community_member(community_id));

-- 4) المحادثات الخاصة والمجموعات فقط في تبويب «المحادثات»
create or replace function public.my_chats()
returns table (
  conversation_id uuid, is_group boolean, title text, other_id uuid,
  last_message text, last_type text, last_at timestamptz, unread bigint
) language sql security definer stable set search_path = public as $$
  select
    c.id, c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else coalesce(op.display_name, op.username) end,
    case when c.is_group then null else op.id end,
    lm.content, lm.type,
    coalesce(lm.created_at, c.created_at),
    (select count(*) from messages u
      where u.conversation_id = c.id and u.sender_id <> auth.uid()
        and u.created_at > me.last_read_at)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by 7 desc;
$$;

-- 5) المجتمعات: إنشاء وانضمام وعرض
create or replace function public.create_community(p_name text, p_description text)
returns uuid language plpgsql security definer set search_path = public as $$
declare cid uuid; general uuid; news uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'name required'; end if;

  insert into communities (name, description, owner_id)
  values (trim(p_name), nullif(trim(coalesce(p_description, '')), ''), auth.uid())
  returning id into cid;
  insert into community_members (community_id, user_id, role) values (cid, auth.uid(), 'owner');

  insert into conversations (is_group, kind, title, community_id)
  values (true, 'channel', 'الإعلانات', cid) returning id into news;
  insert into conversations (is_group, kind, title, community_id)
  values (true, 'chat', 'عام', cid) returning id into general;

  insert into conversation_participants (conversation_id, user_id, role)
  values (news, auth.uid(), 'owner'), (general, auth.uid(), 'owner');
  return cid;
end; $$;

create or replace function public.join_community(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from communities where id = cid and is_public) then
    raise exception 'community not found';
  end if;
  insert into community_members (community_id, user_id) values (cid, auth.uid())
  on conflict do nothing;
  insert into conversation_participants (conversation_id, user_id)
  select c.id, auth.uid() from conversations c where c.community_id = cid
  on conflict do nothing;
end; $$;

create or replace function public.my_communities()
returns table (id uuid, name text, description text, role text, members bigint)
language sql security definer stable set search_path = public as $$
  select c.id, c.name, c.description, m.role,
         (select count(*) from community_members x where x.community_id = c.id)
  from communities c
  join community_members m on m.community_id = c.id and m.user_id = auth.uid()
  order by m.joined_at desc;
$$;

create or replace function public.discover_communities(q text default '')
returns table (id uuid, name text, description text, members bigint)
language sql security definer stable set search_path = public as $$
  select c.id, c.name, c.description,
         (select count(*) from community_members x where x.community_id = c.id) as members
  from communities c
  where c.is_public
    and not exists (select 1 from community_members m
                    where m.community_id = c.id and m.user_id = auth.uid())
    and (coalesce(q, '') = '' or c.name ilike '%' || q || '%')
  order by members desc
  limit 30;
$$;

create or replace function public.community_rooms(cid uuid)
returns table (
  conversation_id uuid, title text, kind text, role text,
  last_message text, last_type text, last_at timestamptz, unread bigint
) language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.kind, me.role, lm.content, lm.type,
         coalesce(lm.created_at, c.created_at),
         (select count(*) from messages u
           where u.conversation_id = c.id and u.sender_id <> auth.uid()
             and u.created_at > me.last_read_at)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select m.content, m.type, m.created_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.community_id = cid
  order by (c.kind = 'channel') desc, c.created_at;
$$;

-- غرفة جديدة داخل مجتمع (للمالك والمشرفين)
create or replace function public.create_room(cid uuid, p_title text)
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if not exists (select 1 from community_members where community_id = cid
                 and user_id = auth.uid() and role in ('owner', 'admin')) then
    raise exception 'not allowed';
  end if;
  insert into conversations (is_group, kind, title, community_id)
  values (true, 'chat', trim(p_title), cid) returning id into conv;
  insert into conversation_participants (conversation_id, user_id, role)
  select conv, m.user_id, m.role from community_members m where m.community_id = cid;
  return conv;
end; $$;

-- 6) القنوات: إنشاء ومتابعة واكتشاف
create or replace function public.create_channel(p_title text, p_description text, p_public boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;
  insert into conversations (is_group, kind, title, description, is_public)
  values (true, 'channel', trim(p_title),
          nullif(trim(coalesce(p_description, '')), ''), coalesce(p_public, true))
  returning id into conv;
  insert into conversation_participants (conversation_id, user_id, role)
  values (conv, auth.uid(), 'owner');
  return conv;
end; $$;

create or replace function public.join_channel(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from conversations where id = conv and kind = 'channel'
                 and is_public and community_id is null) then
    raise exception 'channel not found';
  end if;
  insert into conversation_participants (conversation_id, user_id)
  values (conv, auth.uid()) on conflict do nothing;
end; $$;

create or replace function public.leave_channel(conv uuid)
returns void language sql security definer set search_path = public as $$
  delete from conversation_participants
  where conversation_id = conv and user_id = auth.uid() and role <> 'owner';
$$;

create or replace function public.my_channels()
returns table (
  conversation_id uuid, title text, description text, role text, subscribers bigint,
  last_message text, last_type text, last_at timestamptz, unread bigint
) language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.description, me.role,
         (select count(*) from conversation_participants x where x.conversation_id = c.id),
         lm.content, lm.type, coalesce(lm.created_at, c.created_at),
         (select count(*) from messages u
           where u.conversation_id = c.id and u.sender_id <> auth.uid()
             and u.created_at > me.last_read_at)
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
returns table (conversation_id uuid, title text, description text, subscribers bigint)
language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.description,
         (select count(*) from conversation_participants x where x.conversation_id = c.id) as subscribers
  from conversations c
  where c.kind = 'channel' and c.is_public and c.community_id is null
    and not public.is_member(c.id)
    and (coalesce(q, '') = '' or c.title ilike '%' || q || '%')
  order by subscribers desc
  limit 30;
$$;
