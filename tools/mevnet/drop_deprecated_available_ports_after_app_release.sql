-- NOT EXECUTED.
-- Run only after every deployed Flutter version no longer selects or displays
-- available_ports and the new charger_count UI has been released.

begin;
alter table public.charging_stations drop column available_ports;
commit;
