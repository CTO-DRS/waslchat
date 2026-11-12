-- وصل شات 0.10.0: تشفير بيانات الوصف — التفاعلات وأسماء المجموعات وصورها
-- شغّله في SQL Editor بعد 021_linked_devices.sql
--
-- الفكرة: في المحادثات المشفّرة (الخاص والمجموعات الخاصة) لا يرى الخادم محتوى الرسائل فقط،
-- بل لا يرى أيضاً:
--   1) الإيموجي في التفاعلات — يُشفَّر بمفتاح المحادثة قبل react_message (صيغة v1 كاملة).
--   2) اسم المجموعة الخاصة — يُشفَّر بمفتاح المجموعة (تثبيت الاسم بعد تهيئة المفتاح).
--   3) صورة المجموعة الخاصة — بايتات مشفرة AES-GCM بمفتاح المجموعة في تخزين chat-media.
-- القنوات وغرف المجتمعات وأسماء الحسابات تبقى صريحة (مساحات عامة بالتصميم).
-- التوافق: القيم القديمة الصريحة تُعرض كما هي (التطبيق يفك ما يبدأ بـ v1. فقط).

-- 1) صورة المجموعة: مسار ملف مشفر في تخزين chat-media (مثل <conv>/avatar_169..._ab12.enc.bin)
alter table public.conversations
  add column if not exists avatar_url text;
do $$ begin
  alter table public.conversations add constraint conversations_avatar_url_check
    check (avatar_url is null or char_length(avatar_url) <= 500);
exception when duplicate_object then null; end $$;

-- 2) التفاعلات: الإيموجي المشفر أطول من 16 حرفاً
--   أسوأ إيموجي (16 نقطة كود بمعدِّلات = 64 بايت) مشفراً: 12 nonce + 64 نص + 16 mac
--   = 92 بايت → base64 بـ 124 حرفاً + «v1.» + نقطتان ≈ 129 حرفاً → الحد 160 آمن.
do $$ begin
  alter table public.message_reactions drop constraint message_reactions_emoji_check;
exception when undefined_object then null; end $$;
alter table public.message_reactions
  add constraint message_reactions_emoji_check check (char_length(emoji) between 1 and 160);

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
  -- الإيموجي يصل مشفراً (v1.nonce.text.mac) من التطبيقات المحدثة، أو صريحاً من القديمة
  if char_length(p_emoji) > 160 then raise exception 'bad emoji'; end if;
  insert into message_reactions (message_id, conversation_id, user_id, emoji)
  values (p_id, conv, auth.uid(), p_emoji)
  on conflict (message_id, user_id) do update set emoji = excluded.emoji, created_at = now();
end; $$;

-- 3) اسم المجموعة: يصل مشفراً من التطبيقات المحدثة (≈ 470 حرفاً أسوأ حالة لاسم 80 حرفاً)
create or replace function public.group_rename(p_conv uuid, p_title text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'admins only';
  end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;
  update conversations set title = left(trim(p_title), 500) where id = p_conv;
end; $$;

-- 4) صورة المجموعة: تثبيت/إزالة المسار — لمشرفي المجموعة الخاصة فقط، تعيد المسار القديم
--   (يحذفه التطبيق من التخزين — ينجح لصاحب الملف صامتاً، وتبقى ملفات غيره مشفرة غير مرئية)
create or replace function public.group_set_avatar(p_conv uuid, p_url text)
returns text language plpgsql security definer set search_path = public as $$
declare old text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not public.is_group_admin(p_conv, auth.uid()) then raise exception 'admins only'; end if;
  if p_url is not null and (char_length(p_url) = 0 or char_length(p_url) > 500) then
    raise exception 'bad url';
  end if;
  select avatar_url into old from conversations where id = p_conv;
  update conversations set avatar_url = p_url where id = p_conv;
  return old;
end; $$;

-- 5) قائمة المحادثات: تعيد صورة المجموعة أيضاً (مسار مشفر يفكه التطبيق)
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
    case when c.is_group then c.avatar_url else op.avatar_url end,
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

-- 6) الصلاحيات
do $$ begin
  alter publication supabase_realtime add table public.message_reactions;
exception when duplicate_object then null; end $$;

do $$
declare f text;
begin
  foreach f in array array[
    'public.react_message(uuid, text)',
    'public.group_rename(uuid, text)',
    'public.group_set_avatar(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
