-- Creating a Stack failed with "new row violates row-level security policy
-- for table stacks". The app inserts with `Prefer: return=representation`,
-- so Postgres checks the new row against the SELECT policy. That policy
-- called can_view_stack(id), which looks the Stack up again in a separate
-- query. The row being inserted isn't visible to that query yet, so the
-- check always failed. The policy now reads the row's own columns and only
-- looks up collaborators separately.
create function public.is_accepted_stack_collaborator(target_stack_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.stack_collaborators c
    where c.stack_id = target_stack_id
      and c.user_id = auth.uid()
      and c.accepted_at is not null
  );
$$;

revoke all on function public.is_accepted_stack_collaborator(uuid) from public;
grant execute on function public.is_accepted_stack_collaborator(uuid) to authenticated;

drop policy "stacks viewable when authorized" on public.stacks;
create policy "stacks viewable when authorized"
on public.stacks for select to authenticated
using (
  (
    owner_id = auth.uid()
    or visibility = 'public'
    or (collaboration_enabled and public.is_accepted_stack_collaborator(id))
  )
  and not public.is_blocked_pair(owner_id, auth.uid())
);
