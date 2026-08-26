-- DANGEROUS / NOT EXECUTED.
-- Restores the pre-MEVnet station rows and their pre-migration relationships.
\set ON_ERROR_STOP on

begin;
select pg_advisory_xact_lock(hashtext('chargewise-mevnet-production-migration-v1'));

do $$
begin
  if to_regclass('chargewise_backup.charging_stations_pre_mevnet_20260821') is null
     or to_regclass('chargewise_backup.saved_stations_pre_mevnet_20260821') is null
     or to_regclass('chargewise_backup.charging_sessions_pre_mevnet_20260821') is null then
    raise exception 'Required pre-MEVnet backup tables do not exist';
  end if;
  if to_regclass('chargewise_backup.charging_stations_mevnet_before_rollback_20260821') is not null then
    raise exception 'Rollback snapshot already exists; stop for manual review';
  end if;
end $$;

create table chargewise_backup.charging_stations_mevnet_before_rollback_20260821
  as table public.charging_stations;
create table chargewise_backup.saved_stations_mevnet_before_rollback_20260821
  as table public.saved_stations;
create table chargewise_backup.charging_sessions_mevnet_before_rollback_20260821
  as table public.charging_sessions;

delete from public.saved_stations;
update public.charging_sessions set station_id = null where station_id is not null;
delete from public.charging_stations;

alter table public.charging_stations
  drop constraint if exists charging_stations_mevnet_object_id_key,
  drop constraint if exists charging_stations_existing_only_check,
  drop constraint if exists charging_stations_charger_counts_check,
  drop constraint if exists charging_stations_mevnet_source_check,
  drop constraint if exists charging_stations_latitude_check,
  drop constraint if exists charging_stations_longitude_check;

alter table public.charging_stations
  alter column charger_count drop not null,
  alter column ac_charger_count drop not null,
  alter column dc_charger_count drop not null,
  alter column state drop not null,
  alter column mevnet_object_id drop not null,
  alter column source drop not null,
  alter column source_url drop not null,
  alter column imported_at drop not null,
  alter column network_counts drop not null;

insert into public.charging_stations (
  station_id,
  station_name,
  address,
  latitude,
  longitude,
  charger_type,
  available_ports,
  status,
  indoor_outdoor,
  created_at
)
select
  station_id,
  station_name,
  address,
  latitude,
  longitude,
  charger_type,
  available_ports,
  status,
  indoor_outdoor,
  created_at
from chargewise_backup.charging_stations_pre_mevnet_20260821;

insert into public.saved_stations
select * from chargewise_backup.saved_stations_pre_mevnet_20260821;

update public.charging_sessions current_session
set station_id = old_session.station_id
from chargewise_backup.charging_sessions_pre_mevnet_20260821 old_session
where current_session.id = old_session.id;

do $$
declare
  restored_count integer;
  backup_count integer;
begin
  select count(*) into restored_count from public.charging_stations;
  select count(*) into backup_count
  from chargewise_backup.charging_stations_pre_mevnet_20260821;
  if restored_count <> backup_count then
    raise exception 'Rollback row-count mismatch: restored %, backup %',
      restored_count, backup_count;
  end if;
end $$;

commit;
