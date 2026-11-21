-- وصل شات 0.6.0: روابط دعوة المجموعات الخاصة
-- شغّله في SQL Editor بعد 016_app_version.sql
--
-- - رمز دعوة واحد فعّال لكل مجموعة خاصة؛ إدارته (إنشاء/تجديد/تعطيل) للمشرفين فقط.
-- - الجدول نفسه مخفي بـ RLS عن الجميع عدا مشرفي المجموعة، والانضمام يمر عبر
--   دالة security definer تتحقق من الرمز دون كشف بيانات الدعوات للمستدعي.
-- - بعد الانضمام يصل مفتاح المجموعة للعضو الجديد تلقائياً بغلاف من أي عضو يملكه
--   (السلوك القائم: e2e_wrap_for_members — انظر 009_group_admin.sql).
-- - الرمز 10 أحرف من أبجدية بلا حروف ملتبسة (بلا 0/o/1/l/i) ≈ 30^10 احتمال.

-- 1) الجدول
create table if not exists public.group_invites (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  code text not null unique,
  created_by uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  revoked boolean not null default false,
  use_count integer not null default 0,
  max_uses integer check (max_uses is null or max_uses > 0),
  expires_at timestamptz,
  constraint group_invites_code_shape check (code ~ '^[a-z0-9]{10}$')
);
create index if not exists group_invites_conv_idx on public.group_invites(conversation_id);

alter table public.group_invites enable row level security;

-- 2) هل المستخدم مشرف في مجموعة خاصة؟ (دالة مشتركة)
create or replace function public.is_group_admin(p_conv uuid, p_user uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1
      from conversation_participants cp
      join conversations c on c.id = cp.conversation_id
     where cp.conversation_id = p_conv
       and cp.user_id = p_user
       and cp.role in ('owner', 'admin')
       and c.is_group and c.kind = 'chat' and c.community_id is null
  );
$$;

drop policy if exists "invites managed by group admins" on public.group_invites;
create policy "invites managed by group admins" on public.group_invites
  for all
  using (public.is_group_admin(conversation_id, auth.uid()))
  with check (public.is_group_admin(conversation_id, auth.uid()));

-- 3) إنشاء/تجديد دعوة المجموعة (يعطّل الرمز السابق ويعيد رمزاً جديداً)
create or replace function public.group_invite_create(p_conv uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_code text;
  i int;
begin
  if me is null then raise exception 'not authenticated'; end if;
  if coalesce(public.group_role(p_conv), '') not in ('owner', 'admin') then
    raise exception 'admins only';
  end if;

  update group_invites set revoked = true
   where conversation_id = p_conv and not revoked;

  for i in 1..5 loop
    v_code := (
      select string_agg(
               substr('abcdefghjkmnpqrstuvwxyz23456789', ceil(random() * 30)::int, 1),
               '')
        from generate_series(1, 10)
    );
    exit when not exists (select 1 from group_invites where code = v_code);
  end loop;

  insert into group_invites (conversation_id, code, created_by)
  values (p_conv, v_code, me);

  return v_code;
end $$;

-- 4) الانضمام برمز دعوة (يرجع معرف المحادثة، أو يرفع INVITE_INVALID / INVITE_NOT_GROUP)
create or replace function public.group_invite_join(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_code text;
  v_conv uuid;
begin
  if me is null then raise exception 'not authenticated'; end if;
  v_code := lower(coalesce(trim(p_code), ''));
  if v_code = '' or length(v_code) > 20 or v_code !~ '^[a-z0-9]+$' then
    raise exception 'INVITE_INVALID';
  end if;

  select conversation_id into v_conv
    from group_invites
   where code = v_code
     and not revoked
     and (expires_at is null or expires_at > now())
     and (max_uses is null or use_count < max_uses)
   order by created_at desc
   limit 1
   for update;

  if v_conv is null then raise exception 'INVITE_INVALID'; end if;

  -- يجب أن تكون مجموعة خاصة (لا مجتمعات ولا قنوات ولا محادثات فردية)
  if not exists (select 1 from conversations
                  where id = v_conv and is_group and kind = 'chat'
                    and community_id is null) then
    raise exception 'INVITE_NOT_GROUP';
  end if;

  -- عضو أصلاً؟ يكفي إعادته للمجموعة دون زيادة العدّاد
  if public.group_role(v_conv) is not null then
    return v_conv;
  end if;

  insert into conversation_participants (conversation_id, user_id, role)
  values (v_conv, me, 'member')
  on conflict (conversation_id, user_id) do nothing;

  update group_invites set use_count = use_count + 1
   where code = v_code;

  return v_conv;
end $$;

-- 5) الصلاحيات
do $$
declare f text;
begin
  foreach f in array array[
    'public.is_group_admin(uuid, uuid)',
    'public.group_invite_create(uuid)',
    'public.group_invite_join(text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- 6) تحقق سريع (شغّله بعد الترحيل):
--   select public.is_group_admin(gen_random_uuid(), auth.uid()); -- false بلا خطأ
--   select count(*) from public.group_invites;                   -- يعمل لمشرفٍ فقط
