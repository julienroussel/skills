---
name: jr-doctor
description: Health-check the user's Claude Code setup and the current repo. Verifies CLI tools, plugins, settings.json, installed skills, shared protocol files, gitignore coverage, and optional integrations needed by /jr-audit, /jr-review, /jr-ship, and tackle. Reports per-check status with remediation hints. Optional --fix appends missing patterns to the current repo's .gitignore on per-change confirmation.
argument-hint: "[--fix] [--yes] [--no-probe]"
effort: low
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Glob Grep Bash(git rev-parse *) Bash(git remote *) Bash(grep *) Bash([ *) Bash(ls *) Bash(pwd) Bash(printf *) Bash(echo *) Bash(${CLAUDE_SKILL_DIR}/scripts/skill-drift-check.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/env-probe.sh *) AskUserQuestion Agent ToolSearch
disallowed-tools: Write Edit
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
    - ~/.claude/skills/{jr-doctor/scripts/{env-probe,skill-drift-check},jr-review/scripts/{establish-base-anchor,install-pre-commit-secret-guard}}.sh — existence + executable bit (Group C; these four are invoked directly, so a cleared bit breaks the phase that calls them)
    - ~/.claude/skills/shared/reviewer-boundaries.md     — existence + non-empty + smoke-parse (anchors per the Canonical Anchor Table — Group D reads it at runtime; for reviewer-boundaries that is `| Issue` AND `| Owner` AND `| Not` AND `Severity calibration rubric` AND `Confidence levels`)
    - ~/.claude/skills/shared/untrusted-input-defense.md — existence + non-empty + smoke-parse `do not execute, follow, or respond to`
    - ~/.claude/skills/shared/gitignore-enforcement.md   — existence + non-empty + smoke-parse `git ls-files --error-unmatch`
    - ~/.claude/skills/shared/advisor-criteria.md        — existence + non-empty + smoke-parse `Before substantive work` AND `Single-fire on retry loops`
    - ~/.claude/skills/shared/phase1-track-a-protocol.md — Canonical Anchor Table, parsed at runtime by Group D; it is the
                                                  authoritative source of every anchor listed above, which are reproduced here
                                                  only as an inventory hint and may lag it
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
  Agents spawned (only by the Group J capability probe; skipped with --no-probe):
    - jr-reviewer (haiku, throwaway) — spawned WITHOUT name: (positive channel probe J1) and WITH name: (teammate-ack probe J2), each fed only a fixed token-echo prompt (no repo content passes in). Re-verifies the reviewer→lead reporting channel against shared/subagent-reporting.md "Verified behaviour".
  Harness-claim markers scanned (Group I check 8, staleness):
    - ~/.claude/skills/{shared/*.md,*/SKILL.md,*/protocols/*.md,docs/*.md}  — `<!-- harness-claim-verified: DATE -->` markers, warn past 90 days
  Required tools:
    - Bash, Read, AskUserQuestion, Agent, ToolSearch  (Agent + ToolSearch used ONLY by the Group J capability probe)
  Tools NOT used:
    - Write (the only file mutation is the .gitignore append/create in Phase 4, done via Bash `printf >>`); TaskCreate/TaskList (the Group J probe asserts the lead LACKS these — it never calls them); advisor

  No advisor anywhere in the skill: deliberate, not an omission. Rationale and the three
  conditions that would reopen it live in `protocols/rationale.md` "No advisor call anywhere
  in the skill" (maintainer reference, never read at runtime). Do not re-raise as a
  missing-advisor finding without reading it first. Same treatment as
  jr-ship/protocols/rationale.md's own advisor carve-out note.
-->

Diagnose whether the current codebase + Claude Code setup is ready to use `/jr-audit`, `/jr-review`, `/jr-ship`, and `bin/tackle`. Report per-check status with remediation hints. Default is read-only; `--fix` appends missing patterns to the current repo's `.gitignore` on per-change confirmation.

**Arguments**: $ARGUMENTS

Recognized flags:
- `--fix` — Apply safe fixes (append/create the current repo's `.gitignore`) on per-change confirmation. Never modifies `~/.claude/settings.json`. Never untracks files. Never installs anything.
- `--yes` — With `--fix`, skip per-change prompts and apply all fixable changes. Without `--fix`, ignored with a warning.
- `--no-probe` — Skip the Group J capability probe (the reviewer→lead channel spawn checks). The rest of /jr-doctor is unaffected. Use in fast/offline runs; otherwise the probe runs by default (two throwaway haiku agents issued in one message, ~5-10s).

**Examples**: `/jr-doctor`, `/jr-doctor --fix`, `/jr-doctor --fix --yes`, `/jr-doctor --no-probe`

**Plan-mode note**: when `defaultMode: "plan"` is set in `~/.claude/settings.json`, each `.gitignore` write under `--fix` will trip the standard plan-mode permission prompt. Expect serial approval prompts; the harness handles them — this is not a /jr-doctor bug.

**First-run note**: `allowed-tools` grants exactly the Bash commands this body still issues, one grant per site: `git rev-parse` and `ls` (Phase 1 repo/scratch probe), `git remote -v` piped to `grep` (Phase 1 `HAS_REMOTE`), `[` and `echo` (Phase 1 presence tests and the headless predicate), `pwd` (Phase 1 `CWD`), `printf` (the Phase 4 `.gitignore` append), and the two bundled scripts. **Everything a script runs internally needs no grant of its own**: `${CLAUDE_SKILL_DIR}/scripts/env-probe.sh` is one Bash invocation whatever `jq`, `awk`, `git ls-files`, `gh auth status`, `claude mcp list` or `printenv` it calls inside. The grants for those were left behind when the probes moved into `scripts/`, and `Bash(awk *)` in particular is arbitrary file-write and command execution, so they are removed rather than kept "just in case" on a publicly installable skill. Any command that still prompts is a genuine grant gap worth fixing rather than accepting. /jr-doctor itself does NOT modify `permissions.allow` (out of scope).

## Display protocol

- **Phase headers** use prominent `━━━` separators, matching `/jr-audit` / `/jr-review` style.
- **Single-line groups on full pass**, expanded only on `⚠`/`✗`. Keep happy-path output ≤ 30 lines.
- **Indents**: 2 spaces for groups, 4 spaces for expanded checks.
- **Status markers**: `✓` (pass), `⚠` (warn — informational, non-blocking), `✗` (fail — required item missing).
- **Never echo `advisorModel` value** to keep transcript logs clean. Report `set` / `missing` only.
- **Collapse `$HOME` to `~` in every path you print**, wherever it came from: the report header, a repo root, a marker detail (`REPO:`, `GITIGNORE_ABSENT:`, `REPO_QUERY_FAILED:`), a remediation hint. `scripts/env-probe.sh` emits absolute paths because `--fix` needs them; the tilde form is a rendering rule the lead applies. An absolute path under a home directory names its owner, and the mocks in `examples.md` have always shown the collapsed form.
- **Final summary**: `Summary: N ✓  M ⚠  K ✗   Total: <elapsed>`.

## Phase 1 — Argument parsing + environment probe

### Argument parsing

Parse `\$ARGUMENTS` as space-separated tokens. Accept only `--fix`, `--yes`, and `--no-probe`; warn and ignore unknown tokens. The Group J capability probe runs by default; `--no-probe` disables it.

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

**Note** (canonical: `../shared/secret-scan-protocols.md` "Headless/CI detection"): this is a deliberate **re-expansion** of a predicate that canonical forbids re-expanding at individual sites ("Defined once here and referenced by name elsewhere"). The carve-out is that `/jr-doctor` never Reads that file — Group D only smoke-parses it — so it needs an executable copy rather than a reference. The copy is therefore **drift-prone by construction**: the eleven environment variables below must stay identical to the canonical's list, and a CI variable added there would otherwise never reach this skill (symptom: `--fix` prompting instead of auto-disabling in an unrecognised CI). Group I check #14 now diffs the two lists mechanically so the divergence cannot go unnoticed. This predicate has no `[ ! -t 0 ]` (no-TTY) term, and **neither does the canonical any more**. `/jr-doctor` dropped it first, because the Claude Code Bash tool runs subprocesses without a TTY, so the test always fires and would incorrectly auto-disable `--fix` in normal interactive use. That reasoning held for every consumer, not just this one, and `../shared/secret-scan-protocols.md` ("There is deliberately no tty condition") now carries it: CI environment variables plus the explicit non-interactive flag are the authoritative signals. This predicate and the canonical are therefore aligned, not divergent — do not re-add the term to either.

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

**Groups A, B, C, E, F, G and H are one script call.** Run:

```bash
${CLAUDE_SKILL_DIR}/scripts/env-probe.sh <REPO_ROOT|none> <yes|no>
```

**Substitute the two literal values you derived in Phase 1**, e.g. `env-probe.sh ~/some/repo no`. Do NOT write `"$REPO_ROOT"` / `"$IS_TACKLE_WORKTREE"`: each Bash call is a fresh shell, so those variables are empty here and the probe would see no arguments at all. When `IN_REPO=no`, pass the **literal `none`** as the first argument, which is what makes a genuine "not in a git repo" distinguishable from an argument that failed to arrive (the latter emits `REPO: unknown` plus `PROBE_ARGS:`, and Group F's ✗-severity checks are withheld rather than silently skipped).

The script prints `GROUP: <letter>` separators followed by `MARKER: detail` lines, the same report-facts / lead-grades contract as `scripts/skill-drift-check.sh` (Group I). **The script never grades**: every ✓/⚠/✗ below is the lead's, and a condition that passes emits no marker at all — absence is the pass. Marker meanings and hints are tabulated in `${CLAUDE_SKILL_DIR}/examples.md` "Marker semantics"; read it only when a marker actually fires.

**Completeness precondition (check before grading anything).** Absence-is-the-pass is only sound on a run that finished, so the probe's last line is `PROBE_COMPLETE: ok`. If the invocation errors (script missing, exec bit cleared, permission denied) or the output does not contain `PROBE_COMPLETE:`, the run was truncated: report `✗ Environment probe incomplete: Groups A/B/C/E/F/G/H not graded` with the invocation error or last marker seen, and grade **none** of those seven groups. Any marker that did arrive may still be reported as a finding; what is forbidden is reading silence as a pass. This is also the only cover for `env-probe.sh` losing its own executable bit, which its Group C check cannot report from inside itself.

- `PROBE_ARGS: <detail>` → **✗** (caller bug, not an environment fault). The lead built the invocation wrongly; re-issue with the two literals. A `bad worktree flag` detail additionally means `.claude/worktrees/` entries below are reported unsuppressed, so do not grade them until the flag is right.

Dispatch that single call together with Group D (a `Read`-tool check, not Bash) and Group I in **one tool-use message**. Group J (capability probe) runs after Phase 1 as its own step — it issues `Agent`/`ToolSearch` calls — and is skipped when `--no-probe` is set.

The groups below give the **grading rules only**. The probes themselves moved into the script (the skills doc designates `scripts/` as "executed, not loaded" precisely so probe bodies stop costing context on every session); Group I already proved the pattern.

### Group A — CLI tools

- `CLI_MISSING: git` or `CLI_MISSING: jq` → **✗** (required).
- `CLI_MISSING: claude` → **⚠** (recommended). `CLI_MISSING: rtk` / `wt` → **⚠** (optional).
- `FORGE_CLI: gh=no glab=no` → **✗** (no forge CLI).
- **Join `FORGE_CLI:` with Group F's `REPO_REMOTE:` before grading either one.** Neither is decidable alone: which CLI a run needs is a property of the repo's host, and one-CLI-present is fine or fatal depending on it.
  - `REPO_REMOTE: github` with `gh=no` → **✗** (`/jr-ship`, `/jr-review --pr/--branch` and `tackle` cannot run here). Symmetrically `REPO_REMOTE: gitlab` with `glab=no` → **✗**.
  - `REPO_REMOTE: github` with `gh=yes` → **✓**; a missing `glab` is a note, not a finding, and vice versa.
  - No `REPO_REMOTE:` line at all (not in a repo, or `REPO: unknown`/`REPO_QUERY_FAILED:`) → **✓ with a note** naming which CLI is absent. There is no repo to decide against, so do not escalate.
- `GH_AUTH: failed` / `GLAB_AUTH: failed` → **⚠** not authenticated, escalating to **✗** when `REPO_REMOTE:` names that CLI's host. `GH_AUTH: absent` / `GLAB_AUTH: absent` restate `FORGE_CLI:` and are graded through the join above, never waived on their own: the `CLI_MISSING:` loop covers `git jq claude rtk wt` and has never checked `gh` or `glab`.
- `RTK_VARIANT: unknown` → **⚠** likely `reachingforthejack/rtk`, which lacks the `rtk gain` subcommand.

### Group B — settings.json

- `SETTINGS: absent` → **✗** settings.json missing. `SETTINGS: unparseable` → **✗**. `SETTINGS: no-jq` → **?** unknown, NOT a fault of the file: `jq` is not on `PATH`, so nothing about settings.json was read. Hint: `brew install jq`; Group A already reports `CLI_MISSING: jq`. On all three paths the script emits none of the fields below and a `HOOK_WIRING: unchecked` marker in place of the four hook probes — it will not grade a file it could not read, so do NOT report hooks as unwired on any of them.
- `ADVISOR_MODEL: missing` → **✗** (required).
- `PERM_MISSING: <rule>` → **✗**, one marker per missing rule, naming it. Both `Edit(.claude/**)` and `Write(.claude/**)` are required; each is tested for independently, so two copies of one rule can no longer stand in for the pair.
- `PLUGIN_WORKTRUNK: missing` → **⚠** (recommended).
- `DEFAULT_MODE:` anything other than `plan` → **⚠** (preference).

### Group C — skills installed + shared files + tackle/docs (single Bash)

- `FILE_MISSING: jr-audit/SKILL.md` / `jr-review/SKILL.md` / `jr-ship/SKILL.md` → **✗**.
- `FILE_MISSING:` for `bin/tackle`, `bin/seed-project-memory`, `bin/tackle-top`, `docs/worktree-architecture.md` or any `shared/*` → **⚠** (only relevant to tackle workflows).
- `NOT_EXECUTABLE: bin/*` → **⚠**.
- `FILE_MISSING:` or `NOT_EXECUTABLE:` for any `<skill>/scripts/*.sh` → **✗** with hint `chmod +x ~/.claude/skills/<path>`. These four are invoked **directly**, not through an interpreter, so a cleared bit takes out the phase that calls them: `jr-doctor/scripts/env-probe.sh` (Groups A/B/C/E/F/G/H), `jr-doctor/scripts/skill-drift-check.sh` (Group I), `jr-review/scripts/establish-base-anchor.sh` (Phase 5 base anchor) and `jr-review/scripts/install-pre-commit-secret-guard.sh` (Phase 5.6). `env-probe.sh` cannot report its own cleared bit; that case surfaces as the failed invocation covered by the completeness precondition above.
- `MISSING_AGENT:` (jr-reviewer/jr-implementer not resolvable at `~/.claude/agents/`) → **✗**: the reviewer/implementer swarms in /jr-audit, /jr-review, /jr-i18n, /jr-skill-audit cannot spawn without them. Hint: run the README install, then restart Claude Code so the new agents dir is watched. The probe uses `-e`, which follows symlinks, so a dangling `~/.claude/agents` link still reports missing.
- `AGENT_NOT_READONLY:` → **✗**: jr-reviewer must exclude Write/Edit (/jr-i18n's no-write property depends on it). Two distinct causes, both fatal — **no `tools:` line at all** (a native subagent without one inherits ALL tools including Write/Edit, so silence must fail, not pass) and **`tools:` granting a file-writing tool**, which the marker names: `Write`, `Edit`, `MultiEdit` or `NotebookEdit`, in the inline, YAML-list or flow-sequence form. The probe scans only the frontmatter, so a body mention of "Write/Edit" cannot false-fire, and it compares whole tool names, so `TodoWrite` (a built-in that writes no repo file) does not either.

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

- `HOOK_MISSING: <name>` (hook absent or not executable at `~/.claude/hooks/`) → **⚠**.
- `PROJECTS_DIR_MISSING:` → **⚠**.
- `HOOK_NOT_WIRED: <name>` → **⚠**. All wiring checks are warn-only — missing wiring degrades the setup but doesn't block /jr-audit, /jr-review or /jr-ship.
- `HOOK_WIRING: unchecked` → **?** unknown, and it **suppresses the whole `Hooks wired` row**: render `? Hooks wired (not checked, see Group B)` and never `✓ Hooks wired (4/4)`. The four probes did not run, so their silence carries nothing.

The probe uses `jq -r` + stdout-empty checks rather than `jq -e` (which exits non-zero on no-match), and `[]?` to suppress errors when an array is missing entirely. It emits **no** `HOOK_NOT_WIRED:` markers at all when settings.json is absent, unparseable, or unreadable for want of `jq` — Group B already graded that, and reporting four unwired hooks off an unreadable file would be four false findings. The three states the report must keep apart are **wired** (no marker of either kind), **not wired** (`HOOK_NOT_WIRED:`) and **not checked** (`HOOK_WIRING: unchecked`); collapsing the third into the first is what made an unreadable settings.json certify 4/4.

### Group F — per-repo checks (skipped if `IN_REPO=no`)

If not in a repo: emit one line `Not in a git repo — skipping per-repo checks` and skip Group F.

The script emits exactly one `REPO:` line, and it says which of three things happened. `REPO: none` is a genuine skip (the lead passed the literal `none`). `REPO: <path>` runs the group. `REPO: unknown` means the first argument never arrived: **not** a skip, so report `✗ Repo checks not run: probe called without a repo argument` and re-issue the call rather than rendering the "not in a git repo" banner.

- `REPO_MISSING: CLAUDE.md` → **✗** (required for /jr-audit and /jr-review Phase 1). `REPO_MISSING: .claude` → **⚠** (created on first run). `REPO_MISSING: .gitignore` → **⚠** (informs `--fix`).
- `REPO_REMOTE: github` / `gitlab` → the repo's forge host; grade it jointly with Group A's `FORGE_CLI:` per the join stated there. `REPO_REMOTE: none` → **⚠** — a `github.com`/`gitlab.com` remote is required for /jr-ship and /jr-review `--pr`/`--branch`.
- `REPO_QUERY_FAILED: <detail>` → **✗** `Repo checks could not run`. It **invalidates every git-derived Group F fact**, not just the one that failed: `REPO_REMOTE:`, `TRACKED_CACHE:`, `GITIGNORE_ABSENT:` and `GITIGNORE_MISSING_PATTERN:` are all suppressed, partial or meaningless after it, so never render `✓ Gitignore coverage`, a clean tracked-cache row, or the Group A forge join on a run that emitted it. Usually a `REPO_ROOT` that is not a git work tree.
- `TRACKED_CACHE: <path>` → **✗** with hint `git rm --cached <path> && add to .gitignore`. Manual: /jr-doctor does NOT auto-untrack. Pass `yes` as the script's second argument inside a tackle worktree — it then suppresses `.claude/worktrees/` entries, which are expected there.
- `GITIGNORE_ABSENT: <path>` → **⚠**, and no per-pattern markers follow (one finding, not thirteen).
- `GITIGNORE_MISSING_PATTERN: <pattern>` → each is a **fixable issue** (see Phase 4). Report by name. Absence of all thirteen (on a run with no `REPO_QUERY_FAILED:`) is `✓ Gitignore coverage`, however the repo spells its rules.

**Where the canonical pattern list lives.** The thirteen patterns are in `scripts/env-probe.sh` (Group F), a deliberate verbatim copy of the canonical set — the "Sites that apply this protocol" table in `shared/gitignore-enforcement.md` plus its "Ancillary files" table. Runtime parsing of those tables was considered and rejected as fragile. **When /jr-audit or /jr-review adds a cache file or ancillary artifact, update both shared tables AND the list in the script.**

**How coverage is decided.** Per pattern, by `git check-ignore` on a concrete path that pattern must match, not by matching lines in `.gitignore`. git is the only thing that knows all five blanket spellings (`.claude/`, `.claude/*`, `.claude/**`, `/.claude/`, bare `.claude`), that `.claude/secret-warnings*.json` covers the plain and dashed forms but not the `.tmp`/`.lock`/`.corrupt-*` variants, and that a later `!.claude/secret-warnings.json` re-includes that path under `.claude/*`. **In scope** is the repo's own `.gitignore`, the protection a collaborator inherits on clone; `core.excludesFile` is neutralised for the query and `.git/info/exclude` is a known accepted gap, because a rule that lives only on this machine does not stop the next contributor committing the file. So a pattern can be reported missing here while a bare `git check-ignore` in your shell says the path is ignored: that difference is the point, not a bug.

### Group G — codebase-memory-mcp probe (best-effort)

Always warn-only.

- `MCP_CBM: configured` → **✓**.
- `MCP_CBM: not-configured` → **⚠**. Hint: `Recommended for /jr-audit, /jr-review structural queries; see https://github.com/anthropics/codebase-memory-mcp`.
- `MCP_CBM: unprobeable (<reason>)` → **⚠**, quoting the reason. Either the `claude` CLI is not on PATH (Group A already reports that as `CLI_MISSING: claude`) or `claude mcp list` hit its 15s bound.

`claude mcp list` is the script's only network call: it contacts every configured MCP server and can spawn `npx`, measured at 6.6s of an 8.0s run. It is therefore emitted **last**, after Group H, so an unreachable server cannot delay or truncate a group that needs no network, including the `CLAUDE_VERSION:` line the report header wants. It is bounded by `timeout`/`gtimeout` where either exists; base macOS userland ships neither (both come with homebrew coreutils), so on such a machine the call is unbounded and the ordering is the whole mitigation. Group G still renders in report section 4; emission order and report order are independent.

### Group H — Claude Code runtime (env vars + version)

The script emits `ENV: <VAR>=<value>` (or `=<unset>`) for the four named vars (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_NO_FLICKER`, `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`), `CLAUDE_VERSION: <version>` when the `claude` CLI is present, and one `TUNABLE: <VAR>=<value>` line per explicitly-set optional tunable — unset tunables stay silent so the report stays compact.

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
"${CLAUDE_SKILL_DIR}/scripts/skill-drift-check.sh" 2>&1
```

The script implements all fifteen checks (1 line count, 2 broken shared refs, 3 frontmatter contradictions, 4 inline drift, 5 template hash, 6 refs cache freshness, 7 abortReason enum drift, 8 harness-claim staleness, 9 canonical-rule linkage, 10 guard-mode mismatch, 11 malformed harness-claim marker, 12 tail-unguarded protocol file, 13 unresolved canonical pointer, 14 isHeadless env-var drift, 15 jr-ship anchor-table drift) and emits one marker line per finding. See `scripts/skill-drift-check.sh` directly for the implementation; the marker contract below is what /jr-doctor parses.

#### Marker semantics

The full `Marker | Status | Meaning | Hint` table (one row per marker) lives in `${CLAUDE_SKILL_DIR}/examples.md`
under **"Marker semantics"**. Read it **only when `scripts/skill-drift-check.sh` emits at least one
marker line** — a fully-passing run needs none of it, and the table is ~6.5 KB that would otherwise
sit in context for the whole session. Same on-demand rule as the Optional tunables reference above
(`https://code.claude.com/docs/en/skills`, "Skill content lifecycle").

Recognise a marker by shape, not by memorised name: any output line matching `^(FAIL|WARN)_[A-Z_]+:`
is one. `FAIL_*` is a hard finding, `WARN_*` is advisory. Look up the specific meaning and hint only
for the markers a given run actually emits.

#### Display rollup

- Render one rollup line: `Skill drift (X/Y)` where Y is the number of skills iterated and X is the number passing all 5 per-skill checks. The one-shot checks (template hash, refs cache, abort-reason enum, harness-claim markers, canonical-rule linkage, isHeadless drift, jr-ship anchor drift) render as their own rows below the rollup — green inline (`✓ Template hash`, `✓ Refs cache`, `✓ Abort-reason enum`, `✓ Harness-claim freshness`, `✓ Canonical-rule linkage`, `✓ isHeadless sync`, `✓ jr-ship anchor sync`) or expanded with a hint on warning/failure.
- On any warning/failure, expand inline with the skill name + first failing check per skill (4-space indent), matching the existing `Group D` and `Group F` expansion style.
- All findings are warn or fail — **never auto-fixable**. /jr-doctor reports; humans refactor (or run `/jr-skill-audit --refresh-refs` for the refs-cache case).

Group results and print using the format below. Each group prints a single line on full pass; expand inline on any `⚠`/`✗`.

### Group J — Capability probe (skipped if `--no-probe`)

Live-verifies the reviewer→lead reporting channel every swarm skill (`/jr-audit`, `/jr-review`, `/jr-i18n`, `/jr-skill-audit`) depends on — the machinery that failed silently for months in issue #70, where an empty result was indistinguishable from a clean review. It re-verifies `shared/subagent-reporting.md` "Verified behaviour" against the *running* harness, spawning throwaway `jr-reviewer` agents (haiku) fed only a fixed token-echo prompt (no repo content passes in, so the `Bash` their type grants has nothing to act on). Infrastructure errors (cannot spawn, tool not granted, a declined permission prompt) degrade **per-check**, never abort /jr-doctor, and a declined/blocked spawn is a skip, not a fail. Critically, a J2 or J3 infra-skip MUST NOT suppress J1: its reviewer→lead verdict is the actual #70 catch and is always reported on its own line (`⚠ <check> skipped (<reason>)` renders per failing check, never as a whole-group skip).

Issue the two spawns and the ToolSearch in one tool-use message, then assert:

- **J1 — reviewer→lead channel (positive).** Spawn `subagent_type: "jr-reviewer"`, `model: "haiku"`, **no** `name:`, and **no `run_in_background` pin** — let the harness choose, which since v2.1.198 means background by default (`https://code.claude.com/docs/en/sub-agents`). The pin was removed deliberately: the swarms this probe guards set no posture either, so pinning foreground would verify a configuration none of them requests, and a background-specific channel regression would pass J1 while findings vanished. Prompt: *emit the token `JR-DOCTOR-PROBE-POS` as your entire final response, nothing else*. PASS if the returned result contains the token. If it does not, **retry the spawn once** before recording anything (`docs/skill-anatomy.md` "Re-verifying a harness claim": confirm a negative before recording it — one haiku turn does not bound variance, and a false alarm on a default-on check breeds the fatigue that buries the real signal). Only if the retry *also* lacks the token: `✗ reviewer→lead channel BROKEN — every swarm skill will silently lose findings; this is the #70 failure mode. Do not trust any 'clean' swarm result until fixed.` Distinguish a spawn error (could not spawn `jr-reviewer` — cross-ref Group C `MISSING_AGENT`) from a channel break (spawned, token absent).
- **J2 — `name:` yields a teammate, not a return (negative).** Spawn the same but **with** `name: "jr-doctor-probe-named"` (append a fresh suffix if that name is still live from an earlier same-session run) and token `JR-DOCTOR-PROBE-NAMED`. PASS if the immediate spawn result is a persistent-teammate ack (a **presence** match: it contains `mailbox` / `Spawned successfully` / an `agent_id` line), NOT "token absent" — an absence-based negative is the exact anti-pattern this probe exists to prevent. This confirms `name:` buys a teammate ack (the proxy for "its report never reaches the lead"), not full non-return. If the token instead comes back: `⚠ name:'d spawns now appear to return — shared/subagent-reporting.md "Spawn rule" premise may be stale; re-verify the "Verified behaviour" matrix.` The named agent is left idle (a haiku throwaway, reclaimed at session end); do not message or stop it.
- **J3 — lead lacks `TaskCreate`/`TaskList` (negative).** `ToolSearch("select:TaskCreate,TaskList,TaskGet,TaskUpdate")`. PASS on `No matching deferred tools found` (a definite response, not silence). If any resolve: `⚠ the lead can now obtain TaskCreate/TaskList — the agent-teams task model may be back; no skill should route reviewer reporting through it (issue #70).` If `ToolSearch` is not available under this skill's grant, skip J3 with `⚠ J3 skipped (ToolSearch unavailable)`.

**Display**: one rollup line `Capability probe (X/3)`; expand inline on any `⚠`/`✗` (4-space indent), matching Group I's style.

<!-- harness-claim-verified: 2026-07-19 -->
<!-- Group J's own harness assumptions were verified live on 2026-07-19: J1 (unnamed jr-reviewer, haiku) returned its token in the result; J2 (name:d spawn) returned a mailbox/idle ack, not the token; J3 `ToolSearch("select:TaskCreate,TaskList,TaskGet,TaskUpdate")` returned exactly `No matching deferred tools found`. The probe live-re-checks J1/J2/J3 every run; this stamp additionally backstops J3's `select:` grammar + pass-string, which the probe cannot self-verify for grammar drift (docs/skill-anatomy.md "Re-verifying a harness claim"). Bump on re-verification. -->

### Sections

1. **Global setup** — Groups A, B, C, D, E, I (everything outside the current repo, including skill drift checks).
2. **Claude Code runtime** — Group H (env vars + claude version) + Group J (capability probe, unless `--no-probe`).
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

After the fix loop, print a final summary: the count of lines actually appended, each appended line,
then the Group F gitignore-coverage re-check. See `examples.md` "Fix pass" for the rendered shape.

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
