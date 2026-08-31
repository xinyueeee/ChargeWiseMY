
begin;

alter table public.users
  add column if not exists status text not null default 'active'
  check (status in ('active', 'deactivated'));

comment on column public.users.status is
  'Set by an admin via the Manage Users screen (through set_user_status(),
  never a direct update). Deactivated accounts are blocked at login
  (checked client-side in AuthService.login) rather than by RLS, since the
  account still needs to read its own row to learn it is deactivated.';


drop policy if exists "users_admin_full_access" on public.users;
drop policy if exists "users_admin_read_all" on public.users;
create policy "users_admin_read_all"
  on public.users for select
  to authenticated
  using (is_admin());

create or replace function set_user_status(
  target_user_id uuid,
  new_status text
) returns void as $$
begin
  if not is_admin() then
    raise exception 'Only admins can change account status.';
  end if;
  if new_status not in ('active', 'deactivated') then
    raise exception 'Invalid status value.';
  end if;
  if new_status = 'deactivated' and target_user_id = auth.uid() then
    raise exception 'You cannot deactivate your own account.';
  end if;

  update public.users set status = new_status where id = target_user_id;
end;
$$ language plpgsql security definer;

grant execute on function set_user_status(uuid, text) to authenticated;

commit;