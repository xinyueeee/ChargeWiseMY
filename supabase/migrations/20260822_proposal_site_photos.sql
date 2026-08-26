begin;

alter table public.proposals
  add column if not exists site_photo_path text;

comment on column public.proposals.site_photo_path is
  'Private Supabase Storage object path for optional proposal site evidence. Never store signed URLs here.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'proposals_site_photo_path_owner_check'
      and conrelid = 'public.proposals'::regclass
  ) then
    alter table public.proposals
      add constraint proposals_site_photo_path_owner_check
      check (
        site_photo_path is null
        or (
          site_photo_path like user_id::text || '/' || proposal_id::text || '/%'
          and site_photo_path not like '%..%'
        )
      );
  end if;
end
$$;

do $$
begin
  if exists (
    select 1 from storage.buckets
    where id = 'proposal-site-photos' and public
  ) then
    raise exception
      'Existing proposal-site-photos bucket is public; review it manually before continuing.';
  end if;
end
$$;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'proposal-site-photos',
  'proposal-site-photos',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'proposal_site_photos_owner_insert'
  ) then
    create policy proposal_site_photos_owner_insert
      on storage.objects
      for insert
      to authenticated
      with check (
        bucket_id = 'proposal-site-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
        and exists (
          select 1
          from public.proposals proposal
          where proposal.proposal_id::text = (storage.foldername(name))[2]
            and proposal.user_id = auth.uid()
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'proposal_site_photos_owner_admin_select'
  ) then
    create policy proposal_site_photos_owner_admin_select
      on storage.objects
      for select
      to authenticated
      using (
        bucket_id = 'proposal-site-photos'
        and (
          (storage.foldername(name))[1] = auth.uid()::text
          or exists (
            select 1
            from public.users app_user
            where app_user.id = auth.uid()
              and app_user.role = 'admin'
          )
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'proposal_site_photos_owner_delete'
  ) then
    create policy proposal_site_photos_owner_delete
      on storage.objects
      for delete
      to authenticated
      using (
        bucket_id = 'proposal-site-photos'
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;
end
$$;

commit;
