# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of personal Claude Code skills (slash commands) — `/audit`, `/review`, `/ship` — plus companion shell CLIs that partner with those skills. Each skill is a `SKILL.md` file in its own directory; companion CLIs live under `bin/`. There is no application code, no build system, no tests — just markdown skill definitions and shell scripts.

## Repo structure

```
audit/SKILL.md                     — full codebase audit swarm
review/SKILL.md                    — multi-agent PR review swarm
ship/SKILL.md                      — ship working-tree changes via PR (split analysis, branching, CI, merge)
shared/reviewer-boundaries.md      — canonical dimension-ownership table, severity rubric, confidence levels
shared/untrusted-input-defense.md  — canonical prompt-injection defense block for subagent prompts
shared/gitignore-enforcement.md    — canonical write-safety protocol for .claude/* cache + audit-trail files
bin/tackle                         — bootstrap a Claude Code session for a PR/issue/scratch worktree
                                     (drops a marker that /ship reads to rename the scratch branch in place)
```

### `shared/` — single source of truth

Files in `shared/` are referenced by `/audit` and `/review` at Phase 1 Track A. Each SKILL.md reads them in parallel with the other config files and enforces a **hard-fail guard**: if any shared file is missing, empty, or fails to Read, Phase 1 aborts immediately. Rationale: the inline duplicates at former call-sites were removed to eliminate drift; a missing shared file means the skill's guarantees (reviewer boundaries, untrusted-input safety, cache-write .gitignore checks) cannot be enforced, and silently degrading coverage is worse than aborting.

Usage pattern per file:
- `reviewer-boundaries.md` — passed verbatim into every reviewer subagent prompt.
- `untrusted-input-defense.md` — passed verbatim into every reviewer, implementer, simplification, convergence, and fresh-eyes subagent prompt.
- `gitignore-enforcement.md` — the lead agent applies the protocol at each `.claude/*` write site (cache files, audit reports, suppressions). Call-sites keep the `git ls-files --error-unmatch <path>` command and a per-site "Why" reason inline for reliability; the prose expansion of warn/append behavior lives in the shared file only.

**Exception — secret-warnings.json**: `/review` Phase 5.6 writes `.claude/secret-warnings.json` under a site-specific atomic-write protocol (`flock` + `.tmp` + `mv`, per-session filename variants). That inline block is NOT a gitignore-enforcement duplicate — it's a different protocol that happens to start with a similar security check — so it stays fully inline.

## Skill file anatomy

Each `SKILL.md` has:
1. **YAML frontmatter** — `name`, `description`, `argument-hint`, `effort`, `model`, `disable-model-invocation: true`, `user-invocable: true`. Note: there is no per-skill `advisor-model` field — the advisor tool uses the global `advisorModel` setting in `settings.json`.
2. **HTML comment block** — declares plugin dependencies, required CLI tools, cache files read/written, and required Claude Code tools
3. **Body** — phased execution plan with argument parsing, flag conflict resolution, display protocol, and detailed per-phase instructions

## Shared conventions across all three skills

- **Phased execution**: Every skill runs in numbered phases. Each phase has a prominent `━━━` header and a running cumulative timeline (`Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → ...`).
- **Parallel-first**: Tracks within a phase run simultaneously via multiple tool calls in a single message. Independent Bash/Read/Grep calls are always batched.
- **Silent agents, noisy lead**: Reviewer/implementer subagents report via TaskCreate and SendMessage only — no console output. Only the lead agent prints progress.
- **Shared cache files** in `.claude/`: `review-profile.json` (stack/package-manager detection), `review-baseline.json` (validation command baselines), `review-config.md` (suppressions and auto-learned rules), `audit-history.json` (append-only audit log).
- **Model routing**: Reviewer and implementer agents spawn with `model: "opus"`. Mechanical phases (context gathering, dedup, validation, cleanup) use the default model.
- **Severity rubric** (canonical: `shared/reviewer-boundaries.md`): critical → high → medium → low, with confidence levels certain → likely → speculative. Low-severity findings are dropped unless trivially fixable.
- **Reviewer dimension boundaries** (canonical: `shared/reviewer-boundaries.md`): Strict ownership of finding categories to prevent duplicates (e.g., silent failures → error-handling-reviewer, not security or typescript).
- **Finding format**: Every reviewer finding must include `file`, `line`, AND a `codeExcerpt` (3 consecutive lines from the cited file, verbatim). Phase 3 step 0 sanity-check reads the cited range and rejects any finding whose excerpt doesn't match — catches line-number AND content hallucinations. Per-reviewer 25% rejection rate escalates to Phase 7 `ACTION REQUIRED`.
- **Fix verification (Phase 5.55)**: After implementers mark findings "addressed", the lead re-reads the cited `file:line` (±5 lines) and confirms the issue described in the finding is no longer present. Classifies each as verified / unverified / moved. Soft flag — informs user, does not auto-revert.
- **`nofix` mode**: Every skill that implements fixes supports a findings-only mode that skips implementation and validation phases.
- **Memory integration**: `/audit` and `/review` Phase 1 Track A read (a) project memory at `~/.claude/projects/"${PWD//[.\/]/-}"/memory/` (all types — applies to this project), and (b) user-global memory at `~/.claude/projects/-Users-jroussel--claude-skills/memory/` (**`user_*.md` only** — role/expertise/preferences that apply across projects; framework-specific `feedback_*` stays per-repo). Phase 4.5 cross-run rejection promotion writes a `feedback`-type memory to the user-global dir when the same `dimension+category` has been rejected in 3+ separate runs (with explicit user consent and security dimension excluded).
- **Graph integration (optional)**: When `codebase-memory-mcp` is available and the repo is indexed, reviewers prefer `search_graph` / `trace_path` / `detect_changes` over Grep for structural questions (call-chain impact, dead-code detection, import edges). Grep fallback preserved when the graph is unavailable. `/audit` probes in Phase 0 Track 3; `/review` probes in Phase 1 Pre-checks (only for diffs ≥ 20 files and non-headless sessions). `/ship` Phase 2 uses `detect_changes` + `trace_path` for split analysis when available.
- **Advisor calls**: `/ship` calls `advisor()` before `gh pr merge` (single-PR step 14 and multi-PR step 11-multi 2a) and before committing to a split plan (step 5). `/review --converge` calls `advisor()` before convergence iteration 3+. All three are irreversible junctures; the advisor provides a second opinion without seeing the outcome.

## Worktree architecture: `bin/tackle` ↔ `/ship`

### Role split
- **`bin/tackle`** — user-invoked shell CLI. Not a skill; Claude does not invoke it. Bootstraps Claude Code sessions against a GitHub PR/issue (`tackle <N>`) or an empty scratch worktree (`tackle --scratch`).
- **`/ship`** — skill Claude invokes when the user types `/ship`. Consumes the worktree state tackle set up.
- **Coordination**: no IPC. They agree on filesystem conventions (paths + marker files). Changing one end of the contract requires changing the other.

### Worktree layout convention
- All tackle worktrees live at `<repo>/.claude/worktrees/<id>/`.
- `<id>` = `<N>-<slug>` for PR/issue worktrees (slug from PR/issue title), `scratch-<ts>-<pid>` for scratch worktrees.
- Branch naming per mode:
  - **Scratch**: branch equals `<id>` (tackle uses `git worktree add -b <scratch-id>`).
  - **Issue**: branch equals `<id>` (tackle uses `gh issue develop --name <N>-<slug>`, or a local-branch fallback with the same name).
  - **PR**: branch is the PR's own branch name (via `gh pr checkout <N>`), NOT `<id>`. Fork PRs use the PR branch directly; if the branch is already checked out elsewhere, tackle falls back to a local name `<N>-<slug>`.
- `/ship` treats any worktree whose path contains the segment `/.claude/worktrees/` as tackle-managed (`IS_TACKLE_WORKTREE=true`) and ephemeral — it auto-removes them after merge. (Running `/ship` inside a PR worktree is unusual; use `git push` to update the existing PR instead.)

### Why tackle does NOT use `claude -w`
- `claude -w <name>` forces the branch to be named `worktree-<name>` (Claude Code convention).
- That defeats tackle's naming scheme (`<N>-<slug>` / `scratch-<id>`) and conflicts with `/ship`'s conventional-commit branch derivation.
- tackle creates worktrees itself via raw `git worktree add` and invokes Claude with `claude --name <id>` for a friendly session label without the branch-name constraint. **Do not replace `--name` with `-w` — it breaks the architecture.**

### Scratch-session contract
- `tackle --scratch` creates a placeholder branch `scratch-<ts>-<pid>` from HEAD and drops a marker at `<worktree>/.git/info/scratch-session` whose contents are the scratch-id.
- `.git/info/` is the worktree-scoped git info dir (resolves to `<repo>/.git/worktrees/<id>/info/` for linked worktrees). It is **never committed** and is auto-cleaned when the worktree is pruned — no `.gitignore` entry needed.
- `/ship` Phase 1 reads this marker. If non-empty AND matches current HEAD, it sets `IS_SCRATCH=true` and `SCRATCH_ID=<marker>`.
- When set, `/ship` step 6 **renames the placeholder branch in place** via `git branch -m <SCRATCH_ID> <derived-name>` instead of creating a new branch. It then `rm`s the marker so re-running `/ship` on the same worktree doesn't retrigger the rename path.
- Stale marker (scratch-id ≠ current HEAD): warn "stale scratch marker", treat as non-scratch, continue normal flow.

### Tackle-type marker
- After creating any worktree (PR / issue / scratch), tackle writes the mode to `<worktree>/.git/info/tackle-type` — one of `pr`, `issue`, or `scratch`. Same worktree-scoped, never-committed, auto-pruned pattern as `scratch-session`.
- Read on resume by `read_tackle_type()` to drive the right behavior without an extra `gh` API call. Currently consumed by the prefill-prompt feature in `launch_claude()` (chooses "tackle issue" vs "tackle PR" template). Older worktrees from before this marker existed return empty → graceful no-op.
- Don't conflate with `scratch-session`: the scratch marker is a runtime contract with `/ship` (presence + match-vs-HEAD triggers in-place rename); `tackle-type` is a runtime hint local to tackle.

### Per-session context injection
- tackle writes PR/issue-specific context — title, URL, body, comments, reviews, instructions — into `<worktree>/CLAUDE.local.md`, delimited by `<!-- tackle-context-begin -->` and `<!-- tackle-context-end -->`. The `inject_claude_local_md()` function (`bin/tackle`) handles idempotent replacement: re-running `tackle <N>` rewrites the block in place.
- `CLAUDE.local.md` is auto-loaded by Claude Code alongside `CLAUDE.md`, so the session sees the context without the repo's real project-standards file being touched.
- tackle appends `CLAUDE.local.md` to the worktree-scoped `.git/info/exclude` on every inject, so the file can never be staged or committed from inside the worktree. Same pattern as the scratch-session marker: worktree-scoped, never committed, auto-cleaned when `git worktree prune` runs.
- `/ship` and `/review` need no special handling: the file is invisible to git from inside the worktree (via the exclude entry), and `CLAUDE.md` itself is untouched — so `/review`'s Phase 1 Track A and `/audit`'s equivalent read the real project standards, not PR context.

### Worktree-aware cleanup in `/ship`
`/ship` runs from any worktree. A secondary worktree cannot `git checkout <base>` (dual-checkout protection) and cannot `git branch -d` the currently-checked-out branch. So step 15 (single-PR) and step 12-multi (split-PR) split into two paths.

Detection primitives computed in Phase 1 (step 1b):
- `CURRENT_WORKTREE` = `git rev-parse --show-toplevel`
- `IS_SECONDARY` = `git rev-parse --git-dir` ≠ `git rev-parse --git-common-dir`
- `PRIMARY_WORKTREE` = first `worktree` entry from `git worktree list --porcelain`
- `IS_TACKLE_WORKTREE` = `CURRENT_WORKTREE` contains `/.claude/worktrees/`

Cleanup paths:
- **Path A (primary worktree)**: existing behavior — `checkout <base> && pull --ff-only && branch -d`.
- **Path B (secondary worktree)**: `git -C $PRIMARY_WORKTREE pull --ff-only origin <base>` (non-fatal warn on failure), then by category:
  - Tackle/scratch (`IS_TACKLE_WORKTREE=true` OR `IS_SCRATCH=true`): `cd $PRIMARY_WORKTREE && git worktree remove $CURRENT_WORKTREE --force && git branch -D <branch>`.
  - User-managed secondary: `git checkout --detach && git branch -D <branch>`. Worktree kept; warn the user.

### Anti-patterns (don't do these)
- **Don't use `claude -w` in tackle.** Forces `worktree-<name>` branch prefix and breaks the deferred-naming contract with `/ship`. tackle must create worktrees itself and launch Claude with `claude --name`.
- **Don't `git checkout <base>` from a secondary worktree.** Git's dual-checkout protection will fail. Use `git -C $PRIMARY_WORKTREE` for any operation targeting the base branch.
- **Don't delete the scratch marker before `/ship` step 6 runs.** Breaks rename detection; `/ship` will silently fall into the create-new-branch path.
- **Don't put tackle under `skills/<name>/`.** The `skills/` subtree has semantic meaning for Claude Code's skill loader. tackle is a CLI, not a skill; it lives at `bin/tackle` with a symlink from `~/.local/bin/tackle` for `$PATH` invocation.
- **Don't commit the scratch marker or the `.claude/worktrees/` directory.** Marker is in `.git/info/` precisely to avoid this. Worktree dirs should be in the consuming repo's `.gitignore`.
- **Don't inject tackle context into `<worktree>/CLAUDE.md`.** The repo's CLAUDE.md is read as authoritative project standards by `/review` and `/audit`; injecting per-session PR context there causes both skills to mis-read the standards and exposes the content to accidental commit. Always write to `<worktree>/CLAUDE.local.md` and register it in `.git/info/exclude` (same pattern as the scratch-session marker).
- **Don't expect cleanup in `--no-merge` / `--draft` / `--split-only` flows.** Step 15 / 12-multi are skipped in those modes — tackle worktrees persist until manually removed via `tackle --cleanup` or `git worktree remove`.

## Plugin dependencies

Required: `agent-teams@claude-code-workflows` (team-reviewer, team-implementer, TeamCreate/TeamDelete).

Optional: `pr-review-toolkit@claude-plugins-official` (silent-failure-hunter, type-design-analyzer, code-simplifier), `security-scanning@claude-code-workflows` (STRIDE methodology).

## Key design decisions

- `/audit` and `/review` share the same cache files and stack detection logic (Track C). Changes to one skill's caching format must be mirrored in the other.
- `/review` has a convergence loop (`--converge`) that wraps Phases 2-6 in a repeatable cycle with auto-approval. It includes a fresh-eyes security pass after convergence.
- `/ship` handles both single-PR and multi-PR (stacked/independent) flows. Split analysis uses semantic grouping heuristics with dependency detection between groups.
- Auto-learned suppressions (Phase 4.5 in audit/review) require 2+ rejections of the same pattern before adding a rule — single rejections are treated as situational.
