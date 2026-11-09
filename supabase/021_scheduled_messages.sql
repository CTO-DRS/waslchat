-- وصل شات v0.4.3: الرسائل المجدولة (بند المرحلة 1)
-- شغّله في SQL Editor بعد 020_privacy_toggles.sql
--
-- التصميم الصادق:
-- 1) الرسالة تُشفَّر وتُرفع الآن، وتُحفظ بـ created_at مستقبلي + scheduled=true.
-- 2) RLS يمنع غير المرسل من رؤيتها قبل موعدها (الإخفاء من الخادم لا من العميل).
-- 3) مشغّل pg_cron كل دقيقة يُطلق المستحقات (scheduled=false): تحديث واحد
--    يوقظ Realtime (تصل الرسالة لحظياً) وTrigger الإشعارات معاً.
-- 4) دقة التسليم: خلال دقيقة من الموعد — ونذكر بها المستخدم بصدق.
-- 5) الإشعار لا يُرسل مبكراً: Trigger الإدخال يتخطى المجدولة، ويعود
--    للعمل عند إطلاقها عبر Trigger التحديث.

-- 1) عمود المجدولة
alter table public.messages add column if not exists scheduled boolean not null default false;

-- 2) القراءة: المرسل يرى مجدولته دائماً، والآخرون لا يرونها قبل موعدها
drop policy if exists "members read messages" on public.messages;
create policy "members read messages" on public.messages
  for select to authenticated
  using (public.is_member(conversation_id)
         and (sender_id = auth.uid() or created_at <= now()));

-- 3) الإرسال: نفس شروط 014 + سقف زمني للتأجيل (180 يوماً)
drop policy if exists "members send messages" on public.messages;
create policy "members send messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.can_post(conversation_id)
              and not public.is_dm_blocked(conversation_id, auth.uid())
              and created_at <= now() + interval '180 days');

-- 4) الرسائل المختفية: العدّ من موعد التسليم لا من لحظة الحفظ
--    (للرسائل العادية created_at = now() فلا تغيير في سلوكها)
create or replace function public.messages_set_expiry()
returns trigger language plpgsql security definer set search_path = public as $$
declare secs integer;
begin
  select disappear_seconds into secs from conversations where id = new.conversation_id;
  new.expires_at := case when secs is null then null
    else coalesce(new.created_at, now()) + make_interval(secs => secs) end;
  return new;
end; $$;

-- 5) الإشعارات: لا إشعار عند حفظ المجدولة، وإشعار لحظة إطلاقها
drop trigger if exists messages_push on public.messages;
create trigger messages_push after insert on public.messages
  for each row when (not coalesce(new.scheduled, false))
  execute function public.notify_push();
drop trigger if exists messages_push_release on public.messages;
create trigger messages_push_release after update of scheduled on public.messages
  for each row when (old.scheduled is true and new.scheduled is false)
  execute function public.notify_push();

-- 6) قائمة المحادثات: لا تتسرب معاينات غيري المجدولة، وعدّادي لا يحتسبها،
--    وتظهر مجدولتي بعلامة واضحة
drop function if exists public.my_chats();
create function public.my_chats()
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
        and (u.expires_at is null or u.expires_at > now())),
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
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;

-- 7) مُطلِق المجدول + الوظيفة كل دقيقة (إعادة الجدولة آمنة عند إعادة التشغيل)
create or replace function public.release_scheduled_messages()
returns void language plpgsql security definer set search_path = public as $$
begin
  update messages set scheduled = false
  where scheduled = true and created_at <= now();
end; $$;
do $$ begin
  if exists (select 1 from cron.job where jobname = 'release-scheduled-messages') then
    perform cron.unschedule('release-scheduled-messages');
  end if;
  perform cron.schedule('release-scheduled-messages', '* * * * *',
    'select public.release_scheduled_messages()');
end $$;
