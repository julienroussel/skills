# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of personal Claude Code skills (slash commands) — `/audit`, `/review`, `/ship`, plus the diagnostic `/doctor` and the meta-audit `/skill-audit` — and companion shell CLIs that partner with those skills. Each skill is a `SKILL.md` file in its own directory; companion CLIs live under `bin/`. There is no application code, no build system, no tests — just markdown skill definitions and shell scripts.

## Repo structure

```
audit/SKILL.md                     — full codebase audit swarm (--converge for re-audit loops)
review/SKILL.md                    — multi-agent PR review swarm (--converge for re-review loops)
review/convergence-protocol.md     — skill-local convergence loop body (state tracking, file tracking,
                                     convergence Phases 2-6, fresh-eyes pass); NOT in shared/ because
                                     /audit's convergence is a separate, smaller protocol.
review/scripts/                    — Phase 5 base-commit anchor + symlink-escape (establish-base-anchor.sh);
                                     Phase 5.6 pre-commit hook installer (install-pre-commit-secret-guard.sh,
                                     SHA-256 verifies templates/ before append).
review/templates/                  — canonical pre-commit hook body (pre-commit-secret-guard.sh.tmpl);
                                     read-only; install script verifies its hash.
review/protocols/                  — skill-local procedures read at Phase 1 Track A under hard-fail +
                                     smoke-parse guard (mirrors shared/* discipline). Seven files:
                                     phase2-reviewers.md (Phase 2 body — effort-adaptive breadth,
                                     reviewer selection + swarm scaling, reviewer instructions,
                                     finding format), finding-sanity-check.md (Phase 3 step 0
                                     hallucination rejection), secret-warnings-lifecycle.md (Phase 7
                                     step 3 prune), base-anchor.md (Phase 5 base-commit anchor +
                                     Combined revert sequence), pre-commit-hook-offer.md (Phase 5.6
                                     install + 0/2/4/* error matrix), phase7-cleanup-report.md
                                     (Phase 7 body — flags, exit codes, 16-item report enumeration),
                                     phase8-followups.md (Phase 8 body — dedup + cross-repo
                                     visibility checks). These extractions pull /review toward
                                     Anthropic's 500-line guideline (issue #20).
ship/SKILL.md                      — ship working-tree changes via PR (split analysis, branching, CI
                                     wait + opus CI-failure fix loop, merge)
ship/protocols/                    — skill-local procedure read at Phase 1 under hard-fail + smoke-parse
                                     guard: ci-failure-handling.md (the opus CI-fix investigate →
                                     confirm-gate → re-watch loop, 2-cycle cap + single-fire stuck-loop
                                     advisor)
doctor/SKILL.md                    — health-check the user's Claude Code setup + current repo
                                     (CLI tools, plugins, settings.json, installed skills, shared
                                     files, gitignore); --fix appends to repo .gitignore on
                                     per-change confirmation (never edits settings.json). Group I
                                     (skill drift) runs narrow yes/no factual checks on every SKILL.md
                                     (line count, broken shared/* refs, frontmatter validity, inline
                                     duplication, template SHA-256 drift, refs-cache freshness)
skill-audit/SKILL.md               — opinionated audit of SKILL.md files; complements /doctor's narrow
                                     factual drift checks. Spawns 7 reviewer dimensions in parallel
                                     (frontmatter, advisor-coverage, token-efficiency, shared-drift,
                                     feature-adoption, safety-protocols, model-routing). Findings-only (no auto-fix in v1)
codebase-memory/SKILL.md           — personal cheat-sheet for the optional codebase-memory-mcp
                                     integration (decision matrix, edge types, Cypher examples)
find-skills/SKILL.md               — discover and install agent skills from the open ecosystem when
                                     the user asks "how do I do X" / "is there a skill for X" / wants
                                     to extend Claude Code capabilities
shared/reviewer-boundaries.md      — canonical dimension-ownership table, severity rubric, confidence levels
shared/untrusted-input-defense.md  — canonical prompt-injection defense block for subagent prompts
shared/gitignore-enforcement.md    — canonical write-safety protocol for .claude/* cache + audit-trail files
shared/display-protocol.md         — phase headers, timeline, silent-reviewers rule, compact tables, console redaction
shared/secret-scan-protocols.md    — isHeadless predicate, AUTO_APPROVE export, CI/headless secret-halt, user-continue
                                     (six behaviors), advisory-tier classification for re-scans
shared/audit-history-schema.md     — .claude/audit-history.json cross-skill schema (runs, runSummaries,
                                     reviewerStats, lastPromptedAt) shared between /audit and /review
shared/abort-markers.md            — Phase 7 abortReason → marker mapping (e.g. [ABORT — HEAD MOVED])
shared/secret-warnings-schema.md   — .claude/secret-warnings.json schema (consumerEnforcement, patternType
                                     enum, atomic-write requirements)
shared/advisor-criteria.md         — canonical advisor-call rules (when, gating, single-fire guards,
                                     conditional triggers); consumed by /skill-audit's advisor-coverage-reviewer
                                     (extracted from Anthropic's advisor tool guidance for portability — NOT
                                     from any user's personal CLAUDE.md, which would tie findings to whoever
                                     ran the skill last)
shared/secret-patterns.md          — canonical regex catalog for secret detection (token-prefix union,
                                     connection-string variants, quoted/unquoted assignments, POSIX ERE
                                     constraints, grep -Ei invocation rule). Read by /audit, /review,
                                     /ship secret-scan sites; co-cited with secret-scan-protocols.md
                                     (which owns the halt/continue procedures, not the patterns themselves).
shared/cache-schema-validation.md  — canonical schema validation for .claude/review-profile.json (rules
                                     a-f) and .claude/review-baseline.json (rules a-c). Includes binary
                                     availability probe and same-session shortcut. Read by /audit and
                                     /review at Phase 1 Track A (hard-fail + smoke-parse guard); applied
                                     at Track C and Track D cache-load sites.
skill-audit/cache/refs.json        — /skill-audit Phase 1 Track C live-references cache (Anthropic skills doc,
                                     env-vars doc, claude-code CHANGELOG); 7-day TTL, stale-cache fallback,
                                     `--refresh-refs` to force refresh; /doctor Group I warns if > 30 days old
docs/worktree-architecture.md      — tackle ↔ /ship contract; loaded via `@docs/worktree-architecture.md`
                                     when working on tackle/ship to avoid the per-session token cost
docs/skill-anatomy.md              — framework meta-doc explaining the five-tier layout (SKILL.md /
                                     shared/ / <skill>/protocols/ / scripts/ / templates/), where new
                                     content goes, smoke-parse anchor convention, hard-fail guard
                                     pattern, allowed-tools narrowing, anti-patterns, new-skill
                                     checklist. Loaded on-demand via `@docs/skill-anatomy.md` when
                                     adding a skill, extracting from SKILL.md, or onboarding
bin/tackle                         — bootstrap a Claude Code session for a PR/issue/scratch worktree
                                     (drops a marker that /ship reads to rename the scratch branch in place)
bin/seed-project-memory            — one-shot helper to draft a project_<name>.md auto-memory entry
                                     with placeholder sections for goals + conventions (the facts NOT
                                     derivable from the live repo — stack, git log, and CLAUDE.md are
                                     read fresh every run, so duplicating them would just decay).
                                     Opens $EDITOR, then writes to ~/.claude/projects/<encoded-cwd>/memory/
```

### `shared/` — single source of truth

Files in `shared/` are referenced by `/audit`, `/review`, and `/skill-audit` at Phase 1 Track A. Each SKILL.md reads them in parallel with the other config files and enforces a **hard-fail guard**: if any shared file is missing, empty, or fails to Read, Phase 1 aborts immediately. Rationale: the inline duplicates at former call-sites were removed to eliminate drift; a missing shared file means the skill's guarantees (reviewer boundaries, untrusted-input safety, cache-write .gitignore checks) cannot be enforced, and silently degrading coverage is worse than aborting.

Usage pattern per file:
- `reviewer-boundaries.md` — passed verbatim into every reviewer subagent prompt.
- `untrusted-input-defense.md` — passed verbatim into every reviewer, implementer, simplification, convergence, and fresh-eyes subagent prompt.
- `gitignore-enforcement.md` — the lead agent applies the protocol at each `.claude/*` write site (cache files, audit reports, suppressions). Call-sites keep the `git ls-files --error-unmatch <path>` command and a per-site "Why" reason inline for reliability; the prose expansion of warn/append behavior lives in the shared file only.
- `display-protocol.md` — the lead agent applies the rules (phase headers, timeline, silent-reviewers, compact tables, redaction) at every console-output site. Skill-specific Phase 4 finding-approval menus and convergence-display variants stay inline in the owning skill.
- `secret-scan-protocols.md` — referenced at every `isHeadless` evaluation, secret-halt invocation, user-continue site, and advisory-tier classification site. Pattern-specific demotion criteria for `SK`/`sk-`/`dapi` stay inline in `/review` Phase 1 Track B step 7 (scope-specific to diff-mode reviewing).
- `audit-history-schema.md` — referenced at Phase 1 Track A reads (rejection-rate calibration, suppression checks) and Phase 7 step 5 appends. Both `/audit` and `/review` MUST read and write the same schema.
- `abort-markers.md` — referenced at Phase 7 step 16 to render the correct marker per `abortReason`. Single source of truth for the `abortReason` enum.
- `secret-warnings-schema.md` — referenced at every `.claude/secret-warnings.json` append. `/review` writes at Phase 5.6, Phase 6 regression re-scan, Convergence Phase 5.6, and Fresh-eyes; `/audit` writes at Phase 5.6 and Phase 6 regression re-scan. Both skills MUST preserve the top-level `consumerEnforcement` value and the rich-wrapper shape across writes — the file is co-written and the previous `/audit` flat-array form is no longer accepted.
- `advisor-criteria.md` — passed verbatim to `/skill-audit`'s `advisor-coverage-reviewer` (the only consumer today). Extracted from Anthropic's published advisor tool guidance so the criteria are portable across users — explicitly NOT sourced from any individual user's `~/.claude/CLAUDE.md`. If Anthropic's advisor guidance changes, update this file (and bump the `Last verified` timestamp at the bottom).

## Skill file anatomy

Each `SKILL.md` has:
1. **YAML frontmatter** — `name`, `description`, `argument-hint`, `effort`, `model`, `disable-model-invocation: true`, `user-invocable: true`. Note: there is no per-skill `advisor-model` field — the advisor tool uses the global `advisorModel` setting in `settings.json`.
2. **HTML comment block** — declares plugin dependencies, required CLI tools, cache files read/written, and required Claude Code tools
3. **Body** — phased execution plan with argument parsing, flag conflict resolution, display protocol, and detailed per-phase instructions

## Shared conventions across `/audit`, `/review`, `/ship`, `/skill-audit`

(`/doctor` is intentionally simpler — it's a low-effort diagnostic that does not run reviewers, agents, or validation; the conventions below do not apply to it. `/skill-audit` participates in the conventions that apply to its scope: phased execution, parallel-first dispatch, silent agents, model routing for reviewers, severity rubric, finding format. Conventions tied to code modifications — fix verification, `nofix` mode, validation, auto-learning — do not apply because skill-audit is findings-only in v1.)

- **Phased execution**: Every skill runs in numbered phases. Each phase has a prominent `━━━` header and a running cumulative timeline (`Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → ...`).
- **Parallel-first**: Tracks within a phase run simultaneously via multiple tool calls in a single message. Independent Bash/Read/Grep calls are always batched.
- **Silent agents, noisy lead**: Reviewer/implementer subagents report via TaskCreate and SendMessage only — no console output. Only the lead agent prints progress.
- **Shared cache files** in `.claude/`: `review-profile.json` (stack/package-manager detection), `review-baseline.json` (validation command baselines), `review-config.md` (suppressions and auto-learned rules), `audit-history.json` (append-only audit log).
- **Model routing**: Reviewer and implementer agents spawn with `model: "opus"`. Mechanical phases (context gathering, dedup, validation, cleanup) use the default model. `/ship` keeps its lead on `sonnet` and spawns `model: "opus"` sub-agents for its two judgment-heavy tasks — split analysis (Phase 2) and CI-failure diagnosis/fix (CI-failure handling).
- **Severity rubric** (canonical: `shared/reviewer-boundaries.md`): critical → high → medium → low, with confidence levels certain → likely → speculative. Low-severity findings are dropped unless trivially fixable.
- **Reviewer dimension boundaries** (canonical: `shared/reviewer-boundaries.md`): Strict ownership of finding categories to prevent duplicates (e.g., silent failures → error-handling-reviewer, not security or typescript).
- **Finding format**: Every reviewer finding must include `file`, `line`, AND a `codeExcerpt` (3 consecutive lines from the cited file, verbatim). Phase 3 step 0 sanity-check reads the cited range and rejects any finding whose excerpt doesn't match — catches line-number AND content hallucinations. Per-reviewer 25% rejection rate escalates to Phase 7 `ACTION REQUIRED`.
- **Fix verification (Phase 5.55)**: After implementers mark findings "addressed", the lead re-reads the cited `file:line` (±5 lines) and confirms the issue described in the finding is no longer present. Classifies each as verified / unverified / moved. Soft flag — informs user, does not auto-revert.
- **`nofix` mode**: Every skill that implements fixes supports a findings-only mode that skips implementation and validation phases.
- **Memory integration**: `/audit` and `/review` Phase 1 Track A read (a) project memory at `~/.claude/projects/"${PWD//[.\/]/-}"/memory/` (all types — applies to this project), and (b) user-global memory at `~/.claude/projects/-Users-jroussel--claude-skills/memory/` (**`user_*.md` only** — role/expertise/preferences that apply across projects; framework-specific `feedback_*` stays per-repo). Phase 4.5 cross-run rejection promotion writes a `feedback`-type memory to the user-global dir when the same `dimension+category` has been rejected in **2+ separate runs** (with explicit user consent and security dimension excluded). Cross-run state lives in `.claude/audit-history.json` under a shared schema (`runs[]` per rejection, `runSummaries[]` per run, `reviewerStats[]` for FP-rate persistence, `lastPromptedAt` map to suppress re-prompts) — both `/audit` and `/review` read and write the same file.
- **FP-rate calibration**: Each reviewer dimension's running rejection rate (last 5 entries from `reviewerStats[]`) is computed at Phase 1 Track A. If ≥ 25%, a calibration note is prepended verbatim to that reviewer's Phase 2 prompt, instructing it to be more conservative on borderline cases.
- **Graph integration (optional)**: When `codebase-memory-mcp` is available and the repo is indexed, reviewers prefer `search_graph` / `trace_path` / `detect_changes` over Grep for structural questions (call-chain impact, dead-code detection, import edges). Grep fallback preserved when the graph is unavailable. `/audit` probes in Phase 0 Track 3; `/review` probes in Phase 1 Pre-checks (only for diffs ≥ 20 files and non-headless sessions). `/ship` Phase 2 uses `detect_changes` + `trace_path` for split analysis when available.
- **Advisor calls** (canonical rules in `shared/advisor-criteria.md`): `/ship --merge` calls `advisor()` before `gh pr merge` (single-PR step 14 and multi-PR step 11b-multi 1); `/ship` always calls `advisor()` before committing to a split plan (step 5). The pre-merge advisor only fires when `--merge` is set — the new default stops after CI without merging, so the merge advisor is dormant in the safe path. `/review` calls `advisor()` at Phase 4 pre-approval (≥ 20 findings or skewed-dimension), Phase 5 pre-dispatch (substantive-edit boundary), and Phase 6 stuck-loop (single-fire when retry count exhausts). `/review --converge` calls `advisor()` before convergence iteration 3+. `/audit` calls `advisor()` at Phase 4 pre-approval (same skewed-reviewer signal) and Phase 5 pre-dispatch (always). `/audit --converge` adds a pre-iteration advisor check at iteration ≥ 2. `/skill-audit` calls `advisor()` at Phase 4 pre-approval (skewed-dimension trigger) and Phase 7 declare-done (gated on non-triviality: `findingCount ≥ 5 OR dimensionCount ≥ 3 OR rejectionCount ≥ 1 OR abort fired` — trivially-clean small runs skip per the "Unconditional advisor on every run" anti-pattern in `advisor-criteria.md`). All are irreversible/high-blast-radius junctures or declare-done checkpoints; the advisor provides a second opinion without seeing the outcome.

## Worktree architecture: `bin/tackle` ↔ `/ship`

Worktree layout, marker conventions, scratch-session contract, per-session context injection, cleanup paths, and anti-patterns are documented in `docs/worktree-architecture.md`. **When working on tackle or `/ship`, load that doc with `@docs/worktree-architecture.md` to bring the full contract into context.** It is not auto-loaded here so non-tackle work doesn't pay the ~2K-token cost on every session.

Quick reminder of what lives there: role split between `tackle` and `/ship` (no IPC, only filesystem conventions); why tackle does not use `claude -w`; the `scratch-session` and `tackle-type` markers under `.git/info/`; `CLAUDE.local.md` injection registered via `.git/info/exclude`; primary-vs-secondary worktree cleanup paths in `/ship`; and the explicit anti-patterns (do not use `claude -w`, do not commit markers, do not inject context into `CLAUDE.md`, etc.).

## Plugin dependencies

Required: `agent-teams@claude-code-workflows` (team-reviewer, team-implementer, TeamCreate/TeamDelete).

Optional: `pr-review-toolkit@claude-plugins-official` (silent-failure-hunter, type-design-analyzer, code-simplifier), `security-scanning@claude-code-workflows` (STRIDE methodology).

## Key design decisions

- `/skill-audit` is the *opinionated* meta-audit counterpart to `/doctor`'s narrow factual checks (Group I). `/doctor` answers "is this skill objectively broken?" via yes/no file reads; `/skill-audit` answers "what could be better?" via 7 reviewer dimensions (frontmatter, advisor-coverage, token-efficiency, shared-drift, feature-adoption, safety-protocols, model-routing). Reviewers cite **live Anthropic documentation** — the skills doc and the claude-code CHANGELOG are fetched at Phase 1 Track C and cached at `skill-audit/cache/refs.json` (7-day TTL, `--refresh-refs` to force, stale-cache fallback when offline). Phase 3 sanity-check validates every finding's `source` citation against the cache so reviewers can't hallucinate features. Phase 4 has a [Clarify] sub-flow for `clarify: true` findings — judgment-call recommendations are surfaced via `AskUserQuestion` so the user resolves workflow-dependent calls in-line rather than at the end. Findings-only in v1 — no auto-fix, no Phase 5/6. Skill files are markdown specifications without a test harness. Scope: `~/.claude/skills/*/SKILL.md` (user skills, excluding gitignored / externally-maintained skills like `find-skills/` — Phase 1 Track B drops them); plugin skills out of scope in v1.
- `/audit` and `/review` share the same cache files and stack detection logic (Track C). Changes to one skill's caching format must be mirrored in the other.
- Both `/audit` and `/review` support `--converge[=N]`: a re-review loop that wraps Phases 2–6 in a repeatable cycle with auto-approval. `/review` defaults to 3 iterations (max 10) and runs a fresh-eyes security pass after convergence. `/audit` defaults to 2 iterations (max 5) — lower because the per-iteration blast radius is higher.
- `/review` supports `--branch[=<base>]` for reviewing the full feature-branch diff (committed-on-branch + working tree) as one scope — closes the gap between bare `/review` (working tree only, misses committed work) and `--pr=N` (remote read-only, misses unpushed/uncommitted work). Default `<base>` resolves via `gh pr list --head` (linked PR) or falls back to `origin/<default-branch>` via `gh repo view`. Aborts if local HEAD is behind upstream — local files must reflect HEAD for codeExcerpt verification to be safe. Mutually exclusive with `--pr`. Implementer + validation run normally (fixes apply locally); Phase 8 creates standalone issues, NOT a PR comment.
- `/ship` handles both single-PR and multi-PR (stacked/independent) flows. Split analysis uses semantic grouping heuristics with dependency detection between groups. On CI failure (single-PR step 13, multi-PR 11a-multi) it invokes the **CI-failure handling** procedure — an `opus` sub-agent diagnoses the failure from its own log fetch and proposes a fix, the user confirms before it is committed + re-pushed, then CI is re-watched (max 2 fix cycles). This runs in all modes; `--merge` differs only in that it proceeds to merge once CI is green.
- Auto-learned suppressions (Phase 4.5 in audit/review) require 2+ rejections of the same pattern before adding a rule — single rejections are treated as situational. Cross-run promotion to user-global memory needs 2+ rejections in 2+ separate runs (lowered from the original 3+ which empirically never fired).
- Shared protocol files (`shared/*.md`) are validated at Phase 1 with a hard-fail guard PLUS a structural smoke-parse (each file must contain a known load-bearing substring) — catches truncation that the non-empty check misses.
- `/audit` Phase 1 Track B uses lazy-load by default (reviewers fetch files on demand). Use `--prefetch` to restore the original pre-read behavior for ≤ 50-file scopes.
- `/review --pr` mode runs the `codeExcerpt` content match against the PR's post-image fetched via `gh api`, NOT the local checkout — so the hallucination guard works even when the local branch differs from the PR base. `/review --branch` mode reads from the local working tree (the Phase 1 behind-upstream abort guarantees local files reflect HEAD; bare `/review` and `--branch` share the same local-Read path).
