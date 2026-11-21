-- وصل شات v1.6.0+68 — المرحلة 15 ب: الأمان العميق (الجانب الثاني)
-- 038: شهود خارجيون لشفافية المفاتيح — إغلاق الحد البنيوي F7 الموثق منذ 0.25.0
--
-- شغّله في SQL Editor بعد 037_prekey_signing.sql.
--
-- الفكرة: سجل الشفافية الإلحاحي (034) مُستضاف على خادم وصل نفسه — من يستطيع
--   إعادة كتابة القاعدة كلها يستطيع نظرياً بناء سلسلة كاذبة متسقة تتحقق
--   محلياً عند كل مستخدم وحده (موثق بصدق في §8-هـ وSECURITY F7). الشاهد
--   الخارجي يغلق هذا: أي طرف — مالك التطبيق أو غيره — يشغّل أداة مراقبة
--   مفتوحة المصدر (`tools/key_transparency_witness.py`) تقرأ لقطة دورية من
--   الدالتين الخادمتين أدناه وتنشرها في سجل إلحاحي عام (فرع witness-log في
--   المستودع العام مثلاً). لو أُعيدت كتابة التاريخ على الخادم فتتغير اللقطات
--   المنشورة قديماً عن الجديدة ويكشف الانتهاك أمام الجميع — لا ثقة بوعد.
--
-- ما تراه الدالتان وما لا تراه (الحدود المعلنة):
--   - بصمة عمياء لكل حساب: sha256('wt1|' || user_id || '|' || رأس السلسلة)
--     — لا معرّفات ولا بصمات مفاتيح ولا تواريخ مفردة، ومن غير صاحب الحساب
--     لا يستطيع ربط البصمة العمياء بمعرّفه (يعرف صاحبها فقط لأنه يعرف
--     uid ورأس سلسلته فيحسبها ويجدها في السجل المنشور).
--   - طول كل سلسلة ووقت آخر حدث — عدّ إجمالي لا محتوى.
--   - لا شيء غير ذلك: لا نصوص ولا مفاتيح ولا أجهزة ولا تواريخ أحداث مفردة.
--
-- الصيغة الصارمة (يجب أن تطابق محرك التحقق النقي في التطبيق حرفياً):
--   blind_digest   = sha256_hex( 'wt1|' || user_id::text || '|' || head_hash )
--   snapshot_digest= sha256_hex( string_agg(blind_digest, '\n' order by blind_digest) )
--   والسجل الفارغ كلها: بصمة السلسلة الفارغة الثابتة sha256('') بلا حالة خاصة.

-- 1) لقطة الشهود: بصمة عمياء لرأس سلسلة كل حساب بطولها ووقت آخر حدث ----------
create or replace function public.key_log_witness_heads()
returns table (blind_digest text, chain_len bigint, last_event_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select
    encode(extensions.digest('wt1|' || u.uid::text || '|' || u.head, 'sha256'), 'hex') as blind_digest,
    c.len as chain_len,
    u.last_at as last_event_at
  from (
    select distinct on (l.user_id)
      l.user_id as uid,
      l.entry_hash as head,
      l.created_at as last_at
    from public.e2e_key_log l
    order by l.user_id, l.id desc
  ) u
  join (
    select l.user_id as uid, count(*) as len
    from public.e2e_key_log l
    group by l.user_id
  ) c on c.uid = u.uid
  order by 1
$$;

-- 2) بصمة اللقطة الكلية — تجزئة البصمات العمياء مرتبة فلا ترتيب يُعبث به -----
create or replace function public.key_log_witness_digest()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    encode(
      extensions.digest(
        (select string_agg(h.blind_digest, chr(10) order by h.blind_digest)
         from public.key_log_witness_heads() h),
        'sha256'),
      'hex'),
    '')
$$;

-- 3) الصلاحيات: قراءة للجميع (anon وauthenticated) حصراً — لا كتابة إطلاقاً ---
--   والدالتان security definer تقرآن السجل خلف RLS ولا تكشفان سوى البصمات
--   العمياء والأعداد — وهذا كل غرضهما، فالمنفذ المجهول يرى ما يعلنه الشاهد.
revoke all on function public.key_log_witness_heads() from public;
revoke all on function public.key_log_witness_digest() from public;
grant execute on function public.key_log_witness_heads() to anon, authenticated;
grant execute on function public.key_log_witness_digest() to anon, authenticated;

-- 4) تحقيقات الإلزام — شغّلها بعد الترحيل وتحقق بالنتائج -----------------------
--
--   أ) لا كتابة جديدة إطلاقاً: الجدول وسياساته كما هي من 034 حرفياً —
--      select count(*) from pg_policies where tablename='e2e_key_log';
--      صف واحد (قراءة لصاحبه حصراً) — لا سياسة كتابة عميلية سُيئست.
--
--   ب) الدالتان موجودتان بمنفذيها:
--      select count(*) from pg_proc
--        where proname in ('key_log_witness_heads','key_log_witness_digest');
--      يجب أن يعيد 2.
--
--   ج) من SQL Editor أنت أنت (auth.uid() = صاحب حسابك):
--      select * from key_log_witness_heads() limit 3;
--      select key_log_witness_digest();
--      يعملان ويعيدان بصمات عمياء بطول 64 وقيمة كلية — بلا أي معرّف خام.
--
--   د) تطابق الصيغة مع التطبيق: احسب يدوياً بصمتك العمياء من «سجل مفاتيحي»
--      (الشاشة تعرضها) وقارنها بصفّك في key_log_witness_heads() — يجب أن
--      يتطابقا حرفياً (المحرك النقي موثق بمتجهات ثابتة محسوبة خارجياً).
--
--   هـ) من مجهول (نافذة متصفح غير مسجل عبر anon key):
--      curl -s "$SUPABASE_URL/rest/v1/rpc/key_log_witness_heads" \
--           -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY"
--      يعيد اللقطة نفسها — هذا ما ينشره الشاهد، بلا أي معلومة صاحبها.
