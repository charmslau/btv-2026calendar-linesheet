-- ============================================================
-- BTV Planner – Supabase Setup SQL
-- Safe to re-run at any time — all statements are idempotent.
-- Run this entire script in Supabase → SQL Editor → New query
-- ============================================================

-- ── 1. app_state ─────────────────────────────────────────────

create table if not exists public.app_state (
  key        text        primary key,
  value      jsonb       not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid        references auth.users(id) on delete set null
);

alter table public.app_state enable row level security;

drop policy if exists "Authenticated users can read app_state"   on public.app_state;
drop policy if exists "Authenticated users can write app_state"  on public.app_state;
drop policy if exists "Authenticated users can update app_state" on public.app_state;

create policy "Authenticated users can read app_state"
  on public.app_state for select
  to authenticated
  using (true);

create policy "Authenticated users can write app_state"
  on public.app_state for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update app_state"
  on public.app_state for update
  to authenticated
  using (true);


-- ── 2. user_profiles ─────────────────────────────────────────

create table if not exists public.user_profiles (
  id             uuid        primary key references auth.users(id) on delete cascade,
  email          text,
  can_access_cal boolean     not null default true,
  can_access_ls  boolean     not null default true,
  created_at     timestamptz not null default now()
);

-- If table already existed with default false, update the defaults
alter table public.user_profiles
  alter column can_access_cal set default true,
  alter column can_access_ls  set default true;

alter table public.user_profiles enable row level security;

drop policy if exists "Users can read own profile"               on public.user_profiles;
drop policy if exists "Authenticated users can read all profiles" on public.user_profiles;
drop policy if exists "Authenticated users can update profiles"  on public.user_profiles;
drop policy if exists "Allow insert on user_profiles"            on public.user_profiles;

create policy "Users can read own profile"
  on public.user_profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "Authenticated users can read all profiles"
  on public.user_profiles for select
  to authenticated
  using (true);

create policy "Authenticated users can update profiles"
  on public.user_profiles for update
  to authenticated
  using (true);

create policy "Allow insert on user_profiles"
  on public.user_profiles for insert
  to authenticated
  with check (true);


-- ── 3. Trigger: auto-create profile on sign-up ───────────────

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, email, can_access_cal, can_access_ls)
  values (new.id, new.email, true, true)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();


-- ── 4. Grant access to all existing accounts ─────────────────
-- Fixes accounts that were created when the default was false.
-- Safe to re-run — only updates rows that are currently blocked.

update public.user_profiles
set can_access_cal = true,
    can_access_ls  = true
where can_access_cal = false
   or can_access_ls  = false;

-- Also ensure your own account has access.
insert into public.user_profiles (id, email, can_access_cal, can_access_ls)
select id, email, true, true
from auth.users
where email = 'charmaine.lau.btv@gmail.com'
on conflict (id) do update
  set can_access_cal = true,
      can_access_ls  = true;

-- ── Diagnostic: see all accounts and their access ────────────
-- Run this separately to check who has access and who doesn't:
--
--   select email, can_access_cal, can_access_ls, created_at
--   from public.user_profiles
--   order by created_at;
--

-- ── 5. change_log ────────────────────────────────────────────

create table if not exists public.change_log (
  id          bigint      generated always as identity primary key,
  key         text        not null,
  label       text,
  changed_by  uuid        references auth.users(id) on delete set null,
  email       text,
  changed_at  timestamptz not null default now()
);

create index if not exists change_log_changed_at_idx on public.change_log (changed_at desc);

alter table public.change_log enable row level security;

drop policy if exists "Authenticated users can read change_log"   on public.change_log;
drop policy if exists "Authenticated users can insert change_log" on public.change_log;

create policy "Authenticated users can read change_log"
  on public.change_log for select
  to authenticated
  using (true);

create policy "Authenticated users can insert change_log"
  on public.change_log for insert
  to authenticated
  with check (true);


-- ── 6. Enable Realtime on app_state ─────────────────────────

-- Adds app_state to the Realtime publication if not already there.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_state'
  ) then
    alter publication supabase_realtime add table public.app_state;
  end if;
end;
$$;


-- ── 7. Viewer / Editor permission columns ────────────────────
-- These let admins set per-user edit access for each module.
-- can_access_* controls visibility; can_edit_* controls write access.

alter table public.user_profiles
  add column if not exists can_access_creative boolean not null default true,
  add column if not exists can_edit_cal        boolean not null default true,
  add column if not exists can_edit_creative   boolean not null default true,
  add column if not exists can_edit_ls         boolean not null default true;


-- ── 8. BTV Calendar access column ────────────────────────────
-- Separate permission for the read-only BTV Calendar tab.
-- Managed independently from BTV Management Calendar access.

alter table public.user_profiles
  add column if not exists can_access_pub_cal boolean not null default true;


-- ── 9. public_calendar_entries ───────────────────────────────
-- Stores entries that have been marked "Live" in the BTV
-- Management Calendar, making them visible in the BTV Calendar.

create table if not exists public.public_calendar_entries (
  id           bigserial    primary key,
  entry_id     text         not null,
  year         int          not null,
  week_id      text         not null,
  section      text         not null,
  entry_data   jsonb        not null default '{}',
  published_by text,
  published_at timestamptz  not null default now(),
  unique (entry_id, year)
);

alter table public.public_calendar_entries enable row level security;

drop policy if exists "btv_pub_cal_select" on public.public_calendar_entries;
drop policy if exists "btv_pub_cal_insert" on public.public_calendar_entries;
drop policy if exists "btv_pub_cal_update" on public.public_calendar_entries;
drop policy if exists "btv_pub_cal_delete" on public.public_calendar_entries;

create policy "btv_pub_cal_select" on public.public_calendar_entries
  for select to authenticated using (true);

create policy "btv_pub_cal_insert" on public.public_calendar_entries
  for insert to authenticated with check (true);

create policy "btv_pub_cal_update" on public.public_calendar_entries
  for update to authenticated using (true);

create policy "btv_pub_cal_delete" on public.public_calendar_entries
  for delete to authenticated using (true);

grant all on public.public_calendar_entries to authenticated;
grant usage, select on sequence public.public_calendar_entries_id_seq to authenticated;

-- Enable realtime so BTV Calendar auto-refreshes when Live is toggled
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'public_calendar_entries'
  ) then
    alter publication supabase_realtime add table public.public_calendar_entries;
  end if;
end;
$$;


-- ── Done! ─────────────────────────────────────────────────────
