-- وصل شات 0.1.9: إشعار «تحديث متوفر» + مهمة keep-alive يومية
-- شغّله بعد 015_webhook_secret_vault.sql

-- 1) إصدارات التطبيق: أضف سطراً هنا عند كل إصدار جديد (من لوحة Supabase أو SQL Editor)
--    مثال:
--    insert into app_releases (version_code, version_name, url, notes)
--    values (16, '0.1.9', 'https://github.com/CTO-DRS/wasl-chat/releases', 'الحظر والإبلاغ وتحسينات الأمان');
create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_code integer not null unique,
  version_name text not null,
  url text not null,
  notes text,
  created_at timestamptz not null default now()
);

alter table public.app_releases enable row level security;

create policy "releases readable" on public.app_releases
  for select to authenticated using (true);
-- الكتابة للمالك فقط: من لوحة Supabase (postgres يتجاوز RLS) — لا سياسات كتابة للعملاء.

-- يعيد أحدث إصدار أحدث من إصدار الجهاز (null إن كان محدّثاً)
create or replace function public.check_app_update(p_version_code integer)
returns table (version_code integer, version_name text, url text, notes text)
language sql security definer stable set search_path = public as $$
  select r.version_code, r.version_name, r.url, r.notes
  from app_releases r
  where r.version_code > coalesce(p_version_code, 0)
  order by r.version_code desc
  limit 1;
$$;

revoke execute on function public.check_app_update(integer) from public, anon;
grant execute on function public.check_app_update(integer) to authenticated;

-- 2) keep-alive: استعلام يومي بسيط يمنع إيقاف مشروع Supabase المجاني بسبب الخمول
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('wasl-keepalive');
exception when others then null; end $$;
select cron.schedule('wasl-keepalive', '17 4 * * *', 'select 1');
