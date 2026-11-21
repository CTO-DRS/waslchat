-- وصل شات 0.1.4: نسخة احتياطية مشفّرة لمفتاح الهوية + إعادة تغليف بعد تغيير المفتاح
-- شغّله بعد 007_group_keys.sql
--
-- المفتاح الخاص يُشفَّر على الجهاز بكلمة سر يختارها المستخدم (PBKDF2-SHA256 + AES-256-GCM)
-- ولا يصل الخادم إلا النص المشفّر والملح. الخادم لا يرى كلمة السر ولا المفتاح.

create table if not exists public.e2e_key_backups (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  salt       text not null check (char_length(salt) between 16 and 64),
  iterations int  not null check (iterations between 100000 and 5000000),
  wrapped    text not null check (char_length(wrapped) between 40 and 300),
  updated_at timestamptz not null default now()
);

alter table public.e2e_key_backups enable row level security;

drop policy if exists "backup own select" on public.e2e_key_backups;
create policy "backup own select" on public.e2e_key_backups
  for select to authenticated using (user_id = auth.uid());
drop policy if exists "backup own insert" on public.e2e_key_backups;
create policy "backup own insert" on public.e2e_key_backups
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "backup own update" on public.e2e_key_backups;
create policy "backup own update" on public.e2e_key_backups
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "backup own delete" on public.e2e_key_backups;
create policy "backup own delete" on public.e2e_key_backups
  for delete to authenticated using (user_id = auth.uid());

-- بعد إنشاء مفتاح جديد: نحذف أظرفتي (لا تُفك بالمفتاح الجديد) والأظرفة التي غلّفتُها لغيري
-- (تعتمد على مفتاحي القديم). الأعضاء الذين يحفظون المفتاح على أجهزتهم يعيدون التغليف تلقائياً.
create or replace function public.e2e_drop_my_envelopes()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  delete from conversation_key_envelopes
  where user_id = auth.uid() or wrapped_by = auth.uid();
end; $$;

revoke execute on function public.e2e_drop_my_envelopes() from public, anon;
grant execute on function public.e2e_drop_my_envelopes() to authenticated;
