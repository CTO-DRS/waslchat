-- وصل شات v0.25.0+56 — المرحلة 10: تشفير بلا منازع (الجانب الثاني)
-- 034: شفافية المفاتيح — سجل إلحاقي بسلسلة بصمات لكل تغيير مفاتيح الحساب
--
-- شغّله في SQL Editor بعد 033_pq_prekeys.sql.
--
-- الفكرة: حتى اليوم تغيّر مفتاح جهاز أو نشر مفتاح جديد حدث صامت — إن عبث
--   وسيطٌ خادمي (صلاحية خاطئة، عطل، يد سوداء) بمفتاح عام واستبدله، فالمستخدم
--   يكتشفه فقط عبر رمز الأمان/QR عند المقارنة اليدوية، ولا يرى التاريخ.
--   هنا سجل **إلحاقي** لكل حدث مفاتيح بصمةً وسلسلة تجزئة (chain hash): كل
--   صف يحمل تجزئة (تجزئة الصف السابق + بيانات الحدث) — أي تعديل أو حذف أو
--   إعادة ترتيب صف يكسر السلسلة، وشاشة «سجل مفاتيحي» تعيد حسابها محلياً.
--
-- الصيغة الصارمة (يجب أن تطابق محرك التحقق النقي في التطبيق حرفياً):
--   entry_hash = sha256_hex( prev_hash || '|' || user_id || '|' || device_id(أو '') || '|' || kind || '|' || fingerprint )
--   وأول صف: prev_hash = '' .
--
-- حدود صادقة موثقة في E2EE_PLAN §8-هـ وTRANSPARENCY: السجل مُستضاف ومتحقَّق
--   على الخادم نفسه — من يملك صلاحية إعادة كتابة القاعدة كلها يستطيع إعادة
--   بناء سلسلة كاذبة متسقة (شفافية حقيقية كاملة تحتاج شهوداً خارجيين يوقّعون
--   — تصميم مؤجل بعد 1.0). ما يمنعه السجل اليوم: أي عبث جزئي (حذف صف، تعديل
--   بصمة، إعادة ترتيب، استبدال تاريخي) يكشفه التطبيق محلياً بلا شبكة تحقق خارجية.

-- 1) امتداد التجزئة (sha256 داخل الدالة) -------------------------------------
create extension if not exists pgcrypto;

-- 2) جدول السجل — إلحاق فقط ---------------------------------------------------
create table if not exists public.e2e_key_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid,
  kind text not null,
  fingerprint text not null default '',
  prev_hash text not null default '',
  entry_hash text not null,
  created_at timestamptz not null default now(),
  constraint e2e_key_log_kind_check
    check (kind in ('identity_publish','device_register','device_remove','key_reset')),
  constraint e2e_key_log_hash_shape check (char_length(entry_hash) = 64)
);

create index if not exists e2e_key_log_user_idx
  on public.e2e_key_log (user_id, id);

alter table public.e2e_key_log enable row level security;

-- القراءة لصاحب الحساب حصراً — تاريخ مفاتيحك لا يراه غيرك
drop policy if exists "e2e_key_log read own" on public.e2e_key_log;
create policy "e2e_key_log read own" on public.e2e_key_log
  for select to authenticated
  using (user_id = auth.uid());

-- لا سياسة إدراج ولا تحديث ولا حذف للعميل إطلاقاً: الجدول إلحاقي بالتصميم،
--   والكتابة الوحيدة عبر الدالة الخادمية أدناه التي تحسب السلسلة بنفسها —
--   فلا يستطيع عميل حقن صف بتجزئة مزورة أو تعديل تاريخ.

-- 3) دالة الإلحاح — تحسب التجزئة من آخر صف وتضيف الجديد -----------------------
-- تحقق صارم: الطالب هو صاحب السجل حصراً، والنوع من الأربعة المعروفة حصراً.

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
  if p_kind not in ('identity_publish','device_register','device_remove','key_reset') then
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

-- 4) التحققات -----------------------------------------------------------------
-- يجب أن يظهر هنا بعد التنفيذ:
--   select * from information_schema.tables where table_name='e2e_key_log';
--     (الجدول موجود)
--   select proconfig, proname from pg_proc where proname='e2e_log_key_event';
--     (الدالة موجودة security definer)
--   -- سلوك الإلحاح (بعد استدعاءات حقيقية من التطبيق):
--   select id, kind, fingerprint, prev_hash, entry_hash from e2e_key_log
--     where user_id = auth.uid() order by id;
--     (أول صف prev_hash='' وكل صف prev_hash = entry_hash الصف السابق)
--   -- رفض عبث الصلاحيات:
--   insert into e2e_key_log (user_id, kind, entry_hash) values (auth.uid(), 'identity_publish', 'x');
--     (فشل — لا سياسة إدراج للعميل)
-- وملاحظة النطاق: pgcrypto إن كان مفعّلاً مسبقاً فالسطر الأول صامت، والسجل
--   يبدأ فارغاً ويمتلئ من لحظة الترحيل للأمام — التاريخ قبل 0.25.0 غير مسجّل
--   (موثق بصدق في الشاشة نفسها).
