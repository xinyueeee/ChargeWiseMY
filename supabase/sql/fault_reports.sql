-- Module 3 — Infrastructure Feedback
-- Driver-facing schema: `fault_reports` table + `fault_report_photos` bucket.
-- See MODULE3_USER_IMPLEMENTATION_PLAN.md §4 for the design rationale.
--
-- Run this in the Supabase SQL editor (Project → SQL Editor → New query).
-- Idempotent: safe to re-run (uses `if not exists` / `on conflict` / `drop ... if exists`).
--
-- NOT included here: admin-only RLS policies (full read/write regardless of
-- owner) and the `maintenance_records` table — those depend on the
-- `is_admin()` helper and live in a companion migration alongside
-- MODULE3_ADMIN_IMPLEMENTATION_PLAN.md. Run this file first.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------

create table if not exists fault_reports (
  report_id    uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,

  -- Intentionally no FK to charging_stations(station_id) yet — confirm that
  -- column's actual type in the dashboard before adding one; a mismatched
  -- FK type will fail this migration outright. A report isn't required to
  -- be tied to a known station anyway (see plan §4.1).
  station_id   text,

  category     text not null default 'Other',
  description  text not null default '',
  photo_urls   text[] not null default '{}',
  contact_info text,
  latitude     double precision,
  longitude    double precision,
  address      text not null default '',

  -- Four-stage lifecycle: a driver files `submitted`; an admin confirms it
  -- with `verified`; logging a maintenance record against it (see
  -- `maintenance_records` in fault_reports_admin.sql) moves it to
  -- `in_progress`; completing that record — or an admin resolving it
  -- directly — moves it to `resolved`. See
  -- MODULE3_ADMIN_IMPLEMENTATION_PLAN.md for the admin-side write path.
  status       text not null default 'submitted'
               check (status in ('submitted', 'verified', 'in_progress', 'resolved')),

  -- Admin-only triage field: drivers never set or see this (the "Report an
  -- Issue" form has no priority input). Defaults to 'medium' so every
  -- existing/new report is triageable without a backfill.
  priority     text not null default 'medium'
               check (priority in ('high', 'medium', 'low')),

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- Written by the admin side only (see MODULE3_ADMIN_IMPLEMENTATION_PLAN.md).
  verified_at    timestamptz,
  verified_by    uuid references users(id),
  in_progress_at timestamptz,
  resolved_at    timestamptz

);

-- Upgrade path for anyone who already ran an earlier version of this file
-- (single `photo_url` column, no `contact_info`, 3-stage status, no
-- priority/in_progress_at) — matches the "Report an Issue" mockup's up-to-3
-- -photos picker/optional contact field, and the admin dashboard mockup's
-- 4-stage status pipeline + High/Medium/Low priority triage.
-- No-ops on a fresh install, since the table above is already created with
-- the final shape.
alter table fault_reports
  add column if not exists photo_urls text[] not null default '{}';
alter table fault_reports
  add column if not exists contact_info text;
alter table fault_reports
  drop column if exists photo_url;
alter table fault_reports
  add column if not exists priority text not null default 'medium';
alter table fault_reports
  add column if not exists in_progress_at timestamptz;
alter table fault_reports
  drop constraint if exists fault_reports_status_check;
alter table fault_reports
  add constraint fault_reports_status_check
  check (status in ('submitted', 'verified', 'in_progress', 'resolved'));
alter table fault_reports
  drop constraint if exists fault_reports_priority_check;
alter table fault_reports
  add constraint fault_reports_priority_check
  check (priority in ('high', 'medium', 'low'));

create index if not exists fault_reports_user_id_idx
  on fault_reports (user_id);
create index if not exists fault_reports_status_idx
  on fault_reports (status);
create index if not exists fault_reports_created_at_idx
  on fault_reports (created_at desc);

-- Keep `updated_at` current on every write.
create or replace function set_fault_reports_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists fault_reports_set_updated_at on fault_reports;
create trigger fault_reports_set_updated_at
  before update on fault_reports
  for each row execute function set_fault_reports_updated_at();

-- ---------------------------------------------------------------------------
-- Row Level Security — driver-owner policies
-- (admin full-access policies come in the companion admin migration)
-- ---------------------------------------------------------------------------

alter table fault_reports enable row level security;

drop policy if exists "fault_reports_select_all_authenticated" on fault_reports;
create policy "fault_reports_select_all_authenticated"
  on fault_reports for select
  to authenticated
  -- Community-wide visibility, same model as `proposals`: any signed-in
  -- driver can see all reports ("View Nearby Reported Issues").
  using (true);

drop policy if exists "fault_reports_insert_own" on fault_reports;
create policy "fault_reports_insert_own"
  on fault_reports for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "fault_reports_update_own_while_submitted" on fault_reports;
create policy "fault_reports_update_own_while_submitted"
  on fault_reports for update
  to authenticated
  -- Drivers may only edit their own report, and only before an admin has
  -- started processing it.
  using (auth.uid() = user_id and status = 'submitted')
  with check (auth.uid() = user_id);

drop policy if exists "fault_reports_delete_own_while_submitted" on fault_reports;
create policy "fault_reports_delete_own_while_submitted"
  on fault_reports for delete
  to authenticated
  using (auth.uid() = user_id and status = 'submitted');

-- ---------------------------------------------------------------------------
-- Storage bucket — mirrors the existing `avatars` bucket pattern
-- (path convention: `${userId}/${reportId}/${index}.${ext}`, up to 3 photos
-- per report; see auth_service.dart uploadAvatar for the analogous
-- driver-owned-folder approach. The policies below only check the first
-- path segment, so the extra `${reportId}/` nesting doesn't need any
-- policy change.)
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('fault_report_photos', 'fault_report_photos', true)
on conflict (id) do nothing;

drop policy if exists "fault_report_photos_public_read" on storage.objects;
create policy "fault_report_photos_public_read"
  on storage.objects for select
  to public
  using (bucket_id = 'fault_report_photos');

drop policy if exists "fault_report_photos_owner_write" on storage.objects;
create policy "fault_report_photos_owner_write"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'fault_report_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "fault_report_photos_owner_update" on storage.objects;
create policy "fault_report_photos_owner_update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'fault_report_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "fault_report_photos_owner_delete" on storage.objects;
create policy "fault_report_photos_owner_delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'fault_report_photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );