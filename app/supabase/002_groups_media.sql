-- وصل شات v0.2: المجموعات والصور والرسائل الصوتية
-- شغّله في SQL Editor بعد 001_schema.sql

-- 1) أنواع الرسائل (نص / صورة / صوت)
alter table public.messages add column if not exists type text not null default 'text';
alter table public.messages add column if not exists media_url text;
alter table public.messages add column if not exists duration_ms integer;
alter table public.messages alter column content set default '';
alter table public.messages drop constraint if exists messages_content_check;
alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'voice'));
alter table public.messages add constraint messages_body_check
  check ((type = 'text' and char_length(content) between 1 and 4000)
      or (type <> 'text' and media_url is not null));

-- 2) إنشاء مجموعة
create or replace function public.create_group_chat(p_title text, p_members uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;

  insert into conversations (is_group, title) values (true, trim(p_title)) returning id into conv;

  insert into conversation_participants (conversation_id, user_id)
  select conv, s.u
  from (select unnest(p_members) as u union select auth.uid()) s
  where exists (select 1 from profiles p where p.id = s.u);

  return conv;
end; $$;

-- 3) قائمة المحادثات (خاصة + مجموعات)
drop function if exists public.my_chats();
create function public.my_chats()
returns table (
  conversation_id uuid,
  is_group boolean,
  title text,
  last_message text,
  last_type text,
  last_at timestamptz
) language sql security definer stable set search_path = public as $$
  select
    c.id,
    c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else (select coalesce(p.display_name, p.username)
               from conversation_participants o
               join profiles p on p.id = o.user_id
               where o.conversation_id = c.id and o.user_id <> auth.uid()
               limit 1)
    end,
    lm.content,
    lm.type,
    coalesce(lm.created_at, c.created_at)
  from conversations c
  join conversation_participants me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select m.content, m.type, m.created_at
    from messages m
    where m.conversation_id = c.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by 6 desc;
$$;

-- 4) تخزين الوسائط (خاص: لا يراه إلا أعضاء المحادثة)
-- مسار كل ملف: <conversation_id>/<file>
insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

drop policy if exists "members read media" on storage.objects;
drop policy if exists "members upload media" on storage.objects;

create policy "members read media" on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-media'
         and public.is_member(((storage.foldername(name))[1])::uuid));

create policy "members upload media" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'chat-media'
              and public.is_member(((storage.foldername(name))[1])::uuid));
