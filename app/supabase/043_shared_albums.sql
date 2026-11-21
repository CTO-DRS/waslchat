-- وصل شات v1.20.0+87 — المرحلة 22: استوديو الوسائط الموحد (الألبومات المشتركة)
-- 043: ألبومات مشتركة داخل الغرف المسموحة (المحرك النقي الثاني عشر wasl_mediastudio)
--
-- شغّله في SQL Editor بعد 042_mls_group_state.sql. لا نشر دوال خادمية جديدة:
-- الخادم وسيط شفاف يحمل مراجع القطع لا يفك محتواها (الوسائط مشفرة كما هي
-- اليوم)، وقواعد العضوية والترتيب نقيّة في التطبيق (shared_album_service.dart).
--
-- الفكرة الصادقة (بند 1.20.0 «ألبومات مشتركة داخل الغرف المسموحة»):
--   1) الغرف المسموحة = الجماعية حصراً (conversations.is_group = true) —
--      الخاصة أظرفتها ثنائية وألبومها المشترك فقاعة الوسائط القائمة.
--   2) لا صلاحية جديدة: من أضاف قطعة يملك إزالتها، ومنشئ الألبوم يملك
--      حذفه — نفس عُادة الصلاحيات في ترحيل 039 (الفاعل هو صاحب الفعل).
--   3) القطع مراجع لرسائل وسائط قائمة (بمعرّفها) لا نسخ محتوى — والحذف
--      من المحادثة يُسقط القطعة تلقائياً (on delete cascade).

-- ============================================================
-- جدول الألبومات المشتركة — صف لكل ألبوم داخل غرفة جماعية
-- ============================================================
create table if not exists public.shared_albums (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  title           text not null
    check (char_length(title) between 1 and 60),
  created_by      uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  -- الغرفة المسموحة جماعية حصراً — قاعدة البند موثقة على مستوى الخادم
  constraint shared_albums_group_only check (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and c.is_group = true))
);

alter table public.shared_albums enable row level security;

drop policy if exists "shared albums members select" on public.shared_albums;
create policy "shared albums members select" on public.shared_albums
  for select to authenticated
  using (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = shared_albums.conversation_id
      and m.user_id = auth.uid()));

drop policy if exists "shared albums members insert" on public.shared_albums;
create policy "shared albums members insert" on public.shared_albums
  for insert to authenticated
  with check (exists (
    select 1 from public.conversation_members m
    where m.conversation_id = shared_albums.conversation_id
      and m.user_id = auth.uid())
    and created_by = auth.uid());

drop policy if exists "shared albums creator update" on public.shared_albums;
create policy "shared albums creator update" on public.shared_albums
  for update to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

drop policy if exists "shared albums creator delete" on public.shared_albums;
create policy "shared albums creator delete" on public.shared_albums
  for delete to authenticated
  using (created_by = auth.uid());

-- ============================================================
-- قطع الألبوم — مراجع رسائل وسائط قائمة بترتيب الإضافة
-- ============================================================
create table if not exists public.shared_album_items (
  album_id    uuid not null
    references public.shared_albums(id) on delete cascade,
  message_id  uuid not null
    references public.messages(id) on delete cascade,
  added_by    uuid not null references public.profiles(id) on delete cascade,
  added_at    timestamptz not null default now(),
  primary key (album_id, message_id)
);

alter table public.shared_album_items enable row level security;

drop policy if exists "shared album items members select" on public.shared_album_items;
create policy "shared album items members select" on public.shared_album_items
  for select to authenticated
  using (exists (
    select 1 from public.shared_albums a
    join public.conversation_members m on m.conversation_id = a.conversation_id
    where a.id = shared_album_items.album_id
      and m.user_id = auth.uid()));

drop policy if exists "shared album items members insert" on public.shared_album_items;
create policy "shared album items members insert" on public.shared_album_items
  for insert to authenticated
  with check (added_by = auth.uid() and exists (
    select 1 from public.shared_albums a
    join public.conversation_members m on m.conversation_id = a.conversation_id
    where a.id = shared_album_items.album_id
      and m.user_id = auth.uid()));

drop policy if exists "shared album items adder delete" on public.shared_album_items;
create policy "shared album items adder delete" on public.shared_album_items
  for delete to authenticated
  using (added_by = auth.uid());

create index if not exists shared_album_items_order
  on public.shared_album_items (album_id, added_at);

-- حد صادق موثق: لا قراءة خادمية لأي محتوى — مراجع حصراً، وواجهة الألبوم
-- المشترك (القوائم والإضافة من المعرض) هي إصدار التكامل التالي كما في
-- عُادة النواة ثم الواجهة في كل مرحلة.
