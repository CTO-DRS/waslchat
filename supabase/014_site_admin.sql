-- 014: website backend — contact form, download counter, admins, admin dashboard RPCs

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.app_admins enable row level security;
-- no policies: readable only through security definer functions

insert into public.app_admins(user_id)
select id from auth.users where email in ('cto.drs@gmail.com','info@cto-drs.com')
on conflict do nothing;

create or replace function public.is_app_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.app_admins where user_id = auth.uid());
$$;
grant execute on function public.is_app_admin() to authenticated;

-- contact form
create table if not exists public.contact_messages (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 100),
  email text not null check (char_length(email) between 3 and 200 and email like '%@%'),
  subject text check (subject is null or char_length(subject) <= 150),
  message text not null check (char_length(message) between 1 and 4000),
  status text not null default 'new' check (status in ('new','read','done')),
  created_at timestamptz not null default now()
);
alter table public.contact_messages enable row level security;
drop policy if exists contact_insert_anyone on public.contact_messages;
create policy contact_insert_anyone on public.contact_messages
  for insert to anon, authenticated with check (status = 'new');
drop policy if exists contact_admin_select on public.contact_messages;
create policy contact_admin_select on public.contact_messages
  for select to authenticated using (public.is_app_admin());
drop policy if exists contact_admin_update on public.contact_messages;
create policy contact_admin_update on public.contact_messages
  for update to authenticated using (public.is_app_admin()) with check (public.is_app_admin());
drop policy if exists contact_admin_delete on public.contact_messages;
create policy contact_admin_delete on public.contact_messages
  for delete to authenticated using (public.is_app_admin());

-- simple rate limit: max 5 messages per email per hour
create or replace function public.contact_rate_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.contact_messages
      where lower(email) = lower(new.email) and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'rate_limited';
  end if;
  return new;
end $$;
drop trigger if exists contact_rate_limit on public.contact_messages;
create trigger contact_rate_limit before insert on public.contact_messages
  for each row execute function public.contact_rate_limit();

-- download counter
create table if not exists public.site_downloads (
  id bigint generated always as identity primary key,
  version text,
  platform text,
  created_at timestamptz not null default now()
);
alter table public.site_downloads enable row level security;

create or replace function public.track_download(p_version text default null, p_platform text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare n bigint;
begin
  insert into public.site_downloads(version, platform)
  values (left(p_version, 20), left(p_platform, 40));
  select count(*) into n from public.site_downloads;
  return n;
end $$;
grant execute on function public.track_download(text, text) to anon, authenticated;

create or replace function public.download_count()
returns bigint language sql stable security definer set search_path = public as $$
  select count(*) from public.site_downloads;
$$;
grant execute on function public.download_count() to anon, authenticated;

-- admin stats
create or replace function public.admin_stats()
returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  return json_build_object(
    'users', (select count(*) from auth.users),
    'users_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'active_24h', (select count(*) from auth.users where last_sign_in_at > now() - interval '24 hours'),
    'conversations', (select count(*) from public.conversations),
    'groups', (select count(*) from public.conversations where is_group),
    'communities', (select count(*) from public.communities),
    'messages', (select count(*) from public.messages),
    'messages_24h', (select count(*) from public.messages where created_at > now() - interval '24 hours'),
    'downloads', (select count(*) from public.site_downloads),
    'downloads_7d', (select count(*) from public.site_downloads where created_at > now() - interval '7 days'),
    'contact_new', (select count(*) from public.contact_messages where status = 'new')
  );
end $$;
grant execute on function public.admin_stats() to authenticated;

create or replace function public.admin_users(p_limit int default 50)
returns table(id uuid, email text, username text, display_name text, created_at timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  return query
    select u.id, u.email::text, p.username, p.display_name, u.created_at, u.last_sign_in_at
    from auth.users u left join public.profiles p on p.id = u.id
    order by u.created_at desc limit least(greatest(p_limit,1),500);
end $$;
grant execute on function public.admin_users(int) to authenticated;

create or replace function public.admin_downloads_daily(p_days int default 30)
returns table(day date, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_app_admin() then raise exception 'not_admin'; end if;
  return query
    select (d.created_at at time zone 'Asia/Riyadh')::date, count(*)
    from public.site_downloads d
    where d.created_at > now() - make_interval(days => least(greatest(p_days,1),365))
    group by 1 order by 1;
end $$;
grant execute on function public.admin_downloads_daily(int) to authenticated;
