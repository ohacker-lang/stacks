-- An inviter may have invited someone to a Stack they do not own. Retaining
-- that historical inviter ID must not prevent the inviter from deleting their
-- account and its profile row.
alter table public.stack_collaborators
  drop constraint if exists stack_collaborators_invited_by_fkey;

alter table public.stack_collaborators
  alter column invited_by drop not null;

alter table public.stack_collaborators
  add constraint stack_collaborators_invited_by_fkey
  foreign key (invited_by) references public.profiles(id) on delete set null;
