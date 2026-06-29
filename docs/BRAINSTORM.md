# LockedIn — Brainstorm

Working notes for a fitness-focused mobile app. Captures early design decisions, scope, and the reasoning behind each choice. Not polished docs — this is the scratchpad.

> **⚠️ Decision provenance (added 2026-06-27).** The decisions D1–D106 below were proposed and argued by Claude during brainstorming, **not yet validated by the project owner with real implementation context.** They are working defaults, not commitments. As each decision resurfaces during implementation — and as the owner gains hands-on context (mobile, AWS, Docker, the actual data shapes) — **re-open it and decide again.** A decision being in this doc means "Claude's best guess at the time," not "settled." Treat the ✅ marks as "captured," not "ratified."

---

## Elevator pitch

A mobile app where users:

1. Run structured mesocycle-based workout programs and log lifts.
2. Track body weight over time with a trend line.
3. Talk to an AI coach that has read access to their training and weight data and can suggest adjustments.

Food tracking and streaks are deferred to v2. **A social component is a committed future pillar (not a maybe)** — sharing/following/feed around training — but it lands after the v1 single-player core is solid. See "Social — committed v2 direction" below.

## North star

Be a genuinely useful daily-driver app, not a feature checklist. **Depth** in workout tracking + AI coaching beats shallow coverage of everything. Resume value comes from one polished, working product — not five half-built ones.

---

## v1 Scope

**Mesocycle creation + per-set logging is the centerpiece. A fully functional read-only AI agent ships alongside.** No scope cuts — user has 20–30 hrs/wk over 12 weeks (~250–360 hrs total), which fits everything below.

### In (committed)

- **Auth** — sign up, sign in, password reset (Supabase Auth).
- **Workout tracker** (primary focus):
  - 3 curated mesocycle templates (PPL 6-day, Upper/Lower 4-day, Full Body 3x/week).
  - Mesocycle instantiation from a template.
  - Week → workout → exercise → per-set CRUD.
  - **Per-set logging** (weight, reps, optional RIR) — not per-exercise.
  - **Dropset support** via `parent_set_id` + `drop_order`.
  - Exercise library (~100 system entries) + custom user-created exercises.
  - Notes at the exercise level.
  - Unit preference (kg/lb), denormalized onto every logged set.
- **Body weight tracking** — daily weight log, line graph, rolling-average trend.
- **AI agent — fully functional read-only**:
  - Chat UI with multi-turn conversation.
  - Persisted conversation history in Postgres.
  - 4 read tools: `get_workout_history`, `get_body_weight_trend`, `get_current_mesocycle`, `get_volume_per_muscle_group`.
  - No write tools (D9 holds — write tools are v1.1 due to data-corruption risk if model misfires).

### Out (deferred to v2+)

- Agent write tools (`log_workout_set`, `log_body_weight`, `suggest_mesocycle_adjustment`) — v1.1.
- Food tracking (food DB, barcode scan, macros).
- **Social component — committed v2 direction, not a maybe** (sharing workouts/programs, following, activity feed). Deferred out of v1 for scope, but it *will* ship. See dedicated section below.
- Streaks + push-notification engagement loops.
- Full user-authored program builder (schema supports it; UI is v2).
- Arnold split, Anterior/Posterior splits, Upper/Lower 6-day — add by user demand in v1.1.

### Social — committed v2 direction

Not in v1, but the owner intends this app to have a real social layer eventually (sharing workouts/programs, following other users, an activity feed). Logged here so it isn't treated as a throwaway "deferred maybe."

**Near-term consequence for v1 (flagged, not yet decided):** a social layer changes data-ownership assumptions. v1's current model is strictly single-player — every row is scoped to one `user_id`, and authz (D63) and RLS (D70) are built around "you only ever see your own data." Social introduces *cross-user reads* (I see your shared workout). We do **not** need to build that in v1, but two cheap, reversible hedges are worth a deliberate decision before the schema migration lands in Weeks 1–2:
- A `visibility` concept (private/shared) is far cheaper to leave room for now than to retrofit across every table and RLS policy later.
- Whether shared content is a copy/snapshot vs. a live reference changes the FK design.

This is a **decision to make with context, not now** — per the provenance note above. Captured so it's on the radar when the data-model migration is written.

### Why this cut

- Workout tracker with **real per-set fidelity** is the daily-driver. Most fitness apps log per-exercise and lose the signal needed for progressive overload.
- The agent — even read-only — is the resume differentiator. "LLM function-calling against my own Postgres schema with optimistic UI" gets recruiter attention; "CRUD tracker" doesn't.
- Food/social/streaks bolt on cleanly once the core works. Doing them now means everything is shallow.

---

## Timeline & scope discipline

- **Hard guardrail: working TestFlight build in 12 weeks.** Even if ugly.
- **Availability: 20–30 hrs/wk** (focused / minimal classes / summer).
- **No scope cuts on the list above.** If hours slip below 20/wk for 2+ weeks in a row, the first cut is **deferring offline persistence to v1.1** (still ~1 week to do well), then **stub the agent at 2 tools + chat UI** rather than full surface.
- **Single biggest failure mode: planning depth >> shipping depth.** This doc is excellent and also a warning sign. From here on, design dialogue is bounded — when implementation begins, design questions get *short* answers in conversation, not new doc sections.

---

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Mobile | **React Native + Expo SDK 54** (TypeScript, strict mode) | One codebase iOS+Android, EAS builds, fast iteration. No Next.js — this is mobile-first. **Pinned versions (D85): `expo: ~54.0.0`, `react: 19.1.0`, `react-native: 0.81`, Node 20.19.x.** Picked SDK 54 (current-stable) over SDK 55/56 (bleeding edge) — fewer landmines for first-time mobile dev. |
| Backend API | **Node + Fastify (TypeScript), Dockerized** | **Type-sharing with the RN frontend is the decisive factor:** define schemas once with `zod`, get backend validation + backend types + frontend types in one shot. Eliminates a whole class of bugs for a solo dev. Plugin ecosystem is a bonus, not the reason. Express is out (legacy API, no native TS). Flask is out (no validation/typing story). FastAPI is defensible but loses type-sharing — only pick it if prioritizing AI/ML resume angle over mobile. |
| Backend hosting | **Heroku Basic dyno** ($7/mo, no idle sleep), Container Registry deploy | 1 year of credits covers the cost; no reason to suffer Eco's 30-min idle sleep + 5–15s cold starts. Simpler than running a keepalive ping. |
| Database | **Supabase Postgres** | Free tier (500MB, pauses after 7 days inactive). Real Postgres, not a toy. Comes with auth + storage. |
| Auth | **Supabase Auth** | Free up to 50k MAU. Cognito is painful; Supabase is the pragmatic choice. |
| File storage | **Supabase Storage** (or Cloudflare R2 if we outgrow it) | Workout photos, profile pics. R2 is free egress, nice future option. |
| LLM | **OpenAI-compatible API via user's custom endpoint** | User has key + free model access. Standard function-calling API. |
| Charts | **Victory Native** or **react-native-gifted-charts** | Body-weight line graph, volume charts. Decide during impl. |
| Push notifications | **Expo Notifications** | Deferred until streaks/engagement features land. |
| CI/CD | **GitHub Actions** → Heroku Container Registry **and AWS ECR** | Build Docker image on push, deploy to Heroku (primary, live demo) **and** AWS ECS on EC2 (containerization/IaC resume bullet — demo-only, not reachable from the mobile app). **Same image, SHA-tagged, pushed to both registries before Heroku release-phase activation; pipeline fails on either registry failure (D84).** Prevents silent drift between registries. |
| AWS deploy (v1) | **ECS on EC2 (t2.micro, free tier 12 months) + ECR**, no ALB, **demo-only** | Free for 12 months — matches Heroku credit horizon. Fargate is **not** free tier; ALB is **not** free tier. Public IP on task serves plain HTTP — fine for `curl /health` + README screenshots, but iOS App Transport Security blocks plain HTTP from the mobile app, so AWS is **not** wired up as a real backend. Heroku is the only URL the app calls. |
| Testing | **Jest + React Native Testing Library** for unit tests; **no E2E in v1** | RNTL for shared/pure logic (template expansion, dropset ordering, rolling-average trend, agent tool-result truncation). Maestro/Detox = v1.1 after TestFlight feedback drives iteration. |

### Resume story this gives you

- **TypeScript** (strict) across mobile + backend.
- **React Native + Expo** (real mobile dev).
- **Docker** (containerized backend, deployed via Container Registry).
- **Postgres** (real relational DB, not Mongo).
- **LLM tool use / agent design** (genuinely current, in-demand).
- **CI/CD pipeline** (GitHub Actions).

What's **not** here on purpose:

- **Kubernetes** — overkill for one container. Cargo-culting K8s on a side project is a red flag, not a green one. Build a separate small K8s project if you want that bullet.
- **AWS Cognito** for auth — notoriously painful. Supabase Auth is the pragmatic choice.
- **Next.js** — the product is mobile-first. Add a marketing site later if you want; don't conflate it with the app.

---

## Resume positioning

This stack is broad. Recruiters skim; engineering managers dig. Choose what to lead with carefully.

### Lead with (these get callbacks)

- **Per-set data model with denormalized `user_id`, planned-vs-logged split, dropset chains via `(parent_set_id, drop_order)`, and `exercise_muscle` weighted contribution table** — concrete schema design that solves real product problems.
- **LLM function-calling against my own Postgres schema** with 4 read tools, persisted multi-turn chat history, and rate-limited routes. Not "I used the OpenAI API"; "I wired a tool-calling agent against a domain schema I designed."
- **Type-shared monorepo** — `zod` schemas in `packages/shared` flow into backend validation, backend types, and React Native frontend types in a single source of truth.
- **Optimistic mutations with per-row mutation keys and server-stamped timestamps** — concrete mobile UX engineering, not "I used TanStack Query."
- **Containerized deploy to two clouds via GitHub Actions** — same Docker image pushed to Heroku Container Registry (the live mobile-facing backend) and AWS ECR + ECS-on-EC2 (demo-only second target showing I can wire up an AWS pipeline end-to-end: ECR repo + lifecycle policy, ECS task definition, IAM role via OIDC from GH Actions). Frame honestly: "deployed the same image to AWS ECS-on-EC2 with screenshots in the README," not "production AWS infrastructure."

### Skim past (don't lead, mention briefly)

- Expo Router, NativeWind, Zustand, Victory Native — implementation choices, not differentiators.
- "I used Supabase Auth" — it's a SaaS button; don't list as auth expertise. Mention as DB+auth provider.
- The 3 templates and exercise library curation — content authoring, not engineering.

### Don't mention

- Kubernetes (not used and not relevant).
- "Production-ready" or "scalable" — overpromises for a personal project. Use "deployed to production" instead.

### One ADR (post-launch)

Not in v1. After TestFlight, extract 3 load-bearing decisions into `docs/adr/` as formal Architecture Decision Records (e.g., Fastify-vs-FastAPI, denormalize-user_id-down-tree, agent-in-v1-vs-v1.1). Better than nothing for engineering-process signal in interviews — but not worth doing pre-launch when nothing is shipped.

---

## Auth & API security

### How auth flows end-to-end

1. Mobile signs in via Supabase Auth → receives a JWT (RS256-signed by Supabase).
2. Every request to the Fastify API includes the JWT as `Authorization: Bearer <token>`.
3. Fastify verifies the token via Supabase's **JWKS endpoint** (`<project>.supabase.co/auth/v1/.well-known/jwks.json`) using `@fastify/jwt` + `jwks-rsa`.
4. Decoded claims populate `request.user`; protected route handlers read `request.user.sub` (= `users.id`).

### Why JWKS, not shared `SUPABASE_JWT_SECRET`

- No shared secret to rotate.
- Survives Supabase key rotations without redeploying the API.
- Standard pattern; future-proof if you ever swap auth providers.

### JWKS client config (must pin)

Default `jwks-rsa` config is too loose. Configure explicitly on `apps/api` boot:

```ts
jwksRsa({
  jwksUri: `${process.env.SUPABASE_URL}/auth/v1/.well-known/jwks.json`,
  cache: true,
  cacheMaxAge: 10 * 60 * 1000,   // 10 min — refreshes ahead of typical Supabase key rotation lag
  cacheMaxEntries: 5,
  rateLimit: true,                // block JWKS endpoint hammering on key-rotation thrash
  jwksRequestsPerMinute: 10,
})
```

Without `cache: true` + `rateLimit: true`, every request fetches JWKS (latency + Supabase rate-limit risk). Without a `cacheMaxAge` cap, a key rotation can keep stale keys cached past Supabase's grace window and 401 every request until restart.

### DB role + authorization (where the user filter lives)

The Fastify API connects to Postgres as the **Supabase service role**. The service role bypasses RLS, so every route handler is responsible for filtering by `request.user.sub`. Authorization lives in app code, not in the database.

- The mobile app talks to Supabase directly **only** for auth (sign-in, refresh). It does not query data tables directly — all data flows through Fastify.
- **All DB access in the API goes through a `db.forUser(userId)` helper** that returns a thin query builder pre-bound to a `user_id` filter. Forgetting the filter requires actively reaching past the helper, not just forgetting a `WHERE` clause.
- **RLS is still enabled on every user-scoped table** with default-deny policies (`user_id = auth.uid()`, plus the template-visibility carveout in the data model section). The service role bypasses RLS in normal operation, but if a future feature ever connects with the anon key (debug tools, web admin), the defenses fall back on instead of leaking everything.
- **Driver: `node-postgres` (`pg`) with parameterized queries via `$1`/`$2`, NOT named prepared statements (D90).** Transaction pooler (port 6543, `pgbouncer=true`) does not support named prepared statements — they silently break at concurrency. Set `statement_timeout` on the connection to prevent runaway queries. Prisma was eliminated because its transaction-pooler story has more sharp edges.

### Token refresh (mobile side)

- `supabase.auth.getSession()` is wrapped by a **singleton refresh promise** in `apps/mobile/src/lib/api-client.ts`. N parallel queries on cold start collapse to one underlying `getSession()` / `refreshSession()` call — otherwise N parallel refreshes thunder onto Supabase Auth and one wins, the rest reject.
- On a 401 from the API, the client awaits a single in-flight `refreshSession()` (creating one if none is running), retries the request once, and signs out on second failure.
- **`refreshSession()` can resolve with `{ session: null }` instead of throwing** when the refresh token itself has expired (user offline >30 days, password changed elsewhere). Code path must check `session === null` AND catch errors — both branches trigger sign-out (D89).
- Use `refreshSession()` not raw `getSession()` for proactive refresh ~60s before `expires_at` to absorb clock skew.
- `supabase.auth.onAuthStateChange` on `SIGNED_OUT` events calls **both** `queryClient.clear()` AND `queryClient.getMutationCache().clear()` (D93). Without clearing the mutation cache, dehydrated mutations replay on next launch with stale `Authorization` headers → 401 sign-out loop.

### Rate limiting

- `@fastify/rate-limit` on **all** `/agent/*` routes. LLM calls are unbounded cost otherwise — a misbehaving client (or compromised key) can run up a huge bill.
- Conservative initial limits: 30 req/min per user, 200/day per user.
- Lighter limits on other routes (200/min per user, soft).

### Env schema

- `packages/shared/env.ts` defines the env schema with `zod`.
- Both `apps/api` and `apps/mobile` import and parse it on boot. Missing/malformed env crashes loudly at startup, not at request time.
- CI step diffs `heroku config -s` against the schema's required keys and fails the build on drift.

### CORS

- **Not needed for v1.** Native React Native does not enforce CORS — the request is a raw HTTP call, not a browser fetch.
- Revisit `@fastify/cors` if/when a web client (admin tool, marketing site, debug build) lands.

---

## Observability, reliability & deployment

### Observability

- **Sentry** (free tier, 5k events/mo) on both `apps/mobile` (via `@sentry/react-native` + EAS source-map upload) and `apps/api` (via `@sentry/node`).
- **`pino`** (Fastify's built-in logger) configured for JSON output.
- **Heroku log drain → Better Stack** (free tier) for searchable log retention beyond Heroku's 1500-line buffer.
- **Uptime monitoring (D88)**: UptimeRobot free tier pings `/health` every 5 min. Sentry catches in-app errors; Better Stack stores logs; neither detects a dyno 503-ing or the Heroku→Supabase pooler dying.

### Reliability

- **Daily `pg_dump` cron** via GitHub Actions → Cloudflare R2 bucket. Supabase free tier has **no PITR**; if you delete a row by accident at 3am, this is your only recovery path.
- **Supabase keepalive cron**: GitHub Actions hits `/health` (which executes a trivial DB query) every 3 days. Prevents the 7-day inactivity pause from biting during recruiter demos.
- **Single region: `us-east-1`** for both Heroku and Supabase. Cross-region adds 80–150ms per query — the agent loop (~3 tool calls × multiple roundtrips) compounds this into seconds.

### Heroku deployment specifics

- **Multi-stage Dockerfile** based on `node:20-alpine`.
- **`pnpm deploy --prod --filter api`** in the builder stage produces a self-contained `api` artifact without `apps/mobile` deps. Naive `pnpm install` in a monorepo copies the entire workspace into the image.
- Final image stays under ~200MB; well within Heroku's 10GB limit and the 15-minute build timeout.
- **Auth token** for `heroku container:push`: use a long-lived authorization token (`heroku authorizations:create`), not a user API key. Store as GitHub secret `HEROKU_API_KEY`.
- **Eco/Basic dyno cycling**: 24h auto-restart + 30min idle sleep on Eco. Cold start is 5–15s for a Node container. Either pay for Basic ($7/mo) + add a keepalive ping, or accept the cold start and design a loading state for the first request after sleep.
- **Connection pooling**: connect to Supabase via the **transaction pooler on port 6543** with `pgbouncer=true` in the connection string. The direct connection pool caps at ~60 and will exhaust under any concurrency.
- **Custom domain + TLS**: bind a free subdomain (e.g. `api.lockedin.app` via Cloudflare/Namecheap) to the Basic dyno and provision a free **Heroku Automated Certificate Management (ACM)** cert. Required so the mobile app can hit a stable HTTPS URL — `*.herokuapp.com` works for testing but binding it permanently into a TestFlight build is the wrong move (you can't move backends without resubmitting). Configure in week 1, not week 12.
- **ACM cert issuance gotcha (D87)**: if DNS is behind Cloudflare, set the CNAME to **grey-cloud (DNS-only mode)** during initial cert provisioning. Cloudflare's orange-cloud proxy breaks Heroku ACM's HTTP-01 challenge and can brick cert issuance for ~24h. After the cert is issued, you can flip to orange-cloud if you want Cloudflare's CDN/DDoS benefits.

### AWS deploy specifics (demo-only)

- **ECR lifecycle policy on day one.** ECR free tier is 500MB **per account**, not per repo. Without a lifecycle policy, every CI push accumulates and you blow the free tier in a few months. Configure: keep the latest 3 images tagged `prod-*`, expire untagged images after 7 days. One-line CloudFormation/Terraform or via the console — do it when the repo is created, not "later."
- **OIDC, not access keys, for GH Actions → AWS.** Configure an IAM role with a trust policy on the GitHub OIDC provider. No long-lived AWS credentials in GH secrets. Standard pattern; not optional.
- **OIDC trust scope (D91)**: the `sub` condition in the role's trust policy must be scoped to `repo:Fritozz-105/LockedIn:ref:refs/heads/main`, NOT `repo:Fritozz-105/*:*`. Without scoping, any branch or forked repo could assume the role and push to ECR.
- **t2.micro memory ceiling (D92)**: 1 GB RAM with Node baseline ~80MB + ECS agent ~150MB leaves ~700MB for the app. Set `NODE_OPTIONS=--max-old-space-size=400` in the ECS task definition to prevent OOM-kills during the demo. Document in README that AWS is sized for demo loads only.
- **Public IP on task is plain HTTP only.** Document in the README that the AWS endpoint is reachable via `curl http://<task-ip>/health` for verification but is not the mobile app's backend (App Transport Security blocks plain HTTP). This is the honest framing the resume bullet relies on.

### Heroku credit horizon

- **1 year of credits available.** The real deadline is the 12-week TestFlight build, not the credits. Day-after-credits-expire cost is ~$32/mo (Heroku Basic $7 + Supabase Pro $25 if you haven't already upgraded).

### Supabase storage watch

- **Free tier: 500MB DB.** Per-set rows × 6 days/wk × ~25 sets × 24 weeks ≈ 22k `exercise_set` rows per active user per 6 months, plus chat history. Order-of-magnitude ceiling: ~500–2000 active users.
- **If storage crosses ~400MB**, upgrade to Supabase Pro ($25/mo) before launching publicly. No active monitoring needed at this scale — check the dashboard every couple of weeks.

---

## Data model (workout tracker)

### Hierarchy

```
mesocycle
  └─ mesocycle_week (×N, where N = mesocycle.total_weeks)
       └─ workout (one per training day in that week)
            └─ workout_exercise (an exercise slot in the workout)
                 └─ exercise_set (one row per set — planned or logged)
                      └─ exercise_set (dropset child, via parent_set_id)
```

### Tables

```
users                                 -- mirrors auth.users; app-level profile
  id                  uuid (PK, FK -> auth.users.id)
  display_name        text?
  unit_preference     text             -- 'kg' | 'lb' (user-level default for new logs)
  created_at          timestamptz

exercise_library
  id                  uuid (PK)
  slug                text unique               -- "barbell-bench-press" — stable across reseeds
  name                text                      -- "Barbell Bench Press"
  primary_muscle      muscle_group              -- enum (kept for fast filters; authoritative volume comes from exercise_muscle)
  equipment           equipment_type            -- enum
  mechanic            mechanic_type             -- enum: 'compound' | 'isolation'
  movement_pattern    movement_pattern_type?    -- enum: horizontal_push | vertical_push | horizontal_pull | vertical_pull | squat | hinge | lunge | carry | isolation
  is_unilateral       boolean
  description         text?
  default_rep_min     smallint?
  default_rep_max     smallint?
  image_url           text?
  is_custom           boolean
  created_by_user_id  uuid?                     -- null for system exercises

exercise_muscle                        -- replaces the secondary_muscles[] array
  exercise_id         uuid FK -> exercise_library(id)
  muscle              muscle_group
  contribution        numeric(3,2)              -- 1.00 for primary; e.g. 0.50 for strong secondaries, 0.25 for incidental
  PRIMARY KEY (exercise_id, muscle)

mesocycle
  id                  uuid (PK)
  user_id?            uuid FK -> users(id)      -- null = system template
  name                text
  total_weeks         smallint
  start_date?         date                      -- null on templates; NOT NULL on instances (enforced by CHECK)
  is_template         boolean
  template_id?        uuid FK -> mesocycle(id)  -- the template this instance was cloned from (if any)
  created_at, archived_at?
  -- Templates: user_id=null, is_template=true, start_date=null
  -- User instances: user_id=<them>, is_template=false, start_date=<when they started>
  CHECK (is_template = true OR (user_id IS NOT NULL AND start_date IS NOT NULL))

mesocycle_week
  id, mesocycle_id, week_number,      -- 1..total_weeks
  user_id?,                           -- DENORMALIZED for query speed + RLS; matches parent mesocycle.user_id
  notes?

workout                               -- one training "day"
  id, week_id, day_number,            -- 1..7
  user_id?,                           -- DENORMALIZED
  name,                               -- "Push A", "Legs", etc.
  notes?
  -- No explicit start/finish columns. Completion state is derived from child set completion:
  --   no sets have completed_at         => planned
  --   some sets have completed_at       => in progress
  --   all sets have completed_at        => completed

workout_exercise                      -- an exercise slot in a workout
  id, workout_id, exercise_id (FK -> exercise_library),
  user_id?,                           -- DENORMALIZED
  position,                           -- ordering within the workout
  superset_group_id?  smallint,       -- if non-null, this exercise is part of a superset; same value = paired
  target_sets, target_rep_min, target_rep_max,    -- AUTHORITATIVE rep range (exercise_library.default_rep_* is only a seed hint)
  notes?

exercise_set                          -- one row per set, planned or logged
  id,
  workout_exercise_id   FK -> workout_exercise(id) ON DELETE CASCADE,    -- D79
  set_number          smallint,       -- DROPSET SEMANTICS: dropset children share their parent's set_number — it acts as a group ID, not a unique key. "Next working set #" = MAX(set_number) WHERE parent_set_id IS NULL. "Working sets logged" = COUNT(*) WHERE parent_set_id IS NULL AND completed_at IS NOT NULL.
  user_id?,                           -- DENORMALIZED (critical: every AI agent tool filters on this)
  exercise_id?        uuid FK -> exercise_library(id),   -- DENORMALIZED from workout_exercise. Lets get_volume_per_muscle_group skip the workout_exercise hop. Stamped at instantiation, copied on cascade. Exercise substitution = delete+recreate the workout_exercise slot (child sets cascade), never mutate the FK.
  planned_weight,    planned_reps,    -- baseline prescription; written at instantiation. Rewritten by the "apply to future weeks" cascade on unlogged rows; otherwise immutable.
  weight,            reps,            -- mutable per-row; equals planned_* on planned rows, gets stamped on log
  weight_unit         text,           -- 'kg' | 'lb' — snapshot of user's pref at log time
  rir?,
  parent_set_id?      FK -> exercise_set(id) ON DELETE CASCADE,          -- D79: non-null = this set is a dropset of parent
  drop_order?         smallint,       -- 1, 2, 3, ... for ordering within a drop chain (NULL on non-dropsets)
  is_warmup           boolean DEFAULT false,   -- D83: warmup sets excluded from volume queries (COUNT(*) WHERE is_warmup = false)
  completed_at?                       -- null = planned but not yet performed
  UNIQUE (workout_exercise_id, set_number, drop_order) -- D79; treats NULL drop_order as distinct (Postgres default)

body_weight                           -- D82: was a TODO; landed here
  id,
  user_id   FK -> users(id) ON DELETE CASCADE,
  logged_at date,
  weight    numeric(5,2),
  weight_unit text,                   -- 'kg' | 'lb'
  created_at timestamptz,
  UNIQUE (user_id, logged_at)         -- prevents accidental double-log of same morning

agent_conversation
  id, user_id, title?, created_at, last_message_at

agent_message
  id, conversation_id, role,          -- 'user' | 'assistant' | 'tool'
  content text,                       -- for tool messages: JSON-stringified tool result, capped at ~4KB
  tool_calls jsonb?,                  -- on assistant messages that requested tools
  tool_call_id text?,                 -- on tool-role messages
  created_at
```

### Enums

```
muscle_group:           chest, back, lats, traps, shoulders, biceps, triceps,
                        quads, hamstrings, glutes, calves, abs, forearms, neck

equipment_type:         barbell, dumbbell, cable, machine, smith, bodyweight,
                        kettlebell, band, plate, other

mechanic_type:          compound, isolation

movement_pattern_type:  horizontal_push, vertical_push, horizontal_pull, vertical_pull,
                        squat, hinge, lunge, carry, isolation
```

### Indexes (must be in initial migration, not added later)

```
-- Hot path: get_workout_history filters by user + exercise + completion (set-by-set fade per lift across time)
CREATE INDEX exercise_set_user_exercise_completed_idx
  ON exercise_set (user_id, exercise_id, completed_at DESC)
  WHERE completed_at IS NOT NULL;

-- Hot path: get_volume_per_muscle_group by time window. INCLUDE (exercise_id) for index-only scan
-- on the join key. (D81)
CREATE INDEX exercise_set_user_completed_idx
  ON exercise_set (user_id, completed_at DESC)
  INCLUDE (exercise_id)
  WHERE completed_at IS NOT NULL AND is_warmup = false;

-- Hot path: render a workout's sets in order
CREATE INDEX exercise_set_we_setnum_idx
  ON exercise_set (workout_exercise_id, set_number, drop_order NULLS FIRST);

-- Dropset child lookup
CREATE INDEX exercise_set_parent_idx
  ON exercise_set (parent_set_id) WHERE parent_set_id IS NOT NULL;

-- User's mesocycle list + cross-mesocycle progression queries (ordered by start_date)
CREATE INDEX mesocycle_user_archived_idx
  ON mesocycle (user_id, archived_at);
CREATE INDEX mesocycle_user_startdate_idx
  ON mesocycle (user_id, start_date DESC)
  WHERE is_template = false;

-- Exercise library
CREATE UNIQUE INDEX exercise_library_slug_idx ON exercise_library (slug);
CREATE INDEX exercise_library_primary_muscle_idx ON exercise_library (primary_muscle);

-- exercise_muscle: lookup by muscle for volume queries
CREATE INDEX exercise_muscle_muscle_idx ON exercise_muscle (muscle);

-- Agent chat
CREATE INDEX agent_message_conversation_idx ON agent_message (conversation_id, created_at);

-- NOTE: body_weight table is omitted from the schema block above. Add it before scaffolding step 9:
--   body_weight (id, user_id, logged_at date, weight numeric, weight_unit text, created_at)
--   CREATE INDEX body_weight_user_logged_idx ON body_weight (user_id, logged_at DESC);
```

### Row Level Security (RLS) policies

Service-role bypass is the API's normal path (see "DB role + authorization" in Auth & API security). Policies still exist for defense-in-depth.

```sql
-- User-scoped tables (mesocycle, mesocycle_week, workout, workout_exercise, exercise_set,
-- body_weight, agent_conversation, agent_message): default-deny, with a single read-write policy
-- gated on user_id. Template visibility is the only carveout.

ALTER TABLE mesocycle ENABLE ROW LEVEL SECURITY;
CREATE POLICY mesocycle_owner ON mesocycle
  USING (user_id = auth.uid());
CREATE POLICY mesocycle_templates_public ON mesocycle FOR SELECT
  USING (is_template = true);

-- Same pattern (sans the templates carveout) on every other user-scoped table.

-- Exercise library: readable by all authenticated users; writable only when is_custom = true
-- AND created_by_user_id = auth.uid().
ALTER TABLE exercise_library ENABLE ROW LEVEL SECURITY;
CREATE POLICY exercise_library_read_all ON exercise_library FOR SELECT
  USING (auth.role() = 'authenticated');
CREATE POLICY exercise_library_custom_owner ON exercise_library FOR ALL
  USING (is_custom = true AND created_by_user_id = auth.uid());
```

### Enums

```
muscle_group:    chest, back, lats, traps, shoulders, biceps, triceps,
                 quads, hamstrings, glutes, calves, abs, forearms, neck

equipment_type:  barbell, dumbbell, cable, machine, smith, bodyweight,
                 kettlebell, band, plate, other
```

### Key design choices

- **Per-set logging, not per-exercise.** A flat `weight × sets × reps` model can't represent fade across sets (185×8, 185×7, 185×6, 185×5) — which is the exact signal progressive-overload analysis needs.
- **`user_id` denormalized down the workout tree.** Otherwise every AI agent query becomes a 6-table join and every Supabase RLS policy becomes a multi-level `EXISTS` clause. Write cost: trivial (set during template instantiation, copied on cascade). Query/security cost: huge improvement.
- **Dropsets via `parent_set_id` + `drop_order`.** A dropset *is* a set with no rest after its parent. `drop_order` (1, 2, 3, …) handles triple-drops and gives a stable render order — UI sorts `(set_number ASC, drop_order ASC NULLS FIRST)`. `didDropSet?` is derived: "does any row reference this row as parent?" **`set_number` on a dropset child equals the parent's `set_number`** — it's a group ID, not a unique key. Anything that wants "how many working sets" must filter `WHERE parent_set_id IS NULL`; anything that wants "render order" sorts by `(set_number, drop_order)`.
- **`planned_*` vs logged `weight`/`reps`**. `planned_weight`/`planned_reps` are stamped at template instantiation. `weight`/`reps` start equal to planned, then get updated on log. This preserves "what the program prescribed" — at the row level — when a user edits one set's actual weight mid-workout.
- **Cascade ("apply to future weeks") rewrites planned_* on unlogged rows.** When a user edits Wk N's bench press to 195×8 and picks "apply forward," the cascade updates **both** `planned_weight`/`planned_reps` **and** `weight`/`reps` on every unlogged row in weeks N+1…final for that exercise. Rationale: "apply to future weeks" means "the plan has changed," not "log a one-off." Already-logged rows (`completed_at IS NOT NULL`) are never touched by the cascade — historical truth is preserved. Per-row immutability of `planned_*` thus holds for individual edits but not for cascades; the UI must make the difference visible (e.g., "this updates weeks 3-6").
- **Cascade vs exercise substitution (D80)**: cascade matches on `exercise_id`. If the user previously substituted bench → incline bench in week 5, the cascade will skip week 5 (different `exercise_id`). The UI **must show a confirmation modal** listing which weeks will be updated and which will be skipped (e.g., *"This will update bench press in weeks 3, 4, 6. Week 5 has been substituted to incline bench — skipped. Continue?"*). Silent skip is wrong UX; the user should see the mismatch.
- **`weight_unit` snapshotted onto every `exercise_set`.** User can toggle kg ↔ lb without corrupting history. Display reads the stored unit per row; no on-the-fly conversion of historical data.
- **Muscle contribution via `exercise_muscle` join table, not `secondary_muscles[]`.** Array column can't carry per-muscle contribution weights, and `get_volume_per_muscle_group` needs them (e.g. bench bars trizonal contribution at 0.5 for triceps and 0.25 for front delts). Primary muscle is also in the join table at 1.0; the `primary_muscle` column on `exercise_library` is a denormalized cache for fast filters in the picker UI.
- **`exercise_id` denormalized onto `exercise_set`.** Same logic as denormalizing `user_id` — `get_volume_per_muscle_group` and `get_workout_history` would otherwise climb back through `workout_exercise` for a value that never changes after instantiation. Stamped at instantiation, copied on cascade. With this in place the volume query is a clean 2-table join: `exercise_set` filtered by `(user_id, completed_at)` → joined to `exercise_muscle` on `exercise_id`, summed weighted by `contribution`.
- **Dropsets count as full sets for volume.** `get_volume_per_muscle_group` is `COUNT(*) FROM exercise_set WHERE completed_at IS NOT NULL AND is_warmup = false` joined with `exercise_muscle.contribution` — each dropset row contributes its `contribution` weight independently. Weighted dropset counting (e.g., 0.5× because of shorter rest) is a v1.1 refinement if it becomes useful.
- **Warmup sets excluded from volume (D83).** `is_warmup boolean DEFAULT false` on `exercise_set`. UI offers a "mark as warmup" toggle when adding sets. All volume queries filter `WHERE is_warmup = false`. Without this, warmup-heavy programs inflate volume metrics and break the AI agent's recommendations.
- **Supersets via `superset_group_id` on `workout_exercise`.** Two or more exercises in the same workout sharing a `superset_group_id` value are paired. UI renders them grouped; user logs one set of A, one of B, repeat. The value itself is just a small integer (1, 2, 3…) scoped within a single workout — no `superset` table needed.
- **`default_rep_range` source of truth.** `workout_exercise.target_rep_min/max` is **authoritative** at the workout-instance level. `exercise_library.default_rep_min/max` is only a starting hint used when authoring/instantiating templates. The two are allowed to drift; the workout always wins.
- **`completed_at` distinguishes plan from log.** Same row, two states. Server stamps `completed_at` — never accept a client timestamp (avoids optimistic-update race).
- **Notes at the `workout_exercise` level**, not per set. Form cues and "felt heavy" are per-exercise observations.
- **`total_weeks` on mesocycle; workouts under weeks.** "Exercises per week" is derived (`COUNT(*)`). Different weeks can differ (deloads).
- **Exercise library is shared.** ~100 system entries (`is_custom=false`). Users add custom ones (`is_custom=true, created_by_user_id=<them>`).
- **Template instantiation fully expands all weeks.** Deep-copy all rows under the template with the new `user_id`. Postgres won't notice the duplication.
- **Week-edit semantics.** When editing a workout in week N, the UI presents a toggle: *"apply to this week only"* (default) vs *"apply to all future weeks of this mesocycle"*. No schema change needed — the second option just cascades the edit across weeks N+1…final.
- **Mesocycle state: just `archived_at`, no `status` enum.** Active = `archived_at IS NULL`. Archived = non-null. We don't distinguish "completed" from "abandoned" in v1 — most users don't care. A `status` enum (`active`, `completed`, `abandoned`) is a v1.1 refinement if it becomes useful for analytics.

### Sample data (Push Day, set 4 of bench with a double-dropset)

```
workout_exercise:  id=42, exercise=BarbellBench, target_sets=4, rep_range=6-8, notes="control eccentric"
exercise_set:      id=101, we_id=42, set#=1,  185 × 8, rir=2, completed_at=...
exercise_set:      id=102, we_id=42, set#=2,  185 × 7, rir=1, completed_at=...
exercise_set:      id=103, we_id=42, set#=3,  185 × 6, rir=0, completed_at=...
exercise_set:      id=104, we_id=42, set#=4,  185 × 5, rir=0, completed_at=...           -- top set
exercise_set:      id=105, we_id=42, set#=4,  135 × 8, parent_set_id=104, drop_order=1   -- first drop
exercise_set:      id=106, we_id=42, set#=4,   95 × 8, parent_set_id=104, drop_order=2   -- second drop
```

UI render query for this exercise:
```sql
SELECT * FROM exercise_set
WHERE workout_exercise_id = 42
ORDER BY set_number ASC, drop_order ASC NULLS FIRST;
```

---

## Mobile architecture

### Routing — Expo Router

File-based routing built on top of React Navigation. The file path *is* the route. Modern Expo default; what their docs assume. Lets you drop down to React Navigation primitives when needed.

### State management — three layers

| Kind | Used for | Tool |
|---|---|---|
| **Server state** | Workouts, body weight history, mesocycles, exercise library, anything from the API | **TanStack Query** |
| **Global client state** | Logged-in user, theme, in-progress workout session | **Zustand** (or Supabase's `useUser` for auth specifically) |
| **Local UI state** | Form inputs, modal toggles | `useState` |

**TanStack Query is non-negotiable.** Caching, background refetch, loading/error states, and — critically — **optimistic mutations** (set logging must feel instant; the UI updates before the server confirms). Without optimistic updates, the app feels like a sluggish website.

### Offline persistence

- A gym app *will* be used in spotty connectivity (basement gyms, no LTE).
- Use **`@tanstack/query-async-storage-persister`** with **`expo-sqlite/kv-store`** (faster than AsyncStorage in 2026) to persist the query cache across app restarts.
- **Mutation replay is not automatic.** TanStack Query v5 defaults to *not* dehydrating mutations and *not* auto-resuming them. Explicit setup required:
  ```ts
  persistQueryClient({
    queryClient,
    persister,
    dehydrateOptions: {
      shouldDehydrateMutation: () => true,   // v5 default is false — mutations disappear without this
    },
  });

  onlineManager.subscribe((isOnline) => {
    if (isOnline) queryClient.resumePausedMutations();   // onlineManager gates, doesn't drive replay
  });
  ```
- Without both pieces, queued offline set-logs silently vanish on app reopen and reconnect.

### Optimistic mutation pattern (set logging)

Set logging fires rapidly during a workout; naive optimistic updates race. The pattern:

- **Per-row `scope: { id: setId }`** on the mutation (TanStack Query v5). `mutationKey` alone doesn't serialize network calls — `scope` does. Two rapid taps on the same set queue serially instead of firing parallel POSTs that interleave.
- **Client-generated `idempotency_key` (UUID v4) on every set-log POST.** Stored alongside the optimistic row. Server keeps a **48-hour (D94)** dedupe table keyed by `(user_id, idempotency_key)` — duplicate POSTs return the existing row instead of inserting twice. Without this, retry-once-on-5xx + a flaky network = double-logged sets. **48h not 1h**: real offline windows (gym vacation, dead phone) exceed 1h.
- **Orphaned-row reconciliation on rehydrate (D94)**: on app launch, walk the persisted cache for optimistic rows older than 24h with no matching server row (by `idempotency_key`); purge them. Without this, app-kill mid-mutation leaves optimistic rows in the cache forever.
- **`onMutate`**: cancel in-flight queries for the workout, snapshot the cache, write the optimistic update.
- **`onError`**: roll back to snapshot.
- **`onSettled`**: invalidate the workout query.
- **Server stamps `completed_at`** (server-authoritative timestamp); client uses a sentinel value like `'now'` and reads back the true timestamp from the response. Never write `completed_at = Date.now()` on the client — clocks drift and you'll see ordering bugs.

### Metro + pnpm workspaces config (critical, breaks easily)

**Strategy: pnpm hoisting (not symlinks).** Two valid approaches exist for pnpm + Metro: `node-linker=hoisted` (mimics npm/yarn layout) or `unstable_enableSymlinks` (preserves pnpm's symlinked store, requires Metro/Expo SDK with stable symlink support). Hoisting is the safer first-mobile-app choice — RN native modules expect the npm-style flat layout, and symlink resolution has bitten Metro repeatedly across SDK versions. Commit to hoisting; revisit only if it causes actual problems.

`metro.config.js` in `apps/mobile/`:

```js
const path = require('path');
const { getDefaultConfig } = require('expo/metro-config');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');

const config = getDefaultConfig(projectRoot);
config.watchFolders = [workspaceRoot];
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];
config.resolver.disableHierarchicalLookup = true;
// zod and other CJS-only packages need .cjs in source extensions (Metro defaults omit it)
config.resolver.sourceExts = [...config.resolver.sourceExts, 'cjs', 'mjs'];

module.exports = config;
```

`.npmrc` at the repo root:
```
node-linker=hoisted
public-hoist-pattern[]=*
```

**Pin React + React Native at the workspace root** (`package.json` `pnpm.overrides` or `resolutions`) so hoisting can't produce two copies if `apps/api` ever pulls in a transient React dep. Two Reacts = "Invalid hook call" runtime crash with no useful stack.

```json
// package.json (workspace root) — concrete pins for Expo SDK 54 (D85)
"pnpm": {
  "overrides": {
    "react": "19.1.0",
    "react-native": "0.81"
    // No react-dom pin — Expo SDK 54 doesn't bundle RN-web by default.
  }
}
```

Without all of the above, `@lockedin/shared` resolves but its transitive `zod` doesn't, or two Reacts collide at runtime, or pnpm's default symlink store breaks RN native modules.

### Expo Router auth gating

- Use the `(auth)` group for unauthenticated routes and the `(tabs)` group for authenticated.
- Gate via `<Stack.Protected guard={!!session}>` (Expo Router SDK 53+) or a `_layout.tsx` redirect (`<Redirect href="/sign-in" />` based on session).
- **Gate in render**, not in `useEffect` — redirects from effects cause flicker.
- **Three-state session handling (D95)**: `session: undefined | null | Session`. Stored in a Zustand auth store; root `_layout.tsx` branches:
  - `undefined` = bootstrap not finished → render splash screen (no nav)
  - `null` = signed out → render `(auth)` group
  - `Session` = signed in → render `(tabs)` group
  - Without the three-state model, the auth group flashes on cold start while session loads.

### Workout detail route placement

- `app/workout/[workoutId].tsx` lives **outside** the `(tabs)` group on purpose. The tab bar disappears during active workout logging — focused mode, no distractions.
- Standard pattern (Strong, Hevy, Jefit all do this). Back from the workout returns to the tab where the user came from.

### Dark mode (v1, D96)

Dark mode ships in v1 (timeline permits per D86).

- Use `useColorScheme` from `nativewind` (NOT the React Native one) — returns the current scheme and reacts to system changes.
- Theme tokens defined in `tailwind.config.js` with `dark:` variants on every color reference: `bg-white dark:bg-zinc-900`, `text-zinc-900 dark:text-zinc-100`, etc.
- All custom components must support both schemes — establish via a `<ThemedCard>` / `<ThemedText>` primitive set in `src/components/` rather than per-screen `dark:` sprinkles.
- Manual override (light/dark/system) stored in Zustand + AsyncStorage; applied via NativeWind's `colorScheme.set()`.
- ~3-4 days additional design + test work absorbed into weeks 5-9.

### NativeWind helpers

- Add `src/lib/cn.ts` exporting a `cn()` helper that wraps `clsx` + a NativeWind-aware `tailwind-merge`:
  ```ts
  import clsx from 'clsx';
  import { extendTailwindMerge } from 'tailwind-merge';

  // Stock twMerge doesn't know about NativeWind's `dark:`, `ios:`, `android:` variants
  // and will produce wrong "last-wins" merges (e.g. dropping `dark:bg-black` against `bg-white`).
  const twMerge = extendTailwindMerge({
    extend: {
      classGroups: {
        // Add NativeWind-specific groups as you actually use them; start with the platform variants.
      },
    },
  });

  export const cn = (...inputs: Parameters<typeof clsx>) => twMerge(clsx(inputs));
  ```
- **Avoid dynamic class strings** like `` `bg-${color}-500` `` — NativeWind tree-shakes Tailwind classes at build time and dynamic strings won't be detected. Use a lookup map of full class names, or `cssInterop` for runtime styling.
- NativeWind v4 also requires `jsxImportSource: "nativewind"` in `tsconfig.json` and the Babel preset order matters: `nativewind/babel` then `react-native-reanimated/plugin` **last**. Reanimated's plugin must be the final entry in `babel.config.js` `plugins` — wrong order = the app silently runs without Reanimated's worklet transform.

### Deep linking

- Stub `expo-linking` in the root `_layout.tsx` from day one, even though push notifications are deferred.
- Configure URL scheme in `app.json` (e.g., `lockedin://`). Cheap insurance — adding it later when notifications land means retrofitting a moving target.

### Accessibility (minimum baseline)

Not pursuing WCAG 2.1 AA in v1, but every screen meets a minimum:

- **Screen-reader labels** on every actionable element (`accessibilityLabel` on touchables, descriptive text on icons).
- **No color-only state indicators** — use shape, position, or text alongside color (the body-weight chart's "trending down" indicator can't be red alone).
- **Text scales with system font size** — use `Text` defaults; avoid hardcoded `fontSize` without responding to `useWindowDimensions`.
- **Tap targets ≥ 44pt** — Apple HIG minimum; particularly the set-completion buttons.

Full a11y audit (focus order, contrast ratios, VoiceOver/TalkBack testing) is a v1.1 task.

**Lint enforcement (D97)**: add `eslint-plugin-react-native-a11y` to dev deps with the recommended config. Without lint, the a11y baseline drifts within 2 weeks on a solo project — labels get forgotten on new components.

### Styling — NativeWind

Tailwind for React Native. Fastest iteration, biggest community, easy to keep visual consistency. If Tailwind feels alien, fall back to `StyleSheet.create()` + theme constants.

### Mobile-specific concerns to bake in

- **Lists use `FlatList`** (virtualized), never `.map()` over arrays of ~50+ items.
- **Safe area insets**: wrap screens in `SafeAreaView` or use `react-native-safe-area-context`.
- **Keyboard handling**: `KeyboardAvoidingView` for inputs near the bottom of the screen (set logging will hit this constantly).
- **Gestures**: `react-native-gesture-handler` + `react-native-reanimated` (both included with Expo).
- **Optimistic updates** on every set log, weight log, and mesocycle edit.

### EAS Build + Sentry source maps

- `@sentry/react-native` ships an Expo config plugin. Add it to `app.json` under `plugins`:
  ```json
  ["@sentry/react-native/expo", { "organization": "<sentry-org>", "project": "<sentry-project>" }]
  ```
- `SENTRY_AUTH_TOKEN` must be set as an **EAS secret** (`eas secret:create`), not an env var — env vars in `.env` don't reach the EAS Build container. Without it, source maps don't upload and Sentry shows bytecode offsets, not stack traces.
- Hermes bytecode source maps need an explicit upload step in `eas-build-post-install` (the Sentry expo plugin handles this automatically as of recent versions — verify the upload happens by checking the EAS Build log for `Source maps successfully uploaded`).
- **Verify on a release/TestFlight build, NOT dev (D99)**: the "Source maps successfully uploaded" log line covers JS source maps. Hermes bytecode (`.hbc.map`) is a separate concern. Throw a deliberate error from a debug screen on an actual TestFlight build, confirm Sentry shows the actual JS file/line, not `<anonymous>` at `index.android.bundle:1`. Dev builds use the Metro dev server and naturally show source maps — they don't prove the release path works.

### Testing infrastructure (D98)

Spec'd before scaffolding step 11 so test setup doesn't get hand-wavy.

- **Preset**: `jest-expo` (handles RN + Expo module transforms).
- **Route mocking**: `expo-router/testing-library` for Stack/Tab navigation tests.
- **API mocking**: **MSW v2** (Mock Service Worker) — intercepts at the network layer, works with TanStack Query naturally.
- **MSW polyfill**: MSW v2 requires `whatwg-fetch` polyfill in `jest.setup.js`; RN's native `fetch` isn't a full WHATWG implementation.
- **Test file layout**: colocated under each `src/features/*/__tests__/` — same archaeology rule as feature folders.
- **Coverage targets**: pure logic only (template expansion, dropset ordering, rolling-average trend, agent tool-result truncation). UI smoke tests via RNTL on the highest-traffic screens (workout detail, set logging). No E2E in v1 (D46).

### Shared query-key factory

Feature-local `api.ts` files (e.g. `src/features/workout/api.ts`) use TanStack Query keys like `['workout', workoutId]`. The `mesocycle` feature reads the same workout from a different angle. Inline string keys = typos cause silent cache misses.

Put a single key factory in `src/lib/query-keys.ts`:

```ts
export const queryKeys = {
  workout: {
    all: ['workout'] as const,
    detail: (id: string) => ['workout', id] as const,
  },
  mesocycle: {
    all: ['mesocycle'] as const,
    detail: (id: string) => ['mesocycle', id] as const,
    current: ['mesocycle', 'current'] as const,
  },
  bodyWeight: {
    all: ['bodyWeight'] as const,
    trend: (days: number) => ['bodyWeight', 'trend', days] as const,
  },
  agent: {
    conversation: (id: string) => ['agent', 'conversation', id] as const,
  },
} as const;
```

Every feature imports from one place. `queryClient.invalidateQueries({ queryKey: queryKeys.workout.all })` invalidates everything workout-shaped without string archaeology.

### Repo layout — pnpm workspaces monorepo

Needed so `apps/mobile` and `apps/api` can both import zod schemas from `packages/shared`. Lightest possible monorepo — no Turborepo/Nx until there's a real reason.

```
LockedIn/
├── apps/
│   ├── mobile/                       ← Expo app
│   └── api/                          ← Fastify backend
├── packages/
│   └── shared/                       ← zod schemas + shared TS types
├── docs/
├── package.json                      ← workspaces root
├── pnpm-workspace.yaml
└── tsconfig.base.json
```

### Mobile folder structure (`apps/mobile/`)

```
app/                                  ← Expo Router (file = route). Keep thin: wire data + render.
├── _layout.tsx                       ← root layout, providers (QueryClient, Theme, Auth)
├── (auth)/
│   ├── sign-in.tsx
│   └── sign-up.tsx
├── (tabs)/
│   ├── _layout.tsx                   ← tab bar config
│   ├── index.tsx                     ← Home / current mesocycle overview
│   ├── workout.tsx                   ← Today's workout
│   ├── weight.tsx                    ← Body weight + chart
│   └── profile.tsx
└── workout/
    └── [workoutId].tsx               ← Specific workout detail

src/
├── features/                         ← feature-grouped logic
│   ├── workout/
│   │   ├── components/               ← SetRow, ExerciseCard
│   │   ├── hooks/                    ← useWorkout, useSetMutation
│   │   └── api.ts                    ← TanStack Query queries/mutations
│   ├── weight/
│   ├── mesocycle/
│   └── auth/
├── components/                       ← cross-feature UI primitives (Button, Input)
├── lib/
│   ├── api-client.ts                 ← typed fetch wrapper using @lockedin/shared; singleton getSession() + 401 retry-once
│   ├── supabase.ts                   ← Supabase client init
│   ├── query-client.ts               ← TanStack Query setup + persistQueryClient + onlineManager resume
│   ├── query-keys.ts                 ← shared key factory (cross-feature invalidation correctness)
│   └── cn.ts                         ← clsx + extendTailwindMerge helper
├── stores/                           ← Zustand stores
└── theme.ts

assets/
app.json                              ← Expo config
package.json
```

**Why feature-grouped under `src/features/`:** deleting a feature = deleting one folder. Layer-grouped (`components/`, `hooks/`, `utils/`) forces archaeology across 5 dirs to remove or rename a feature. Feature-grouping wins as the app grows.

**Why `app/` stays thin:** screens just wire data sources to UI. Feature logic lives in `src/features/*` so it's testable and reusable across routes.

---

## Mesocycle templates (v1)

### Design principles

- **6-week mesocycles**: 5 weeks accumulation + 1 deload.
- **Hypertrophy-focused, RP-style**:
  - Start at MEV (Minimum Effective Volume) — 2 working sets per exercise in week 1.
  - +1 set per exercise each week → approaching MRV (Maximum Recoverable Volume) by week 5.
  - RIR drops over the block: weeks 1–2 target RIR 3–4, weeks 3–4 RIR 2–3, week 5 RIR 0–2.
  - Week 6 deload: half the sets of week 5, RIR 4–5, weight ~60–70% of working weight.
- **Rep ranges per exercise** (not single rep targets) — most lifts in the 6–12 range, isolation in 10–20.
- **Progression rule**: if a lifter hits the top of the rep range with target RIR, add weight next session; if they fall short, repeat weight.

### Three templates shipping in v1

#### 1. PPL 6-day (Push/Pull/Legs, twice through)

Most popular hypertrophy split. Highest user demand.

| Day | Focus | Working sets (week 1 → week 5) |
|---|---|---|
| Mon | Push A — chest emphasis | 12 → 22 |
| Tue | Pull A — back-width emphasis (pulldown, row) | 12 → 22 |
| Wed | Legs A — squat emphasis | 12 → 22 |
| Thu | Push B — shoulder emphasis | 12 → 22 |
| Fri | Pull B — back-thickness emphasis | 12 → 22 |
| Sat | Legs B — hinge/posterior chain emphasis | 12 → 22 |
| Sun | Rest | — |

Push A exercises: Barbell bench (3→5×6–10), Incline DB press (2→4×8–12), Overhead press (2→4×6–10), Cable lateral raise (2→4×12–20), Tricep pushdown (2→3×10–15), Overhead tricep extension (1→2×10–15).
Push B exercises: Incline barbell press, Flat DB press, Seated DB shoulder press, DB lateral raise, Skull crushers, Cable tricep kickback.
*(Full exercise lists per workout for all 6 days authored at seeding time, not in this doc.)*

#### 2. Upper/Lower 4-day

Most accessible. Covers the "intermediate lifter with a job" demographic.

| Day | Focus | Working sets (week 1 → week 5) |
|---|---|---|
| Mon | Upper A — horizontal push/pull emphasis | 14 → 24 |
| Tue | Lower A — squat emphasis | 12 → 22 |
| Wed | Rest | — |
| Thu | Upper B — vertical push/pull emphasis | 14 → 24 |
| Fri | Lower B — hinge emphasis | 12 → 22 |
| Sat–Sun | Rest | — |

Upper A: Barbell bench (3→5×6–10), Barbell row (3→5×6–10), Incline DB press (2→4×8–12), Cable row (2→4×8–12), DB lateral raise (2→4×12–20), Barbell curl (2→3×8–12), Skull crushers (2→3×8–12).
*Upper B, Lower A, Lower B authored at seeding time.*

#### 3. Full Body 3x/week (every other day)

Beginner entry point. Lowest barrier. Each workout hits all major movement patterns.

| Day | Focus | Working sets (week 1 → week 5) |
|---|---|---|
| Mon | FB A — squat + horizontal push/pull | 14 → 22 |
| Tue | Rest | — |
| Wed | FB B — hinge + vertical push/pull | 14 → 22 |
| Thu | Rest | — |
| Fri | FB C — variation day (front squat + incline) | 14 → 22 |
| Sat–Sun | Rest | — |

FB A: Back squat (3→5×6–10), Barbell bench (3→5×6–10), Lat pulldown (3→4×8–12), DB lateral raise (2→3×12–20), Leg curl (2→3×10–15), Barbell curl (1→2×8–12), Tricep pushdown (1→2×10–15).
*FB B and FB C authored at seeding time.*

### Template authoring workflow

Templates live in **seed data**, not migrations. A `seed/templates.ts` script reads JSON/TS template definitions and populates `mesocycle_template` (and child) rows. This way you can edit templates with a code review, not a database migration.

Schema-wise, templates use the same tables as user mesocycles — a "template" is just a mesocycle row with `user_id = null` and `is_template = true`. Instantiation = deep-copy all rows under it with the new user_id.

---

## AI agent design

### Approach

Use the **OpenAI SDK's native function calling** directly. No LangChain, no MCP.

- **Not LangChain** — extra framework, extra indirection, hides the API surface you're trying to learn. The ecosystem is moving away from it.
- **Not MCP** — MCP is a protocol for exposing tools to *external* Claude/AI clients (like Claude Desktop). Your app **is** the client; you control both sides. MCP solves a different problem.

### How tool use actually works

The model never touches your DB. The loop is:

1. User sends a message.
2. Backend calls the LLM with the user message + a `tools` array (JSON schemas of available functions).
3. LLM either responds with text, or returns `tool_calls` (structured JSON: "I want to call `get_workout_history(days=14)`").
4. Backend executes the function against Postgres, captures the result.
5. Backend sends results back to the LLM as a `tool` role message.
6. Loop until the LLM stops requesting tools and returns final text.

### Tool surface (v1: read-only, all 4 ship)

- `get_workout_history(days)` — recent sessions, exercises, sets/reps/weight, RIR.
- `get_body_weight_trend(days)` — weight logs + computed rolling-average trend.
- `get_current_mesocycle()` — active program, current week, planned exercises, RIR state.
- `get_volume_per_muscle_group(days)` — weekly sets per muscle group, using `exercise_muscle.contribution` for weighting. With `exercise_id` denormalized onto `exercise_set`, this is a 2-table join: `exercise_set` filtered by `(user_id, completed_at >= now() - days)` joined to `exercise_muscle` on `exercise_id`, summed by muscle weighted by `contribution`. No traversal through `workout_exercise`.

All four read tools filter by `request.user.sub` server-side; the LLM never sees or chooses the user_id.

### Tool surface (deferred to v1.1)

Write tools open up data-corruption risk if the model misfires:

- `log_body_weight(weight, date?)`
- `log_workout_set(exercise, weight, reps, rpe?)`
- `suggest_mesocycle_adjustment(notes)` — drafts a change; user applies.

Ship read-only first. Promote to write tools after the read agent is solid and after a confirmation-flow UX is designed (no silent writes).

### Chat history persistence

- Two tables (`agent_conversation`, `agent_message`) — see Data model.
- One rolling conversation per user in v1 (can start a new one explicitly; no auto-summarization).
- Each turn, send the **last ~10 user/assistant pairs** + system prompt + tool definitions.
- **Tool results capped at ~4KB** before being sent back to the model. A `get_workout_history(180)` result with 200 sets blows context otherwise.
- Each `agent_message` row persists everything (full tool result, not the capped version) so the UI can show the real context.

### Rate limiting

Critical: `@fastify/rate-limit` on the agent route. 30 req/min and 200/day per user. LLM calls are unbounded cost without it.

### Why not run models locally (HF / on-device)?

- **On-device:** Small enough models to run on a phone (sub-3B, quantized) are unreliable at structured tool calls. Agent will break.
- **Self-hosted on server:** Needs a GPU dyno. Heroku doesn't offer one. AWS GPU instances kill the "free" budget instantly.
- **HF Inference API free tier:** Heavily rate-limited, slow cold starts. Bad chat UX.
- Use hosted OpenAI-compatible endpoint. Ship faster. Revisit local only if privacy becomes a real requirement.

### Custom-endpoint caveat

Not every OpenAI-compatible proxy implements `tools` / `function_calling` fully. Before building the agent, write a 10-line script that:

1. Hits the endpoint with a `tools` array.
2. Confirms the response contains a proper `tool_calls` block.

If it doesn't, fallback is JSON-mode + a hand-rolled parser — workable but uglier.

---

## Open questions / decisions log

| # | Decision | Status | Rationale |
|---|---|---|---|
| D1 | Mobile-only v1 (RN+Expo); no Next.js | ✅ | Product is mobile-first; don't conflate platforms. |
| D2 | v1 scope = workout + body weight + AI agent | ✅ | Depth > breadth. Food/social/streaks deferred. |
| D3 | No Kubernetes | ✅ | Cargo-cult signal on a solo project. Docker only. |
| D4 | Heroku for backend (Docker deploy) | ✅ | User has credits; supports Container Registry. |
| D5 | Supabase for Postgres + Auth + Storage | ✅ | Free tier sufficient; real Postgres. |
| D6 | OpenAI-compatible API for LLM | ✅ | User has key + free model access. |
| D7 | Native SDK function calling — no LangChain, no MCP | ✅ | LangChain = bloat; MCP = wrong use case. |
| D8 | No local HF models for v1 | ✅ | Latency, reliability, cost all wrong. |
| D9 | Read-only AI tools for v1; write tools later | ✅ | Safety + trust before automating user data. Re-affirmed after review (D27). |
| D10 | Backend framework: **Fastify (Node + TS)** | ✅ | **Type-sharing with the RN frontend is the decisive factor** — zod schemas defined once flow into backend validation, backend types, and frontend types. Express/Flask eliminated (legacy, no typing). FastAPI defensible only if prioritizing AI/ML resume angle over mobile. |
| D11 | Mesocycle data model: **schema supports both template-instantiated and user-authored; v1 UI ships templates only** | ✅ | `mesocycle.template_id` nullable from day one — no future migration. v1 UI restricts to 3–5 curated templates + light overrides (swap exercises, tweak set counts). Full program-builder is v2. |
| D12 | Chat history: **persist every turn in Postgres; send last ~10 pairs to LLM; defer summarization** | ✅ | Two tables (`agent_conversation`, `agent_message`). One rolling conversation per user in v1. Cap each tool-result string at ~4KB before resending. Add summarization only when truncation actually shows up. |
| D13 | AI agent runs in **backend Fastify route, not Supabase Edge Function** | ✅ | One codebase, one auth flow, one deploy. Heroku↔Supabase latency is fine. Edge Function would fragment for no real gain. |
| D14 | **Per-set logging, not per-exercise.** Dropsets modeled as child `exercise_set` rows via `parent_set_id` | ✅ | Flat per-exercise model loses set-to-set fade — the exact signal needed for progressive overload. Dropset-as-child-row keeps schema flat (no separate dropset table); `didDropSet?` is derived. |
| D15 | **`total_weeks` on mesocycle; workouts hang off weeks; "exercises per week" not stored** | ✅ | Week-level ownership of workouts handles deloads and progression. "Exercises per week" is a `COUNT(*)` query — storing it creates drift risk. Fully expand weeks at template instantiation; Postgres won't notice the duplication. |
| D16 | ~~v1 re-scoped: AI agent shrinks to stretch goal~~ — **reversed by D27** | ↩️ | Original demotion superseded after review pointed out the agent is the resume differentiator and the timeline supports it. |
| D17 | **Expo Router** for navigation | ✅ | File-based routing, modern Expo default, drops down to React Navigation primitives when needed. |
| D18 | **TanStack Query + Zustand** for state | ✅ | TanStack Query handles all server state with caching + optimistic mutations (non-negotiable for set logging to feel instant). Zustand for the small amount of global client state. `useState` for local UI. |
| D19 | **NativeWind** for styling | ✅ | Fastest iteration, biggest community. Fallback to `StyleSheet.create()` + theme constants if Tailwind feels alien. |
| D20 | **pnpm workspaces monorepo** | ✅ | Required for the type-sharing decision (D10). `packages/shared` holds zod schemas imported by both `apps/mobile` and `apps/api`. No Turborepo/Nx until a real reason appears. |
| D21 | **Feature-grouped structure under `src/features/`** | ✅ | Deleting a feature = deleting one folder. Layer-grouped scales poorly. `app/` stays thin (route wiring); logic lives in features. |
| D22 | **3 templates in v1**: PPL 6-day, Upper/Lower 4-day, Full Body 3x/week | ✅ | Covers 3/4/6-day-per-week users with distinct splits. Arnold + Anterior/Posterior + UL 6-day deferred to v1.1 by user demand. Quality over quantity. |
| D23 | **6-week mesocycle length** (5 accumulation + 1 deload) | ✅ | Consistent UX across templates. Standard RP-style block. Easier progression logic. |
| D24 | **Hypertrophy / RP-style** as the default training model | ✅ | MEV → MRV volume progression, RIR drops across the block, week 6 deload. Matches the audience for these splits. Strength-focused variants are v2. |
| D25 | **Templates live in seed data, not migrations** | ✅ | A template is a `mesocycle` row with `user_id=null` and `is_template=true`. Instantiation = deep-copy under the new user. Editing templates = code review, not schema migration. |
| D26 | **Hand-curated exercise library (~100 entries); custom schema, not free-exercise-db's verbatim** | ✅ | free-exercise-db's `level`/`category`/`instructions[]` are weak fit; their schema lacks `movement_pattern`, `is_unilateral`, `default_rep_range`. Design schema around LockedIn needs; write a thin adapter if importing later. Seed by upsert on `slug`. |
| D27 | **Reverse D16: fully functional read-only agent ships in v1** | ✅ | 4 read tools, chat UI, persisted history. Resume differentiator. Timeline supports it (20–30 hrs/wk × 12 wks). Write tools still deferred (D9 holds). |
| D28 | **12-week TestFlight deadline at 20–30 hrs/wk** | ✅ | Hard guardrail against planning-vs-shipping drift. If hours slip <20/wk for 2+ weeks, first cut is deferring offline persistence, then stubbing agent at 2 tools. |
| D29 | **JWT verification via Supabase JWKS** (`@fastify/jwt` + `jwks-rsa`) | ✅ | No shared secret to rotate; survives Supabase key rotations; standard pattern. RS256, decoded claims populate `request.user`. |
| D30 | **Denormalize `user_id` onto `mesocycle_week`, `workout`, `workout_exercise`, `exercise_set`** | ✅ | Every AI tool query filters by user; without denormalization that's a 6-table join + nested RLS `EXISTS` clauses. Write cost trivial (cascade on instantiation). |
| D31 | **`planned_weight` / `planned_reps` separate from logged `weight` / `reps`** | ✅ | Preserves the original prescription if a user edits weight mid-workout at the row level. Planned fields are immutable for individual edits; **D67 carves out the cascade ("apply to future weeks") path, which does overwrite planned_* on unlogged future rows.** Logged fields start equal and get stamped on log. |
| D32 | **Units: `users.unit_preference` + snapshot `weight_unit` on every `exercise_set`** | ✅ | User can toggle kg ↔ lb without corrupting history. No on-the-fly conversion of stored data. |
| D33 | **`exercise_muscle` join table replaces `secondary_muscles[]` array** | ✅ | `get_volume_per_muscle_group` needs per-muscle contribution weights (compound lifts contribute ~0.5× to secondaries). Array column can't carry that. Primary muscle also lives in the join at 1.0; `exercise_library.primary_muscle` kept as a denormalized cache for picker filtering. |
| D34 | **Dropset ordering via `drop_order` smallint** | ✅ | Multi-drop chains share `set_number` with the parent and need a stable render order. UI sorts `(set_number ASC, drop_order ASC NULLS FIRST)`. |
| D35 | **All indexes specified in initial migration** | ✅ | See Data model § Indexes. Adding indexes after the fact during a demo is the worst time. |
| D36 | **Offline persistence via `@tanstack/query-async-storage-persister` + `expo-sqlite/kv-store`** | ✅ | Gym connectivity is unreliable. Mutation queue replays on reconnect via `onlineManager`. |
| D37 | **Optimistic mutation pattern: per-row `mutationKey`, server-stamped `completed_at`** | ✅ | Rapid set-tap races otherwise. `mutationKey: ['set', setId]` serializes per-row; server is authoritative for timestamps to avoid clock drift. |
| D38 | **Observability: Sentry on RN + API, `pino` JSON logs, Heroku log drain to Better Stack** | ✅ | Free-tier coverage for crashes, errors, structured logging. Source-map upload via EAS. |
| D39 | **Reliability: daily `pg_dump` cron → R2; Supabase 3-day keepalive cron via GH Actions** | ✅ | Supabase free tier has no PITR; 7-day pause kills demo links. Both fixed by GH Actions. |
| D40 | **Region: `us-east-1` for Heroku + Supabase** | ✅ | Cross-region adds 80–150ms per query; agent loops compound this into seconds. |
| D41 | **Multi-stage Dockerfile (`node:20-alpine`); `pnpm deploy --prod --filter api`** | ✅ | Keeps image under ~200MB; avoids copying `apps/mobile` deps. Image stays well within Heroku's 10GB limit and 15-min build timeout. |
| D42 | **Env schema in `packages/shared/env.ts` (zod); CI step diffs against `heroku config`** | ✅ | Crashes loudly at boot on missing keys; catches env drift between prod and CI before it ships. |
| D43 | **`@fastify/rate-limit` on `/agent/*` routes: 30/min + 200/day per user** | ✅ | LLM cost is unbounded otherwise. A misbehaving client or compromised key runs up the bill fast. |
| D44 | **Week-edit semantics: UI toggle "apply to this week" vs "apply to all future weeks"** | ✅ | No schema change. Default = this week only. The cascade option propagates the edit to weeks N+1…final at write time. |
| D45 | ~~`workout.started_at` / `finished_at` for completion state~~ — **reverted** | ↩️ | User clarified workout model is "log as you go, navigate away anytime." No start/stop UX. Workout state derived from set completion (no sets with `completed_at` = planned; some = in progress; all = completed). |
| D46 | **Testing: Jest + React Native Testing Library only in v1; no E2E** | ✅ | Tests target pure logic (template expansion, dropset ordering, rolling-average trend, agent tool-result truncation). Maestro is industry-standard for RN E2E in 2026 but adds 1.5–2 weeks and pays off mainly during iteration. Add post-TestFlight in v1.1. |
| D47 | **Supersets via `superset_group_id` smallint on `workout_exercise`** | ✅ | Shared value within a workout = paired exercises. No `superset` table needed. UI groups during render; user alternates set logging across the pair. |
| D48 | **AWS ECS on EC2 deploy in v1 (alongside Heroku)** | ✅ | ECS-on-EC2 with t2.micro is free tier for 12 months; matches Heroku credit horizon. ECR for image storage (free tier 500MB). Public IP on task — no ALB ($20/mo, not free tier). **Narrowed by D61 to demo-only:** plain-HTTP public IP can't host the mobile app's backend under iOS ATS; Heroku is the only URL the app calls. AWS shows containerization + CI-to-cloud via README screenshots + curl-able `/health`. ~1 weekend in week 11–12. |
| D49 | **Workout completion is derived, not stored.** Implicit state from `exercise_set.completed_at` aggregation | ✅ | "Current workout" UI query: first workout in active mesocycle where any set has `completed_at IS NULL`. Removes UX friction of explicit start/stop. |
| D50 | **Dropsets count as full sets for volume; `target_rep_range` on `workout_exercise` is authoritative** | ✅ | Volume query is `COUNT(*) × exercise_muscle.contribution` over completed sets — each dropset row contributes independently. `exercise_library.default_rep_*` is a seed hint only; `workout_exercise.target_rep_*` is the source of truth at the workout-instance level. |
| D51 | **Heroku Basic dyno ($7/mo, no idle sleep)** | ✅ | 1 year of credits covers it; eliminates 30-min idle sleep + 5–15s cold starts. Simpler than running a keepalive ping against an Eco dyno. |
| D52 | **No `@fastify/cors` in v1** | ✅ | Native RN doesn't enforce CORS. Add only when a web client lands. |
| D53 | **Supabase storage watch: upgrade to Pro at ~400MB** | ✅ | Free tier is 500MB; per-set rows + chat history puts ~500–2000 active users as the order-of-magnitude ceiling. Manual dashboard check every couple of weeks; no active monitoring needed at this scale. |
| D54 | **Mesocycle state: just `archived_at`, no `status` enum** | ✅ | Active = `archived_at IS NULL`. v1 doesn't need to distinguish "completed" vs "abandoned"; that's a v1.1 analytics refinement. |
| D55 | **NativeWind: `cn()` helper (clsx + tailwind-merge) in `src/lib/cn.ts`; no dynamic class strings** | ✅ | Class merging needs `tailwind-merge` for predictable last-wins. Dynamic class strings get tree-shaken by NativeWind's build-time scan; use lookup maps or `cssInterop`. |
| D56 | **Deep linking: stub `expo-linking` from day one** | ✅ | Configure URL scheme in `app.json` (e.g., `lockedin://`). Cheap insurance for v1.1 push notifications; retrofitting later means a moving target. |
| D57 | **Workout detail screen outside `(tabs)` group; tab bar hidden during active logging** | ✅ | Standard pattern in fitness apps (Strong, Hevy, Jefit). Focused logging mode, no distractions. |
| D58 | **No formal `docs/adr/` directory in v1; decisions log is ADR-lite and sufficient** | ✅ | Post-launch, extract 3 load-bearing decisions into proper ADR format as a portfolio polish step. Not worth doing pre-launch. |
| D59 | **Accessibility minimum baseline in v1**: screen-reader labels, no color-only state, system font scaling, ≥44pt tap targets | ✅ | Not full WCAG 2.1 AA. Full a11y audit (focus order, contrast ratios, VoiceOver/TalkBack testing) deferred to v1.1. |
| D60 | **Resume positioning codified**: lead with data model, agent function-calling, type-shared monorepo, optimistic mutations, dual deploy. Skim past UI framework choices. | ✅ | Stack is broad; recruiters skim. Choose what to lead with. Reference section in BRAINSTORM.md for README + portfolio writeup. |
| D61 | **AWS demoted to demo-only**: Heroku is the mobile app's only backend; AWS ECS-on-EC2 exists for the containerization/CI bullet via README screenshots, not as a reachable endpoint | ✅ | Public IP on t2.micro serves plain HTTP; iOS App Transport Security blocks plain HTTP from RN. No-ALB free-tier path can't host a real mobile backend without adding Caddy/LE work that exceeds the bullet's value. Resume framing updated for honesty. |
| D62 | **ECR lifecycle policy day one**: keep 3 latest tagged images, expire untagged after 7 days | ✅ | ECR free tier is 500MB per account, not per repo. Without lifecycle policy, every CI push accumulates and silently exits free tier. |
| D63 | **Fastify API connects as Supabase service role; authorization in app code; RLS enabled defensively** | ✅ | Mobile app never queries data tables directly (only auth) — RLS would never fire from the mobile direction. Service role + a `db.forUser(userId)` helper that filters every query is simpler and works cleanly with the transaction pooler. RLS policies (default-deny + template-visibility carveout) stay enabled for defense-in-depth and to keep the option of direct-from-mobile queries open. |
| D64 | **JWKS client config pinned**: `cache: true`, `cacheMaxAge: 10min`, `rateLimit: true`, `jwksRequestsPerMinute: 10` | ✅ | Defaults are too loose. Without cache, every request fetches JWKS; without rateLimit, key rotations cause request storms. |
| D65 | **Singleton token-refresh promise in `api-client.ts`** | ✅ | Multiple parallel `getSession()` / 401-retry calls collapse to one underlying refresh. Without it, cold start fires N parallel refreshes (thundering herd) and most reject. |
| D66 | **`exercise_id` denormalized onto `exercise_set`** | ✅ | Same logic as D30 (`user_id` denorm). `get_volume_per_muscle_group` becomes a 2-table join instead of climbing through `workout_exercise`. Stamped at instantiation, copied on cascade. Exercise substitution = delete+recreate slot (sets cascade), never mutate the FK. |
| D67 | **Cascade ("apply to future weeks") rewrites `planned_*` AND `weight`/`reps` on unlogged future rows** | ✅ | "Apply to future weeks" means the plan changed, not "log a one-off." Logged rows (`completed_at IS NOT NULL`) are never touched. Per-row immutability of `planned_*` holds for individual edits but not cascades. Clarifies D31 + D44 interaction. |
| D68 | **`set_number` on dropset children equals parent's `set_number`** — it's a group ID, not a unique key | ✅ | "Working sets" = `WHERE parent_set_id IS NULL`; render order = `(set_number, drop_order NULLS FIRST)`. Clarifies D34 against `MAX(set_number)` and `COUNT(DISTINCT set_number)` failure modes. |
| D69 | **`mesocycle` CHECK constraint**: `is_template = true OR (user_id IS NOT NULL AND start_date IS NOT NULL)` | ✅ | Cross-mesocycle progression queries need chronology — instances must have `start_date`. Templates remain unanchored. |
| D70 | **RLS template visibility carveout**: separate `mesocycle_templates_public` SELECT policy on `is_template = true`, plus `exercise_library` readable by all authenticated users | ✅ | Without the carveout, denormalized-user_id RLS hides templates from every user. |
| D71 | **Time-range index on `exercise_set (user_id, completed_at DESC) WHERE completed_at IS NOT NULL`** | ✅ | All 4 agent tools take a `days` window. Without this, time-range scans fall back to seq-scan over user's history. Plus a `mesocycle (user_id, start_date DESC) WHERE is_template = false` index for cross-meso progression. |
| D72 | **Metro/pnpm strategy: hoisting (`node-linker=hoisted`); `.cjs`/`.mjs` source extensions added explicitly; React + React Native pinned at workspace root via pnpm overrides** | ✅ | Symlink resolution has bitten Metro repeatedly across SDK versions; hoisting is the safer first-mobile-app choice. Without `.cjs` in `sourceExts`, zod et al. fail to resolve. Without pinning, hoisting can produce two Reacts → runtime "Invalid hook call." Clarifies D20. |
| D73 | **Offline mutation replay requires explicit `shouldDehydrateMutation: () => true` + `onlineManager.subscribe(...resumePausedMutations())`** | ✅ | TanStack Query v5 defaults: mutations are *not* dehydrated, replays are *not* automatic. `onlineManager` alone only gates new requests — it doesn't drive replay. Without both pieces, queued offline set-logs vanish. Corrects D36. |
| D74 | **Mutation idempotency: `scope: { id: setId }` + client-generated `idempotency_key` (UUID v4) per set log; 1-hour server dedupe table keyed by `(user_id, idempotency_key)`** | ✅ | `mutationKey` alone serializes cache writes, not network calls. Without `scope`, rapid taps fire parallel POSTs; with retry-once on 5xx, flaky network = double-logged sets. Clarifies D37. |
| D75 | **NativeWind `cn()` uses `extendTailwindMerge`, not stock `twMerge`** | ✅ | Stock `tailwind-merge` doesn't know NativeWind's `dark:` / `ios:` / `android:` variants and mis-merges last-wins. Plus: `jsxImportSource: "nativewind"` in tsconfig; Reanimated Babel plugin must be last in `babel.config.js`. Clarifies D55. |
| D76 | **EAS Sentry setup**: `SENTRY_AUTH_TOKEN` as EAS secret (not env var); `@sentry/react-native/expo` plugin in `app.json`; verify upload via "Source maps successfully uploaded" in EAS build log before TestFlight | ✅ | Env vars in `.env` don't reach EAS Build. Without auth token, source maps silently don't upload and Sentry shows bytecode offsets. Clarifies D38. |
| D77 | **Shared query-key factory in `src/lib/query-keys.ts`** | ✅ | Feature-local `api.ts` with inline string keys = cross-feature invalidation broken on first typo. One factory; every feature imports from it. Clarifies D21. |
| D78 | **Heroku custom domain + ACM TLS for the mobile-facing URL** | ✅ | TestFlight builds bind a backend URL that's hard to migrate. Free subdomain + free Heroku ACM cert from week 1; not week 12. |
| D79 | **`exercise_set` composite UNIQUE `(workout_exercise_id, set_number, drop_order)` + explicit `ON DELETE CASCADE`** on both `workout_exercise_id` FK and `parent_set_id` FK | ✅ | D74's idempotency_key handles client races but DB-level integrity was missing. D66's "delete+recreate slot, sets cascade" requires explicit cascade — undocumented before. Without cascade, orphaned drops become phantom working sets. |
| D80 | **Cascade vs exercise substitution: confirmation modal in UI** | ✅ | Cascade matches on `exercise_id`; if user previously substituted bench → incline bench in a later week, cascade skips that week silently. UI surfaces the mismatch with a confirmation modal listing updated/skipped weeks. Silent skip = bad UX; error = blocks legitimate cascades. Clarifies D67. |
| D81 | **Volume index includes `exercise_id`**: `CREATE INDEX … ON exercise_set (user_id, completed_at DESC) INCLUDE (exercise_id) WHERE completed_at IS NOT NULL AND is_warmup = false` | ✅ | Original index forced a heap fetch per row to get `exercise_id` for the `exercise_muscle` join. INCLUDE makes it an index-only scan. Also filters out warmup sets (D83) at the index level. |
| D82 | **`body_weight` table lands with `UNIQUE (user_id, logged_at)`** | ✅ | Was a TODO note in the doc. Unique constraint prevents accidental double-log of the same morning. Schema: `(id, user_id, logged_at date, weight numeric(5,2), weight_unit text, created_at)`. |
| D83 | **`exercise_set.is_warmup boolean DEFAULT false`; volume queries filter `WHERE is_warmup = false`** | ✅ | Without this, warmup-heavy programs inflate volume metrics. The AI agent's `get_volume_per_muscle_group` becomes misleading. UI exposes a "mark as warmup" toggle when adding sets. |
| D84 | **CI: SHA-tagged images pushed to both registries before Heroku release-phase activation; fail job on either registry failure** | ✅ | Without atomic gating, transient ECR or Heroku push failures cause silent drift between the two "same image" deploys — breaks the resume claim on first network blip. |
| D85 | **Expo SDK 54** (current-stable Jun 2026): React 19.1.0, React Native 0.81, Node 20.19.x. Drop `react-dom` from pnpm overrides (SDK 54 doesn't bundle RN-web) | ✅ | Placeholder `0.7x.x` in the original example was a literal copy-paste hazard. Picked current-stable over SDK 55/56 (bleeding edge) — fewer landmines for first-time mobile dev. Clarifies D72. |
| D86 | **Timeline relaxed: 12-week target kept as anchor, 16-week soft cap allowed.** Agent abort criteria from D101-D104 still apply | ✅ | User flagged "no rush." 12-week target stays in doc as discipline against perfectionism (already round-3 review). Soft cap to 16 weeks gives breathing room. Removing the deadline entirely would let scope drift indefinitely. |
| D87 | **Cloudflare grey-cloud (DNS-only mode) during initial Heroku ACM cert issuance** | ✅ | Cloudflare orange-cloud proxy breaks ACM's HTTP-01 challenge; can brick TestFlight URL for ~24h on first provisioning. Flip to orange-cloud after cert issued if CDN benefits wanted. |
| D88 | **UptimeRobot free tier pinging `/health` every 5 min** | ✅ | Sentry catches in-app errors; Better Stack stores logs; neither detects dyno 503s or pooler death. Add lightweight uptime monitor. 10-min setup. |
| D89 | **`refreshSession()` checks both throw AND `session === null`**; both paths trigger sign-out | ✅ | Supabase can resolve refresh with `{ session: null }` instead of throwing when refresh token itself expired (user offline >30 days, password changed elsewhere). Bare catch-only logic = silent 401 loop. |
| D90 | **Postgres driver: `node-postgres` (`pg`) with parameterized queries; NOT named prepared statements** | ✅ | Transaction pooler (port 6543, `pgbouncer=true`) doesn't support named prepared statements — silent break at concurrency. Prisma eliminated due to sharper pooler edges. Set `statement_timeout` to prevent runaway queries. |
| D91 | **OIDC trust policy `sub` condition scoped to `repo:Fritozz-105/LockedIn:ref:refs/heads/main` only** | ✅ | Wide `repo:Fritozz-105/*:*` lets any branch/fork assume the role and push to ECR. Standard hardening; trivial to specify, expensive to debug if missed. Clarifies D62. |
| D92 | **ECS task definition sets `NODE_OPTIONS=--max-old-space-size=400`** | ✅ | t2.micro has 1 GB RAM. Node baseline ~80MB + ECS agent ~150MB → ~700MB headroom. Default `--max-old-space-size` can OOM-kill the task during a recruiter demo. Cap at 400MB explicitly. Document in README that AWS is demo-sized. |
| D93 | **`onAuthStateChange('SIGNED_OUT')` calls `queryClient.getMutationCache().clear()` alongside `queryClient.clear()`** | ✅ | Without clearing dehydrated mutations, they replay on next launch with stale auth headers → 401 sign-out loop. Clarifies D65. |
| D94 | **Server dedupe TTL bumped 1h → 48h; rehydrate-time reconciliation purges optimistic rows older than 24h with no matching server row** | ✅ | Real offline windows (gym vacation, dead phone) exceed 1h. App-kill mid-mutation leaves orphaned optimistic rows in persisted cache forever without reconciliation. Clarifies D74. |
| D95 | **Three-state session: `undefined` (splash), `null` (auth group), `Session` (tabs group)**. Stored in Zustand; root `_layout.tsx` branches | ✅ | Without three-state model, `(auth)` group flashes on cold start while session loads. Implicit in prior decisions; spec'd explicitly here. Clarifies D17. |
| D96 | **Dark mode in v1**: `useColorScheme` from `nativewind`, theme tokens with `dark:` variants in tailwind.config.js, themed component primitives (`<ThemedCard>`, `<ThemedText>`) | ✅ | Timeline permits per D86. Adds ~3-4 days design + test absorbed into weeks 5-9. Manual override (light/dark/system) in Zustand + AsyncStorage. Reverses prior intent to defer to v1.1. |
| D97 | **`eslint-plugin-react-native-a11y` enforced with recommended config** | ✅ | A11y baseline (D59) drifts within 2 weeks on solo project without lint. 10-min cost. |
| D98 | **Testing infra spec'd**: `jest-expo` preset, `expo-router/testing-library`, MSW v2 + `whatwg-fetch` polyfill in `jest.setup.js`, colocated `__tests__/` under each `src/features/*` | ✅ | Step 11 said "Jest + RNTL configured" without specifying preset + route mocking + API mocking strategy. Each has known gotchas worth nailing down pre-scaffolding. Clarifies D46. |
| D99 | **Sentry source-map verification runs on release/TestFlight build, not dev** | ✅ | "Source maps successfully uploaded" log line covers JS, not Hermes bytecode. Dev builds use Metro dev server and naturally show source maps — they don't prove the release path works. Verify by throwing a deliberate error in TestFlight and confirming Sentry shows JS file/line. Clarifies D76. |
| D100 | **Agent prep moved to week 9; custom-endpoint function-calling probe runs in week 6** | ✅ | Probe failure in week 10 turns the build into a JSON-mode parser rewrite. Running probe 4 weeks earlier gives time to pivot. Step ordering changes in Next steps. |
| D101 | **AWS time-box: 16 hours with abort criterion.** If `/health` not curl-able by end of weekend, ship without AWS and reframe resume bullet as "Dockerized; AWS deployment in progress" | ✅ | First-time AWS user risks 30+ hours on IAM + ECS debugging. Protects against AWS eating an entire month under D86's relaxed timeline. |
| D102 | **Per-set logging UI "ugly-but-functional" gate at end of week 7** | ✅ | The "users touch 200×/week" framing is the perfectionism trap. Logs end-to-end by week 7 (no animations, no polish); polish budget reserved for week 11. |
| D103 | **Templates: author PPL 6-day fully first, validate schema end-to-end, then clone-and-modify for UL 4 and FB 3** | ✅ | 750+ row entries hand-curated = ~15h, not "an afternoon." Authoring one fully catches schema gaps before they multiply. |
| D104 | **Agent quality bar (not cut)**: 4 tools ship, but if chat UI doesn't render tool results cleanly by end of week 11, descope `get_volume_per_muscle_group` (most complex) | ✅ | Under D86's relaxed timeline, descope-the-hardest-tool is the right escape valve — not the original "stub at 2 tools" cut. Preserves the resume bullet. |
| D105 | **Resume bullet reframe**: drop "dual deploy"; use "Containerized Node/Fastify backend with CI/CD pipelines to Heroku (production) and AWS ECR/ECS (validation environment)" | ✅ | "Dual deploy" reads as overclaim once recruiter learns iOS ATS blocks AWS. "Production / validation environment" is the honest split. Updates D60. |
| D106 | **TestFlight distribution checklist**: LinkedIn post at launch, 60-sec Loom walkthrough linked in README, Excalidraw architecture diagram, pin GitHub repo on profile, monthly TestFlight resubmit reminder (90-day build expiry) | ✅ | A shipped project that nobody sees is wasted work. These are 1-4h tasks each; the Loom + diagram have the highest recruiter-attention ROI. TestFlight builds expire silently at 90d — schedule the resubmit. |

---

## Next steps (12-week order; 16-week soft cap per D86)

### Weeks 1–2 — Scaffolding (no features)

1. **Monorepo root**: `pnpm-workspace.yaml`, `package.json`, `tsconfig.base.json`, `.npmrc` (with `node-linker=hoisted`).
2. **`packages/shared`**: zod baseline + `env.ts` schema. Export a `HealthResponse` type to validate the first roundtrip.
3. **`apps/api`** (Fastify TS): `/health` route returns a `HealthResponse`. `@fastify/jwt` configured against Supabase JWKS with pinned `jwks-rsa` config (`cache: true`, `cacheMaxAge: 10min`, `rateLimit: true`). `@fastify/rate-limit` installed. `pino` JSON logging. **`db.forUser(userId)` helper** as the only sanctioned path for user-scoped queries (service-role connection, app-level filter).
4. **Dockerfile**: multi-stage, `node:20-alpine`, `pnpm deploy --prod --filter api`. `docker build && docker run` exposes `/health`.
5. **Heroku deploy**: Container Registry push, dyno running, `/health` returns over public URL. Region `us-east-1`. **Custom domain (e.g. `api.lockedin.app`) bound to dyno; Heroku ACM provisions a free TLS cert.** The mobile app config points at the custom domain — never `*.herokuapp.com` — so the backend URL is migratable post-launch.
6. **GitHub Actions**: build + push to Heroku Container Registry on push to `main`. ECR repo created with a lifecycle policy (keep 3 latest tagged images, expire untagged after 7 days). OIDC trust relationship between GH Actions and an AWS IAM role — no long-lived AWS credentials in GH secrets. Add `pg_dump` daily cron + Supabase keepalive cron (every 3 days).
7. **`apps/mobile`** (Expo + TS + Expo Router + NativeWind): `metro.config.js` configured for the monorepo (hoisted strategy, `.cjs`/`.mjs` in sourceExts, React/RN pinned in workspace-root `pnpm.overrides`). App boots. `(auth)` and `(tabs)` route groups exist. `src/lib/api-client.ts` has the singleton getSession() pattern. `src/lib/query-client.ts` wires `persistQueryClient` with `shouldDehydrateMutation: () => true` and `onlineManager.subscribe(...)` to call `resumePausedMutations()`. `src/lib/query-keys.ts` factory stub.
8. **Mobile → API roundtrip**: tap a button on a debug screen, fetch `/health`, render the validated response. **This is the proof the stack works.**
9. **Supabase project**: created. Initial SQL migration applies the full data-model schema — every table, enum, the `mesocycle` CHECK constraint (D69), all indexes from the Indexes section (including the `(user_id, exercise_id, completed_at)` and `(user_id, completed_at)` partial indexes on `exercise_set`, and `(user_id, start_date DESC)` on `mesocycle`), and the **`body_weight` table** noted in the Indexes block. RLS enabled on every user-scoped table with the template-visibility carveout on `mesocycle` (D70) and exercise-library read-all + custom-owner policies.
10. **Sentry + Better Stack** wired on both api and mobile. `SENTRY_AUTH_TOKEN` registered as an EAS secret (D76); `@sentry/react-native/expo` plugin in `app.json`. Throw a deliberate error from a debug screen and verify the EAS Build log shows "Source maps successfully uploaded" before any feature work begins.
11. **Jest + RNTL** configured in both `apps/mobile` and `apps/api` (and `packages/shared`). First test: a `Mesocycle` zod schema round-trips correctly. Establishes the test infrastructure before there's anything meaningful to test.
12. **`expo-linking` stub** in root `_layout.tsx`; URL scheme (`lockedin://`) configured in `app.json`.
13. **`cn()` helper** in `apps/mobile/src/lib/cn.ts` using `extendTailwindMerge` (D75). NativeWind dark-mode setup (`colorScheme` from `nativewind`); `jsxImportSource: "nativewind"` in `tsconfig.json`; verify Reanimated plugin is last in `babel.config.js` plugins.

### Weeks 3–4 — Body weight (smallest vertical slice)

11. Auth screens (sign-in, sign-up) using Supabase Auth UI components.
12. Body weight logging UI + API endpoints + RLS-secured DB writes.
13. Line graph with rolling-average trend (Victory Native).
14. **Optimistic mutation pattern** proven end-to-end on body weight (smaller surface than set logging).
15. Offline persistence wired (`@tanstack/query-async-storage-persister`).

### Weeks 5–9 — Workout tracker (the centerpiece) + dark mode

16. Exercise library seed (~100 entries) with `exercise_muscle` rows.
17. Template seed: **author PPL 6-day fully first (D103)**, validate schema end-to-end (instantiation, cascade, render, volume queries), then clone-and-modify for UL 4 and FB 3. Budget ~15h.
18. Mesocycle home screen (current week, today's workout).
19. Workout detail screen — render `exercise_set` rows sorted `(set_number, drop_order NULLS FIRST)`.
20. **Per-set logging UI** with keyboard handling, dropset add/edit, RIR input, warmup toggle, notes. **End-of-week-7 gate (D102): ugly-but-functional — logs sets end-to-end, no animations, no polish.** Polish budget reserved for week 11.
21. Week-edit semantics (apply-this-week vs apply-forward toggle) + cascade confirmation modal (D80).
22. Workout completion state — derived from `exercise_set.completed_at` aggregation (D49). "Current workout" = first workout in the active mesocycle where any set has `completed_at IS NULL`.
23. **Dark mode (D96)**: themed component primitives, `useColorScheme` wiring, manual override storage, screen-by-screen dark-mode pass.

### Week 6 (parallel to workout tracker) — Custom-endpoint probe (D100)

24. **Validate the custom OpenAI endpoint supports function calling.** 10-line probe script with a `tools` array. Run this in week 6, NOT week 10. If it fails, the fallback (JSON-mode parser) needs the runway.

### Week 9 — Agent prep (moved up per D100)

25. Implement the 4 read tools as Fastify route handlers.
26. `agent_conversation` + `agent_message` persistence.
27. Tool-result truncation cap (~4KB) with full result still persisted to DB.

### Weeks 10–12 — Agent + AWS deploy + polish + TestFlight

28. Chat UI (multi-turn, persisted history).
29. Agent loop: send last ~10 turn pairs + tools, handle `tool_calls`, execute against DB, return results, loop until done.
30. Rate-limit + observability check.
31. **End-of-week-11 agent quality gate (D104)**: chat UI renders all 4 tool results cleanly. If `get_volume_per_muscle_group` (the most complex) isn't rendering well, descope it to 3 tools rather than slip TestFlight.
32. **AWS ECS deploy — 16h hard time-box (D101).** Set up ECR repository, `aws-deploy.yml` workflow pushing the same SHA-tagged image, ECS-on-EC2 cluster (1× t2.micro, public-IP task, no ALB, `NODE_OPTIONS=--max-old-space-size=400`). Verify via `curl http://<task-ip>/health`. **Abort criterion: if `/health` not curl-able by end of weekend, ship without AWS; reframe resume bullet as "Dockerized; AWS deployment in progress."**
33. **EAS Build → TestFlight submission.** Source-map upload to Sentry verified on the actual release build (D99).
34. **Critical unit tests** before submission: template expansion, dropset ordering query, rolling-average body-weight trend, agent tool-result truncation cap, cascade behavior with substitution.
35. **README with**: 30-second screen-recording GIF, AWS console screenshots, Excalidraw architecture diagram in `Architecture` section.
36. **Distribution checklist (D106)**: post LinkedIn launch announcement, record 60-sec Loom walkthrough (link in README), pin LockedIn repo on GitHub profile, calendar reminder for monthly TestFlight resubmit (90-day build expiry).
