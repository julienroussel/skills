---
name: jr-rollup
description: Cross-app health rollup. Aggregates each app's `.claude/health.json` snapshot (written by /jr-audit at Phase 7) into one estate view — a worst-first table plus a portfolio summary (band counts, total remaining criticals, staleness, incomplete and never-audited apps). Read-only; never runs an audit. Wraps the deterministic companion CLI `bin/jr-rollup`, then interprets which apps to prioritise.
argument-hint: "[root | app-dir ...] [--json]"
effort: low
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Glob Bash(bash *) Bash(test *)
---

# /jr-rollup — cross-app health rollup

Aggregate every app's `/jr-audit` health snapshot into one estate view. The deterministic
aggregation (read each `<app>/.claude/health.json`, sort worst-first, compute staleness, tally the
portfolio) is done by the companion CLI **`bin/jr-rollup`** — this skill runs it and tells you what
to act on. **Read-only: it never runs an audit.**

**The request:** `$ARGUMENTS` → passed straight through to the CLI (an optional root path, and/or
explicit app dirs, and/or `--json`). No args ⇒ the CLI discovers apps from the current directory:
git submodules, else the union of any dir already holding a `.claude/health.json` (name-agnostic)
and standard component dirs (`apps|packages|services|libs/*` plus common top-level names like `e2e`,
`docs`, `web`, `api`, `infra`, …) — that component sweep is skipped when the root itself holds a
valid, complete snapshot, whose audit already covered the root's whole tree (an unreadable or
incomplete one does not count) — else the repo root itself. Works with or without submodules.

## Workflow

### 1. Run the CLI (single source of truth for the numbers)
Resolve `bin/jr-rollup` relative to this skill, falling back to the absolute path:
```
CLI="${CLAUDE_SKILL_DIR}/../bin/jr-rollup"; test -x "$CLI" || CLI="$HOME/.claude/skills/bin/jr-rollup"
bash "$CLI" $ARGUMENTS
```
If it exits non-zero with a missing-dependency message (`jq` / `git` / `column`), relay that and
stop. Do NOT hand-roll the aggregation or recompute any number — the CLI owns the figures.

### 2. Present + interpret (never recompute)
Show the CLI's table and portfolio summary. Then add a short, grounded read on top, **citing the
CLI's own numbers, never inventing**:
- **Act now** — apps with remaining criticals, then the lowest scores (RED band, <41).
- **Watch** — AMBER apps (41–70); **stale** apps (code moved since the audit → re-run `/jr-audit` there).
- **Blind spots** — never-audited, **incomplete** (the run was never scored — either a reviewer or an
  implementer returned nothing, so part of it never happened, or it went unscored with no loss named:
  no reliable signal either way, re-run `/jr-audit` there), and invalid apps
  (no reliable signal: run `/jr-audit` in them, or investigate a malformed snapshot).
Keep it to a few lines. If every app is GREEN and fresh, say so plainly rather than manufacturing concern.

### 3. Populating the rollup
The rollup only sees apps that already have a `.claude/health.json` (written by `/jr-audit` at
Phase 7). To populate or refresh: run `/jr-audit` (or `/jr-audit nofix`) in each app. The rollup
never triggers audits itself.

### 4. Reading `--json`
**`status: "incomplete"` is the signal, not `unreported`.** Each `unreported` entry names one lost
member of that run's swarm, a reviewer dimension or an implementer — but the array names the losses
only **when they are known**. An empty array on an `incomplete` record means *not known*, never
*none*: a snapshot that published `healthScore: null` without naming anything still lost part of its
run. Never read an empty array as a benign record. `reason` is display-only — the same list
comma-joined, or `unscored` when the score is null and no loss was named, or a
fixed enum (`bad-json` / `bad-schema`) for `invalid`; it is `null` for `fresh` / `stale` /
`never-audited`. The text table does not render `reason` on an `incomplete` row: it recomputes that
cell from `unreported`, prefixed `lost:` (`incomplete(lost:security-reviewer,p1/impl-2)`, versus
`incomplete(unscored)` when nothing was named), so a snapshot cannot name a subagent `unscored` and
disguise its own loss. Consume `unreported`, never split
`reason`. `path` is the app's absolute path, at either arity. For an `incomplete` record, `healthScore` and `counts` are forced to `null` regardless of
the snapshot's contents — a partly-silent swarm's counts cover only the dimensions that reported and
are not comparable with a complete audit. Read `unreported` to see what was lost; the snapshot's own
partial `counts` are intentionally not surfaced.

## Style
British English, terse, scannable. The CLI owns the numbers; you own the one-paragraph "what to do
about it". Never soften a RED score or a critical count, and flag stale/incomplete/never-audited apps rather
than implying the estate is healthier than the data shows.
