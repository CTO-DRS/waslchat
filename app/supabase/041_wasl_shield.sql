-- وصل شات 1.10.0: Wasl Shield — الحماية ومكافحة الابتزاز
-- يُشغَّل بعد 040_official.sql. إضافي بالكامل: لا يحذف ولا يغيّر بيانات قائمة. آمن لإعادة التشغيل.
--
-- المبادئ:
--   - البلاغ يصل مباشرة للمدير العام (app_admins) دون فريق وسيط.
--   - المبلَّغ عنه لا يرى البلاغ ولا يُشعَر به: لا سياسة قراءة له إطلاقاً.
--   - الأدلة يرسلها المبلِّغ من جهازه (النصوص المشفّرة طرفياً لا يقرؤها الخادم)،
--     وتُخزَّن في مخزن خاص shield-evidence لا يقرؤه إلا المدير، وكل فتح يُسجَّل قبله
--     (سياسة التخزين نفسها تشترط سطر تدقيق حديثاً — لا يكفي أن تكون مديراً).
--   - كل إجراء إداري يتطلب مبرراً مكتوباً ويُسجَّل في سجل تدقيق إضافة-فقط مسلسل بالتجزئة.
--   - «إبطال الروابط»: الروابط الموقّعة لا تُلغى قبل انتهائها في Supabase، لذلك
--     الإبطال = نقل الملف إلى حجر shield-quarantine (عبر دالة shield-admin بصلاحية الخدمة)،
--     فيصبح كل رابط سابق 404 فوراً. لا شيء هنا يمسّ أجهزة المستخدمين.

-- ============ 1) إعدادات الحماية لكل مستخدم ============
create table if not exists public.shield_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default false,
  secure_screens boolean not null default true,   -- FLAG_SECURE على كل الشاشات الحساسة
  protect_media boolean not null default true,    -- وسائطي المرسلة: بلا حفظ/توجيه + علامة مائية + روابط 5 دقائق
  capture_alerts boolean not null default true,   -- تنبيه عند لقطة/تسجيل الشاشة حيث يدعم النظام
  updated_at timestamptz not null default now()
);
alter table public.shield_settings enable row level security;
drop policy if exists "shield settings own" on public.shield_settings;
create policy "shield settings own" on public.shield_settings for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- وسائط محمية: يضعها المرسل (أو الخادم إن كانت الحماية مفعّلة عنده)
alter table public.messages add column if not exists protected boolean not null default false;
alter table public.messages add column if not exists shield_removed boolean not null default false;

create or replace function public.messages_shield_defaults()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  -- منع إرسال الوسائط لمن قيّده المدير
  if new.type is distinct from 'text' and exists (
      select 1 from shield_restrictions r
      where r.user_id = new.sender_id and r.no_media and (r.until_at is null or r.until_at > now())) then
    raise exception 'SHIELD_MEDIA_RESTRICTED';
  end if;
  if new.type is distinct from 'text' and exists (
      select 1 from shield_settings s where s.user_id = new.sender_id and s.enabled and s.protect_media) then
    new.protected := true;
  end if;
  new.shield_removed := false;  -- لا يضعه إلا المدير عبر دالته
  return new;
end; $$;

-- ============ 2) القيود الإدارية ============
create table if not exists public.shield_restrictions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  no_media boolean not null default true,
  until_at timestamptz,
  case_id uuid,
  created_at timestamptz not null default now()
);
alter table public.shield_restrictions enable row level security; -- بلا سياسات: عبر الدوال فقط

create or replace function public.messages_shield_guard()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  -- لا يغيّر المستخدمون علمَي الحماية بعد الإرسال (المدير والخدمة عبر دوالهم فقط)
  if auth.uid() is not null and not public.is_app_admin() then
    new.protected := old.protected;
    new.shield_removed := old.shield_removed;
  end if;
  return new;
end; $$;
drop trigger if exists messages_shield_guard on public.messages;
create trigger messages_shield_guard before update on public.messages
  for each row execute function public.messages_shield_guard();

drop trigger if exists messages_shield_defaults on public.messages;
create trigger messages_shield_defaults before insert on public.messages
  for each row execute function public.messages_shield_defaults();

-- ============ 3) الحالات (البلاغات) ============
create table if not exists public.shield_cases (
  id uuid primary key default gen_random_uuid(),
  ref text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
  reporter uuid not null references auth.users(id) on delete cascade,
  target_user uuid references auth.users(id) on delete set null,
  conversation_id uuid references public.conversations(id) on delete set null,
  category text not null check (category in ('blackmail', 'threat', 'harassment', 'impersonation', 'other')),
  urgent boolean not null default false,
  severity text not null check (severity in ('critical', 'high', 'medium', 'low')),
  description text not null check (char_length(btrim(description)) between 3 and 2000),
  status text not null default 'new' check (status in ('new', 'reviewing', 'action_taken', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  retain_until timestamptz          -- يُضبط عند الإغلاق (+180 يوماً)؛ لا حذف قبله ولا والبلاغ مفتوح
);
create index if not exists shield_cases_status on public.shield_cases (status, created_at desc);
create index if not exists shield_cases_reporter on public.shield_cases (reporter, created_at desc);
alter table public.shield_cases enable row level security;
-- المبلِّغ يرى حالاته فقط. المبلَّغ عنه لا يرى شيئاً. لا إدراج/تعديل مباشر.
drop policy if exists "shield cases reporter reads own" on public.shield_cases;
create policy "shield cases reporter reads own" on public.shield_cases for select to authenticated
  using (reporter = auth.uid());

-- ============ 4) الأدلة ============
create table if not exists public.shield_evidence (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.shield_cases(id) on delete cascade,
  kind text not null check (kind in ('messages', 'media', 'file')),
  storage_path text not null,          -- داخل مخزن shield-evidence: {case_id}/{id}...
  mime text,
  size_bytes bigint,
  sha256 text,                          -- بصمة الملف كما رفعه المبلِّغ (سلامة الدليل)
  source_message uuid,                  -- الرسالة الأصلية إن وجدت
  created_at timestamptz not null default now()
);
alter table public.shield_evidence enable row level security; -- بلا سياسات: عبر الدوال فقط

-- ============ 5) الحجر (وسائط أُبطلت روابطها) ============
create table if not exists public.shield_quarantine (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.shield_cases(id) on delete cascade,
  original_path text not null,
  quarantine_path text not null,
  message_id uuid,
  created_at timestamptz not null default now()
);
alter table public.shield_quarantine enable row level security;

-- ============ 6) سجل التدقيق (إضافة فقط + سلسلة تجزئة) ============
create table if not exists public.shield_audit (
  seq bigserial primary key,
  at timestamptz not null default now(),
  actor uuid,
  case_id uuid,
  action text not null,
  target text,
  reason text,
  details jsonb not null default '{}'::jsonb,
  prev_hash text not null,
  hash text not null
);
create index if not exists shield_audit_case on public.shield_audit (case_id, seq);
alter table public.shield_audit enable row level security; -- القراءة عبر الدوال فقط

create or replace function public.shield_audit_chain()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare prev text;
begin
  perform pg_advisory_xact_lock(424242);
  select hash into prev from shield_audit order by seq desc limit 1;
  new.prev_hash := coalesce(prev, 'GENESIS');
  new.at := now();
  new.hash := encode(extensions.digest(
    new.prev_hash || '|' || new.at::text || '|' || coalesce(new.actor::text, '') || '|' ||
    coalesce(new.case_id::text, '') || '|' || new.action || '|' || coalesce(new.target, '') || '|' ||
    coalesce(new.reason, '') || '|' || new.details::text, 'sha256'), 'hex');
  return new;
end; $$;
drop trigger if exists shield_audit_chain on public.shield_audit;
create trigger shield_audit_chain before insert on public.shield_audit
  for each row execute function public.shield_audit_chain();

create or replace function public.shield_audit_immutable()
returns trigger language plpgsql as $$
begin
  raise exception 'SHIELD_AUDIT_IMMUTABLE';
end; $$;
drop trigger if exists shield_audit_no_update on public.shield_audit;
create trigger shield_audit_no_update before update or delete on public.shield_audit
  for each row execute function public.shield_audit_immutable();
drop trigger if exists shield_audit_no_truncate on public.shield_audit;
create trigger shield_audit_no_truncate before truncate on public.shield_audit
  for each statement execute function public.shield_audit_immutable();

create or replace function public._shield_log(p_case uuid, p_action text, p_target text,
                                             p_reason text, p_details jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, extensions as $$
  insert into shield_audit (actor, case_id, action, target, reason, details, prev_hash, hash)
  values (auth.uid(), p_case, p_action, p_target, p_reason, coalesce(p_details, '{}'::jsonb), '', '');
$$;

-- ============ 7) المخازن ============
insert into storage.buckets (id, name, public, file_size_limit)
values ('shield-evidence', 'shield-evidence', false, 52428800)
on conflict (id) do update set public = false;
insert into storage.buckets (id, name, public)
values ('shield-quarantine', 'shield-quarantine', false)
on conflict (id) do update set public = false;

-- الرفع: المبلِّغ فقط داخل مجلد حالته وما دامت مفتوحة
drop policy if exists "shield evidence upload by reporter" on storage.objects;
create policy "shield evidence upload by reporter" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'shield-evidence'
    and exists (select 1 from public.shield_cases c
                where c.id::text = (storage.foldername(name))[1]
                  and c.reporter = auth.uid() and c.status <> 'closed'));
-- القراءة: المدير فقط، وبشرط سطر تدقيق «فتح دليل» لنفس الملف خلال آخر دقيقتين
-- (دالة security definer لأن سجل التدقيق نفسه لا يُقرأ مباشرة)
create or replace function public.shield_can_read_evidence(p_name text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.is_app_admin() and exists (
    select 1 from shield_audit a
    where a.actor = auth.uid() and a.action = 'evidence_open'
      and a.target = p_name and a.at > now() - interval '2 minutes');
$$;
drop policy if exists "shield evidence read by admin with audit" on storage.objects;
create policy "shield evidence read by admin with audit" on storage.objects for select to authenticated
  using (bucket_id = 'shield-evidence' and public.shield_can_read_evidence(name));
-- الحجر: لا قراءة لأحد من التطبيق (الخدمة فقط)

-- ============ 8) الإشعار الفوري للمدير ============
-- رسالة من «دعم وصل شات» إلى كل مدير في محادثته معه → خط الإشعارات القائم (FCM).
-- لا تتضمن اسم المبلِّغ ولا المبلَّغ عنه.
create or replace function public._shield_notify_admins(p_text text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare sup uuid := official_id('support'); a uuid; dm uuid;
begin
  if sup is null then return; end if;
  for a in select user_id from app_admins loop
    select c.id into dm from conversations c
      join conversation_participants x on x.conversation_id = c.id and x.user_id = a
      join conversation_participants y on y.conversation_id = c.id and y.user_id = sup
      where not c.is_group and c.kind = 'chat' limit 1;
    if dm is null then
      insert into conversations (is_group, kind, created_by) values (false, 'chat', sup) returning id into dm;
      insert into conversation_participants (conversation_id, user_id) values (dm, a), (dm, sup);
    end if;
    insert into messages (conversation_id, sender_id, content) values (dm, sup, p_text);
    dm := null;
  end loop;
end; $$;

-- محادثة الدعم مع مستخدم (تُنشأ إن لم توجد)
create or replace function public._shield_support_dm(p_user uuid)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare sup uuid := official_id('support'); dm uuid;
begin
  select c.id into dm from conversations c
    join conversation_participants x on x.conversation_id = c.id and x.user_id = p_user
    join conversation_participants y on y.conversation_id = c.id and y.user_id = sup
    where not c.is_group and c.kind = 'chat' limit 1;
  if dm is null then
    insert into conversations (is_group, kind, created_by) values (false, 'chat', sup) returning id into dm;
    insert into conversation_participants (conversation_id, user_id) values (dm, p_user), (dm, sup);
  end if;
  return dm;
end; $$;

-- ============ 9) واجهة المستخدم ============
-- إنشاء بلاغ. يتحقق: معدل (5/يوم)، علاقة حقيقية بالمبلَّغ عنه (محادثة مشتركة)، صيغة الحقول.
create or replace function public.shield_report(p_category text, p_description text, p_urgent boolean,
                                               p_target uuid default null, p_conversation uuid default null,
                                               p_block boolean default true)
returns table (case_id uuid, ref text)
language plpgsql security definer set search_path = public, extensions as $$
declare me uuid := auth.uid(); sev text; cid uuid; r text;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if p_category not in ('blackmail', 'threat', 'harassment', 'impersonation', 'other') then
    raise exception 'bad category';
  end if;
  if char_length(btrim(coalesce(p_description, ''))) not between 3 and 2000 then
    raise exception 'bad description';
  end if;
  if (select count(*) from shield_cases where reporter = me and created_at > now() - interval '24 hours') >= 5 then
    raise exception 'SHIELD_RATE_LIMIT';
  end if;
  if p_target = me then raise exception 'bad target'; end if;
  if p_conversation is not null and not public.is_member(p_conversation) then
    raise exception 'not a member';
  end if;
  -- علاقة حقيقية: محادثة خاصة مشتركة (غير الغرف الرسمية التي يدخلها الجميع تلقائياً)،
  -- أو رسالة أرسلها المبلَّغ عنه في محادثة يشارك فيها المبلِّغ
  if p_target is not null and not exists (
      select 1 from conversation_participants a
      join conversation_participants b on b.conversation_id = a.conversation_id
      join conversations cv on cv.id = a.conversation_id
      where a.user_id = me and b.user_id = p_target
        and cv.id not in (select id from app_official)
        and (cv.community_id is null or cv.community_id not in (select id from app_official)))
     and not exists (
      select 1 from messages m
      join conversation_participants a on a.conversation_id = m.conversation_id and a.user_id = me
      where m.sender_id = p_target) then
    raise exception 'SHIELD_NO_RELATION';
  end if;

  sev := case
    when p_category in ('blackmail', 'threat') and coalesce(p_urgent, false) then 'critical'
    when p_category in ('blackmail', 'threat') then 'high'
    when p_category in ('harassment', 'impersonation') and coalesce(p_urgent, false) then 'high'
    when p_category in ('harassment', 'impersonation') then 'medium'
    when coalesce(p_urgent, false) then 'medium'
    else 'low' end;

  insert into shield_cases (reporter, target_user, conversation_id, category, urgent, severity, description)
  values (me, p_target, p_conversation, p_category, coalesce(p_urgent, false), sev, btrim(p_description))
  returning shield_cases.id, shield_cases.ref into cid, r;

  -- حظر صامت: نفس الحظر العادي، لا يكشف وجود بلاغ
  if p_block and p_target is not null then
    insert into blocks (blocker, blocked) values (me, p_target) on conflict do nothing;
  end if;

  perform _shield_log(cid, 'case_created', null, null,
                      jsonb_build_object('category', p_category, 'severity', sev, 'urgent', coalesce(p_urgent, false)));
  perform _shield_notify_admins(
    '🛡️ بلاغ جديد في Wasl Shield' || chr(10) ||
    'الرقم: ' || r || ' · الخطورة: ' ||
    case sev when 'critical' then 'حرجة 🔴' when 'high' then 'عالية 🟠' when 'medium' then 'متوسطة 🟡' else 'منخفضة' end ||
    chr(10) || 'افتح لوحة الإدارة ← البلاغات للمراجعة.');

  -- تأكيد للمبلِّغ في محادثة الدعم
  insert into messages (conversation_id, sender_id, content)
  values (_shield_support_dm(me), official_id('support'),
          'وصلنا بلاغك (رقم ' || r || ') ويراجعه المدير مباشرة. لن يعرف الطرف الآخر بالبلاغ ولا بهويتك.' || chr(10) ||
          'يمكنك إضافة أي تفاصيل أو أدلة بالرد هنا. إن كنت في خطر مباشر فاتصل بالجهات الأمنية فوراً.');
  return query select cid, r;
end; $$;

-- تسجيل دليل بعد رفعه (الرفع نفسه تحكمه سياسة التخزين)
create or replace function public.shield_add_evidence(p_case uuid, p_kind text, p_path text, p_mime text,
                                                     p_size bigint, p_sha256 text, p_source uuid default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare eid uuid;
begin
  if not exists (select 1 from shield_cases where id = p_case and reporter = auth.uid() and status <> 'closed') then
    raise exception 'not allowed';
  end if;
  if p_kind not in ('messages', 'media', 'file') then raise exception 'bad kind'; end if;
  if split_part(p_path, '/', 1) <> p_case::text then raise exception 'bad path'; end if;
  if not exists (select 1 from storage.objects where bucket_id = 'shield-evidence' and name = p_path) then
    raise exception 'object missing';
  end if;
  if (select count(*) from shield_evidence where case_id = p_case) >= 60 then raise exception 'too many'; end if;
  insert into shield_evidence (case_id, kind, storage_path, mime, size_bytes, sha256, source_message)
  values (p_case, p_kind, p_path, p_mime, p_size, p_sha256, p_source) returning id into eid;
  perform _shield_log(p_case, 'evidence_added', p_path, null, jsonb_build_object('kind', p_kind, 'sha256', p_sha256));
  return eid;
end; $$;

create or replace function public.shield_my_cases()
returns table (id uuid, ref text, category text, severity text, status text, created_at timestamptz,
               updated_at timestamptz, evidence bigint)
language sql stable security definer set search_path = public, extensions as $$
  select c.id, c.ref, c.category, c.severity, c.status, c.created_at, c.updated_at,
         (select count(*) from shield_evidence e where e.case_id = c.id)
  from shield_cases c where c.reporter = auth.uid() order by c.created_at desc;
$$;

-- ============ 10) واجهة المدير العام ============
create or replace function public._shield_admin()
returns void language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null or not public.is_app_admin() then raise exception 'not_admin'; end if;
end; $$;

create or replace function public._shield_need_reason(p text)
returns void language plpgsql immutable as $$
begin
  if char_length(btrim(coalesce(p, ''))) < 5 then raise exception 'SHIELD_REASON_REQUIRED'; end if;
end; $$;

create or replace function public.shield_admin_cases(p_status text default null)
returns table (id uuid, ref text, category text, severity text, urgent boolean, status text,
               created_at timestamptz, updated_at timestamptz, evidence bigint,
               reporter_name text, target_name text)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform _shield_admin();
  return query
    select c.id, c.ref, c.category, c.severity, c.urgent, c.status, c.created_at, c.updated_at,
           (select count(*) from shield_evidence e where e.case_id = c.id),
           coalesce(rp.display_name, rp.username), coalesce(tp.display_name, tp.username)
    from shield_cases c
    left join profiles rp on rp.id = c.reporter
    left join profiles tp on tp.id = c.target_user
    where p_status is null or c.status = p_status
    order by (c.status = 'closed'),
             array_position(array['critical','high','medium','low'], c.severity),
             c.created_at desc
    limit 300;
end; $$;

create or replace function public.shield_admin_case(p_case uuid)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare j json;
begin
  perform _shield_admin();
  select json_build_object(
    'case', to_json(c),
    'reporter', (select json_build_object('id', p.id, 'username', p.username, 'name', p.display_name,
                                          'avatar_url', p.avatar_url) from profiles p where p.id = c.reporter),
    'target', (select json_build_object('id', p.id, 'username', p.username, 'name', p.display_name,
                                        'avatar_url', p.avatar_url,
                                        'banned', (select u.banned_until > now() from auth.users u where u.id = p.id),
                                        'media_restricted', exists (select 1 from shield_restrictions r where r.user_id = p.id
                                                                    and (r.until_at is null or r.until_at > now())))
               from profiles p where p.id = c.target_user),
    'evidence', coalesce((select json_agg(e order by e.created_at) from shield_evidence e where e.case_id = c.id), '[]'),
    'quarantine', coalesce((select json_agg(q order by q.created_at) from shield_quarantine q where q.case_id = c.id), '[]'),
    'support_dm', public._shield_support_dm(c.reporter)
  ) into j from shield_cases c where c.id = p_case;
  if j is null then raise exception 'not found'; end if;
  perform _shield_log(p_case, 'case_viewed', null, null);
  return j;
end; $$;

-- فتح دليل: يسجَّل أولاً، ثم سياسة التخزين تسمح بالقراءة دقيقتين
create or replace function public.shield_admin_open_evidence(p_evidence uuid)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare e shield_evidence;
begin
  perform _shield_admin();
  select * into e from shield_evidence where id = p_evidence;
  if e.id is null then raise exception 'not found'; end if;
  perform _shield_log(e.case_id, 'evidence_open', e.storage_path, null, jsonb_build_object('evidence', e.id));
  return e.storage_path;
end; $$;

create or replace function public.shield_admin_set_status(p_case uuid, p_status text, p_reason text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _shield_admin();
  perform _shield_need_reason(p_reason);
  if p_status not in ('new', 'reviewing', 'action_taken', 'closed') then raise exception 'bad status'; end if;
  update shield_cases set status = p_status, updated_at = now(),
         closed_at = case when p_status = 'closed' then now() else null end,
         retain_until = case when p_status = 'closed' then now() + interval '180 days' else null end
   where id = p_case;
  if not found then raise exception 'not found'; end if;
  perform _shield_log(p_case, 'status_' || p_status, null, p_reason);
end; $$;

-- مراسلة المبلِّغ بصفة «دعم وصل شات» (لا يظهر حساب المدير الشخصي)
create or replace function public.shield_admin_message_reporter(p_case uuid, p_text text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare rep uuid;
begin
  perform _shield_admin();
  if char_length(btrim(coalesce(p_text, ''))) not between 1 and 4000 then raise exception 'bad text'; end if;
  select reporter into rep from shield_cases where id = p_case;
  if rep is null then raise exception 'not found'; end if;
  insert into messages (conversation_id, sender_id, content)
  values (_shield_support_dm(rep), official_id('support'), btrim(p_text));
  perform _shield_log(p_case, 'message_reporter', null, null, jsonb_build_object('chars', char_length(p_text)));
end; $$;

create or replace function public.shield_admin_thread(p_case uuid)
returns table (id uuid, from_support boolean, content text, type text, created_at timestamptz)
language plpgsql security definer set search_path = public, extensions as $$
declare rep uuid; dm uuid;
begin
  perform _shield_admin();
  select sc.reporter into rep from shield_cases sc where sc.id = p_case;
  if rep is null then raise exception 'not found'; end if;
  dm := _shield_support_dm(rep);
  perform _shield_log(p_case, 'thread_viewed', null, null);
  return query select m.id, m.sender_id = official_id('support'), m.content, m.type, m.created_at
    from messages m where m.conversation_id = dm and m.deleted_at is null
    order by m.created_at desc limit 200;
end; $$;

-- تعليق حساب المبلَّغ عنه (بمبرر)
create or replace function public.shield_admin_suspend(p_case uuid, p_suspend boolean, p_reason text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare t uuid;
begin
  perform _shield_admin();
  perform _shield_need_reason(p_reason);
  select target_user into t from shield_cases where id = p_case;
  if t is null then raise exception 'no target'; end if;
  if exists (select 1 from app_admins where user_id = t) or exists (select 1 from profiles where id = t and is_official) then
    raise exception 'protected';
  end if;
  update auth.users set banned_until = case when p_suspend then 'infinity'::timestamptz else null end where id = t;
  if p_suspend then
    delete from auth.sessions where user_id = t;
    delete from auth.refresh_tokens where user_id::uuid = t;
  end if;
  update shield_cases set status = case when status = 'new' or status = 'reviewing' then 'action_taken' else status end,
         updated_at = now() where id = p_case;
  perform _shield_log(p_case, case when p_suspend then 'target_suspended' else 'target_unsuspended' end, t::text, p_reason);
end; $$;

-- منع المبلَّغ عنه من إرسال أي وسائط
create or replace function public.shield_admin_restrict_media(p_case uuid, p_restrict boolean, p_reason text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare t uuid;
begin
  perform _shield_admin();
  perform _shield_need_reason(p_reason);
  select target_user into t from shield_cases where id = p_case;
  if t is null then raise exception 'no target'; end if;
  if p_restrict then
    insert into shield_restrictions (user_id, no_media, case_id) values (t, true, p_case)
    on conflict (user_id) do update set no_media = true, until_at = null, case_id = p_case;
  else
    delete from shield_restrictions where user_id = t;
  end if;
  perform _shield_log(p_case, case when p_restrict then 'media_restricted' else 'media_unrestricted' end, t::text, p_reason);
end; $$;

-- قائمة وسائط المحادثة المبلَّغ عنها التي أرسلها المبلَّغ عنه (لتحويلها للحجر عبر shield-admin)
create or replace function public.shield_admin_case_media(p_case uuid)
returns table (message_id uuid, media_url text, type text, created_at timestamptz, quarantined boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
declare c shield_cases;
begin
  perform _shield_admin();
  select * into c from shield_cases where id = p_case;
  if c.id is null then raise exception 'not found'; end if;
  return query select m.id, m.media_url, m.type, m.created_at, m.shield_removed
    from messages m
    where m.conversation_id = c.conversation_id and m.sender_id = c.target_user
      and m.media_url is not null
    order by m.created_at desc limit 500;
end; $$;

-- سجل التدقيق + التحقق من سلامة السلسلة
create or replace function public.shield_admin_audit(p_case uuid default null)
returns table (seq bigint, at timestamptz, actor_name text, action text, target text, reason text, details jsonb)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform _shield_admin();
  return query select a.seq, a.at, coalesce(p.display_name, p.username, 'النظام'), a.action, a.target, a.reason, a.details
    from shield_audit a left join profiles p on p.id = a.actor
    where p_case is null or a.case_id = p_case
    order by a.seq desc limit 500;
end; $$;

create or replace function public.shield_admin_verify_audit()
returns json language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; prev text := 'GENESIS'; calc text; n bigint := 0;
begin
  perform _shield_admin();
  for r in select * from shield_audit order by seq loop
    calc := encode(extensions.digest(
      prev || '|' || r.at::text || '|' || coalesce(r.actor::text, '') || '|' ||
      coalesce(r.case_id::text, '') || '|' || r.action || '|' || coalesce(r.target, '') || '|' ||
      coalesce(r.reason, '') || '|' || r.details::text, 'sha256'), 'hex');
    if r.prev_hash <> prev or r.hash <> calc then
      return json_build_object('ok', false, 'broken_at', r.seq, 'checked', n);
    end if;
    prev := r.hash; n := n + 1;
  end loop;
  return json_build_object('ok', true, 'checked', n);
end; $$;

-- ============ 11) دوال للخدمة فقط (shield-admin) ============
-- يستدعيها shield-admin بصلاحية الخدمة بعد التحقق من أن المستدعي مدير؛ تمرير هوية المدير صراحة.
create or replace function public.shield_service_mark_quarantined(p_actor uuid, p_case uuid, p_message uuid,
                                                                 p_original text, p_qpath text, p_reason text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from app_admins where user_id = p_actor) then raise exception 'not_admin'; end if;
  insert into shield_quarantine (case_id, original_path, quarantine_path, message_id)
  values (p_case, p_original, p_qpath, p_message);
  update messages set shield_removed = true where id = p_message;
  insert into shield_audit (actor, case_id, action, target, reason, details, prev_hash, hash)
  values (p_actor, p_case, 'media_quarantined', p_original, p_reason,
          jsonb_build_object('quarantine_path', p_qpath, 'message', p_message), '', '');
  update shield_cases set status = case when status in ('new', 'reviewing') then 'action_taken' else status end,
         updated_at = now() where id = p_case;
end; $$;

-- تنظيف الاحتفاظ: يعيد مسارات الأدلة للحالات المغلقة المنتهية (يحذفها shield-admin من التخزين)
create or replace function public.shield_service_expired()
returns table (case_id uuid, path text, bucket text)
language sql stable security definer set search_path = public, extensions as $$
  select e.case_id, e.storage_path, 'shield-evidence' from shield_evidence e
    join shield_cases c on c.id = e.case_id
    where c.status = 'closed' and c.retain_until is not null and c.retain_until < now()
  union all
  select q.case_id, q.quarantine_path, 'shield-quarantine' from shield_quarantine q
    join shield_cases c on c.id = q.case_id
    where c.status = 'closed' and c.retain_until is not null and c.retain_until < now();
$$;

create or replace function public.shield_service_purge_case(p_case uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from shield_cases where id = p_case and status = 'closed'
                 and retain_until is not null and retain_until < now()) then
    raise exception 'not expired';
  end if;
  insert into shield_audit (actor, case_id, action, target, reason, details, prev_hash, hash)
  values (null, p_case, 'retention_purged', null, 'سياسة الاحتفاظ 180 يوماً', '{}', '', '');
  delete from shield_cases where id = p_case;   -- الأدلة والحجر تُحذف بالتتابع؛ سجل التدقيق يبقى
end; $$;

-- ============ 12) الصلاحيات ============
do $$ declare f text; begin
  foreach f in array array[
    'public.shield_report(text, text, boolean, uuid, uuid, boolean)',
    'public.shield_add_evidence(uuid, text, text, text, bigint, text, uuid)',
    'public.shield_my_cases()',
    'public.shield_admin_cases(text)',
    'public.shield_admin_case(uuid)',
    'public.shield_admin_open_evidence(uuid)',
    'public.shield_admin_set_status(uuid, text, text)',
    'public.shield_admin_message_reporter(uuid, text)',
    'public.shield_admin_thread(uuid)',
    'public.shield_admin_suspend(uuid, boolean, text)',
    'public.shield_admin_restrict_media(uuid, boolean, text)',
    'public.shield_admin_case_media(uuid)',
    'public.shield_admin_audit(uuid)',
    'public.shield_admin_verify_audit()',
    'public.shield_can_read_evidence(text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  foreach f in array array[
    'public._shield_log(uuid, text, text, text, jsonb)',
    'public._shield_notify_admins(text)',
    'public._shield_support_dm(uuid)',
    'public.shield_service_mark_quarantined(uuid, uuid, uuid, text, text, text)',
    'public.shield_service_expired()',
    'public.shield_service_purge_case(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ============ 13) الاحتفاظ اليومي ============
do $$
declare src text; secret text;
begin
  select prosrc into src from pg_proc where proname = 'notify_push' limit 1;
  secret := substring(src from '''x-webhook-secret''\s*,\s*''([^'']+)''');
  if secret is null then raise notice 'webhook secret not found — retention cron skipped'; return; end if;
  begin perform cron.unschedule('wasl-shield-retention'); exception when others then null; end;
  perform cron.schedule('wasl-shield-retention', '17 3 * * *', format(
    $f$select net.http_post(url := 'https://hplzbillnbdjtufazrlp.supabase.co/functions/v1/shield-admin',
       headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', %L),
       body := '{"action":"retention"}'::jsonb)$f$, secret));
end $$;
