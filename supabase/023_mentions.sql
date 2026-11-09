-- وصل شات 0.4.5: الإشارة @ في المجموعات + «ردّ على رسالتك» في الإشعار
-- شغّله في SQL Editor بعد 022_polls.sql
--
-- التصميم الصادق:
-- - نص الإشارة (@اسم وموضعه داخل الرسالة) داخل التشفير بين الطرفين:
--   رسالة نصية عليها إشارات يصير محتواها JSON مشفّراً
--   {t:'wasl-text-v1', x:النص, m:[{u:المستخدم, s:البداية, e:النهاية}]}،
--   والرسائل بلا إشارات تبقى بنصّها العادي كما هي (بلا أي تغيير).
-- - البيانات الوصفية الجديدة: عمود mentions (قائمة معرّفات) — الخادم
--   يعرف «فلان أُشير إليه في رسالة كذا» دون معرفة نص الإشارة أو سياقها.
--   يُستخدم لإشعار التنبيه «🔔 أشار إليك» فقط. موثّق في TRANSPARENCY §1.
-- - «ردّ على رسالتك» في الإشعار يستخدم reply_to الموجود أصلاً — بلا أي
--   بيانات وصفية جديدة.

-- 1) عمود المُشار إليهم (بيانات وصفية للتنبيه فقط — النص نفسه مشفّر)
alter table public.messages
  add column if not exists mentions uuid[] default null;

-- فهرس GIN لأي استخدام لاحق (مثل عدّاد «أشار إليك غير المقروء»)
create index if not exists messages_mentions_gin
  on public.messages using gin (mentions) where mentions is not null;

-- 2) سلامة: تُقبَل الإشارات لأعضاء المحادثة فقط — غيرهم يُحذف بصمت،
--    والقائمة الفارغة تصير null
create or replace function public.messages_check_mentions()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.mentions is null then return new; end if;
  select array_agg(u order by ord) into new.mentions
  from unnest(new.mentions) with ordinality as t(u, ord)
  where exists (
        select 1 from conversation_participants cp
        where cp.conversation_id = new.conversation_id
          and cp.user_id = u);
  if new.mentions is null or new.mentions = '{}' then
    new.mentions := null;
  end if;
  return new;
end; $$;
drop trigger if exists messages_check_mentions on public.messages;
create trigger messages_check_mentions before insert on public.messages
  for each row execute function public.messages_check_mentions();

-- لا تغيير على my_chats ولا مشغّل الإشعارات: الرسالة المُشار فيها نصية
-- عادية في العدّاد والمعاينة، والإشعار المخصّص يُصنع في دالة push
-- (أعد نشرها بعد هذا الترحيل — راجع RUNBOOK §10).
