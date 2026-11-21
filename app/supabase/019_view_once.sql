-- وصل شات v0.7.2: وسائط «تُعرض مرة واحدة» — المرحلة 2
-- شغّله في SQL Editor بعد 018_statuses.sql
--
-- الفكرة: المرسل يعلّم صورة أو فيديو بـ view_once = true (العلم نفسه ليس سراً —
--   الخادم يعرف النوع أصلاً). المستلم يفتح الوسيط مرة واحدة فيسجّل التطبيق مشاهدته
--   عبر open_view_once، وعندما يشاهد كل الأعضاء الآخرين يُنقل ملف الوسيط إلى
--   media_trash فتحذفه دالة media-cleanup الساعية من التخزين نهائياً —
--   أي أن فرض «مرة واحدة» من الخادم لا من الواجهة فقط.
-- viewed_at على الرسالة يتحدث عند أول مشاهدة من غير المرسل (مُحفّز) فيتدفق لحظياً
--   للمرسل عبر اشتراك messages الحالي (stream يلتقط التحديثات تلقائياً).
-- المرسل يفتح نسخته قبل أول مشاهدة بلا تسجيل مشاهدة (محتواه هو).
-- الويب: أفضل جهد (المتصفح لا يمنع لقطات الشاشة) — يُوضّح في RUNBOOK.

-- 1) أعمدة الرسالة ---------------------------------------------------------

alter table public.messages
  add column if not exists view_once boolean not null default false,
  add column if not exists viewed_at timestamptz;

-- 2) سجل المشاهدات ----------------------------------------------------------

create table if not exists public.message_views (
  message_id uuid not null references public.messages(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (message_id, viewer_id)
);

alter table public.message_views enable row level security;

-- المشاهد يسجّل مشاهدته على رسالة عرض-مرة-واحدة في محادثة يشاركها ولم تُحذف
drop policy if exists "message views insert by viewer" on public.message_views;
create policy "message views insert by viewer" on public.message_views
  for insert to authenticated
  with check (
    viewer_id = auth.uid()
    and exists (
      select 1 from messages m
      where m.id = message_id
        and m.view_once = true
        and m.deleted_at is null
        and m.media_url is not null
        and public.is_member(m.conversation_id)
    )
  );

-- المرسل يقرأ من شاهد رسالته؛ المشاهد يقرأ سجل مشاهدته
drop policy if exists "message views read by sender or viewer" on public.message_views;
create policy "message views read by sender or viewer" on public.message_views
  for select to authenticated
  using (
    viewer_id = auth.uid()
    or exists (select 1 from messages m
        where m.id = message_id and m.sender_id = auth.uid())
  );

-- 3) RPC: فتح وسيط «عرض مرة واحدة» ------------------------------------------
-- يستدعيه التطبيق عند فتح المستلم للوسيط (بعد تنزيله وفك تشفيره بنجاح).

create or replace function public.open_view_once(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  m public.messages;
  others int;
  seen int;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  select * into m from messages where id = p_id;
  if not found then raise exception 'not found'; end if;
  if not public.is_member(m.conversation_id) then raise exception 'not member'; end if;
  if not m.view_once or m.deleted_at is not null or m.media_url is null then
    raise exception 'not view-once';
  end if;

  -- المرسل يفتح نسخته بلا تسجيل ولا حذف
  if m.sender_id = auth.uid() then return; end if;

  insert into message_views (message_id, viewer_id)
  values (p_id, auth.uid())
  on conflict do nothing;

  -- اكتمال مشاهدات كل الأعضاء الآخرين ⇒ الوسيط إلى سلة التنظيف (حذف من الخادم)
  select count(*) into others
    from conversation_participants cp
    where cp.conversation_id = m.conversation_id and cp.user_id <> m.sender_id;

  select count(*) into seen
    from message_views v
    where v.message_id = p_id and v.viewer_id <> m.sender_id;

  if seen >= others then
    insert into media_trash (path) values (m.media_url) on conflict do nothing;
  end if;
end; $$;

revoke execute on function public.open_view_once(uuid) from public, anon;
grant execute on function public.open_view_once(uuid) to authenticated;

-- 4) viewed_at عند أول مشاهدة (يتدفق للمرسل لحظياً عبر stream الرسائل) -------

create or replace function public.message_views_touch()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update messages set viewed_at = now()
   where id = new.message_id and viewed_at is null;
  return new;
end; $$;

drop trigger if exists message_views_touch on public.message_views;
create trigger message_views_touch after insert on public.message_views
  for each row execute function public.message_views_touch();

-- 5) منع حذف/تعديل سجل المشاهدة بعد تسجيله (أثر التدقيق) — لا سياسات DELETE/UPDATE
--    على message_views أصلاً، فهي مغلقة افتراضياً مع RLS بلا سياسات لهذين الفعلين.
