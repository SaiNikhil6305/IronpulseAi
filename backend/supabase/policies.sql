-- IronPulse Supabase security policies. Run in the Supabase SQL editor AFTER `alembic upgrade head`.
--
-- Data-access model
-- * The mobile app NEVER reads or writes application tables through PostgREST. All data goes through the
--   FastAPI backend, which verifies the user's JWT and scopes every query by user id.
-- * The backend connects with the database owner role (DATABASE_URL), which bypasses RLS.
-- * Defence in depth: RLS is enabled on every application table with NO policies for `anon` or
--   `authenticated`, and table privileges are revoked, so a leaked anon key or a user JWT used directly
--   against PostgREST cannot read or modify any row.
-- * Progress photos are stored in a PRIVATE storage bucket. Users may only touch objects under a folder
--   named after their own auth.uid().

do $$
declare t text;
begin
  for t in
    select tablename from pg_tables
    where schemaname = 'public' and tablename <> 'alembic_version'
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
    execute format('revoke all on table public.%I from anon, authenticated', t);
  end loop;
end $$;

-- alembic_version is not user data but should not be exposed either.
revoke all on table public.alembic_version from anon, authenticated;

-- Shared read-only catalogue could be exposed, but the app fetches it through the API; keep it closed.

-- ---------------------------------------------------------------------------------------------
-- Private storage for progress photos
-- ---------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('progress-photos', 'progress-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "progress photos: owner read" on storage.objects;
drop policy if exists "progress photos: owner insert" on storage.objects;
drop policy if exists "progress photos: owner update" on storage.objects;
drop policy if exists "progress photos: owner delete" on storage.objects;

create policy "progress photos: owner read" on storage.objects for select to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "progress photos: owner insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "progress photos: owner update" on storage.objects for update to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "progress photos: owner delete" on storage.objects for delete to authenticated
  using (bucket_id = 'progress-photos' and (storage.foldername(name))[1] = auth.uid()::text);
