-- READ ONLY. Run after staging import and before approving production migration.

select count(*) as staging_row_count
from public.charging_stations_mevnet_staging;

select status, count(*) as location_count
from public.charging_stations_mevnet_staging
group by status
order by status;

select
  count(*) filter (where include_for_existing_coverage) as production_candidates,
  count(*) filter (
    where include_for_existing_coverage
      and (status <> 'Existing' or not coordinate_valid)
  ) as invalid_candidates,
  sum(charger_count) filter (where include_for_existing_coverage)
    as existing_chargers_represented,
  sum(ac_charger_count) filter (where include_for_existing_coverage)
    as ac_chargers_represented,
  sum(dc_charger_count) filter (where include_for_existing_coverage)
    as dc_chargers_represented,
  count(*) filter (where address is not null) as fabricated_address_count
from public.charging_stations_mevnet_staging;

select count(*) as current_production_station_count
from public.charging_stations;

select
  count(*) as saved_stations_row_count,
  count(cs.station_id) as references_current_station,
  count(*) - count(cs.station_id) as orphaned_station_reference
from public.saved_stations saved
left join public.charging_stations cs on cs.station_id = saved.station_id;

select
  count(*) as charging_sessions_row_count,
  count(*) filter (where session.station_id is not null)
    as rows_with_station_id,
  count(cs.station_id) as references_current_station,
  count(*) filter (
    where session.station_id is not null and cs.station_id is null
  ) as orphaned_station_reference
from public.charging_sessions session
left join public.charging_stations cs on cs.station_id = session.station_id;

select
  constraint_record.conname as constraint_name,
  constraint_record.conrelid::regclass as referencing_table,
  constraint_record.confrelid::regclass as referenced_table,
  pg_get_constraintdef(constraint_record.oid) as definition
from pg_constraint constraint_record
where constraint_record.contype = 'f'
  and (
    constraint_record.conrelid = 'public.charging_stations'::regclass
    or constraint_record.confrelid = 'public.charging_stations'::regclass
  )
order by constraint_record.conrelid::regclass::text, constraint_name;

select
  constraint_record.conname as constraint_name,
  constraint_record.conrelid::regclass as referencing_table,
  pg_get_constraintdef(constraint_record.oid) as definition
from pg_constraint constraint_record
where constraint_record.contype = 'f'
  and constraint_record.confrelid = 'public.charging_stations'::regclass
  and constraint_record.conrelid not in (
    'public.saved_stations'::regclass,
    'public.charging_sessions'::regclass
  )
order by constraint_record.conrelid::regclass::text, constraint_name;

select
  column_name,
  data_type,
  is_nullable,
  column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'charging_stations'
  and column_name in ('status', 'station_id', 'available_ports', 'address')
order by column_name;

select
  constraint_record.conname as constraint_name,
  constraint_record.contype as constraint_type,
  pg_get_constraintdef(constraint_record.oid) as definition
from pg_constraint constraint_record
where constraint_record.conrelid = 'public.charging_stations'::regclass
  and (
    pg_get_constraintdef(constraint_record.oid) ilike '%status%'
    or pg_get_constraintdef(constraint_record.oid) ilike '%station_id%'
    or pg_get_constraintdef(constraint_record.oid) ilike '%available_ports%'
    or pg_get_constraintdef(constraint_record.oid) ilike '%address%'
  )
order by constraint_name;

select
  table_name,
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'charging_sessions' and column_name = 'station_id')
    or (table_name = 'saved_stations' and column_name = 'station_id')
  )
order by table_name;

select
  to_regclass('chargewise_backup.charging_stations_pre_mevnet_20260821')
    as station_backup_already_exists,
  to_regclass('chargewise_backup.saved_stations_pre_mevnet_20260821')
    as saved_station_backup_already_exists,
  to_regclass('chargewise_backup.charging_sessions_pre_mevnet_20260821')
    as charging_session_backup_already_exists;
