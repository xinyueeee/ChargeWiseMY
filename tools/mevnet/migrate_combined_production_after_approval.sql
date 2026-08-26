-- DANGEROUS / NOT EXECUTED.
-- Run in Supabase SQL Editor only after reviewing the preflight output.
begin;

select pg_advisory_xact_lock(
  hashtext('chargewise-mevnet-combined-production-migration-v1')
);

do $$
declare
  source_rows bigint;
  existing_valid bigint;
  proposed_valid bigint;
  invalid_rows bigint;
  existing_evcb bigint;
  ac_evcb bigint;
  dc_evcb bigint;
  proposed_evcb bigint;
  duplicate_station_ids bigint;
  duplicate_object_ids bigint;
  current_production_rows bigint;
  current_non_existing_rows bigint;
begin
  select
    count(*),
    count(*) filter (where status = 'Existing' and coordinate_valid),
    count(*) filter (where status = 'Newly Proposed' and coordinate_valid),
    count(*) filter (where not coordinate_valid),
    coalesce(sum(charger_count) filter (where status = 'Existing' and coordinate_valid), 0),
    coalesce(sum(ac_charger_count) filter (where status = 'Existing' and coordinate_valid), 0),
    coalesce(sum(dc_charger_count) filter (where status = 'Existing' and coordinate_valid), 0),
    coalesce(sum(proposed_charger_count) filter (where status = 'Newly Proposed' and coordinate_valid), 0),
    count(*) filter (where coordinate_valid)
      - count(distinct station_id) filter (where coordinate_valid),
    count(*) filter (where coordinate_valid)
      - count(distinct mevnet_object_id) filter (where coordinate_valid)
  into source_rows, existing_valid, proposed_valid, invalid_rows,
       existing_evcb, ac_evcb, dc_evcb, proposed_evcb,
       duplicate_station_ids, duplicate_object_ids
  from public.charging_stations_mevnet_staging;

  select count(*), count(*) filter (where status <> 'Existing')
  into current_production_rows, current_non_existing_rows
  from public.charging_stations;

  if source_rows <> 4477 then
    raise exception 'Expected 4477 staging rows, found %', source_rows;
  end if;
  if current_production_rows <> 1374 or current_non_existing_rows <> 0 then
    raise exception
      'Expected current production to contain 1374 Existing rows; total=%, non-Existing=%',
      current_production_rows, current_non_existing_rows;
  end if;
  if existing_valid <> 1374 or proposed_valid <> 3100 then
    raise exception 'Valid status counts mismatch: Existing=%, Newly Proposed=%',
      existing_valid, proposed_valid;
  end if;
  if invalid_rows <> 3 then
    raise exception 'Expected 3 invalid-coordinate source rows, found %', invalid_rows;
  end if;
  if existing_evcb <> 4161 or ac_evcb <> 2857 or dc_evcb <> 1304 then
    raise exception 'Existing EVCB totals mismatch: total=%, AC=%, DC=%',
      existing_evcb, ac_evcb, dc_evcb;
  end if;
  if proposed_evcb <> 8266 then
    raise exception 'Expected 8266 proposed EVCB on valid rows, found %', proposed_evcb;
  end if;
  if duplicate_station_ids <> 0 or duplicate_object_ids <> 0 then
    raise exception 'Duplicate valid identifiers: station_id=%, mevnet_object_id=%',
      duplicate_station_ids, duplicate_object_ids;
  end if;
  if to_regclass(
    'chargewise_backup.charging_stations_pre_combined_mevnet_20260823'
  ) is not null then
    raise exception 'Combined MEVnet backup already exists; stop for review';
  end if;
end $$;

create schema if not exists chargewise_backup;
revoke all on schema chargewise_backup from public, anon, authenticated;

create table chargewise_backup.charging_stations_pre_combined_mevnet_20260823
  as table public.charging_stations;

alter table public.charging_stations
  add column if not exists proposed_charger_count integer not null default 0,
  add column if not exists charger_count integer not null default 0,
  add column if not exists ac_charger_count integer not null default 0,
  add column if not exists dc_charger_count integer not null default 0,
  add column if not exists state text,
  add column if not exists pbt text,
  add column if not exists category text,
  add column if not exists indoor_outdoor text,
  add column if not exists mevnet_object_id integer,
  add column if not exists source text,
  add column if not exists source_url text,
  add column if not exists data_date date,
  add column if not exists imported_at timestamptz,
  add column if not exists network_counts jsonb;

alter table public.charging_stations
  drop constraint if exists charging_stations_existing_only_check,
  drop constraint if exists charging_stations_charger_counts_check,
  drop constraint if exists charging_stations_status_check;

delete from public.charging_stations;

insert into public.charging_stations (
  station_id, station_name, address, latitude, longitude, charger_type,
  available_ports, charger_count, ac_charger_count, dc_charger_count,
  proposed_charger_count, status, indoor_outdoor, state, pbt, category,
  mevnet_object_id, source, source_url, data_date, imported_at,
  network_counts, created_at
)
select
  station_id,
  station_name,
  null,
  latitude,
  longitude,
  charger_type,
  null,
  case when status = 'Existing' then charger_count else 0 end,
  case when status = 'Existing' then ac_charger_count else 0 end,
  case when status = 'Existing' then dc_charger_count else 0 end,
  case when status = 'Newly Proposed' then proposed_charger_count else 0 end,
  status,
  nullif(indoor_outdoor, ''),
  state,
  nullif(pbt, ''),
  nullif(category, ''),
  mevnet_object_id,
  source,
  source_url,
  data_date,
  now(),
  network_counts,
  now()
from public.charging_stations_mevnet_staging
where coordinate_valid
  and status in ('Existing', 'Newly Proposed')
order by mevnet_object_id;

alter table public.charging_stations
  alter column charger_count set not null,
  alter column ac_charger_count set not null,
  alter column dc_charger_count set not null,
  alter column proposed_charger_count set not null,
  alter column state set not null,
  alter column mevnet_object_id set not null,
  alter column source set not null,
  alter column source_url set not null,
  alter column imported_at set not null,
  alter column network_counts set not null;

alter table public.charging_stations
  add constraint charging_stations_status_check
    check (status in ('Existing', 'Newly Proposed')),
  add constraint charging_stations_charger_counts_check check (
    charger_count >= 0
    and ac_charger_count >= 0
    and dc_charger_count >= 0
    and proposed_charger_count >= 0
    and (
      (status = 'Existing'
        and charger_count = ac_charger_count + dc_charger_count
        and proposed_charger_count = 0)
      or
      (status = 'Newly Proposed'
        and charger_count = 0
        and ac_charger_count = 0
        and dc_charger_count = 0)
    )
  );

do $$
declare
  total_rows bigint;
  existing_rows bigint;
  proposed_rows bigint;
  existing_evcb bigint;
  ac_evcb bigint;
  dc_evcb bigint;
  proposed_evcb bigint;
  invalid_rows bigint;
  duplicate_station_ids bigint;
  duplicate_object_ids bigint;
begin
  select
    count(*),
    count(*) filter (where status = 'Existing'),
    count(*) filter (where status = 'Newly Proposed'),
    coalesce(sum(charger_count) filter (where status = 'Existing'), 0),
    coalesce(sum(ac_charger_count) filter (where status = 'Existing'), 0),
    coalesce(sum(dc_charger_count) filter (where status = 'Existing'), 0),
    coalesce(sum(proposed_charger_count) filter (where status = 'Newly Proposed'), 0),
    count(*) filter (
      where latitude is null or longitude is null
         or latitude not between 0.5 and 7.6
         or longitude not between 99.5 and 120.0
    ),
    count(*) - count(distinct station_id),
    count(*) - count(distinct mevnet_object_id)
  into total_rows, existing_rows, proposed_rows, existing_evcb,
       ac_evcb, dc_evcb, proposed_evcb, invalid_rows,
       duplicate_station_ids, duplicate_object_ids
  from public.charging_stations;

  if total_rows <> 4474 or existing_rows <> 1374 or proposed_rows <> 3100 then
    raise exception 'Production row validation failed: total=%, Existing=%, Proposed=%',
      total_rows, existing_rows, proposed_rows;
  end if;
  if existing_evcb <> 4161 or ac_evcb <> 2857 or dc_evcb <> 1304 then
    raise exception 'Production Existing EVCB validation failed: total=%, AC=%, DC=%',
      existing_evcb, ac_evcb, dc_evcb;
  end if;
  if proposed_evcb <> 8266 then
    raise exception 'Production proposed EVCB validation failed: %', proposed_evcb;
  end if;
  if invalid_rows <> 0 or duplicate_station_ids <> 0 or duplicate_object_ids <> 0 then
    raise exception 'Production validity failed: invalid=%, station duplicates=%, object duplicates=%',
      invalid_rows, duplicate_station_ids, duplicate_object_ids;
  end if;
end $$;

commit;

select
  count(*) as total_locations,
  count(*) filter (where status = 'Existing') as existing_locations,
  count(*) filter (where status = 'Newly Proposed') as planned_locations,
  sum(charger_count) filter (where status = 'Existing') as installed_evcb,
  sum(proposed_charger_count) filter (
    where status = 'Newly Proposed'
  ) as proposed_evcb
from public.charging_stations;
