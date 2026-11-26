-- Forge Davao: run this whole file once in Supabase > SQL Editor.

-- 1. Tables ---------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  name       text,
  role       text not null default 'member' check (role in ('member','coach')),
  status     text not null default 'pending' check (status in ('pending','approved','rejected')),
  member_id  text,
  created_at timestamptz not null default now()
);

create table if not exists public.docs (
  collection text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);

alter table public.profiles enable row level security;
alter table public.docs     enable row level security;

-- 2. Helpers --------------------------------------------------------------
create or replace function public.is_coach() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role = 'coach' and status = 'approved');
$$;

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and status = 'approved');
$$;

-- 3. New sign-ups start as pending members ---------------------------------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. Profile policies: nobody can edit their own status or role ------------
drop policy if exists profiles_read   on public.profiles;
drop policy if exists profiles_update on public.profiles;
create policy profiles_read   on public.profiles for select
  using (id = auth.uid() or public.is_coach());
create policy profiles_update on public.profiles for update
  using (public.is_coach()) with check (public.is_coach());

-- 5. Data policies ----------------------------------------------------------
drop policy if exists docs_read          on public.docs;
drop policy if exists docs_coach_write   on public.docs;
drop policy if exists docs_member_insert on public.docs;
drop policy if exists docs_member_update on public.docs;

-- Coaches read everything. Approved members read shared data plus their own docs.
create policy docs_read on public.docs for select using (
  public.is_coach()
  or (public.is_approved() and (
        collection in ('members','schedule','workouts','announcements','scores','reservations')
        or (collection in ('claims','prs','logs','mydues') and id = auth.uid()::text)
     ))
);

-- Coaches write everything.
create policy docs_coach_write on public.docs for all
  using (public.is_coach()) with check (public.is_coach());

-- Members write only their own doc in these collections.
create policy docs_member_insert on public.docs for insert with check (
  public.is_approved() and id = auth.uid()::text
  and collection in ('prs','reservations','scores','logs')
);
create policy docs_member_update on public.docs for update
  using (public.is_approved() and id = auth.uid()::text
         and collection in ('prs','reservations','scores','logs'))
  with check (public.is_approved() and id = auth.uid()::text
         and collection in ('prs','reservations','scores','logs'));

-- 6. "Log once": members cannot change or remove a logged score ----------------
create or replace function public.protect_entries() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  k text; old_e jsonb; new_e jsonb;
begin
  if public.is_coach() then return new; end if;
  if new.collection in ('scores','logs') then
    old_e := coalesce(old.data->'entries', '{}'::jsonb);
    new_e := coalesce(new.data->'entries', '{}'::jsonb);
    for k in select jsonb_object_keys(old_e) loop
      if (new_e -> k) is distinct from (old_e -> k) then
        -- the app prunes entries older than 180 days; allow that only
        if (new_e ? k)
           or coalesce(old_e -> k ->> 'date', '9999-12-31') >= to_char(current_date - 150, 'YYYY-MM-DD') then
          raise exception 'Already logged. Ask a coach to clear it first.' using errcode = 'P0001';
        end if;
      end if;
    end loop;
  end if;
  return new;
end $$;

drop trigger if exists docs_protect_entries on public.docs;
create trigger docs_protect_entries before update on public.docs
  for each row execute function public.protect_entries();

-- 7. Live updates -----------------------------------------------------------
do $$ begin
  begin alter publication supabase_realtime add table public.docs;     exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.profiles; exception when duplicate_object then null; end;
end $$;

-- 8. Make yourself the first coach (edit the email, run after you sign up) ----
-- update public.profiles set role = 'coach', status = 'approved' where email = 'lu.janjan@gmail.com';
