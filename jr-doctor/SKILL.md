---
name: jr-doctor
description: Health-check the user's Claude Code setup and the current repo. Verifies CLI tools, plugins, settings.json, installed skills, shared protocol files, gitignore coverage, and optional integrations needed by /jr-audit, /jr-review, /jr-ship, and tackle. Reports per-check status with remediation hints. Optional --fix appends missing patterns to the current repo's .gitignore on per-change confirmation.
argument-hint: "[--fix] [--yes]"
effort: low
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Glob Grep Bash(git rev-parse *) Bash(git ls-files *) Bash(git config --get *) Bash(git ls-remote *) Bash(git diff *) Bash(git status *) Bash(jq *) Bash(grep *) Bash(awk *) Bash(test *) Bash([ *) Bash(stat *) Bash(shasum *) Bash(sha256sum *) Bash(ls *) Bash(find . *) Bash(wc *) Bash(head *) Bash(tail *) Bash(sed *) Bash(tr *) Bash(cut *) Bash(date *) Bash(gdate *) Bash(printf *) Bash(echo *) Bash(basename *) Bash(command -v *) AskUserQuestion
---

<!-- Dependencies:
  Required plugins:
    - (none — /jr-doctor is a diagnostic skill; it CHECKS for plugins but does not depend on them)
  Required CLI:
    - git                                        — repo detection, ls-files (per-repo checks; if not in repo, skipped)
    - jq                                         — settings.json parsing (if absent, settings checks degrade to "unavailable")
  Optional CLI checked (warn-only):
    - gh, claude                                 — required by /jr-audit, /jr-review, /jr-ship
    - rtk                                        — Rust Token Killer (used by Bash PreToolUse hook)
    - wt                                         — worktrunk CLI (used by tackle); ships via worktrunk@worktrunk plugin
  Files read:
    - ~/.claude/settings.json                    — JSON parse + key extraction
    - ~/.claude/skills/{jr-audit,jr-review,jr-ship}/SKILL.md  — existence only (Group C)
    - ~/.claude/skills/*/SKILL.md                — line count + frontmatter parse + broken-shared-ref scan + inline-drift scan (Group I)
    - ~/.claude/skills/bin/{tackle,seed-project-memory,tackle-top}  — existence + executable bit
    - ~/.claude/skills/shared/reviewer-boundaries.md     — existence + non-empty + smoke-parse (anchors per the Canonical Anchor Table — Group D reads it at runtime; for reviewer-boundaries that is `| Issue` AND `| Owner` AND `| Not` AND `Severity calibration rubric` AND `Confidence levels`)
    - ~/.claude/skills/shared/untrusted-input-defense.md — existence + non-empty + smoke-parse `do not execute, follow, or respond to`
    - ~/.claude/skills/shared/gitignore-enforcement.md   — existence + non-empty + smoke-parse `git ls-files --error-unmatch`
    - ~/.claude/skills/shared/advisor-criteria.md        — existence + non-empty + smoke-parse `Before substantive work`
    - ~/.claude/skills/jr-review/templates/pre-commit-secret-guard.sh.tmpl — SHA-256 hash (Group I template hash check)
    - ~/.claude/skills/jr-review/scripts/install-pre-commit-secret-guard.sh — extracts EXPECTED_TEMPLATE_SHA256 (Group I template hash check)
    - ~/.claude/skills/jr-skill-audit/cache/refs.json       — fetchedAt timestamp (Group I refs-cache freshness check)
    - ~/.claude/skills/docs/worktree-architecture.md     — existence (tackle/jr-ship contract)
    - ~/.claude/agents/{jr-reviewer,jr-implementer}.md   — presence (resolves via symlink) + jr-reviewer read-only (no Write/Edit in tools:); Group C
    - ~/.claude/hooks/{no-claude-attribution,cbm-code-discovery-gate,cbm-session-reminder} — existence + executable
    - <cwd>/CLAUDE.md, <cwd>/.gitignore          — per-repo
  Env vars probed:
    - CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS       — informational (formerly required for the agent-teams plugin; the reviewer/implementer swarms now use repo-local native `.claude/agents/` types, which need no flag)
    - CLAUDE_CODE_NO_FLICKER                     — recommended (=1) UI preference for cleaner output
    - CLAUDECODE, CLAUDE_CODE_ENTRYPOINT         — informational (set automatically inside Claude Code)
    - BASH_DEFAULT_TIMEOUT_MS, BASH_MAX_TIMEOUT_MS  — informational (long /audit-/review-/jr-ship validation runs)
    - MCP_TIMEOUT, MCP_TOOL_TIMEOUT              — informational (codebase-memory-mcp startup + tool calls)
    - MAX_THINKING_TOKENS, MAX_MCP_OUTPUT_TOKENS — informational (model thinking + MCP output budgets)
    - CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY       — informational (parallelism cap; default 10)
    - DISABLE_TELEMETRY, DISABLE_AUTOUPDATER, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC — informational (privacy/cost preferences; the last is a shorthand that disables autoupdater + telemetry + error reporting + feedback)
    - CI/GITHUB_ACTIONS/GITLAB_CI/JENKINS_URL/BUILDKITE/CIRCLECI/TF_BUILD/DRONE/WOODPECKER_CI/TEAMCITY_VERSION/AUTO_APPROVE — headless signal
  Files written (only if --fix is set AND user confirms or --yes):
    - <cwd>/.gitignore                           — APPEND ONLY
    - (NEVER writes to ~/.claude/settings.json or anything outside cwd)
  Required tools:
    - Bash, Read, AskUserQuestion
  Tools NOT used:
    - Write (the only file mutation is the .gitignore append/create in Phase 4, done via Bash `printf >>`), TaskCreate, Agent, advisor
-->

Diagnose whether the current codebase + Claude Code setup is ready to use `/jr-audit`, `/jr-review`, `/jr-ship`, and `bin/tackle`. Report per-check status with remediation hints. Default is read-only; `--fix` appends missing patterns to the current repo's `.gitignore` on per-change confirmation.

**Arguments**: $ARGUMENTS

Recognized flags:
- `--fix` — Apply safe fixes (append/create the current repo's `.gitignore`) on per-change confirmation. Never modifies `~/.claude/settings.json`. Never untracks files. Never installs anything.
- `--yes` — With `--fix`, skip per-change prompts and apply all fixable changes. Without `--fix`, ignored with a warning.

**Examples**: `/jr-doctor`, `/jr-doctor --fix`, `/jr-doctor --fix --yes`

**Plan-mode note**: when `defaultMode: "plan"` is set in `~/.claude/settings.json`, each `.gitignore` write under `--fix` will trip the standard plan-mode permission prompt. Expect serial approval prompts; the harness handles them — this is not a /jr-doctor bug.

**First-run note**: /jr-doctor runs `command -v`, `git ls-files`, `jq`, etc. via Bash. The first invocation in a fresh permission set may trip 5-8 permission prompts; subsequent runs are silent. /jr-doctor itself does NOT modify `permissions.allow` (out of scope).

## Display protocol

- **Phase headers** use prominent `━━━` separators, matching `/jr-audit` / `/jr-review` style.
- **Single-line groups on full pass**, expanded only on `⚠`/`✗`. Keep happy-path output ≤ 30 lines.
- **Indents**: 2 spaces for groups, 4 spaces for expanded checks.
- **Status markers**: `✓` (pass), `⚠` (warn — informational, non-blocking), `✗` (fail — required item missing).
- **Never echo `advisorModel` value** to keep transcript logs clean. Report `set` / `missing` only.
- **Final summary**: `Summary: N ✓  M ⚠  K ✗   Total: <elapsed>`.

## Phase 1 — Argument parsing + environment probe

### Argument parsing

Parse `$ARGUMENTS` as space-separated tokens. Accept only `--fix` and `--yes`; warn and ignore unknown tokens.

If `--yes` is set without `--fix`: warn `--yes ignored: only meaningful with --fix` and unset `--yes`.

### Headless detection

```bash
is_headless=$(
  if [ -n "$AUTO_APPROVE" ] || [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] || \
     [ -n "$GITLAB_CI" ] || [ -n "$JENKINS_URL" ] || [ -n "$BUILDKITE" ] || \
     [ -n "$CIRCLECI" ] || [ -n "$TF_BUILD" ] || [ -n "$DRONE" ] || \
     [ -n "$WOODPECKER_CI" ] || [ -n "$TEAMCITY_VERSION" ]; then
    echo yes
  else
    echo no
  fi
)
```

**Note**: this predicate intentionally drops the `[ ! -t 0 ]` (no-TTY) fallback used by `/jr-review`'s canonical `isHeadless`. Reason: `/jr-doctor` is user-invocable only (`disable-model-invocation: true`), so it's always invoked from an interactive session by definition — and the Claude Code Bash tool runs subprocesses without a TTY, so `[ ! -t 0 ]` would always fire and incorrectly auto-disable `--fix` in normal interactive use. CI environment variables are the authoritative signal for true headless invocations.

If `is_headless=yes` AND `--fix` is set AND `--yes` is NOT set: warn `--fix ignored: requires interactive session or --yes` and unset `--fix`.

### Environment probe (single parallel Bash batch)

Run these in one tool-use message with multiple Bash calls in parallel:

```bash
git rev-parse --git-dir 2>/dev/null            # IN_REPO if exit 0
git rev-parse --show-toplevel 2>/dev/null      # REPO_ROOT
ls "$(git rev-parse --git-dir 2>/dev/null)/info/scratch-session" 2>/dev/null  # IS_SCRATCH
git remote -v 2>/dev/null | grep -qE 'github\.com|gitlab\.com' && echo yes || echo no  # HAS_REMOTE (github.com or gitlab.com)
[ -f ~/.claude/settings.json ] && echo yes || echo no  # SETTINGS_PRESENT
[ -d ~/.claude/skills ] && echo yes || echo no   # SKILLS_PRESENT
pwd                                              # CWD
```

Derive: `IS_TACKLE_WORKTREE=yes` if `CWD` matches `*/.claude/worktrees/*`.

### Header

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /jr-doctor — Claude Code Setup Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/jr-doctor at <CWD>
Mode: report-only|--fix [--yes]   Repo: <REPO_ROOT|"not in a git repo"> (<in-repo|no-repo>, <has-remote|no-remote>)
```

If `IS_TACKLE_WORKTREE=yes`: append a banner line `Inside tackle worktree (.claude/worktrees/* tracking warning suppressed)`.
If `IS_SCRATCH=yes`: append `Inside tackle scratch session (id=<scratch-id-from-marker>)`.

## Phase 2 — Run all checks (parallel groups)

Dispatch Groups A, B, C, D, E, G, H, I in **one tool-use message**. Group F runs after Phase 1 because it depends on `IN_REPO` and `REPO_ROOT`.

### Group A — CLI tools

POSIX `command -v` is single-arg; loop:

```bash
missing_cli=""
for c in git jq claude rtk wt; do
  command -v "$c" >/dev/null 2>&1 || missing_cli="$missing_cli $c"
done
echo "missing:$missing_cli"
```

Required: `git`, `jq` (✗ if missing). Recommended: `claude` (warn if missing). Optional: `rtk`, `wt` (warn).

**Forge CLI** (`gh` for GitHub, `glab` for GitLab — at least one is needed; `/jr-ship`, `/jr-review --pr/--branch`, and `tackle` auto-detect per repo per `shared/forge-detection.md`):

```bash
command -v gh   >/dev/null 2>&1 && echo "gh:yes"   || echo "gh:no"
command -v glab >/dev/null 2>&1 && echo "glab:yes" || echo "glab:no"
```

✗ if BOTH are missing (no forge CLI). Otherwise ✓; if only one is present, note that the other is needed only for that host's repos (`gh`→GitHub, `glab`→GitLab).

Additional probes:
- If `gh` present: `gh auth status 2>&1 | head -3` — warn if not authenticated.
- If `glab` present: `glab auth status 2>&1 | head -3` — warn if not authenticated (needed for GitLab repos).
- If `rtk` present: `rtk --version 2>&1 | grep -E "^rtk " >/dev/null` — warn if it's `reachingforthejack/rtk` (lacks `rtk gain` subcommand).

### Group B — settings.json

Short-circuit if `SETTINGS_PRESENT=no`: emit `✗ settings.json missing` and skip to Group C.

```bash
jq empty ~/.claude/settings.json 2>&1                                                  # parseable
[ -n "$(jq -r '.advisorModel // empty' ~/.claude/settings.json)" ] && echo "set" || echo "missing"
jq -r '.enabledPlugins["worktrunk@worktrunk"] // "missing"' ~/.claude/settings.json
jq -r '.permissions.allow // [] | map(select(. == "Edit(.claude/**)" or . == "Write(.claude/**)")) | length' ~/.claude/settings.json
jq -r '.permissions.defaultMode // "missing"' ~/.claude/settings.json
```

Required: parseable, `advisorModel` set, `permissions.allow` count ≥ 2 (✗ on fail).
Recommended: `worktrunk` plugin enabled (warn).
Preference: `defaultMode = "plan"` (warn if different).

### Group C — skills installed + shared files + tackle/docs (single Bash)

```bash
for f in jr-audit/SKILL.md jr-review/SKILL.md jr-ship/SKILL.md \
         bin/tackle bin/seed-project-memory bin/tackle-top \
         shared/reviewer-boundaries.md shared/untrusted-input-defense.md shared/gitignore-enforcement.md \
         docs/worktree-architecture.md; do
  [ -e ~/.claude/skills/$f ] || echo "MISSING: $f"
done
[ -x ~/.claude/skills/bin/tackle ] || echo "NOT_EXECUTABLE: bin/tackle"
[ -x ~/.claude/skills/bin/seed-project-memory ] || echo "NOT_EXECUTABLE: bin/seed-project-memory"
[ -x ~/.claude/skills/bin/tackle-top ] || echo "NOT_EXECUTABLE: bin/tackle-top"
# Repo-local native agent types jr-reviewer/jr-implementer (replaced the agent-teams plugin dep).
# -e follows the symlink, so a dangling ~/.claude/agents link (target missing) still reports MISSING_AGENT.
for a in jr-reviewer jr-implementer; do
  [ -e ~/.claude/agents/$a.md ] || echo "MISSING_AGENT: ~/.claude/agents/$a.md"
done
# jr-reviewer must stay read-only: no Write/Edit tools (/jr-i18n's no-write rests on this). A native
# subagent with NO tools: line inherits ALL tools (incl. Write/Edit), so a missing tools: line must FAIL,
# not pass silently. Scan only the YAML frontmatter (between the first two `---`) so a body mention of
# "Write/Edit" can't false-fire; catch the inline `tools: …` form and a YAML `- Write`/`- Edit` list item.
if [ -e ~/.claude/agents/jr-reviewer.md ]; then
  fm=$(awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f' ~/.claude/agents/jr-reviewer.md)
  if ! printf '%s\n' "$fm" | grep -qE '^tools:'; then
    echo "AGENT_NOT_READONLY: jr-reviewer has no 'tools:' line (a subagent with no tools list inherits ALL tools, incl. Write/Edit)"
  elif printf '%s\n' "$fm" | grep -qE '^tools:.*(Write|Edit)|^[[:space:]]*-[[:space:]]*(Write|Edit)([[:space:]]|$)'; then
    echo "AGENT_NOT_READONLY: jr-reviewer tools: grants Write/Edit"
  fi
fi
```

Missing jr-audit/jr-review/jr-ship/SKILL.md → ✗. Missing tackle/seed-project-memory/tackle-top/docs → warn (only relevant to tackle workflows). Non-executable bin/* → warn. `MISSING_AGENT` (jr-reviewer/jr-implementer not resolvable at `~/.claude/agents/`) → ✗: the reviewer/implementer swarms in /jr-audit, /jr-review, /jr-i18n, /jr-skill-audit cannot spawn without them; run the README install, then restart Claude Code so the new agents dir is watched. `AGENT_NOT_READONLY` → ✗: jr-reviewer must exclude Write/Edit (/jr-i18n's no-write property depends on it).

### Group D — shared file smoke-parse (canonical-driven)

Source of truth: `~/.claude/skills/shared/phase1-track-a-protocol.md` (the same file `/jr-audit`, `/jr-review`, and `/jr-skill-audit` consume at Phase 1 Track A). /jr-doctor reads the canonical's anchor table at runtime — there is no /doctor-side copy.

Procedure:
1. **Self-reference escape hatch (hardcoded)**: Read `~/.claude/skills/shared/phase1-track-a-protocol.md`. If the Read fails (file missing or unreadable), report `✗ shared/phase1-track-a-protocol.md is missing — Group D cannot run` and skip the rest of Group D. Otherwise verify it contains the literal string `Canonical Anchor Table` (case-sensitive); if absent, report `✗ shared/phase1-track-a-protocol.md is corrupted (missing 'Canonical Anchor Table')` and skip the rest of Group D — the table cannot be trusted to drive any other check.
2. **Parse the Canonical Anchor Table** from the file just read. The table has two columns (`File`, `Required substrings`); each `Required substrings` cell contains one or more anchors AND-joined by the literal token ` AND ` (surrounded by spaces) and rendered as inline-code spans.
2a. **Membership cross-check (independence from canonical content)**: glob `~/.claude/skills/shared/*.md` and verify every file in the directory has a row in the parsed table. Any file present in the directory but absent from the table is reported as `✗ shared/<file> exists but has no row in phase1-track-a-protocol.md Canonical Anchor Table` — this catches a corrupted canonical whose own table has been reduced to a stub (the table-driven verification in step 4 would otherwise pass green because there are no untruthful rows, only missing ones).
3. **Read every file listed in the table in parallel** via the `Read` tool (single tool-use message), under `~/.claude/skills/shared/`. The table covers all shared files including `phase1-track-a-protocol.md` itself, so coverage is uniform across the directory.
4. **Verify each row**: for every (file, anchor) pair, the anchor substring must appear verbatim in the file (case-sensitive, fixed-string match — equivalent to `grep -F`).

On smoke-parse failure: emit `✗ shared/<file> smoke-parse failed: missing '<substring>'` with hint `cd ~/.claude/skills && git checkout shared/<file>`. /jr-doctor REPORTS the failure but does NOT abort (unlike /jr-audit and /jr-review which hard-fail).

### Group E — hooks + memory dir (single Bash)

```bash
for h in no-claude-attribution cbm-code-discovery-gate cbm-session-reminder; do
  [ -x ~/.claude/hooks/$h ] || echo "MISSING: $h"
done
[ -d ~/.claude/projects ] || echo "MISSING: ~/.claude/projects"
```

Verify hooks are wired in `settings.json`. Use `jq -r` + stdout-empty checks (NOT `jq -e`, which exits non-zero on no-match and would abort the batched call):

```bash
[ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Bash")) | .hooks[].command | select(. == "rtk hook claude")' ~/.claude/settings.json)" ] || echo "NOT_WIRED: rtk hook claude"
[ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Bash")) | .hooks[].command | select(. == "~/.claude/hooks/no-claude-attribution")' ~/.claude/settings.json)" ] || echo "NOT_WIRED: no-claude-attribution"
[ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Read")) | .hooks[].command | select(. == "~/.claude/hooks/cbm-code-discovery-gate")' ~/.claude/settings.json)" ] || echo "NOT_WIRED: cbm-code-discovery-gate"
[ -n "$(jq -r '.hooks.SessionStart[]? | .hooks[].command | select(. == "~/.claude/hooks/cbm-session-reminder")' ~/.claude/settings.json)" ] || echo "NOT_WIRED: cbm-session-reminder"
```

The `?` after `[]` suppresses jq errors when an array is missing entirely. All wiring checks are warn-only — missing wiring degrades the user's setup but doesn't block /jr-audit/jr-review/jr-ship.

### Group F — per-repo checks (skipped if `IN_REPO=no`)

If not in a repo: emit one line `Not in a git repo — skipping per-repo checks` and skip Group F.

```bash
[ -f "$REPO_ROOT/CLAUDE.md" ]                                                          # required for /jr-audit, /jr-review Phase 1
[ -d "$REPO_ROOT/.claude" ]                                                            # warn — created on first run if missing
[ -f "$REPO_ROOT/.gitignore" ]                                                         # warn — informs --fix
git -C "$REPO_ROOT" remote -v | grep -qE 'github\.com|gitlab\.com'                       # warn — required for /jr-ship and /jr-review --pr/--branch (gh→GitHub, glab→GitLab; forge auto-detected)
```

**Tracked-cache scan** — single batched `git ls-files` for literal paths, separate calls for globs:

```bash
git -C "$REPO_ROOT" ls-files -- \
  .claude/review-profile.json .claude/review-baseline.json .claude/review-config.md \
  .claude/audit-history.json .claude/health.json .claude/secret-warnings.json
git -C "$REPO_ROOT" ls-files -- '.claude/audit-report-*.md'
git -C "$REPO_ROOT" ls-files -- '.claude/secret-warnings-*.json'
git -C "$REPO_ROOT" ls-files -- '.claude/worktrees/'
```

Any non-empty stdout names a tracked cache file → ✗ with hint `git rm --cached <path> && add to .gitignore` (manual; /jr-doctor does NOT auto-untrack).

If `IS_TACKLE_WORKTREE=yes`: suppress the `.claude/worktrees/` warning (worktree files are expected here).

**Gitignore coverage** — if `$REPO_ROOT/.gitignore` exists, read it and check coverage. The canonical pattern set is:

```
.claude/review-profile.json
.claude/review-baseline.json
.claude/review-config.md
.claude/audit-history.json
.claude/health.json
.claude/audit-report-*.md
.claude/secret-warnings.json
.claude/secret-warnings-*.json
.claude/secret-hook-patterns.txt
.claude/secret-warnings*.json.tmp
.claude/secret-warnings*.json.lock
.claude/secret-warnings*.json.corrupt-*
.claude/worktrees/
```

**Intentional duplication** (not drift): this list is deliberately a verbatim copy of the canonical pattern set — the cache-file paths in `shared/gitignore-enforcement.md`'s "Sites that apply this protocol" table PLUS the "Ancillary files" table (transient `.tmp` / `.lock` / `.corrupt-*` artifacts that no skill invokes the per-write protocol on but that still must not be committed). The alternative — having /jr-doctor parse the pattern set out of the shared file's markdown tables at runtime — was considered and **rejected as fragile**: it couples the coverage check to the shared file's exact table layout (cell formatting, the `(glob: ...)` annotation, row order), trading a one-line maintenance note for a brittle parser. Keep the copy; if `/jr-audit` or `/jr-review` adds a new cache file or ancillary artifact, update both shared tables AND this list. Same deliberate-coupling pattern as the inline anchor list in `jr-doctor/scripts/skill-drift-check.sh`.

Coverage is satisfied if EITHER:
- A literal `.claude/` or `.claude/*` line exists (covers everything below `.claude/`), OR
- Each canonical pattern above has a matching gitignore line.

Note: `.claude/secret-warnings*.json` (single line, no dash) covers both `.claude/secret-warnings.json` and `.claude/secret-warnings-*.json`. Treat it as covering both patterns. The `.claude/secret-warnings*.json.tmp`, `.claude/secret-warnings*.json.lock`, and `.claude/secret-warnings*.json.corrupt-*` patterns are NOT covered by `.claude/secret-warnings*.json` — they have a different terminal segment. Each must be present (or covered by a broader `.claude/` rule) independently.

Report missing patterns by name; each missing pattern is a fixable issue (see Phase 4).

### Group G — codebase-memory-mcp probe (best-effort)

```bash
if command -v claude >/dev/null 2>&1; then
  claude mcp list 2>&1 | grep -qE "codebase-memory(-mcp)?" && echo "configured" || echo "not configured"
else
  echo "unable to probe (claude CLI not found)"
fi
```

Always warn-only. Hint when not configured: `Recommended for /jr-audit, /jr-review structural queries; see https://github.com/anthropics/codebase-memory-mcp`.

### Group H — Claude Code runtime (env vars + version)

```bash
echo "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-<unset>}"
echo "CLAUDE_CODE_NO_FLICKER=${CLAUDE_CODE_NO_FLICKER:-<unset>}"
echo "CLAUDECODE=${CLAUDECODE:-<unset>}"

if command -v claude >/dev/null 2>&1; then
  claude --version 2>&1 | head -1
fi

# Optional tunables — print only if explicitly set so the report stays compact
for v in BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS MCP_TIMEOUT MCP_TOOL_TIMEOUT \
         MAX_THINKING_TOKENS MAX_MCP_OUTPUT_TOKENS CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY \
         DISABLE_TELEMETRY DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
  val=$(printenv "$v" 2>/dev/null) && [ -n "$val" ] && echo "TUNABLE: $v=$val"
done
```

**Rendering rule** (lead applies to the printed `TUNABLE:` lines):
- If 0 `TUNABLE:` lines → emit `ℹ Optional tunables       (all defaults)` + the inline teaser block.
- If ≥1 `TUNABLE:` lines → emit `ℹ Optional tunables       (N set)` followed by the values, indented 4 spaces.
- The teaser block (BASH_MAX_TIMEOUT_MS / MCP_TIMEOUT suggestions) appears AFTER the printed lines if EITHER of those two specific vars is still unset — so a user with `MAX_THINKING_TOKENS=20000` but no BASH/MCP overrides still gets the suggestion. Drop a suggestion from the teaser the moment its var is set.

**`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`** — Informational. Formerly REQUIRED when the reviewer/implementer swarms depended on the `agent-teams` plugin; they now use repo-local native `.claude/agents/` types (`jr-reviewer`/`jr-implementer`), which are a stable feature and need no flag. Work-producing subagents are still spawned **without `name:`** per `~/.claude/skills/shared/subagent-reporting.md` "Spawn rule"; do not describe them as named teammates, which is the model that lost findings silently in issue #70. No longer gates any skill; reported for information only.

**`CLAUDE_CODE_NO_FLICKER`** — Recommended `=1` UI preference (cleaner output, no terminal redraw flicker). Hint: `export CLAUDE_CODE_NO_FLICKER=1`. ⚠ if unset.

**`CLAUDECODE` / `CLAUDE_CODE_ENTRYPOINT`** — Set automatically by Claude Code when the skill runs from inside a Claude Code session. Informational only; useful in the report header.

**`claude --version`** — Reports the installed CLI version. Informational. If `claude` is not on PATH, this falls through to Group A's `MISSING: claude` finding. **Minimum-version check** is intentionally not enforced: there is no published "skills compatibility floor" for these skills today, so /jr-doctor reports the version and lets the user judge. If a future version introduces a breaking change to a skill's required APIs, document the floor in that skill's HTML comment block and have /jr-doctor parse the version against it.

#### Optional tunables (informational only — never graded)

The Group H probe Bash + rendering rule above surface these env vars on the report only when explicitly set. The full reference table — every tunable, its default, and when raising it helps — lives in `examples.md` ("Optional tunables reference"). It is pure informational reference (no probe or rendering logic depends on it), moved out of `SKILL.md` to keep always-loaded context lean. For the full Claude Code env-var reference, see https://code.claude.com/docs/en/env-vars.

### Group I — Skill drift checks (per skill in `~/.claude/skills/`)

Yes/no factual drift only — every check below is derivable from a file read. **No opinion-style coaching** (e.g. "should use advisor more", "description is too verbose"). Recommendations belong in `claude-automation-recommender`; /jr-doctor stays diagnostic.

Iterate every `~/.claude/skills/*/SKILL.md` (skip directories without a `SKILL.md` such as `bin/`, `docs/`, `shared/`). `doctor`'s own `SKILL.md` IS included — the line/frontmatter/drift checks are still meaningful for it, and excluding self would silently mask self-drift.

Run the bundled drift script and parse the marker lines on stdout:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/skill-drift-check.sh" 2>&1
```

The script implements all seven checks (line count, broken shared refs, frontmatter contradictions, inline drift, template hash, refs cache freshness, abortReason enum drift) and emits one marker line per finding. See `scripts/skill-drift-check.sh` directly for the implementation; the marker contract below is what /jr-doctor parses.

#### Marker semantics

| Marker | Status | Meaning | Hint |
|---|---|---|---|
| `WARN_LINES:<skill>:<n>` | ⚠ | SKILL.md exceeds Anthropic's 500-line guideline (https://code.claude.com/docs/en/skills). Large skills cost tokens for the rest of the session after invocation. | Extract phases to `<skill>/scripts/*.sh` or move shared content to `~/.claude/skills/shared/*.md`. Refer to `/jr-review`'s extraction history (commits introducing `shared/*.md`, `jr-review/scripts/*.sh`, `jr-review/convergence-protocol.md`) as a worked example. |
| `FAIL_BROKEN_REF:<skill>:<ref>` | ✗ | SKILL.md references a non-existent shared file. /jr-audit and /jr-review hard-fail at Phase 1 Track A on this; /jr-doctor catches it earlier. | `cd ~/.claude/skills && git status shared/` to find the missing or renamed file. |
| `WARN_DMI_INERT:<skill>` | ⚠ | `disable-model-invocation: true` makes `when_to_use:` and `paths:` inert (description is not loaded into context per https://code.claude.com/docs/en/skills). | Either remove the inert field or set `disable-model-invocation: false`. |
| `FAIL_EFFORT:<skill>:<value>` | ✗ | `effort:` value is not in the allowlist (`low|medium|high|xhigh|max`). Claude Code rejects the skill at load time. | Pick a valid value. |
| `WARN_MODEL:<skill>:<value>` | ⚠ | `model:` value not in the known allowlist. May be a typo OR a model added after this allowlist was last updated. | If the value is a real model alias, update the regex in /jr-doctor's Group I. Otherwise correct the typo. |
| `FAIL_NO_DESC:<skill>` | ✗ | Frontmatter is missing the required `description:` field. | Add a `description:` line. |
| `WARN_INLINE_DRIFT:<skill>:<file>` | ⚠ | A canonical Group D smoke-parse anchor appears inline AND the corresponding `shared/<file>` reference is absent. Drift risk: future edits to the shared file won't propagate. | Add a `../shared/<file>` reference at the call site. |
| `FAIL_TEMPLATE_HASH:expected=<x>:actual=<y>` | ✗ | `jr-review/templates/pre-commit-secret-guard.sh.tmpl` hash differs from `EXPECTED_TEMPLATE_SHA256` in the install script. The install path will abort with exit 2 until reconciled. | If the template change is intentional, update `EXPECTED_TEMPLATE_SHA256` in `jr-review/scripts/install-pre-commit-secret-guard.sh` per its 4-step maintenance contract. Otherwise restore the template from git. |
| `WARN_REFS_CACHE_MISSING` | ⚠ | `jr-skill-audit/cache/refs.json` not found. `feature-adoption-reviewer` will skip on next `/jr-skill-audit` run unless the cache is built. | Run `/jr-skill-audit --refresh-refs` once to populate the cache. |
| `WARN_REFS_CACHE_NO_TIMESTAMP` | ⚠ | `jr-skill-audit/cache/refs.json` is present but missing the `fetchedAt` field. Likely manual edit or corruption. | Run `/jr-skill-audit --refresh-refs` to rewrite. |
| `WARN_REFS_CACHE_STALE:<fetched>:<age_days>` | ⚠ | Cache is older than 30 days; live Anthropic docs/changelog have probably moved on. `feature-adoption-reviewer` findings will be tagged `[Source: cached YYYY-MM-DD]`. | Run `/jr-skill-audit --refresh-refs` to refresh. |
| `FAIL_ABORT_REASON_ORPHAN:<value>:<file>:<line>` | ✗ | A skill sets `abortReason="<value>"` that is not declared in `shared/abort-markers.md`'s mapping table. At runtime it falls through the `case` to `[ABORT — UNLABELED]` — a contract violation surfaced only after the fact. | Fix the typo, or add the value's row to the mapping table (the script and table are co-authored). |
| `FAIL_ABORT_MARKERS_TABLE_EMPTY` | ✗ | `shared/abort-markers.md` exists but its `## Reason → Marker mapping` table yielded no values — stubbed or truncated. The enum check cannot run. | Restore `shared/abort-markers.md` from git. |
| `FAIL_ABORT_REASON_EXTRACTION_EMPTY` | ✗ | No `abortReason="..."` setter was found in any skill though the enum is in active use — the extraction regex is broken, not the repo. Emitted so a silently-matching-nothing check fails loudly instead of certifying clean. | Inspect the abortReason extraction in `scripts/skill-drift-check.sh` (check 7). |

#### Display rollup

- Render one rollup line: `Skill drift (X/Y)` where Y is the number of skills iterated and X is the number passing all 5 per-skill checks. The two one-shot checks (template hash, refs cache) render as their own rows below the rollup — green inline (`✓ Template hash`, `✓ Refs cache`) or expanded with a hint on warning/failure.
- On any warning/failure, expand inline with the skill name + first failing check per skill (4-space indent), matching the existing `Group D` and `Group F` expansion style.
- All findings are warn or fail — **never auto-fixable**. /jr-doctor reports; humans refactor (or run `/jr-skill-audit --refresh-refs` for the refs-cache case).

Group results and print using the format below. Each group prints a single line on full pass; expand inline on any `⚠`/`✗`.

### Sections

1. **Global setup** — Groups A, B, C, D, E, I (everything outside the current repo, including skill drift checks).
2. **Claude Code runtime** — Group H (env vars + claude version).
3. **Current repo (<REPO_ROOT>)** — Group F (skipped if `IN_REPO=no`).
4. **Optional integrations** — Group G + any other warn-only items.
5. **Summary line** — `Summary: N ✓  M ⚠  K ✗   Total: <elapsed>`.

### Mocks

See `examples.md` for the full-pass mock and variations (fresh `git init` directory, smoke-parse failure, skill-drift warning, skill-drift failure).

## Phase 4 — `--fix` flow (only if `--fix` AND ≥1 fixable issue)

**Fixable scope**: exactly one class — append/create lines in `<REPO_ROOT>/.gitignore`.

**Not auto-fixable** (hint only, never modified by /jr-doctor):
- `~/.claude/settings.json` (any key)
- Tracked cache files (`git rm --cached` is destructive — user judgment)
- Plugin enablement
- CLI tool / MCP installation
- Hook files (user-authored)

### Fix flow (per fixable issue)

For each missing canonical pattern in `<REPO_ROOT>/.gitignore`:

1. Render proposed change: file path + exact line being appended.
2. In non-headless mode: `AskUserQuestion` with options `[Apply] | [Skip] | [Apply all remaining and stop asking]`.
3. With `--yes` (or after the user picks "Apply all remaining"): skip prompts, apply directly, log each one.
4. Apply: re-read `<REPO_ROOT>/.gitignore` (concurrent-write safety), then `printf '%s\n' "<line>" >> "$REPO_ROOT/.gitignore"`. If `.gitignore` doesn't exist, create it with the missing lines.
5. After all fixable issues are resolved, re-run only the gitignore-coverage check from Group F and emit `✓ Gitignore coverage` (or list any remaining gaps).

**Race-safety**: re-read `.gitignore` immediately before each append. `flock` is overkill for a low-effort skill; concurrent /jr-doctor invocations against the same repo may produce duplicate lines, which is harmless.

**Plan-mode interaction**: when `defaultMode: "plan"` is set, each `printf >>` will queue for user approval through the harness. Communicate this to the user up front.

### Fix-pass summary

After the fix loop, print a final summary:

```
Phase 4 — Fix pass
  ✓ Applied 9 / 9 fixable changes to /tmp/doctor-test/.gitignore
    + .claude/review-profile.json
    + .claude/review-baseline.json
    + .claude/review-config.md
    + .claude/audit-history.json
    + .claude/health.json
    + .claude/audit-report-*.md
    + .claude/secret-warnings*.json
    + .claude/secret-hook-patterns.txt
    + .claude/secret-warnings*.json.tmp
    + .claude/secret-warnings*.json.lock
    + .claude/secret-warnings*.json.corrupt-*
    + .claude/worktrees/

Re-check: ✓ Gitignore coverage
```

## Edge cases

| Case | Behavior |
|---|---|
| Not a git repo | Skip Group F. Print banner. Exit 0 if global setup passes. |
| `~/.claude/settings.json` missing | `✗ settings.json missing`. Skip Group B sub-checks. Other groups proceed. |
| `jq` missing | Group B → `?` (unknown). Hint: `brew install jq`. |
| `claude` CLI missing | Group G → `unable to probe`. Group H → `claude --version` line omitted. |
| Inside tackle worktree | Banner + suppress `.claude/worktrees/` tracking warning (worktree files are expected). |
| Inside scratch session | Banner: `Inside tackle scratch session (id=...)`. No check changes. |
| Headless | `--fix` auto-disabled with warning unless `--yes`. |
| `.gitignore` missing | Treat as fixable (`--fix` creates it). |
| `jr-reviewer`/`jr-implementer` not resolvable at `~/.claude/agents/` | `✗` (Group C `MISSING_AGENT`). The reviewer/implementer swarms cannot spawn. Hint: run the README install (`mkdir -p ~/.claude/agents && ln -sf ~/.claude/skills/.claude/agents/jr-reviewer.md ~/.claude/agents/`, same for `jr-implementer.md`), then restart Claude Code so the new agents dir is watched. |
| `CLAUDE_CODE_NO_FLICKER` unset/≠1 | `⚠ Recommended env vars`. Hint: `export CLAUDE_CODE_NO_FLICKER=1`. Non-blocking; UI preference only. |
| Optional tunables all unset | `ℹ Optional tunables (all defaults)` plus a 2-3-line inline suggestion of the most-likely-relevant ones (BASH_MAX_TIMEOUT_MS, MCP_TIMEOUT). Never blocks. |
| Doctor's own SKILL.md | Group C existence check skipped — if running, it exists. Group I (skill drift) DOES include doctor — line/frontmatter/inline-drift checks remain meaningful for doctor itself. |
