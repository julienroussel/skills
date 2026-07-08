---
name: jr-rollup
description: Cross-app health rollup. Aggregates each app's `.claude/health.json` snapshot (written by /jr-audit at Phase 7) into one estate view — a worst-first table plus a portfolio summary (band counts, total remaining criticals, staleness, never-audited apps). Read-only; never runs an audit. Wraps the deterministic companion CLI `bin/jr-rollup`, then interprets which apps to prioritise.
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
`docs`, `web`, `api`, `infra`, …), else the repo root itself. Works with or without submodules.

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
- **Blind spots** — never-audited and invalid apps (no reliable signal: run `/jr-audit` in them, or
  investigate a malformed snapshot).
Keep it to a few lines. If every app is GREEN and fresh, say so plainly rather than manufacturing concern.

### 3. Populating the rollup
The rollup only sees apps that already have a `.claude/health.json` (written by `/jr-audit` at
Phase 7). To populate or refresh: run `/jr-audit` (or `/jr-audit nofix`) in each app. The rollup
never triggers audits itself.

## Style
British English, terse, scannable. The CLI owns the numbers; you own the one-paragraph "what to do
about it". Never soften a RED score or a critical count, and flag stale/never-audited apps rather
than implying the estate is healthier than the data shows.
