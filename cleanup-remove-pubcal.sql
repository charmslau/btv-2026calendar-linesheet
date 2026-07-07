-- ============================================================
-- BTV Planner – Remove BTV Public Calendar (one-time cleanup)
-- ============================================================
-- The BTV Public Calendar feature (nav tab, Publish/Live buttons,
-- and the underlying public_calendar_entries table) has been fully
-- removed from the app. This script cleans up what's left in the
-- database so it matches.
--
-- This is NOT part of supabase-setup.sql because it's destructive —
-- run it manually, once, in Supabase → SQL Editor → New query,
-- whenever you're ready. It is safe to re-run (idempotent), but the
-- data drop itself is irreversible.
-- ============================================================

-- Drops all published/Live entries. Irreversible — the data only ever
-- mirrored entries already stored in app_state (calendar-*-working-v5),
-- so nothing unique is lost.
drop table if exists public.public_calendar_entries;

-- Drops the per-user "BTV Cal" access toggle — no longer meaningful
-- with the tab removed.
alter table public.user_profiles
  drop column if exists can_access_pub_cal;
