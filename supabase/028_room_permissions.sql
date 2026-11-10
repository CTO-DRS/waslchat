-- وصل شات 0.5.0: أدوار وصلاحيات مخصّصة لكل غرفة (المرحلة 3 — بند 1)
-- شغّله في SQL Editor بعد 027_stickers.sql
--
-- الفكرة: الأدوار الثابتة (owner/admin/member) تبقى كما هي، ويضاف فوقها
-- جدول صلاحيات لكل غرفة يتحكم فيما يستطيع الأعضاء والمشرفون فعله فيها.
-- غرفة بلا صف في الجدول = السلوك القديم حرفياً (كل الغرف القائمة تبقى كما هي).
--
-- الصلاحيات الست القابلة للتخصيص (قيمها الافتراضية تطابق السلوك الحالي):
--   member_media   : إرسال صور/فيديو/ملفات/ملصقات/موقع/بطاقات   (افتراضي: مسموح)
--   member_voice   : إرسال رسائل صوتية                            (افتراضي: مسموح)
--   member_polls   : إنشاء استطلاع والتصويت فيه                   (افتراضي: مسموح)
--   member_invites : إنشاء روابط دعوة للمجموعة                    (افتراضي: ممنوع — كما كان)
--   admin_manage_members : إضافة/إزالة أعضاء (للمشرفين)           (افتراضي: مسموح)
--   admin_edit_info      : تغيير اسم المجموعة (للمشرفين)          (افتراضي: مسموح)
-- المالك يملك كل شيء دائماً، والنص الحر يبقى مسموحاً لمن يملك النشر.
-- الفرض الخادمي على كل رسالة عبر can_send في سياسة الإدراج، وعلى الإدارة في RPCs.

-- 1) جدول الصلاحيات: قراءة لأعضاء الغرفة فقط، والكتابة عبر RPC فقط
--    (بلا سياسات insert/update/delete فأي كتابة مباشرة من العميل مرفوضة)
create table if not exists public.room_permissions (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  perms jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);
alter table public.room_permissions enable row level security;

drop policy if exists "room members read perms" on public.room_permissions;
create policy "room members read perms" on public.room_permissions
  for select to authenticated
  using (public.is_member(conversation_id));

-- 2) دوري في أي غرفة (مجموعة خاصة، غرفة مجتمع، قناة) — null إن لم أكن عضواً
create or replace function public.room_role(p_conv uuid)
returns text language sql security definer stable set search_path = public as $$
  select p.role from conversation_participants p
  where p.conversation_id = p_conv and p.user_id = auth.uid();
$$;

-- 3) قيمة صلاحية في غرفة: القيمة المحفوظة أو الافتراضي المطابق للسلوك القديم.
--    أي مفتاح غير معروف = false (أمان)
create or replace function public.room_permission(p_conv uuid, p_perm text)
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce(
    (select (r.perms ->> p_perm)::boolean
       from room_permissions r where r.conversation_id = p_conv),
    p_perm in ('member_media', 'member_voice', 'member_polls',
               'admin_manage_members', 'admin_edit_info')
  );
$$;

-- 4) الفرض على الإرسال: تحل محل can_post في سياسة إدراج الرسائل.
--    text دائماً مسموح لمن يملك النشر؛ المشرفون والمالك فوق القيود؛
--    الأعضاء يخضعون لصلاحيات النوع (الوسائط/الصوت/الاستطلاعات)
create or replace function public.can_send(p_conv uuid, p_type text)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants p
    join conversations c on c.id = p.conversation_id
    where p.conversation_id = p_conv and p.user_id = auth.uid()
      and (c.kind = 'chat' or p.role in ('owner', 'admin'))
  )
  and (
    p_type = 'text'
    or coalesce(public.room_role(p_conv), 'none') in ('owner', 'admin')
    or case
      when p_type in ('image', 'video', 'file', 'sticker', 'location', 'contact')
        then public.room_permission(p_conv, 'member_media')
      when p_type = 'voice'
        then public.room_permission(p_conv, 'member_voice')
      when p_type in ('poll', 'poll_vote')
        then public.room_permission(p_conv, 'member_polls')
      else false
    end
  );
$$;

drop policy if exists "members send messages" on public.messages;
create policy "members send messages" on public.messages
  for insert to authenticated
  with check (sender_id = auth.uid() and public.can_send(conversation_id, type));

-- 5) حفظ الصلاحيات: المالك فقط، تحقق صارم من المفاتيح والقيم (12 عنصراً كحدّ أقصى)،
--    يعيد الخريطة النهائية ليبني عليها العميل
create or replace function public.room_set_permissions(p_conv uuid, p_perms jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  allowed text[] := array[
    'member_media', 'member_voice', 'member_polls', 'member_invites',
    'admin_manage_members', 'admin_edit_info'
  ];
  k text;
  v jsonb;
  out_perms jsonb := '{}'::jsonb;
  n integer := 0;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(public.room_role(p_conv), 'none') <> 'owner' then
    raise exception 'owner only';
  end if;
  if p_perms is null or jsonb_typeof(p_perms) <> 'object' then
    raise exception 'bad perms';
  end if;
  for k, v in select * from jsonb_each(p_perms) loop
    if not (k = any(allowed)) or v is null or jsonb_typeof(v) <> 'boolean'
       or n >= 12 then
      raise exception 'bad perms';
    end if;
    out_perms := out_perms || jsonb_build_object(k, (v #>> '{}')::boolean);
    n := n + 1;
  end loop;
  insert into room_permissions (conversation_id, perms, updated_by)
  values (p_conv, out_perms, auth.uid())
  on conflict (conversation_id) do update
    set perms = excluded.perms,
        updated_at = now(),
        updated_by = excluded.updated_by;
  return out_perms;
end; $$;

-- 6) جلب دوري وصلاحيات غرفة في استدعاء واحد (كلفة شبكية واحدة لكل فتح محادثة)
create or replace function public.my_room_perms(p_conv uuid)
returns jsonb language sql security definer stable set search_path = public as $$
  select jsonb_build_object(
    'role', coalesce(public.room_role(p_conv), 'none'),
    'perms', coalesce(
      (select r.perms from room_permissions r
        where r.conversation_id = p_conv), '{}'::jsonb)
  );
$$;

-- 7) RPCs الإدارة تُحدَّث لتحترم الصلاحيات (نفس النطاق القديم: مجموعات خاصة)
--    إضافة أعضاء: المشرف يضيف إن سمحت له admin_manage_members
create or replace function public.group_add_members(p_conv uuid, p_members uuid[])
returns integer language plpgsql security definer set search_path = public as $$
declare n integer; my_role text := public.group_role(p_conv);
begin
  if not (my_role = 'owner'
          or (my_role = 'admin'
              and public.room_permission(p_conv, 'admin_manage_members'))) then
    raise exception 'admins only';
  end if;
  if coalesce(array_length(p_members, 1), 0) > 100 then raise exception 'too many'; end if;
  insert into conversation_participants (conversation_id, user_id, role)
  select p_conv, u, 'member' from unnest(p_members) u
  where exists (select 1 from profiles p where p.id = u)
  on conflict (conversation_id, user_id) do nothing;
  get diagnostics n = row_count;
  return n;
end; $$;

--    إزالة عضو: المشرف يزيل إن سمحت له admin_manage_members
create or replace function public.group_remove_member(p_conv uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
declare my_role text := public.group_role(p_conv); their_role text;
begin
  if not (my_role = 'owner'
          or (my_role = 'admin'
              and public.room_permission(p_conv, 'admin_manage_members'))) then
    raise exception 'admins only';
  end if;
  if p_user = auth.uid() then raise exception 'use group_leave'; end if;
  select role into their_role from conversation_participants
   where conversation_id = p_conv and user_id = p_user;
  if their_role is null then return; end if;
  if their_role = 'owner' then raise exception 'cannot remove owner'; end if;
  if their_role = 'admin' and my_role <> 'owner' then raise exception 'owner only'; end if;
  delete from conversation_participants where conversation_id = p_conv and user_id = p_user;
  update conversations set needs_rekey = true where id = p_conv;
end; $$;

--    تغيير الاسم: المشرف يغيّر إن سمحت له admin_edit_info
create or replace function public.group_rename(p_conv uuid, p_title text)
returns void language plpgsql security definer set search_path = public as $$
declare my_role text := public.group_role(p_conv);
begin
  if not (my_role = 'owner'
          or (my_role = 'admin'
              and public.room_permission(p_conv, 'admin_edit_info'))) then
    raise exception 'admins only';
  end if;
  if coalesce(trim(p_title), '') = '' then raise exception 'title required'; end if;
  update conversations set title = left(trim(p_title), 80) where id = p_conv;
end; $$;

--    الدعوات: المالك والمشرفون كالسابق، وأُضيف خيار فتحها للأعضاء (member_invites)
create or replace function public.group_get_invite(p_conv uuid)
returns text
language plpgsql security definer stable set search_path = public as $$
declare my_role text := public.group_role(p_conv);
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not (my_role in ('owner', 'admin')
          or (my_role = 'member'
              and public.room_permission(p_conv, 'member_invites'))) then
    raise exception 'forbidden';
  end if;
  return (select code from group_invites
           where conversation_id = p_conv and not revoked
           order by created_at desc limit 1);
end; $$;

create or replace function public.group_create_invite(p_conv uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare r text; my_role text := public.group_role(p_conv);
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not (my_role in ('owner', 'admin')
          or (my_role = 'member'
              and public.room_permission(p_conv, 'member_invites'))) then
    raise exception 'forbidden';
  end if;

  update group_invites set revoked = true
   where conversation_id = p_conv and not revoked;

  loop
    r := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from group_invites where code = r);
  end loop;

  insert into group_invites (code, conversation_id, created_by)
  values (r, p_conv, auth.uid());
  return r;
end; $$;

create or replace function public.group_revoke_invite(p_conv uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare my_role text := public.group_role(p_conv);
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not (my_role in ('owner', 'admin')
          or (my_role = 'member'
              and public.room_permission(p_conv, 'member_invites'))) then
    raise exception 'forbidden';
  end if;
  update group_invites set revoked = true
   where conversation_id = p_conv and not revoked;
end; $$;

-- 8) الصلاحيات: منح التنفيذ للمصادَقين فقط
do $$
declare f text;
begin
  foreach f in array array[
    'public.room_role(uuid)',
    'public.room_permission(uuid, text)',
    'public.can_send(uuid, text)',
    'public.room_set_permissions(uuid, jsonb)',
    'public.my_room_perms(uuid)',
    'public.group_add_members(uuid, uuid[])',
    'public.group_remove_member(uuid, uuid)',
    'public.group_rename(uuid, text)',
    'public.group_get_invite(uuid)',
    'public.group_create_invite(uuid)',
    'public.group_revoke_invite(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
