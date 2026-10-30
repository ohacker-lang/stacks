-- Stacks works like Pinterest: every account has a public page at
-- stacks.spot/username, and new Stacks appear on it unless the owner chooses
-- Private or link-only.
--
-- Existing Stacks keep their current visibility. They were created while
-- private was the default, so flipping them would expose things people chose
-- not to share.

alter table public.stacks
  alter column visibility set default 'public';

-- The profile page itself is no longer opt-in. web-preview no longer reads
-- this flag; it is kept true so older app builds show the right state.
alter table public.profiles
  alter column profile_share_enabled set default true;

update public.profiles
  set profile_share_enabled = true
  where profile_share_enabled = false;

-- The app reads other people's profile rows only through Discover opt-in or a
-- shared Collab. Now that every profile is public on the web, signed-in users
-- may read the same public fields (never email, legal or onboarding state),
-- so public Stacks show their real author and stacks.spot/username links can
-- open the profile in the app. Blocked pairs stay hidden from each other.
create or replace function public.public_profiles(target_ids uuid[])
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_path text,
  bio text,
  link_in_bio_url text
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.display_name, p.username::text, p.avatar_path, p.bio, p.link_in_bio_url
  from public.profiles p
  where p.id = any(target_ids[1:200])
    and not public.is_blocked_pair(p.id, auth.uid());
$$;

create or replace function public.public_profile_by_username(target_username text)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_path text,
  bio text,
  link_in_bio_url text
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.display_name, p.username::text, p.avatar_path, p.bio, p.link_in_bio_url
  from public.profiles p
  where p.username = target_username::citext
    and not public.is_blocked_pair(p.id, auth.uid());
$$;

revoke all on function public.public_profiles(uuid[]) from public;
revoke all on function public.public_profile_by_username(text) from public;
grant execute on function public.public_profiles(uuid[]) to authenticated;
grant execute on function public.public_profile_by_username(text) to authenticated;
