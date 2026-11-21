-- وصل شات 0.1.3: تشفير المجموعات الخاصة بين الطرفين — المرحلة 2
-- شغّله في SQL Editor بعد 006_e2e_keys.sql
--
-- الفكرة: مفتاح مجموعة عشوائي (32 بايت) يبقى على أجهزة الأعضاء فقط.
-- يُغلَّف المفتاح لكل عضو بـ AES-256-GCM بمفتاح مشتق من
--   HKDF-SHA256( X25519(خاصي المُغلِّف، عامُ العضو), salt = conversation_id, info = 'wasl-group-v1' )
-- ويُخزَّن الظرف المغلَّف هنا. الخاص لا يغادر الجهاز أبداً، والسيرفر يرى أظرفةً مغلقة فقط.
--
-- الكتابة على الجدول تتم حصراً عبر دالتي RPC (تحقق من العضوية + قفل استشاري يمنع
-- سباق تثبيت مفتاحين مختلفين عند فتح المجموعة من جهازين معاً).
-- القراءة المباشرة مسموحة للأعضاء (الأظرفة مغلقة — لا فائدة لمن يقرؤها بلا مفاتيح خاصة).

-- 1) من أنشأ المجموعة؟ (لتحديد مَن يثبّت مفتاح المجموعة لأول مرة)
alter table public.conversations
  add column if not exists created_by uuid references public.profiles(id) on delete set null;

-- سدّ المجموعات القديمة: أول من انضم هو المؤسس
update public.conversations c
  set created_by = (
    select p.user_id from public.conversation_participants p
    where p.conversation_id = c.id
    order by p.joined_at, p.user_id
    limit 1
  )
  where c.created_by is null;

-- دالة إنشاء المجموعة: تسجّل المؤسس
create or replace function public.create_group_chat(p_title text, p_members uuid[])
returns uuid language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;

  insert into conversations (is_group, title, created_by)
  values (true, trim(p_title), auth.uid()) returning id into conv;

  insert into conversation_participants (conversation_id, user_id)
  select conv, s.u
  from (select unnest(p_members) as u union select auth.uid()) s
  where exists (select 1 from profiles p where p.id = s.u);

  return conv;
end; $$;

-- 2) جدول الأظرفة: ظرف واحد لكل (محادثة، عضو)
create table if not exists public.conversation_key_envelopes (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.profiles(id) on delete cascade,
  wrapped_by      uuid not null references public.profiles(id) on delete cascade,
  wrapped_key     text not null check (char_length(wrapped_key) between 20 and 700),
  created_at      timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

alter table public.conversation_key_envelopes enable row level security;

-- القراءة للأعضاء فقط (الأظرفة مغلقة — لا سرّ فيها)
drop policy if exists "envelopes read by members" on public.conversation_key_envelopes;
create policy "envelopes read by members" on public.conversation_key_envelopes
  for select to authenticated
  using (public.is_member(conversation_id));

-- لا سياسات كتابة مباشرة: الإضافة/التعديل عبر الدالتين أدناه فقط

-- 3) تثبيت مفتاح مجموعة (مرة واحدة فقط): المؤسس أول مرة. لا استبدال لمفتاح قائم.
--    يولّد التطبيق مفتاحاً جديداً ويغلفه لكل الأعضاء ثم يستدعي هذه الدالة.
--    القفل الاستشاري + فحص «ظرفي» داخل المعاملة يمنعان تثبيت مفتاحين متنافسين.
create or replace function public.e2e_set_group_key(
  p_conv uuid,
  p_envelopes jsonb  -- [{"user_id": "...", "wrapped_key": "v1...."}]
)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_conv) then raise exception 'not member'; end if;
  if p_envelopes is null or jsonb_typeof(p_envelopes) <> 'array'
     or jsonb_array_length(p_envelopes) = 0
     or jsonb_array_length(p_envelopes) > 500 then
    raise exception 'bad envelopes';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('e2e:' || p_conv::text, 7));

  -- إن وُجد أي ظرف فالمجموعة لها مفتاح: لا يُستبدل أبداً (ومتسابقٌ سبقنا هو الفائز).
  -- العضو بلا ظرف ينتظر عضواً يملك المفتاح ليغلّفه له عبر e2e_wrap_for_members.
  if exists (select 1 from conversation_key_envelopes
             where conversation_id = p_conv) then
    return;
  end if;
  -- التثبيت الأول للمؤسس فقط (أو أي عضو في مجموعة بلا مؤسس مسجّل)
  if exists (select 1 from conversations
             where id = p_conv and created_by is not null and created_by <> me) then
    raise exception 'only founder installs the first key';
  end if;

  insert into conversation_key_envelopes (conversation_id, user_id, wrapped_by, wrapped_key)
  select p_conv,
         (e->>'user_id')::uuid,
         me,
         e->>'wrapped_key'
  from jsonb_array_elements(p_envelopes) e
  where exists (select 1 from conversation_participants cp
                where cp.conversation_id = p_conv
                  and cp.user_id = (e->>'user_id')::uuid)
  on conflict (conversation_id, user_id) do nothing;
end; $$;

-- 4) تغليف إضافي: عضو يملك المفتاح يغلّفه لأعضاء بلا ظرف (انضمام لاحق / تقصّر سابق)
--    يكتب في الخانات الفارغة فقط — لا يستبدل أظرفة موجودة.
create or replace function public.e2e_wrap_for_members(
  p_conv uuid,
  p_envelopes jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'not authenticated'; end if;
  if not public.is_member(p_conv) then raise exception 'not member'; end if;
  -- لا بد أن أملك المفتاح أصلاً (ظرفي موجود) حتى أغلّفه لغيري
  if not exists (select 1 from conversation_key_envelopes
                 where conversation_id = p_conv and user_id = me) then
    raise exception 'no key held';
  end if;
  if p_envelopes is null or jsonb_typeof(p_envelopes) <> 'array'
     or jsonb_array_length(p_envelopes) = 0
     or jsonb_array_length(p_envelopes) > 500 then
    raise exception 'bad envelopes';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('e2e:' || p_conv::text, 7));

  insert into conversation_key_envelopes (conversation_id, user_id, wrapped_by, wrapped_key)
  select p_conv,
         (e->>'user_id')::uuid,
         me,
         e->>'wrapped_key'
  from jsonb_array_elements(p_envelopes) e
  where exists (select 1 from conversation_participants cp
                where cp.conversation_id = p_conv
                  and cp.user_id = (e->>'user_id')::uuid)
  on conflict (conversation_id, user_id) do nothing;
end; $$;

-- لا تنفيذ إلا لمستخدمين مسجلين
revoke execute on function public.e2e_set_group_key(uuid, jsonb) from public, anon;
revoke execute on function public.e2e_wrap_for_members(uuid, jsonb) from public, anon;
grant execute on function public.e2e_set_group_key(uuid, jsonb) to authenticated;
grant execute on function public.e2e_wrap_for_members(uuid, jsonb) to authenticated;
