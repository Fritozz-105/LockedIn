-- LockedIn schema smoke test (read-only defense-in-depth posture, 2026-07-13).
-- Everything runs in ONE transaction and ROLLS BACK — safe against the hosted
-- (pre-launch) database. Any failed assertion raises and aborts with a nonzero
-- exit via ON_ERROR_STOP.
-- Usage: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/smoke.sql
begin;

-- ---- 0a. all required indexes exist ----
do $$
declare idx text;
begin
  foreach idx in array array[
    'exercise_set_user_exercise_completed_idx','exercise_set_user_completed_idx',
    'exercise_set_we_setnum_idx','exercise_set_parent_idx',
    'mesocycle_user_archived_idx','mesocycle_user_startdate_idx',
    'exercise_library_slug_idx','exercise_library_primary_muscle_idx',
    'exercise_muscle_muscle_idx','agent_message_conversation_idx',
    'body_weight_user_logged_idx','workout_week_id_day_number_key',
    'workout_exercise_workout_idx','agent_conversation_user_idx'
  ] loop
    if to_regclass('public.' || idx) is null then
      raise exception 'FAIL: required index % is missing', idx;
    end if;
  end loop;
end $$;

-- ---- 0b. effective grants match the read-only posture ----
-- (asserts EFFECTIVE state, so it holds whether the project is on the legacy
--  auto-grant default or the 2026 no-auto-grant default — research § 1)
do $$
declare bad int;
begin
  -- authenticated: nothing beyond SELECT; anon: nothing at all
  select count(*) into bad
  from information_schema.role_table_grants
  where table_schema = 'public'
    and ((grantee = 'authenticated' and privilege_type <> 'SELECT')
      or grantee = 'anon');
  if bad <> 0 then
    raise exception 'FAIL: % unexpected anon/authenticated table grants in public', bad;
  end if;
  -- authenticated: SELECT present on every public table
  select count(*) into bad
  from pg_tables t
  where t.schemaname = 'public'
    and not exists (
      select 1 from information_schema.role_table_grants g
      where g.table_schema = 'public' and g.table_name = t.tablename
        and g.grantee = 'authenticated' and g.privilege_type = 'SELECT');
  if bad <> 0 then
    raise exception 'FAIL: % public tables missing SELECT grant for authenticated', bad;
  end if;
end $$;

-- ---- 0c. policy inventory: 11 policies, all SELECT-only, no carveout ----
do $$
declare n int;
begin
  select count(*) into n from pg_policies where schemaname = 'public';
  if n <> 11 then raise exception 'FAIL: expected 11 policies, found %', n; end if;
  select count(*) into n from pg_policies where schemaname = 'public' and cmd <> 'SELECT';
  if n <> 0 then raise exception 'FAIL: % non-SELECT policies exist', n; end if;
  select count(*) into n from pg_policies where policyname = 'mesocycle_templates_public';
  if n <> 0 then raise exception 'FAIL: template carveout policy still exists'; end if;
end $$;

-- ---- 1. auth trigger + backfill ----
-- migration backfill: every PRE-EXISTING auth user already has a profile row
do $$
declare missing int;
begin
  select count(*) into missing
  from auth.users au
  where not exists (select 1 from public.users u where u.id = au.id);
  if missing <> 0 then
    raise exception 'FAIL: % pre-existing auth users missing profile rows (backfill incomplete)', missing;
  end if;
end $$;

-- trigger: inserting a NEW auth user auto-creates the profile row
insert into auth.users (instance_id, id, aud, role, email)
values ('00000000-0000-0000-0000-000000000000',
        '00000000-0000-0000-0000-0000000000a1',
        'authenticated', 'authenticated', 'smoke-a@test.local');

do $$ begin
  if not exists (select 1 from public.users where id = '00000000-0000-0000-0000-0000000000a1') then
    raise exception 'FAIL: on_auth_user_created trigger did not create the profile row';
  end if;
end $$;

-- ---- 2. reference data: one exercise with weighted muscle contributions ----
insert into public.exercise_library (id, slug, name, primary_muscle, equipment, mechanic, movement_pattern)
values ('00000000-0000-0000-0000-0000000000e1',
        'smoke-barbell-bench-press', 'Smoke Barbell Bench Press',
        'chest', 'barbell', 'compound', 'horizontal_push');

insert into public.exercise_muscle (exercise_id, muscle, contribution) values
  ('00000000-0000-0000-0000-0000000000e1', 'chest',     1.00),
  ('00000000-0000-0000-0000-0000000000e1', 'triceps',   0.50),
  ('00000000-0000-0000-0000-0000000000e1', 'shoulders', 0.25);

-- a CUSTOM exercise owned by user A (read-split probe target)
insert into public.exercise_library (id, slug, name, primary_muscle, equipment, mechanic,
                                     is_custom, created_by_user_id)
values ('00000000-0000-0000-0000-0000000000e2',
        'smoke-custom-cable-fly', 'Smoke Custom Cable Fly',
        'chest', 'cable', 'isolation', true,
        '00000000-0000-0000-0000-0000000000a1');
insert into public.exercise_muscle (exercise_id, muscle, contribution)
values ('00000000-0000-0000-0000-0000000000e2', 'chest', 1.00);

-- ---- 3. the sample Push Day from BRAINSTORM (4 working sets, double-dropset on set 4) ----
insert into public.mesocycle (id, user_id, name, total_weeks, start_date, is_template)
values ('00000000-0000-0000-0000-0000000000c1',
        '00000000-0000-0000-0000-0000000000a1', 'Smoke Meso', 4, current_date, false);

insert into public.mesocycle_week (id, mesocycle_id, week_number, user_id)
values ('00000000-0000-0000-0000-0000000000d1',
        '00000000-0000-0000-0000-0000000000c1', 1,
        '00000000-0000-0000-0000-0000000000a1');

insert into public.workout (id, week_id, day_number, user_id, name)
values ('00000000-0000-0000-0000-0000000000f1',
        '00000000-0000-0000-0000-0000000000d1', 1,
        '00000000-0000-0000-0000-0000000000a1', 'Push A');

insert into public.workout_exercise (id, workout_id, exercise_id, user_id, position,
                                     target_sets, target_rep_min, target_rep_max)
values ('00000000-0000-0000-0000-000000000042',
        '00000000-0000-0000-0000-0000000000f1',
        '00000000-0000-0000-0000-0000000000e1',
        '00000000-0000-0000-0000-0000000000a1', 1, 4, 6, 8);

-- 4 completed working sets showing fade, then two completed drops under set 4
insert into public.exercise_set
  (id, workout_exercise_id, set_number, user_id, exercise_id,
   planned_weight, planned_reps, weight, reps, weight_unit, rir,
   parent_set_id, drop_order, completed_at)
values
  ('00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000042',1,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',185,8,185,8,'lb',2,null,null,now()),
  ('00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000042',2,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',185,8,185,7,'lb',1,null,null,now()),
  ('00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000042',3,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',185,8,185,6,'lb',0,null,null,now()),
  ('00000000-0000-0000-0000-000000000104','00000000-0000-0000-0000-000000000042',4,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',185,8,185,5,'lb',0,null,null,now()),
  ('00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000042',4,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',null,null,135,8,'lb',null,'00000000-0000-0000-0000-000000000104',1,now()),
  ('00000000-0000-0000-0000-000000000106','00000000-0000-0000-0000-000000000042',4,'00000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000e1',null,null, 95,8,'lb',null,'00000000-0000-0000-0000-000000000104',2,now());

-- agent persistence rows for user A (RLS probe targets)
insert into public.agent_conversation (id, user_id, title)
values ('00000000-0000-0000-0000-0000000000a9',
        '00000000-0000-0000-0000-0000000000a1', 'Smoke chat');
insert into public.agent_message (conversation_id, user_id, role, content)
values ('00000000-0000-0000-0000-0000000000a9',
        '00000000-0000-0000-0000-0000000000a1', 'user', 'How was my bench today?');

-- body-weight row for user A (owner-read + write-denial probe target)
insert into public.body_weight (user_id, logged_at, weight, weight_unit)
values ('00000000-0000-0000-0000-0000000000a1', current_date, 180.40, 'lb');

-- dedupe row for user A (D74/D94; fixed key — § 6 proves the duplicate rejects; § 7 proves RLS hides it)
insert into public.mutation_dedupe (user_id, idempotency_key, response)
values ('00000000-0000-0000-0000-0000000000a1',
        '00000000-0000-0000-0000-0000000000dd', '{"ok":true}'::jsonb);

-- ---- 4. render query returns the 6 rows in exact UI order ----
do $$
declare got uuid[];
begin
  select array_agg(id order by set_number asc, drop_order asc nulls first) into got
  from public.exercise_set
  where workout_exercise_id = '00000000-0000-0000-0000-000000000042';
  -- IS DISTINCT FROM: a NULL got (zero rows) must FAIL, not silently pass
  if got is distinct from array[
    '00000000-0000-0000-0000-000000000101','00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000103','00000000-0000-0000-0000-000000000104',
    '00000000-0000-0000-0000-000000000105','00000000-0000-0000-0000-000000000106'
  ]::uuid[] then
    raise exception 'FAIL: render order wrong, got %', got;
  end if;
end $$;

-- ---- 5. volume query: 6 completed non-warmup sets x contribution weights ----
do $$
declare chest numeric; tri numeric;
begin
  select coalesce(sum(em.contribution) filter (where em.muscle = 'chest'), 0),
         coalesce(sum(em.contribution) filter (where em.muscle = 'triceps'), 0)
    into chest, tri
  from public.exercise_set es
  join public.exercise_muscle em on em.exercise_id = es.exercise_id
  where es.user_id = '00000000-0000-0000-0000-0000000000a1'
    and es.completed_at is not null and es.is_warmup = false;
  if chest <> 6.00 or tri <> 3.00 then
    raise exception 'FAIL: volume weights wrong — chest %, triceps % (expected 6.00 / 3.00)', chest, tri;
  end if;
end $$;

-- ---- 6. constraints reject bad rows ----
-- D69: instance without start_date
do $$ begin
  begin
    insert into public.mesocycle (user_id, name, total_weeks, is_template)
    values ('00000000-0000-0000-0000-0000000000a1', 'bad instance', 4, false);
    raise exception 'FAIL: mesocycle CHECK (D69) accepted an instance without start_date';
  exception when check_violation then null;  -- expected
  end;
end $$;

-- NULLS NOT DISTINCT: duplicate working-set number
do $$ begin
  begin
    insert into public.exercise_set (workout_exercise_id, set_number, user_id, exercise_id)
    values ('00000000-0000-0000-0000-000000000042', 4,
            '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000e1');
    raise exception 'FAIL: duplicate working set (we,set#,NULL) was accepted — NULLS NOT DISTINCT missing';
  exception when unique_violation then null;  -- expected
  end;
end $$;

-- D82: same-day body-weight double log
do $$ begin
  begin
    insert into public.body_weight (user_id, logged_at, weight, weight_unit)
    values ('00000000-0000-0000-0000-0000000000a1', current_date, 181.00, 'lb');
    raise exception 'FAIL: body_weight accepted a same-day double log';
  exception when unique_violation then null;  -- expected
  end;
end $$;

-- D74: the dedupe table's CORE guarantee — duplicate (user_id, idempotency_key) rejects,
-- so a retried mutation can only ever replay, never double-write
do $$ begin
  begin
    insert into public.mutation_dedupe (user_id, idempotency_key, response)
    values ('00000000-0000-0000-0000-0000000000a1',
            '00000000-0000-0000-0000-0000000000dd', '{"ok":"dup"}'::jsonb);
    raise exception 'FAIL: mutation_dedupe accepted a duplicate (user_id, idempotency_key)';
  exception when unique_violation then null;  -- expected
  end;
end $$;

-- ---- 7. RLS probes: everything is fail-closed except owner reads ----
-- system + user-authored template rows to prove the carveout is GONE
insert into public.mesocycle (id, user_id, name, total_weeks, is_template)
values ('00000000-0000-0000-0000-0000000000c2', null, 'Smoke System Template', 4, true);
insert into public.mesocycle (id, user_id, name, total_weeks, is_template)
values ('00000000-0000-0000-0000-0000000000c3',
        '00000000-0000-0000-0000-0000000000a1', 'Smoke User Template', 4, true);

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000b2"}';  -- a DIFFERENT user

do $$
declare own_visible int; sys_tpl int; user_tpl int;
begin
  select count(*) into own_visible from public.mesocycle
    where id = '00000000-0000-0000-0000-0000000000c1';       -- user A's instance
  select count(*) into sys_tpl from public.mesocycle
    where id = '00000000-0000-0000-0000-0000000000c2';       -- system template
  select count(*) into user_tpl from public.mesocycle
    where id = '00000000-0000-0000-0000-0000000000c3';       -- user A's template
  if own_visible <> 0 then raise exception 'FAIL: RLS leaked another user''s mesocycle'; end if;
  if sys_tpl <> 0 then raise exception 'FAIL: system template visible — carveout not removed (fail-closed posture violated)'; end if;
  if user_tpl <> 0 then raise exception 'FAIL: user-authored template leaked'; end if;
end $$;

-- still user B: zero cross-user rows anywhere; system exercises visible, custom ones not
do $$
declare leaked int; sys_ex int;
begin
  select (select count(*) from public.workout)
       + (select count(*) from public.body_weight)
       + (select count(*) from public.agent_conversation)
       + (select count(*) from public.agent_message)
       + (select count(*) from public.users)
       + (select count(*) from public.mesocycle_week)
       + (select count(*) from public.workout_exercise)
       + (select count(*) from public.exercise_set)
       + (select count(*) from public.mutation_dedupe)
       + (select count(*) from public.exercise_library where is_custom)
       + (select count(*) from public.exercise_muscle
            where exercise_id = '00000000-0000-0000-0000-0000000000e2')
    into leaked;
  select count(*) into sys_ex from public.exercise_library
    where id = '00000000-0000-0000-0000-0000000000e1';
  if leaked <> 0 then raise exception 'FAIL: RLS leaked % cross-user rows', leaked; end if;
  if sys_ex <> 1 then raise exception 'FAIL: system exercise not readable by other users'; end if;
end $$;

set local request.jwt.claims to '{"sub":"00000000-0000-0000-0000-0000000000a1"}';  -- user A themself
do $$
declare n int; own_custom int; own_custom_muscle int; own_bw int; own_chat int;
        own_profile int; own_week int; own_we int; own_meso int; own_workout int; own_conv int;
begin
  select count(*) into n from public.exercise_set
    where workout_exercise_id = '00000000-0000-0000-0000-000000000042';
  select count(*) into own_custom from public.exercise_library
    where id = '00000000-0000-0000-0000-0000000000e2';
  select count(*) into own_custom_muscle from public.exercise_muscle
    where exercise_id = '00000000-0000-0000-0000-0000000000e2';
  select count(*) into own_bw from public.body_weight;
  select count(*) into own_chat from public.agent_message;
  select count(*) into own_profile from public.users
    where id = '00000000-0000-0000-0000-0000000000a1';
  select count(*) into own_week from public.mesocycle_week;
  select count(*) into own_we from public.workout_exercise;
  select count(*) into own_meso from public.mesocycle
    where id = '00000000-0000-0000-0000-0000000000c1';
  select count(*) into own_workout from public.workout
    where id = '00000000-0000-0000-0000-0000000000f1';
  select count(*) into own_conv from public.agent_conversation
    where id = '00000000-0000-0000-0000-0000000000a9';
  if n <> 6 then raise exception 'FAIL: owner cannot see their own sets under RLS (got %)', n; end if;
  if own_custom <> 1 or own_custom_muscle <> 1 then
    raise exception 'FAIL: owner cannot see their own custom exercise under RLS';
  end if;
  if own_bw <> 1 or own_chat <> 1 then
    raise exception 'FAIL: owner cannot see their own body_weight/agent rows under RLS';
  end if;
  if own_profile <> 1 or own_week <> 1 or own_we <> 1 then
    raise exception 'FAIL: owner cannot see their own users/mesocycle_week/workout_exercise rows under RLS';
  end if;
  if own_meso <> 1 or own_workout <> 1 or own_conv <> 1 then
    raise exception 'FAIL: owner cannot see their own mesocycle/workout/agent_conversation rows under RLS';
  end if;
  -- mutation_dedupe is service-role only: invisible even to its OWNER (zero policies)
  select count(*) into n from public.mutation_dedupe;
  if n <> 0 then
    raise exception 'FAIL: mutation_dedupe visible to authenticated — service-role-only posture violated';
  end if;
end $$;

-- ---- 8. write path is CLOSED at the grant layer: 42501 for all three statement types ----
-- (research § 5: with no write grants, INSERT/UPDATE/DELETE fail as insufficient_privilege
--  BEFORE RLS is evaluated — even on the user's own rows)
do $$ begin
  begin
    insert into public.body_weight (user_id, logged_at, weight, weight_unit)
    values ('00000000-0000-0000-0000-0000000000a1', current_date - 1, 179.00, 'lb');
    raise exception 'FAIL: authenticated INSERT accepted — write grants exist';
  exception when insufficient_privilege then null;  -- expected 42501
  end;
end $$;

do $$ begin
  begin
    update public.exercise_set set reps = 99
    where id = '00000000-0000-0000-0000-000000000101';
    raise exception 'FAIL: authenticated UPDATE accepted — write grants exist';
  exception when insufficient_privilege then null;  -- expected 42501
  end;
end $$;

do $$ begin
  begin
    delete from public.body_weight
    where user_id = '00000000-0000-0000-0000-0000000000a1';
    raise exception 'FAIL: authenticated DELETE accepted — write grants exist';
  exception when insufficient_privilege then null;  -- expected 42501
  end;
end $$;

-- EXECUTE revoked on the trigger function. Checked via the ACL (has_function_privilege
-- resolves PUBLIC grants too), NOT via a direct call — calling a trigger function raises
-- 0A000 at parse analysis BEFORE any privilege check, so a call-based probe would be
-- ambiguous about whether the revoke actually happened.
do $$ begin
  if has_function_privilege('authenticated', 'public.handle_new_user()', 'execute')
     or has_function_privilege('anon', 'public.handle_new_user()', 'execute') then
    raise exception 'FAIL: EXECUTE on handle_new_user not revoked from anon/authenticated (PUBLIC grant survives?)';
  end if;
end $$;

reset role;

rollback;
\echo SMOKE PASSED — all assertions held; transaction rolled back
