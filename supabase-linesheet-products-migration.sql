-- ============================================================
-- BTV Planner – Linesheet Products: per-row storage migration
--
-- WHY: btv_linesheet_products used to be stored as ONE giant JSON blob
-- under a single row in app_state. Every save — even ticking one
-- checkbox — rewrote the ENTIRE product list from whatever that
-- browser tab happened to have in memory. If two people worked on
-- different products around the same time, whoever saved last would
-- silently wipe out the other person's change, because their save
-- overwrote the whole list, not just the one product they touched.
--
-- This migration creates a dedicated table with ONE ROW PER PRODUCT,
-- so saving/deleting/toggling a product only ever touches that one
-- row and can never clobber anyone else's work.
--
-- Safe to re-run — all statements are idempotent. The data-copy step
-- uses ON CONFLICT DO NOTHING so re-running it won't duplicate or
-- overwrite anything.
--
-- Run this entire script in Supabase → SQL Editor → New query,
-- BEFORE deploying the corresponding code change.
-- ============================================================

-- ── 1. Table ──────────────────────────────────────────────────

create table if not exists public.linesheet_products (
  id         text        primary key,
  group_id   text        not null,
  data       jsonb       not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid        references auth.users(id) on delete set null
);

create index if not exists linesheet_products_group_id_idx
  on public.linesheet_products (group_id);

alter table public.linesheet_products enable row level security;

drop policy if exists "Authenticated users can read linesheet_products"   on public.linesheet_products;
drop policy if exists "Authenticated users can insert linesheet_products" on public.linesheet_products;
drop policy if exists "Authenticated users can update linesheet_products" on public.linesheet_products;
drop policy if exists "Authenticated users can delete linesheet_products" on public.linesheet_products;

create policy "Authenticated users can read linesheet_products"
  on public.linesheet_products for select
  to authenticated
  using (true);

create policy "Authenticated users can insert linesheet_products"
  on public.linesheet_products for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update linesheet_products"
  on public.linesheet_products for update
  to authenticated
  using (true);

create policy "Authenticated users can delete linesheet_products"
  on public.linesheet_products for delete
  to authenticated
  using (true);


-- ── 2. Enable Realtime ───────────────────────────────────────

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'linesheet_products'
  ) then
    alter publication supabase_realtime add table public.linesheet_products;
  end if;
end;
$$;


-- ── 3. One-time data copy from the old app_state blob ────────
-- Unpacks the existing JSON array (stored under app_state.key =
-- 'btv_linesheet_products') into individual rows. Rows already
-- migrated are skipped (ON CONFLICT DO NOTHING), so this is safe
-- to re-run if new products were added to the old blob before the
-- code deploy goes out.

insert into public.linesheet_products (id, group_id, data, updated_at, updated_by)
select
  elem->>'id'                                   as id,
  coalesce(elem->>'groupId', elem->>'id')       as group_id,
  elem                                          as data,
  coalesce(src.updated_at, now())               as updated_at,
  src.updated_by                                as updated_by
from public.app_state src,
     jsonb_array_elements(src.value) as elem
where src.key = 'btv_linesheet_products'
  and elem->>'id' is not null
on conflict (id) do nothing;


-- ── Verify ────────────────────────────────────────────────────
-- Run separately to confirm the row count matches the old blob's
-- array length before considering the migration complete:
--
--   select count(*) from public.linesheet_products;
--
--   select jsonb_array_length(value) from public.app_state
--   where key = 'btv_linesheet_products';
--
-- These two numbers should match.


-- ── Done! ─────────────────────────────────────────────────────
-- Do NOT delete the old app_state row for 'btv_linesheet_products'
-- yet — it's kept as a rollback safety net. Once the new code has
-- been running cleanly for a while and you've confirmed everything
-- looks right, it can be removed with:
--
--   delete from public.app_state where key = 'btv_linesheet_products';
