-- وصل شات 0.4.4: استطلاعات الرأي المشفّرة (بند المرحلة 1)
-- شغّله في SQL Editor بعد 021_scheduled_messages.sql
--
-- التصميم الصادق:
-- - السؤال والخيارات واختيار المصوّت كلها داخل التشفير بين الطرفين:
--   رسالة type='poll' تحمل JSON مشفّراً {q: السؤال, o: [الخيارات]}،
--   ورسالة type='poll_vote' تحمل JSON مشفّراً {c: رقم الخيار المختار}.
-- - البيانات الوصفية الوحيدة المرئية للخادم: poll_id — أي «فلان صوّت في
--   استطلاع كذا» دون أي معرفة بما اختار. موثّقة في docs/TRANSPARENCY.md.
-- - الصوت صامت كما في واتساب: لا يدخل عدّاد غير المقروء، ولا يظهر معاينة
--   لآخر رسالة، ولا يرسل إشعاراً.

-- 1) عمود ربط التصويت بالاستطلاع (بيانات وصفية فقط — الاختيار مشفّر)
alter table public.messages
  add column if not exists poll_id uuid references public.messages(id) on delete cascade;

create index if not exists messages_poll
  on public.messages (poll_id) where poll_id is not null;

-- 2) سلامة الربط: poll_id على أصوات الاستطلاع فقط، وفي نفس المحادثة،
--    ويشير إلى استطلاع قائم غير محذوف — وإلا يُهمَل الربط بصمت
create or replace function public.messages_check_poll()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.poll_id is not null and new.type <> 'poll_vote' then
    raise exception 'poll_id is only allowed on poll_vote messages';
  end if;
  if new.poll_id is not null and not exists (
       select 1 from messages p where p.id = new.poll_id
         and p.conversation_id = new.conversation_id
         and p.type = 'poll' and p.deleted_at is null) then
    new.poll_id := null;
  end if;
  return new;
end; $$;
drop trigger if exists messages_check_poll on public.messages;
create trigger messages_check_poll before insert on public.messages
  for each row execute function public.messages_check_poll();

-- 3) قائمة المحادثات (نفس 021 مع ثلاثة تعديلات للاستطلاعات):
--    أ) أصوات الاستطلاع لا تظهر كـ«آخر رسالة» — تبقى المعاينة على الاستطلاع نفسه
--    ب) أصوات الآخرين لا تدخل عدّاد غير المقروء (التصويت صامت)
--    ج) معاينة الاستطلاع نص عام «📊 استطلاع» — السؤال لا يراه الخادم أصلاً
create or replace function public.my_chats()
returns table (
  conversation_id uuid, is_group boolean, title text, other_id uuid,
  last_message text, last_type text, last_at timestamptz, unread bigint,
  avatar_url text, pinned boolean, muted boolean, archived boolean,
  last_scheduled boolean
) language sql security definer stable set search_path = public as $$
  select
    c.id, c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else coalesce(op.display_name, op.username) end,
    case when c.is_group then null else op.id end,
    case
      when lm.deleted_at is not null then '🚫 حُذفت هذه الرسالة'
      when lm.scheduled then '⏰ رسالة مجدولة'
      when lm.type = 'poll' then '📊 استطلاع'
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
        and u.created_at <= now()
        and (u.expires_at is null or u.expires_at > now())
        and u.type <> 'poll_vote'),
    case when c.is_group then null else op.avatar_url end,
    me.pinned_at is not null,
    me.muted_until is not null and me.muted_until > now(),
    me.archived,
    coalesce(lm.scheduled, false)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name, p.avatar_url
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at, m.view_once, m.viewed_at,
           m.media_url, m.sender_id, m.scheduled
    from messages m
    where m.conversation_id = c.id
      and (m.expires_at is null or m.expires_at > now())
      and (m.sender_id = auth.uid() or m.created_at <= now())
      and m.type <> 'poll_vote'
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;

-- 4) الإشعارات: التصويت صامت — لا ويبهوك ولا إشعار FCM لأصوات الاستطلاع.
--    (نفس شرط 021 للمجدولة + استثناء poll_vote. دالة notify_push تبقى كما هي.)
drop trigger if exists messages_push on public.messages;
create trigger messages_push after insert on public.messages
  for each row when (not coalesce(new.scheduled, false)
                     and new.type is distinct from 'poll_vote')
  execute function public.notify_push();
-- messages_push_release (إطلاق المجدولة) تبقى كما هي — الأصوات لا تُجدول أبداً
