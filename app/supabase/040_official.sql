-- وصل شات 1.9.4: الحسابات والغرف الرسمية الموثّقة + إدارة التطبيق
-- يُشغَّل بعد 039. آمن لإعادة التشغيل.
--
-- ما يضيفه:
--   1) توثيق الأشخاص: profiles.verified و profiles.is_official (لا يكتبهما إلا مسؤول التطبيق).
--   2) حسابان رسميان (لا يُدخل منهما إلا باستعادة كلمة المرور على بريد المالك):
--        @waslchat  «وصل شات»       — مالك الغرف الرسمية
--        @wasl_support «دعم وصل شات» — الدعم الفني
--   3) غرف رسمية موثّقة: «مجتمع وصل شات» (بغرفتيه)، «قناة وصل شات»، «مجموعة وصل شات».
--   4) كل حساب جديد ينضم تلقائياً إليها، وتُفتح له محادثة مع الدعم برسالة ترحيب.
--   5) cto.drs@gmail.com يصبح مسؤول التطبيق الوحيد، موثّقاً ومشرفاً في كل الغرف الرسمية.
--   6) أدوات الإدارة: توثيق/حظر المستخدمين، توثيق المجتمعات والقنوات والمجموعات.
--   7) my_chats تعيد is_bot (سقط سهواً في 031) و verified و official.

-- ============ 1) الأعمدة ============
alter table public.profiles add column if not exists verified boolean not null default false;
alter table public.profiles add column if not exists is_official boolean not null default false;

-- منع المستخدم من توثيق نفسه: أي تحديث من غير مسؤول لا يغيّر العمودين
create or replace function public.profiles_guard_badges()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is not null and not public.is_app_admin() then
    new.verified := old.verified;
    new.is_official := old.is_official;
  end if;
  return new;
end; $$;
drop trigger if exists profiles_guard_badges on public.profiles;
create trigger profiles_guard_badges before update on public.profiles
  for each row execute function public.profiles_guard_badges();

-- ============ 2) سجل الكيانات الرسمية ============
create table if not exists public.app_official (
  key text primary key,          -- account | support | community | channel | group
  id uuid not null
);
alter table public.app_official enable row level security;
drop policy if exists "official readable" on public.app_official;
create policy "official readable" on public.app_official for select to authenticated using (true);

create table if not exists public.app_owner_emails (email text primary key);
alter table public.app_owner_emails enable row level security; -- لا سياسات: لا يقرؤه أحد من التطبيق
insert into public.app_owner_emails values ('cto.drs@gmail.com') on conflict do nothing;

create or replace function public.official_id(k text)
returns uuid language sql stable security definer set search_path = public, extensions as $$
  select id from app_official where key = k;
$$;

-- ============ 3) إنشاء الحسابات الرسمية ============
create or replace function public._ensure_official_user(k text, p_email text, p_username text,
                                                       p_name text, p_bio text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid;
begin
  uid := official_id(k);
  if uid is not null and exists (select 1 from auth.users where id = uid) then return uid; end if;
  uid := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', p_email,
          crypt(encode(gen_random_bytes(24), 'hex'), gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}',
          jsonb_build_object('username', p_username, 'display_name', p_name), now(), now(), '', '', '', '');
  update profiles set username = p_username, display_name = p_name, bio = p_bio,
                      verified = true, is_official = true
   where id = uid;
  insert into app_official values (k, uid) on conflict (key) do update set id = excluded.id;
  return uid;
end; $$;

do $$
declare acc uuid; sup uuid; cid uuid; ch uuid; grp uuid;
begin
  acc := public._ensure_official_user('account', 'cto.drs+waslchat@gmail.com', 'waslchat',
           'وصل شات', 'الحساب الرسمي لتطبيق وصل شات');
  sup := public._ensure_official_user('support', 'cto.drs+support@gmail.com', 'wasl_support',
           'دعم وصل شات', 'الدعم الفني الرسمي — نرد عليك هنا');

  -- المجتمع الرسمي
  cid := public.official_id('community');
  if cid is null then
    insert into communities (name, description, owner_id, is_public, verified)
    values ('مجتمع وصل شات', 'المجتمع الرسمي لمستخدمي وصل شات: أخبار، أفكار، ومساعدة', acc, true, true)
    returning id into cid;
    insert into community_members (community_id, user_id, role) values (cid, acc, 'owner');
    insert into conversations (is_group, kind, title, community_id, created_by)
      values (true, 'channel', 'الإعلانات', cid, acc), (true, 'chat', 'عام', cid, acc);
    insert into conversation_participants (conversation_id, user_id, role)
      select id, acc, 'owner' from conversations where community_id = cid;
    insert into app_official values ('community', cid);
  end if;

  -- القناة الرسمية
  ch := public.official_id('channel');
  if ch is null then
    insert into conversations (is_group, kind, title, description, is_public, verified, created_by)
    values (true, 'channel', 'قناة وصل شات', 'التحديثات والإعلانات الرسمية لوصل شات', true, true, acc)
    returning id into ch;
    insert into conversation_participants (conversation_id, user_id, role) values (ch, acc, 'owner');
    insert into app_official values ('channel', ch);
  end if;

  -- المجموعة الرسمية (غير مشفّرة طرفياً: مجموعة عامة مفتوحة للجميع)
  grp := public.official_id('group');
  if grp is null then
    insert into conversations (is_group, kind, title, description, verified, created_by)
    values (true, 'chat', 'مجموعة وصل شات', 'مجموعة المستخدمين الرسمية — تعارف ونقاش واقتراحات', true, acc)
    returning id into grp;
    insert into conversation_participants (conversation_id, user_id, role) values (grp, acc, 'owner');
    insert into app_official values ('group', grp);
  end if;
end $$;

-- ============ 4) الانضمام التلقائي + ترحيب الدعم + المالك ============
create or replace function public.join_official(uid uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare acc uuid := official_id('account'); sup uuid := official_id('support');
        cid uuid := official_id('community'); ch uuid := official_id('channel');
        grp uuid := official_id('group'); dm uuid; owner boolean; r text;
begin
  if uid is null or uid in (acc, sup) then return; end if;
  if exists (select 1 from profiles where id = uid and is_bot) then return; end if;
  owner := exists (select 1 from auth.users u join app_owner_emails o on lower(o.email) = lower(u.email)
                   where u.id = uid);
  r := case when owner then 'admin' else 'member' end;

  if cid is not null then
    insert into community_members (community_id, user_id, role) values (cid, uid, r)
      on conflict (community_id, user_id) do update set role = excluded.role
      where community_members.role <> 'owner';
    insert into conversation_participants (conversation_id, user_id, role)
      select c.id, uid, r from conversations c where c.community_id = cid
      on conflict (conversation_id, user_id) do update set role = excluded.role
      where conversation_participants.role <> 'owner';
  end if;
  insert into conversation_participants (conversation_id, user_id, role)
    select x, uid, r from unnest(array[ch, grp]) x where x is not null
    on conflict (conversation_id, user_id) do update set role = excluded.role
    where conversation_participants.role <> 'owner';

  if owner then
    insert into app_admins (user_id) values (uid) on conflict do nothing;
    update profiles set verified = true where id = uid;
  end if;

  -- محادثة الدعم برسالة ترحيب (غير مشفّرة: حساب رسمي)
  if sup is not null and not exists (
      select 1 from conversations c
      join conversation_participants a on a.conversation_id = c.id and a.user_id = uid
      join conversation_participants b on b.conversation_id = c.id and b.user_id = sup
      where not c.is_group and c.kind = 'chat') then
    insert into conversations (is_group, kind, created_by) values (false, 'chat', sup) returning id into dm;
    insert into conversation_participants (conversation_id, user_id) values (dm, uid), (dm, sup);
    insert into messages (conversation_id, sender_id, content)
    values (dm, sup, 'أهلاً بك في وصل شات 👋' || chr(10) ||
                     'هذا حساب الدعم الفني الرسمي. اكتب لنا هنا أي مشكلة أو فكرة، ونرد عليك بأسرع وقت.' || chr(10) ||
                     'تابع «قناة وصل شات» لآخر التحديثات، وشاركنا في «مجموعة وصل شات».');
  end if;
end; $$;
revoke execute on function public.join_official(uuid) from public, anon, authenticated;
revoke execute on function public._ensure_official_user(text, text, text, text, text) from public, anon, authenticated;

create or replace function public.profiles_after_insert_official()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  begin
    perform public.join_official(new.id);
  exception when others then
    raise warning 'join_official failed: %', sqlerrm; -- لا نعطّل التسجيل أبداً
  end;
  return new;
end; $$;
drop trigger if exists profiles_after_insert_official on public.profiles;
create trigger profiles_after_insert_official after insert on public.profiles
  for each row execute function public.profiles_after_insert_official();

-- ============ 5) أدوات مسؤول التطبيق ============
create or replace function public.admin_set_user_verified(p_user uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  update profiles set verified = coalesce(p_verified, false) where id = p_user;
end; $$;

create or replace function public.admin_set_banned(p_user uuid, p_banned boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  if p_user = auth.uid() or exists (select 1 from app_admins where user_id = p_user)
     or exists (select 1 from profiles where id = p_user and is_official) then
    raise exception 'protected';
  end if;
  update auth.users set banned_until = case when p_banned then 'infinity'::timestamptz else null end
   where id = p_user;
  if p_banned then
    delete from auth.sessions where user_id = p_user;
    delete from auth.refresh_tokens where user_id::uuid = p_user;
  end if;
end; $$;

create or replace function public.admin_verify_conversation(conv uuid, p_verified boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  update conversations set verified = coalesce(p_verified, false) where id = conv;
end; $$;

drop function if exists public.admin_users(integer);
create function public.admin_users(p_limit integer default 50, q text default '')
returns table (id uuid, email text, username text, display_name text, avatar_url text,
               created_at timestamptz, last_sign_in_at timestamptz,
               verified boolean, is_official boolean, banned boolean, is_admin boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  return query
    select u.id, u.email::text, p.username, p.display_name, p.avatar_url, u.created_at,
           u.last_sign_in_at, coalesce(p.verified, false), coalesce(p.is_official, false),
           (u.banned_until is not null and u.banned_until > now()),
           exists (select 1 from app_admins a where a.user_id = u.id)
    from auth.users u left join profiles p on p.id = u.id
    where coalesce(p.is_bot, false) = false
      and (coalesce(q, '') = '' or p.username ilike '%' || q || '%'
           or p.display_name ilike '%' || q || '%' or u.email ilike '%' || q || '%')
    order by u.created_at desc limit least(greatest(p_limit, 1), 500);
end $$;

do $$ declare f text; begin
  foreach f in array array[
    'public.admin_set_user_verified(uuid, boolean)',
    'public.admin_set_banned(uuid, boolean)',
    'public.admin_verify_conversation(uuid, boolean)',
    'public.admin_users(integer, text)',
    'public.official_id(text)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ============ 6) my_chats: is_bot + verified + official ============
drop function if exists public.my_chats();
create function public.my_chats()
returns table (conversation_id uuid, is_group boolean, title text, other_id uuid,
               last_message text, last_type text, last_at timestamptz, unread bigint,
               avatar_url text, pinned boolean, muted boolean, archived boolean,
               is_bot boolean, verified boolean, official boolean)
language sql stable security definer set search_path = public, extensions as $$
  select
    c.id, c.is_group,
    case when c.is_group then coalesce(c.title, 'مجموعة')
         else coalesce(op.display_name, op.username) end,
    case when c.is_group then null else op.id end,
    case when lm.deleted_at is not null then '🚫 حُذفت هذه الرسالة' else lm.content end,
    lm.type,
    coalesce(lm.created_at, c.created_at),
    (select count(*) from messages u
      where u.conversation_id = c.id and u.sender_id <> auth.uid()
        and u.deleted_at is null and u.created_at > me.last_read_at
        and u.created_at > coalesce(me.cleared_at, 'epoch'::timestamptz)),
    case when c.is_group then c.avatar_url else op.avatar_url end,
    me.pinned_at is not null,
    me.muted_until is not null and me.muted_until > now(),
    me.archived,
    case when c.is_group then false else coalesce(op.is_bot, false) end,
    case when c.is_group then c.verified else coalesce(op.verified, false) end,
    case when c.is_group then c.id = public.official_id('group')
         else coalesce(op.is_official, false) end
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name, p.avatar_url, p.is_bot, p.verified, p.is_official
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at from messages m
    where m.conversation_id = c.id
      and m.created_at > coalesce(me.cleared_at, 'epoch'::timestamptz)
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;
