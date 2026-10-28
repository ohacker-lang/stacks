-- Website waitlist reservations use the same username namespace as app profiles.
-- Emails are private: anonymous clients may call only the narrow RPCs below.
create table public.waitlist_entries (
  id bigint generated always as identity primary key,
  username public.citext not null unique,
  email public.citext not null unique,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz
);

alter table public.waitlist_entries enable row level security;
revoke all on public.waitlist_entries from public, anon, authenticated;
revoke all on sequence public.waitlist_entries_id_seq from public, anon, authenticated;

create or replace function public.waitlist_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_username is not null
    and pg_catalog.lower(pg_catalog.btrim(p_username)) ~ '^[a-z0-9_]{3,30}$'
    and pg_catalog.lower(pg_catalog.btrim(p_username)) not in
      ('admin', 'api', 'help', 'root', 'stacks', 'support', 'www')
    and not exists (
      select 1 from public.profiles p
      where p.username = pg_catalog.lower(pg_catalog.btrim(p_username))::public.citext
    )
    and not exists (
      select 1 from public.waitlist_entries w
      where w.username = pg_catalog.lower(pg_catalog.btrim(p_username))::public.citext
    );
$$;

revoke all on function public.waitlist_username_available(text) from public;
grant execute on function public.waitlist_username_available(text) to anon, authenticated;

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

  -- Also acquired by the profile trigger below to close cross-table races.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('stacks_username:' || normalized_username, 0)
  );

  if exists (select 1 from public.profiles where username = normalized_username::public.citext)
    or exists (select 1 from public.waitlist_entries where username = normalized_username::public.citext) then
    return 'username_taken';
  end if;
  if exists (select 1 from public.waitlist_entries where email = normalized_email::public.citext) then
    return 'email_already_joined';
  end if;

  insert into public.waitlist_entries (username, email)
  values (normalized_username, normalized_email);
  return 'joined';
exception
  when unique_violation then
    -- A concurrent request may have inserted the same email or username.
    return 'already_taken';
end;
$$;

revoke all on function public.reserve_waitlist_username(text, text) from public;
grant execute on function public.reserve_waitlist_username(text, text) to anon;

create or replace function public.protect_waitlist_username()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.username is distinct from old.username then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('stacks_username:' || pg_catalog.lower(new.username::text), 0)
    );
    if exists (
      select 1 from public.waitlist_entries w
      where w.username = new.username
        and not exists (
          select 1 from auth.users u
          where u.id = new.id and u.email_confirmed_at is not null
            and pg_catalog.lower(u.email) = pg_catalog.lower(w.email::text)
        )
    ) then
      raise exception 'This username is reserved for the waitlist email address.'
        using errcode = '23505', constraint = 'waitlist_username_reserved';
    end if;
  end if;
  return new;
end;
$$;

create trigger profiles_protect_waitlist_username
before insert or update of username on public.profiles
for each row execute function public.protect_waitlist_username();

revoke all on function public.protect_waitlist_username() from public, anon, authenticated;
