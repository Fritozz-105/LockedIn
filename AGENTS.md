# AGENTS.md

Instruction file for OpenCode. Claude Code reads `CLAUDE.md`; OpenCode reads
this file plus `CLAUDE.md`, `docs/PROJECT.md`, `docs/STATE.md`, and
`docs/ROADMAP.md` via `opencode.json`'s `instructions` array, so both engines
share one source of truth.

## Source of Truth

- **`CLAUDE.md`** — project overview, tech stack, architecture, git flow, commit format. Authoritative.
- **`docs/BRAINSTORM.md`** — the canonical decision log (D1–D108); read before proposing architectural changes. Each decision is a re-openable working default.
- **`docs/PROJECT.md`** — what's being built and why; requirements; constraints.
- **`docs/STATE.md`** — current position; points to the **active phase directory** and its `PLAN.md`.
- **`docs/phases/{NN}-{name}/PLAN.md`** — the executable plan for the active phase.

To get oriented (the Codex equivalent of `/catchup`): read `CLAUDE.md`,
`docs/PROJECT.md`, `docs/STATE.md`, then the active phase's `PLAN.md`.

## Git flow (hard rule)

`develop` = integration, `main` = production. **Never merge to `main` without the user's explicit review.** Work on branches off `develop`; promote via a `develop`→`main` PR the user reviews.

## Executing a Plan (the Execution Contract)

When asked to implement a `PLAN.md`, follow its **Execution Contract** exactly:

1. Execute tasks in order; respect each task's `Depends on`.
2. **Commits are optional, chosen per run** (asked at the start): `per-task`, `at-end`, or `none`. **Verification-only tasks** never commit — record results in the plan's **Deviations Log**. Never make empty commits. Commit format from `CLAUDE.md`.
3. **TDD:** write the task's named failing test first, watch it fail, then implement until it passes — nothing beyond the task's scope. Where no test harness exists, the task's **Acceptance** check substitutes.
4. **Do NOT improvise** architecture, add scope, or substitute a different approach than the plan specifies.
5. **STOP-AND-REPORT** — if a named file/symbol doesn't exist or has a different signature, a precondition is false, the specified test can't be run as described, or reality contradicts the plan: **HALT**, append to the plan's **Deviations Log**, and surface it. Never work around a contradiction silently. A **[human]** task (needs a web UI, credential, or approval) is itself a STOP-AND-REPORT.

This is what "don't deviate from the plan" means here: **never deviate silently.**

## After Implementing

- Run the plan's **Must-Haves** checklist with real commands; confirm output.
- Update the plan: check off must-haves, set `Status: Complete`.
- Record any execution-time decision in `docs/records/NNN-{slug}.md`.
- Update `docs/phases/{NN}-{name}/SUMMARY.md`.
