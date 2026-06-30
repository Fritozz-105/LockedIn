# LockedIn — Interview Cheat Sheet

Use this before any interview where LockedIn comes up. These are the load-bearing decisions a senior engineer is most likely to probe. If you can answer all of these crisply, the project is defensible.

For deeper context on any answer, see the cited D-number in `BRAINSTORM.md`.

---

## 1. Why per-set logging instead of per-exercise? (D14)

**Short answer:** Per-exercise logging loses set-to-set fade — the exact signal needed for progressive overload analysis. A user benching 185×8, 185×7, 185×6, 185×5 looks the same in a per-exercise model as a user doing 4×8 — but they're completely different stimuli.

**The data model:** Each set is its own row in `exercise_set` with weight, reps, RIR (reps in reserve), and a server-stamped `completed_at`. Planned and logged sets share the same table; `completed_at IS NULL` means planned but not yet performed.

**Why it matters:** This is the foundation of every AI agent query. "How is bench progressing across the last mesocycle?" only makes sense if you have per-set granularity.

---

## 2. Why is `user_id` denormalized down the workout tree? (D30)

**Short answer:** Without it, every AI agent query becomes a 6-table join (`mesocycle → mesocycle_week → workout → workout_exercise → exercise_set`), and every RLS policy becomes a multi-level `EXISTS` clause. Write cost is trivial (set once at template instantiation, copied on cascade); query cost improvement is huge.

**The general principle:** Denormalize for query speed when the write path is rare or already complex. The agent reads constantly; cascades happen once per mesocycle instantiation.

**Same logic applies to `exercise_id` (D66):** denormalized onto `exercise_set` so `get_volume_per_muscle_group` is a 2-table join instead of climbing back through `workout_exercise`.

---

## 3. Why a type-shared monorepo? What does `packages/shared` do? (D10, D20)

**Short answer:** Define each API contract once as a Zod schema in `packages/shared/`, get backend validation + backend types + frontend types from one source of truth. Eliminates the entire class of "API and frontend disagree" bugs.

**Concrete example:** `LogSetRequest` is a Zod schema. The Fastify route uses it for runtime validation. TypeScript infers the backend's request type from it. The mobile app imports the same schema for its typed fetch wrapper.

**Why this drove the backend choice:** Fastify (Node + TS) won over FastAPI specifically because of type-sharing. FastAPI would force re-defining contracts on both sides.

---

## 4. How does the AI agent work end-to-end? (D7, D12, AI agent section)

**Walk through one user message:**

1. User types a message in the chat UI.
2. Mobile POSTs to `/agent/message` with the user's text + conversation ID.
3. Fastify loads the last ~10 turn pairs from `agent_message`, builds the LLM payload (system prompt + history + tools array as JSON schemas).
4. LLM responds with either text OR `tool_calls` (structured JSON like `get_workout_history(days=14)`).
5. If tool_calls: Fastify executes the function against Postgres (filtered by `request.user.sub` — LLM never sees the user_id), captures the result, truncates to ~4KB, sends back as a `tool` role message.
6. Loop until LLM stops requesting tools and returns final text.
7. Every turn persists to `agent_message` for history.

**What you DIDN'T use:**
- **Not LangChain** — extra framework, hides the API surface you're trying to learn.
- **Not MCP** — MCP is for exposing tools to *external* clients (Claude Desktop). Your app IS the client; you control both sides.

---

## 5. Why read-only tools in v1? Why not write tools? (D9, D27)

**Short answer:** Write tools (`log_workout_set`, `log_body_weight`) open data-corruption risk if the model misfires. A hallucinated `log_workout_set(weight=405)` on a user who benches 185 silently writes a junk row.

**v1 ships read-only because:** Get the agent solid first, then add write tools with a confirmation UX (user reviews + applies). Promotes to v1.1 after the read agent is trusted.

**Why this isn't a cop-out:** The 4 read tools alone (`get_workout_history`, `get_body_weight_trend`, `get_current_mesocycle`, `get_volume_per_muscle_group`) give the agent enough context to make recommendations. The user applies them manually.

---

## 6. Heroku vs AWS — what's the actual deployment story? (D48, D61, D78)

**Short answer:** Heroku is the only backend the mobile app calls. AWS ECS-on-EC2 exists for the containerization + CI bullet via README screenshots and `curl /health`.

**Why:** The AWS free-tier path (ECS-on-EC2, no ALB) serves plain HTTP only. iOS App Transport Security blocks plain HTTP from React Native apps. Adding an ALB ($20/mo) or Caddy + Let's Encrypt to get HTTPS on AWS would exceed the bullet's value.

**The honest framing:** "Containerized Node/Fastify backend with CI/CD pipelines to Heroku (production) and AWS ECR/ECS (validation environment)." Don't say "production AWS infrastructure" — you'd get caught in one follow-up question.

**The same Docker image goes to both** via GitHub Actions (SHA-tagged for traceability, atomic push gating so they never drift).

---

## 7. Why JWKS for JWT verification, not a shared secret? (D29, D64)

**Short answer:** JWKS = JSON Web Key Set. Supabase publishes the public keys; your API fetches them at startup and verifies tokens against them. No shared secret to rotate; survives Supabase key rotations without redeploying.

**The pinned config matters:** `cache: true`, `cacheMaxAge: 10min`, `rateLimit: true`. Without cache, every request fetches JWKS (latency + rate-limit risk). Without rateLimit, key rotations cause request storms.

**Standard pattern:** This is how production OAuth/OIDC systems verify tokens. Future-proof if you ever swap auth providers.

---

## 8. Why service-role connections + app-level authz instead of RLS-via-JWT-passthrough? (D63)

**Short answer:** The mobile app never queries Postgres directly — it only talks to Supabase for auth. All data flows through Fastify. RLS would never fire from the mobile direction, so passing the user's JWT to Postgres just to invoke RLS is pointless complexity that also breaks with the transaction pooler.

**What I did instead:** Fastify connects as the service role (bypasses RLS by default). Every DB call goes through a `db.forUser(userId)` helper that pre-binds a `user_id = $userId` filter. Forgetting the filter requires actively reaching past the helper.

**Defense in depth:** RLS policies stay enabled with default-deny on every user-scoped table. If a future feature ever connects with the anon key (debug tool, web admin), the defenses are still there.

---

## 9. Walk me through the optimistic mutation pattern for set logging. (D37, D74, D94)

**The flow:**

1. User taps "log set." `onMutate` cancels in-flight queries for the workout, snapshots the cache, writes the optimistic row (with a client-generated UUID `idempotency_key`).
2. UI shows the set immediately. POST fires in the background.
3. Server validates, checks the dedupe table for the `idempotency_key`, inserts if new, returns the row with `completed_at` server-stamped.
4. `onSuccess` replaces the optimistic row with the server response. `onError` rolls back to snapshot.

**Why each piece:**
- **`scope: { id: setId }`** — TanStack Query v5. Serializes network calls per row. Two rapid taps queue serially instead of racing.
- **`idempotency_key` + 48-hour server dedupe table** — prevents double-logged sets on retry-after-5xx with flaky network.
- **Server-stamped `completed_at`** — never trust client clocks. They drift.

**Edge case handled:** App killed mid-mutation leaves an optimistic row in the persisted cache. Rehydrate-time reconciliation purges rows older than 24h with no matching server row.

---

## 10. How are dropsets modeled? (D14, D34, D68, D79)

**The structure:** A dropset is a child `exercise_set` row pointing to its parent via `parent_set_id`. `drop_order` (1, 2, 3...) gives stable ordering within the drop chain.

**The tricky part:** `set_number` on a dropset child equals its parent's `set_number` — it's a group ID, not a unique key. So:
- "Working sets logged" = `COUNT(*) WHERE parent_set_id IS NULL AND completed_at IS NOT NULL`
- "Render order" = `ORDER BY set_number ASC, drop_order ASC NULLS FIRST`

**Integrity:** Composite UNIQUE `(workout_exercise_id, set_number, drop_order)` prevents races. `ON DELETE CASCADE` on both `workout_exercise_id` and `parent_set_id` so substituting an exercise (delete + recreate the slot) doesn't orphan child sets.

---

## 11. What does the "apply to future weeks" cascade actually do? (D31, D44, D67, D80)

**Short answer:** When a user edits week N's bench press to 195×8 and picks "apply to future weeks," the cascade rewrites both `planned_weight`/`planned_reps` AND `weight`/`reps` on every unlogged future row in weeks N+1..final — for the same `exercise_id`.

**What it does NOT touch:** Already-logged rows (`completed_at IS NOT NULL`). Historical truth is preserved.

**Edge case:** If the user previously substituted bench → incline bench in week 5, the cascade matches on `exercise_id` and skips week 5. The UI shows a confirmation modal: *"This will update bench press in weeks 3, 4, 6. Week 5 has been substituted to incline bench — skipped. Continue?"*

**Why this design:** "Apply to future weeks" means the plan changed, not "log a one-off." Cascades are the only mechanism that legitimately mutates `planned_*` after instantiation.

---

## 12. Why no Kubernetes? Why no LangChain? Why not Cognito? (D3, D5, D7)

**Kubernetes:** Cargo-cult signal on a solo side project. Overkill for one container. If you want K8s on the resume, build a separate small K8s project — don't bolt it onto something that doesn't need it.

**LangChain:** Extra framework, extra indirection, hides the OpenAI SDK API surface you're trying to learn. The ecosystem is moving away from it. Direct SDK function-calling is what production teams actually use.

**MCP:** MCP is a protocol for exposing tools to *external* AI clients (Claude Desktop, etc.). Your app IS the client; you control both sides. MCP solves a different problem.

**Cognito:** Notoriously painful developer experience for the auth flows you actually need. Supabase Auth is the pragmatic choice — and it bundles the database you needed anyway.

---

## How to use this in an interview

- **Don't memorize verbatim.** Memorize the SHAPE of the answer (the trade-off, the alternative, the reason). Then talk through it naturally.
- **Lead with the WHY, not the WHAT.** "I denormalized `user_id` because..." not "I denormalized `user_id`."
- **Volunteer one alternative you considered and why you rejected it.** Shows you actually thought about it.
- **Have a "what would I do differently" answer ready.** Honest reflection > defensive posture. (Example: "I'd probably extract the API client into a shared package earlier so the mobile and a future web client could share it.")
- **If you genuinely don't know:** "I haven't run into that yet — what would you reach for?" Better than bluffing.
