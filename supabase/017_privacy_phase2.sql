-- وصل شات 0.3.0: خصوصية أقوى من الجميع (المرحلة 2)
-- منع لقطات الشاشة لكل محادثة + وسائط «عرض مرة واحدة» بفرض حقيقي من الخادم
-- شغّله بعد 016_app_releases_keepalive.sql (كل الملف وحده في SQL Editor ثم Run)

-- ============================================================
-- 1) منع لقطات الشاشة لكل محادثة
--    العميل يطبّق FLAG_SECURE أثناء وجودك في المحادثة المحمية.
--    ملاحظة صادقة: هذا إجراء على الجهاز — لا يمكن لأي نظام منع الطرف
--    الآخر من تصوير الشاشة بكاميرا جهاز آخر (راجع docs/TRANSPARENCY.md).
-- ============================================================
alter table public.conversations
  add column if not exists screenshot_block boolean not null default false;

-- المحادثة الفردية: أي الطرفين. المجموعة الخاصة: المالك أو المشرف. القنوات والمجتمعات: لا.
create or replace function public.set_screenshot_block(p_conv uuid, p_block boolean)
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
  update conversations set screenshot_block = p_block where id = p_conv;
end; $$;
revoke execute on function public.set_screenshot_block(uuid, boolean) from public, anon;
grant execute on function public.set_screenshot_block(uuid, boolean) to authenticated;

-- ============================================================
-- 2) وسائط «عرض مرة واحدة» (الصور والفيديو)
--    الفرض الحقيقي من الخادم: أول فتح من المتلقي يسجّل viewed_at،
--    وينقل الملف إلى سلة التنظيف media_trash التي تحذفه الدالة
--    media-cleanup من التخزين كل ساعة — بعد ذلك لا ملف يُعاد تنزيله.
-- ============================================================
alter table public.messages add column if not exists view_once boolean not null default false;
alter table public.messages add column if not exists viewed_at timestamptz;

-- رسالة وسائط بلا مسار ملف مسموح فقط إذا كانت عرض مرة واحدة وقد عُرضت
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (type = 'text' and char_length(content) between 1 and 4000)
  or (type <> 'text'
      and (media_url is not null or (view_once and viewed_at is not null))
      and char_length(coalesce(content, '')) <= 4000));

-- فتح وسيط عرض مرة واحدة:
--  - فتح المرسِل لرسالته لا يستهلكها (يستطيع رؤيتها حتى يفتحها المتلقي)
--  - أول فتح من المتلقي يسجّل العرض ويعطّل الملف نهائياً
create or replace function public.open_view_once(p_msg uuid)
returns void language plpgsql security definer set search_path = public as $$
declare m record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into m from messages where id = p_msg for update;
  if not found then raise exception 'not found'; end if;
  if not public.is_member(m.conversation_id) then raise exception 'not member'; end if;
  if not m.view_once then return; end if;
  -- المرسِل يرى رسالته دون استهلاكها
  if m.sender_id = auth.uid() then return; end if;
  if m.viewed_at is not null then return; end if; -- عُرضت سابقاً: لا شيء
  update messages set viewed_at = now() where id = p_msg;
  if m.media_url is not null then
    insert into media_trash (path) values (m.media_url) on conflict do nothing;
    update messages set media_url = null where id = p_msg;
  end if;
end; $$;
revoke execute on function public.open_view_once(uuid) from public, anon;
grant execute on function public.open_view_once(uuid) to authenticated;

-- ============================================================
-- 3) حماية المرسل من صور شاشة الطرف الآخر؟ لا شيء يضمنها — لكن
--    الإشعار اللحظي لا يكشف محتوى الوسائط أصلاً (يقول «رسالة مشفرة»)،
--    وقائمة المحادثات تعرض معاينة محايدة لرسائل عرض مرة واحدة.
-- ============================================================
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
    case
      when lm.deleted_at is not null then '🚫 حُذفت هذه الرسالة'
      when lm.view_once and lm.viewed_at is not null then '📷 عرض مرة واحدة · تم العرض'
      when lm.view_once and lm.media_url is not null and lm.sender_id <> auth.uid()
        then '📷 عرض مرة واحدة'
      else lm.content
    end,
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
    select m.content, m.type, m.created_at, m.deleted_at, m.view_once, m.viewed_at,
           m.media_url, m.sender_id from messages m
    where m.conversation_id = c.id and (m.expires_at is null or m.expires_at > now())
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;
