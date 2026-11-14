-- وصل شات 0.21.0 (المرحلة 8 ب): جرس القنوات — «أعلّم الجرس» لكل قناة
-- شغّله في SQL Editor بعد 031_album_clear.sql
--
-- الفكرة: تفضيل إشعار لكل قناة مستقلة على حدة، بثلاثة أوضاع:
--   all    : كل المنشورات تنبّهني (الافتراضي — السلوك الحالي كما هو)
--   pinned : المنشورات المثبتة فقط تنبّهني (إعلانات المالك/المشرفين)
--   mute   : صمت تام — لا تصلني بيانات أصلاً (الخادم يخرجني من قائمة
--            المستلمين في دالة الإشعارات، فلا يخترق شيء الجهاز)
--
-- التطبيق الفعلي في دالة push الخادمية (index.ts): تجلب bell مع الأعضاء
-- وتطبّقه حصراً على القنوات — المحادثات الفردية والمجموعات لا تتأثر أبداً.
--
-- الصلاحيات: العضو يضبط تفضيله حصراً عبر set_channel_bell، وقراءة
-- التفضيل عبر my_channels المعاد تعريفها أدناه بالعمود الجديد.

alter table public.conversation_participants
  add column if not exists bell text not null default 'all';

alter table public.conversation_participants
  drop constraint if exists participants_bell_check;

alter table public.conversation_participants
  add constraint participants_bell_check
    check (bell in ('all', 'pinned', 'mute'));

-- العضو يضبط جرس قناة هو عضو فيها حصراً — والقناة مستقلة (لا غرف المجتمعات
-- ولا المحادثات الفردية: تفضيل الكتم القائم يغطيها أصلاً بصمت كامل)
create or replace function public.set_channel_bell(conv uuid, pref text)
returns void language plpgsql security definer
set search_path = public as $$
declare
  me uuid;
  kind text;
begin
  me := auth.uid();
  if me is null then raise exception 'not authenticated'; end if;
  if pref not in ('all', 'pinned', 'mute') then
    raise exception 'bad bell pref';
  end if;
  select c.kind into kind from conversations c where c.id = conv;
  if kind is distinct from 'channel' then
    raise exception 'not a channel';
  end if;
  update conversation_participants p
     set bell = pref
   where p.conversation_id = conv
     and p.user_id = me;
  if not found then raise exception 'not a member'; end if;
end;
$$;

revoke execute on function public.set_channel_bell(uuid, text) from public, anon;
grant execute on function public.set_channel_bell(uuid, text) to authenticated;

-- my_channels مع عمود الجرس: القائمة تعرض حالة الجرس فوراً
-- (نفس التعريف في 026_verification.sql + عمود bell)
create or replace function public.my_channels()
returns table (
  conversation_id uuid, title text, description text, role text, subscribers bigint,
  last_message text, last_type text, last_at timestamptz, unread bigint, verified boolean,
  bell text
) language sql security definer stable set search_path = public as $$
  select c.id, c.title, c.description, me.role,
         (select count(*) from conversation_participants x where x.conversation_id = c.id),
         lm.content, lm.type, coalesce(lm.created_at, c.created_at),
         (select count(*) from messages u
           where u.conversation_id = c.id and u.sender_id <> auth.uid()
             and u.created_at > me.last_read_at),
         c.verified,
         me.bell
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select m.content, m.type, m.created_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'channel' and c.community_id is null
  order by 8 desc;
$$;
