-- Preserve access for Stacks that already had accepted collaborators before
-- the explicit collaboration switch was introduced.
update public.stacks s
set collaboration_enabled = true
where exists (
  select 1
  from public.stack_collaborators c
  where c.stack_id = s.id and c.accepted_at is not null
);
