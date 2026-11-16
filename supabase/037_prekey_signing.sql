-- وصل شات v1.5.0+67 — المرحلة 15 أ: الأمان العميق والاستقلال
-- 037: توقيع المفاتيح الأولية Ed25519 — إغلاق البند الوحيد المفتوح في التقوية (E2EE_PLAN §9)
--
-- شغّله في SQL Editor بعد 036_web_push_subscriptions.sql.
--
-- الفكرة (نمط سيجنال): حتى اليوم يستطيع وسيطٌ خادمي (عطل أو صلاحية خاطئة أو يد
--   سوداء) أن يستبدل مفتاهاً أولياً عاماً بمفتاحيه فتبدأ جلسة جديدة نحوه — لا
--   يقرأ رسائل سابقة (DH1 مرتبط بهوية الجهاز) ولا ينتحل هوية كاملة (رمز الأمان
--   وQR يكشفانه)، لكنه يسبب فشل جلسات متكرراً (حرمان) وأزمة ثقة صامتة. هنا كل
--   جهاز يولد زوج توقيع Ed25519 وينشر عامه في devices (عمود signing_public_key)
--   ويوقّع كل مفتاح أولي يرفعه (عمود signature على e2e_prekeys)، والطرف المبادر
--   يتحقق التوقيع قبل قبول المفتاح — فلا استبدال صامت للمفاتيح الأولية.
--
-- المادة الموقَّعة (يجب أن تطابق المحرك النقي في التطبيق حرفياً):
--   payload = 'wasl-prekey-sig-v1' || bytes(prekey_public_key) || bytes(pq_public_key إن وجد)
--   والتوقيع Ed25519Pure بزوج توقيع الجهاز — 64 بايت (88 حرفاً b64).
--
-- توافق رجعي صادق (نمط الهجين الكمومي نفسه):
--   - مفاتيح ما قبل الترحيل بلا توقيع (null) → تُقبل كما هي اليوم.
--   - جهاز بلا مفتاح توقيع منشور (تطبيق قديم) → تُقبل كما هي اليوم.
--   - التحقق إلزامي فقط حين يتوفر التوقيع ومفتاح التوقيع معاً — وفشله يعني
--     عبثاً وسيطياً فيُهمل الجهاز في هذه الرسالة بلا هبوط كلاسيكي (استخدام
--     مفتاح معبوث أسوأ من فشل جلسة).
--
-- إصلاح كامن موثق: فرع «مخزون الحساب» (device_id null) في دالة 033 كان يقرأ
--   r.pq_public_key دون تسميته في SELECT INTO — خطأ تشغيلي كامن لا يُلمَس في
--   المسار الفعلي (استدعاء الواجهة ذو المعامل الواحد يذهب لدالة 020 القديمة)،
--   ويُصحَّح هنا بتسمية الأعمدة صراحة في SELECT INTO.

-- 1) عمود التوقيع على المفاتيح الأولية ----------------------------------------
-- Ed25519 توقيع = 64 بايت = 88 حرفاً b64. النطاق متسامح لحدود التحقق فقط.

alter table public.e2e_prekeys
  add column if not exists signature text;

do $$ begin
  alter table public.e2e_prekeys add constraint e2e_prekeys_signature_len_check
    check (signature is null or char_length(signature) between 80 and 100);
exception when duplicate_object then null; end $$;

-- 2) مفتاح التوقيع العام على الجهاز --------------------------------------------
-- مفتاح Ed25519 العام = 32 بايت = 44 حرفاً b64. ليس سراً — القراءة عامة كما
--   هي مفاتيح الهوية العامة، والتحقق يفعله أي طرف يبدأ جلسة نحو الجهاز.

alter table public.devices
  add column if not exists signing_public_key text;

do $$ begin
  alter table public.devices add constraint devices_signing_len_check
    check (signing_public_key is null or char_length(signing_public_key) between 40 and 48);
exception when duplicate_object then null; end $$;

-- 3) دالة السحب تعيد التوقيع — نفس دالة 033 حرفاً بحرف مع عمود إضافي -----------
-- التطبيقات القديمة تتجاهل العمود الجديد بالكامل (اختياري في الاستجابة).
-- فرع مخزون الحساب: الأعمدة الإضافية تُسمّى صراحة في SELECT INTO (إصلاح 033).

create or replace function public.e2e_claim_prekey(
  p_user_id uuid,
  p_device_id uuid default null
)
returns table (o_key_id bigint, o_public_key text, o_last_resort boolean,
               o_pq_public_key text, o_signature text)
language plpgsql security definer set search_path = public as $$
declare
  r record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  if p_device_id is null then
    -- المخزون القديم على مستوى الحساب (توافق v2) — بلا كمومي وبلا توقيع
    -- بالتصميم (لا جهاز ولا مفتاح توقيع له)، والأعمدة تُسمّى صراحة (إصلاح 033)
    select k.id, k.public_key,
           null::text as pq_public_key,
           null::text as signature
      into r
      from e2e_prekeys k
      where k.user_id = p_user_id and k.device_id is null
        and k.consumed_at is null and not k.is_last_resort
      order by k.id
      limit 1
      for update skip locked;

    if r.id is not null then
      update e2e_prekeys set consumed_at = now() where id = r.id;
      return query select r.id, r.public_key, false, r.pq_public_key, r.signature;
      return;
    end if;

    select k.id, k.public_key,
           null::text as pq_public_key,
           null::text as signature
      into r
      from e2e_prekeys k
      where k.user_id = p_user_id and k.device_id is null and k.is_last_resort
      order by k.id
      limit 1;

    if r.id is not null then
      return query select r.id, r.public_key, true, r.pq_public_key, r.signature;
    end if;
    return;
  end if;

  -- مخزون جهاز محدد (مسار v3) — مع المفتاح الكمومي المرافق والتوقيع
  select k.id, k.public_key, k.pq_public_key, k.signature into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.device_id = p_device_id
      and k.consumed_at is null and not k.is_last_resort
    order by k.id
    limit 1
    for update skip locked;

  if r.id is not null then
    update e2e_prekeys set consumed_at = now() where id = r.id;
    return query select r.id, r.public_key, false, r.pq_public_key, r.signature;
    return;
  end if;

  select k.id, k.public_key, k.pq_public_key, k.signature into r
    from e2e_prekeys k
    where k.user_id = p_user_id and k.device_id = p_device_id and k.is_last_resort
    order by k.id
    limit 1;

  if r.id is not null then
    return query select r.id, r.public_key, true, r.pq_public_key, r.signature;
  end if;
  -- لا صفوف: الجهاز لم ينشر مخزونه بعد → المرسل يتخطى هذا الجهاز في هذه الرسالة
end; $$;

revoke execute on function public.e2e_claim_prekey(uuid, uuid) from public, anon;
grant execute on function public.e2e_claim_prekey(uuid, uuid) to authenticated;

-- 4) التحققات -----------------------------------------------------------------
-- يجب أن يظهر هنا بعد التنفيذ:
--   select column_name from information_schema.columns
--     where table_name='e2e_prekeys' and column_name='signature';
--     (صف واحد)
--   select column_name from information_schema.columns
--     where table_name='devices' and column_name='signing_public_key';
--     (صف واحد)
--   select * from e2e_claim_prekey('<uuid حساب به جهاز مسجل>', '<uuid جهازه>');
--     (خمسة أعمدة — o_signature null لمفاتيح ما قبل الترحيل و88 حرفاً للجديدة
--      بعد رفع مخزون جديد من التطبيق المحدّث)
--   select provs.* from pg_constraint provs
--     where conname in ('e2e_prekeys_signature_len_check','devices_signing_len_check');
--     (قيدان)
-- وملاحظة النطاق: مفاتيح المخزون الحالي تبقى بلا توقيع (null) وتُقبل كما هي —
--   التوقيع يولد مع كل مخزون جديد يرفعه التطبيق المحدّث، ومفتاح توقيع الجهاز
--   يُنشر لحظة تسجيله أو أول تحديث بعده (صامت وناريَ ونسيان).

-- 5) دالة الإلحاح المطورة — النوع الخامس signing_publish ------------------------
-- نشر مفتاح توقيع جهاز حدث مفاتيح بمعناه: يغيّر ما يقبله الأطراف الذين يبدؤون
--   جلسات نحو هذا الجهاز، فيلحق بالسجل كسائر الأحداث — فأي نشر مكرر أو استبدال
--   مفتاح توقيع يظهر في «سجل مفاتيحي» كسلسلة تتحقق محلياً.

drop function if exists public.e2e_log_key_event(uuid, text, text, uuid);

create or replace function public.e2e_log_key_event(
  p_user_id uuid,
  p_kind text,
  p_fingerprint text default '',
  p_device_id uuid default null
)
returns void
language plpgsql security definer set search_path = public as $$
declare
  ph text;
begin
  if auth.uid() is null or auth.uid() <> p_user_id then
    raise exception 'not allowed';
  end if;
  if p_kind not in ('identity_publish','device_register','device_remove','key_reset','signing_publish') then
    raise exception 'bad kind';
  end if;

  select entry_hash into ph
    from e2e_key_log
    where user_id = p_user_id
    order by id desc
    limit 1;
  ph := coalesce(ph, '');

  insert into e2e_key_log (user_id, device_id, kind, fingerprint, prev_hash, entry_hash)
  values (
    p_user_id,
    p_device_id,
    p_kind,
    coalesce(p_fingerprint, ''),
    ph,
    encode(
      sha256(
        (coalesce(ph, '') || '|' || p_user_id::text || '|'
          || coalesce(p_device_id::text, '') || '|' || p_kind || '|'
          || coalesce(p_fingerprint, ''))::bytea
      ),
      'hex'
    )
  );
end; $$;

revoke execute on function public.e2e_log_key_event(uuid, text, text, uuid) from public, anon;
grant execute on function public.e2e_log_key_event(uuid, text, text, uuid) to authenticated;

do $$ begin
  alter table public.e2e_key_log drop constraint e2e_key_log_kind_check;
exception when undefined_object then null; end $$;

do $$ begin
  alter table public.e2e_key_log add constraint e2e_key_log_kind_check
    check (kind in ('identity_publish','device_register','device_remove','key_reset','signing_publish'));
exception when duplicate_object then null; end $$;
