create table if not exists fault_reports (
  report_id    uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users(id) on delete cascade,

  station_id   text,

  category     text not null default 'Other',
  description  text not null default '',
  photo_urls   text[] not null default '{}',
  contact_info text,
  latitude     double precision,
  longitude    double precision,
  address      text not null default '',

  status       text not null default 'submitted'
               check (status in ('submitted', 'verified', 'in_progress', 'resolved')),

  priority     text not null default 'medium'
               check (priority in ('high', 'medium', 'low')),

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  verified_at    timestamptz,
  verified_by    uuid references users(id),
  in_progress_at timestamptz,
  resolved_at    timestamptz

);

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

-- Realtime: let driver + admin clients receive live status changes.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fault_reports'
  ) then
    alter publication supabase_realtime add table public.fault_reports;
  end if;
end $$;

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

alter table fault_reports enable row level security;

drop policy if exists "fault_reports_select_all_authenticated" on fault_reports;
create policy "fault_reports_select_all_authenticated"
  on fault_reports for select
  to authenticated
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
  using (auth.uid() = user_id and status = 'submitted')
  with check (auth.uid() = user_id);

drop policy if exists "fault_reports_delete_own_while_submitted" on fault_reports;
create policy "fault_reports_delete_own_while_submitted"
  on fault_reports for delete
  to authenticated
  using (auth.uid() = user_id and status = 'submitted');

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