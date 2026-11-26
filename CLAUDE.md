# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

"Escudo Familiar" — a family safety app with three independent subsystems,
each with its own plan under `docs/superpowers/plans/`:

1. **Supabase backend** (`supabase/`) — the only one with code so far. One
   Postgres schema, RLS as the sole access boundary (no separate API layer).
2. **Android app** (not started) — runs on the children's phones only.
3. **Web dashboard** (not started) — the parents' panel; a responsive site
   (Next.js/React), not a native app, because it must work from a browser on
   both Android and Windows.

Read `docs/superpowers/specs/2026-11-25-escudo-familiar-design.md` before
touching anything — it is the binding spec every plan argues from, and it
carries constraints that are not optional implementation details:

- **Never** read or store message/notification content (WhatsApp, SMS,
  social apps) — not a non-goal to revisit, a hard line.
- **Never** monitor an adult (the spouse or anyone else) without that
  person's own active consent. Only the two parents and the two named minor
  children are in scope.
- A child's monitoring stops automatically at 18; `children.birthdate` is
  editable only by the `parents` role, enforced in RLS, not in app code.
- Not distributed via Play Store (sideload only) — do not add Play
  Store-oriented code (e.g. Play Billing, Play Integrity assumptions).

## Backend architecture (`supabase/`)

RLS is the entire security model — there is no backend API server. Every
table with a `child_id` enforces access through two SQL helper functions
defined in migration `0001`:

- `is_parent()` — true if `auth.uid()` has a row in `parents`. Parents get
  full access to every child's data; there is no per-parent partition (both
  parents see the same family data).
- `is_own_child(child_id)` — true if `auth.uid()` is that child's
  `device_user_id`. A child's device account can only ever touch its own
  rows, and typically only `insert` (telemetry), never `select` on sensitive
  tables like `locations`.

Each child's Android app authenticates as its own dedicated Supabase Auth
account (`children.device_user_id`), provisioned by the parents at setup —
never created by the child. This identity model, and every other
cross-cutting backend decision (push via Firebase, no SMS fallback in v1,
180-day location retention via `pg_cron`), is recorded in the spec's
Constraints section, not re-derived from the schema.

Migrations live in `supabase/migrations/NNNN_*.sql`, one per task in
`docs/superpowers/plans/2026-11-25-escudo-familiar-backend.md`; each owns its
own tables and RLS policies and documents in its plan task what it consumes
from earlier migrations (`is_parent()`, `is_own_child()`) and produces for
later ones. Corresponding RLS tests live in `supabase/tests/NNNN_*.test.sql`,
run with `psql` against the local stack, impersonating a specific
`auth.uid()` via the `test.assume_user()` helper in `supabase/tests/_helpers.sql`.
Every test file wraps its fixtures and assertions in `begin; ... rollback;`
so it can be re-run against the same long-lived local stack without
unique-constraint collisions with other tasks' fixtures — this is a
project-specific convention, not a Supabase default.

## Commands

Local Docker Desktop/WSL2 on Windows turned out not to be viable for this
project (WSL2's container runtime repeatedly hung and once took the whole
machine down) — **this project has actually been tested, from very early
in the implementation onward, against a Supabase dev stack running on a
remote VPS over SSH**, not against a locally-running `supabase start`. Keep
using that workflow:

```bash
# SSH target (key-based auth, no password needed):
#   root@193.203.182.112
# Repo clone on the VPS, same branch as this worktree:
#   /root/projetos/funfam

# 1. Sync the VPS clone with whatever you just pushed/committed locally:
ssh root@193.203.182.112 "cd /root/projetos/funfam && git fetch origin && git reset --hard origin/<branch>"

# (If you're iterating on uncommitted local changes instead, scp the
# changed file(s) to the same path under /root/projetos/funfam/ first.)

# 2. Apply every migration fresh (also applies supabase/seed.sql — see the
#    UUID-range note below) and bring up the dev stack:
ssh root@193.203.182.112 "cd /root/projetos/funfam && supabase db reset"

# 3. Run each RLS test file over SSH, against the VPS's local Postgres
#    (reachable only via SSH, not exposed publicly):
ssh root@193.203.182.112 "psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -f /root/projetos/funfam/supabase/tests/0001_parents_and_children.test.sql"
# (repeat per supabase/tests/000N_*.test.sql file)

supabase link                      # connect to the real hosted project (Task 7 only)
supabase db push                   # apply migrations to the hosted project
```

**`seed.sql` uses its own UUID range, disjoint from every test file.**
`supabase db reset` applies `supabase/seed.sql` (enabled via `[db.seed]` in
`config.toml`) immediately after migrations, and those rows are never
rolled back — unlike every `supabase/tests/*.test.sql` file's own fixtures,
which live inside `begin; ... rollback;`. `seed.sql` therefore uses only
hex-letter UUIDs (`aaaa…`/`bbbb…`/`cccc…`/`dddd…`/`eeee…`/`ffff…`) and a
distinct email domain, deliberately disjoint from every test file's digit-
only fixture UUIDs (`1111…`, `2222…`, `3333…`, `4444…`, `5555…`, `6666…`,
`7777…`) and `@example.com` emails. If you ever add a new UUID to
`seed.sql`, keep it in that same hex-letter range — otherwise a real
`supabase db reset` followed by any test file's plain (non-`on conflict`)
fixture insert will hit a unique-constraint violation against seed's
permanently-committed rows.

If you ever do need to debug against a local Docker stack instead: local
Postgres requires Docker Desktop + WSL2 (Windows). If `docker info` fails,
Docker Desktop likely isn't running yet — launch it and wait; it can take a
few minutes on first start after install/reboot. This was never reliable
enough to use as the actual test workflow for this project, though.

## Working process

This repo is being built with the `superpowers` skill set
(`superpowers:brainstorming` → `superpowers:writing-plans` →
`superpowers:subagent-driven-development`). Each plan's live execution state
— ledger, task briefs, implementer reports, review packages — lives under
`.superpowers/sdd/<plan-name>/` inside whatever git worktree is executing it
(git-ignored, not part of the shipped code). Don't treat files there as
project documentation; they're scratch state for resuming an in-progress
plan. The durable record is the plan and spec files under `docs/superpowers/`.

Implementation happens in a dedicated git worktree per plan, never directly
on `master` — see the ledger under `.superpowers/sdd/` for which worktree
and branch is live for a given plan.
