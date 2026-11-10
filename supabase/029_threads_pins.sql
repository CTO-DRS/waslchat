-- وصل شات 0.5.1: سلاسل الردود (Threads) والمنشورات المثبّتة (المرحلة 3 — بند 2)
-- شغّله في SQL Editor بعد 028_room_permissions.sql
--
-- السلاسل: ردّ يُؤسّس سلسلة تحت رسالة جذر. رسائل السلسلة إدراج عادي في
-- messages (تخضع لسياسة can_send الخادمية كأي رسالة)، والربط معرف فقط:
-- الخادم يعرف أي رسالة تتبع أي سلسلة — لا نص ولا وسائط.
--   بلا تعشيق: ردّ على رسالة داخل سلسلة يتبع جذر سلسلتها الأصلي.
--   حذف الجذر فيزيائياً (on delete set null) يفتح ردوده في التدفق الرئيسي.
--
-- المثبتات: حتى 10 لكل غرفة (خطأ MAX_PINS صريح عند التجاوز)، للمشرفين
-- والمالك في المجموعات وغرف المجتمعات، وللطرفين في الخاص. رسالة محذوفة
-- لا تُثبَّت، وحذف الرسالة يزيل تثبيتها (cascade). الإدراج والحذف عبر
-- RPCs فقط — بلا سياسات كتابة مباشرة على الجدول.

-- 1) عمود السلسلة + فهرس جزئي لقراءة رسائل سلسلة واحدة
alter table public.messages
  add column if not exists thread_root_id uuid
    references public.messages(id) on delete set null;

create index if not exists messages_thread_root
  on public.messages (thread_root_id) where thread_root_id is not null;

-- 2) فرض صحة السلسلة لحظة الإدراج (نمط messages_check_reply في 010):
--    الجذر لازم يكون في نفس المحادثة وغير محذوف؛ ردّ داخل سلسلة يتبع جذرها
--    الأصلي؛ أي حالة غير صالحة تعيد الرسالة للتدفق الرئيسي بربط null.
create or replace function public.messages_check_thread()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  root_conv uuid;
  root_deleted boolean;
  root_root uuid;
begin
  if new.thread_root_id is not null then
    select conversation_id, (deleted_at is not null), thread_root_id
      into root_conv, root_deleted, root_root
      from messages where id = new.thread_root_id;
    if root_conv is null or root_deleted then
      new.thread_root_id := null;
    elsif root_conv <> new.conversation_id then
      new.thread_root_id := null;
    elsif root_root is not null then
      new.thread_root_id := root_root; -- بلا تعشيق: نفس السلسلة الأصلية
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists messages_check_thread on public.messages;
create trigger messages_check_thread before insert on public.messages
  for each row execute function public.messages_check_thread();

-- 3) جدول المثبتات: قراءة لأعضاء الغرفة، الكتابة عبر RPCs فقط
create table if not exists public.room_pins (
  message_id      uuid primary key references public.messages(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  pinned_by       uuid not null references public.profiles(id) on delete cascade,
  pinned_at       timestamptz not null default now()
);
create index if not exists room_pins_conv
  on public.room_pins (conversation_id, pinned_at desc);

alter table public.room_pins enable row level security;

drop policy if exists "pins read by members" on public.room_pins;
create policy "pins read by members" on public.room_pins
  for select to authenticated
  using (public.is_member(conversation_id));

-- من يملك حق التثبيت في هذه المحادثة؟ الخاص: أي طرف؛ المجموعة والقناة: المالك والمشرف
create or replace function public.can_pin(p_conv uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare
  is_group boolean;
  my_role text;
begin
  if auth.uid() is null or not public.is_member(p_conv) then
    return false;
  end if;
  select c.is_group into is_group from conversations c where c.id = p_conv;
  if coalesce(is_group, true) then
    select p.role into my_role from conversation_participants p
      where p.conversation_id = p_conv and p.user_id = auth.uid();
    return coalesce(my_role, 'member') in ('owner', 'admin');
  end if;
  return true;
end; $$;

-- 4) تثبيت: رسالة موجودة غير محذوفة في غرفة أملك حقها، وحد 10 صارم
create or replace function public.pin_message(p_message uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  conv uuid;
  msg_deleted boolean;
  n integer;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select conversation_id, (deleted_at is not null)
    into conv, msg_deleted
    from messages where id = p_message;
  if conv is null or msg_deleted then raise exception 'message not found'; end if;
  if not public.can_pin(conv) then raise exception 'admins only'; end if;
  select count(*) into n from room_pins where conversation_id = conv;
  if n >= 10 then raise exception 'MAX_PINS'; end if;
  insert into room_pins (message_id, conversation_id, pinned_by)
  values (p_message, conv, auth.uid())
  on conflict (message_id) do nothing;
end; $$;

-- 5) إزالة تثبيت: بنفس حق التثبيت؛ غياب الصف لا خطأ (idempotent)
create or replace function public.unpin_message(p_message uuid)
returns void language plpgsql security definer set search_path = public as $$
declare conv uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select conversation_id into conv from room_pins where message_id = p_message;
  if conv is null then return; end if;
  if not public.can_pin(conv) then raise exception 'admins only'; end if;
  delete from room_pins where message_id = p_message;
end; $$;

-- 6) جلب مثبتات غرفة (حتى 10): معرفات وبيانات نوع الرسالة فقط —
--    النص المشفر يفكه العميل بنفس مفتاح المحادثة كما في أي رسالة
create or replace function public.list_pins(p_conv uuid)
returns table (
  message_id uuid,
  pinned_at  timestamptz,
  pinned_by  uuid,
  sender_id  uuid,
  type       text,
  content    text,
  created_at timestamptz
) language sql security definer stable set search_path = public as $$
  select r.message_id, r.pinned_at, r.pinned_by,
         m.sender_id, m.type, m.content, m.created_at
    from room_pins r
    join messages m on m.id = r.message_id
   where r.conversation_id = p_conv
     and public.is_member(p_conv)
   order by r.pinned_at desc
   limit 10;
$$;

-- 7) لا استدعاء من غير المصادَقين (نمط 028)
do $$
declare f text;
begin
  foreach f in array array[
    'public.can_pin(uuid)',
    'public.pin_message(uuid)',
    'public.unpin_message(uuid)',
    'public.list_pins(uuid)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
