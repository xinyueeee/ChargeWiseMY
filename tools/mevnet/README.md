# MEVnet staging export

This workflow reads the public PLANMalaysia MEVnet FeatureServer and creates
local review artifacts. It does not connect to Supabase and cannot modify the
production `charging_stations` table.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File tools/mevnet/export_mevnet_staging.ps1
```

Generated files under `tools/mevnet/staging/`:

- `mevnet_raw.json`: source attributes exactly as returned by MEVnet.
- `mevnet_staging.json`: transformed rows, including network-count metadata.
- `mevnet_staging.csv`: flat staging import file.
- `mevnet_summary.json`: reproducible validation summary.

The export uses the MEVnet `latitude` and `longitude` attributes. It requests
`returnGeometry=false`, so projected ArcGIS geometry cannot be used by mistake.

Only rows whose MEVnet status is exactly `Existing` and whose coordinates are
valid receive `include_for_existing_coverage=true`. `Newly Proposed` rows remain
available for review but must not be inserted into the current production table,
because the Flutter data layer currently treats every `charging_stations` row as
existing coverage.

`address` remains null. MEVnet does not provide a separate verified street-address
field. PBT and state are stored in their own fields and are never presented as a
fabricated postal address.

`create_staging_table.sql` is intentionally separate and has not been executed.
It creates a staging table only; it does not delete, truncate, update, or replace
the existing production dataset.

After reviewing the local export, the optional Supabase staging-only import is:

```powershell
psql $env:SUPABASE_DB_URL -f tools/mevnet/create_staging_table.sql
psql $env:SUPABASE_DB_URL -f tools/mevnet/import_staging.psql
```

`import_staging.psql` truncates only `charging_stations_mevnet_staging` to make
the staging sync reproducible. It never changes `public.charging_stations`.

## Current Flutter compatibility mapping

| Current column | MEVnet transformation |
| --- | --- |
| `station_id` | deterministic UUID derived from MEVnet `objectid` |
| `station_name` | `location` |
| `address` | null; MEVnet has no verified postal-address field |
| `latitude` / `longitude` | MEVnet attributes; projected geometry is not requested |
| `charger_type` | derived from `type_ac` and `type_dc` |
| `charger_count` | `number_of_existing_ev_charger_s` |
| `ac_charger_count` | `type_ac` |
| `dc_charger_count` | `type_dc` |
| `status` | original MEVnet status |
| `indoor_outdoor` | `indoor___outdoor` |

The eventual production candidate must select only:

```sql
where include_for_existing_coverage = true
```

This yields valid-coordinate `Existing` MEVnet locations only. Promoting or
swapping that candidate into production requires a separate reviewed migration;
no production migration is included or executed in this phase.
