-- DEMO ONLY: deterministic Infrastructure Planning proposal/reaction data.
-- Run manually in the Supabase SQL Editor after replacing demo_user_ids below
-- with exactly 4 unique UUIDs belonging exclusively to existing demo/test accounts.
-- This script never creates auth users and never fabricates Storage paths.

begin;

do $$
declare
  -- REQUIRED MANUAL INPUT. Do not use real production-user UUIDs.
  demo_user_ids uuid[] := array[]::uuid[];
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
  -- Each support + oppose total is at most four, so the same four users can
  -- safely be reused for different proposals without duplicate per-proposal
  -- reactions.
  support_counts constant integer[] := array[3, 2, 4, 1, 3, 2, 1, 3, 2];
  oppose_counts constant integer[] := array[1, 2, 0, 3, 1, 1, 2, 0, 2];
  proposal_index integer;
  reaction_index integer;
  existing_demo_users integer;
  existing_auth_users integer;
  unique_demo_users integer;
  conflicting_ids integer;
begin
  if coalesce(cardinality(demo_user_ids), 0) <> 4 then
    raise exception
      'DEMO setup aborted: provide exactly 4 unique existing demo/test user UUIDs in demo_user_ids.';
  end if;

  select count(distinct user_id) into unique_demo_users
  from unnest(demo_user_ids) as demo_user(user_id);

  if unique_demo_users <> cardinality(demo_user_ids) then
    raise exception
      'DEMO setup aborted: demo_user_ids must not contain duplicate UUIDs.';
  end if;

  select count(*) into existing_demo_users
  from public.users
  where id = any(demo_user_ids);

  select count(*) into existing_auth_users
  from auth.users
  where id = any(demo_user_ids);

  if existing_demo_users <> cardinality(demo_user_ids)
     or existing_auth_users <> cardinality(demo_user_ids) then
    raise exception
      'DEMO setup aborted: every supplied UUID must already exist in both auth.users and public.users.';
  end if;

  select count(*) into conflicting_ids
  from public.proposals
  where proposal_id = any(demo_proposal_ids)
    and title not like 'Demo – %';

  if conflicting_ids > 0 then
    raise exception
      'DEMO setup aborted: a reserved demo proposal UUID belongs to non-demo data.';
  end if;

  insert into public.proposals (
    proposal_id,
    user_id,
    title,
    description,
    address,
    latitude,
    longitude,
    charger_type,
    expected_demand,
    status,
    created_at,
    site_photo_path
  ) values
    (demo_proposal_ids[1], demo_user_ids[1],
     'Demo – Bukit Bintang EV Charging Proposal',
     'Demo proposal for reviewing public charging coverage near a central commercial area.',
     'Bukit Bintang, Kuala Lumpur', 3.1466, 101.7108,
     'DC Fast Charger', 3, 'Pending', now() - interval '2 days', null),
    (demo_proposal_ids[2], demo_user_ids[2],
     'Demo – Shah Alam Community Charging Hub',
     'Demo proposal for a shared charging location serving nearby community facilities.',
     'Shah Alam, Selangor', 3.0738, 101.5183,
     'AC Charger', 2, 'Pending', now() - interval '4 days', null),
    (demo_proposal_ids[3], demo_user_ids[3],
     'Demo – Penang Urban Charging Point',
     'Demo proposal for an additional urban charging location within George Town.',
     'George Town, Penang', 5.4141, 100.3288,
     'DC Fast Charger', 3, 'Under Review', now() - interval '7 days', null),
    (demo_proposal_ids[4], demo_user_ids[4],
     'Demo – Johor Bahru Public Charging Bay',
     'Demo proposal for public charging bays near municipal and retail services.',
     'Johor Bahru, Johor', 1.4927, 103.7414,
     'DC Fast Charger', 3, 'Under Review', now() - interval '9 days', null),
    (demo_proposal_ids[5], demo_user_ids[1],
     'Demo – Melaka Sentral Charging Proposal',
     'Demo proposal for a charging location near a regional transport interchange.',
     'Melaka Sentral, Melaka', 2.2167, 102.2492,
     'AC Charger', 2, 'Under Review', now() - interval '11 days', null),
    (demo_proposal_ids[6], demo_user_ids[2],
     'Demo – Ipoh Civic Charging Location',
     'Demo proposal for accessible charging near civic services in central Ipoh.',
     'Ipoh, Perak', 4.5975, 101.0901,
     'DC Fast Charger', 2, 'Approved', now() - interval '16 days', null),
    (demo_proposal_ids[7], demo_user_ids[3],
     'Demo – Kota Kinabalu Community Charger',
     'Demo proposal for a community-facing charging location in Kota Kinabalu.',
     'Kota Kinabalu, Sabah', 5.9804, 116.0735,
     'AC Charger', 3, 'Approved', now() - interval '21 days', null),
    (demo_proposal_ids[8], demo_user_ids[4],
     'Demo – Kuching Riverside Charging Point',
     'Demo proposal used to review an unsuitable or lower-priority location.',
     'Kuching, Sarawak', 1.5533, 110.3592,
     'DC Fast Charger', 2, 'Rejected', now() - interval '25 days', null),
    (demo_proposal_ids[9], demo_user_ids[1],
     'Demo – Alor Setar Neighbourhood Charger',
     'Demo proposal used to review community feedback and administrative rejection.',
     'Alor Setar, Kedah', 6.1248, 100.3678,
     'AC Charger', 1, 'Rejected', now() - interval '30 days', null)
  on conflict (proposal_id) do update set
    user_id = excluded.user_id,
    title = excluded.title,
    description = excluded.description,
    address = excluded.address,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    charger_type = excluded.charger_type,
    expected_demand = excluded.expected_demand,
    status = excluded.status,
    created_at = excluded.created_at,
    site_photo_path = null;

  -- Rebuild only reactions belonging to the reserved demo proposal IDs.
  delete from public.proposal_reactions
  where proposal_id = any(demo_proposal_ids);

  for proposal_index in 1..cardinality(demo_proposal_ids) loop
    for reaction_index in 1..support_counts[proposal_index] loop
      insert into public.proposal_reactions (
        reaction_id, proposal_id, user_id, reaction, created_at
      ) values (
        gen_random_uuid(),
        demo_proposal_ids[proposal_index],
        demo_user_ids[reaction_index],
        'Like',
        now() - make_interval(days => 1 + proposal_index)
      );
    end loop;

    for reaction_index in 1..oppose_counts[proposal_index] loop
      insert into public.proposal_reactions (
        reaction_id, proposal_id, user_id, reaction, created_at
      ) values (
        gen_random_uuid(),
        demo_proposal_ids[proposal_index],
        demo_user_ids[support_counts[proposal_index] + reaction_index],
        'Dislike',
        now() - make_interval(days => 1 + proposal_index)
      );
    end loop;
  end loop;

  raise notice 'Created/refreshed 9 demo proposals and their deterministic reaction distributions.';
end
$$;

commit;
