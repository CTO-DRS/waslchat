-- وصل شات 0.1.7: الرسائل المختفية والرسائل المميزة بنجمة
-- شغّله بعد 011_profile_chat_prefs.sql

-- 1) الرسائل المختفية: مؤقت لكل محادثة، ووقت انتهاء لكل رسالة
alter table public.conversations add column if not exists disappear_seconds integer;
do $$ begin
  alter table public.conversations add constraint conversations_disappear_check
    check (disappear_seconds is null or disappear_seconds in (86400, 604800, 7776000));
exception when duplicate_object then null; end $$;
alter table public.messages add column if not exists expires_at timestamptz;
create index if not exists messages_expires_idx on public.messages (expires_at)
  where expires_at is not null;

-- يضبط وقت الانتهاء من إعداد المحادثة عند الإرسال (لا يثق بالعميل)
create or replace function public.messages_set_expiry()
returns trigger language plpgsql security definer set search_path = public as $$
declare secs integer;
begin
  select disappear_seconds into secs from conversations where id = new.conversation_id;
  new.expires_at := case when secs is null then null else now() + make_interval(secs => secs) end;
  return new;
end; $$;
drop trigger if exists messages_set_expiry on public.messages;
create trigger messages_set_expiry before insert on public.messages
  for each row execute function public.messages_set_expiry();

-- الرسائل المنتهية لا تُقرأ حتى قبل أن يحذفها المجدول
drop policy if exists "hide expired messages" on public.messages;
create policy "hide expired messages" on public.messages
  as restrictive for select to authenticated
  using (expires_at is null or expires_at > now());

-- المحادثة الفردية: أي الطرفين. المجموعة الخاصة: المالك أو المشرف. القنوات والمجتمعات: لا.
create or replace function public.set_disappearing(p_conv uuid, p_seconds integer)
returns void language plpgsql security definer set search_path = public as $$
declare c record; r text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into c from conversations where id = p_conv;
  if not found or c.kind <> 'chat' or c.community_id is not null then
    raise exception 'not allowed';
  end if;
  select role into r from conversation_participants
    where conversation_id = p_conv and user_id = auth.uid();
  if not found then raise exception 'not member'; end if;
  if c.is_group and coalesce(r, 'member') not in ('owner', 'admin') then
    raise exception 'admins only';
  end if;
  update conversations set disappear_seconds = nullif(p_seconds, 0) where id = p_conv;
end; $$;
revoke execute on function public.set_disappearing(uuid, integer) from public, anon;
grant execute on function public.set_disappearing(uuid, integer) to authenticated;

-- حذف دوري كل 15 دقيقة (pg_cron، متاح في الخطة المجانية)
create extension if not exists pg_cron;
create or replace function public.purge_expired_messages()
returns void language sql security definer set search_path = public as $$
  delete from messages where expires_at is not null and expires_at < now();
$$;
revoke execute on function public.purge_expired_messages() from public, anon, authenticated;
do $$ begin
  perform cron.unschedule('wasl-purge-expired');
exception when others then null; end $$;
select cron.schedule('wasl-purge-expired', '*/15 * * * *', 'select public.purge_expired_messages()');

-- 2) الرسائل المميزة بنجمة (خاصة بكل مستخدم)
create table if not exists public.message_stars (
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  message_id uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table public.message_stars enable row level security;
drop policy if exists "own stars read" on public.message_stars;
create policy "own stars read" on public.message_stars
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "own stars insert" on public.message_stars;
create policy "own stars insert" on public.message_stars
  for insert to authenticated with check (
    user_id = auth.uid() and public.is_member(conversation_id)
    and exists (select 1 from messages m where m.id = message_id
                and m.conversation_id = message_stars.conversation_id));
drop policy if exists "own stars delete" on public.message_stars;
create policy "own stars delete" on public.message_stars
  for delete to authenticated using (user_id = auth.uid());

-- 4) قائمة المحادثات تتجاهل الرسائل المنتهية
create or replace function public.my_chats()
returns table (
  conversation_id uuid, is_group boolean, title text, other_id uuid,
  last_message text, last_type text, last_at timestamptz, unread bigint,
  avatar_url text, pinned boolean, muted boolean, archived boolean
) language sql security definer stable set search_path = public as $$
  select
    c.id, c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else coalesce(op.display_name, op.username) end,
    case when c.is_group then null else op.id end,
    case when lm.deleted_at is not null then '🚫 حُذفت هذه الرسالة' else lm.content end,
    lm.type,
    coalesce(lm.created_at, c.created_at),
    (select count(*) from messages u
      where u.conversation_id = c.id and u.sender_id <> auth.uid()
        and u.deleted_at is null and u.created_at > me.last_read_at
        and (u.expires_at is null or u.expires_at > now())),
    case when c.is_group then null else op.avatar_url end,
    me.pinned_at is not null,
    me.muted_until is not null and me.muted_until > now(),
    me.archived
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name, p.avatar_url
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at from messages m
    where m.conversation_id = c.id and (m.expires_at is null or m.expires_at > now())
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;
