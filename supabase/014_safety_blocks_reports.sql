-- وصل شات 0.1.9: الحظر والإبلاغ (بند خارطة الطريق — مطلوب لمتاجر التطبيقات)
-- + سدّ ثغرة مسارات الوسائط + تحقق العضوية في تعديل/حذف الرسائل
-- شغّله بعد 013_files_video_cleanup.sql (كل ملف وحده ثم Run)

-- 1) الحظر: من يحجب من. الحظر يمنع المحظور من مراسلة الحاجب في المحادثات الفردية
--    ومن فتح محادثة فردية جديدة معه، ويخفي الحاجبَ من بحثه. لا يؤثر على المجموعات والقنوات.
create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
do $$ begin
  alter table public.user_blocks add constraint user_blocks_not_self
    check (blocker_id <> blocked_id);
exception when duplicate_object then null; end $$;

alter table public.user_blocks enable row level security;

drop policy if exists "own blocks read" on public.user_blocks;
create policy "own blocks read" on public.user_blocks
  for select to authenticated using (blocker_id = auth.uid());
drop policy if exists "own blocks insert" on public.user_blocks;
create policy "own blocks insert" on public.user_blocks
  for insert to authenticated with check (blocker_id = auth.uid());
drop policy if exists "own blocks delete" on public.user_blocks;
create policy "own blocks delete" on public.user_blocks
  for delete to authenticated using (blocker_id = auth.uid());

create or replace function public.block_user(p_target uuid)
returns void language sql security definer set search_path = public as $$
  insert into user_blocks (blocker_id, blocked_id)
  values (auth.uid(), p_target)
  on conflict do nothing;
$$;

create or replace function public.unblock_user(p_target uuid)
returns void language sql security definer set search_path = public as $$
  delete from user_blocks where blocker_id = auth.uid() and blocked_id = p_target;
$$;

-- قائمة من حظرتهم أنا (للفلترة في العميل)
create or replace function public.my_blocked_ids()
returns setof uuid language sql security definer stable set search_path = public as $$
  select blocked_id from user_blocks where blocker_id = auth.uid();
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.block_user(uuid)',
    'public.unblock_user(uuid)',
    'public.my_blocked_ids()'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- هل أرسل الرسالة إلى محادثة فردية طُلب فيها حظره من الطرف الآخر؟
create or replace function public.is_dm_blocked(p_conv uuid, p_sender uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
    from conversations c
    join conversation_participants o
      on o.conversation_id = c.id and o.user_id <> p_sender
    join user_blocks b on b.blocker_id = o.user_id and b.blocked_id = p_sender
    where c.id = p_conv and c.is_group = false
  );
$$;

-- سياسة الإرسال: عضوية + صلاحية نشر + ليست محظورة (لا تأثير على المجموعات والقنوات)
drop policy if exists "members send messages" on public.messages;
create policy "members send messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.can_post(conversation_id)
              and not public.is_dm_blocked(conversation_id, auth.uid()));

-- فتح محادثة فردية جديدة مع من حظرني يُرفض (وتُعرض رسالة واضحة في التطبيق)
create or replace function public.create_direct_chat(other_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if other_id = auth.uid() then raise exception 'cannot chat with yourself'; end if;
  if exists (select 1 from user_blocks where blocker_id = other_id and blocked_id = auth.uid())
  then raise exception 'conversation is blocked'; end if;

  select c.id into conv
  from conversations c
  join conversation_participants a on a.conversation_id = c.id and a.user_id = auth.uid()
  join conversation_participants b on b.conversation_id = c.id and b.user_id = other_id
  where c.is_group = false and c.kind = 'chat' and c.community_id is null
  limit 1;

  if conv is not null then return conv; end if;

  insert into conversations (is_group, kind) values (false, 'chat') returning id into conv;
  insert into conversation_participants (conversation_id, user_id)
  values (conv, auth.uid()), (conv, other_id);
  return conv;
end; $$;

-- 2) البلاغات عن مستخدمين أو رسائل — تُراجع يدوياً من لوحة Supabase
create table if not exists public.abuse_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  target_message_id uuid references public.messages(id) on delete set null,
  conversation_id uuid references public.conversations(id) on delete set null,
  reason text not null check (reason in ('spam','inappropriate','harassment','fraud','other')),
  details text check (char_length(details) <= 1000),
  created_at timestamptz not null default now()
);
create index if not exists abuse_reports_target on public.abuse_reports (target_user_id, created_at);

alter table public.abuse_reports enable row level security;

-- الإبلاغ لا بد أن يكون من عضو في محادثة الرسالة المُبلَّغ عنها
create policy "reporters write own" on public.abuse_reports
  for insert to authenticated with check (
    reporter_id = auth.uid()
    and (target_message_id is null
         or exists (select 1 from messages m
                    where m.id = target_message_id
                      and public.is_member(m.conversation_id)))
  );
create policy "reporters read own" on public.abuse_reports
  for select to authenticated using (reporter_id = auth.uid());
-- لا تحديث ولا حذف للعملاء؛ المراجعة بحساب الخدمة أو لوحة التحكم.

-- 3) عضو مُزال من محادثة لا يعدّل/يحذف رسائله القديمة عبر RPC (التحقق من العضوية الحالية)
create or replace function public.edit_message(p_id uuid, p_content text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(char_length(p_content), 0) not between 1 and 4000 then raise exception 'bad content'; end if;
  if not exists (select 1 from messages m
                 where m.id = p_id and public.is_member(m.conversation_id))
  then raise exception 'not allowed'; end if;
  update messages set content = p_content, edited_at = now()
   where id = p_id and sender_id = auth.uid() and type = 'text' and deleted_at is null
     and created_at > now() - interval '48 hours';
  if not found then raise exception 'cannot edit'; end if;
end; $$;

create or replace function public.delete_message(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare old_media text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from messages m
                 where m.id = p_id and public.is_member(m.conversation_id))
  then raise exception 'not allowed'; end if;
  select media_url into old_media from messages
   where id = p_id and sender_id = auth.uid() and deleted_at is null;
  if not found then raise exception 'cannot delete'; end if;
  update messages set type = 'text', content = '-', media_url = null, duration_ms = null,
         deleted_at = now()
   where id = p_id;
  delete from message_reactions where message_id = p_id;
  return old_media;
end; $$;

-- 4) مسار الوسيط لا بد أن يكون داخل مجلد محادثته
-- (سدّ حذف ملفات محادثات أخرى عبر إرسال رسالة بـ media_url مزوّر ثم انتهائها/حذفها)
alter table public.messages drop constraint if exists messages_media_path_check;
alter table public.messages add constraint messages_media_path_check
  check (media_url is null or media_url like conversation_id::text || '/%') not valid;
do $$ begin
  alter table public.messages validate constraint messages_media_path_check;
exception when others then
  raise notice 'media path check stayed NOT VALID: legacy rows violate it — review manually';
end $$;
