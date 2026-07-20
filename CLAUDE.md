# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of personal Claude Code skills (slash commands) — `/jr-audit`, `/jr-review`, `/jr-ship`, plus the diagnostic `/jr-doctor` and the meta-audit `/jr-skill-audit` — and companion shell CLIs that partner with those skills. Each skill is a `SKILL.md` file in its own directory; companion CLIs live under `bin/`. There is no application code, no build system, no tests — just markdown skill definitions and shell scripts.

## Always redact — never name a private identifier

These skills must be generic: they run in anyone's repo, so a name that means something only to their author is a bug. This repo is also public (`gh repo view --json visibility`), which makes the same mistake a leak. **Never write a private identifier into any file here** — skill bodies, shared protocols, edge-case tables, examples, sample console output, `bin/` scripts, commit messages, issue bodies.

| Never write | Write instead |
|---|---|
| A username, or an absolute path under a home dir | `~/…`, or derive it: `${HOME}`, `${PWD}`, `${CLAUDE_SKILL_DIR}`. (This repo's own public clone URL in `README.md` is fine — the owner handle is inherently public.) |
| A real private repo/project name as an example | a neutral placeholder repo/path, or `<repo>` |
| An employer, org, customer, or internal hostname | nothing — cut it; say what kind of thing it was only if the claim needs it |
| A private MR/issue/PR ref | its *date* alone (see below) |

**Redaction does not override "cite your sources" — it changes what the citation carries.** When a claim's evidence is a private artifact, keep the claim and its **date** and cut the identity outright: `confirmed against a live gitlab.com MR (2026-07-10)`, `Empirically observed (2026-07-16): …`. The date is the whole citation — it lets a reader judge staleness, which is the job the identity was not doing anyway.

**Do not leave a redaction artifact.** Swapping a name for a vague gesture ("a private ETL repo", "a private gitlab.com MR") is the worst outcome: untraceable, so it is not a citation; still pointing at something private, so it is not generic; and often redundant with the sentence around it.

Conversely, don't date-stamp a fact that is trivially re-checkable and non-volatile (the repo's own visibility); a stale stamp on a live fact reads as authoritative and misleads. A date earns its place when the fact drifts **and** a reader must judge staleness — not as a badge on every assertion.

Sweep for the *class*, not the instance — usernames appear under several spellings, so grep home-dir paths, org names, and private hostnames together rather than one known string. Enforced by review, not by a hook: it is on the author.

## Repo structure

```
jr-audit/SKILL.md                     — full codebase audit swarm (--converge for re-audit loops); also emits
                                     a 0–100 health score + verdict/hidden-bombs/strengths/roadmap report
                                     sections, an opt-in standardisation migration-map lens (Track C 7.5),
                                     and a .claude/health.json snapshot consumed by /jr-rollup
jr-audit/protocols/                   — skill-local procedures read at Phase 1 Track A under hard-fail +
                                     smoke-parse guard: phase2-reviewers.md (Phase 2 reviewer-swarm body —
                                     scope/effort/selection/scaling/reviewer instructions/finding format;
                                     anchors: `### Classify scope size` AND `### Finding format`),
                                     phase7-report.md (Phase 7 cleanup/report body; anchor `False positive rates`).
jr-audit/standardisation-target.md    — generic reference for /jr-audit's optional migration-map lens;
                                     contains NO target itself. The lens is opt-in per repo via a
                                     `## Standardisation target` in that repo's .claude/review-config.md
                                     (absent ⇒ lens off); classified lead-only in Track C step 7.5, printed
                                     in Phase 7. Soft-read pattern mirrors jr-skill-audit/edge-cases.md.
jr-rollup/SKILL.md                    — cross-app health rollup: thin skill over bin/jr-rollup that reads
                                     every app's .claude/health.json (from /jr-audit) into a worst-first
                                     estate table + portfolio summary, then flags what to prioritise.
                                     Read-only; never audits. effort:low, model:sonnet.
jr-review/SKILL.md                    — multi-agent PR/MR review swarm (--converge for re-review loops)
jr-review/convergence-protocol.md     — skill-local convergence loop body (state tracking, file tracking,
                                     convergence Phases 2-6, fresh-eyes pass); NOT in shared/ because
                                     /jr-audit's convergence is a separate, smaller protocol.
jr-review/scripts/                    — Phase 5 base-commit anchor + symlink-escape (establish-base-anchor.sh);
                                     Phase 5.6 pre-commit hook installer (install-pre-commit-secret-guard.sh,
                                     SHA-256 verifies templates/ before append).
jr-review/templates/                  — canonical pre-commit hook body (pre-commit-secret-guard.sh.tmpl);
                                     read-only; install script verifies its hash.
jr-review/protocols/                  — skill-local procedures read at Phase 1 Track A under hard-fail +
                                     smoke-parse guard (mirrors shared/* discipline). Nine files:
                                     phase2-reviewers.md (Phase 2 body — effort-adaptive breadth,
                                     reviewer selection + swarm scaling, reviewer instructions,
                                     finding format), finding-sanity-check.md (Phase 3 step 0
                                     hallucination rejection), secret-warnings-lifecycle.md (Phase 7
                                     step 3 prune), base-anchor.md (Phase 5 base-commit anchor +
                                     Combined revert sequence), pre-commit-hook-offer.md (Phase 5.6
                                     install + 0/2/4/* error matrix), phase7-cleanup-report.md
                                     (Phase 7 body — flags, exit codes, 16-item report enumeration),
                                     phase8-followups.md (Phase 8 body — dedup + cross-repo
                                     visibility checks), branch-mode.md (Phase 1 `--branch` pre-checks —
                                     detached-HEAD, base resolution, behind-upstream guard, merge-base; read
                                     ONLY when --branch is set, anchors `Detached HEAD check` AND `Compute
                                     merge base`), pr-url-mode.md (Phase 1 `--pr=<url>` URL parse + forge-pin
                                     from URL host + same-repo guard + `--allow-remote` off-repo opt-in; read
                                     ONLY when the --pr value is a URL, anchors `Parse the forge URL` AND
                                     `Same-repo guard`). These extractions pull /jr-review to Anthropic's
                                     500-line guideline (518→500, held below 500 with pr-url-mode extracted;
                                     issue #20).
jr-ship/SKILL.md                      — ship working-tree changes via PR (GitHub) / MR (GitLab), forge
                                     auto-detected per repo (split analysis, branching, CI wait + opus
                                     CI-failure fix loop, merge + file-overlap warning after PR/MR creation)
jr-ship/protocols/                    — skill-local procedures read at Phase 1 under hard-fail + smoke-parse
                                     guard: ci-failure-handling.md (the opus CI-fix investigate →
                                     confirm-gate → re-watch loop, 2-cycle cap + single-fire stuck-loop
                                     advisor); overlap-check.md (post-create PR file-overlap warning
                                     vs currently-open PRs via gh pr list --json files; informational
                                     only, opt-out via --no-overlap-check); worktree-cleanup.md
                                     (worktree-aware cleanup body — Consent basis + Path A/B,
                                     parameterized by BRANCHES/DELETE_SCRATCH/SUMMARY_STEP; applied
                                     at single-PR step 15 and multi-PR step 12-multi)
jr-doctor/SKILL.md                    — health-check the user's Claude Code setup + current repo
                                     (CLI tools, plugins, settings.json, installed skills, shared
                                     files, gitignore); --fix appends to repo .gitignore on
                                     per-change confirmation (never edits settings.json). Group I
                                     (skill drift) runs narrow yes/no factual checks on every SKILL.md
                                     (line count, broken shared/* refs, frontmatter validity, inline
                                     duplication, template SHA-256 drift, refs-cache freshness, abortReason enum drift, harness-claim
                                     date-stamp staleness >90d). Group J (capability probe, default-on;
                                     --no-probe skips) spawns two throwaway haiku jr-reviewer agents to live-verify the
                                     reviewer→lead reporting channel (issue #70/#73), that a name:d spawn does
                                     not return, and that the lead lacks TaskCreate/TaskList
jr-skill-audit/SKILL.md               — opinionated audit of SKILL.md files; complements /jr-doctor's narrow
                                     factual drift checks. Spawns 7 reviewer dimensions in parallel
                                     (frontmatter, advisor-coverage, token-efficiency, shared-drift,
                                     feature-adoption, safety-protocols, model-routing). Findings-only (no auto-fix in v1)
jr-skill-audit/protocols/plugin-scope.md — Track B `--plugin` scope-resolution procedure (marketplace
                                     location, git-tracked-skill enumeration, symlink/containment
                                     canonicalization, tagging); read at Phase 1 Track A ONLY when
                                     `--plugin` is set (conditional, mirrors jr-review convergence-protocol.md).
                                     Anchors: `Locate the marketplace` AND `Enumerate git-tracked skills`.
jr-skill-audit/protocols/personal-project-scope.md — Track B personal/project scope-resolution procedure
                                     (scope-root parent-walk, auto-scope default, enumeration/dedupe, argument-set +
                                     scope filters, cross-scope conflict probe, bare-positional resolution, per-scope
                                     gitignore exclusion); read at Phase 1 Track A ONLY when `--plugin` is NOT set
                                     (complementary conditional to plugin-scope.md). Anchors: `Scope roots` AND
                                     `Gitignore exclusion`.
jr-skill-audit/edge-cases.md          — case→behavior reference table (~21 rows); loaded on demand, NOT
                                     read at Phase 1 (reference material, no hard-fail guard). SKILL.md
                                     `## Edge cases` points here.
jr-i18n/SKILL.md                   — native-translator review of a project's translation catalogs. For each
                                     target locale the lead fans out ONE language-expert subagent (a reviewer
                                     dimension can't — `jr-reviewer` has no Agent tool) that
                                     ultrathinks accuracy + real-world idiom, plus mechanical catalog checks
                                     (missing/extra keys, placeholder/ICU-arg parity). Findings + suggested
                                     corrected text; findings-only, NEVER writes catalogs (`disallowed-tools`
                                     blocks Write/Edit/WebFetch — the load-bearing safety property). Complements the
                                     `i18n-reviewer` code-review dimension (diff-side code checks).
jr-i18n/protocols/                 — read at Phase 1 Track A under hard-fail + smoke-parse guard:
                                     locale-discovery.md (Phase 1 Track B framework/catalog detection +
                                     source/target locale resolution; anchors `Framework detection matrix`
                                     AND `Parameter sanitization`), phase2-translators.md (Phase 2 per-locale
                                     native-translator fan-out — persona, ultrathink, finding+suggestion
                                     format; anchors `Native-translator persona` AND `Finding format`).
jr-mermaid/SKILL.md                — generate a Mermaid diagram from a written source via
                                     plan → confirm → generate → review (lead-driven, no swarm).
                                     Confirms the plan before drawing; never invents unconfirmed
                                     nodes/edges; outputs a fenced ```mermaid block; writes into a
                                     target only via `--out` + the per-call Write prompt (`allowed-tools`
                                     omits Write/Edit). Generation counterpart to the `mermaid-reviewer`
                                     review dimension (which reviews existing diagrams in a diff).
codebase-memory/SKILL.md           — personal cheat-sheet for the optional codebase-memory-mcp
                                     integration (decision matrix, edge types, Cypher examples)
find-skills/SKILL.md               — discover and install agent skills from the open ecosystem when
                                     the user asks "how do I do X" / "is there a skill for X" / wants
                                     to extend Claude Code capabilities
jr-tackle/SKILL.md                    — wrap an ad-hoc in-session task with rigor instructions
                                     (ultrathink, verify findings against current sources or advisor(),
                                     ask clarifying questions early, smallest viable change, cite
                                     file:line for code claims, advisor before done). In-session
                                     equivalent of bin/tackle's "in plan mode, ultrathink to tackle ..."
                                     prefill (single source of truth — bin/tackle:19-21 now prefills
                                     "/jr-tackle <verb> <url>" instead of the literal rigor prose).
                                     Scope: file edits only — `/jr-ship` owns all git mutations
                                     (commit/push/PR/MR/merge); /jr-tackle stops at the working-tree-modified
                                     state and lets the user invoke /jr-ship explicitly.
                                     Intentionally minimal: no shared/*.md deps, no Phase 1 Track A
                                     guard, no protocols/ or scripts/ — does not participate in the
                                     "Shared conventions" block below.
.claude/agents/jr-reviewer.md      — repo-local native reviewer subagent type (no Write/Edit; tools: Read, Glob,
.claude/agents/jr-implementer.md      Grep, Bash); jr-implementer adds Write/Edit. Spawned unnamed by the
                                     reviewer/implementer swarms (/jr-audit, /jr-review, /jr-i18n, /jr-skill-audit);
                                     installed at ~/.claude/agents/ (README install). Replaced
                                     agent-teams@claude-code-workflows (#72). Tracked source; harness-resolved,
                                     not loaded into the lead's context.
shared/reviewer-boundaries.md      — canonical dimension-ownership table, severity rubric, confidence levels
shared/untrusted-input-defense.md  — canonical prompt-injection defense block for subagent prompts
shared/gitignore-enforcement.md    — canonical write-safety protocol for .claude/* cache + audit-trail files
shared/display-protocol.md         — phase headers, timeline, silent-reviewers rule, compact tables, console redaction
shared/secret-scan-protocols.md    — isHeadless predicate, AUTO_APPROVE export, CI/headless secret-halt, user-continue
                                     (six behaviors), advisory-tier classification for re-scans
shared/audit-history-schema.md     — .claude/audit-history.json cross-skill schema (runs, runSummaries,
                                     reviewerStats, lastPromptedAt) shared between /jr-audit and /jr-review
shared/abort-markers.md            — Phase 7 abortReason → marker mapping (e.g. [ABORT — HEAD MOVED])
shared/secret-warnings-schema.md   — .claude/secret-warnings.json schema (consumerEnforcement, patternType
                                     enum, atomic-write requirements)
shared/advisor-criteria.md         — canonical advisor-call rules (when, gating, single-fire guards,
                                     conditional triggers); consumed by /jr-skill-audit's advisor-coverage-reviewer
                                     (extracted from Anthropic's advisor tool guidance for portability — NOT
                                     from any user's personal CLAUDE.md, which would tie findings to whoever
                                     ran the skill last)
shared/secret-patterns.md          — canonical regex catalog for secret detection (token-prefix union,
                                     connection-string variants, quoted/unquoted assignments, POSIX ERE
                                     constraints, grep -Ei invocation rule). Read by /jr-audit, /jr-review,
                                     /jr-ship secret-scan sites; co-cited with secret-scan-protocols.md
                                     (which owns the halt/continue procedures, not the patterns themselves).
shared/code-edit-discipline.md     — canonical surgical-changes discipline for code-modifying subagents:
                                     Do/Don't list, worked ❌/✅ diff, "defend every changed line" test.
                                     Passed verbatim into every code-modifying subagent prompt in
                                     /jr-audit, /jr-review, and /jr-ship. Also bars slop in generated
                                     code (emoji/marketing prose, comments that restate code, padding with
                                     speculative abstraction/stubs/defensive cruft) and permits dead-code
                                     removal when that removal is the explicit assignment.
shared/cache-schema-validation.md  — canonical schema validation for .claude/review-profile.json (rules
                                     a-f) and .claude/review-baseline.json (rules a-c). Includes binary
                                     availability probe and same-session shortcut. Read by /jr-audit and
                                     /jr-review at Phase 1 Track A (hard-fail + smoke-parse guard); applied
                                     at Track C and Track D cache-load sites.
shared/phase1-track-a-protocol.md  — canonical Phase 1 Track A hard-fail guard: algorithm + Canonical
                                     Anchor Table (one row per shared/*.md with load-bearing smoke-parse
                                     substrings). Consumed by /jr-audit, /jr-review, /jr-skill-audit, /jr-i18n, /jr-mermaid at Phase 1
                                     Track A (hard-fail abort); /jr-doctor Group D reads at runtime for
                                     drift reporting (warn-only). Documents self-reference escape hatch
                                     and rules for adding new shared files.
shared/claim-verification.md       — canonical anti-hallucination doctrine: code-internal vs external-authority
                                     claim taxonomy, lead-independent Phase-3 classification (default-to-external),
                                     Tier 2 fetch-verify (default-on) + Tier 1 cap-and-defer fallback
                                     (--no-verify-claims opts out; raw .md / gh api, never a lone WebFetch), headless defer,
                                     the no-autonomous-decision-without-a-checked-fact rule, and the Harness-claims
                                     scope (a skill's own runtime assertions: date-stamp + re-verify-on-trigger +
                                     prefer a live probe; /jr-doctor Group J/I enforce). Read at Phase 1
                                     Track A by /jr-audit, /jr-review, /jr-skill-audit, /jr-i18n, /jr-mermaid; cross-ref'd by /jr-ship, /jr-tackle,
                                     /jr-doctor. /jr-skill-audit's live refs-cache is the reference Tier-2 impl.
shared/forge-detection.md          — canonical forge auto-detection (GitHub gh ↔ GitLab glab): host-heuristic
                                     detection algorithm (origin host → gh/glab; CLAUDE_FORGE overrides), the
                                     gh↔glab command / JSON-field / terminology mapping, and the per-site
                                     application rule incl. the external-authority gh api carve-out (stays gh
                                     regardless of the user's repo forge — only user-repo ops switch). Read at
                                     Phase 1 Track A by /jr-audit, /jr-review (and /jr-ship inline); /jr-doctor
                                     Group D smoke-parses it. The bin/ CLIs implement the same detection
                                     natively. gitlab.com-only heuristic; the `--pr`-consumed glab JSON field
                                     names are confirmed against a live GitLab MR (2026-07-10); other fields
                                     remain Milestone-2.
shared/model-override.md           — canonical `--model=<tier>` per-run subagent model override (allowlist
                                     sonnet|opus|haiku|fable; total override of every Agent-spawn preset
                                     incl. mechanical sites; nested spawns inherit; lead unaffected —
                                     frontmatter applies before arg parsing). Read at Phase 1 by
                                     /jr-audit, /jr-review, /jr-skill-audit, /jr-i18n (Track A) and /jr-ship (inline).
shared/subagent-reporting.md       — canonical subagent→lead reporting contract (issue #70). Four parts: the
                                     **Spawn rule** (work-producing subagents are spawned WITHOUT `name:`; a named
                                     subagent is a persistent teammate whose final response never reaches the lead,
                                     which is how findings vanished silently), the verified channel matrix (volatile:
                                     re-verify after a Claude Code upgrade — do not restate its verdicts
                                     elsewhere), the subagent-facing block passed verbatim into every reviewer/
                                     translator/implementer prompt, and the lead-side roll-call. Read at Phase 1
                                     Track A by /jr-audit, /jr-review, /jr-skill-audit, /jr-i18n.
jr-skill-audit/cache/refs.json        — /jr-skill-audit Phase 1 Track C live-references cache (Anthropic skills doc,
                                     env-vars doc, claude-code CHANGELOG); 7-day TTL, stale-cache fallback,
                                     `--refresh-refs` to force refresh; /jr-doctor Group I warns if > 30 days old
docs/worktree-architecture.md      — tackle ↔ /jr-ship contract; loaded via `@docs/worktree-architecture.md`
                                     when working on tackle/jr-ship to avoid the per-session token cost
docs/skill-anatomy.md              — framework meta-doc explaining the five-tier layout (SKILL.md /
                                     shared/ / <skill>/protocols/ / scripts/ / templates/), where new
                                     content goes, smoke-parse anchor convention, hard-fail guard
                                     pattern, allowed-tools narrowing, anti-patterns, new-skill
                                     checklist. Loaded on-demand via `@docs/skill-anatomy.md` when
                                     adding a skill, extracting from SKILL.md, or onboarding
bin/tackle                         — bootstrap a Claude Code session for a PR/MR/issue/scratch worktree
                                     (drops a marker that /jr-ship reads to rename the scratch branch in
                                     place; prefills "/jr-tackle <verb> <url>" into Claude's input box to
                                     invoke the in-session rigor wrapper — jr-tackle/SKILL.md is the
                                     single source of truth for the rigor prose, so the script's
                                     PROMPT_*_TEMPLATE constants at lines 19-21 stay trivial. UX
                                     caveat: the leading "/" may trigger Claude Code's slash-command
                                     picker mid-keystroke; the prefill is editable before Enter so
                                     the user can correct any distortion. If jr-tackle/SKILL.md is
                                     absent, build_prefill_text silently falls back to legacy
                                     literal-prose templates — PROMPT_*_TEMPLATE_LEGACY constants)
bin/seed-project-memory            — one-shot helper to draft a project_<name>.md auto-memory entry
                                     with placeholder sections for goals + conventions (the facts NOT
                                     derivable from the live repo — stack, git log, and CLAUDE.md are
                                     read fresh every run, so duplicating them would just decay).
                                     Opens $EDITOR, then writes to ~/.claude/projects/<encoded-cwd>/memory/
bin/jr-rollup                      — deterministic cross-app health aggregator behind /jr-rollup (also
                                     runnable directly). Generic discovery: git submodules, else any dir with a
                                     .claude/health.json (name-agnostic) + standard component dirs
                                     (apps|packages|services|libs/* and top-level e2e/docs/web/api/…; that
                                     component sweep is skipped when the root itself holds a valid, complete
                                     snapshot, whose audit already covered the root's whole tree — an
                                     unreadable or incomplete one does not count), else the
                                     repo root. Reads each <app>/.claude/health.json, prints a worst-first estate
                                     table + portfolio summary (bands, total remaining criticals, stale/
                                     incomplete/never-audited/invalid(bad-json|bad-schema)). --json for machine output.
                                     bash 3.2-compatible. Read-only; never audits. Needs jq/git/column.
bin/tackle-top                     — rank a repo's open issues (GitHub or GitLab — forge auto-detected) via headless `claude -p` (haiku,
                                     `--json-schema` constrained), then spawn N WezTerm tabs each
                                     running `tackle <N>` in the target repo. Interactive selection by
                                     default; `--yes` to skip the prompt; `--dry-run` for ranking-only.
                                     Spawns through `$SHELL -lc` so the wezterm-mux PATH (which lacks
                                     `~/.local/bin` on macOS GUI launches) picks up `claude`.
```

### `shared/` — single source of truth

Files in `shared/` are referenced by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n`, `/jr-mermaid`, and `/jr-ship` at Phase 1 (Track A in the multi-track skills; `/jr-mermaid` reads its subset in a single-track Phase 1, `/jr-ship` inline in Phase 1). Each SKILL.md reads its declared subset in parallel with the other config files and enforces a **hard-fail guard**: if any shared file is missing, empty, fails to Read, or fails the structural smoke-parse defined in `phase1-track-a-protocol.md`, Phase 1 aborts immediately. Rationale: the inline duplicates at former call-sites were removed to eliminate drift; a missing shared file means the skill's guarantees (reviewer boundaries, untrusted-input safety, cache-write .gitignore checks) cannot be enforced, and silently degrading coverage is worse than aborting.

Usage pattern per file:
- `reviewer-boundaries.md` — passed verbatim into every reviewer subagent prompt.
- `untrusted-input-defense.md` — passed verbatim into every reviewer, implementer, simplification, convergence, and fresh-eyes subagent prompt.
- `gitignore-enforcement.md` — the lead agent applies the protocol at each `.claude/*` write site (cache files, audit reports, suppressions, health snapshots). Call-sites keep the `git ls-files --error-unmatch <path>` command and a per-site "Why" reason inline for reliability; the prose expansion of warn/append behavior lives in the shared file only.
- `display-protocol.md` — the lead agent applies the rules (phase headers, timeline, silent-reviewers, compact tables, redaction) at every console-output site. Skill-specific Phase 4 finding-approval menus and convergence-display variants stay inline in the owning skill.
- `secret-scan-protocols.md` — referenced at every `isHeadless` evaluation, secret-halt invocation, user-continue site, and advisory-tier classification site. Pattern-specific demotion criteria for `SK`/`sk-`/`dapi` stay inline in `/jr-review` Phase 1 Track B step 7 (scope-specific to diff-mode reviewing).
- `audit-history-schema.md` — referenced at Phase 1 Track A reads (rejection-rate calibration, suppression checks) and Phase 7 step 5 appends. Both `/jr-audit` and `/jr-review` MUST read and write the same schema.
- `abort-markers.md` — referenced at Phase 7 step 16 to render the correct marker per `abortReason`. Single source of truth for the `abortReason` enum.
- `secret-warnings-schema.md` — referenced at every `.claude/secret-warnings.json` append. `/jr-review` writes at Phase 5.6, Phase 6 regression re-scan, Convergence Phase 5.6, and Fresh-eyes; `/jr-audit` writes at Phase 5.6 and Phase 6 regression re-scan. Both skills MUST preserve the top-level `consumerEnforcement` value and the rich-wrapper shape across writes — the file is co-written and the previous `/jr-audit` flat-array form is no longer accepted.
- `code-edit-discipline.md` — passed verbatim into every code-modifying subagent prompt across `/jr-audit`, `/jr-review`, and `/jr-ship` (with a Phase-5.5-specific lead-in prepended to the canonical body for `/jr-review`'s simplification agent, and a CI-fix-specific lead-in + opening-paragraph elision for `/jr-ship`'s CI-fix agent — the canonical's "you have been assigned specific findings" opening assumes a findings-list workflow that doesn't fit CI-failure repair). Codifies surgical-changes discipline (no drive-by refactors, no style drift, no opportunistic type/comment creep, no fixing unrelated bugs). Prevention-side counterpart to Phase 5.55 fix-verification's reactive `moved` classification.
- `advisor-criteria.md` — passed verbatim to `/jr-skill-audit`'s `advisor-coverage-reviewer` (the only consumer today). Extracted from Anthropic's published advisor tool guidance so the criteria are portable across users — explicitly NOT sourced from any individual user's `~/.claude/CLAUDE.md`. If Anthropic's advisor guidance changes, update this file (and bump the `Last verified` timestamp at the bottom).
- `phase1-track-a-protocol.md` — read at Phase 1 Track A by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n` (and at single-track Phase 1 by `/jr-mermaid`) (as a shared file) AND parsed by them for the Canonical Anchor Table that drives the structural smoke-parse. `/jr-doctor` Group D consumes the same canonical at runtime to smoke-parse every shared file (warn-only). Each consumer hardcodes one self-reference anchor (`Canonical Anchor Table`) to break the circularity. Abort message wording is **not canonical** — consumers own it; the file documents that intentional divergence (`/jr-audit` and `/jr-review` use inline prose; the other consumers use the canonical `[ABORT — SHARED FILE MISSING]` marker).
- `claim-verification.md` — read at Phase 1 Track A by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n` (and at single-track Phase 1 by `/jr-mermaid`) and passed to reviewers/translators as context (applied lead-side in `/jr-mermaid`); the lead applies its claim classification + cap/verify at Phase 3 and the no-autonomous-decision-without-a-checked-fact rule at every auto-apply/merge site. Cross-referenced (not Track-A-read) by `/jr-ship`'s CI-fix protocol and `/jr-tackle`'s rigor protocol. `/jr-skill-audit`'s live refs-cache is the reference Tier-2 implementation of the doctrine.
- `subagent-reporting.md` — read at Phase 1 Track A by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n` (the four skills that spawn subagents to produce findings). Its **Spawn rule** is applied at every Agent-spawn site: no `name:` on a work-producing subagent. Its **Subagent-facing block** is passed **verbatim** into every reviewer, translator, and implementer prompt (do not paraphrase the "if you found nothing, say so explicitly" rule — it is what keeps a clean dimension distinguishable from a lost one). Its **Lead-side: reviewer roll-call** runs at Phase 3 step 0.0, numbered so the convergence protocols' by-number step inheritance carries it, and applies again to the Phase 5 implementer dispatch. `UNREPORTED` is load-bearing state that every consumer MUST consume — render it, exit non-zero on it, and let it block every clean-result path (`no findings` / `clean` / `all clear` / `converged = true`); a consumer that computes it and drops it has rebuilt #70 with extra steps. The file also records the verified channel matrix so dead options are not re-proposed; treat it as volatile and re-verify after an upgrade rather than restating its verdicts here.
- `model-override.md` — read at Phase 1 by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n` (at Track A) and `/jr-ship` (inline). The lead applies it at every Agent-spawn call site: when `--model=<tier>` was parsed, the spawn passes `model: "<tier>"` instead of the site's preset (including mechanical default-model sites — the override is total). The lead's own model is out of scope (frontmatter applies before argument parsing; users run `/model <tier>` first for a uniform run).
- `forge-detection.md` — read at Phase 1 Track A by `/jr-audit` and `/jr-review`; `/jr-ship` reads it inline in Phase 1; `/jr-doctor` Group D smoke-parses it via the anchor table. The lead detects the forge once per run from the `origin` host and translates every `gh`/PR/checks reference to its `glab`/MR/pipeline equivalent per the command-equivalence + terminology tables at each **user-repo** call-site. The **external-authority `gh api` carve-out** is the load-bearing distinction: a `gh api …/contents/…` that fetches an Anthropic/framework doc (claim verification) stays `gh` even on a GitLab repo — only ops on the user's own repo switch. The `bin/` CLIs (`tackle`, `tackle-top`) implement the same detection natively (they can't read `shared/` at runtime). gitlab.com-only hostname heuristic; `CLAUDE_FORGE` env overrides. The `--pr`-consumed glab JSON field names are verified against a live GitLab MR (2026-07-10, `§c`); the rest remain an implementation-time deliverable.
- `cache-schema-validation.md` — schema-validation rules (binary-availability probe, cache-poisoning guard, same-session shortcut) applied before trusting `.claude/review-profile.json` and `.claude/review-baseline.json`. Read at Phase 1 Track A and applied at every cache-read site by `/jr-audit` and `/jr-review` (the cache co-owners).
- `secret-patterns.md` — the canonical secret-detection regex catalog, applied at every secret pre-scan / post-implementation re-scan site by `/jr-audit`, `/jr-review`, and `/jr-ship` (inline). The pre-commit hook `/jr-review` installs materializes it into `.claude/secret-hook-patterns.txt` rather than reading this file directly.

## Skill file anatomy

Each `SKILL.md` has:
1. **YAML frontmatter** — `name`, `description`, `argument-hint`, `effort`, `model`, `disable-model-invocation: true`, `user-invocable: true`. Note: there is no per-skill `advisor-model` field — the advisor tool uses the global `advisorModel` setting in `settings.json`.
2. **HTML comment block** — declares plugin dependencies, required CLI tools, cache files read/written, and required Claude Code tools
3. **Body** — phased execution plan with argument parsing, flag conflict resolution, display protocol, and detailed per-phase instructions

## Shared conventions across `/jr-audit`, `/jr-review`, `/jr-ship`, `/jr-skill-audit`

(`/jr-doctor` is intentionally simpler — it's a low-effort diagnostic that runs no reviewer/implementer swarm and no validation — the only agents it spawns are the Group J capability probe's two throwaway haiku self-tests of the reviewer→lead channel (default-on, `--no-probe` skips); the conventions below do not apply to it. `/jr-skill-audit` participates in the conventions that apply to its scope: phased execution, parallel-first dispatch, silent agents, model routing for reviewers, severity rubric, finding format. Conventions tied to code modifications — fix verification, `nofix` mode, validation, auto-learning — do not apply because skill-audit is findings-only in v1.)

- **Phased execution**: Every skill runs in numbered phases. Each phase has a prominent `━━━` header and a running cumulative timeline (`Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → ...`).
- **Parallel-first**: Tracks within a phase run simultaneously via multiple tool calls in a single message. Independent Bash/Read/Grep calls are always batched.
- **Silent agents, noisy lead**: Reviewer/implementer subagents never print to the console (their output is not visible to the user); only the lead agent prints progress. They deliver findings **in their final response**, which reaches the lead only because they are spawned **without `name:`** (canonical: `shared/subagent-reporting.md`). The lead runs a **roll-call** against its spawn list before dedup: a subagent that returns nothing is `UNREPORTED`, never a clean dimension.
- **Shared cache files** in `.claude/`: `review-profile.json` (stack/package-manager detection), `review-baseline.json` (validation command baselines), `review-config.md` (suppressions and auto-learned rules), `audit-history.json` (append-only audit log).
- **Model routing**: Reviewer and implementer agents spawn with `model: "opus"`. Mechanical phases (context gathering, dedup, validation, cleanup) use the default model. `/jr-audit`, `/jr-review`, `/jr-skill-audit`, `/jr-i18n`, and `/jr-ship` all keep their **lead** on `sonnet` — each lead's own judgment-heavy-looking phases (claim classification, dedup/synthesis, fix-verification) turned out to be rule-driven orchestration once inspected line-by-line, not open-ended agentic coding — and delegate the actual deep-reasoning work to `model: "opus"` sub-agents (reviewers, implementers, simplification, translators, split analysis, CI-failure diagnosis/fix, security fresh-eyes). `/jr-mermaid` and `/jr-tackle` are the intentional exception: lead-only skills with no subagent swarm to delegate to, so the lead itself stays `opus`. All five swarm skills — and the satellite `/jr-i18n` — accept `--model=<tier>` (canonical: `shared/model-override.md`), which overrides every subagent spawn preset for that run; absent the flag, each reviewer/implementer/analysis/translator spawn defaults to `opus` (mechanical phases keep the session default). The lead's frontmatter model is independent of the flag.
- **Forge auto-detection** (canonical: `shared/forge-detection.md`): `/jr-review` and `/jr-ship` detect the repo's forge once per run from the `origin` host — `github.com`→`gh`, `gitlab.com`→`glab` (gitlab.com-only hostname heuristic; `CLAUDE_FORGE` overrides) — and translate every `gh`/PR/checks reference to its `glab`/MR/pipeline equivalent at each **user-repo** call-site (`gh pr merge`→`glab mr merge`, `gh pr checks --watch`→`glab ci status --live`, etc.; CI is a semantic adaptation, not a rename). `/jr-audit` has **no user-repo forge call-site** — its sole `gh` use is the external-authority claim-verification `gh api` (which stays `gh`), so it reads `forge-detection.md` for the carve-out context + glab-mirror readiness only, with nothing to translate. The **external-authority carve-out** is load-bearing: a `gh api …/contents/…` that fetches an Anthropic/framework doc for claim verification stays `gh` regardless of the user's forge — only the user's own repo switches. `/jr-doctor` accepts `gh` OR `glab`; the `bin/` CLIs (`tackle`, `tackle-top`) implement the same detection natively. the `--pr`-consumed glab `-F json` field names are verified against a live GitLab MR (2026-07-10); the rest remain a Milestone-2 deliverable.
- **Severity rubric** (canonical: `shared/reviewer-boundaries.md`): critical → high → medium → low, with confidence levels certain → likely → speculative. Low-severity findings are dropped unless trivially fixable.
- **Reviewer dimension boundaries** (canonical: `shared/reviewer-boundaries.md`): Strict ownership of finding categories to prevent duplicates (e.g., silent failures → error-handling-reviewer, not security or typescript). The `simplicity-reviewer` dimension (both skills; conservative, severity-capped at medium) owns within-unit slop — over-engineering, local dead code, redundancy, comments that restate code, defensive code for impossible states — deferring cross-module structure to architecture-reviewer and inaccurate comments to comment-reviewer. It is not file-type-bound (receives all changed/in-scope files) and is diff-scoped in `/jr-review`, scope-wide in `/jr-audit`.
- **Finding format**: Every reviewer finding must include `file`, `line`, AND a `codeExcerpt` (3 consecutive lines from the cited file, verbatim). Phase 3 step 0 sanity-check reads the cited range and rejects any finding whose excerpt doesn't match — catches line-number AND content hallucinations. Per-reviewer 25% rejection rate escalates to Phase 7 `ACTION REQUIRED`.
- **Escalation rendering (`ACTION REQUIRED`)**: `/jr-review` and `/jr-audit` render every run escalation routed to `ACTION REQUIRED` (secret-continue, per-reviewer ≥25% rejection/refuted rates, >30%-unverified-fix and unverified-`critical` notes, plus `/jr-review`'s secret-warnings / pre-commit-hook maintenance) under a **mandatory-when-non-empty `Action required` lead-in** at the top of their Phase 7 report body (`jr-review/protocols/phase7-cleanup-report.md`, `jr-audit/protocols/phase7-report.md`) — in `/jr-review`'s compact report as well as the full one (its compact whitelist names it, so `quick`/`nofix` can't drop it). The literal `ACTION REQUIRED` label is retained (NOT converged to `/jr-skill-audit`'s vocabulary) because `shared/secret-scan-protocols.md` behavior 4 reads *"the files listed in the ACTION REQUIRED section"* by name — the label is a load-bearing anchor, not cosmetic. `/jr-skill-audit` **bans** the label (its Naming contract) and uses `Audit integrity` / `Action items` instead, after an incident where it routed *findings* through the label and rendered "ACTION REQUIRED: None" while 28 findings existed; `/jr-review` and `/jr-audit` never route findings through it (findings have Phase 4 approval + the Findings report item), so that conflation cannot recur — the divergence is intentional (issue #74, criterion 3). This rationale is maintainer-read, **not** machine-enforced: `shared-drift-reviewer` polices `shared/*.md`, not this file, so re-converging the label is guarded only by a maintainer reading this bullet first.
- **Claim verification** (canonical: `shared/claim-verification.md`): citation integrity (the `codeExcerpt` sanity-check, above) proves the cited line *exists*; claim verification proves the *claim about it* is true. The lead independently classifies each finding at Phase 3 as **code-internal** (provable from local code — already covered by `codeExcerpt`) or **external-authority** (depends on API deprecation, version behavior, framework rules, CVEs, WCAG/OWASP — the hallucination-prone class), defaulting to external-when-in-doubt (never the reviewer's self-label). For an external-authority claim that local context (pinned versions/types/config) can't settle, the lead **by default** fetches an authoritative source (raw `.md` / `gh api`, never a lone WebFetch — a single WebFetch can fabricate verbatim text) to confirm or refute it (Tier 2; always-on for `/jr-skill-audit`, whose live refs-cache is the reference implementation; `--no-verify-claims` opts out elsewhere): `confirmed` → kept (a checked fact, auto-appliable); `refuted` → rejected under `[REJECTED — CLAIM REFUTED BY SOURCE]`. Only a claim that can't be verified (offline, uncorroborable, or `--no-verify-claims`) is capped to `speculative` and routed to the user (interactive) or deferred + reported (headless), never auto-applied (Tier 1 fallback). Generalizes to the rule: no consequential autonomous action (apply a fix, write a suppression, auto-approve in convergence, merge) without a checked fact.
- **Fix verification (Phase 5.55)**: After implementers mark findings "addressed", the lead re-reads the cited `file:line` (±5 lines) and confirms the issue described in the finding is no longer present. Classifies each as verified / unverified / moved. Soft flag — informs user, does not auto-revert.
- **`nofix` mode**: Every skill that implements fixes supports a findings-only mode that skips implementation and validation phases.
- **Memory integration**: `/jr-audit` and `/jr-review` Phase 1 Track A read (a) project memory at `~/.claude/projects/"${PWD//[.\/]/-}"/memory/` (all types — applies to this project), and (b) user-global memory at `~/.claude/projects/"${HOME//[.\/]/-}--claude-skills"/memory/` (the skills repo's own memory dir, derived from `$HOME` so it is portable — NOT a hardcoded username) (**`user_*.md` only** — role/expertise/preferences that apply across projects; framework-specific `feedback_*` stays per-repo). Phase 4.5 cross-run rejection promotion writes a `feedback`-type memory to the user-global dir when the same `dimension+category` has been rejected in **2+ separate runs** (with explicit user consent and security dimension excluded). Cross-run state lives in `.claude/audit-history.json` under a shared schema (`runs[]` per rejection, `runSummaries[]` per run, `reviewerStats[]` for FP-rate persistence, `lastPromptedAt` map to suppress re-prompts) — both `/jr-audit` and `/jr-review` read and write the same file.
- **FP-rate calibration**: Each reviewer dimension's running rejection rate (last 5 entries from `reviewerStats[]`) is computed at Phase 1 Track A. If ≥ 25%, a calibration note is prepended verbatim to that reviewer's Phase 2 prompt, instructing it to be more conservative on borderline cases.
- **Graph integration (optional)**: When `codebase-memory-mcp` is available and the repo is indexed, reviewers prefer `search_graph` / `trace_path` / `detect_changes` over Grep for structural questions (call-chain impact, dead-code detection, import edges). Grep fallback preserved when the graph is unavailable. `/jr-audit` probes in Phase 0 Track 3; `/jr-review` probes in Phase 1 Pre-checks (only for diffs ≥ 20 files and non-headless sessions). `/jr-ship` Phase 2 uses `detect_changes` + `trace_path` for split analysis when available.
- **Advisor calls** (canonical rules in `shared/advisor-criteria.md`): `/jr-ship --merge` calls `advisor()` before `gh pr merge` (single-PR step 14 and multi-PR step 11b-multi 1); `/jr-ship` always calls `advisor()` before committing to a split plan (step 5). The pre-merge advisor only fires when `--merge` is set — the new default stops after CI without merging, so the merge advisor is dormant in the safe path. `/jr-review` calls `advisor()` at Phase 4 pre-approval (≥ 20 findings or skewed-dimension), Phase 5 pre-dispatch (substantive-edit boundary), and Phase 6 stuck-loop (single-fire when retry count exhausts). `/jr-review --converge` calls `advisor()` before convergence iteration 3+. `/jr-audit` calls `advisor()` at Phase 4 pre-approval (same skewed-reviewer signal) and Phase 5 pre-dispatch (substantive-edit boundary — required unless skipped per the site's documented exceptions, matching `/jr-review`). `/jr-audit --converge` adds a pre-iteration advisor check at iteration ≥ 2. `/jr-skill-audit` calls `advisor()` at Phase 4 pre-approval (skewed-dimension trigger) and Phase 7 declare-done (gated on non-triviality: `findingCount ≥ 5 OR dimensionCount ≥ 3 OR rejectionCount ≥ 1 OR abort fired` — trivially-clean small runs skip per the "Unconditional advisor on every run" anti-pattern in `advisor-criteria.md`). All are irreversible/high-blast-radius junctures or declare-done checkpoints; the advisor provides a second opinion without seeing the outcome.

## Worktree architecture: `bin/tackle` ↔ `/jr-ship`

Worktree layout, marker conventions, scratch-session contract, per-session context injection, cleanup paths, and anti-patterns are documented in `docs/worktree-architecture.md`. **When working on tackle or `/jr-ship`, load that doc with `@docs/worktree-architecture.md` to bring the full contract into context.** It is not auto-loaded here so non-tackle work doesn't pay the ~2K-token cost on every session.

Quick reminder of what lives there: role split between `tackle` and `/jr-ship` (no IPC, only filesystem conventions); why tackle does not use `claude -w`; the `scratch-session` and `tackle-type` markers under `.git/info/`; `CLAUDE.local.md` injection registered via `.git/info/exclude`; primary-vs-secondary worktree cleanup paths in `/jr-ship`; and the explicit anti-patterns (do not use `claude -w`, do not commit markers, do not inject context into `CLAUDE.md`, etc.).

## External dependencies — vanilla-first

**No required third-party dependency.** Any capability a skill's guarantees rest on must be vanilla Claude Code or repo-local (`.claude/agents/*.md`, `shared/*.md`, `<skill>/scripts/`). A capability that is only available from a plugin or marketplace is a capability this repo does not have. This is not a rule against plugins; it is a rule against a skill's correctness depending on one.

**Reviewer/implementer agent types (repo-local, native).** The reviewer/implementer swarms in `/jr-audit`, `/jr-review`, `/jr-i18n`, `/jr-skill-audit` spawn the repo-local `jr-reviewer` (no Write/Edit; tools: `Read, Glob, Grep, Bash`) and `jr-implementer` (`Read, Write, Edit, Glob, Grep, Bash`) types, defined in `.claude/agents/*.md` and installed at `~/.claude/agents/` (see the README install). No plugin, no experimental flag; spawned WITHOUT `name:` per `shared/subagent-reporting.md` "Spawn rule". They replaced `agent-teams@claude-code-workflows` (#72).

**Optional integrations must degrade gracefully.** An integration may make a skill better when present, but its absence must produce a documented fallback, never an abort. Canonical example: `codebase-memory-mcp` (reviewers prefer `search_graph`/`trace_path` when indexed; Grep fallback otherwise). If you cannot write the fallback, the dependency is required and belongs elsewhere.

**Credit is not a dependency.** Where a plugin's *methodology* was inlined into a prompt, say so under Methodology credits (below), not as a dependency: a reader will install it expecting it to be wired, and `/jr-doctor` should not check for it.

**Rationale.** A third-party agent definition can change its `tools:` list or persona in a release and silently alter every reviewer in the repo. That is not hypothetical: this repo depended on `agent-teams` for a read-only sandbox while overriding its persona, dimensions, model, and output format, and inherited an execution model that lost findings silently for months (#70, #72).

## Methodology credits

These plugins' *methodologies* were inlined into reviewer prompts. They are **never spawned** and are **not dependencies**; `/jr-doctor` does not check for them and their absence changes nothing.

- `pr-review-toolkit@claude-plugins-official` — silent-failure-hunter → error-handling, type-design-analyzer → typescript, code-simplifier → Phase 5.5, comment-analyzer → comment, pr-test-analyzer → testing.
- `security-scanning@claude-code-workflows` — STRIDE methodology → security-reviewer (large/full audits).

## Key design decisions

- `/jr-skill-audit` is the *opinionated* meta-audit counterpart to `/jr-doctor`'s narrow factual checks (Group I). `/jr-doctor` answers "is this skill objectively broken?" via yes/no file reads; `/jr-skill-audit` answers "what could be better?" via 7 reviewer dimensions (frontmatter, advisor-coverage, token-efficiency, shared-drift, feature-adoption, safety-protocols, model-routing) plus a lead-synthesized `scope-resolution` dimension that fires on personal/project shadow collisions. Reviewers cite **live Anthropic documentation** — the skills doc and the claude-code CHANGELOG are fetched at Phase 1 Track C and cached at `jr-skill-audit/cache/refs.json` (7-day TTL, `--refresh-refs` to force, stale-cache fallback when offline). Phase 3 sanity-check validates every finding's `source` citation against the cache so reviewers can't hallucinate features. Phase 4 has a [Clarify] sub-flow for `clarify: true` findings — judgment-call recommendations are surfaced via `AskUserQuestion` so the user resolves workflow-dependent calls in-line rather than at the end. Findings-only in v1 — no auto-fix, no Phase 5/6. Skill files are markdown specifications without a test harness. Scope: personal `~/.claude/skills/*/SKILL.md` + project `<walked-dir>/.claude/skills/*/SKILL.md` (walks from CWD up to repo root, matching Claude Code runtime semantics), excluding gitignored / externally-maintained skills like `find-skills/` — Phase 1 Track B drops them. **Auto-scope default**: an unfiltered run from a git repo other than the skills repo, when that repo has its own skills, audits project ALONE — only project scope depends on `$PWD`. Personal is still enumerated, so shadow detection fires. Overrides, the auto-narrow fallback, and edge cases: `jr-skill-audit/protocols/personal-project-scope.md` (canonical). Same-name collisions across scopes emit a `medium`/`clarify:true` `scope-resolution` finding (lead-synthesized, not a reviewer dimension). Plugin skills out of scope (tracked in issue #18).
- `/jr-audit` and `/jr-review` share the same cache files and stack detection logic (Track C). Changes to one skill's caching format must be mirrored in the other.
- Both `/jr-audit` and `/jr-review` support `--converge[=N]`: a re-review loop that wraps Phases 2–6 in a repeatable cycle with auto-approval. Both default effort-adaptively from `CLAUDE_EFFORT` (`low`/`medium` → 2, `high` → 3, `xhigh`/`max` → 5). `/jr-review` caps at 10 and runs a fresh-eyes security pass after convergence. `/jr-audit` caps at 5 — lower because the per-iteration blast radius is higher.
- `/jr-review` supports `--branch[=<base>]` for reviewing the full feature-branch diff (committed-on-branch + working tree) as one scope — closes the gap between bare `/jr-review` (working tree only, misses committed work) and `--pr=N` (remote read-only, misses unpushed/uncommitted work). Default `<base>` resolves via `gh pr list --head` (linked PR) or falls back to `origin/<default-branch>` via `gh repo view`. Aborts if local HEAD is behind upstream — local files must reflect HEAD for codeExcerpt verification to be safe. Mutually exclusive with `--pr`. Implementer + validation run normally (fixes apply locally); Phase 8 creates standalone issues, NOT a PR comment.
- `/jr-ship` handles both single-PR and multi-PR (stacked/independent) flows. Split analysis uses semantic grouping heuristics with dependency detection between groups. On CI failure (single-PR step 13, multi-PR 11a-multi) it invokes the **CI-failure handling** procedure — an `opus` sub-agent diagnoses the failure from its own log fetch and proposes a fix, the user confirms before it is committed + re-pushed, then CI is re-watched (max 2 fix cycles). This runs in all modes; `--merge` differs only in that it proceeds to merge once CI is green. After PR creation (single-PR step 11a, multi-PR step 10a-multi), `/jr-ship` runs the **file-overlap check** (canonical procedure: `jr-ship/protocols/overlap-check.md`) — one `gh pr list --json files` call enumerates currently-open PRs and intersects their file sets with this PR's (or batch's). The check is informational only — it never blocks, never asks, and any failure is logged with `Overlap check skipped: <reason>` and falls through. Opt out per-run with `--no-overlap-check`. Runs on every PR-creating invocation including `--draft` and `--merge` resume mode (a resume can happen days after the original ship, and new overlaps may have appeared in the interim).
- Auto-learned suppressions (Phase 4.5 in jr-audit/jr-review) require 2+ rejections of the same pattern before adding a rule — single rejections are treated as situational. Cross-run promotion to user-global memory needs 2+ rejections in 2+ separate runs (lowered from the original 3+ which empirically never fired).
- Shared protocol files (`shared/*.md`) are validated at Phase 1 with a hard-fail guard PLUS a structural smoke-parse (each file must contain a known load-bearing substring) — catches truncation that the non-empty check misses.
- **Claim verification doctrine** (`shared/claim-verification.md`): closes the gap between *citation integrity* (the `codeExcerpt` sanity-check proves a cited line exists) and *claim correctness* (whether an external-authority assertion about that line — deprecation, version behavior, CVE, WCAG/OWASP — is actually true). The lead classifies findings independently at Phase 3 step 0.5 and **by default** verifies external-authority claims by fetching an authoritative source (Tier 2; raw `.md`/`gh api`, never a lone WebFetch, per the known fabrication risk) — keeping confirmed ones and rejecting refuted ones under `[REJECTED — CLAIM REFUTED BY SOURCE]`; only a claim it can't verify (offline, uncorroborable, or `--no-verify-claims`) is capped to `speculative` and routed/deferred, never auto-applied (Tier 1 fallback). `/jr-skill-audit`'s live refs-cache is the reference Tier-2 implementation. Wired into `/jr-audit`, `/jr-review`, `/jr-skill-audit`; cross-ref'd by `/jr-ship` (CI-fix diagnosis grounding) and `/jr-tackle` (rigor protocol). `/jr-doctor` Group D smoke-parses the new shared file automatically via the Canonical Anchor Table.
- `/jr-audit` Phase 1 Track B uses lazy-load by default (reviewers fetch files on demand). Use `--prefetch` to restore the original pre-read behavior for ≤ 50-file scopes.
- `/jr-review --pr` mode runs the `codeExcerpt` content match against the PR's post-image fetched via `gh api`, NOT the local checkout — so the hallucination guard works even when the local branch differs from the PR base. `/jr-review --branch` mode reads from the local working tree (the Phase 1 behind-upstream abort guarantees local files reflect HEAD; bare `/jr-review` and `--branch` share the same local-Read path).
- `/jr-review --pr` accepts a bare iid OR a full GitHub PR / GitLab MR URL (canonical: `jr-review/protocols/pr-url-mode.md`, read at Phase 1 only when the value contains `://`, before forge detection + tracks). The URL host pins the forge (overriding `CLAUDE_FORGE` + origin detection) and its project is guarded against the current repo: same-project runs full-fidelity; a different project aborts with a `cd` hint. Off-repo review is **GitLab-only** via `--allow-remote` (degraded cross-file analysis, surfaced as a warning + report caveat); a GitHub PR URL for a different repo always aborts (GitHub is accepted in-repo only, keeping the surface small and avoiding an unverified off-repo GitHub path). Parsing reuses `bin/tackle`'s URL regexes + `_validate_owner_repo` allowlist. On GitLab this also completes the pre-Milestone-2 `--pr` path: the glab `-F json` head-SHA (`.sha`), changed-files (`/diffs` → `.[].new_path`), title/body, and the subgroup raw-file API are verified against a live MR (`shared/forge-detection.md` §c), so the same change also repairs bare `--pr=<iid>` on GitLab.
