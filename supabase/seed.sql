-- DEVELOPMENT ONLY. `supabase db reset` loads this file into a local database.
-- Never run it against staging or production. The fixture creates deterministic
-- auth users only because profiles are foreign-keyed to auth.users; it is not
-- a production login fixture.

do $$
begin
  if coalesce(current_setting('app.settings.environment', true), 'development') in ('staging', 'production') then
    raise exception 'Development seed data is disabled outside local development.';
  end if;
end;
$$;

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '10000000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'owen@example.test',
    '$2a$10$8L6JCY6r9PTFPs4mEo2JxeoqUYDpnBIZbtfmumR7IZu74pjIpxGWO',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Owen Hacker"}'::jsonb,
    now(),
    now()
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'isabella@example.test',
    '$2a$10$8L6JCY6r9PTFPs4mEo2JxeoqUYDpnBIZbtfmumR7IZu74pjIpxGWO',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"full_name":"Isabella Martinez"}'::jsonb,
    now(),
    now()
  )
on conflict (id) do nothing;

update public.profiles
set
  display_name = case id
    when '10000000-0000-4000-8000-000000000001'::uuid then 'Owen Hacker'
    when '20000000-0000-4000-8000-000000000002'::uuid then 'Isabella Martinez'
  end,
  username = case id
    when '10000000-0000-4000-8000-000000000001'::uuid then 'owen'
    when '20000000-0000-4000-8000-000000000002'::uuid then 'isabella'
  end,
  discovery_enabled = id = '20000000-0000-4000-8000-000000000002'::uuid
where id in (
  '10000000-0000-4000-8000-000000000001'::uuid,
  '20000000-0000-4000-8000-000000000002'::uuid
);

insert into public.stacks (
  id, owner_id, title, summary, visibility, wishlist_mode, public_link_token
)
values
  (
    '30000000-0000-4000-8000-000000000001',
    '10000000-0000-4000-8000-000000000001',
    'Desk Dreams',
    'Objects for a quieter desk.',
    'private',
    false,
    '40000000-0000-4000-8000-000000000001'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'Summer',
    'Things I am keeping close this season.',
    'public',
    false,
    '40000000-0000-4000-8000-000000000002'
  ),
  (
    '30000000-0000-4000-8000-000000000003',
    '20000000-0000-4000-8000-000000000002',
    'Birthday Wishes',
    'A link-only wishlist for friends.',
    'link_only',
    true,
    '40000000-0000-4000-8000-000000000003'
  )
on conflict (id) do nothing;

insert into public.stack_collaborators (stack_id, user_id, permission, invited_by, accepted_at)
values (
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000002',
  'editor',
  '10000000-0000-4000-8000-000000000001',
  now()
)
on conflict (stack_id, user_id) do nothing;

insert into public.stack_items (
  id, stack_id, title, brand, description, price, currency_code, source_url,
  buy_url, removal_status, placement_x, placement_y, placement_scale,
  rotation_degrees, has_custom_placement, source_type
)
values
  (
    '50000000-0000-4000-8000-000000000001',
    '30000000-0000-4000-8000-000000000001',
    'Desk Lamp', 'Aperture', 'A focused little pool of light.', 120.00, 'USD',
    'https://example.test/desk-lamp', 'https://example.test/desk-lamp', 'complete',
    0.25, 0.43, 1.05, -4, true, 'pasted_link'
  ),
  (
    '50000000-0000-4000-8000-000000000002',
    '30000000-0000-4000-8000-000000000002',
    'Denim Shorts', 'Sol', 'A pair for slow August afternoons.', 98.00, 'USD',
    'https://example.test/denim-shorts', 'https://example.test/denim-shorts', 'complete',
    0.50, 0.48, 1.00, 2, true, 'pasted_link'
  ),
  (
    '50000000-0000-4000-8000-000000000003',
    '30000000-0000-4000-8000-000000000003',
    'Unidentified Find', '', 'A photo saved for later.', null, null,
    null, null, 'queued', 0.50, 0.50, 1.00, 0, false, 'manual_photo'
  )
on conflict (id) do nothing;

insert into public.stack_pins (stack_id, user_id)
values ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001')
on conflict do nothing;

insert into public.follows (follower_id, followed_user_id)
values ('10000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000002')
on conflict do nothing;
