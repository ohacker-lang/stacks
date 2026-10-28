-- Do not disclose whether a specific email address is on the waitlist.
create or replace function public.reserve_waitlist_username(p_username text, p_email text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text := pg_catalog.lower(pg_catalog.btrim(p_username));
  normalized_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
begin
  if p_username is null or normalized_username !~ '^[a-z0-9_]{3,30}$'
    or normalized_username in ('admin', 'api', 'help', 'root', 'stacks', 'support', 'www') then
    return 'invalid_username';
  end if;
  if p_email is null or pg_catalog.length(normalized_email) > 254
    or normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then
    return 'invalid_email';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stacks_username:' || normalized_username, 0)
  );

  if exists (select 1 from public.profiles where username = normalized_username::public.citext)
    or exists (select 1 from public.waitlist_entries where username = normalized_username::public.citext) then
    return 'username_taken';
  end if;
  if exists (select 1 from public.waitlist_entries where email = normalized_email::public.citext) then
    return 'already_taken';
  end if;

  insert into public.waitlist_entries (username, email)
  values (normalized_username, normalized_email);
  return 'joined';
exception
  when unique_violation then
    return 'already_taken';
end;
$$;

revoke all on function public.reserve_waitlist_username(text, text) from public;
grant execute on function public.reserve_waitlist_username(text, text) to anon;
