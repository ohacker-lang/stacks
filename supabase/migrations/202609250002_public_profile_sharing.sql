-- Sharing a profile is separate from consenting to Discover indexing.
alter table public.profiles
  add column if not exists profile_share_enabled boolean not null default false;

-- Only an authenticated owner can enable their own bare /username page.
create or replace function public.enable_profile_sharing()
returns void
language plpgsql volatile security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required.' using errcode = '42501';
  end if;
  update public.profiles set profile_share_enabled = true where id = auth.uid();
  if not found then
    raise exception 'Profile unavailable.' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.enable_profile_sharing() from public;
grant execute on function public.enable_profile_sharing() to authenticated;
