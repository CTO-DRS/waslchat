-- وصل شات 0.13.0: المرحلة 4 كاملة — قوة تيليجرام
-- شغّله في SQL Editor بعد 024_community_phase3.sql
--
-- الفلسفة (مبدأ الخصوصية قبل الميزة):
-- - «رسائلي المحفوظة» سحابة شخصية: محادثة kind='saved' عضوها الوحيد صاحبها،
--   ورسائلها تُشفَّر بمفتاح محادثة يُغلَّف لنفسه — الخادم يخزّن نصاً مشفراً كأي مجموعة.
-- - اسم المستخدم: مساحة معرّف عامة (a-z0-9_ بحدود واضحة) مع كلمات محجوزة،
--   والتغيير مرة كل 24 ساعة لمنع التملص بعد الالتزام باسم.
-- - البوتات: كل بوت مستخدم auth حقيقي (بريد داخلي بكلمة مرور عشوائية لا يدخل منها
--   أحد) فصار عضواً عادياً في المحادثات بصلاحيات RLS نفسها. رمزه يظهر مرة واحدة
--   ويُخزَّن مُجزّأ SHA-256 — لا يُخزَّن الرمز الخام إطلاقاً. الويب هوك يوقَّع
--   HMAC-SHA256 بسرّ مستقل عن الرمز، وفي المحادثات المشفرة يصل للبوت نص مشفر
--   لا يستطيع فكه (لا مفاتيح له) — البوتات تعمل بأمانة كاملة في القنوات وغرف
--   المجتمعات (محتواها صريح بالتصميم) وفي محادثاتها المباشرة غير المشفرة.
-- - مشاهدات القنوات: صف لكل مشاهدة لكل مستخدم — عدّاد يقرؤه أعضاء القناة،
--   وإحصاءات موسعة لمشرفيها فقط.

-- ============ أ) رسائلي المحفوظة (السحابة الشخصية) ============

alter table public.conversations drop constraint if exists conversations_kind_check;
alter table public.conversations add constraint conversations_kind_check
  check (kind in ('chat', 'channel', 'saved'));

-- يجلب (أو ينشئ) محادثة «المحفوظة» الخاصة بالمستخدم — عضوها الوحيد هو
create or replace function public.saved_chat_get()
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid; conv uuid;
begin
  me := auth.uid();
  if me is null then raise exception 'not authenticated'; end if;
  select c.id into conv
  from conversations c
  join conversation_participants p on p.conversation_id = c.id and p.user_id = me
  where c.kind = 'saved'
  limit 1;
  if conv is not null then return conv; end if;
  insert into conversations (is_group, kind, title, created_by)
  values (true, 'saved', 'رسائلي المحفوظة', me) returning id into conv;
  insert into conversation_participants (conversation_id, user_id, role)
  values (conv, me, 'owner');
  return conv;
end; $$;

-- آخر رسالة في المحفوظة (للمعاينة في القائمة)
create or replace function public.saved_chat_preview()
returns table (message text, type text, created_at timestamptz)
language sql security definer stable set search_path = public as $$
  select m.content, m.type, m.created_at
  from messages m
  join conversations c on c.id = m.conversation_id and c.kind = 'saved'
  join conversation_participants p on p.conversation_id = c.id and p.user_id = auth.uid()
  order by m.created_at desc
  limit 1;
$$;

-- ============ ب) اسم المستخدم (waslchat.app/@user) ============

-- 1) تطبيع الأسماء القائمة قبل فرض القيد: أحرف صغيرة ورقم وشرطة سفلية فقط
update public.profiles
   set username = lower(regexp_replace(username, '[^a-zA-Z0-9_]', '_', 'g'));

-- 2) الأسماء الأقصر من 4 تُمدَّد بجزء من معرّف الحساب
update public.profiles
   set username = left(username, 18) || '_' || substr(replace(id::text, '-', ''), 1, 6)
 where char_length(username) < 4;

-- 3) فض التكرارات بعد التطبيع (الأقدم يحتفظ بالاسم، والبقية تُمدَّد حتى تتفرد)
do $$
declare r record; cand text; tries integer;
begin
  for r in
    select id, username, row_number() over (partition by username order by created_at, id) rn,
           (select count(*) from profiles x where x.username = p.username) total
    from profiles p
  loop
    continue when r.rn = 1;
    tries := 0;
    loop
      tries := tries + 1;
      cand := left(r.username, 16) || '_' || substr(replace(r.id::text, '-', ''), 1, 6 + tries);
      exit when not exists (select 1 from profiles x where x.username = cand and x.id <> r.id)
                  or tries > 20;
    end loop;
    update profiles set username = cand where id = r.id;
  end loop;
end $$;

-- 4) القيد الدائم: 4–24 حرفاً إنجليزياً صغيراً ورقماً وشرطة سفلية
alter table public.profiles drop constraint if exists profiles_username_format;
alter table public.profiles add constraint profiles_username_format
  check (username ~ '^[a-z0-9_]{4,24}$');

-- 5) متى غيّر المستخدم اسمه آخر مرة (أول تعيين حر ثم مرة كل 24 ساعة)
alter table public.profiles add column if not exists username_changed_at timestamptz;

-- 6) المستخدمون الجدد يولَّد لهم اسم مطابق للقيد دائماً (+ علم البوت)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  raw text;
  norm text;
begin
  raw := coalesce(nullif(new.raw_user_meta_data->>'username', ''),
                  split_part(new.email, '@', 1));
  norm := lower(regexp_replace(coalesce(raw, ''), '[^a-zA-Z0-9_]', '_', 'g'));
  if char_length(norm) < 4 then
    norm := norm || '_user';
  end if;
  norm := left(norm, 18);
  if exists (select 1 from profiles x where x.username = norm) then
    norm := left(norm, 16) || '_' || substr(replace(new.id::text, '-', ''), 1, 6);
  end if;
  insert into public.profiles (id, username, display_name, is_bot)
  values (new.id, norm,
          coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), raw),
          coalesce(new.raw_user_meta_data->>'is_bot', 'false')::boolean);
  return new;
end; $$;

-- 6-ب) علم البوت على الملف الشخصي: يعرف التطبيق أن يفتح محادثته غير مشفرة
alter table public.profiles add column if not exists is_bot boolean not null default false;

-- 7) هل الاسم متاح؟ (الصيغة + غير محجوز + غير مستخدم)
create or replace function public.username_available(p_username text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare u text;
begin
  u := lower(coalesce(trim(p_username), ''));
  if u like '@_%' then u := substr(u, 2); end if;
  if u !~ '^[a-z0-9_]{4,24}$' then return false; end if;
  if u = any (array[
    'wasl','waslchat','admin','administrator','support','help','api','bot','bots',
    'root','official','team','staff','moderator','mod','security','abuse','info',
    'contact','me','self','null','undefined','system','ai','notifications','verify',
    'login','signup','register','settings','profile','privacy','terms'
  ]) then return false; end if;
  return not exists (select 1 from profiles x where x.username = u);
end; $$;

-- 8) تعيين اسم المستخدم: صيغة سليمة + متاح + ليس قبل 24 ساعة من آخر تغيير
create or replace function public.username_set(p_username text)
returns text language plpgsql security definer set search_path = public as $$
declare u text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  u := lower(coalesce(trim(p_username), ''));
  if u like '@_%' then u := substr(u, 2); end if;
  if u !~ '^[a-z0-9_]{4,24}$' then raise exception 'bad username format'; end if;
  -- تعيين الاسم نفسه دون تغيير: نجاح صامت بلا عدّ تغيير
  if exists (select 1 from profiles x where x.id = auth.uid() and x.username = u) then
    return u;
  end if;
  if not public.username_available(u) then raise exception 'username taken'; end if;
  if exists (select 1 from profiles x
              where x.username = u and x.id <> auth.uid()) then
    raise exception 'username taken';
  end if;
  update profiles
     set username = u, username_changed_at = now()
   where id = auth.uid()
     and (username_changed_at is null or username_changed_at < now() - interval '24 hours');
  if not found then raise exception 'username cooldown'; end if;
  return u;
end; $$;

-- 9) جلب ملف مستخدم باسمه (لفتح محادثة من الرابط waslchat.app/@user)
create or replace function public.profile_by_username(p_username text)
returns table (id uuid, username text, display_name text, avatar_url text, bio text, is_bot boolean)
language sql security definer stable set search_path = public as $$
  select p.id, p.username, p.display_name, p.avatar_url, p.bio, p.is_bot
  from profiles p
  where p.username = lower(coalesce(trim(p_username), ''))
  limit 1;
$$;

-- 10) my_chats تعيد علم البوت (إلحاق في النهاية حفاظاً على التوافق)
--     محادثات البوتات تُفتح غير مشفرة — البوت يقرأها عبر واجهته بالتصميم
create or replace function public.my_chats()
returns table (
  conversation_id uuid, is_group boolean, title text, other_id uuid,
  last_message text, last_type text, last_at timestamptz, unread bigint,
  avatar_url text, pinned boolean, muted boolean, archived boolean,
  is_bot boolean
) language sql security definer stable set search_path = public as $$
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
        and (u.expires_at is null or u.expires_at > now())),
    case when c.is_group then c.avatar_url else op.avatar_url end,
    me.pinned_at is not null,
    me.muted_until is not null and me.muted_until > now(),
    me.archived,
    case when c.is_group then false else coalesce(op.is_bot, false) end
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name, p.avatar_url, p.is_bot
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at from messages m
    where m.conversation_id = c.id and (m.expires_at is null or m.expires_at > now())
    order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;

-- ============ ج) البوتات وواجهة المطوّرين (Webhooks) ============

-- 1) جدول البوتات: معرّف البوت هو مستخدم auth حقيقي (صف في profiles تلقائياً)
create table if not exists public.bots (
  id             uuid primary key references auth.users(id) on delete cascade,
  owner_id       uuid not null references public.profiles(id) on delete cascade,
  username       text not null unique check (username ~ '^[a-z0-9_]{4,20}_bot$'),
  name           text not null check (char_length(name) between 1 and 60),
  description    text check (char_length(coalesce(description, '')) <= 300),
  token_hash     text not null,
  token_tail     text not null default '',
  webhook_url    text,
  webhook_secret text not null default '',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);
create index if not exists bots_owner on public.bots (owner_id);
alter table public.bots enable row level security;

drop policy if exists "bots owner all" on public.bots;
create policy "bots owner all" on public.bots
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- 2) إنشاء بوت: يولّد مستخدم auth + ملف شخصي + رمزاً يظهر مرة واحدة (wasl_…)
create or replace function public.bot_create(
  p_name text, p_username text, p_description text default null, p_webhook_url text default null
) returns table (bot_id uuid, token text)
language plpgsql security definer set search_path = public as $$
declare
  me uuid; u text; bid uuid; tok text; raw jsonb;
begin
  me := auth.uid();
  if me is null then raise exception 'not authenticated'; end if;
  if (select count(*) from bots where owner_id = me) >= 10 then
    raise exception 'bot limit'; -- حد صادق لخطة مجانية: 10 بوتات لكل مالك
  end if;
  if char_length(coalesce(trim(p_name), '')) not between 1 and 60 then
    raise exception 'bad name';
  end if;
  u := lower(coalesce(trim(p_username), ''));
  if u like '@%' then u := substr(u, 2); end if;
  if u !~ '^[a-z0-9_]{4,20}_bot$' then raise exception 'bad bot username'; end if;
  if not public.username_available(u) then raise exception 'username taken'; end if;
  if char_length(coalesce(trim(coalesce(p_description, '')), '')) > 300 then
    raise exception 'bad description';
  end if;
  if p_webhook_url is not null and p_webhook_url <> ''
     and p_webhook_url !~ '^https?://[^\s]+$' then
    raise exception 'bad webhook url';
  end if;

  bid := gen_random_uuid();
  tok := 'wasl_' || encode(gen_random_bytes(24), 'hex');
  raw := jsonb_build_object('username', u, 'display_name', trim(p_name), 'is_bot', true);

  begin
    insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values (bid, 'authenticated', 'authenticated',
            u || '@bots.waslchat.internal',
            crypt(gen_random_uuid()::text, gen_salt('bf')),
            now(),
            '{"provider":"email","providers":["email"]}',
            raw, now(), now());
  exception when others then
    delete from auth.users where id = bid;
    raise;
  end;

  begin
    insert into bots (id, owner_id, username, name, description, token_hash, token_tail,
                      webhook_url, webhook_secret)
    values (bid, me, u, trim(p_name), nullif(trim(coalesce(p_description, '')), ''),
            encode(digest(tok, 'sha256'), 'hex'), right(tok, 4),
            nullif(trim(coalesce(p_webhook_url, '')), ''),
            encode(gen_random_bytes(24), 'hex'));
  exception when others then
    delete from auth.users where id = bid;
    raise;
  end;

  return query select bid, tok;
end; $$;

-- 3) تجديد الرمز (يظهر الجديد مرة واحدة — القديم يُلغى فوراً)
create or replace function public.bot_token_reset(p_bot uuid)
returns text language plpgsql security definer set search_path = public as $$
declare tok text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  tok := 'wasl_' || encode(gen_random_bytes(24), 'hex');
  update bots set token_hash = encode(digest(tok, 'sha256'), 'hex'), token_tail = right(tok, 4)
   where id = p_bot and owner_id = auth.uid();
  if not found then raise exception 'not found'; end if;
  return tok;
end; $$;

-- 4) ضبط/مسح الويب هوك + تفعيل/تعطيل
create or replace function public.bot_set_webhook(p_bot uuid, p_url text)
returns text language plpgsql security definer set search_path = public as $$
declare sec text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if coalesce(trim(p_url), '') <> '' and p_url !~ '^https?://[^\s]+$' then
    raise exception 'bad webhook url';
  end if;
  sec := encode(gen_random_bytes(24), 'hex');
  update bots set webhook_url = nullif(trim(coalesce(p_url, '')), ''), webhook_secret = sec
   where id = p_bot and owner_id = auth.uid();
  if not found then raise exception 'not found'; end if;
  return case when nullif(trim(coalesce(p_url, '')), '') is null then null else sec end;
end; $$;

create or replace function public.bot_set_active(p_bot uuid, p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update bots set is_active = coalesce(p_on, true)
   where id = p_bot and owner_id = auth.uid();
  if not found then raise exception 'not found'; end if;
end; $$;

-- 5) حذف بوت: يحذف مستخدم auth فيحذف بالتتابع ملفه وعضوياته ورسائله (cascade)
create or replace function public.bot_delete(p_bot uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from bots where id = p_bot and owner_id = auth.uid()) then
    raise exception 'not found';
  end if;
  delete from auth.users where id = p_bot;
end; $$;

-- 6) بوتاتي (بسرّ الويب هوك — يقرؤه المالك فقط عبر RLS، ولا يُعاد رمز الواجهة أبداً)
create or replace function public.my_bots()
returns table (id uuid, username text, name text, description text,
               webhook_url text, webhook_secret text, is_active boolean,
               token_tail text, created_at timestamptz)
language sql security definer stable set search_path = public as $$
  select b.id, b.username, b.name, b.description,
         b.webhook_url, b.webhook_secret, b.is_active, b.token_tail, b.created_at
  from bots b
  where b.owner_id = auth.uid()
  order by b.created_at asc;
$$;

-- 6) إضافة البوت إلى محادثة: مالك البوت وهو مشرف المحادثة (أو أي عضو لغرفتي؟ لا — مشرفون)
create or replace function public.bot_add_to_chat(p_bot uuid, p_conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c record; b record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into b from bots where id = p_bot and owner_id = auth.uid();
  if b.id is null then raise exception 'not your bot'; end if;
  select * into c from conversations where id = p_conv;
  if c.id is null then raise exception 'conversation not found'; end if;
  if c.kind = 'saved' then raise exception 'not allowed'; end if;
  if c.is_group then
    if not exists (select 1 from conversation_participants
                   where conversation_id = p_conv and user_id = auth.uid()
                     and role in ('owner', 'admin')) then
      raise exception 'admins only';
    end if;
  else
    -- محادثة فردية: لا يُضاف البوت إلا لمحادثته المباشرة عبر bot_start_chat
    raise exception 'use bot_start_chat';
  end if;
  insert into conversation_participants (conversation_id, user_id, role)
  values (p_conv, p_bot, 'member') on conflict do nothing;
end; $$;

create or replace function public.bot_remove_from_chat(p_bot uuid, p_conv uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b record;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into b from bots where id = p_bot and owner_id = auth.uid();
  if b.id is null then raise exception 'not your bot'; end if;
  delete from conversation_participants
   where conversation_id = p_conv and user_id = p_bot and role = 'member';
end; $$;

-- 7) بدء محادثة مباشرة مع بوت (أي مستخدم — البوتات عامة بروابطها)
create or replace function public.bot_start_chat(p_bot uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid; conv uuid;
begin
  me := auth.uid();
  if me is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from bots where id = p_bot and is_active) then
    raise exception 'bot not found';
  end if;
  if p_bot = me then raise exception 'cannot chat with yourself'; end if;
  select c.id into conv
  from conversations c
  join conversation_participants a on a.conversation_id = c.id and a.user_id = me
  join conversation_participants b on b.conversation_id = c.id and b.user_id = p_bot
  where c.is_group = false and c.kind = 'chat'
  limit 1;
  if conv is not null then return conv; end if;
  insert into conversations (is_group, kind) values (false, 'chat') returning id into conv;
  insert into conversation_participants (conversation_id, user_id, role)
  values (conv, me, 'owner'), (conv, p_bot, 'member');
  return conv;
end; $$;

-- 8) محادثات البوت (للمالك: أين يوجد بوتي؟)
create or replace function public.bot_chats(p_bot uuid)
returns table (conversation_id uuid, title text, kind text, is_group boolean, members bigint)
language sql security definer stable set search_path = public as $$
  select c.id,
         case when c.is_group then coalesce(c.title, 'محادثة')
              else coalesce((select p.display_name
                             from conversation_participants o
                             join profiles p on p.id = o.user_id
                             where o.conversation_id = c.id and o.user_id <> p_bot
                             limit 1), 'محادثة') end,
         c.kind, c.is_group,
         (select count(*) from conversation_participants x where x.conversation_id = c.id)
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  join conversation_participants bp on bp.conversation_id = c.id and bp.user_id = p_bot
  where exists (select 1 from bots b where b.id = p_bot and b.owner_id = auth.uid())
  order by c.created_at desc
  limit 100;
$$;

-- 9) واجهة البوت البرمجية (تستدعى من دالة bots-api بصلاحية الخدمة فقط):
--    التحقق من العضوية والصلاحيات والكتم ثم الإرسال باسم البوت
create or replace function public.bot_send_message(
  p_bot uuid, p_conv uuid, p_text text, p_reply_to uuid default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare mid uuid; c record; m record;
begin
  select * into c from conversations where id = p_conv;
  if c.id is null then raise exception 'chat not found'; end if;
  select * into m from conversation_participants
   where conversation_id = p_conv and user_id = p_bot;
  if m.user_id is null then raise exception 'bot not in chat'; end if;
  if c.kind = 'channel' and m.role not in ('owner', 'admin') then
    raise exception 'admins only'; -- القنوات: النشر للمشرفين فقط
  end if;
  -- الكتم المجتمعي يُفرض على البوت كأي عضو (community_mutes من ترحيل 023 —
  -- الكتم في وصل على مستوى المجتمع ويشمل كل غرفه)
  if c.community_id is not null and exists (
      select 1 from community_mutes m
      where m.community_id = c.community_id and m.user_id = p_bot
        and m.until_at > now()) then
    raise exception 'bot is muted';
  end if;
  -- حد الإغراق: 20 رسالة في الدقيقة لكل بوت (حماية لطبقة مجانية)
  if (select count(*) from messages x
      where x.conversation_id = p_conv and x.sender_id = p_bot
        and x.created_at > now() - interval '60 seconds') >= 20 then
    raise exception 'rate limit';
  end if;
  if char_length(coalesce(p_text, '')) not between 1 and 4000 then
    raise exception 'bad text length';
  end if;
  if p_reply_to is not null and not exists
     (select 1 from messages r
       where r.id = p_reply_to and r.conversation_id = p_conv) then
    p_reply_to := null;
  end if;
  insert into messages (conversation_id, sender_id, type, content, reply_to)
  values (p_conv, p_bot, 'text', p_text, p_reply_to)
  returning id into mid;
  return mid;
end; $$;

create or replace function public.bot_edit_message(p_bot uuid, p_msg uuid, p_text text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(p_text, '')) not between 1 and 4000 then
    raise exception 'bad text length';
  end if;
  update messages set content = p_text, edited_at = now()
   where id = p_msg and sender_id = p_bot
     and created_at > now() - interval '48 hours';
  if not found then raise exception 'message not editable'; end if;
end; $$;

create or replace function public.bot_delete_message(p_bot uuid, p_msg uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from messages where id = p_msg and sender_id = p_bot;
  if not found then raise exception 'message not found'; end if;
end; $$;

create or replace function public.bot_chat_info(p_bot uuid, p_conv uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from conversations where id = p_conv;
  if c.id is null then raise exception 'chat not found'; end if;
  if not exists (select 1 from conversation_participants
                 where conversation_id = p_conv and user_id = p_bot) then
    raise exception 'bot not in chat';
  end if;
  return jsonb_build_object(
    'id', c.id, 'kind', c.kind, 'is_group', c.is_group,
    'title', case when c.is_group then c.title else null end,
    'members', (select count(*) from conversation_participants x where x.conversation_id = c.id));
end; $$;

-- 10) تسليم الويب هوك: مُحفّز بعد إدراج أي رسالة في محادثة فيها بوت نشط له رابط
--     المحتوى المشفر يصل كما هو (نصاً مشفراً) — البوت لا يملك مفاتيح فلا يفكه أبداً
create or replace function public.bot_webhook_dispatch()
returns trigger language plpgsql security definer set search_path = public as $$
declare b record; payload jsonb;
begin
  -- رسائل البوت نفسه لا تُرسل له (منع الحلقات)
  if exists (select 1 from bots where id = new.sender_id) then
    return new;
  end if;
  for b in
    select bt.id, bt.webhook_url, bt.webhook_secret
    from bots bt
    join conversation_participants p on p.user_id = bt.id
      and p.conversation_id = new.conversation_id
    where bt.is_active and bt.webhook_url is not null
  loop
    payload := jsonb_build_object(
      'update_id', new.id,
      'message', jsonb_build_object(
        'id', new.id,
        'chat_id', new.conversation_id,
        'sender_id', new.sender_id,
        'type', new.type,
        'content', new.content,
        'media_url', new.media_url,
        'reply_to', new.reply_to,
        'created_at', new.created_at));
    begin
      perform extensions.net.http_post(
        url := b.webhook_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'User-Agent', 'WaslChat-Bot-Webhook/1.0',
          'X-Wasl-Signature', 'sha256=' || encode(
            hmac(payload::text, b.webhook_secret, 'sha256'), 'hex')),
        body := payload::text,
        timeout_milliseconds := 8000);
    exception when others then
      null; -- pg_net غير مفعّل أو فشل شبكة: لا نعطّل الإرسال أبداً
    end;
  end loop;
  return new;
end; $$;

drop trigger if exists bot_webhook_dispatch on public.messages;
create trigger bot_webhook_dispatch after insert on public.messages
  for each row execute function public.bot_webhook_dispatch();

-- ============ د) مشاهدات القنوات ============

-- صف لكل مشاهدة لكل مستخدم — القنوات فقط (kind='channel')
create table if not exists public.message_views (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  viewed_at  timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists message_views_message on public.message_views (message_id);
alter table public.message_views enable row level security;

drop policy if exists "views read by channel members" on public.message_views;
create policy "views read by channel members" on public.message_views
  for select to authenticated using (public.is_member(
    (select m.conversation_id from messages m where m.id = message_id)));

drop policy if exists "views insert own in my channel" on public.message_views;
create policy "views insert own in my channel" on public.message_views
  for insert to authenticated with check (
    user_id = auth.uid()
    and exists (
      select 1 from messages m
      join conversations c on c.id = m.conversation_id
      where m.id = message_id and c.kind = 'channel' and public.is_member(c.id)));

-- تسجيل مشاهدات دفعة واحدة (رسائل القنوات التي أعرضها الآن)
create or replace function public.channel_track_views(p_ids uuid[])
returns void language sql security definer set search_path = public as $$
  insert into message_views (message_id, user_id)
  select v, auth.uid()
  from unnest(p_ids) as v
  join messages m on m.id = v
  join conversations c on c.id = m.conversation_id
  where c.kind = 'channel' and public.is_member(c.id)
  on conflict (message_id, user_id) do nothing;
$$;

-- عدّادات المشاهدة لرسائل دفعة واحدة
create or replace function public.channel_view_counts(p_ids uuid[])
returns table (message_id uuid, views bigint)
language sql security definer stable set search_path = public as $$
  select v, count(mv.user_id)
  from unnest(p_ids) as v
  join messages m on m.id = v
  left join message_views mv on mv.message_id = v
  where public.is_member(m.conversation_id)
  group by v;
$$;

-- إحصاءات القناة للمشرفين: آخر 30 منشوراً بعدّاداتها + المتوسط
create or replace function public.channel_stats(p_conv uuid)
returns table (subscribers bigint, total_views bigint, avg_views numeric,
               post_id uuid, post_type text, post_content text,
               post_created_at timestamptz, views bigint)
language plpgsql security definer stable set search_path = public as $$
begin
  if not exists (
    select 1 from conversation_participants p
    join conversations c on c.id = p.conversation_id
    where p.conversation_id = p_conv and p.user_id = auth.uid()
      and c.kind = 'channel' and p.role in ('owner', 'admin')) then
    raise exception 'admins only';
  end if;
  return query
  with posts as (
    select m.id, m.type, m.content, m.created_at
    from messages m
    where m.conversation_id = p_conv and m.deleted_at is null
    order by m.created_at desc limit 30
  )
  select
    (select count(*) from conversation_participants x where x.conversation_id = p_conv),
    (select count(*) from message_views mv
      join messages m2 on m2.id = mv.message_id and m2.conversation_id = p_conv),
    coalesce((select round(avg(cnt), 1) from (
      select count(mv2.user_id) cnt from message_views mv2
      join messages m3 on m3.id = mv2.message_id and m3.conversation_id = p_conv
      group by mv2.message_id) s), 0),
    posts.id, posts.type, posts.content, posts.created_at,
    (select count(*) from message_views mv3 where mv3.message_id = posts.id)
  from posts
  order by posts.created_at desc;
end; $$;

-- ============ هـ) الصلاحيات ============

do $$
declare f text;
begin
  foreach f in array array[
    'public.saved_chat_get()',
    'public.saved_chat_preview()',
    'public.username_available(text)',
    'public.username_set(text)',
    'public.profile_by_username(text)',
    'public.bot_create(text, text, text, text)',
    'public.bot_token_reset(uuid)',
    'public.bot_delete(uuid)',
    'public.bot_set_webhook(uuid, text)',
    'public.bot_set_active(uuid, boolean)',
    'public.my_bots()',
    'public.bot_add_to_chat(uuid, uuid)',
    'public.bot_remove_from_chat(uuid, uuid)',
    'public.bot_start_chat(uuid)',
    'public.bot_chats(uuid)',
    'public.channel_track_views(uuid[])',
    'public.channel_view_counts(uuid[])',
    'public.channel_stats(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- دوال واجهة البوت لدالة bots-api (service_role) فقط — لا يستدعيها المستخدمون
  execute 'revoke execute on function public.bot_send_message(uuid, uuid, text, uuid) from public, anon, authenticated';
  execute 'revoke execute on function public.bot_edit_message(uuid, uuid, text) from public, anon, authenticated';
  execute 'revoke execute on function public.bot_delete_message(uuid, uuid) from public, anon, authenticated';
  execute 'revoke execute on function public.bot_chat_info(uuid, uuid) from public, anon, authenticated';
  execute 'grant execute on function public.bot_send_message(uuid, uuid, text, uuid) to service_role';
  execute 'grant execute on function public.bot_edit_message(uuid, uuid, text) to service_role';
  execute 'grant execute on function public.bot_delete_message(uuid, uuid) to service_role';
  execute 'grant execute on function public.bot_chat_info(uuid, uuid) to service_role';
end $$;
