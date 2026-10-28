-- Turning collaboration off suspends both editing and private Stack access
-- without deleting the roster, so the owner can restore it later.
create or replace function public.is_stack_member(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and (
        s.owner_id = auth.uid()
        or (
          s.collaboration_enabled
          and exists (
            select 1 from public.stack_collaborators c
            where c.stack_id = s.id
              and c.user_id = auth.uid()
              and c.accepted_at is not null
          )
        )
      )
  );
$$;

create or replace function public.can_view_stack(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and (
        s.owner_id = auth.uid()
        or s.visibility = 'public'
        or (
          s.collaboration_enabled
          and exists (
            select 1 from public.stack_collaborators c
            where c.stack_id = s.id
              and c.user_id = auth.uid()
              and c.accepted_at is not null
          )
        )
      )
  );
$$;

revoke all on function public.is_stack_member(uuid) from public;
revoke all on function public.can_view_stack(uuid) from public;
grant execute on function public.is_stack_member(uuid) to authenticated;
grant execute on function public.can_view_stack(uuid) to authenticated;
