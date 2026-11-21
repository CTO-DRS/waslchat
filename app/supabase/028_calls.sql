-- وصل شات 0.17.0: المرحلة 6 أ) — المكالمات الصوتية والمرئية الفردية (WebRTC)
-- شغّله في SQL Editor بعد 027_ai_moderation.sql.
--
-- الفلسفة (مبدأ «الخصوصية قبل الميزة»):
-- - الصوت والصورة لا يعبران أي خادم في الاتصال الناجح: اتصال مباشر P2P مشفّر
--   DTLS-SRTP بين الجهازين، ومفاتيح التشفير تُتفاوض بينهما حصراً — خادم وصل
--   لا يسمع المكالمة ولا يراها، ولا يستطيع حتى لو أراد.
-- - ما يعرفه الخادم هو «أيضاً» المكالمة: مَن صلى مَن ومتى وكم استغرقت وكيف
--   انتهت — هذا ما يعرفه خادم أي تطبيق مكالمات، ونجعله سجل مكالمات يقرؤه
--   الطرفان فقط ويُنظَّف تلقائياً بعد 90 يوماً.
-- - بيانات إشارة الاتصال (SDP/ICE) تعبر قناة Realtime لحظية لا تُخزَّن إطلاقاً
--   في قاعدة البيانات، وقد تكشف عنوان شبكة طرف للطرف الآخر — هذا مطلوب
--   اتصالياً لأي WebRTC، وموثق صادقاً في TRANSPARENCY.md.
-- - كل إدراج يفرض عبر RLS: محادثة فردية واقعية (is_group=false وkind='chat')
--   والطرفان المشاركان فيها فعلاً — لا مكالمات عبر القنوات ولا المجموعات ولا
--   «المحفوظة» ولا لطرف غريب.
-- - انتقالات الحالة (ردّ/رفض/إلغاء/فائتة/فشل/انتهت) عبر دالة security definer
--   تحدد دور مَن يحق له كل انتقال، ولا حذف ولا تحديث مباشر من العملاء.

-- ============ 1) جدول سجل المكالمات ============

create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null default 'voice' check (kind in ('voice', 'video')),
  status text not null default 'ringing' check (status in (
    'ringing', 'answered', 'declined', 'missed', 'cancelled', 'failed', 'ended')),
  duration integer not null default 0 check (duration >= 0 and duration <= 86400),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  -- لا مكالمة لنفسك عبر السحابة («رسائلي المحفوظة» لا تُكالم)
  constraint calls_no_self check (caller_id <> callee_id)
);
alter table public.calls enable row level security;

create index if not exists calls_callee_idx on public.calls (callee_id, created_at desc);
create index if not exists calls_caller_idx on public.calls (caller_id, created_at desc);
create index if not exists calls_conv_idx on public.calls (conversation_id, created_at desc);

-- القراءة للطرفين فقط — لا أحد غيرهما يرى أن مكالمة حصلت
create policy "calls read participants" on public.calls
  for select to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid());

-- الإدراج للطالب فقط: محادثة فردية من نوع chat يشارك فيها الطرفان فعلاً
create policy "calls insert by caller" on public.calls
  for insert to authenticated
  with check (
    caller_id = auth.uid()
    and exists (
      select 1 from conversations c
      where c.id = conversation_id
        and c.is_group = false
        and c.kind = 'chat'
        and exists (
          select 1 from conversation_participants p
          where p.conversation_id = c.id and p.user_id = auth.uid())
        and exists (
          select 1 from conversation_participants p
          where p.conversation_id = c.id and p.user_id = callee_id)
    )
  );

-- بلا سياسات تحديث أو حذف: العملاء لا يكتبون إلا عبر call_update أدناه
-- والتنظيف عبر pg_cron. anon لا يرى الجدول أصلاً.
revoke all on table public.calls from anon;

-- ============ 2) انتقالات الحالة: security definer بأدوار صارمة ============
-- المُستدعي (caller): إلغاء قبل الرد، تصنيف «فائتة/فشلت».
-- المُستدعى (callee): الرد، الرفض.
-- بعد الرد: أي طرف ينتهي المكالمة بالمدة، والفشل محتمَل من الطرفين.
-- الحالات النهائية (انتهت/رفضت/فائتة/ملغاة) مغلقة — لا تُعاد كتابتها أبداً.
create or replace function public.call_update(call_id uuid, new_status text, dur integer default null)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  me uuid;
  c public.calls%rowtype;
begin
  me := auth.uid();
  if me is null then raise exception 'not authenticated'; end if;
  if new_status not in ('answered', 'declined', 'cancelled', 'missed', 'failed', 'ended') then
    raise exception 'bad status';
  end if;
  if call_id is null then raise exception 'not found'; end if;
  select * into c from public.calls where id = call_id;
  if not found then raise exception 'not found'; end if;
  if c.caller_id <> me and c.callee_id <> me then raise exception 'not allowed'; end if;

  -- حالة نهائية لا تُعاد — سباقات التحديث المتأخرة صمت لا خطأ
  if c.status in ('ended', 'declined', 'missed', 'cancelled') then
    return false;
  end if;

  if new_status = 'answered' then
    -- الرد حصراً للمُستدعى على مكالمة تُرن
    if c.status <> 'ringing' or me <> c.callee_id then raise exception 'not allowed'; end if;
    update public.calls set status = 'answered', answered_at = now() where id = call_id;
    return true;
  elsif new_status = 'declined' then
    -- الرفض حصراً للمُستدعى على مكالمة تُرن
    if c.status <> 'ringing' or me <> c.callee_id then raise exception 'not allowed'; end if;
    update public.calls set status = 'declined', ended_at = now() where id = call_id;
    return true;
  elsif new_status = 'cancelled' then
    -- الإلغاء حصراً للمُستدعي قبل الرد (الطرف الآخر انسحب من الرنين)
    if me <> c.caller_id then raise exception 'not allowed'; end if;
    update public.calls set status = 'cancelled', ended_at = now() where id = call_id;
    return true;
  elsif new_status = 'missed' then
    -- «فائتة» يصنفها المُستدعي بعد مهلة الرنين — لا يقررها المُستدعى
    if me <> c.caller_id then raise exception 'not allowed'; end if;
    update public.calls set status = 'missed', ended_at = now() where id = call_id;
    return true;
  elsif new_status = 'failed' then
    -- الفشل محتمَل من الطرفين (فصل شبكة، رفض أذونات، فشل اتصال)
    update public.calls set status = 'failed', ended_at = now() where id = call_id;
    return true;
  else
    -- ended: فقط بعد الرد، والمدة من مَن أنهى (0–86400 ثانية محصورة)
    if c.status <> 'answered' then raise exception 'not allowed'; end if;
    update public.calls set status = 'ended', ended_at = now(),
      duration = coalesce(least(greatest(coalesce(dur, 0), 0), 86400), 0)
    where id = call_id;
    return true;
  end if;
end $$;
revoke all on function public.call_update(uuid, text, integer) from public, anon;
grant execute on function public.call_update(uuid, text, integer) to authenticated;

-- ============ 3) إشعار «مكالمة واردة» بنفس آلية الرسائل ============
-- يُطلق عند الإدراج (تُرن) فقط — يستدعي دالة push بنفس سر الـWebhook.
-- إن لم تُحدَّث دالة push بعد لفهم جدول calls فترتجع «ignored» بلا أذى،
-- والمكالمة تعمل عبر Realtime لحظياً كلما كان التطبيق متصلاً.
create or replace function public.calls_push() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare url text; secret text;
begin
  if new.status <> 'ringing' then return new; end if;
  url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/push';
  select prosrc into secret from pg_proc where proname = 'notify_push' limit 1;
  secret := substring(secret from '''x-webhook-secret''\s*,\s*''([^'']+)''');
  if secret is null then return new; -- بلا سر لا إشعار ولا إفشال المكالمة
  end if;
  perform net.http_post(
    url := url,
    body := jsonb_build_object('type', 'INSERT', 'table', 'calls', 'record', to_jsonb(new)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', secret)
  );
  return new;
end $$;
drop trigger if exists calls_push on public.calls;
create trigger calls_push after insert on public.calls for each row execute function public.calls_push();

-- ============ 4) البث اللحظي: الطرفان يرأيان تغيّر الحالة فوراً ============
alter publication supabase_realtime add table public.calls;

-- ============ 5) تنظيف يومي: سجل المكالمات عمره أكثر من 90 يوماً ============
do $$
begin
  begin perform cron.unschedule('wasl-calls-expiry'); exception when others then null; end;
  perform cron.schedule('wasl-calls-expiry', '44 4 * * *',
    'delete from public.calls where created_at < now() - interval ''90 days''');
end $$;
