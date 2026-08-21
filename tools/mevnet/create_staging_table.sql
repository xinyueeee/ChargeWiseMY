-- REVIEW ONLY: this file has not been executed against Supabase.
-- It creates a separate staging table and does not alter charging_stations.

create table if not exists public.charging_stations_mevnet_staging (
  station_id uuid primary key,
  station_name text not null,
  address text,
  latitude double precision,
  longitude double precision,
  charger_type text,
  charger_count integer not null default 0,
  ac_charger_count integer not null default 0,
  dc_charger_count integer not null default 0,
  status text not null,
  indoor_outdoor text,
  source text not null check (source = 'MEVnet / PLANMalaysia'),
  mevnet_object_id integer not null unique,
  source_url text not null,
  data_date date,
  source_data_date_original text,
  state text,
  state_original text,
  pbt text,
  pbt_code integer,
  location text,
  proposed_charger_count integer not null default 0,
  category text,
  indoor_count integer not null default 0,
  outdoor_count integer not null default 0,
  network_counts jsonb not null default '{}'::jsonb,
  coordinate_valid boolean not null default false,
  include_for_existing_coverage boolean not null default false,
  imported_at timestamptz not null default now()
);

create index if not exists mevnet_staging_status_idx
  on public.charging_stations_mevnet_staging (status);

create index if not exists mevnet_staging_state_idx
  on public.charging_stations_mevnet_staging (state);

create index if not exists mevnet_staging_coverage_idx
  on public.charging_stations_mevnet_staging (include_for_existing_coverage);

comment on table public.charging_stations_mevnet_staging is
  'Read-only staging copy of PLANMalaysia MEVnet locations. Not consumed by Flutter.';
