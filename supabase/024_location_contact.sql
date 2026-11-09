-- وصل شات 0.4.6: مشاركة الموقع وبطاقات جهات الاتصال + إصلاح قيد الاستطلاعات
-- شغّله في SQL Editor بعد 023_mentions.sql
--
-- التصميم الصادق:
-- - كل محتوى الموقع (الإحداثيات والدقة) ومحتوى البطاقة (الاسم والأرقام
--   والبريد) داخل التشفير بين الطرفين: رسالة type='location' تحمل JSON
--   مشفّراً {t:'wasl-location-v1',...} ورسالة type='contact' تحمل
--   {t:'wasl-contact-v1',...}. الخادم لا يفكّهما أبداً.
-- - لا بيانات وصفية جديدة إطلاقاً: الخادم يرى النوع فقط (كما يرى نوع أي
--   رسالة) والمعاينة في القائمة نص عام «📍 موقع» / «👤 جهة اتصال» مثل
--   معاينة الاستطلاعات.
-- - إصلاح خلل قائم من 022: قيد messages_type_check لم يُوسَّع ليشمل
--   poll/poll_vote — أي أن إرسال استطلاع بعد تطبيق 022 كان سيرفضه
--   قاعدة البيانات. هذا الترحيل يوسّع القيد ويعالج الأنواع الجديدة معاً.
-- - إصلاح ثانٍ في messages_body_check: اشتراط media_url لكل غير النصي
--   كان سيرفض الاستطلاعات والموقع والبطاقات (كلها بلا وسائط). يصبح
--   الاشتراط للوسائط فقط (image/voice/video/file).

-- 1) قيد الأنواع: النصية والوسائط والاستطلاعات والموقع والبطاقات
alter table public.messages drop constraint if exists messages_type_check;
alter table public.messages add constraint messages_type_check
  check (type in ('text', 'image', 'voice', 'video', 'file',
                  'poll', 'poll_vote', 'location', 'contact'));

-- 2) قيد الجسم: الوسائط تتطلب media_url، وأنواع المحتوى-فقط (الاستطلاعات
--    والأصوات والموقع والبطاقات) بلا media_url والمحتوى 1..4000
alter table public.messages drop constraint if exists messages_body_check;
alter table public.messages add constraint messages_body_check check (
  (type = 'text' and char_length(content) between 1 and 4000)
  or (type in ('poll', 'poll_vote', 'location', 'contact')
      and media_url is null and char_length(content) between 1 and 4000)
  or (type in ('image', 'voice', 'video', 'file')
      and media_url is not null and char_length(coalesce(content, '')) <= 4000));

-- 3) قائمة المحادثات (نفس 022 مع معاينتين عامتين جديدتين):
--    الموقع والبطاقة تدخلان العدّاد والإشعار كأي رسالة (لأن وصولهما مهم)،
--    لكن معاينتهما في القائمة نص عام — المحتوى المشفّر لا يُعرَض أصلاً.
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
      when lm.type = 'location' then '📍 موقع'
      when lm.type = 'contact' then '👤 جهة اتصال'
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

-- 4) الإشعارات: بلا تغيير — الموقع والبطاقة رسالتان عاديتان في مشغّل
--    messages_push، ونص الإشعار العام «📍 موقع»/«👤 جهة اتصال» يُصنع في
--    دالة push (أعد نشرها بعد هذا الترحيل — راجع RUNBOOK §11).
