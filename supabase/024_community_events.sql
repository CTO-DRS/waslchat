-- وصل شات 0.12.0: أحداث المجتمع وتذكيراتها (المرحلة 3 — مجتمعات بمستوى ديسكورد)
-- شغّله في SQL Editor بعد 023_community_moderation.sql. ثم انشر الدالة supabase/functions/event-reminders.
--
-- الفكرة:
--   - مشرفو المجتمع (أو من أنشأ الحدث) ينشئون حدثاً بعنوان ووصف ومكان ووقت بدء ومدة،
--     مع تذكير قبل البدء (بلا تذكير أو 15 دقيقة → 24 ساعة).
--   - الأعضاء يجيبون: «سأحضر» أو «ربما» أو «لن أحضر» — والعدّادات وأسماء المجيبين ظاهرة للجميع.
--   - التذكير من الخادم: pg_cron كل 10 دقائق يستدعي دالة event-reminders فترسل إشعار FCM
--     لكل أعضاء المجتمع قبل بدء الحدث بالمدة المحددة (مرة واحدة لكل حدث، علم reminded_at).
--
-- مبادئ التصميم (نمط 023):
--   - الجدولان للقراءة فقط عبر RLS؛ كل الكتابة تمر عبر دوال security definer تتحقق من العضوية
--     والتراتب: الإنشاء والتعديل والحذف لمشرفي المجتمع (التعديل والحذف أيضاً لمن أنشأ الحدث)،
--     والرد على الحضور لأي عضو على حدث لم ينتهِ بعد.
--   - لا يمس هذا الترحيل المحادثات الخاصة والمجموعات والقنوات إطلاقاً.
--   - أحداث منتهية أكثر من 30 يوماً تُحذف دورياً (pg_cron) مع ردودها (تتالي).

-- ============================================================
-- 1) الجداول
-- ============================================================

-- الحدث: صف لكل حدث مجتمعي
create table if not exists public.community_events (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 120),
  description text check (description is null or char_length(btrim(description)) between 1 and 1000),
  location text check (location is null or char_length(btrim(location)) between 1 and 200),
  starts_at timestamptz not null,
  duration_minutes int not null default 60 check (duration_minutes between 5 and 10080),
  remind_minutes int not null default 30 check (remind_minutes in (0, 15, 30, 60, 180, 1440)),
  reminded_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists community_events_upcoming
  on public.community_events (community_id, starts_at);
-- لدالة التذكيرات: الأحداث المستحقة فقط (فهرس جزئي صغير)
create index if not exists community_events_due
  on public.community_events (starts_at) where reminded_at is null;

-- ردود الحضور: صف لكل عضو على كل حدث
create table if not exists public.community_event_rsvps (
  event_id uuid not null references public.community_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  response text not null check (response in ('going', 'maybe', 'not_going')),
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index if not exists community_event_rsvps_user on public.community_event_rsvps (user_id);

-- ============================================================
-- 2) سياسات RLS — القراءة فقط؛ الكتابة عبر الدوال حصراً
-- ============================================================
alter table public.community_events enable row level security;
alter table public.community_event_rsvps enable row level security;

-- الأحداث: أعضاء المجتمع فقط
drop policy if exists "events read members" on public.community_events;
create policy "events read members" on public.community_events
  for select to authenticated
  using (public.is_community_member(community_id));

-- الردود: أعضاء مجتمع الحدث فقط (ليروا من سيحضر)
drop policy if exists "event rsvps read members" on public.community_event_rsvps;
create policy "event rsvps read members" on public.community_event_rsvps
  for select to authenticated
  using (exists (
    select 1 from community_events e
    where e.id = event_id and public.is_community_member(e.community_id)
  ));

-- ============================================================
-- 3) الإنشاء والتعديل والحذف — لمشرفي المجتمع (والمنشئ في التعديل والحذف)
-- ============================================================
create or replace function public.community_event_create(
  cid uuid, p_title text, p_description text default null, p_location text default null,
  p_starts_at timestamptz, p_duration_minutes int default 60, p_remind_minutes int default 30
)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  eid uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'bad title';
  end if;
  if coalesce(p_starts_at, to_timestamp(0)) < now() + interval '5 minutes'
     or coalesce(p_starts_at, to_timestamp(0)) > now() + interval '365 days' then
    raise exception 'bad starts_at';
  end if;
  if coalesce(p_duration_minutes, 60) not between 5 and 10080 then
    raise exception 'bad duration';
  end if;
  if coalesce(p_remind_minutes, 30) not in (0, 15, 30, 60, 180, 1440) then
    raise exception 'bad remind';
  end if;

  insert into community_events
    (community_id, created_by, title, description, location, starts_at, duration_minutes, remind_minutes)
  values (
    cid, me, btrim(p_title),
    nullif(btrim(coalesce(p_description, '')), ''),
    nullif(btrim(coalesce(p_location, '')), ''),
    p_starts_at, coalesce(p_duration_minutes, 60), coalesce(p_remind_minutes, 30)
  ) returning id into eid;
  return eid;
end; $$;

-- التعديل: منشئ الحدث أو مشرفو المجتمع — وقبل بدئه فقط (إعادة تسليح التذكير تلقائياً)
create or replace function public.community_event_update(
  eid uuid, p_title text, p_description text default null, p_location text default null,
  p_starts_at timestamptz, p_duration_minutes int default 60, p_remind_minutes int default 30
)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ev community_events%rowtype;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into ev from community_events where id = eid;
  if ev.id is null then raise exception 'not found'; end if;
  if ev.created_by <> me and not public.is_community_admin(ev.community_id) then
    raise exception 'not allowed';
  end if;
  if ev.starts_at <= now() then raise exception 'already started'; end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'bad title';
  end if;
  if coalesce(p_starts_at, to_timestamp(0)) < now() + interval '5 minutes'
     or coalesce(p_starts_at, to_timestamp(0)) > now() + interval '365 days' then
    raise exception 'bad starts_at';
  end if;
  if coalesce(p_duration_minutes, 60) not between 5 and 10080 then
    raise exception 'bad duration';
  end if;
  if coalesce(p_remind_minutes, 30) not in (0, 15, 30, 60, 180, 1440) then
    raise exception 'bad remind';
  end if;

  update community_events set
    title = btrim(p_title),
    description = nullif(btrim(coalesce(p_description, '')), ''),
    location = nullif(btrim(coalesce(p_location, '')), ''),
    starts_at = p_starts_at,
    duration_minutes = coalesce(p_duration_minutes, 60),
    remind_minutes = coalesce(p_remind_minutes, 30),
    reminded_at = null
  where id = eid;
end; $$;

-- الحذف: منشئ الحدث أو مشرفو المجتمع — في أي وقت (الردود تُحذف بالتتالي)
create or replace function public.community_event_delete(eid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ev community_events%rowtype;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into ev from community_events where id = eid;
  if ev.id is null then return; end if;
  if ev.created_by <> me and not public.is_community_admin(ev.community_id) then
    raise exception 'not allowed';
  end if;
  delete from community_events where id = eid;
end; $$;

-- ============================================================
-- 4) ردود الحضور — لأي عضو على حدث لم ينتهِ بعد
-- ============================================================
create or replace function public.community_event_respond(eid uuid, p_response text)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  ev community_events%rowtype;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into ev from community_events where id = eid;
  if ev.id is null then raise exception 'not found'; end if;
  if not public.is_community_member(ev.community_id) then raise exception 'not allowed'; end if;
  if ev.starts_at + make_interval(mins => ev.duration_minutes) <= now() then
    raise exception 'event ended';
  end if;

  if coalesce(p_response, 'none') = 'none' then
    delete from community_event_rsvps where event_id = eid and user_id = me;
  elsif p_response in ('going', 'maybe', 'not_going') then
    insert into community_event_rsvps (event_id, user_id, response, updated_at)
    values (eid, me, p_response, now())
    on conflict (event_id, user_id) do update
      set response = excluded.response, updated_at = now();
  else
    raise exception 'bad response';
  end if;
end; $$;

-- ============================================================
-- 5) قوائم القراءة
-- ============================================================
-- أحداث المجتمع: القادمة والجارية وانتهت قبل أسبوع — مع العدّادات وردّي
create or replace function public.community_events_list(cid uuid)
returns table (
  id uuid, title text, description text, location text,
  starts_at timestamptz, duration_minutes int, remind_minutes int,
  created_by uuid, creator_name text,
  going_count int, maybe_count int, my_response text, ended boolean
) language sql security definer stable set search_path = public as $$
  select
    e.id, e.title, e.description, e.location,
    e.starts_at, e.duration_minutes, e.remind_minutes,
    e.created_by, coalesce(p.display_name, p.username, ''),
    (select count(*)::int from community_event_rsvps r
      where r.event_id = e.id and r.response = 'going'),
    (select count(*)::int from community_event_rsvps r
      where r.event_id = e.id and r.response = 'maybe'),
    (select r.response from community_event_rsvps r
      where r.event_id = e.id and r.user_id = auth.uid()),
    (e.starts_at + make_interval(mins => e.duration_minutes)) <= now()
  from community_events e
  join profiles p on p.id = e.created_by
  where e.community_id = cid
    and (e.starts_at + make_interval(mins => e.duration_minutes)) > now() - interval '7 days'
  order by e.starts_at
  limit 100;
$$;

-- المجيبون على حدث: بالأسماء والصور (للأعضاء كافة)
create or replace function public.community_event_rsvps_list(eid uuid)
returns table (user_id uuid, username text, name text, avatar_url text, response text)
language sql security definer stable set search_path = public as $$
  select r.user_id, p.username, coalesce(p.display_name, p.username), p.avatar_url, r.response
  from community_event_rsvps r
  join profiles p on p.id = r.user_id
  where r.event_id = eid
  order by r.updated_at
$$;

-- ============================================================
-- 6) صلاحيات التنفيذ: للمسجلين فقط (بأسلوب الترحيلات السابقة)
-- ============================================================
do $$
declare f text;
begin
  for f in select unnest(array[
    'public.community_event_create(uuid, text, text, text, timestamptz, integer, integer)',
    'public.community_event_update(uuid, text, text, text, timestamptz, integer, integer)',
    'public.community_event_delete(uuid)',
    'public.community_event_respond(uuid, text)',
    'public.community_events_list(uuid)',
    'public.community_event_rsvps_list(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ============================================================
-- 7) التذكيرات: pg_cron كل 10 دقائق يستدعي دالة event-reminders
--    (نفس سر الـWebhook المستخرج من notify_push كما في ترحيل 013)
-- ============================================================
do $$
declare src text; secret text;
begin
  select prosrc into src from pg_proc where proname = 'notify_push' limit 1;
  secret := substring(src from '''x-webhook-secret''\s*,\s*''([^'']+)''');
  if secret is null then raise exception 'webhook secret not found'; end if;
  begin perform cron.unschedule('wasl-event-reminders'); exception when others then null; end;
  perform cron.schedule('wasl-event-reminders', '*/10 * * * *', format(
    $f$select net.http_post(url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/event-reminders',
       headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', %L),
       body := '{}'::jsonb)$f$, secret));
end $$;

-- ============================================================
-- 8) حذف الأحداث المنتهية قبل 30 يوماً يومياً 04:33 (الردود تُحذف بالتتالي)
-- ============================================================
do $$
begin
  begin perform cron.unschedule('wasl-events-expiry'); exception when others then null; end;
  perform cron.schedule('wasl-events-expiry', '33 4 * * *',
    'delete from public.community_events where starts_at + make_interval(mins => duration_minutes) < now() - interval ''30 days''');
end $$;
