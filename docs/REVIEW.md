# LockedIn — Plan Review Handoff

This file lets a fresh Claude Code session spawn a multi-agent review against the current state of `docs/BRAINSTORM.md`.

The intent: get four independent skeptical perspectives on the plan from agents that have no conversational priors, then synthesize. The author (Claude in the originating session) co-built the plan and is anchored to it — fresh reviewers will catch things the author skims past.

---

## Context for the session reading this file

- **Project:** LockedIn, a planned mobile fitness app.
- **Audience:** solo undergraduate developer building this as a resume project, targeting entry-level / new-grad software engineering roles (including AWS-flavored cloud roles).
- **Stack at the time of writing:** React Native + Expo + TypeScript + NativeWind for mobile; Fastify (Node + TS) backend in Docker on Heroku Basic (primary) and AWS ECS-on-EC2 (secondary); Supabase Postgres + Auth + Storage; OpenAI-compatible custom endpoint for the LLM; GitHub Actions CI/CD pushing to both Heroku Container Registry and AWS ECR.
- **Scope:** workout tracker (mesocycle-based, per-set logging with dropset/superset support) + body weight tracking + read-only AI agent with 4 tools. 12-week TestFlight target at 20–30 hrs/wk.
- **Plan lives in:** `docs/BRAINSTORM.md` — read this in full before spawning reviewers.
- **Prior review state:** the plan has been through **two** rounds of multi-agent review already. Round one surfaced ~31 items and produced D27–D60. Round two surfaced ~20 items and produced D61–D78. This third-pass review exists to catch what slipped through both prior passes, find issues introduced by the round-two fixes themselves (denormalized `exercise_id`, service-role authz, cascade rewriting `planned_*`, etc.), and identify anything still missing.

---

## How to run the review

1. Read `docs/BRAINSTORM.md` in full. Don't skim — the doc is ~750 lines and load-bearing details are everywhere.
2. Spawn **four general-purpose agents in parallel** (one message, four `Agent` tool calls) using the four prompts below.
3. When all four return, synthesize their feedback into a single summary categorized as:
   - **Act on now** — real issues affecting upcoming scaffolding or v1 feature work.
   - **Defer / backlog** — real issues that are v1.1+ or low-impact for v1.
   - **Disagree** — reviewer mistakes, missed context, or recommendations that conflict with already-decided tradeoffs in BRAINSTORM.md.
   - **Already addressed** — the reviewer flagged something that's already in the doc (cite the D-number).
4. Present the synthesis to the user. Don't auto-commit changes. Wait for the user to triage which items to act on.

### Notes for the synthesizer

- The doc's decisions log (D1–D60) is authoritative. If a reviewer reopens a settled question, weigh it — sometimes a second opinion catches a flawed first decision, but more often it's reviewer noise. Cite the existing D-number when filing as "already addressed."
- The user has a strong stated preference for **concrete, falsifiable pushback** over generic concerns. Filter reviewer output through this lens: a punch list of named failure modes lands; vague worry slides off. (See feedback memory `feedback-pushback`.)
- Some reviewers may relitigate already-rejected choices. Cite the relevant D-number and move on. Frequently re-opened settled questions:
  - Kubernetes (D3), MCP / LangChain / local HF models (D7, D8), AWS Cognito (D5)
  - **AWS demoted to demo-only — do not reopen the ATS/TLS question** (D61, narrows D48)
  - **Service role + app-level authz, not RLS-via-JWT-passthrough** (D63)
  - **`exercise_id` denormalized onto `exercise_set`** (D66)
  - **Cascade ("apply to future weeks") rewrites `planned_*` on unlogged future rows** (D67, carves out D31)
  - **`set_number` on dropset children = group ID, not unique key** (D68, clarifies D34)
  - **Heroku custom domain + ACM TLS, not `*.herokuapp.com`** (D78)

---

## The four prompts

Each agent is `subagent_type: general-purpose`, run in parallel.

### Reviewer 1 — Infrastructure & deployment

```
You are a skeptical infrastructure reviewer. Read `/Users/zzeng/Coding/VSCodeProjects/LockedIn/docs/BRAINSTORM.md` in full before responding.

Context: LockedIn is a planned mobile fitness app built by a solo undergraduate as a resume project. Stack: React Native + Expo mobile, Fastify (Node + TS) backend in Docker, deployed to Heroku Basic via Container Registry (the mobile app's only backend — custom domain + ACM TLS) AND AWS ECS-on-EC2 with ECR (demo-only, plain-HTTP public IP, used only for README screenshots + curl-able /health since iOS ATS blocks the mobile app from calling it). Supabase Postgres for DB/auth/storage. The Fastify API connects as the Supabase service role and enforces authorization in app code via a `db.forUser(userId)` helper; RLS is enabled defensively with template-visibility carveouts. JWKS-verified JWTs with pinned cache config. CI/CD via GitHub Actions with OIDC to AWS. 1 year of Heroku credits, AWS free tier (12 months, t2.micro). 12-week TestFlight target at 20–30 hrs/wk.

Your slice: infrastructure and deployment only. Ignore data model, mobile UI patterns, and scope debates. Focus on:

- Heroku Basic dyno specifics (1× dyno, no autoscaling, deploy strategy, custom domain + ACM cert).
- Supabase free-tier traps: transaction pooler with service-role connections, RLS performance at scale, the 7-day pause keepalive plan.
- The mobile app talking to Supabase (for auth JWTs only) AND to the Fastify API. JWT verification via pinned JWKS config — gaps in the flow? Token refresh edge cases beyond the singleton-promise pattern?
- CORS, cold starts (already addressed by Basic dyno but worth double-checking), Docker image size.
- GitHub Actions pipeline pushing to BOTH registries (Heroku + ECR with lifecycle policy, OIDC trust to AWS IAM role): realistic failure modes, secret rotation, deploy gating, drift between the two pushes.
- AWS demo-only path: is the ECR lifecycle policy + OIDC role + plain-HTTP `/health` setup actually defensible as a resume bullet? What breaks even at the demo-only scope? **Do not relitigate ATS/TLS — D61 settled that.**
- Observability: Sentry + pino + Better Stack log drain + daily pg_dump cron. What's missing? Anomaly detection? Uptime monitoring? Restore drill? Backup encryption?
- Anything missing entirely from the infra plan.

Output requirements:
- Be concrete and falsifiable. Name specific failure modes ("at X users you hit Y limit"), not generic concerns.
- Cap at ~300 words.
- No praise. Punch list, sorted by severity (highest first).
- If you flag something already in the doc, note the decision number (D1–D78) — that helps the synthesizer know it was deliberate.
```

### Reviewer 2 — Data model

```
You are a skeptical database / data-model reviewer. Read `/Users/zzeng/Coding/VSCodeProjects/LockedIn/docs/BRAINSTORM.md` in full, with particular attention to the "Data model (workout tracker)" section.

Context: LockedIn is a planned mobile fitness app built by a solo undergraduate. Tracks mesocycles, weekly workouts, per-set logging (planned vs logged split; dropset support via `parent_set_id` + `drop_order` where dropset children share parent's `set_number` as a group ID; superset support via `superset_group_id`), an exercise library with an `exercise_muscle` join table for weighted muscle contribution, and body weight (body_weight table noted as a TODO in the doc — flag if not added before scaffolding step 9). The DB is Postgres (Supabase). Both `user_id` AND `exercise_id` are denormalized onto `exercise_set` (round-two decision D66). A CHECK constraint requires `start_date NOT NULL` on mesocycle instances. RLS is enabled defensively but bypassed by the API's service-role connection. The "apply to future weeks" cascade rewrites `planned_*` AND `weight`/`reps` on unlogged future rows (D67). The AI agent queries via 4 read tools: `get_workout_history`, `get_body_weight_trend`, `get_current_mesocycle`, `get_volume_per_muscle_group`.

Your slice: data model only. Ignore infrastructure, mobile UI, scope. Focus on:

- Do the indexes specified actually cover the agent's 4 read tools and the per-set logging hot path? The new `(user_id, exercise_id, completed_at DESC)` and `(user_id, completed_at DESC)` partial indexes — actually correct, or is there a better composite?
- Does the schema cleanly answer: (a) "show me set-by-set fade for bench press across the last mesocycle", (b) "weekly volume per muscle group for the last 8 weeks weighted by exercise_muscle.contribution", (c) "render today's workout with planned + completed sets + dropsets in correct order", (d) "is this user progressing on barbell squat across multiple mesocycles?"
- Dropset modeling edge cases — triple drops, mid-set unlogged drops, render ordering. The doc commits to "set_number is a group ID, not unique" (D68); does that break anywhere downstream (uniqueness constraints, foreign keys, ON CONFLICT clauses)?
- Superset modeling: `superset_group_id` smallint on `workout_exercise`. Does this support tri-sets / giant-sets cleanly? Cross-superset rendering?
- Cascade semantics (D67): cascade rewrites `planned_*` and `weight`/`reps` on unlogged future rows for the same exercise across weeks N+1..final. Edge cases — what if exercise was substituted in a later week? What about cascade across dropset chains?
- `exercise_id` denormalization (D66): write-time correctness on cascade + instantiation + any future "substitute exercise" UX. Stamping cost. Risk surface.
- Templates + instances in the same `mesocycle` table with `user_id=null` for templates. RLS template-visibility carveout (D70) — clean?
- Workout completion derived from set completion (D49). Empty-workout edge case (zero exercise_set rows): planned vs unscheduled — distinguishable?
- `exercise_muscle` join table. Is the contribution numeric design (0.0–1.0) correct? Edge cases for stabilizer muscles?
- Anything missing: exercise substitution history, set notes (vs exercise-level notes), warm-up vs working sets distinction, PRs / personal records denormalized, body_weight table schema.

Output requirements:
- Be concrete. Name specific queries that will be slow or awkward, specific edge cases the schema can't represent.
- Cap at ~300 words.
- No praise. Punch list, sorted by severity.
- Cite D-numbers when flagging something already addressed.
```

### Reviewer 3 — Mobile architecture

```
You are a skeptical React Native / mobile architecture reviewer. Read `/Users/zzeng/Coding/VSCodeProjects/LockedIn/docs/BRAINSTORM.md` in full, with particular attention to the "Mobile architecture" section.

Context: LockedIn is a planned mobile fitness app built by a solo undergraduate who has never built a mobile app before. Stack: React Native + Expo + TypeScript (strict), Expo Router for navigation, TanStack Query (with `@tanstack/query-async-storage-persister` + `expo-sqlite/kv-store` for offline persistence) for server state, Zustand for global client state, NativeWind for styling (with a `cn()` helper using clsx + an `extendTailwindMerge`-wrapped twMerge), pnpm-workspaces monorepo (hoisted strategy with `.cjs`/`.mjs` source extensions added and React/RN pinned in workspace-root pnpm overrides). Feature-grouped folders under `src/features/` with a shared query-key factory at `src/lib/query-keys.ts`. Optimistic mutation pattern uses TanStack Query v5 `scope: { id: setId }` plus a client-generated `idempotency_key` UUID and a server-side 1-hour dedupe table, with server-stamped `completed_at`. Singleton `getSession()` promise in `api-client.ts` to prevent thundering-herd refreshes. Offline mutation replay requires explicit `shouldDehydrateMutation: () => true` plus `onlineManager.subscribe(...resumePausedMutations())`. Jest + React Native Testing Library for unit tests; no E2E in v1. EAS Build → TestFlight; `SENTRY_AUTH_TOKEN` as EAS secret. `expo-linking` stub from day one with URL scheme `lockedin://`.

Your slice: mobile architecture only. Ignore data model, backend infra, scope debates. Focus on:

- The committed Metro + pnpm config (hoisting, `.cjs`/`.mjs` in sourceExts, React/RN pinned). Will it actually hold up for a first-timer in 2026? Missing pieces? Any Expo SDK version mismatch risks?
- Singleton `getSession()` + 401-retry-once pattern. Edge cases beyond thundering herd: token expiry mid-request, refresh-while-online-then-offline, signed-out state during a queued mutation?
- Optimistic mutation pattern (`scope` + idempotency key + server dedupe + per-row server-stamped timestamp): realistic? Any leaks (orphaned optimistic rows on app kill mid-mutation, dedupe table miss after 1-hour TTL on a slow background sync)?
- Offline persister + explicit `resumePausedMutations` wiring: any remaining gotchas with `expo-sqlite/kv-store` as the storage backend?
- Expo Router `(auth)`/`(tabs)` group pattern with auth gating in render. Known issues in current Expo SDK? Three-state session handling (`undefined`/`null`/session) actually documented or implicit?
- NativeWind v4 with `extendTailwindMerge`. Babel plugin order (Reanimated must be last) — anything else fragile? Dark mode story?
- Workout detail screen outside `(tabs)` group hiding tab bar. `router.dismissTo` vs `router.back` from deep links.
- Accessibility minimum baseline. Realistic without explicit tooling (no `eslint-plugin-react-native-a11y` listed)?
- Testing strategy (Jest + RNTL, no E2E). Mocking Expo Router (`expo-router/testing-library`), MSW for query mocks, `jest-expo` preset — what's spec'd vs assumed?
- EAS Build + Sentry source-map upload — the doc now spells out SENTRY_AUTH_TOKEN as EAS secret + `@sentry/react-native/expo` plugin. Any remaining setup pitfalls? Hermes bytecode source-map verification?
- The `src/features/*` structure with feature-local `api.ts` + shared `query-keys.ts` factory. Cross-feature cache invalidation correctness?

Output requirements:
- Be concrete. Name specific configuration gotchas, file names, library versions where relevant.
- Cap at ~300 words.
- No praise. Punch list, sorted by severity (highest first).
- Cite D-numbers when flagging something already addressed.
```

### Reviewer 4 — Scope, timeline & resume positioning

```
You are a skeptical reviewer assessing scope realism, timeline, and resume positioning. Read `/Users/zzeng/Coding/VSCodeProjects/LockedIn/docs/BRAINSTORM.md` in full.

Context: LockedIn is a planned mobile fitness app built by a solo undergraduate as a resume project, targeting entry-level / new-grad software engineering roles including AWS-flavored cloud roles. Never built a mobile app before; new to AWS/Docker/Kubernetes. v1 scope: mesocycle-based workout tracker with per-set logging + body weight tracking + fully functional read-only AI agent (chat UI, persisted history, 4 read tools). Ships 3 templates (PPL 6, UL 4, FB 3) and ~100 hand-curated exercises. Deploys to Heroku Basic (the mobile app's only backend, custom domain + ACM TLS) and AWS ECS-on-EC2 (demo-only, plain-HTTP — README screenshots + curl-able `/health` only; iOS ATS blocks the app from calling it). Resume bullet is honestly framed as "containerized deploy to AWS ECS via GitHub Actions," not "production AWS infrastructure." 12-week timeline at 20–30 hrs/wk (~250–360 total hours).

Your slice: scope realism, timeline, and resume positioning only. Ignore data model, infra specifics, mobile architecture specifics. Focus on:

- Is 12 weeks at 20–30 hrs/wk realistic for the v1 scope as defined? Honest weeks-of-work estimate per major milestone in the doc's "Next steps" section. Where is the timeline most likely to slip?
- The decision to ship the agent in v1 (D27) at ~2–3 weeks of work: realistic? Does the agent surface (4 read tools, chat UI, persistence, rate limiting) all fit in weeks 10–12?
- The AWS ECS-on-EC2 weekend addition in week 11–12 (D48): realistic for a first-time AWS user? What's the bigger risk — that they can't do it in a weekend, or that they spend two weeks on it?
- The "Resume positioning" section that codifies what to lead with vs skim past. Anything missing? Anything overclaimed?
- Solo-dev failure modes the doc doesn't yet defend against (perfectionism on UI, gold-plating templates, never shipping the agent, etc.).
- The 3 templates + ~100 exercises authoring estimate: honest time?
- What's missing for a real shipped resume project: ADR (deferred to post-launch), TestFlight (in plan), README + GIF (in plan), tests (in plan), public demo URL (Heroku). Anything else (LinkedIn writeup, a demo video, a short blog/case study)?
- Is the agent demotion-then-reversal (D16 → D27) defensible, or should it be re-demoted to free up runway?

Output requirements:
- Be concrete and direct. Name specific risks and specific fixes.
- Cap at ~350 words.
- No praise. Punch list of risks + recommendations, sorted by severity.
- Cite D-numbers when flagging something already addressed.
```

---

## After the review

Once the synthesis is presented to the user:

1. The user will pick which items to act on now vs defer.
2. Each accepted change should get a new `D<number>` in the decisions log of `BRAINSTORM.md`.
3. Project memory at `/Users/zzeng/.claude/projects/-Users-zzeng-Coding-VSCodeProjects-LockedIn/memory/project_lockedin.md` should be updated if any load-bearing decision changes.
4. The user has indicated scaffolding (real project file creation) begins after this second review pass — so the review should also surface anything that would block scaffolding step 1 (monorepo root setup).
