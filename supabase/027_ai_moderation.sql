-- وصل شات 0.15.0: مساعد الإشراف الذكي الاختياري للمجتمعات العامة (المرحلة 3 — مجتمعات بمستوى ديسكورد)
-- شغّله في SQL Editor بعد 026_verification.sql. ثم انشر الدالة supabase/functions/moderation-ai (RUNBOOK §3.5).
--
-- الفكرة:
--   - مالك المجتمع أو مشرفوه يفعّلون «المساعد الذكي» اختيارياً (عمود ai_moderation على المجتمع).
--   - الفحص عند الطلب حصراً: المشرف يضغط «فحص آخر الرسائل» في شاشة الإشراف فتستدعي دالة
--     moderation-ai فتجلب آخر 120 رسالة نصية من غرف المجتمع (المجتمعات العامة نصوصها صريحة
--     على الخادم أصلاً بالتصميم) وترسلها إلى Gemini للتصنيف، وتخزّن الملاحظات في community_ai_flags.
--   - المساعد يقترح ولا ينفذ: لا كتم ولا طرد ولا حذف تلقائي — المشرف يرى الملاحظة (الرسالة
--     والمُرسل والسبب) ويقرر بإجراءات الإشراف القائمة (ترحيل 023) ثم يعيّن الملاحظة «مُعالَجة».
--   - المجتمعات الخاصة (غير العامة) لا يدعمه عمداً: رسائلها مشفّرة بين الطرفين والخادم
--     (ولا Gemini) لا يراها إطلاقاً — تفعيل المساعد عليها مرفوض من الخادم.
--
-- مبادئ التصميم (نمط 023/024):
--   - جدول الملاحظات للقراءة فقط عبر RLS لمشرفي المجتمع؛ لا سياسات كتابة للمستخدمين إطلاقاً —
--     الدالة moderation-ai تكتب بمفتاح service_role بعد التحقق من أن الطالب مشرف.
--   - ملاحظة واحدة لكل (رسالة، فئة) غير معالَجة — فهرس فريد جزئي يمنع التكرار،
--     وبعد معالجة الملاحظة يجوز ظهورها من فحص لاحق من جديد.
--   - بلا إشعارات ولا cron: الفحص عند الضغط فقط — صفر استهلاك للخادم والحصة المجانية ما لم يُطلب.

-- ============================================================
-- 1) عمود التفعيل الاختياري
-- ============================================================
alter table public.communities add column if not exists ai_moderation boolean not null default false;

-- ============================================================
-- 2) جدول الملاحظات
-- ============================================================
create table if not exists public.community_ai_flags (
  id uuid primary key default gen_random_uuid(),
  community_id uuid not null references public.communities(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid references public.messages(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('spam', 'abuse', 'scam', 'nsfw', 'danger')),
  severity text not null default 'low' check (severity in ('high', 'low')),
  reason text check (reason is null or char_length(reason) between 1 and 300),
  excerpt text check (excerpt is null or char_length(excerpt) between 1 and 200),
  triggered_by uuid references public.profiles(id) on delete set null,
  resolved boolean not null default false,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_action text check (resolved_action in ('ignored', 'muted', 'kicked', 'deleted', 'warned')),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists community_ai_flags_recent
  on public.community_ai_flags (community_id, resolved, created_at desc);
-- ملاحظة واحدة لكل (رسالة، فئة) ما دامت غير معالَجة — فحص لاحق قد يعيدها بعد المعالجة
create unique index if not exists community_ai_flags_unique
  on public.community_ai_flags (message_id, category)
  where message_id is not null and not resolved;

-- ============================================================
-- 3) RLS: القراءة لمشرفي المجتمع فقط — بلا أي كتابة للمستخدمين
--    (الدالة moderation-ai تكتب بمفتاح service_role بعد التحقق من الإشراف)
-- ============================================================
alter table public.community_ai_flags enable row level security;
drop policy if exists "ai flags read admins" on public.community_ai_flags;
create policy "ai flags read admins" on public.community_ai_flags
  for select to authenticated
  using (public.is_community_admin(community_id));

-- ============================================================
-- 4) التفعيل والإيقاف — لمشرفي المجتمع، وعلى المجتمعات العامة حصراً
-- ============================================================
create or replace function public.community_set_ai_moderation(cid uuid, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_community_admin(cid) then raise exception 'not allowed'; end if;
  if not exists (select 1 from communities where id = cid and is_public) then
    raise exception 'not public'; -- المجتمعات الخاصة مشفرة: المساعد لا يراها عمداً
  end if;
  update communities set ai_moderation = coalesce(p_enabled, false) where id = cid;
end; $$;

-- ============================================================
-- 5) قائمة الملاحظات — لمشرفي المجتمع، بالأسماء وأسماء الغرف ومن عالجها
-- ============================================================
create or replace function public.community_ai_flags_list(cid uuid)
returns table (
  id uuid, conversation_id uuid, message_id uuid, sender_id uuid,
  sender_name text, room_title text,
  category text, severity text, reason text, excerpt text,
  resolved boolean, resolved_by uuid, resolved_action text, resolved_by_name text,
  created_at timestamptz
) language sql security definer stable set search_path = public as $$
  select
    f.id, f.conversation_id, f.message_id, f.sender_id,
    coalesce(sp.display_name, sp.username, ''),
    coalesce(c.title, ''),
    f.category, f.severity, f.reason, f.excerpt,
    f.resolved, f.resolved_by, f.resolved_action,
    coalesce(rp.display_name, rp.username, ''),
    f.created_at
  from community_ai_flags f
  join profiles sp on sp.id = f.sender_id
  join conversations c on c.id = f.conversation_id
  left join profiles rp on rp.id = f.resolved_by
  where f.community_id = cid
    and public.is_community_admin(f.community_id)
  order by f.resolved, f.created_at desc
  limit 100;
$$;

-- ============================================================
-- 6) تعيين الملاحظة معالَجة — لمشرفي المجتمع (الإجراء نفسه ينفَّذ بأدوات 023 من التطبيق)
-- ============================================================
create or replace function public.community_ai_flag_resolve(fid uuid, p_action text)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); f record;
begin
  if me is null then raise exception 'not authenticated'; end if;
  select * into f from community_ai_flags where id = fid;
  if f.id is null then raise exception 'not found'; end if;
  if not public.is_community_admin(f.community_id) then raise exception 'not allowed'; end if;
  if coalesce(p_action, '') not in ('ignored', 'muted', 'kicked', 'deleted', 'warned') then
    raise exception 'bad action';
  end if;
  update community_ai_flags set
    resolved = true, resolved_by = me, resolved_action = p_action, resolved_at = now()
  where id = fid;
end; $$;

-- ============================================================
-- 7) صلاحيات التنفيذ: للمسجلين فقط (الدوال تتحقق من الإشراف بنفسها)
-- ============================================================
do $$
declare f text;
begin
  for f in select unnest(array[
    'public.community_set_ai_moderation(uuid, boolean)',
    'public.community_ai_flags_list(uuid)',
    'public.community_ai_flag_resolve(uuid, text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
