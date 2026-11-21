-- وصل شات v1.19.0+86 — المرحلة 21: التوسعة الاجتماعية (MLS للجمعات الضخمة)
-- 042: جدول حالة MLS للمجموعات الكبيرة (نواة engines/mls النقية الحادية عشر)
--
-- شغّله في SQL Editor بعد 041_wasl_shield.sql. لا نشر دوال خادمية جديدة:
-- الخادم يبقى **وسيطاً شفافاً** كما وثق التصميم docs/MLS_DESIGN.md §2 —
-- يحمل لقطات الشجرة والكومتات الثنائية لا يفكها (لا مفتاح عنده ولا صلاحية
-- جديدة)، والتنبيه عبر قناة Realtime القائمة.
--
-- الفكرة الصادقة (ترحيل مرقّم كما يطلب 1.19.0):
--   1) حالة المجموعة (شجرة/عهد/آخر كومت) تُخزن مشفرة على أجهزة الأعضاء،
--      وهذا الجدول نسخة تنسيق للمزامنة فقط: لقطة شجرة عامة (مفاتيح عامة
--      حصراً) وآخر كومت موقّع — ما يكفي لعضو عاد من الغياب يعيد بناء حالته
--      عبر applyCommit. بلا أسرار خاصة هنا أبداً: ما لا يفكه الخادم لا
--      يخزنه بأي شكل.
--   2) السياسات بفحص عضوية المحادثة القائم نفسه — من ليس عضواً لا يرى
--      ولا حتى وجود الحالة.
--   3) التفعيل التدريجي كما في التصميم §5: مجموعات جديدة كبيرة حصراً
--      في هذه المرحلة، والمجموعات الصغيرة تبقى على المسار المغلف.

-- ============================================================
-- جدول حالة MLS — صف لكل مجموعة كبيرة، يقرأه ويكتبه أعضاؤها حصراً
-- ============================================================
create table if not exists public.mls_group_state (
  conversation_id uuid primary key
    references public.conversations(id) on delete cascade,
  epoch           integer not null default 0
    check (epoch >= 0),
  -- لقطة الشجرة العامة: مفاتيح X25519 عامة وأوراق غير مدمجة فقط
  tree_snapshot   jsonb not null default '{}'::jsonb,
  -- آخر كومت موقّع تسلسلياً (JSON داخلي للنواة — لا صيغة أسلاك رسمية بعد)
  last_commit     jsonb,
  updated_by      uuid references public.profiles(id) on delete set null,
  updated_at      timestamptz not null default now()
);

alter table public.mls_group_state enable row level security;

drop policy if exists "mls state members select" on public.mls_group_state;
create policy "mls state members select" on public.mls_group_state
  for select to authenticated
  using (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = mls_group_state.conversation_id
      and m.user_id = auth.uid()));

drop policy if exists "mls state members insert" on public.mls_group_state;
create policy "mls state members insert" on public.mls_group_state
  for insert to authenticated
  with check (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = mls_group_state.conversation_id
      and m.user_id = auth.uid()));

drop policy if exists "mls state members update" on public.mls_group_state;
create policy "mls state members update" on public.mls_group_state
  for update to authenticated
  using (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = mls_group_state.conversation_id
      and m.user_id = auth.uid()))
  with check (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = mls_group_state.conversation_id
      and m.user_id = auth.uid()));

drop policy if exists "mls state members delete" on public.mls_group_state;
create policy "mls state members delete" on public.mls_group_state
  for delete to authenticated
  using (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = mls_group_state.conversation_id
      and m.user_id = auth.uid()));

create index if not exists mls_group_state_epoch
  on public.mls_group_state (conversation_id, epoch desc);

-- حد صادق موثق: لا دالة خادمية جديدة ولا قراءة أي محتوى من هذا الجدول
-- بأي مسار خادمي — التنفيذ الكامل (رسائل حمل mls) هو إصدار التكامل التالي
-- كما قدّر التصميم بنفسه («إصداران كاملان قبل أول مجموعة تعمل MLS حقيقياً»).
