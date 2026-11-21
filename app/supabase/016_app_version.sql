-- شاشة «تحديث متوفر» — جدول إصدارات التطبيق
-- الصق كاملاً في Supabase > SQL Editor ثم Run

create table if not exists public.app_versions (
  id int primary key generated always as identity,
  version text not null,           -- مثل '0.6.0'
  build int not null,              -- مثل 31
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.app_versions enable row level security;

create policy "app versions read all" on public.app_versions
  for select to authenticated using (true);

-- إضافة/تعديل الإصدارات للمشرفين فقط (من لوحة الإدارة أو SQL)
create policy "app versions admin insert" on public.app_versions
  for insert to authenticated with check (public.is_app_admin());
create policy "app versions admin update" on public.app_versions
  for update to authenticated using (public.is_app_admin());

-- آخر إصدار فعّال (أعلى رقم بناء)
create or replace function public.latest_app_version()
returns table (version text, build int, notes text)
language sql security definer stable set search_path = public as $$
  select v.version, v.build, v.notes
  from app_versions v
  where v.is_active
  order by v.build desc
  limit 1;
$$;

-- الإصدار الحالي عند كتابة الترحيل (شغّل الملف مرة واحدة؛ تكراره يضيف سطراً بلا ضرر)
insert into public.app_versions (version, build, notes)
values ('0.6.0', 31, 'الحظر والإبلاغ + توحيد الإصدارات ومزامنة الوثائق');
