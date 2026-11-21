-- وصل شات v0.3: علامات القراءة، عداد غير المقروء، وأجهزة الإشعارات
-- شغّله في SQL Editor بعد 002_groups_media.sql

-- 1) آخر وقت قرأ فيه كل عضو المحادثة
alter table public.conversation_participants
  add column if not exists last_read_at timestamptz not null default now();

create or replace function public.mark_read(conv uuid)
returns void language sql security definer set search_path = public as $$
  update conversation_participants
     set last_read_at = now()
   where conversation_id = conv and user_id = auth.uid();
$$;

-- تحديث علامات القراءة لحظياً
do $$ begin
  alter publication supabase_realtime add table public.conversation_participants;
exception when duplicate_object then null; end $$;

-- 2) قائمة المحادثات مع عدد غير المقروء
drop function if exists public.my_chats();
create function public.my_chats()
returns table (
  conversation_id uuid,
  is_group boolean,
  title text,
  other_id uuid,
  last_message text,
  last_type text,
  last_at timestamptz,
  unread bigint
) language sql security definer stable set search_path = public as $$
  select
    c.id,
    c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else coalesce(op.display_name, op.username) end,
    case when c.is_group then null else op.id end,
    lm.content,
    lm.type,
    coalesce(lm.created_at, c.created_at),
    (select count(*) from messages u
      where u.conversation_id = c.id
        and u.sender_id <> auth.uid()
        and u.created_at > me.last_read_at)
  from conversations c
  join conversation_participants me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name
    from conversation_participants o
    join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid()
    limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at
    from messages m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by 7 desc;
$$;

-- 3) رموز الأجهزة للإشعارات (Firebase Cloud Messaging)
create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text,
  updated_at timestamptz not null default now()
);
create index if not exists device_tokens_user on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

drop policy if exists "own tokens read" on public.device_tokens;
drop policy if exists "own tokens insert" on public.device_tokens;
drop policy if exists "own tokens update" on public.device_tokens;
drop policy if exists "own tokens delete" on public.device_tokens;

create policy "own tokens read" on public.device_tokens
  for select to authenticated using (user_id = auth.uid());
create policy "own tokens insert" on public.device_tokens
  for insert to authenticated with check (user_id = auth.uid());
create policy "own tokens update" on public.device_tokens
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own tokens delete" on public.device_tokens
  for delete to authenticated using (user_id = auth.uid());
