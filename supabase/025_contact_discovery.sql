-- وصل شات 0.4.7: اكتشاف الأصدقاء من جهات الاتصال (بند المرحلة 1)
-- شغّله في SQL Editor بعد 024_location_contact.sql
--
-- التصميم الصادق (الخصوصية أولاً):
-- - أرقام دفتر عناوين المستخدم تُجزَّأ SHA-256 على جهازه بملح نطاق ثابت
--   ("wasl-cd-v1:") ولا تُرفع أرقام خام إطلاقاً، وتُرسل للخادم لحظة
--   الاكتشاف فقط داخل استدعاء واحد للمقارنة ثم تُهمل — لا جدول تخزين
--   لتجزئات دفتر العناوين إطلاقاً.
-- - الجدول الوحيد المُخزَّن: الرقم الذي يُصرّح به المستخدم ليُكتشف
--   (تجزئة فقط، اختياري صريح، وحذفه يعيده للخفاء فوراً).
-- - من لم يُصرّح برقمه لا يمكن لأحد اكتشافه — الافتراضي هو الخفاء.
-- - حدود معروفة وموثّقة في TRANSPARENCY §1: التجزئة بلا ملح لكل مستخدم
--   تسمح نظرياً بالسرد المسبق لمساحة أرقام صغيرة (نموذج التطبيقات
--   السائدة ذاته)؛ التخفيف هنا: لا تخزين، حدّ 5000 تجزئة لكل استدعاء،
--   والإقرار العلني بالحدّ.
-- - كل شيء على الجهاز، وflow الاكتشاف لا يلمس دالة الإشعارات push.

-- 1) جدول هوية الرقم المُصرّح به — صف واحد لكل مستخدم
create table if not exists public.discovery_identity (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone_hash text not null,
  updated_at timestamptz not null default now()
);

-- شكل التجزئة: 64 خانة hex صغيرة (sha256)
alter table public.discovery_identity
  add constraint discovery_identity_hash_shape
  check (phone_hash ~ '^[0-9a-f]{64}$');

alter table public.discovery_identity enable row level security;

-- كل مستخدم يدير صفه فقط — لا سياسة قراءة لغير المالك إطلاقاً
drop policy if exists discovery_identity_own on public.discovery_identity;
create policy discovery_identity_own on public.discovery_identity
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 2) دالة الاكتشاف: تقارن تجزئات الطلب بالهويات المُصرّح بها دون أي تخزين
--    - تستبعد المحظورين من الطرفين (014)
--    - تستبعد صاحب الطلب نفسه
--    - حدّ صارم: 5000 تجزئة لكل استدعاء، وأقصى 500 نتيجة
--    security definer لأنها تقرأ discovery_identity التي لا يقرؤها أحد،
--    ولا تكتب في أي شيء
create or replace function public.discover_contacts(hashes text[])
returns table (user_id uuid, username text, display_name text, avatar_url text)
language sql stable security definer set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar_url
  from public.discovery_identity di
  join public.profiles p on p.id = di.user_id
  where di.user_id <> auth.uid()
    and di.phone_hash = any(hashes)
    and coalesce(array_length(hashes, 1), 0) between 1 and 5000
    and not exists (
      select 1 from public.user_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = di.user_id)
         or (b.blocker_id = di.user_id and b.blocked_id = auth.uid()))
  limit 500;
$$;

-- الاكتشاف للمصادَقين فقط
revoke execute on function public.discover_contacts(text[]) from anon;
revoke execute on function public.discover_contacts(text[]) from public;
grant execute on function public.discover_contacts(text[]) to authenticated;
