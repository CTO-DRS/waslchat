-- وصل شات v0.4.2: الخصوصية الاختيارية — إخفاء «متصل الآن» وعلامات القراءة ✓✓
-- (بند المرحلة 1 من خارطة الطريق) — شغّله في SQL Editor بعد 019_stories.sql
--
-- التصميم الصادق:
-- 1) الإعداد نفسه سِر: جدول privacy_settings لا تقرؤه أي سياسة غير صاحبه،
--    فلا يعرف الطرف الآخر حتى أنك أخفيت شيئاً.
-- 2) فصلنا علامات القراءة (✓✓) عن عدّاد غير المقروء:
--    - conversation_participants.last_read_at يبقى لعدّاد غير المقروء الخاص بك (كما هو).
--    - read_receipts الجديد للعلامات ✓✓ فقط، وRLS يخفي صفوفك تماماً متى فعّلت الإخفاء.
-- 3) القاعدة المتبادلة تُفرض في التطبيق: من يخفي حالته لا يرى حالة الآخرين،
--    ومن يخفي علاماته لا يرى علامات الآخرين (نفس سلوك واتساب).
-- 4) الإخفاء لا يكشف التاريخ: mark_read يتوقف عن كتابة الإيصالات أثناء الإخفاء،
--    فإلغاء الإخفاء لاحقاً لا يكشف ما قُرئ في فترة الإخفاء.

-- 1) إعدادات الخصوصية (صف لكل مستخدم، محجوب تماماً عن غير صاحبه)
create table if not exists public.privacy_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  hide_presence boolean not null default false,
  hide_read_receipts boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.privacy_settings enable row level security;
create policy "privacy readable by owner" on public.privacy_settings
  for select to authenticated using (user_id = auth.uid());
create policy "privacy insert by owner" on public.privacy_settings
  for insert to authenticated with check (user_id = auth.uid());
create policy "privacy update by owner" on public.privacy_settings
  for update to authenticated using (user_id = auth.uid());

-- 2) إيصالات القراءة (✓✓) — جدول مستقل يمكن لـRLS إخفاؤه بالكامل
create table if not exists public.read_receipts (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  seen_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.read_receipts enable row level security;
create index if not exists read_receipts_conv on public.read_receipts (conversation_id);

-- هل يخفي هذا المستخدم علامات القراءة؟ (security definer: تفحص الإعداد
-- دون أن تكشفه للمستطلب — الاستعلام عنها بغير صلاحيات المالك آمن)
create or replace function public.hides_receipts(u uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select hide_read_receipts from privacy_settings where user_id = u), false);
$$;

-- الصف يراه صاحبه دائماً، ويراه أعضاء المحادثة فقط إن لم يخفِ صاحبه علاماته
create policy "receipts visible unless hidden" on public.read_receipts
  for select to authenticated
  using (
    user_id = auth.uid()
    or (public.is_member(conversation_id) and not public.hides_receipts(user_id))
  );

-- بثّ لحظي لعلامات القراءة (نفس نمط conversation_participants في 003)
do $$ begin
  alter publication supabase_realtime add table public.read_receipts;
exception when duplicate_object then null; end $$;

-- 3) mark_read الجديد: يحدّث عدّاد غير المقروء دائماً،
--    ويكتب إيصال القراءة فقط عندما لا يكون الإخفاء مفعّلاً
create or replace function public.mark_read(conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  hide boolean := false;
begin
  if uid is null then return; end if;
  update conversation_participants
     set last_read_at = now()
   where conversation_id = conv and user_id = uid;
  select coalesce(hide_read_receipts, false) into hide
    from privacy_settings where user_id = uid;
  if hide then return; end if;
  insert into read_receipts (conversation_id, user_id, seen_at)
  values (conv, uid, now())
  on conflict (conversation_id, user_id) do update set seen_at = excluded.seen_at;
end; $$;

-- 4) ترحيل الإيصالات القديمة: من اعتاد رؤية ✓✓ يبقى ماضيه كما هو
--    (الإخفاء يبدأ من لحظة تفعيله — لا يُمس التاريخ السابق)
insert into public.read_receipts (conversation_id, user_id, seen_at)
select conversation_id, user_id, last_read_at
from public.conversation_participants
where last_read_at is not null
on conflict (conversation_id, user_id) do nothing;
