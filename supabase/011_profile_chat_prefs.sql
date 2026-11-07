-- وصل شات 0.1.6: الملف الشخصي (نبذة + صورة) وتفضيلات المحادثات (تثبيت/كتم/أرشفة)
-- شغّله في SQL Editor بعد 010_message_features.sql

-- 1) الملف الشخصي
alter table public.profiles add column if not exists bio text;
do $$ begin
  alter table public.profiles add constraint profiles_bio_check
    check (bio is null or char_length(bio) <= 140);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.profiles add constraint profiles_display_name_check
    check (display_name is null or char_length(display_name) between 1 and 40);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.profiles add constraint profiles_avatar_url_check
    check (avatar_url is null or char_length(avatar_url) <= 400);
exception when duplicate_object then null; end $$;

-- الصور الشخصية: عامة القراءة، وكل مستخدم يكتب في مجلده <user_id>/ فقط
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 2097152,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "avatars insert own" on storage.objects;
create policy "avatars insert own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars update own" on storage.objects;
create policy "avatars update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "avatars delete own" on storage.objects;
create policy "avatars delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- 2) تفضيلات المحادثة لكل عضو
alter table public.conversation_participants
  add column if not exists pinned_at timestamptz,
  add column if not exists muted_until timestamptz,
  add column if not exists archived boolean not null default false;

-- p_mute_hours: null = بلا تغيير، 0 = إلغاء الكتم، -1 = دائماً، غير ذلك = عدد الساعات
-- المثبّتة لا تكون مؤرشفة والعكس. حد التثبيت 5 محادثات.
create or replace function public.set_chat_prefs(
  p_conv uuid, p_pinned boolean default null, p_mute_hours integer default null,
  p_archived boolean default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_pinned is true and (select count(*) from conversation_participants
       where user_id = auth.uid() and pinned_at is not null and conversation_id <> p_conv) >= 5 then
    raise exception 'pin limit';
  end if;
  update conversation_participants set
    pinned_at = case when p_archived is true then null
                     when p_pinned is null then pinned_at
                     when p_pinned then coalesce(pinned_at, now()) else null end,
    muted_until = case when p_mute_hours is null then muted_until
                       when p_mute_hours = 0 then null
                       when p_mute_hours < 0 then 'infinity'::timestamptz
                       else now() + make_interval(hours => least(p_mute_hours, 8760)) end,
    archived = case when p_pinned is true then false else coalesce(p_archived, archived) end
  where conversation_id = p_conv and user_id = auth.uid();
  if not found then raise exception 'not member'; end if;
end; $$;

revoke execute on function public.set_chat_prefs(uuid, boolean, integer, boolean) from public, anon;
grant execute on function public.set_chat_prefs(uuid, boolean, integer, boolean) to authenticated;

-- 3) قائمة المحادثات مع الصور والتفضيلات (المثبّتة أولاً)
drop function if exists public.my_chats();
create function public.my_chats()
returns table (
  conversation_id uuid, is_group boolean, title text, other_id uuid,
  last_message text, last_type text, last_at timestamptz, unread bigint,
  avatar_url text, pinned boolean, muted boolean, archived boolean
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
        and u.deleted_at is null and u.created_at > me.last_read_at),
    case when c.is_group then null else op.avatar_url end,
    me.pinned_at is not null,
    me.muted_until is not null and me.muted_until > now(),
    me.archived
  from conversations c
  join conversation_participants me on me.conversation_id = c.id and me.user_id = auth.uid()
  left join lateral (
    select p.id, p.username, p.display_name, p.avatar_url
    from conversation_participants o join profiles p on p.id = o.user_id
    where o.conversation_id = c.id and o.user_id <> auth.uid() limit 1
  ) op on not c.is_group
  left join lateral (
    select m.content, m.type, m.created_at, m.deleted_at from messages m
    where m.conversation_id = c.id order by m.created_at desc limit 1
  ) lm on true
  where c.kind = 'chat' and c.community_id is null
  order by (me.pinned_at is not null) desc, me.pinned_at desc nulls last, 7 desc;
$$;
revoke execute on function public.my_chats() from public, anon;
grant execute on function public.my_chats() to authenticated;
