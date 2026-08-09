# `/jr-skill-audit` — dependency manifest

**Maintainer reference, not runtime content.** Extracted from `SKILL.md`'s header comment so it stops
costing ~6,500 characters of the skill's compaction-retained window on every run (nothing in the body
reads it). `SKILL.md`'s Phase 1 Track A section remains the authoritative read list for what is actually
loaded; this file is the wider inventory.

## Required agent types

Repo-local native `.claude/agents/`, no plugin:

- **`jr-reviewer`** — reviewer agents (Phase 2). `.claude/agents/jr-reviewer.md` installed at
  `~/.claude/agents/` (see README install), spawned via the Agent tool **without `name:`** (see
  `shared/subagent-reporting.md` "Spawn rule").

## Required CLI

Three tiers. Only the first aborts unconditionally; provision against the first two, not the last.

- **`realpath`** — **required; absent ⇒ the run aborts.** Phase 1 Track B probes for it and fails fast with
  `abortReason="realpath-unavailable"` → `[ABORT — REALPATH UNAVAILABLE]`
  (`protocols/personal-project-scope.md` "Scope roots"); two further hard-abort sites are
  `protocols/plugin-scope.md` "Enumerate git-tracked skills" and Phase 3 step 1a
  (`protocols/finding-validation.md` "Contain before opening"). Containment of every reviewer-cited path
  rests on it, and the skill aborts rather than degrading to a check that opens what it cannot verify.
- **`git`** — **required under `--plugin`; degrades silently everywhere else.** `--plugin` resolution is
  entirely `git rev-parse` / `git ls-files` over the marketplace clone, so without it that mode has
  nothing to enumerate. On a personal/project run its two uses are advisory and both swallow failure
  (`2>/dev/null`, empty output read as "no repo"): Track B's per-scope gitignore exclusion of
  externally-maintained skills, and Track C's cache-path probe. Absent `git`, those two checks do nothing
  and say nothing.
- **`gh`** — **optional; absent ⇒ documented degradation, never an abort.** Phase 1 Track C:
  `gh api repos/anthropics/claude-code/contents/CHANGELOG.md` for changelog content (`gh` handles GitHub
  auth + redirects; preferred over WebFetch per WebFetch's own guidance for github.com URLs). Without it,
  or unauthenticated, that key caches `ok: false`; the run continues and Phase 7 reports the degradation
  (SKILL.md Track C, "Same rule per key").

## Files read

| Path | When |
|---|---|
| `~/.claude/skills/*/SKILL.md` | Every repo-owned personal skill (gitignored / externally-maintained skills excluded — Phase 1 Track B) |
| `<walked-dir>/.claude/skills/*/SKILL.md` | Project-scoped skills, walked from `$PWD` up to repo root. An unfiltered run from a foreign repo that has its own skills audits these ALONE (auto-scope); elsewhere they are audited alongside personal. Pin with `--scope-only` |
| `<skill>/scripts/*.sh`, `<skill>/templates/*` | Referenced helper scripts / templates (existence + executable bit) |
| `~/.claude/plugins/marketplaces/<mp>/<source>/skills/*/SKILL.md` | Git-tracked plugin skills, opt-in via `--plugin=<name>` (resolved from `known_marketplaces.json` + each marketplace's `.claude-plugin/marketplace.json`) |
| `${CLAUDE_SKILL_DIR}/cache/refs.json` | Cached Anthropic docs + changelog (Track C). Refreshed when ANY of: `--refresh-refs` is set; the file is missing; `fetchedAt` is older than 7 days; a ref key the schema declares is absent; a declared key fails the step-4 content-shape assertion; `refsSpecVersion` differs from the current spec version. Canonical: SKILL.md Track C "Refresh logic" |

## Protocol files read at runtime

`SKILL.md` Phase 1 Track A is the authoritative read list: which `shared/*.md` and skill-local
`protocols/*.md` files are read, when (unconditional, `--plugin`-conditional, `--report`-conditional, or
deferred to the phase that applies them), and each one's smoke-parse anchors. Deliberately **not**
restated here. A second, non-authoritative copy of a read list, with nothing checking it at author time,
is a drift surface rather than an inventory.

**Not read** (and therefore outside `shared-drift-reviewer`'s detection, which receives only the
`shared/*.md` files Track A actually loaded): `audit-history-schema.md`, `cache-schema-validation.md`,
`code-edit-discipline.md`, `forge-detection.md`, `secret-patterns.md`, `secret-warnings-schema.md`.
Six of the seventeen `shared/*.md` files. Drift against these is not detected by this skill;
`/jr-doctor` Group D smoke-parses every row in the Canonical Anchor Table.

## Files written

| Path | When |
|---|---|
| `${CLAUDE_SKILL_DIR}/cache/refs.json` | Track C live-references cache (timestamp + URL → content map) |
| `<repo>/.claude/skill-audit-<date>.md` | `--report` archival report (project scope; inside the audited repo) |
| `~/.claude/skill-audit-reports/skill-audit-<scope>-<date>.md` | `--report` archival report (personal/both/plugin; outside any repo) |

## Required tools

`Agent`, `AskUserQuestion`, `advisor`, `Bash`, `Read`, `WebFetch`, `Glob`, `Grep`, `Write`.

**Deliberately NOT used** (unavailable to the lead, or a lossy channel — see
`../shared/subagent-reporting.md`): `TaskCreate`, `TaskList`, `TaskGet`, `TaskUpdate`, `SendMessage`.

## Out of scope in v1

Auto-fix (#15), Phase 8 follow-up issues (#16).
