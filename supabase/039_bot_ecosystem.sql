-- وصل شات v1.7.0+69 — المرحلة 15 ج: اكتمال النظام البيئي (المرحلة 15 كاملة)
-- 039: المقترح المنفذ بعد موافقة المشرف + أحداث العضوية للويب هوك + إحصاءات البوت
--
-- شغّله في SQL Editor بعد 037_prekey_signing.sql. ثم أعد نشر دالة bots-api
-- (RUNBOOK §3.16) لتقبل حقل proposal في sendMessage.
--
-- الفكرة الصادقة (بلا صلاحية جديدة للبوت إطلاقاً):
--   1) البوت «يقترح» لا «ينفّذ»: بوت مجتمعي نشط يرسل رسالة تنبيه نصية عادية،
--      ويحمل معها مقترحاً منظماً (كتم عضو لمدة أو طرده) يخزّن الخادم بعد
--      تحقق صارم على غرف المجتمعات العامة حصراً (محتواها صريح بالتصميم).
--      المقترح ينام «معلقاً» إلى أن مشرفاً بشرياً يوافق من شاشة الإشراف —
--      والتنفيذ يجري **بصلاحية المشرف نفسه** (auth.uid() هو الفاعل في دوال
--      community_mute/community_kick من ترحيل 023) لا بصلاحية البوت.
--   2) أحداث العضوية للويب هوك: انضمام عضو أو مغادرته يصل للبوتات النشطة ذات
--      الويب هوك في المحادثة بتوقيع HMAC نفسه — بيانات عضوية كانت غائبة كلياً
--      (التغيير الوحيد الجديد على ما يخرج من الخادم، موثق في TRANSPARENCY).
--   3) إحصاءات البوت لصاحبه: ما يمكن قراءته فعلاً من الجداول القائمة — لا
--      تخزين جديد ولا سجلات إضافية.
--
-- حدود صادقة موثقة: المقترح يُدار من شاشة الإشراف (قائمة معلقة) لا داخل
--   الغرفة؛ والطرد بلا حظر في هذه المرحلة (الحظر قرار بشري أثقل)؛ والمقترح
--   على غرف المجتمعات العامة حصراً — المجموعات المشفرة لا يراها البوت أصلاً.

-- ============================================================
-- 1) أعمدة المقترح على الرسائل — بلا سياسة جديدة: تقرأ بسياسات الرسائل القائمة
-- ============================================================
alter table public.messages add column if not exists proposal jsonb;
alter table public.messages add column if not exists proposal_state text;
alter table public.messages add column if not exists proposal_state_by uuid
  references public.profiles(id) on delete set null;
alter table public.messages add column if not exists proposal_state_at timestamptz;

alter table public.messages drop constraint if exists messages_proposal_state_check;
alter table public.messages add constraint messages_proposal_state_check check (
  (proposal is null and proposal_state is null and proposal_state_by is null and proposal_state_at is null)
  or (proposal is not null and proposal_state in ('pending','approved','rejected')));

create index if not exists messages_proposal_pending
  on public.messages (conversation_id) where proposal_state = 'pending';

-- ============================================================
-- 2) bot_send_message بإعادة تعريف: يقبل مقترحاً منظماً بعد تحقق صارم
--    (التوقيع نفسه للنداءات القائمة — المعامل جديد افتراضي null فلا كسر)
-- ============================================================
create or replace function public.bot_send_message(
  p_bot uuid, p_conv uuid, p_text text, p_reply_to uuid default null,
  p_proposal jsonb default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare mid uuid; c record; m record;
  p_action text; p_target uuid; p_minutes int; p_reason text;
begin
  select * into c from conversations where id = p_conv;
  if c.id is null then raise exception 'chat not found'; end if;
  select * into m from conversation_participants
   where conversation_id = p_conv and user_id = p_bot;
  if m.user_id is null then raise exception 'bot not in chat'; end if;
  if c.kind = 'channel' and m.role not in ('owner', 'admin') then
    raise exception 'admins only'; -- القنوات: النشر للمشرفين فقط
  end if;
  -- الكتم المجتمعي يُفرض على البوت كأي عضو (community_mutes من ترحيل 023 —
  -- الكتم في وصل على مستوى المجتمع ويشمل كل غرفه)
  if c.community_id is not null and exists (
      select 1 from community_mutes m
      where m.community_id = c.community_id and m.user_id = p_bot
        and m.until_at > now()) then
    raise exception 'bot is muted';
  end if;
  -- حد الإغراق: 20 رسالة في الدقيقة لكل بوت (حماية لطبقة مجانية)
  if (select count(*) from messages x
      where x.conversation_id = p_conv and x.sender_id = p_bot
        and x.created_at > now() - interval '60 seconds') >= 20 then
    raise exception 'rate limit';
  end if;
  if char_length(coalesce(p_text, '')) not between 1 and 4000 then
    raise exception 'bad text length';
  end if;
  if p_reply_to is not null and not exists
     (select 1 from messages r
       where r.id = p_reply_to and r.conversation_id = p_conv) then
    p_reply_to := null;
  end if;

  -- ===== تحقق المقترح الصارم: غرف المجتمعات العامة حصراً وشكل مغلق =====
  if p_proposal is not null then
    if c.community_id is null then
      raise exception 'proposals community rooms only';
    end if;
    if jsonb_typeof(p_proposal) <> 'object' then
      raise exception 'bad proposal';
    end if;
    p_action := p_proposal->>'action';
    if p_action not in ('mute', 'kick') then
      raise exception 'bad proposal action';
    end if;
    begin
      p_target := nullif(btrim(coalesce(p_proposal->>'target_id', '')), '')::uuid;
    exception when others then
      raise exception 'bad proposal target';
    end;
    if p_target is null then
      raise exception 'bad proposal target';
    end if;
    -- الهدف عضو فعلي في هذه المحادثة — لا مقترح على غرباء
    if not exists (select 1 from conversation_participants cp
                   where cp.conversation_id = p_conv and cp.user_id = p_target) then
      raise exception 'bad proposal target';
    end if;
    if p_action = 'mute' then
      begin
        p_minutes := nullif(btrim(coalesce(p_proposal->>'minutes', '')), '')::int;
      exception when others then
        raise exception 'bad proposal duration';
      end;
      if p_minutes not between 1 and 43200 then
        raise exception 'bad proposal duration';
      end if;
    else
      p_minutes := null; -- الطرد بلا مدة — والحظر قرار بشري أثقل مقصود من هذه المرحلة
    end if;
    p_reason := nullif(btrim(coalesce(p_proposal->>'reason', '')), '');
    if char_length(coalesce(p_reason, '')) > 200 then
      raise exception 'bad proposal reason';
    end if;
  end if;

  insert into messages (conversation_id, sender_id, type, content, reply_to,
                        proposal, proposal_state)
  values (p_conv, p_bot, 'text', p_text, p_reply_to,
          p_proposal,
          case when p_proposal is null then null else 'pending' end)
  returning id into mid;
  return mid;
end; $$;

-- ============================================================
-- 3) قائمة المقترحات المعلقة لمشرفي المجتمع — بأسماء البوت والهدف والغرفة
-- ============================================================
create or replace function public.proposals_list(cid uuid)
returns table (
  message_id uuid, conversation_id uuid, room_title text,
  bot_id uuid, bot_name text,
  target_id uuid, target_name text,
  action text, minutes int, reason text,
  created_at timestamptz
) language sql security definer stable set search_path = public as $$
  select
    m.id, m.conversation_id, coalesce(c.title, ''),
    m.sender_id, coalesce(bp.display_name, bp.username, ''),
    (m.proposal->>'target_id')::uuid,
    coalesce(tp.display_name, tp.username, ''),
    m.proposal->>'action',
    nullif(m.proposal->>'minutes', '')::int,
    nullif(m.proposal->>'reason', ''),
    m.created_at
  from public.messages m
  join public.conversations c on c.id = m.conversation_id
  join public.profiles bp on bp.id = m.sender_id
  left join public.profiles tp on tp.id = (m.proposal->>'target_id')::uuid
  where c.community_id = cid
    and m.proposal_state = 'pending'
    and public.is_community_admin(cid)
  order by m.created_at desc
$$;

-- ============================================================
-- 4) قرار المشرف: موافقة تنفذ بإجراءات 023 بصلاحية المشرف نفسه، أو رفض
--    (أخطاء الإشراف الحقيقية تمر بصدق: owner/admin/نفسه → تُعلن ولا تعيّن الحالة)
-- ============================================================
create or replace function public.proposal_resolve(p_msg uuid, p_approve boolean)
returns text language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); m record; cid uuid; out_ text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into m from messages
    where id = p_msg and proposal_state = 'pending';
  if m.id is null then raise exception 'proposal not found'; end if;
  select community_id into cid from conversations where id = m.conversation_id;
  if cid is null then raise exception 'not a community room'; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;

  if p_approve then
    if m.proposal->>'action' = 'mute' then
      perform public.community_mute(
        cid,
        (m.proposal->>'target_id')::uuid,
        nullif(m.proposal->>'minutes', '')::int,
        nullif(m.proposal->>'reason', ''));
      out_ := 'muted';
    else
      perform public.community_kick(
        cid,
        (m.proposal->>'target_id')::uuid,
        false,
        nullif(m.proposal->>'reason', ''));
      out_ := 'kicked';
    end if;
  else
    out_ := 'rejected';
  end if;

  -- التنفيذ نجح (أو رفض صريح) — عندها فقط تُعيّن الحالة؛ وإخفاق الإشراف الحقيقي
  -- (هدف مشرف مثلاً) يرمي استثناء فيبقى المقترح معلقاً بصدق لا يُعلن ناجحاً كاذباً
  update messages
    set proposal_state = case when p_approve then 'approved' else 'rejected' end,
        proposal_state_by = me,
        proposal_state_at = now()
  where id = p_msg;
  return out_;
end; $$;

-- ============================================================
-- 5) أحداث العضوية للويب هوك — توقيع HMAC نفسه ونمط الإرسال نفسه
-- ============================================================
create or replace function public.bot_member_event_dispatch()
returns trigger language plpgsql security definer set search_path = public as $$
declare b record; payload jsonb; ev text; cid uuid; mid uuid;
begin
  ev := case when tg_op = 'INSERT' then 'member_join' else 'member_leave' end;
  cid := coalesce(new.conversation_id, old.conversation_id);
  mid := coalesce(new.user_id, old.user_id);
  for b in
    select bt.id, bt.webhook_url, bt.webhook_secret
    from bots bt
    join conversation_participants p on p.user_id = bt.id
      and p.conversation_id = cid
    where bt.is_active and bt.webhook_url is not null
      and bt.id <> mid -- بوت المغادرة حُذف صفه أصلاً — وبوت الانضمام لا ينبّه نفسه
  loop
    payload := jsonb_build_object(
      'update_id', gen_random_uuid(),
      'event', ev,
      'chat_id', cid,
      'member_id', mid,
      'at', now());
    begin
      perform extensions.net.http_post(
        url := b.webhook_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'User-Agent', 'WaslChat-Bot-Webhook/1.0',
          'X-Wasl-Signature', 'sha256=' || encode(
            hmac(payload::text, b.webhook_secret, 'sha256'), 'hex')),
        body := payload::text,
        timeout_milliseconds := 8000);
    exception when others then
      null; -- pg_net غير مفعّل أو فشل شبكة: لا نعطّل الانضمام/المغادرة أبداً
    end;
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end; $$;

drop trigger if exists bot_member_join_dispatch on public.conversation_participants;
create trigger bot_member_join_dispatch after insert on public.conversation_participants
  for each row execute function public.bot_member_event_dispatch();

drop trigger if exists bot_member_leave_dispatch on public.conversation_participants;
create trigger bot_member_leave_dispatch after delete on public.conversation_participants
  for each row execute function public.bot_member_event_dispatch();

-- ============================================================
-- 6) إحصاءات البوت لصاحبه حصراً — ما يمكن قراءته فعلاً من الجداول القائمة
-- ============================================================
create or replace function public.bot_stats(p_bot uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); r record;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from bots where id = p_bot and owner_id = me) then
    raise exception 'not owner';
  end if;
  select
    count(*) filter (where sender_id = p_bot) as total_msgs,
    count(*) filter (where sender_id = p_bot
                      and created_at > now() - interval '24 hours') as msgs_24h,
    max(created_at) filter (where sender_id = p_bot) as last_at,
    (select count(*) from conversation_participants cp
      where cp.user_id = p_bot) as convs,
    (select coalesce(sum(x.cnt), 0)
       from (select count(*) as cnt from conversation_participants cp
              where cp.user_id = p_bot
              group by cp.conversation_id) x) as reach,
    (select count(*) from messages m
       join conversations c on c.id = m.conversation_id
      where m.proposal_state = 'pending' and m.sender_id = p_bot) as prop_pending,
    (select count(*) from messages m
      where m.proposal_state = 'approved' and m.sender_id = p_bot) as prop_approved,
    (select count(*) from messages m
      where m.proposal_state = 'rejected' and m.sender_id = p_bot) as prop_rejected
  into r
  from messages;
  return jsonb_build_object(
    'total_messages', r.total_msgs,
    'messages_24h', r.msgs_24h,
    'last_message_at', r.last_at,
    'conversations', r.convs,
    'members_reached', r.reach,
    'proposals_pending', r.prop_pending,
    'proposals_approved', r.prop_approved,
    'proposals_rejected', r.prop_rejected);
end; $$;

-- ============================================================
-- 7) تحقيقات الإلزام — شغّلها بعد الترحيل وتحقق بالنتائج
-- ============================================================
--
--   أ) أعمدة المقترح بقيدها:
--      select column_name from information_schema.columns
--        where table_name='messages' and column_name like 'proposal%'; — أربعة.
--      select conname from pg_constraint where conname='messages_proposal_state_check'; — صف واحد.
--
--   ب) فحص RLS: لا سياسة كتابة جديدة إطلاقاً —
--      select count(*) from pg_policies where tablename='messages'; — كما كانت حرفياً.
--
--   ج) الدوال الجديدة مثبتة:
--      select count(*) from pg_proc where proname in
--        ('proposals_list','proposal_resolve','bot_member_event_dispatch','bot_stats'); — 4.
--
--   د) من SQL Editor أنت مشرف مجتمع: select proposals_list('<cid>');
--      يعيد صفوفاً فارغة بلا خطأ (لا مقترحات بعد) — والدالة تعمل.
--
--   هـ) أحداث العضوية: انضم بعضو لمجتمع فيه بوت نشط ذو ويب هوك — يصل حدث
--      member_join موقّع بX-Wasl-Signature، ومغادرته يصل member_leave.
