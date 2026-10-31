-- The app uploads avatars with `x-upsert: true` so a new photo replaces the
-- old one. Storage upserts run INSERT ... ON CONFLICT DO UPDATE, which also
-- needs a SELECT policy on the caller's own object. profile-media had none,
-- so every avatar upload failed RLS. The bucket stays public for reading
-- through public URLs; this only lets owners see their own rows.
create policy "users view their profile avatar"
on storage.objects for select to authenticated
using (
  bucket_id = 'profile-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
