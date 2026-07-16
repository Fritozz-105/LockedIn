-- LockedIn initial schema — Phase 1 (data model), fresh derivation 2026-07-13.
-- Spec: docs/BRAINSTORM.md § Data model (D14, D25, D30, D35, D50, D63, D66, D69, D74, D79, D82, D83, D94).
-- Posture: read-only defense-in-depth — single writer is the service-role API (D63);
-- authenticated gets SELECT only; no template carveout (amends D70; Record 004 N1-C).
-- Deviations from the BRAINSTORM sketch are itemized in docs/phases/01-data-model/PLAN.md § Approach.

-- ============================== enums ==============================

create type public.muscle_group as enum (
  'chest','back','lats','traps','shoulders','biceps','triceps',
  'quads','hamstrings','glutes','calves','abs','forearms','neck');

create type public.equipment_type as enum (
  'barbell','dumbbell','cable','machine','smith','bodyweight',
  'kettlebell','band','plate','other');

create type public.mechanic_type as enum ('compound','isolation');

create type public.movement_pattern_type as enum (
  'horizontal_push','vertical_push','horizontal_pull','vertical_pull',
  'squat','hinge','lunge','carry','isolation');

-- ============================== tables ==============================

-- app-level profile mirroring auth.users; rows created by the on_auth_user_created trigger
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  unit_preference text not null default 'lb' check (unit_preference in ('kg','lb')),
  created_at timestamptz not null default now()
);

create table public.exercise_library (
  id uuid primary key default gen_random_uuid(),
  slug text not null,                     -- unique via exercise_library_slug_idx; stable across reseeds
  name text not null,
  primary_muscle public.muscle_group not null,   -- denormalized cache for picker filters; authoritative volume weights live in exercise_muscle
  equipment public.equipment_type not null,
  mechanic public.mechanic_type not null,
  movement_pattern public.movement_pattern_type,
  is_unilateral boolean not null default false,
  description text,
  default_rep_min smallint,               -- seed hint only; workout_exercise.target_* is authoritative (D50)
  default_rep_max smallint,
  image_url text,
  is_custom boolean not null default false,
  created_by_user_id uuid references public.users(id) on delete cascade,
  check ((is_custom and created_by_user_id is not null)
      or (not is_custom and created_by_user_id is null)),
  check (default_rep_min is null or default_rep_max is null or default_rep_min <= default_rep_max)
);

-- per-muscle contribution weights (replaces a secondary_muscles[] array); primary muscle at 1.00
create table public.exercise_muscle (
  exercise_id uuid not null references public.exercise_library(id) on delete cascade,
  muscle public.muscle_group not null,
  contribution numeric(3,2) not null check (contribution > 0 and contribution <= 1),
  primary key (exercise_id, muscle)
);

create table public.mesocycle (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,   -- null = system template
  name text not null,
  total_weeks smallint not null check (total_weeks > 0),
  start_date date,                                              -- null on templates only
  is_template boolean not null default false,
  template_id uuid references public.mesocycle(id) on delete set null,  -- clone source, if any
  created_at timestamptz not null default now(),
  archived_at timestamptz,                                      -- null = active; no status enum (v1)
  -- D69: templates may omit user/start_date; user instances must have both
  check (is_template = true or (user_id is not null and start_date is not null))
);

create table public.mesocycle_week (
  id uuid primary key default gen_random_uuid(),
  mesocycle_id uuid not null references public.mesocycle(id) on delete cascade,
  week_number smallint not null check (week_number > 0),        -- 1..total_weeks (upper bound is an app-code invariant; the read-only grant posture makes the service-role API the ONLY writer, so app code genuinely owns it — D63)
  user_id uuid references public.users(id) on delete cascade,   -- denormalized (D30); null on template rows
  notes text,
  unique (mesocycle_id, week_number)
);

-- one training day; completion state derived from child sets' completed_at (no start/finish columns)
create table public.workout (
  id uuid primary key default gen_random_uuid(),
  week_id uuid not null references public.mesocycle_week(id) on delete cascade,
  day_number smallint not null check (day_number between 1 and 7),
  user_id uuid references public.users(id) on delete cascade,   -- denormalized (D30)
  name text not null,
  notes text,
  -- one workout per day slot (spec: "one per training day"); backing index also serves the week render path
  unique (week_id, day_number)
);

-- an exercise slot in a workout
create table public.workout_exercise (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references public.workout(id) on delete cascade,
  exercise_id uuid not null references public.exercise_library(id),  -- no cascade: deleting a library row in use must fail
  user_id uuid references public.users(id) on delete cascade,   -- denormalized (D30)
  position smallint not null,
  superset_group_id smallint,             -- same value within a workout = paired exercises
  target_sets smallint not null check (target_sets > 0),
  target_rep_min smallint not null,       -- AUTHORITATIVE rep range (D50)
  target_rep_max smallint not null,
  notes text,                             -- per-exercise notes; none at set level
  check (target_rep_min <= target_rep_max)
);

-- one row per set, planned or logged; dropset children reference their parent (D79)
create table public.exercise_set (
  id uuid primary key default gen_random_uuid(),
  workout_exercise_id uuid not null references public.workout_exercise(id) on delete cascade,
  set_number smallint not null check (set_number > 0),  -- dropset children SHARE the parent's set_number (group id, not unique key)
  user_id uuid references public.users(id) on delete cascade,          -- denormalized (D30); every agent tool filters on this
  exercise_id uuid references public.exercise_library(id),             -- denormalized (D66); stamped at instantiation, copied on cascade
  planned_weight numeric(6,2),            -- baseline prescription; rewritten only by the apply-forward cascade on unlogged rows
  planned_reps smallint,
  weight numeric(6,2),                    -- equals planned_* until logged, then stamped with actuals
  reps smallint,
  weight_unit text check (weight_unit in ('kg','lb')),  -- snapshot at log time; null on unit-agnostic template rows
  rir smallint check (rir >= 0),
  parent_set_id uuid references public.exercise_set(id) on delete cascade,  -- non-null = dropset child (D79)
  drop_order smallint,                    -- 1,2,3… within a drop chain; null on working sets
  is_warmup boolean not null default false,  -- D83: excluded from all volume queries
  completed_at timestamptz,               -- null = planned; server-stamped, never client-supplied
  check ((parent_set_id is null and drop_order is null)
      or (parent_set_id is not null and drop_order is not null and drop_order > 0)),
  -- D79 tightened: NULLS NOT DISTINCT (PG15+) also blocks two working sets sharing a set_number
  unique nulls not distinct (workout_exercise_id, set_number, drop_order)
);

create table public.body_weight (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  logged_at date not null,
  weight numeric(5,2) not null check (weight > 0),
  weight_unit text not null check (weight_unit in ('kg','lb')),
  created_at timestamptz not null default now(),
  unique (user_id, logged_at)             -- D82: no double-log of the same morning
);

create table public.agent_conversation (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text,
  created_at timestamptz not null default now(),
  last_message_at timestamptz
);

create table public.agent_message (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.agent_conversation(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,  -- denormalized for single-clause RLS (planner addition)
  role text not null check (role in ('user','assistant','tool')),
  content text not null,                  -- tool messages: JSON-stringified result, capped ~4KB in app code
  tool_calls jsonb,                       -- assistant messages that requested tools
  tool_call_id text,                      -- tool-role messages
  created_at timestamptz not null default now()
);

-- server-side mutation dedupe (D74/D94): duplicate optimistic-mutation POSTs replay the
-- original response instead of double-writing (added-set retries take the NEXT set_number,
-- so unique constraints alone cannot dedupe them). Service-role only. Rows expire after
-- 48h (D94) — expiry is enforced by Phase 3 app code, not the DB.
create table public.mutation_dedupe (
  user_id uuid not null references public.users(id) on delete cascade,
  idempotency_key uuid not null,          -- client-generated UUID v4 per mutation (D74)
  response jsonb not null,                -- the original response payload, replayed on retry
  created_at timestamptz not null default now(),
  primary key (user_id, idempotency_key)
);

-- ==================== auth trigger + backfill ====================

-- create the app profile row the moment an auth user exists (Supabase-documented pattern)
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  insert into public.users (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- backfill profiles for auth users that predate this migration (scaffolding test users)
insert into public.users (id, display_name)
select id, raw_user_meta_data ->> 'display_name'
from auth.users
on conflict (id) do nothing;

-- ============================== indexes ==============================
-- All in the initial migration per D35.

-- hot path: get_workout_history — per-lift set-by-set fade across time
create index exercise_set_user_exercise_completed_idx
  on public.exercise_set (user_id, exercise_id, completed_at desc)
  where completed_at is not null;

-- hot path: get_volume_per_muscle_group by time window; INCLUDE for index-only scan (D81)
create index exercise_set_user_completed_idx
  on public.exercise_set (user_id, completed_at desc)
  include (exercise_id)
  where completed_at is not null and is_warmup = false;

-- hot path: render a workout's sets in order
create index exercise_set_we_setnum_idx
  on public.exercise_set (workout_exercise_id, set_number, drop_order nulls first);

-- dropset child lookup
create index exercise_set_parent_idx
  on public.exercise_set (parent_set_id) where parent_set_id is not null;

-- mesocycle list + cross-mesocycle progression
create index mesocycle_user_archived_idx
  on public.mesocycle (user_id, archived_at);
create index mesocycle_user_startdate_idx
  on public.mesocycle (user_id, start_date desc)
  where is_template = false;

-- exercise library
create unique index exercise_library_slug_idx on public.exercise_library (slug);
create index exercise_library_primary_muscle_idx on public.exercise_library (primary_muscle);

-- volume queries look up by muscle
create index exercise_muscle_muscle_idx on public.exercise_muscle (muscle);

-- agent chat
create index agent_message_conversation_idx on public.agent_message (conversation_id, created_at);

-- body-weight trend reads
create index body_weight_user_logged_idx on public.body_weight (user_id, logged_at desc);

-- FK/render-path indexes the sketch omitted (Postgres does not auto-index FKs; planner addition).
-- workout (week_id, day_number) is covered by its UNIQUE constraint's backing index.
create index workout_exercise_workout_idx on public.workout_exercise (workout_id, position);
create index agent_conversation_user_idx on public.agent_conversation (user_id, last_message_at desc);

-- ============================== RLS ==============================
-- Read-only defense-in-depth (2026-07-13 posture): the API connects as service role
-- (bypasses RLS) and is the ONLY writer (D63). The anon-key/PostgREST path gets
-- owner-scoped SELECT and nothing else. No template carveout — system templates are
-- served by the API; direct reads of them fail closed (amends D70; Record 004 N1-C).
-- Policies use the modern form: TO authenticated + (select auth.uid()).

alter table public.users enable row level security;
create policy users_owner_read on public.users
  for select to authenticated
  using ((select auth.uid()) = id);

alter table public.mesocycle enable row level security;
create policy mesocycle_owner_read on public.mesocycle
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.mesocycle_week enable row level security;
create policy mesocycle_week_owner_read on public.mesocycle_week
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.workout enable row level security;
create policy workout_owner_read on public.workout
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.workout_exercise enable row level security;
create policy workout_exercise_owner_read on public.workout_exercise
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.exercise_set enable row level security;
create policy exercise_set_owner_read on public.exercise_set
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.body_weight enable row level security;
create policy body_weight_owner_read on public.body_weight
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.agent_conversation enable row level security;
create policy agent_conversation_owner_read on public.agent_conversation
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.agent_message enable row level security;
create policy agent_message_owner_read on public.agent_message
  for select to authenticated
  using ((select auth.uid()) = user_id);

alter table public.exercise_library enable row level security;
-- System exercises readable by everyone signed in; CUSTOM exercises only by their creator
-- (2026-07-02 amendment to D70, carried: no cross-user reads of user-created content).
create policy exercise_library_read on public.exercise_library
  for select to authenticated
  using (is_custom = false or created_by_user_id = (select auth.uid()));

alter table public.exercise_muscle enable row level security;
-- Visibility follows the owning exercise: system → all authenticated; custom → creator only.
create policy exercise_muscle_read on public.exercise_muscle
  for select to authenticated
  using (exists (
    select 1 from public.exercise_library el
    where el.id = exercise_id
      and (el.is_custom = false or el.created_by_user_id = (select auth.uid()))
  ));

alter table public.mutation_dedupe enable row level security;
-- no policies on purpose: server bookkeeping, service-role only. authenticated's
-- schema-wide SELECT grant below is neutralized by fail-closed RLS (zero policies).

-- ============================== grants ==============================
-- LAST on purpose: if the project is on the legacy auto-grant default, the default
-- grants land at CREATE TABLE time, so revoking after every CREATE TABLE strips them;
-- if it is on the 2026 no-auto-grant default, the revoke is a harmless no-op. Either
-- way the effective state below is deterministic (research § 1-2). The smoke test
-- asserts the EFFECTIVE grants, not the mechanism.

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to authenticated;
grant select on all tables in schema public to authenticated;

-- trigger-only function: Postgres grants EXECUTE to PUBLIC on new functions; revoke
-- closes direct-call/RPC exposure. Trigger firing does not check the caller's EXECUTE.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
