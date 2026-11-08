-- وصل شات 0.4.0: روابط دعوة المجموعات + رمز QR للانضمام (المرحلة 1 — سد الفجوة مع واتساب)
-- شغّله في SQL Editor بعد 017_privacy_phase2.sql
--
-- الفكرة: المالك أو المشرف ينشئ رمزاً قصيراً لمجموعته (رابط نشط واحد لكل مجموعة)،
-- وينضم أي مستخدم مسجّل عبر group_join_by_invite — بلا رفع جهات اتصال ولا بيانات حساسة.
-- الجدول بلا سياسات RLS: لا أحد يقرأ الرموز مباشرة من الجدول، وكل الوصول عبر
-- دوال security definer تتحقق من الدور قبل أي شيء.

-- 1) جدول رموز الدعوة
create table if not exists public.group_invites (
  code text primary key,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  revoked boolean not null default false
);
create index if not exists group_invites_conv on public.group_invites (conversation_id);

alter table public.group_invites enable row level security;
-- (عمداً بلا سياسات: الجدول محجوب تماماً أمام العملاء)

-- 2) معاينة رمز الدعوة قبل الانضمام: اسم المجموعة وعدد أعضائها
--    (لا تكشف شيئاً غير العنوان والعدد — وليس للقنوات ولا لمجتمعات الغرف)
create or replace function public.group_invite_preview(p_code text)
returns table (title text, members bigint)
language sql security definer stable set search_path = public as $$
  select c.title,
         (select count(*) from conversation_participants cp
           where cp.conversation_id = c.id)
    from group_invites i
    join conversations c on c.id = i.conversation_id
   where i.code = upper(trim(p_code))
     and not i.revoked
     and c.is_group and c.kind = 'chat' and c.community_id is null;
$$;

-- 3) جلب الرمز النشط لمجموعة (المالك أو المشرف فقط) — null إن لم يوجد
create or replace function public.group_get_invite(p_conv uuid)
returns text
language plpgsql security definer stable set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'forbidden';
  end if;
  return (select code from group_invites
           where conversation_id = p_conv and not revoked
           order by created_at desc limit 1);
end; $$;

-- 4) إنشاء رمز جديد (المالك أو المشرف): يُبطل الرمز السابق أولاً — رابط واحد نشط
create or replace function public.group_create_invite(p_conv uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  r text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'forbidden';
  end if;

  update group_invites set revoked = true
   where conversation_id = p_conv and not revoked;

  -- 10 أحرف/أرقام كبيرة من UUID بلا شرطات، مع فحص التفرّد
  loop
    r := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from group_invites where code = r);
  end loop;

  insert into group_invites (code, conversation_id, created_by)
  values (r, p_conv, auth.uid());
  return r;
end; $$;

-- 5) إبطال الرمز النشط (المالك أو المشرف)
create or replace function public.group_revoke_invite(p_conv uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'forbidden';
  end if;
  update group_invites set revoked = true
   where conversation_id = p_conv and not revoked;
end; $$;

-- 6) الانضمام برمز الدعوة (أي مستخدم مسجّل) — يعيد معرّف المحادثة
--    الانضمام للمجموعات الخاصة معناه منح مفتاح التشفير: من انضم بهذه الطريقة
--    يظهر في شاشة معلومات المجموعة كعضو بلا مفتاح حتى يُدار مفتاح جديد
--    (نفس آلية needs_rekey الحالية عند إضافة الأعضاء يدوياً).
create or replace function public.group_join_by_invite(p_code text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select i.conversation_id into conv
    from group_invites i
    join conversations c on c.id = i.conversation_id
   where i.code = upper(trim(p_code))
     and not i.revoked
     and c.is_group and c.kind = 'chat' and c.community_id is null
   limit 1;
  if conv is null then raise exception 'invalid invite'; end if;

  -- عضو أصلاً؟ نعيد المعرّف بلا إدراج مكرر
  if exists (select 1 from conversation_participants
              where conversation_id = conv and user_id = auth.uid()) then
    return conv;
  end if;

  insert into conversation_participants (conversation_id, user_id, role)
  values (conv, auth.uid(), 'member');

  -- منح المفتاح للعضو الجديد يحتاج إعادة تدوير: نعلّم المجموعة كما تفعل
  -- إزالة/مغادرة الأعضاء في 009_group_admin.sql
  update conversations set needs_rekey = true where id = conv;

  return conv;
end; $$;

-- 7) الصلاحيات
grant execute on function public.group_invite_preview(text) to authenticated;
grant execute on function public.group_get_invite(uuid) to authenticated;
grant execute on function public.group_create_invite(uuid) to authenticated;
grant execute on function public.group_revoke_invite(uuid) to authenticated;
grant execute on function public.group_join_by_invite(text) to authenticated;
