-- وصل شات v0.9.0: تعدد الأجهزة المرتبطة بمفاتيح لكل جهاز — المرحلة 2
-- شغّله في SQL Editor بعد 020_e2e_prekeys.sql
--
-- الفكرة: حتى الآن كان لكل حساب مفتاح هوية واحد ومخزون مفاتيح أولية واحد، فجهازان
--   لنفس الحساب يتشاركان مصير الجلسة (جلسة لكل حساب لا لكل جهاز). هنا يسجّل كل جهاز
--   نفسه في جدول devices بهوية X25519 خاصّة به ومخزون مفاتيح أولية خاصّ به، فيصبح:
--   - المرسل يغلّف مفتاح محتوى الرسالة لكل جهاز من أجهزة الطرف بجلسة متدرجة مستقلة.
--   - ويغلّفه أيضاً لأجهزة حسابه الأخرى (تغليف ذاتي) فتقرأ أجهزتها رسائله.
--   - والرسالة الواحدة تحمل كل الأظرفة في ترويسة v3 واحدة (صف واحد في messages).
-- خصوصية: جدول devices يحمل مفاتيح عامة فقط. الخاصة لا تغادر الجهاز أبداً.
-- توافق: e2e_version = 3 يعني «انشر أجهزتي وادعمني v3». التطبيق القديم يقرأ >= 2
--   فيبقى على مسار v2 (الهوية والمفاتيح الأولية على مستوى الحساب تعمل كما هي)،
--   والذين على v1 يبقى لهم المسار الثابت — لا انقطاع لأي طرف.

-- 1) جدول الأجهزة المرتبطة ---------------------------------------------------
-- id يولّده التطبيق (uuid v4) ويُحفظ محلياً في المخزن الآمن حتى يكون التسجيل
--   idempotent عبر إعادة تسجيل الدخول على الجهاز نفسه.

create table if not exists public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null default '',
  platform text not null default '',
  identity_public_key text not null,
  key_fp text not null default '',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz
);

create index if not exists devices_user_idx
  on public.devices (user_id, revoked_at);

do $$ begin
  alter table public.devices add constraint devices_pub_check
    check (char_length(identity_public_key) between 40 and 64);
exception when duplicate_object then null; end $$;

alter table public.devices enable row level security;

-- القراءة لأي مستخدم مسجّل: مفاتيح الأجهزة عامة وليست سراً (كidentity_public_key)
drop policy if exists "devices read by authenticated" on public.devices;
create policy "devices read by authenticated" on public.devices
  for select to authenticated
  using (true);

-- الكتابة والتحديث والحذف لصاحب الحساب فقط
drop policy if exists "devices insert own" on public.devices;
create policy "devices insert own" on public.devices
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "devices update own" on public.devices;
create policy "devices update own" on public.devices
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "devices delete own" on public.devices;
create policy "devices delete own" on public.devices
  for delete to authenticated
  using (user_id = auth.uid());

-- 2) مفاتيح أولية لكل جهاز ----------------------------------------------------
-- device_id فارغ = مخزون الحساب القديم (مسار v2 للنسخ القديمة — يعمل كما هو).
-- حذف جهاز يسحب مخزونه تلقائياً (on delete cascade).

alter table public.e2e_prekeys
  add column if not exists device_id uuid references public.devices(id) on delete cascade;

create index if not exists e2e_prekeys_device_idx
  on public.e2e_prekeys (device_id, consumed_at);

-- مفتاح ملاذ أخير واحد: واحد لمخزون الحساب القديم (بلا جهاز) وواحد لكل جهاز
-- (فهرس 020 القديم كان لكل حساب على كل الصفوف — كان سيمنع ملاذ الجهاز إن وُجد
--  ملاذ حساب، أو يفقد قيده مع صفوف NULL بعد تقسيمه)
drop index if exists e2e_prekeys_one_last_resort_uq;

create unique index if not exists e2e_prekeys_one_last_resort_account_uq
  on public.e2e_prekeys (user_id) where (is_last_resort and device_id is null);

create unique index if not exists e2e_prekeys_one_last_resort_device_uq
  on public.e2e_prekeys (device_id) where (is_last_resort and device_id is not null);

-- 3) سحب مفتاح أولي: من مخزون جهاز بعينه أو من مخزون الحساب القديم ------------
-- p_device_id فارغ → السلوك القديم حرفياً (الصفوف بلا جهاز) للنسخ السابقة.
-- p_device_id محدد → مخزون ذلك الجهاز فقط، والجهاز المُبطل لا يُسحب منه.

create or replace function public.e2e_claim_prekey(
  p_user_id uuid,
  p_device_id uuid default null
)
returns table (o_key_id bigint, o_public_key text, o_last_resort boolean)
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  if p_device_id is null then
    -- المخزون القديم على مستوى الحساب (توافق v2)
    select k.id, k.public_key into r
      from e2e_prekeys k
      where k.user_id = p_user_id and k.device_id is null
        and k.consumed_at is null and not k.is_last_resort
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
      where k.user_id = p_user_id and k.device_id is null and k.is_last_resort
      order by k.id
      limit 1;

    if r.id is not null then
      return query select r.id, r.public_key, true;
    end if;
    return;
  end if;

  -- مخزون جهاز محدد (مسار v3)
  select k.id, k.public_key into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.device_id = p_device_id
      and k.consumed_at is null and not k.is_last_resort
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
    where k.user_id = p_user_id and k.device_id = p_device_id and k.is_last_resort
    order by k.id
    limit 1;

  if r.id is not null then
    return query select r.id, r.public_key, true;
  end if;
  -- لا صفوف: الجهاز لم ينشر مخزونه بعد → المرسل يتخطى هذا الجهاز في هذه الرسالة
end; $$;

revoke execute on function public.e2e_claim_prekey(uuid, uuid) from public, anon;
grant execute on function public.e2e_claim_prekey(uuid, uuid) to authenticated;

-- 4) التحققات -----------------------------------------------------------------
-- يجب أن يظهر هنا بعد التنفيذ:
--   select * from devices limit 1;                          (الجدول موجود)
--   select e2e_claim_prekey('<uuid طرف>');                  (سحب الحساب القديم)
--   select e2e_claim_prekey('<uuid طرف>', '<uuid جهاز>');   (سحب مخزون جهاز)
