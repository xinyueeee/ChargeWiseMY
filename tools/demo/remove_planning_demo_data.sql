-- DEMO ONLY: removes only the records reserved by create_planning_demo_data.sql.
-- Run manually in the Supabase SQL Editor.

begin;

do $$
declare
  demo_proposal_ids constant uuid[] := array[
    'd3e00000-0000-4000-8000-000000000001'::uuid,
    'd3e00000-0000-4000-8000-000000000002'::uuid,
    'd3e00000-0000-4000-8000-000000000003'::uuid,
    'd3e00000-0000-4000-8000-000000000004'::uuid,
    'd3e00000-0000-4000-8000-000000000005'::uuid,
    'd3e00000-0000-4000-8000-000000000006'::uuid,
    'd3e00000-0000-4000-8000-000000000007'::uuid,
    'd3e00000-0000-4000-8000-000000000008'::uuid,
    'd3e00000-0000-4000-8000-000000000009'::uuid
  ];
  removed_reactions integer;
  removed_proposals integer;
begin
  delete from public.proposal_reactions
  where proposal_id = any(demo_proposal_ids);
  get diagnostics removed_reactions = row_count;

  delete from public.proposals
  where proposal_id = any(demo_proposal_ids)
    and title like 'Demo – %';
  get diagnostics removed_proposals = row_count;

  raise notice 'Removed % demo reactions and % demo proposals.',
    removed_reactions, removed_proposals;
end
$$;

commit;

