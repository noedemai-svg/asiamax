-- Schéma initial ASIA MAX (phase 0)
-- Les deux voyageurs sont les seuls autorisés à lire/écrire (RLS ci-dessous).

create extension if not exists pgcrypto;

create table person (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  role text not null check (role in ('voter', 'guest')),
  email text unique not null
);

create table zone (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('country', 'region', 'city', 'district')),
  parent_id uuid references zone(id),
  name_en text not null,
  name_local text,
  center_lat double precision,
  center_lng double precision
);

create table place (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references zone(id),
  category text not null check (category in ('manger', 'boire', 'culture', 'nature', 'loisirs', 'shopping', 'sortir', 'pratique')),
  kind text not null check (kind in ('point', 'area', 'route', 'chain', 'taste', 'tip')),
  name_en text not null,
  name_local text,
  name_transcription text,
  alt_names text[] default '{}',
  lat double precision,
  lng double precision,
  position_precision text check (position_precision in ('exact', 'approx')),
  google_place_id text unique,
  business_status text,
  address_local text,
  opening_hours text,
  closed_days text,
  price_min numeric,
  price_max numeric,
  currency text,
  extra_transport text,
  extra_transport_cost numeric,
  duration_minutes integer,
  best_time text,
  summary text,
  tips text,
  dishes_to_order text,
  needs_reservation boolean default false,
  to_confirm boolean not null default false,
  out_of_trip boolean not null default false,
  parent_place_id uuid references place(id),
  event_start_date date,
  event_end_date date,
  review_status text not null default 'ok' check (review_status in ('ok', 'to_check', 'to_review')),
  created_at timestamptz not null default now()
);

create table media (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references place(id) on delete cascade,
  type text not null check (type in ('reel_frame', 'web_photo', 'screenshot', 'personal_photo')),
  storage_path text not null,
  credit text,
  created_at timestamptz not null default now()
);

create table source (
  id uuid primary key default gen_random_uuid(),
  platform text not null,
  format text not null check (format in ('video', 'carousel', 'photo', 'story', 'link', 'screenshot', 'manual')),
  canonical_url text unique not null,
  creator text,
  published_at date,
  caption text,
  transcript text,
  sponsored boolean not null default false,
  missing_info text check (missing_info in ('dm', 'bio_link')),
  shared_by uuid references person(id),
  created_at timestamptz not null default now()
);

create table source_place (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references source(id) on delete cascade,
  place_id uuid not null references place(id) on delete cascade,
  rank integer,
  timestamp_s numeric,
  slide_index integer,
  media_id uuid references media(id),
  creator_opinion text,
  unique (source_id, place_id)
);

create table import_job (
  id uuid primary key default gen_random_uuid(),
  url text not null,
  shared_by uuid references person(id),
  status text not null default 'pending' check (status in ('pending', 'done', 'to_check', 'error')),
  attempts integer not null default 0,
  failure_reason text,
  next_attempt_at timestamptz,
  created_at timestamptz not null default now()
);

create table rating (
  id uuid primary key default gen_random_uuid(),
  place_id uuid not null references place(id) on delete cascade,
  person_id uuid not null references person(id),
  stars smallint not null check (stars between 1 and 3),
  rated_at timestamptz not null default now(),
  unique (place_id, person_id)
);

create table rating_history (
  id uuid primary key default gen_random_uuid(),
  rating_id uuid not null references rating(id) on delete cascade,
  stars_before smallint,
  stars_after smallint not null,
  changed_at timestamptz not null default now()
);

create table merge_history (
  id uuid primary key default gen_random_uuid(),
  kept_place_id uuid not null references place(id),
  merged_place_snapshot jsonb not null,
  merged_sources jsonb not null,
  merged_ratings jsonb not null,
  author_id uuid references person(id),
  created_at timestamptz not null default now()
);

create table stage (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references zone(id),
  stage_order integer not null,
  days integer,
  start_date date,
  end_date date,
  branch text not null default 'main' check (branch in ('main', 'parallel')),
  participants uuid[] default '{}',
  deciders uuid[] default '{}'
);

create table leg (
  id uuid primary key default gen_random_uuid(),
  from_stage_id uuid not null references stage(id),
  to_stage_id uuid not null references stage(id),
  mode text,
  duration_minutes integer,
  distance_km numeric
);

create table task (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  assignee_id uuid references person(id),
  due_date date,
  done boolean not null default false,
  link text
);

-- RLS : seules les deux adresses du voyage peuvent lire/écrire.
create function is_trip_member() returns boolean
  language sql stable
  as $$
    select coalesce(auth.jwt() ->> 'email', '') in (
      'noe.demai@edu.escp.eu',
      'hugo.meyrand@edu.escp.eu'
    )
  $$;

do $$
declare
  t text;
begin
  for t in select unnest(array[
    'person', 'zone', 'place', 'media', 'source', 'source_place',
    'import_job', 'rating', 'rating_history', 'merge_history',
    'stage', 'leg', 'task'
  ])
  loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for all using (is_trip_member()) with check (is_trip_member())',
      t || '_trip_members', t
    );
  end loop;
end $$;
