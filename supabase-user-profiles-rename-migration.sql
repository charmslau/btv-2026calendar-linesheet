-- ============================================================
-- user_profiles: rename permission columns to match current tab names
--
-- WHY: the site's tabs were renamed to "Product Calendar Input",
-- "Global Calendar" and "Linesheet", but the permission columns in
-- Supabase kept their old internal short names (cal / creative / ls).
-- "creative" in particular no longer means anything on the site
-- (that tab used to be called "Creative Calendar"), so admins
-- granting access could no longer tell which checkbox controlled
-- which tab. This renames the columns to match the tabs exactly:
--
--   can_access_cal      -> can_access_product_calendar
--   can_edit_cal         -> can_edit_product_calendar
--   can_access_creative -> can_access_global_calendar
--   can_edit_creative    -> can_edit_global_calendar
--   can_access_ls       -> can_access_linesheet
--   can_edit_ls          -> can_edit_linesheet
--
-- Safe to re-run — each rename only happens if the old column name
-- still exists, so running this twice (or on a table that already
-- has the new names from a fresh supabase-setup.sql run) is a no-op.
--
-- Run this entire script in Supabase → SQL Editor → New query,
-- BEFORE deploying the corresponding code change in index.html.
-- ============================================================

do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_access_cal') then
    alter table public.user_profiles rename column can_access_cal to can_access_product_calendar;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_edit_cal') then
    alter table public.user_profiles rename column can_edit_cal to can_edit_product_calendar;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_access_creative') then
    alter table public.user_profiles rename column can_access_creative to can_access_global_calendar;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_edit_creative') then
    alter table public.user_profiles rename column can_edit_creative to can_edit_global_calendar;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_access_ls') then
    alter table public.user_profiles rename column can_access_ls to can_access_linesheet;
  end if;

  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_profiles' and column_name = 'can_edit_ls') then
    alter table public.user_profiles rename column can_edit_ls to can_edit_linesheet;
  end if;
end;
$$;

-- ── Verify ────────────────────────────────────────────────────
-- Run separately to confirm the new column names are in place:
--
--   select column_name from information_schema.columns
--   where table_schema = 'public' and table_name = 'user_profiles'
--   order by column_name;
