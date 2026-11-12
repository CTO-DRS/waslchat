-- وصل شات v0.8.0: السرية الأمامية (X3DH + Double Ratchet) للمحادثات الخاصة — المرحلة 2
-- شغّله في SQL Editor بعد 019_view_once.sql
--
-- الفكرة: بدل مفتاح المحادثة الثابت المشتق من مفتاحي الهوية فقط (v1)، ينشر كل حساب
--   مجموعة مفاتيح X25519 «لمرة واحدة» (Prekeys). من يبدأ محادثة يسحب واحداً عبر
--   e2e_claim_prekey (سحب ذري بمرة واحدة — FOR UPDATE SKIP LOCKED، يُعلَّم مستهلكاً
--   ولا يعاد أبدان)، يشتق سرّ X3DH بثلاث خطوات DH:
--     DH1 = X25519(هويتي، هوية الطرف)  — المصادقة (المفتاح المنشور وحده لا يكفي)
--     DH2 = X25519(زائدي المؤقت، هوية الطرف)
--     DH3 = X25519(زائدي المؤقت، المفتاح الأولي المسحوب)
--   ثم يدير الجلسة Double Ratchet محلياً: كل رسالة مفتاحها مشتق من سلسلة تتقدم،
--   وكل تبادل يُدوّر زوج DH — فسرقة مفتاح الهوية لاحقاً لا تكشف الرسائل السابقة
--   (سرّية تقدّمية) واستعادة الجلسة بعد اختراق توقف الأختراق (PCS تدريجي).
-- المفتاح الأولي «المستهلك آخر النهار» (is_last_resort) يبقى غير مستهلك ليستطيع
--   أي جهة جديدة بدء جلسة حتى لو نفد المخزون؛ لا يُعاد سحبه أكثر من مرة معلنة.
-- خصوصية: الجدول يحمل مفاتيح عامة فقط. المفاتيح الخاصة لا تغادر الجهاز أبداً.
-- توافق: من لا يملك prekeys (تطبيق قديم e2e_version = 1) يبقى على مسار v1 الثابت،
--   والمرسل يتجنب v2 تلقائياً إن لم ينشر الطرف الآخر مفاتيح أولية.

-- 1) عمود إصدار قدرات التشفير في الملف الشخصي -------------------------------
-- 1 = مسار v1 الثابت فقط، 2 = ينشر prekeys ويدعم v2 (يضبطه التطبيق عند النشر)

alter table public.profiles
  add column if not exists e2e_version int not null default 1;

do $$ begin
  alter table public.profiles add constraint profiles_e2e_version_check
    check (e2e_version between 1 and 9);
exception when duplicate_object then null; end $$;

-- 2) جدول المفاتيح الأولية ---------------------------------------------------
-- id ثابت صادر من التسلسل يُرسل داخل ترويسة أول رسالة ليعرف صاحبه أيّ خاص يستعمل.

create table if not exists public.e2e_prekeys (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  public_key text not null,
  is_last_resort boolean not null default false,
  created_at timestamptz not null default now(),
  consumed_at timestamptz
);

create index if not exists e2e_prekeys_user_idx
  on public.e2e_prekeys (user_id, consumed_at);

do $$ begin
  alter table public.e2e_prekeys add constraint e2e_prekeys_pub_check
    check (char_length(public_key) between 40 and 64);
exception when duplicate_object then null; end $$;

-- مفتاح ملاذ أخير واحد لكل حساب كحد أقصى (فهرس فريد جزئي)
create unique index if not exists e2e_prekeys_one_last_resort_uq
  on public.e2e_prekeys (user_id) where (is_last_resort);

alter table public.e2e_prekeys enable row level security;

-- القراءة لأي مستخدم مسجّل: المفاتيح عامة وليست سراً (مثل identity_public_key)
drop policy if exists "e2e prekeys read by authenticated" on public.e2e_prekeys;
create policy "e2e prekeys read by authenticated" on public.e2e_prekeys
  for select to authenticated
  using (true);

-- الكتابة والحذف لصاحبها فقط (النشر والتقليم من التطبيق مباشرة)
drop policy if exists "e2e prekeys insert own" on public.e2e_prekeys;
create policy "e2e prekeys insert own" on public.e2e_prekeys
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "e2e prekeys delete own" on public.e2e_prekeys;
create policy "e2e prekeys delete own" on public.e2e_prekeys
  for delete to authenticated
  using (user_id = auth.uid());

-- لا تحديث مباشر إطلاقاً: علَم الاستهلاك يتم حصراً عبر دالة السحب أدناه.

-- 3) RPC: سحب مفتاح أولي بشكل ذري -------------------------------------------
-- يعيد أول مفتاح غير مستهلك ويؤشره مستهلكاً في المعاملة ذاتها (لا يتكرر سحبه)،
-- وإن نفد المخزون أعاد مفتاح الملاذ الأخير دون إستهلاكه.
-- security definer لأن المستخدم لا يملك تعديل صفوف غيره حتى بفعل الدالة.

-- أسماء أعمدة الإرجاع مسبوقة بـ o_ لتفادي غموض المتغيرات مع أعمدة الجدول في plpgsql
create or replace function public.e2e_claim_prekey(p_user_id uuid)
returns table (o_key_id bigint, o_public_key text, o_last_resort boolean)
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select k.id, k.public_key into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.consumed_at is null and not k.is_last_resort
    order by k.id
    limit 1
    for update skip locked;

  if r.id is not null then
    update e2e_prekeys set consumed_at = now() where id = r.id;
    return query select r.id, r.public_key, false;
    return;
  end if;

  select k.id, k.public_key into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.is_last_resort
    order by k.id
    limit 1;

  if r.id is not null then
    return query select r.id, r.public_key, true;
  end if;
  -- لا صفوف: الطرف لم ينشر مفاتيح أولية بعد → يرجع المرسل لمسار v1
end; $$;

revoke execute on function public.e2e_claim_prekey(uuid) from public, anon;
grant execute on function public.e2e_claim_prekey(uuid) to authenticated;

-- 4) تنظيف دوري: مفاتيح مستهلكة أقدم من 30 يوماً -----------------------------
-- (pg_cron موجود أصلاً؛ لا نلمس صفوفاً غير المستهلكة.)

create extension if not exists pg_cron;

do $$ begin
  perform cron.schedule(
    'e2e_prekeys_cleanup', '0 4 * * *',
    $cron$ delete from public.e2e_prekeys where consumed_at is not null and consumed_at < now() - interval '30 days' $cron$
  );
exception when duplicate_object then null; end $$;
