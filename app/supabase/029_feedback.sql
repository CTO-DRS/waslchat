-- وصل شات 0.19.0: المرحلة 7 — برنامج المجرّبين: مجموعة الملاحظات داخل التطبيق
-- شغّله في SQL Editor بعد 028_calls.sql.
--
-- الفلسفة (مبدأ «الخصوصية قبل الميزة» و«لا وعود غير صادقة»):
-- - الملاحظة تصل نصاً صريحاً (غير مشفّرة بين الطرفين) — هذه طبيعة الملاحظة:
--   فريق وصل لا يستطيع قراءة ملاحظة لا يفكها، والملاحظة ليست محتوى محادثة.
--   الشاشة تقول ذلك للمستخدم نصاً قبل الإرسال: «لا تكتب في ملاحظتك محتوى
--   محادثاتك أو أسرارك» — صدق كامل بلا مفاجآت (TRANSPARENCY.md).
-- - ما يُرسل حصراً: نص الملاحظة + الفئة + إصدار التطبيق + اسم المنصة +
--   هوية حسابك (لأن رد المطور يحتاج معرفة مَن قال) — ولا شيء غير ذلك:
--   لا سجلات، لا لقطات شاشة، لا بيانات جهاز تفصيلية، لا عنوان IP مُخزَّناً هنا.
-- - القراءة: صاحب الملاحظة يقرأ ما أرسله، وإدارة التطبيق حصراً (is_app_admin
--   من ترحيل 014) — مالك مجتمع مهما كان دوره لا يرى ملاحظات أحد.
-- - الحذف: لا سياسة حذف لأي دور عبر الواجهة إطلاقاً — الملاحظة أثر مكتوب
--   يبقى (مثل سجل الإشراف)، والحذف اليدوي بيد الإدارة عبر SQL فقط.
-- - حد إغراق: 5 ملاحظات كحد أقصى في الساعة لكل مستخدم من الخادم نفسه —
--   لا يكفي أن تكون الواجهة مؤدبة.
-- - صفر دوال سحابية جديدة وصفر إشعارات: الملاحظة تُدرج بـRLS مباشرة،
--   وتراها الإدارة في لوحة إدارة الموقع (ترحيل 014) أو SQL — لا push ولا cron.

-- ============ 1) جدول ملاحظات المجرّبين ============

create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  category text not null default 'other' check (category in (
    'bug', 'idea', 'privacy', 'other')),
  body text not null check (char_length(btrim(body)) between 5 and 1500),
  app_version text not null check (char_length(app_version) <= 20),
  platform text not null check (char_length(platform) <= 20),
  status text not null default 'open' check (status in ('open', 'triaged', 'resolved')),
  admin_note text check (char_length(admin_note) <= 500),
  created_at timestamptz not null default now()
);
alter table public.app_feedback enable row level security;

create index if not exists app_feedback_status_idx
  on public.app_feedback (status, created_at desc);
create index if not exists app_feedback_user_idx
  on public.app_feedback (user_id, created_at desc);

-- الكتابة: صاحب الملاحظة يدرج صفه هو فقط — لا استبدال هوية ولا إدراج باسم غيرك
create policy "feedback insert own" on public.app_feedback
  for insert to authenticated
  with check (user_id = auth.uid());

-- القراءة: صاحب الملاحظة + إدارة التطبيق حصراً
create policy "feedback read own or admin" on public.app_feedback
  for select to authenticated
  using (user_id = auth.uid() or public.is_app_admin());

-- التحديث (status وadmin_note): إدارة التطبيق حصراً — ولا مستخدم يعدّل ملاحظته
create policy "feedback update admin" on public.app_feedback
  for update to authenticated
  using (public.is_app_admin())
  with check (public.is_app_admin());

-- لا سياسة حذف إطلاقاً عبر الواجهة — الملاحظة أثر مكتوب يبقى.

-- ============ 2) حد الإغراق: 5 ملاحظات في الساعة لكل مستخدم ============

create or replace function public.feedback_rate_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent integer;
begin
  select count(*) into recent
    from public.app_feedback f
    where f.user_id = new.user_id
      and f.created_at > now() - interval '1 hour';
  if recent >= 5 then
    raise exception 'FEEDBACK_RATE_LIMITED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_feedback_rate on public.app_feedback;
create trigger trg_feedback_rate
  before insert on public.app_feedback
  for each row execute function public.feedback_rate_guard();

-- ============ 3) تحققات ما بعد التشغيل (انسخها والصقها في SQL Editor) ============
-- select tablename, rowsecurity from pg_tables where tablename = 'app_feedback';
--   ← صف واحد بقيمة t
-- select tgname from pg_trigger where tgname = 'trg_feedback_rate';
--   ← صف واحد
-- select count(*) from pg_policies where tablename = 'app_feedback';
--   ← 3 (إدراج وقراءة وتحديث)
