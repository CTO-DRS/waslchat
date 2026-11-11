-- الحظر والإبلاغ (المرحلة 0 — مطلوب للمتاجر)
-- الصق كاملاً في Supabase > SQL Editor ثم Run

-- ============ جدول الحظر ============
create table if not exists public.blocks (
  blocker uuid not null references auth.users(id) on delete cascade,
  blocked uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);

alter table public.blocks enable row level security;

create policy "blocks read own" on public.blocks
  for select to authenticated using (auth.uid() = blocker);
create policy "blocks insert own" on public.blocks
  for insert to authenticated with check (auth.uid() = blocker);
create policy "blocks delete own" on public.blocks
  for delete to authenticated using (auth.uid() = blocker);

-- فهرس لفحص سريع عند الإرسال
create index if not exists blocks_blocked_idx on public.blocks (blocked);

-- ============ جدول الإبلاغ ============
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null references auth.users(id) on delete cascade,
  target_user uuid references auth.users(id) on delete cascade,
  message_id uuid,
  reason text not null check (char_length(btrim(reason)) between 1 and 500),
  created_at timestamptz not null default now()
);

alter table public.reports enable row level security;

create policy "reports insert own" on public.reports
  for insert to authenticated with check (auth.uid() = reporter);
create policy "reports read own or admin" on public.reports
  for select to authenticated
  using (auth.uid() = reporter or public.is_app_admin());

-- ============ فرض الحظر من الخادم (المحادثات الفردية) ============
-- لا رسائل بين محظورَين في أي اتجاه؛ المجموعات والقنوات والقنوات المجتمعية مستثناة.
create or replace function public.assert_dm_not_blocked()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  peer uuid;
  is_group boolean;
begin
  select c.is_group into is_group from conversations c where c.id = new.conversation_id;
  if coalesce(is_group, true) then
    return new; -- المجموعات/القنوات لا تُفرض هنا (الإشراف أدواته لاحقاً)
  end if;

  select p.user_id into peer
  from conversation_participants p
  where p.conversation_id = new.conversation_id
    and p.user_id <> new.sender_id
  limit 1;

  if peer is not null and exists (
    select 1 from blocks b
    where (b.blocker = peer and b.blocked = new.sender_id)
       or (b.blocker = new.sender_id and b.blocked = peer)
  ) then
    raise exception 'BLOCKED';
  end if;
  return new;
end; $$;

drop trigger if exists trg_dm_not_blocked on public.messages;
create trigger trg_dm_not_blocked
  before insert on public.messages
  for each row execute function public.assert_dm_not_blocked();

-- ============ إخفاء المحظورون من البحث ============
-- تُفلتر في التطبيق بقائمة الحظر الخاصة (RLS على blocks تمنع رؤية حظر غيرك أصلاً).
