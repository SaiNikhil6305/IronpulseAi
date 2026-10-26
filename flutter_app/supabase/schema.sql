-- IronPulse cloud backup schema. Run once in Supabase: Dashboard -> SQL Editor -> New query -> Run.
-- One private backup row per user. Row Level Security: each user can only see/change their own row.

create table if not exists public.backups (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  data        jsonb not null,
  app_version text not null,
  size_bytes  integer not null check (size_bytes >= 0 and size_bytes <= 20000000),
  updated_at  timestamptz not null default now()
);

alter table public.backups enable row level security;

drop policy if exists "own backup - read"   on public.backups;
drop policy if exists "own backup - insert" on public.backups;
drop policy if exists "own backup - update" on public.backups;
drop policy if exists "own backup - delete" on public.backups;

create policy "own backup - read"   on public.backups for select to authenticated using (user_id = (select auth.uid()));
create policy "own backup - insert" on public.backups for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own backup - update" on public.backups for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own backup - delete" on public.backups for delete to authenticated using (user_id = (select auth.uid()));

-- Nobody signed out can touch the table.
revoke all on public.backups from anon;

-- "Delete my cloud account": removes the caller's login (backup row cascades). Runs with owner
-- rights but only ever deletes auth.uid(), so a user can delete only themselves.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
