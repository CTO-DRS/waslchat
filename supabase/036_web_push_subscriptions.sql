-- وصل شات 0.28.0 (المرحلة 12 أ): اشتراكات إشعارات المتصفح — Web Push
-- شغّله في SQL Editor بعد 035_status_video_reply.sql
--
-- الفكرة: متصفح المستخدم يشترك في Push API (بمفتاح VAPID العام المضمّن
-- في التطبيق)، ويخزّن الاشتراك هنا — ثم دالة push الخادمية الممتدة ترسل
-- له مباشرة بنفس القرارات (الكتوم وجرس القنوات) وحمولة نص إشعار عام.
--
-- الصدق الأمني:
--   endpoint       : عنوان خدمة الدفع — يعرّف المتصفح لا المستخدم.
--   p256dh / auth  : مفاتيح تشفير الطرف الآخر للحمولة (RFC 8291) —
--                    لا تلمس محتوى الرسائل إطلاقاً؛ الخادم يرسل نصاً
--                    عاماً كما يفعل لأندرويد («🔒 رسالة مشفرة»).
--   ua             : وصف المتصفح للتشخيص — لا تخمين بلاه.
--   آخر رد فاشل    : آخر وقت فشل إرسال — التنظيف التلقائي يحذف اليتيم
--                    بعد 30 يوماً بpg_cron (النمط نفسه لتنظيف الوسائط).
--
-- الصلاحيات: صاحب الحساب يكتب اشتراكه ويحذفه حصراً (endpoint فريد)،
-- والدالة الخادمية تقرأ بservice_role خارج RLS كما يفعل لdevice_tokens.

create table if not exists public.web_push_subscriptions (
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null primary key,
  p256dh text not null check (length(p256dh) between 20 and 200),
  auth text not null check (length(auth) between 8 and 60),
  ua text,
  last_failed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.web_push_subscriptions enable row level security;

-- الكتابة والحذف لصاحب الحساب حصراً — endpoint فريداً فيُحدَّث بالتكرار
create policy "own web push insert"
  on public.web_push_subscriptions for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "own web push delete"
  on public.web_push_subscriptions for delete
  to authenticated
  using (auth.uid() = user_id);

-- قراءة صاحب الحساب لاشتراكاته (الإعدادات تعرض الحالة)
create policy "own web push select"
  on public.web_push_subscriptions for select
  to authenticated
  using (auth.uid() = user_id);

-- لا تحديث عميلي — الاشتراك يتغير بالحذف وإعادة الإدراج فتبقى الحالة بسيطة
create policy "no client update"
  on public.web_push_subscriptions for update
  to authenticated
  using (false);

create index if not exists web_push_subs_user_idx
  on public.web_push_subscriptions (user_id);

-- تنظيف الاشتراكات اليتيمة (فشل إرسالها 30 يوماً أو ترك المستخدم قبل 90 يوماً)
-- — نمط التنظيف اليومي القائم في 013_files_video_cleanup.sql
create or replace function public.cleanup_web_push_subs()
returns void language plpgsql security definer
set search_path = public as $$
begin
  delete from web_push_subscriptions
   where (last_failed_at is not null
          and last_failed_at < now() - interval '30 days')
      or (created_at < now() - interval '90 days'
          and last_failed_at is not null
          and last_failed_at < now() - interval '7 days');
end;
$$;

revoke all on function public.cleanup_web_push_subs() from public, anon;
