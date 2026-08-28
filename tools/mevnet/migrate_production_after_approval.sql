-- DANGEROUS / NOT EXECUTED.
-- Run only after staging validation, coordinated Flutter compatibility review,
-- a maintenance window, and explicit user approval.

begin;
select pg_advisory_xact_lock(hashtext('chargewise-mevnet-production-migration-v1'));

do $$
declare
  candidate_count integer;
  invalid_candidate_count integer;
  charger_total integer;
  ac_charger_total integer;
  dc_charger_total integer;
begin
  select
    count(*) filter (where include_for_existing_coverage),
    count(*) filter (
      where include_for_existing_coverage
        and (status <> 'Existing' or not coordinate_valid)
    ),
    coalesce(sum(charger_count) filter (
      where include_for_existing_coverage
    ), 0),
    coalesce(sum(ac_charger_count) filter (
      where include_for_existing_coverage
    ), 0),
    coalesce(sum(dc_charger_count) filter (
      where include_for_existing_coverage
    ), 0)
  into candidate_count, invalid_candidate_count, charger_total,
       ac_charger_total, dc_charger_total
  from public.charging_stations_mevnet_staging;

  if candidate_count <> 1374 then
    raise exception 'Expected 1374 MEVnet Existing candidates, found %', candidate_count;
  end if;
  if invalid_candidate_count <> 0 then
    raise exception 'Invalid/non-Existing rows are marked for coverage: %', invalid_candidate_count;
  end if;
  if charger_total <> 4161 then
    raise exception 'Expected 4161 installed chargers, found %', charger_total;
  end if;
  if ac_charger_total <> 2857 then
    raise exception 'Expected 2857 AC chargers, found %', ac_charger_total;
  end if;
  if dc_charger_total <> 1304 then
    raise exception 'Expected 1304 DC chargers, found %', dc_charger_total;
  end if;
  if to_regclass('chargewise_backup.charging_stations_pre_mevnet_20260821') is not null then
    raise exception 'MEVnet backup already exists; migration may already have run';
  end if;
  if to_regclass('chargewise_backup.saved_stations_pre_mevnet_20260821') is not null
     or to_regclass('chargewise_backup.charging_sessions_pre_mevnet_20260821') is not null then
    raise exception 'A required MEVnet relationship backup already exists; stop for manual review';
  end if;
end $$;

create schema if not exists chargewise_backup;
revoke all on schema chargewise_backup from public, anon, authenticated;

create table chargewise_backup.charging_stations_pre_mevnet_20260821
  as table public.charging_stations;
create table chargewise_backup.saved_stations_pre_mevnet_20260821
  as table public.saved_stations;
create table chargewise_backup.charging_sessions_pre_mevnet_20260821
  as table public.charging_sessions;

alter table public.charging_stations
  add column if not exists charger_count integer,
  add column if not exists ac_charger_count integer,
  add column if not exists dc_charger_count integer,
  add column if not exists state text,
  add column if not exists pbt text,
  add column if not exists category text,
  add column if not exists mevnet_object_id integer,
  add column if not exists source text,
  add column if not exists source_url text,
  add column if not exists data_date date,
  add column if not exists imported_at timestamptz,
  add column if not exists network_counts jsonb;

-- MEVnet has no verified postal-address field. Keep it nullable.
alter table public.charging_stations alter column address drop not null;

-- Keep this deprecated column temporarily so the currently deployed Flutter
-- query remains compatible. Every MEVnet value is deliberately null because
-- installed charger count is not real-time availability.
alter table public.charging_stations alter column available_ports drop not null;

-- Old station IDs cannot be safely mapped because the legacy spatial records
-- are unreliable. Backups above preserve every relationship before detaching.
delete from public.saved_stations;
update public.charging_sessions set station_id = null where station_id is not null;
delete from public.charging_stations;

insert into public.charging_stations (
  station_id,
  station_name,
  address,
  latitude,
  longitude,
  charger_type,
  available_ports,
  charger_count,
  ac_charger_count,
  dc_charger_count,
  status,
  indoor_outdoor,
  state,
  pbt,
  category,
  mevnet_object_id,
  source,
  source_url,
  data_date,
  imported_at,
  network_counts,
  created_at
)
select
  station_id,
  station_name,
  null,
  latitude,
  longitude,
  charger_type,
  null,
  charger_count,
  ac_charger_count,
  dc_charger_count,
  'Existing',
  nullif(indoor_outdoor, ''),
  state,
  nullif(pbt, ''),
  nullif(category, ''),
  mevnet_object_id,
  'MEVnet / PLANMalaysia',
  source_url,
  data_date,
  now(),
  network_counts,
  now()
from public.charging_stations_mevnet_staging
where include_for_existing_coverage
order by mevnet_object_id;

alter table public.charging_stations
  alter column charger_count set not null,
  alter column ac_charger_count set not null,
  alter column dc_charger_count set not null,
  alter column state set not null,
  alter column mevnet_object_id set not null,
  alter column source set not null,
  alter column source_url set not null,
  alter column imported_at set not null,
  alter column network_counts set not null;

alter table public.charging_stations
  add constraint charging_stations_mevnet_object_id_key unique (mevnet_object_id),
  add constraint charging_stations_existing_only_check check (status = 'Existing'),
  add constraint charging_stations_charger_counts_check check (
    charger_count >= 0
    and ac_charger_count >= 0
    and dc_charger_count >= 0
    and charger_count = ac_charger_count + dc_charger_count
  ),
  add constraint charging_stations_mevnet_source_check check (
    source = 'MEVnet / PLANMalaysia'
  ),
  add constraint charging_stations_latitude_check check (
    latitude between 0.5 and 7.6
  ),
  add constraint charging_stations_longitude_check check (
    longitude between 99.5 and 120.0
  );

do $$
declare
  location_count integer;
  installed_charger_total integer;
  ac_charger_total integer;
  dc_charger_total integer;
  non_existing_status_count integer;
  incorrect_source_count integer;
  duplicate_mevnet_object_id_count integer;
  duplicate_station_id_count integer;
  null_coordinate_count integer;
begin
  select
    count(*),
    coalesce(sum(charger_count), 0),
    coalesce(sum(ac_charger_count), 0),
    coalesce(sum(dc_charger_count), 0),
    count(*) filter (where status <> 'Existing'),
    count(*) filter (where source <> 'MEVnet / PLANMalaysia'),
    count(*) - count(distinct mevnet_object_id),
    count(*) - count(distinct station_id),
    count(*) filter (where latitude is null or longitude is null)
  into location_count, installed_charger_total, ac_charger_total,
       dc_charger_total, non_existing_status_count, incorrect_source_count,
       duplicate_mevnet_object_id_count, duplicate_station_id_count,
       null_coordinate_count
  from public.charging_stations;

  if location_count <> 1374 then
    raise exception 'Post-migration location count mismatch: %', location_count;
  end if;
  if installed_charger_total <> 4161 then
    raise exception 'Post-migration installed charger total mismatch: %', installed_charger_total;
  end if;
  if ac_charger_total <> 2857 then
    raise exception 'Post-migration AC charger total mismatch: %', ac_charger_total;
  end if;
  if dc_charger_total <> 1304 then
    raise exception 'Post-migration DC charger total mismatch: %', dc_charger_total;
  end if;
  if non_existing_status_count <> 0 then
    raise exception 'Post-migration non-Existing status count: %', non_existing_status_count;
  end if;
  if incorrect_source_count <> 0 then
    raise exception 'Post-migration incorrect source count: %', incorrect_source_count;
  end if;
  if duplicate_mevnet_object_id_count <> 0 then
    raise exception 'Post-migration duplicate MEVnet object IDs: %', duplicate_mevnet_object_id_count;
  end if;
  if duplicate_station_id_count <> 0 then
    raise exception 'Post-migration duplicate station IDs: %', duplicate_station_id_count;
  end if;
  if null_coordinate_count <> 0 then
    raise exception 'Post-migration null latitude/longitude count: %', null_coordinate_count;
  end if;
end $$;

commit;

select count(*) as production_existing_locations,
       sum(charger_count) as installed_chargers
from public.charging_stations;
