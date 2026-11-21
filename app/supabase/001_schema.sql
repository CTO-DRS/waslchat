-- وصل شات: قاعدة البيانات (الصقه كاملاً في Supabase > SQL Editor ثم Run)

create extension if not exists pgcrypto;

-- الملفات الشخصية
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now()
);

-- المحادثات
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  is_group boolean not null default false,
  title text,
  created_at timestamptz not null default now()
);

-- أعضاء المحادثة
create table if not exists public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- الرسائل
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists messages_conv_time on public.messages (conversation_id, created_at);
create index if not exists participants_user on public.conversation_participants (user_id);

-- إنشاء ملف شخصي تلقائياً عند التسجيل
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'username', ''),
             split_part(new.email, '@', 1) || '_' || substr(new.id::text, 1, 4)),
    coalesce(nullif(new.raw_user_meta_data->>'username', ''), split_part(new.email, '@', 1))
  );
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- هل المستخدم الحالي عضو في المحادثة؟
create or replace function public.is_member(conv uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants
    where conversation_id = conv and user_id = auth.uid()
  );
$$;

-- الحماية (Row Level Security)
alter table public.profiles enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;

create policy "profiles readable by users" on public.profiles
  for select to authenticated using (true);
create policy "users update own profile" on public.profiles
  for update to authenticated using (id = auth.uid());

create policy "members read conversations" on public.conversations
  for select to authenticated using (public.is_member(id));
create policy "members read participants" on public.conversation_participants
  for select to authenticated using (public.is_member(conversation_id));
create policy "members read messages" on public.messages
  for select to authenticated using (public.is_member(conversation_id));
create policy "members send messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.is_member(conversation_id));

-- فتح (أو إنشاء) محادثة خاصة مع مستخدم
create or replace function public.create_direct_chat(other_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if other_id = auth.uid() then raise exception 'cannot chat with yourself'; end if;

  select c.id into conv
  from conversations c
  join conversation_participants a on a.conversation_id = c.id and a.user_id = auth.uid()
  join conversation_participants b on b.conversation_id = c.id and b.user_id = other_id
  where c.is_group = false
  limit 1;

  if conv is not null then return conv; end if;

  insert into conversations (is_group) values (false) returning id into conv;
  insert into conversation_participants (conversation_id, user_id)
  values (conv, auth.uid()), (conv, other_id);
  return conv;
end; $$;

-- قائمة محادثاتي مع آخر رسالة
create or replace function public.my_chats()
returns table (
  conversation_id uuid,
  other_id uuid,
  other_name text,
  last_message text,
  last_at timestamptz
) language sql security definer stable set search_path = public as $$
  select
    c.id,
    p.id,
    coalesce(p.display_name, p.username),
    (select m.content from messages m where m.conversation_id = c.id
       order by m.created_at desc limit 1),
    coalesce((select max(m.created_at) from messages m where m.conversation_id = c.id),
             c.created_at)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  join conversation_participants o on o.conversation_id = c.id and o.user_id <> auth.uid()
  join profiles p on p.id = o.user_id
  where c.is_group = false
  order by 5 desc;
$$;

-- تفعيل الرسائل اللحظية
alter publication supabase_realtime add table public.messages;
