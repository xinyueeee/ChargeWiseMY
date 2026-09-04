-- Module 3 — Infrastructure Feedback: live status sync.
--
-- Adds `fault_reports` to the `supabase_realtime` publication so both the
-- driver app (FeedbackViewModel) and the admin portal (AdminFeedbackViewModel)
-- receive insert/update/delete events and debounce them into a silent
-- re-fetch. Table RLS still applies to realtime, so drivers only receive
-- events for rows their SELECT policy exposes (currently all rows).
--
-- Idempotent: safe to re-run.

begin;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'fault_reports'
  ) then
    alter publication supabase_realtime add table public.fault_reports;
  end if;
end $$;

commit;
