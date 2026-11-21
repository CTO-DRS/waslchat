-- وصل شات 0.1.5: الرد، التعديل، الحذف للجميع، التفاعلات
-- شغّله في SQL Editor بعد 009_group_admin.sql
--
-- التعديل والحذف عبر دوال RPC فقط (لا سياسة UPDATE مباشرة على messages).
-- في المحادثات المشفّرة يُرسل التطبيق النص الجديد مشفّراً، فالخادم لا يرى التعديل.
-- التفاعلات (الإيموجي) غير مشفّرة: الخادم يرى من تفاعل بأي إيموجي، لا نص الرسالة.

alter table public.messages
  add column if not exists reply_to uuid references public.messages(id) on delete set null,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

-- الرد لا بد أن يكون على رسالة من نفس المحادثة
create or replace function public.messages_check_reply()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.reply_to is not null and not exists (
       select 1 from messages r where r.id = new.reply_to
         and r.conversation_id = new.conversation_id) then
    new.reply_to := null;
  end if;
  return new;
end; $$;
drop trigger if exists messages_check_reply on public.messages;
create trigger messages_check_reply before insert on public.messages
  for each row execute function public.messages_check_reply();

-- تعديل رسالتي النصية (خلال 48 ساعة)
create or replace function public.edit_message(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(char_length(p_content), 0) not between 1 and 4000 then raise exception 'bad content'; end if;
  update messages set content = p_content, edited_at = now()
   where id = p_id and sender_id = auth.uid() and type = 'text' and deleted_at is null
     and created_at > now() - interval '48 hours';
  if not found then raise exception 'cannot edit'; end if;
end; $$;

-- حذف رسالتي للجميع: يُمسح المحتوى ويبقى أثر «حُذفت هذه الرسالة»
create or replace function public.delete_message(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare old_media text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select media_url into old_media from messages
   where id = p_id and sender_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'cannot delete'; end if;
  update messages set type = 'text', content = '-', media_url = null, duration_ms = null,
         deleted_at = now()
   where id = p_id;
  delete from message_reactions where message_id = p_id;
  return old_media; -- يحذف التطبيق الملف من التخزين
end; $$;

-- التفاعلات: تفاعل واحد لكل مستخدم على كل رسالة
create table if not exists public.message_reactions (
  message_id      uuid not null references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  emoji           text not null check (char_length(emoji) between 1 and 16),
  created_at      timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists message_reactions_conv on public.message_reactions (conversation_id);

alter table public.message_reactions enable row level security;

drop policy if exists "reactions read by members" on public.message_reactions;
create policy "reactions read by members" on public.message_reactions
  for select to authenticated using (public.is_member(conversation_id));

drop policy if exists "reactions delete own" on public.message_reactions;
create policy "reactions delete own" on public.message_reactions
  for delete to authenticated using (user_id = auth.uid());

-- الإضافة/التغيير عبر دالة (تتحقق من أن الرسالة في المحادثة وأني عضو)
create or replace function public.react_message(p_id uuid, p_emoji text)
returns void language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select conversation_id into conv from messages where id = p_id and deleted_at is null;
  if conv is null or not public.is_member(conv) then raise exception 'not allowed'; end if;
  if p_emoji is null or p_emoji = '' then
    delete from message_reactions where message_id = p_id and user_id = auth.uid();
    return;
  end if;
  if char_length(p_emoji) > 16 then raise exception 'bad emoji'; end if;
  insert into message_reactions (message_id, conversation_id, user_id, emoji)
  values (p_id, conv, auth.uid(), p_emoji)
  on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now();
end; $$;

do $$ begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null; end $$;
-- لتصل أحداث الحذف مع conversation_id (فلترة البث)
alter table public.message_reactions replica identity full;

do $$
declare f text;
begin
  foreach f in array array[
    'public.edit_message(uuid, text)',
    'public.delete_message(uuid)',
    'public.react_message(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- حذف ملف الوسيط من التخزين: لصاحب الملف فقط
drop policy if exists "owners delete media" on storage.objects;
create policy "owners delete media" on storage.objects
  for delete to authenticated
  using (bucket_id = 'chat-media' and owner = auth.uid());

-- قائمة المحادثات: الرسالة المحذوفة تظهر كأثر
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
    case when lm.deleted_at is not null then '🚫 حُذفت هذه الرسالة' else lm.content end,
    lm.type,
    coalesce(lm.created_at, c.created_at),
    (select count(*) from messages u
      where u.conversation_id = c.id and u.sender_id <> auth.uid()
        and u.deleted_at is null and u.created_at > me.last_read_at)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by 7 desc;
$$;
