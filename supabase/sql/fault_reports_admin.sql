-- Module 3 — Infrastructure Feedback
-- Admin-facing schema: `is_admin()` helper, admin RLS on `fault_reports`,
-- and the new `maintenance_records` table + its RLS/storage-free policies.
-- See MODULE3_ADMIN_IMPLEMENTATION_PLAN.md §2.3/§3.2 for the design
-- rationale.
--
-- Run this AFTER fault_reports.sql (this file assumes that table already
-- exists with its 4-stage status + priority columns).
-- Idempotent: safe to re-run.

-- ---------------------------------------------------------------------------
-- is_admin() helper — security definer so the check itself isn't blocked by
-- RLS on `users` (an authenticated user can always read their own row, but
-- this needs to work when checking *any* row during a policy evaluation).
-- ---------------------------------------------------------------------------

create or replace function is_admin() returns boolean as $$
  select exists (
    select 1 from users where id = auth.uid() and role = 'admin'
  );
$$ language sql stable security definer;

-- ---------------------------------------------------------------------------
-- Admin RLS on fault_reports — full read/write regardless of owner, sitting
-- alongside (not instead of) the driver-owner policies in fault_reports.sql.
-- ---------------------------------------------------------------------------

drop policy if exists "fault_reports_admin_full_access" on fault_reports;
create policy "fault_reports_admin_full_access"
  on fault_reports for all
  to authenticated
  using (is_admin())
  with check (is_admin());

-- ---------------------------------------------------------------------------
-- Table: maintenance_records
-- ---------------------------------------------------------------------------

create table if not exists maintenance_records (
  record_id        uuid primary key default gen_random_uuid(),

  -- Set when this record closes out a specific fault report (the normal
  -- "Log Maintenance Record" flow from AdminReportDetailsScreen). Left null
  -- for routine/preventive maintenance not tied to a report.
  report_id        uuid references fault_reports(report_id) on delete set null,
  station_id       text,

  performed_by     uuid references users(id),
  -- Free-text technician name rather than a `users` FK — the technician
  -- dispatched to a site is frequently not an app account holder.
  technician_name  text,

  summary          text not null default '',
  description      text not null default '',

  -- Dispatch/tracking status for this maintenance task — distinct from the
  -- fault report's own lifecycle status. 'completed' is what moves the
  -- linked report (if any) to 'resolved'; it's excluded from "ongoing"
  -- queries once reached.
  status           text not null default 'scheduled'
                   check (status in ('scheduled', 'on_site', 'delayed', 'other', 'completed')),

  -- Free-text ETA label (e.g. "1 hour", "30 mins") rather than a computed
  -- timestamp — keeps the admin form simple and matches how the mockup
  -- displays it verbatim ("ETA: 1 hour" / "Delayed by 1 hour").
  eta_label        text,

  maintenance_date timestamptz not null default now(),
  cost             numeric,

  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists maintenance_records_report_id_idx
  on maintenance_records (report_id);
create index if not exists maintenance_records_status_idx
  on maintenance_records (status);
create index if not exists maintenance_records_maintenance_date_idx
  on maintenance_records (maintenance_date desc);

create or replace function set_maintenance_records_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

drop trigger if exists maintenance_records_set_updated_at on maintenance_records;
create trigger maintenance_records_set_updated_at
  before update on maintenance_records
  for each row execute function set_maintenance_records_updated_at();

alter table maintenance_records enable row level security;

drop policy if exists "maintenance_records_admin_full_access" on maintenance_records;
create policy "maintenance_records_admin_full_access"
  on maintenance_records for all
  to authenticated
  using (is_admin())
  with check (is_admin());
