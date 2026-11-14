-- وصل شات v0.24.0+55 — المرحلة 10: تشفير بلا منازع (الجانب الأول)
-- 033: مفاتيح ما بعد الكم لبدء جلسات هجينة + بث إزالة الأجهزة
--
-- شغّله في SQL Editor بعد 032_channel_bells.sql (الرقم 030 مُخطّ تاريخياً:
-- خارطة القمة خططته لشفافية المفاتيح ثم قفزته ترحيلات 031 و032 الفعلية،
-- فصُحّح الترقيم في GRAND_PLAN — شفافية المفاتيح ستكون 034).
--
-- الفكرة: بدء الجلسات اليوم X3DH كلاسيكي (X25519) — آمن ضد خصم اليوم، لكن
--   خصماً يمتلك حاسباً كمومياً مستقبلاً قد يفكّ DH ويستنتج مفاتيح الجلسات
--   المسجّلة اليوم (Harvest-now-decrypt-later). الحل القياسي (سيجنال PQXDH):
--   هجين يجمع سرّ X3DH الكلاسيكي مع سرّ ML-KEM (FIPS 203) في اشتقاق واحد —
--   فلا يكفي كسر أحدهما لاستنتاج المفتاح.
--
-- ما يفعله هذا الترحيل: عمودان على المفاتيح الأولية + دالة السحب تعيد المفتاح
--   الكمومي + بث لحظي لأحداث حذف الأجهزة (إزالة جهاز كاملة).
--
-- النطاق الكمومي: مخزون الأجهزة فقط (device_id ليس null — مسار v3). مخزون
--   الحساب القديم (device_id is null) للتوافق مع التطبيقات القديمة التي لا
--   تفكّ كمومياً أصلاً، فلا مفاتيح كمومية فيه بلا فائدة.
--
-- التوافق الصارم (معيار قبول المرحلة): المسار الكلاسيكي لا يتغير بايتاً واحداً —
--   من يبادر بلا مفاتيح كمومية عند الطرف يشتق SK بمسار info القديم نفسه،
--   ومن يبادر بها يضع نص التغليف في حقل q بالترويسة بمسار info مستقل،
--   والتطبيق القديم يبقى يعمل كلياً (راجع E2EE_PLAN §8-د).

-- 1) أعمدة ما بعد الكم على المفاتيح الأولية ---------------------------------
-- pq_public_key: مفتاح ML-KEM-768 العام (1184 بايت ≈ 1580 حرفاً b64).
-- pq_algo: اسم الخوارزمية للتوثيق المستقبلي (قيمة واحدة اليوم).

alter table public.e2e_prekeys
  add column if not exists pq_public_key text,
  add column if not exists pq_algo text not null default 'ml-kem-768';

do $$ begin
  alter table public.e2e_prekeys add constraint e2e_prekeys_pq_len_check
    check (pq_public_key is null or char_length(pq_public_key) between 1500 and 1700);
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.e2e_prekeys add constraint e2e_prekeys_pq_algo_check
    check (pq_algo in ('ml-kem-768'));
exception when duplicate_object then null; end $$;

-- 2) سحب مفتاح أولي يعيد المفتاح الكمومي المرافق ----------------------------
-- نفس دالة 021 حرفاً بحرف مع عمودين إضافيين في القراءة والعودة — التطبيقات
--   القديمة تتجاهل العمود الجديد بالكامل (اختياري في الاستجابة).

create or replace function public.e2e_claim_prekey(
  p_user_id uuid,
  p_device_id uuid default null
)
returns table (o_key_id bigint, o_public_key text, o_last_resort boolean, o_pq_public_key text)
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  if p_device_id is null then
    -- المخزون القديم على مستوى الحساب (توافق v2) — بلا كمومي بالتصميم
    select k.id, k.public_key, null::text into r
      from e2e_prekeys k
      where k.user_id = p_user_id and k.device_id is null
        and k.consumed_at is null and not k.is_last_resort
      order by k.id
      limit 1
      for update skip locked;

    if r.id is not null then
      update e2e_prekeys set consumed_at = now() where id = r.id;
      return query select r.id, r.public_key, false, r.pq_public_key;
      return;
    end if;

    select k.id, k.public_key, null::text into r
      from e2e_prekeys k
      where k.user_id = p_user_id and k.device_id is null and k.is_last_resort
      order by k.id
      limit 1;

    if r.id is not null then
      return query select r.id, r.public_key, true, r.pq_public_key;
    end if;
    return;
  end if;

  -- مخزون جهاز محدد (مسار v3) — مع المفتاح الكمومي المرافق إن وُجد
  select k.id, k.public_key, k.pq_public_key into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.device_id = p_device_id
      and k.consumed_at is null and not k.is_last_resort
    order by k.id
    limit 1
    for update skip locked;

  if r.id is not null then
    update e2e_prekeys set consumed_at = now() where id = r.id;
    return query select r.id, r.public_key, false, r.pq_public_key;
    return;
  end if;

  select k.id, k.public_key, k.pq_public_key into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.device_id = p_device_id and k.is_last_resort
    order by k.id
    limit 1;

  if r.id is not null then
    return query select r.id, r.public_key, true, r.pq_public_key;
  end if;
  -- لا صفوف: الجهاز لم ينشر مخزونه بعد → المرسل يتخطى هذا الجهاز في هذه الرسالة
end; $$;

revoke execute on function public.e2e_claim_prekey(uuid, uuid) from public, anon;
grant execute on function public.e2e_claim_prekey(uuid, uuid) to authenticated;

-- 3) بث لحظي لإزالة الأجهزة -------------------------------------------------
-- حدث DELETE على devices يبثّ لكل الأجهزة المصغية فتسقط الجلسات الميتة محلياً
-- (DeviceSecurityService). القراءة عامة أصلاً (المفاتيح العامة ليست سراً).

do $$ begin
  alter publication supabase_realtime add table public.devices;
exception when duplicate_object then null;
exception when undefined_object then null;
end $$;

-- 4) التحققات ---------------------------------------------------------------
-- يجب أن يظهر هنا بعد التنفيذ:
--   select column_name from information_schema.columns
--     where table_name='e2e_prekeys' and column_name in ('pq_public_key','pq_algo');
--     (عمودان)
--   select * from e2e_claim_prekey('<uuid حساب به جهاز مسجل>', '<uuid جهازه>');
--     (أعمدة o_key_id وo_public_key وo_last_resort وo_pq_public_key — الأخير
--      null لمفاتيح ما قبل الترحيل، و1580 حرفاً تقريباً للمفاتيح الجديدة)
--   select * from pg_publication_tables
--     where pubname='supabase_realtime' and tablename='devices';
--     (صف واحد)
--   select provs.* from pg_constraint provs
--     where conname in ('e2e_prekeys_pq_len_check','e2e_prekeys_pq_algo_check');
--     (قيدان)
-- وملاحظة النطاق: الصفوف القديمة تبقى pq_public_key = null وتُقرأ كلاسيكياً —
--   المفاتيح الكمومية تولد مع كل مخزون جديد يرفعه التطبيق المحدّث (25 + ملاذ أخير).
