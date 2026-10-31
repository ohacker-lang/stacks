-- Profiles are public (see 202610280002), but follows RLS only shows a member
-- the rows they are part of, so the app could not count anyone else's
-- followers and faked the number. These functions return real counts, the
-- people behind them, and a people search that is no longer limited to
-- Discover opt-ins. They expose the same public fields as public_profiles and
-- hide blocked pairs in both directions.

create or replace function public.profile_follow_counts(target_user uuid)
returns table (followers bigint, following bigint)
language sql stable security definer set search_path = public
as $$
  select
    (select count(*) from public.follows f
      where f.followed_user_id = target_user
        and not public.is_blocked_pair(f.follower_id, auth.uid())),
    (select count(*) from public.follows f
      where f.follower_id = target_user
        and not public.is_blocked_pair(f.followed_user_id, auth.uid()))
  where not public.is_blocked_pair(target_user, auth.uid());
$$;

create or replace function public.profile_follow_list(target_user uuid, list_kind text)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_path text,
  bio text,
  link_in_bio_url text,
  is_following boolean
)
language sql stable security definer set search_path = public
as $$
  select p.id, p.display_name, p.username::text, p.avatar_path, p.bio, p.link_in_bio_url,
    exists (
      select 1 from public.follows mine
      where mine.follower_id = auth.uid() and mine.followed_user_id = p.id
    )
  from public.follows f
  join public.profiles p
    on p.id = case when list_kind = 'followers' then f.follower_id else f.followed_user_id end
  where list_kind in ('followers', 'following')
    and target_user = case when list_kind = 'followers' then f.followed_user_id else f.follower_id end
    and not public.is_blocked_pair(target_user, auth.uid())
    and not public.is_blocked_pair(p.id, auth.uid())
  order by f.created_at desc
  limit 200;
$$;

create or replace function public.search_profiles(search_text text)
returns table (
  id uuid,
  display_name text,
  username text,
  avatar_path text,
  bio text,
  link_in_bio_url text,
  is_following boolean
)
language sql stable security definer set search_path = public
as $$
  with term as (
    select '%' || replace(replace(replace(trim(ltrim(trim(search_text), '@')), '\', '\\'), '%', '\%'), '_', '\_') || '%' as pattern
  )
  select p.id, p.display_name, p.username::text, p.avatar_path, p.bio, p.link_in_bio_url,
    exists (
      select 1 from public.follows mine
      where mine.follower_id = auth.uid() and mine.followed_user_id = p.id
    )
  from public.profiles p, term
  where length(trim(ltrim(trim(search_text), '@'))) > 0
    and p.id <> auth.uid()
    and p.onboarding_completed_at is not null
    and (p.username::text ilike term.pattern or p.display_name ilike term.pattern)
    and not public.is_blocked_pair(p.id, auth.uid())
  order by (p.username::text ilike ltrim(trim(search_text), '@')) desc, p.username
  limit 20;
$$;

revoke all on function public.profile_follow_counts(uuid) from public, anon;
revoke all on function public.profile_follow_list(uuid, text) from public, anon;
revoke all on function public.search_profiles(text) from public, anon;
grant execute on function public.profile_follow_counts(uuid) to authenticated;
grant execute on function public.profile_follow_list(uuid, text) to authenticated;
grant execute on function public.search_profiles(text) to authenticated;
