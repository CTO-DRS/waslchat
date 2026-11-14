-- وصل شات 0.20.0 (المرحلة 8): الألبوم المتعدد + مسح المحادثة لكل مستخدم
-- شغّله في SQL Editor بعد 029_feedback.sql

-- 1) الألبوم المتعدد: معرّف مجموعة وسائط يُرسل التطبيق معه كل قطع الألبوم
--    (حتى 10 صور/فيديو) بنفس المعرّف، ويُجمّع العرض محلياً بالتسلسل.
--    المحتوى نفسه يُشفَّر كما هو اليوم — المعرّف ليست بيانات حساسة.
alter table public.messages add column if not exists media_group_id uuid;
create index if not exists messages_media_group_idx
  on public.messages (conversation_id, media_group_id);

-- 2) مسح المحادثة لكل مستخدم: طابع زمني على صف المشاركة الشخصي.
--    المسح لا يحذف صفوف الرسائل المشتركة أبداً — يخفيها فقط عن صاحب المسح،
--    والطرف الآخر يرى محادثته كما هي.
alter table public.conversation_participants
  add column if not exists cleared_at timestamptz;

-- مسح محادثة: يحدّث صف المستخدم الحالي فقط (security definer لأن الجدول
-- لا يتيح تحديث cleared_at بسياسات المستخدم، والمشترِك يحدّث صفّه حصراً).
create or replace function public.clear_chat(p_conv uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update conversation_participants
     set cleared_at = now()
   where conversation_id = p_conv and user_id = auth.uid();
  if not found then raise exception 'not member'; end if;
end; $$;

revoke execute on function public.clear_chat(uuid) from public, anon;
grant execute on function public.clear_chat(uuid) to authenticated;

-- 3) قائمة المحادثات تحترم المسح الشخصي: آخر رسالة وعدد غير المقروء
--    يحسبان بعد طابع المسح — المحادثة الممسوحة تظهر بلا معاينة وبلا عدّاد.
drop function if exists public.my_chats();
create function public.my_chats()
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
        and u.created_at > coalesce(me.cleared_at, 'epoch'::timestamptz)),
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
    where m.conversation_id = c.id
      and m.created_at > coalesce(me.cleared_at, 'epoch'::timestamptz)
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;
