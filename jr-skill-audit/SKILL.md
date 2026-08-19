---
name: jr-skill-audit
description: Audit Claude Code skill files (SKILL.md) for 2026-feature alignment, advisor coverage, frontmatter validity, token efficiency, shared-file drift, safety-protocol consistency, and model-tier routing. Reviewers cite live Anthropic docs + changelog (fetched at runtime, cached) so findings are grounded, not hallucinated. Reports a prioritized improvements list with file:line citations. Findings-only — never modifies skill files.
argument-hint: "[skill-name] [--scope=<glob>] [--scope-only=personal|project|both] [--plugin=<name>] [--only=<dims>] [--model=<tier>] [--auto-approve] [--refresh-refs] [--report] [--report-path=<path>]"
effort: max
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Write(~/.claude/skills/jr-skill-audit/cache/**) Write(.claude/skill-audit-*) Write(~/.claude/skill-audit-reports/**) Glob Grep WebFetch AskUserQuestion Agent advisor Bash(grep *) Bash(wc *) Bash(ls *) Bash(jq *) Bash([ *) Bash(head *) Bash(date *) Bash(basename *) Bash(dirname *) Bash(command -v *) Bash(realpath *) Bash(git -C * check-ignore *) Bash(git -C * rev-parse *) Bash(git -C * ls-files *) Bash(gh api repos/anthropics/claude-code/contents/CHANGELOG.md *) Bash(base64 *) Bash(mkdir -p *) Bash(mv ${CLAUDE_SKILL_DIR}/cache/*) Bash(mv .claude/skill-audit-*) Bash(mv ~/.claude/skill-audit-reports/*)
disallowed-tools: Edit
---

<!-- Frontmatter rationale (model/effort/allowed-tools/disallowed-tools): see
     docs/skill-anatomy.md "Grant and model rationale, by skill" -> /jr-skill-audit. Read it before
     changing any frontmatter field here.
     `effort: max` is PINNED, downstream effects: Phase 2, "No effort-adaptive overlay".
     `allowed-tools` is minimised to what the body and its `protocols/*.md` actually issue; 12
     unexercised grants were removed. The two `[` sites are `protocols/personal-project-scope.md:10`
     (scope predicate) and `protocols/plugin-scope.md:27` (repo-root guard). Do not re-add a grant without
     a body site needing it: sed/awk in particular reopen the file-mutation path `disallowed-tools: Edit` closes. -->

<!-- Dependency manifest (agent types, CLI, files read/written, shared-protocol inventory, tool
     grants): see DEPENDENCIES.md. Design rationale behind the rules below: protocols/rationale.md.
     Neither is read at runtime. Phase 1 Track A below is the authoritative read list. -->

Audit Claude Code skill files (`SKILL.md`) for quality, 2026-feature alignment, and drift against the canonical `shared/*.md` protocols. Reviewers cite **live Anthropic documentation** (skills doc, env-vars doc, release notes) fetched at runtime so findings stay current as Claude Code ships new features. **Findings-only** — never modifies skill files. Complements `/jr-doctor`'s narrow factual drift checks (Group I) with opinionated, dimension-scoped review.

**Arguments**: $ARGUMENTS

Parse arguments as space-separated tokens. Recognized flags:
- `[skill-name]` — Bare positional. Limits the audit to a single skill (e.g., `/jr-skill-audit review`). Resolved against personal (`~/.claude/skills/<name>/SKILL.md`) AND project scope roots (`<walked-dir>/.claude/skills/<name>/SKILL.md` for each dir from CWD up to the repo root). If `<name>` matches in both scopes, both are audited (no "primary" — the shadow-detection finding flags the collision).
- `--scope=<glob>` — Limits audit to skills whose directory name matches the glob (e.g., `--scope=*-reviewer`, `--scope=audit*`). Glob applies within whichever scope(s) survive the scope filter; used on its own it overrides the auto-scope default and matches across both. Mutually exclusive with the bare positional.
- `--scope-only=<level>` — Pin the scope explicitly, overriding the auto-scope default. Values: `personal` (only `~/.claude/skills/`), `project` (only `<CWD>/.claude/skills/` and parents up to repo root), or `both`. **Default is auto**: an unfiltered run from a git repo other than the personal skills repo, when that repo has skills of its own, audits `project` only — standing in a repo means auditing that repo's skills, and a personal audit is CWD-independent so including it there is pure duplication. Everywhere else (the skills repo, a non-repo dir, a repo with no skills) the default stays `both`, which is personal-only when project scope is empty. A bare positional or `--scope=<glob>` also overrides auto. Use `--scope-only=both` from a foreign repo to audit personal alongside it. Canonical rule: `protocols/personal-project-scope.md`.
- `--plugin=<name>` — Audit a third-party plugin's skills instead of your own. Resolves `<name>` to its **git-backed marketplace clone** under `~/.claude/plugins/marketplaces/` (the version-controlled upstream source — not the non-git `cache/` install) and audits the git-tracked skills there. Read-only and advisory: plugin skills are owned by the plugin author, so every finding is tagged `[third-party]`. Opt-in — bare `/jr-skill-audit` never touches plugins. Mutually exclusive with `--scope-only`; composes with a bare skill name OR `--scope=<glob>` to narrow which of the plugin's skills are audited.
- `--only=<dims>` — Run only the specified reviewer dimensions (comma-separated). Valid values: `frontmatter`, `advisor-coverage`, `token-efficiency`, `shared-drift`, `feature-adoption`, `safety-protocols`, `model-routing`. Example: `--only=frontmatter,token-efficiency`. **Note**: `scope-resolution` (the lead-emitted shadow-detection finding) is NOT in this enum — it always fires when name collisions exist, since it runs before reviewer dispatch. Users dismiss intentional shadows via the Phase 4 [Clarify] flow.
- `--auto-approve` — Skip the Phase 4 approval gate. Lists all findings in Phase 7 without filtering. Useful for CI / scripted reports. Skips the [Clarify] flow too — `clarify`-flagged findings render in their original tier with a `[CLARIFICATION SKIPPED — auto-approve]` qualifier.
- `--refresh-refs` — Force a fresh Phase 1 Track C fetch even if `cache/refs.json` is within its 7-day TTL. Use after Anthropic publishes a release that adds substitution variables, frontmatter fields, or skill features.
- `--model=<tier>` — `sonnet|opus|haiku|fable`; overrides every subagent spawn (`../shared/model-override.md`). Not the lead: this skill's frontmatter `model:` wins, and a session `/model <tier>` does not work around that.
- `--report` — Also write the rendered Phase 7 report to an archival markdown file (opt-in; default is console-only). Path is chosen by `effectiveScope` (canonical: `protocols/report-write.md`): **project** scope writes to the audited repo's `<repo-root>/.claude/skill-audit-<date>.md`; **personal**/**both** and **`--plugin`** runs write to `~/.claude/skill-audit-reports/skill-audit-<scope>-<date>.md` (outside any repo). The archival write is not fully pre-authorised in any scope: the atomic rename that completes it matches none of the frontmatter `mv` grants (`protocols/report-write.md` "Atomic write"), so it prompts once interactively, and under `--auto-approve`/headless, where nothing can prompt, the write is skipped (non-fatal). For an unattended archival write, add your own `permissions.allow` rules covering the resolved report path. A write failure never aborts the run (the console report is the record). Applies `shared/gitignore-enforcement.md` (advisory) when the resolved path lands inside a git repo.
- `--report-path=<path>` — Write the report to `<path>` instead of the default (implies `--report`). Accepts an absolute, `~/`-relative, or `$PWD`-relative path, and may point outside the repo; a value naming an existing directory or ending in `/` receives `skill-audit-<date>.md` inside it. Sanitized per Parameter sanitization. Not pre-authorised by the skill — relies on your `permissions.allow` settings or a per-call Write prompt (mirrors `/jr-audit`'s `--out`).

**Examples**: `/jr-skill-audit`, `/jr-skill-audit review`, `/jr-skill-audit --scope=*-reviewer`, `/jr-skill-audit --scope-only=project`, `/jr-skill-audit --scope-only=both`, `/jr-skill-audit --plugin=agent-teams`, `/jr-skill-audit --only=frontmatter,advisor-coverage`, `/jr-skill-audit --auto-approve`, `/jr-skill-audit --refresh-refs review`, `/jr-skill-audit --report`, `/jr-skill-audit review --report-path=~/reports/skills.md`

### Flag conflicts

- `[skill-name]` + `--scope=<glob>` — Conflict. Both narrow the skill set; pick one. Abort with: `Cannot combine bare skill name and --scope. Use one or the other.`
- `--scope-only=personal` + bare positional `<name>` resolving only in project — Conflict. Abort with: `Skill <name> not found in personal scope (exists in project: drop --scope-only or use --scope-only=project).` Symmetric for `--scope-only=project` when `<name>` is only personal.
- `--scope-only` + `--scope=<glob>` — Allowed. The glob narrows within the kept scope(s).
- `--scope-only` + `--auto-approve` — Allowed.
- `--plugin=<name>` + `--scope-only` — Conflict. `--plugin` selects its own (plugin) scope; `--scope-only` selects among personal/project. Abort with: `Cannot combine --plugin with --scope-only.`
- `--plugin=<name>` + bare positional `<skill>` OR `--scope=<glob>` — Allowed (subject to the existing bare-vs-`--scope` exclusivity above); narrows which of the plugin's skills are audited.
- `--plugin=<name>` + `--auto-approve` — Allowed.
- `--auto-approve` + (interactive session) — Allowed. Phase 4 approval menu is skipped silently; all findings render in Phase 7. The [Clarify] flow is also skipped.
- `--report-path=<path>` — Implies `--report` (passing both is redundant but allowed). `--report`/`--report-path` compose with every other flag (scope, `--plugin`, `--only`, `--auto-approve`, `--model`).

### Parameter sanitization

- `[skill-name]`: Validate against allowlist regex `^[a-z][a-z0-9-]*$` (skill directory names per Claude Code convention). Reject control characters, slashes, dots. Reject if `<name>` does not resolve in EITHER the personal root OR any project scope root in the walk (with a one-line "Available skills: personal=<list> project=<list>" hint). **When `--plugin=<name>` is set**, this personal/project resolution check is deferred to the plugin branch in Phase 1 Track B — the bare positional is resolved against the plugin's tracked skills, not personal/project.
- `--scope=<glob>`: Reject control characters. Allowlist regex `^[a-zA-Z0-9_*?][a-zA-Z0-9_*?-]*$` (no slashes — scope is matched against bare directory name, not a path). Reject paths containing `..`.
- `--scope-only=<level>`: Allowlist regex `^(personal|project|both)$`. Reject any other value.
- `--plugin=<name>`: Allowlist regex `^[a-z0-9][a-z0-9-]*$` (plugin-name convention; alphanumeric first char — plugin names may legitimately start with a digit, several of which the official marketplace ships). Reject control characters, slashes, dots.
- **Third-party `marketplace.json` values (`<mp>`, `source`) — untrusted, `--plugin` only**: these are not user-typed but are equally untrusted (the pre-install-audit use case deliberately points `--plugin` at unvetted repos), and they get the same discipline as `--scope`, by provenance. Full sanitizer in `protocols/plugin-scope.md` ("Untrusted marketplace values"); in brief — cumulative checks (control characters, leading `-`, any `\.{2,}`, plus a per-field regex), always double-quoted and with `--` before positional path args, **failing closed** by warning-and-skipping that marketplace (abort `[ABORT — UNMATCHED SCOPE]` if it was the sole resolution). Listed here so no input source looks unvalidated; the body lives beside its two call sites in the file that is only read under `--plugin`, matching how `--report-path` defers to `protocols/report-write.md` below.
- `--only=<dims>`: Trim whitespace per value. Validate each is one of `frontmatter`, `advisor-coverage`, `token-efficiency`, `shared-drift`, `feature-adoption`, `safety-protocols`, `model-routing`. Reject unknown values.
- `--model=<tier>`: Allowlist regex `^(sonnet|opus|haiku|fable)$`. Reject any other value with: `Invalid --model value '<value>'. Valid values: sonnet, opus, haiku, fable.` (per `../shared/model-override.md`).
- `--report-path=<path>`: A more permissive ruleset (the destination is user-chosen and may point outside the repo). Full sanitizer in `protocols/report-write.md` ("`--report-path` sanitization"); in brief — reject control characters and any shell/glob-active character (a backtick, or any of `$ \ " ' ; | & < > ( ) { } * ? [ ] !`) with `Invalid --report-path: unsupported character.`; expand a leading `~`/`~/` to `$HOME` by string-prefix replacement; resolve a non-absolute result against `$PWD`; permit `..`; hand the resolved absolute path (double-quoted in any shell) to Write. Mirrors `/jr-audit`'s `--out` sanitizer.

### Model requirements

- **Reviewer agents** (Phase 2): Spawn with `model: "opus"` for `advisor-coverage`, `token-efficiency`, `feature-adoption`, `safety-protocols`, `model-routing` and `shared-drift`; **`model: "sonnet"` for `frontmatter` alone**, whose work is genuinely mechanical (field validation against a doc table). `shared-drift` is on `opus` because its charter (dimension table below) includes recognising **inline duplicates** of canonical prose and judging where a shared file *applies* — semantic comparison across two documents, not anchor-substring presence. **The 25%-rejection escalation does NOT guard this tier split**: Phase 3 step 4 counts only genuine rejections among findings a reviewer actually *reported*, whereas an under-powered tier fails as false negatives that never enter that numerator. If you lower a dimension's tier, verify it by differential (re-run at `--model=opus` and compare finding counts), not by watching the rejection rate. **The `frontmatter` differential was run (2026-08-14): sonnet 0, opus 3 — but opus re-confirmed every mechanical check clean, and all 3 were semantic/cross-referential findings outside the charter. Verdict: `sonnet` stays correct for the charter as written; the charter is what is now under-scoped. Full result and its consequence: `protocols/rationale.md` "`frontmatter` tier differential".** A `--model` override, when set, replaces the tier for **every** reviewer regardless of dimension (`../shared/model-override.md`). Each reviewer receives the full `SKILL.md` content, the inline dimension scope, the `shared/untrusted-input-defense.md` block verbatim, the severity/confidence rubric sections of `shared/reviewer-boundaries.md` verbatim, and the **per-dimension reference excerpt** from Track C (see Phase 2). Reviewers do **not** receive the live skill's runtime context — they read the file as a specification document, not as executable behavior.
- **All other phases**: Default model is fine — discovery, dedup, reporting are mechanical. Any agent spawned in these phases also honors a `--model` override (the override is total, not premium-sites-only).

## Display protocol

Common rules — phase headers (`━━━`), running cumulative timeline, silent-reviewers/noisy-lead pattern, compact reviewer progress table — are in `../shared/display-protocol.md` (read into lead context at Phase 1 Track A; hard-fail guard ensures it was non-empty and structurally valid). Apply those verbatim. The Phase 4 finding-approval menu and the [Clarify] sub-flow below are `/jr-skill-audit`-specific and stay inline.

## Phase 1 — Discover skills + load shared protocols + fetch live refs

Run **three tracks in parallel**:

### Track A — Read shared protocol files

Read **all** shared files in parallel using multiple Read tool calls in a single message:
- `../shared/reviewer-boundaries.md` — severity + confidence rubrics. Skill-audit dimensions are inline below.
- `../shared/untrusted-input-defense.md` — passed verbatim into every reviewer prompt.
- `../shared/display-protocol.md` — applied at every console-output site.
- `../shared/abort-markers.md` — applied at Phase 7 if an abort fires.
- `../shared/advisor-criteria.md` — passed verbatim to `advisor-coverage-reviewer` as canonical advisor-call rules.
- `../shared/gitignore-enforcement.md` — passed to `safety-protocols-reviewer` so it can flag missing applications of the protocol in audited skills; ALSO applied lead-side at Phase 7 `### Save report` for the `--report` archival write.
- `../shared/secret-scan-protocols.md` — passed to `safety-protocols-reviewer` so it can verify an audited skill references the correct secret-scan tier semantics (strict/advisory classification, demotion criteria) where applicable.
- `../shared/claim-verification.md` — anti-hallucination doctrine; skill-audit's Track C live-refs + Phase 3 source-citation validation are its reference **Tier 2** implementation (see the Track C "Doctrine anchor" note).
- `../shared/phase1-track-a-protocol.md` — algorithm + Canonical Anchor Table consumed by the structural smoke-parse below.
- `../shared/model-override.md` — `--model=<tier>` subagent model-override semantics, applied at the Phase 2 reviewer spawns.
- `../shared/subagent-reporting.md` — the reviewer→lead channel. Its **Subagent-facing block** is passed verbatim into every reviewer prompt at Phase 2; its **roll-call** is applied by the lead at Phase 3.

**Hard-fail guard**: if any shared file fails to Read, returns empty content, or fails the structural smoke-parse below, abort Phase 1 immediately with `[ABORT — SHARED FILE MISSING]` (per `../shared/abort-markers.md`) and exit non-zero. Do NOT fall back to inline text.

**Structural smoke-parse** (mandatory, after non-empty Read): apply the smoke-parse algorithm and Canonical Anchor Table from `../shared/phase1-track-a-protocol.md` — each row of the canonical's table lists the required substrings for one shared file (case-sensitive, `grep -F` semantics, AND-joined within a row). **Self-reference escape hatch (hardcoded)**: before parsing the canonical's table, verify `../shared/phase1-track-a-protocol.md` itself contains the literal string `Canonical Anchor Table` — a stub corruption of the canonical that preserves only its self-row anchor would otherwise pass the table-driven check. If any file fails the smoke-parse (self check OR any row check), abort Phase 1 with `[ABORT — SHARED FILE MISSING]` as above.

**Skill-local protocol files (conditional — exactly one per run)**: when `--plugin=<name>` is set, also Read `${CLAUDE_SKILL_DIR}/protocols/plugin-scope.md` into lead context (parallel with the shared files above) and apply the same hard-fail + non-empty + smoke-parse discipline — abort with `[ABORT — SHARED FILE MISSING]` if it is absent, empty, or fails its anchors `Locate the marketplace` AND `Enumerate git-tracked skills` (case-sensitive `grep -F`). When `--plugin` is NOT set, Read `${CLAUDE_SKILL_DIR}/protocols/personal-project-scope.md` instead (same discipline; anchors `Scope roots` AND `Gitignore exclusion`) — the two are mutually exclusive, so exactly one is read per run (mirrors `/jr-review`'s conditional `convergence-protocol.md` read under `--converge`).

**Skill-local phase-body files — body load deferred to point of use, NOT read at Track A.** Each is read at the phase that applies it, under the same hard-fail + non-empty + smoke-parse discipline (abort `[ABORT — SHARED FILE MISSING]` per `../shared/abort-markers.md` if absent, empty, or failing its anchors, case-sensitive `grep -F`). Deferring matches how `report-write.md`, `plugin-scope.md` and `shadow-detection.md` are already handled. What is deferred is the **body load**; one of the two also carries a Phase 1 presence check that costs no context, per its entry below.
- `${CLAUDE_SKILL_DIR}/protocols/finding-validation.md` — anchors `Contain before opening` AND `Source-citation validation`. Read **at Phase 3, before step 1**. Holds the step 1 + step 2 bodies (`file` containment, `codeExcerpt` sanity-check, source-citation validation). **No Phase 1 presence check, an accepted trade-off**: a missing or truncated copy surfaces *after* the reviewer swarm has been paid for, rather than before dispatch. That is the cost of the budget saving, and it is bounded: the abort is still a hard fail, so a corrupt file never degrades silently into a partial run.
- `${CLAUDE_SKILL_DIR}/protocols/phase7-report.md` — anchors `Findings Report` AND `Summary: N findings across M skills`. Read **at Phase 7, before rendering**. Holds the findings-report template. **Presence IS verified here at Phase 1 Track A, WITHOUT loading the body** (grep-guard; the pattern `/jr-review` and `/jr-ship` already use for their deferred protocols): run `grep -Fq` for each of the two anchors above against the file. If either fails (file absent, empty, or the anchor missing: all three make `grep -Fq` exit non-zero), abort Phase 1 with `[ABORT — SHARED FILE MISSING]` (`abortReason="shared-file-missing"`), before any reviewer is dispatched. `grep` alone suffices, so no separate existence probe is needed. Use `grep -F`, **not** a line-anchored `grep -E`: the title line is indented inside that file's fenced template, so `^Findings Report` would never match; a plain substring match is safe here because its header deliberately does not restate its own anchors, so a body-stripped truncation cannot false-pass. Why this file does not take its sibling's trade-off: it is the **only** render path for the run's deliverable, so its failure mode is not late detection but **total loss**. Discovering it broken at Phase 7 has already bought seven `opus` reviewers plus Phase 3 validation and Phase 4 approval, and then renders nothing, with no second path to fall back on; under `--auto-approve` the run would end with nothing shown and nothing written. The Phase 7 Read still applies the full guard; this is a cheap early duplicate of it, not a replacement.

**Skill-local report-write file (conditional — only when `--report` or `--report-path` is set)**: Read `${CLAUDE_SKILL_DIR}/protocols/report-write.md` into lead context (parallel with the shared files above) under the same hard-fail + non-empty + smoke-parse discipline. Abort with `[ABORT — SHARED FILE MISSING]` per `../shared/abort-markers.md` if it is absent, empty, or fails its anchors `Derive the report path` AND `Atomic write` (case-sensitive `grep -F`). It holds the Phase 7 `--report` archival write procedure (path derivation, dynamic gitignore-enforcement, atomic write, non-fatal failure, and `--report-path` sanitization), applied at Phase 7 `### Save report`. Skip the read entirely when neither report flag is set (mirrors the conditional `plugin-scope.md` read above).

### Track B — Discover skill targets

Enumerate skill directories matching the argument set, across personal and project scopes.

**Plugin scope** (when `--plugin=<name>` is set): short-circuit the personal/project discovery below and follow the plugin-scope resolution procedure (marketplace location, git-tracking enumeration, symlink/containment canonicalization, tagging) in `${CLAUDE_SKILL_DIR}/protocols/plugin-scope.md` — read into lead context at Phase 1 Track A **only when `--plugin` is set** (mirrors how `/jr-review` reads `convergence-protocol.md` only under `--converge`). On success it tags each surviving target `scope=plugin` and skips to "For each surviving target" below; the personal/project discovery, gitignore filtering, and shadow detection are all bypassed (plugin scope is exclusive).

**Personal/project scope** (when `--plugin` is NOT set): follow the discovery procedure in `${CLAUDE_SKILL_DIR}/protocols/personal-project-scope.md` — read into lead context at Phase 1 Track A under the non-`--plugin` conditional (hard-fail + non-empty + smoke-parse anchors `Scope roots` AND `Gitignore exclusion`; abort `[ABORT — SHARED FILE MISSING]` per `../shared/abort-markers.md` if absent/empty/invalid; the complementary conditional to `plugin-scope.md`). It computes the scope roots and the auto-scope default, enumerates and tags SKILL.md candidates, applies the argument-set then scope filters (cross-scope conflict probe between), resolves a bare positional, drops gitignored skills per scope, and applies the auto-narrow fallback. It returns the surviving target set plus `effectiveScope`, `autoNarrowed`, `autoNarrowFallbackFired`, `excludedCandidates`, and the canonicalized roots — consumed by the `Scope:` line, the Empty-discovery guard, the Phase 7 `Roots:` line, and Phase 3 step 1a's containment.

For each surviving target, read the `SKILL.md` plus enumerate `<skill>/scripts/*.sh` and `<skill>/templates/*` as supplementary inputs (existence + executable bit only — content reads only when a reviewer cites them). For plugin scope these paths are under the resolved `~/.claude/plugins/marketplaces/<mp>/<source>/`.

**Empty-discovery guard**: if zero skills resolve (e.g., `--scope=foo*` matches nothing, `--scope-only=project` from a dir with no `.claude/skills/` in the walk, or `--plugin=<name>` whose marketplace is non-git or whose `<source>/skills/` has no tracked SKILL.md), abort with `[ABORT — UNMATCHED SCOPE]` per the canonical mapping. The abort message includes the active `--scope-only`, `--plugin`, or `--scope` value (if set) so the user can correct or drop the argument and retry — a mistyped glob must report the glob that matched nothing, not a scope diagnosis. An auto-scope narrowing can never reach this guard with candidates still standing (the auto-narrow fallback in `protocols/personal-project-scope.md` un-narrows first), so reaching it on a **fully unfiltered run** — no `--scope-only`, no `--plugin`, no `--scope`, no bare positional — means nothing survived in either scope; say that, rather than naming an argument the user never passed.

**Report the cause, not just the absence.** On a **fully-unfiltered** run only, branch on `excludedCandidates` (returned by `protocols/personal-project-scope.md`), keeping `abortReason="unmatched-scope"` on both branches. With any filter present the argument-naming rule above owns the message instead. Rationale: `protocols/rationale.md` "Empty-discovery guard".
- **Excluded count > 0**: name them, e.g. `Nothing auditable: N skill(s) found but all excluded as gitignored (externally maintained): <names with [personal]/[project] tags>.` Externally-maintained skills are not repo-owned, so this is a scope outcome the user can act on, not a missing-file error.
- **Excluded count == 0**: the enumeration really was empty; keep the flat "nothing is auditable in either scope" wording.

### Track C — Live Anthropic references (cached with TTL)

Reviewers cite live documentation so findings stay current as Claude Code ships features. The cache lives at `${CLAUDE_SKILL_DIR}/cache/refs.json` with a 7-day TTL.

**Read `${CLAUDE_SKILL_DIR}/protocols/refs-cache.md` into lead context now, at Track C entry**, under hard-fail + non-empty + smoke-parse — anchors `Cache schema` AND `Same rule per key` (case-sensitive `grep -F`); abort `[ABORT — SHARED FILE MISSING]` per `../shared/abort-markers.md` (`abortReason="shared-file-missing"`) if it is absent, empty, or fails either anchor. It carries this whole track and is applied verbatim: the `.gitignore` advisory probe on the cache path (applied on entry, **before** the refresh logic branches, so both arms are covered), the cache schema, the refresh trigger + procedure, the content-shape assertions that gate every load path, both fallbacks, the per-key usability rule, and the per-dimension reference-excerpt allocation consumed at Phase 2.

> **Doctrine anchor**: this cache plus Phase 3 step 2 are the reference **Tier 2** implementation of `../shared/claim-verification.md`. Always-on, no opt-out. Outcome mapping: cached key with `ok:true` (or a confirmed `changelog:`/shared-file line) → `confirmed`; `[REJECTED — citation broken]` → `refuted` (dropped); source missing, uncached, or outside the finding's own skill directory → **`unverifiable`** — capped to `speculative` but **still rendered** in its original tier tagged `[unverified — needs confirmation]`, with a note in `Audit integrity`. Unverifiable ≠ dropped; see `protocols/finding-validation.md` "What a routing actually does to the finding".

### After all tracks complete

**Shadow detection (lead-side synthesis)**: group the **enumerated** discovery candidates by directory basename — the set *before* the argument-set filter, the scope filter, **and gitignore exclusion** (all three exclusions are deliberate; see `protocols/rationale.md` "Shadow detection"). For each basename present in BOTH scopes the lead synthesizes one `scope-resolution` finding (spec: the "Shadow detection" subsection below), which flows into Phase 3 alongside reviewer findings. It fires even when only one side is audited, anchoring on the personal SKILL.md.

**Scope line** — the auto-scope default makes the same bare command audit different skills in different directories, so a run whose scope turned on `$PWD` MUST say so on its own line above the summary. Exactly one variant can fire (the fallback sets `autoNarrowed=false` at the same step it sets `autoNarrowFallbackFired=true`):

| Gate (never `autoScope` — it is a proposal, not the applied scope) | Print |
|---|---|
| `autoNarrowed=true` | `Scope: project (auto — <cwdRepoRoot> has its own skills; --scope-only=both to include personal)` |
| `autoNarrowFallbackFired=true` | `Scope: personal (<projectRoot(s)> has no auditable skills; falling back to personal)` |

Both flags are set by `protocols/personal-project-scope.md` at "Resolve `effectiveScope`". Take `projectRoot(s)` from the returned contract, never synthesised from `cwdRepoRoot`: the parent-walk means the empty root may sit below `cwdRepoRoot`, and `<cwdRepoRoot>/.claude/skills` need not exist at all.

Print a one-line summary. Omit scope segments that are empty (e.g., a personal-only run drops the `project=` segment, and `Shadowed: none` is omitted when both scopes have zero overlap):
```
Discovered N skill(s): personal=<p-list> project=<j-list>   |   Shadowed: <colliding-names>   |   Excluded (gitignored): <names with [personal]/[project] tags | "none">   |   M reviewer dimensions selected   |   Reviewer tier: <default (opus; sonnet for frontmatter) | Model override: <tier>>   |   Refs: <fresh|cached YYYY-MM-DD|partial (<missing-keys>)|stale|missing>
```

**`Reviewer tier:` is mandatory, never omitted**, on this line and on the `--plugin` variant `Discovered N skill(s): plugin=<name> (skills: <s-list>)   |   M reviewer dimensions selected   |   Reviewer tier: <…>   |   Refs: <…>`, which bypasses only the `personal=`/`project=`/`Shadowed:` segments. With `--model` set it renders `Model override: <tier>` per `../shared/model-override.md`'s display rule; otherwise it names the default split. Without it a `--model=haiku` run is indistinguishable from a default one in its own header and in any `--report` archive.

If a skill exceeds **60,000 characters** (`wc -c`, not `wc -l`), warn before dispatch: huge skills cost reviewer-token budget and review quality drops. Recommend the user narrow with `--only=<dims>` to focus on a single dimension first. Rationale: `protocols/rationale.md` "Token budget".

### Shadow detection (lead-side synthesis)

When the Track-B grouping above yields a basename present in both scopes, the lead synthesizes the finding directly — no Phase 2 reviewer agent is involved. The finding routes through Phase 3 (sanity-check + dedup) and Phase 4 ([Clarify] flow) like any other finding.

**Finding shape + rationale**: read `${CLAUDE_SKILL_DIR}/protocols/shadow-detection.md` on demand (only when a cross-scope collision is detected — not a Phase 1 Track A read, since most runs never need it). It carries the exact `scope-resolution` finding shape (anchor field, `clarify: true`, `source` as a `cache/refs.json` key, `scope: personal` as the runtime winner) and the design rationale.

**It IS guarded, unlike `edge-cases.md`.** Apply non-empty + smoke-parse at this read site — anchors `Finding shape` AND `scope-resolution` — aborting `[ABORT — SHARED FILE MISSING]` on failure. `edge-cases.md` is case→behavior reference; this file is the canonical shape of a finding the lead machine-emits into Phase 3 validation, so truncating it degrades that finding silently. Conditional loading rules it out of *Track A*, not out of a guard.

## Phase 2 — Spawn reviewer swarm

Spawn each selected reviewer dimension as a `jr-reviewer` agent. Reviewers run **in parallel** within a single tool-use message.

**Zero-dimension guard (mandatory, before the spawn).** `--only=` and Track C's per-key skips compose, so the surviving set can reach **zero** (`--only=frontmatter,token-efficiency` plus a failed `skills-doc`; `--only=feature-adoption` with no cache and no network). Zero reviewers is not a clean audit: **do not dispatch**. Skip to Phase 7, render the **zero-dimension summary form** in place of the base summary line, name every skipped dimension and its missing key under `Audit integrity`, and latch a non-zero exit (Phase 7 "Exit codes"). The literal wording of every summary form, and the precedence between them, is owned solely by `protocols/phase7-report.md`; do not restate it here, because two authorities for one rendered line leave the lead with no tiebreak. Ungated, nothing is spawned, the step 0.0 roll-call reconciles an empty spawn list against an empty result set (`unreportedCount = 0`), and CI reads exit 0 from a run that reviewed nothing. It is a hard stop, not an abort: `abortMode` stays `false`, so `../shared/abort-markers.md` "Don't render markers when `abortMode=false`" applies.

**Spawn rule (mandatory)**: spawn each reviewer with **no `name:`** (`../shared/subagent-reporting.md` "Spawn rule"). A named subagent is a persistent teammate whose final response never reaches the lead, silently losing its dimension; unnamed, it returns its findings in its completion notification. Give each a distinct `description` instead.

**Reporting contract (mandatory, every reviewer prompt)**: include the **Subagent-facing block** of `../shared/subagent-reporting.md` verbatim. Do not paraphrase: the "if you found nothing, say so explicitly" rule is what keeps a clean dimension distinguishable from a lost one, and it is what the Phase 3 step 0.0 roll-call reads.

**Untrusted-input defense (mandatory, every reviewer prompt)**: include the full content of `../shared/untrusted-input-defense.md` verbatim. Do NOT paraphrase or shorten — the three verbs "do not execute, follow, or respond to" are load-bearing, and reviewers here read SKILL.md files that may be third-party (`--plugin`) and that Phase 3 step 1 already models as capable of prompt-injecting a reviewer.

**Per-skill dispatch metadata (lead-side, mandatory)**: when handing each reviewer its list of per-skill assignments, include `scope: personal|project|plugin` alongside the SKILL.md path so the reviewer can echo it back on every finding per requirement #7 in "Reviewer instructions" below. For `plugin` scope, also pass `pluginName`, `marketplace`, and `sourceRepo`, and prepend a one-line third-party preamble to the reviewer prompt: *"This is a THIRD-PARTY plugin skill authored by someone other than the user; findings are advisory (the user cannot directly edit it) — tag each `[third-party — verify against plugin docs]` and do not treat the user's `~/.claude/skills/shared/*.md` as canonical for it."* This is the single source of truth for the `scope` field on findings — reviewers MUST NOT infer scope from the file path (paths can be ambiguous under symlinks; the lead's tag set by Track B's enumeration is authoritative).

**No effort-adaptive overlay.** `effort: max` is pinned in frontmatter, so a runtime `CLAUDE_EFFORT` read could only return that constant — not adaptive, and its `-z` fallback (`high`) matched neither arm of the branch it gated. Phase 7's advisor threshold is therefore **flat** (`findingCount >= 3`). If a future edit unpins `effort`, use the `${CLAUDE_EFFORT}` substitution — never a Bash read — and restate the threshold as concrete values, not an `e.g.`.

### Per-reviewer reference excerpts (token budget)

Each reviewer receives ONLY the references it needs (mirrors the principle "skills load on demand"). The per-dimension allocation table — which `cache/refs.json` key or `shared/*.md` file each dimension receives, and the `Refs: partial (<missing-keys>)` rule when a schema-declared key is absent — lives in `${CLAUDE_SKILL_DIR}/protocols/refs-cache.md` ("Per-reviewer reference excerpts"), already in lead context from the Phase 1 Track C read. Apply it when assembling each reviewer prompt below.

### Dimension table

| Dimension | Owns | Stays out of |
|-----------|------|--------------|
| `frontmatter-reviewer` | Required fields (`description` per [skills doc](https://code.claude.com/docs/en/skills)); allowed values for `effort` and `model` (verified against the live doc); contradictions (`disable-model-invocation: true` → `description` is NOT in context, making `when_to_use` and `paths` inert per the doc's invocation-control table); `description + when_to_use` exceeding the skill-listing cap — which is **`skillListingMaxDescChars`, user-configurable**, so report it as "exceeds the default" and never as a fixed breach; missing `name` falling through to directory-name fallback when explicit naming would aid clarity. **`model:` legality is not verifiable from the allotted refs** (the skills-doc delegates it to `model-config`, which is not a cached key) — own `effort` legality, and report `model:` as unverifiable rather than asserting it. | Body content (token-efficiency dimension); model-tier appropriateness (model-routing dimension). |
| `advisor-coverage-reviewer` | `advisor()` call sites against `../shared/advisor-criteria.md`: substantive-edit boundaries, declare-done points, stuck-loop signals; gating quality (single-fire guards, conditional triggers based on finding count or skewed dimensions); placement (before substantive work, not after). Each finding MUST cite the violated rule by `shared/advisor-criteria.md:<line>`. | Other call sites' specific phrasing (token-efficiency dimension). |
| `token-efficiency-reviewer` | Line count vs. live skills-doc 500-line tip; large inline blocks that should be `${CLAUDE_SKILL_DIR}/scripts/*` or `shared/*.md` extractions; per-phase prose density; redundant prose between phases; tables/code blocks that could collapse. **Skill content lifecycle** (the doc's section name): every line is a recurring token cost across the whole session — flag aggressively. | Frontmatter character cap (frontmatter dimension); model-tier cost (model-routing dimension). |
| `shared-drift-reviewer` | Inline duplicates of `shared/*.md` content (every duplicate proves the shared/ pattern isn't doing its job); missing references where shared files apply (e.g., subagent prompt without `untrusted-input-defense.md` reference); smoke-parse substring presence at every Read site of a shared file. | Whether the shared file itself is the right design (architecture concern, out of scope here). |
| `feature-adoption-reviewer` | 2026 substitutions used vs. **what the live skills-doc lists** (the full substituted set per the live skills-doc table: `\$ARGUMENTS`, `\$ARGUMENTS[N]`, `$N`, `$name`, `CLAUDE_SESSION_ID`, `CLAUDE_EFFORT`, `CLAUDE_SKILL_DIR`, `CLAUDE_PROJECT_DIR` — the last four named bare here, `\$ARGUMENTS`/`\$ARGUMENTS[N]` backslash-escaped so this cell is not itself substituted before the reviewer reads it. `$N` and `$name` are **in** the substituted set and survive unescaped here only incidentally: a literal `N` is not a digit, and this skill declares no `arguments:` frontmatter. A reviewer MUST still flag a skill that uses `\$0`/`\$1` or a declared `$name`); `allowed-tools` minimization (over-permissive grants like blanket `Bash(*)` without rationale); features adopted by Anthropic post-skill-creation that the skill could leverage (cross-reference the changelog). Every finding MUST cite the doc URL (`https://code.claude.com/docs/en/skills:<heading>`) or a changelog version (`changelog:<version>`). | Whether to add a feature at all if not present (advisor-coverage / token-efficiency may flag instead). |
| `safety-protocols-reviewer` | Untrusted-input defense at every subagent prompt site; gitignore-enforcement at every cache/audit-trail write site; secret-scan tier classification where applicable; explicit-consent gates on destructive operations; abort markers (and a mapped `abortReason`) on irrecoverable failures; **subagent-spawn correctness** — see the sub-section below the table. | Specific finding text in shared files (shared-drift dimension); spawn `model:` tier (model-routing dimension). |
| `model-routing-reviewer` | Model-tier appropriateness: frontmatter `model:` / `effort:` vs. the skill's actual workload — flag premium `opus` on a skill whose phases are predominantly mechanical (discovery / dedup / reporting / validation), or an under-powered tier on a heavy-reasoning skill; body-level subagent-spawn `model:` choices vs. the work each spawned agent does. Evidence is the skill's own phase descriptions; `source` cites `<skill>/<path>:<line>` as a self-contradiction within the same skill. Set `clarify: true` when premium tier is a defensible headroom choice. Canonical good shape: `docs/skill-anatomy.md` "Grant and model rationale, by skill" → `/jr-skill-audit`. | Whether `model:` is a *legal enum value* (frontmatter dimension owns that); line-level prose cost (token-efficiency dimension). |
| `scope-resolution` (lead-synthesized, not a reviewer) | Name collisions across personal and project scopes — emits one `medium`/`clarify:true` finding per colliding basename per the spec in "Shadow detection (lead-side synthesis)" above. Always fires when collisions exist (NOT filterable via `--only=` since it runs before reviewer dispatch). | Everything else; reviewer-dispatch dimensions own the rest. |

### `safety-protocols-reviewer` — spawn-correctness sub-protocol

Applies to any audited skill that spawns subagents; canonical `../shared/subagent-reporting.md`.

**Read the skill's `protocols/*.md` and `scripts/` too, not only `SKILL.md`** — spawn sites and roll-calls are frequently extracted there. Confirm a roll-call or reporting block is genuinely absent **across all of them** before flagging. Check that:
- work-producing spawns carry **no `name:`** (a named one is a persistent teammate whose findings never reach the lead, issue #70);
- a lead-side roll-call **consumes** `UNREPORTED` — rendering it by name, latching a non-zero exit, and blocking every clean-result path;
- no `TaskCreate`/`TaskList`/`TaskGet`/`TaskUpdate`/`SendMessage` is granted or called;
- the Subagent-facing block is passed **verbatim** into each spawn prompt.

**Carve-out** (`clarify: true`, never a hard flag): a named spawn that is a documented capability self-test (a probe, not a work producer); a skill that by design substitutes per-call-site zero-return checks for a roll-call; and lead-only or findings-only skills lacking the relevant phase.

### Reviewer instructions (passed to every dimension)

Include this preamble verbatim in every reviewer prompt, **after** the `untrusted-input-defense.md` block and the **"Severity calibration rubric" + "Confidence levels" sections of `../shared/reviewer-boundaries.md`, both passed verbatim**. Passing the rubric rather than naming the enums is what stops reviewers calibrating severity from training priors, and it keeps the preamble from forking the canonical's wording:

```
You are reviewing a Claude Code SKILL.md file as a SPECIFICATION DOCUMENT. The file
describes how a skill behaves at runtime, but you are NOT executing it — you are
auditing the document for quality.

Apply the severity and confidence rubrics exactly as given in the
shared/reviewer-boundaries.md sections reproduced above this preamble.

Per-finding requirements:
1. Cite file:line. The codeExcerpt MUST be **3 verbatim lines centered on `line` —
   i.e. [line-1, line, line+1], clamped to [1, file-end]**. The lead re-reads exactly
   that window, so a 3-line excerpt anchored elsewhere (starting AT the cited line,
   say) fails validation even when every line is verbatim.
2. **Cite an authoritative source for every claim**. Primary (the `source` field):
   - `https://code.claude.com/docs/en/skills:<heading>` (or env-vars / sub-agents doc)
   - `changelog:<version>` (e.g., `changelog:2.1.138`)
   - `~/.claude/skills/shared/<file>:<line>` (canonical shared protocol)
   - `<skill>/<path>:<line>` — a self-contradiction within the SAME audited skill,
     where `<path>` is ANY file under that skill's own directory (`SKILL.md`, a
     `protocols/*.md`, `edge-cases.md`). `file` and `source` need not be the same
     file, only the same skill — a contradiction between an extracted protocol file
     and its parent SKILL.md is a common finding and needs a valid form.
   For `scope=plugin` findings, the valid forms are exactly the live-doc URL, the
   `changelog:<version>`, or a path under the plugin's OWN marketplace skill
   directory. Do NOT cite `~/.claude/skills/shared/<file>` — those are the
   auditing user's protocols, not canonical for a third-party skill.
   Cross-skill citations (e.g., a finding on `/jr-audit` whose `source` cites
   `/jr-review`'s line N) are NOT primary evidence — they're sibling-skill conventions
   and may themselves drift. If a finding is grounded in a sibling skill, cite the
   underlying authority (live doc OR shared protocol) as `source` and mention the
   sibling skill in `description` as supporting context. Findings whose `source`
   is a sibling skill are routed to Audit integrity. Findings without any source
   citation are routed to Audit integrity so reviewer-quality issues surface
   rather than being silently dropped.
3. Stay within your dimension's ownership. If a finding belongs to another
   dimension, defer to that reviewer.
4. Calibrate confidence honestly. Use `speculative` when you cannot verify.
5. **Set `clarify: true` when the recommendation is genuinely workflow-dependent**
   (e.g., "this skill could use --converge but maybe your workflow doesn't need
   iterative refinement"). Provide a one-sentence `clarificationQuestion` the
   user can answer in Phase 4. Use sparingly: clarify is for judgment calls, not
   for findings you weren't sure about technically (use `speculative` for those).
6. Apply the rubric's own low-severity rule as written above; do not substitute a
   different threshold.
7. Set `scope` to `personal`, `project`, or `plugin` matching the audited
   SKILL.md's location. The lead injects this in your dispatch metadata; echo it
   back on every finding so the Phase 7 report can group by scope. When `scope`
   is `plugin`, additionally (a) tag every finding `[third-party — verify against
   plugin docs]` (these skills are owned by the plugin author; findings are
   advisory), and (b) echo back `pluginName`, `marketplace`, and `sourceRepo`
   exactly as provided in your dispatch metadata — the Phase 7 report needs
   `marketplace` to disambiguate same-named skills across marketplaces.
```

### Finding format

Every finding travels in the reviewer's final response, which the lead receives in its completion notification (`../shared/subagent-reporting.md`), and must include:
- `file` (absolute path)
- `line` (positive integer)
- `dimension` (one of the 7 reviewer dimensions above; `scope-resolution` is lead-only)
- `severity` + `confidence`
- `scope` (string — `personal`, `project`, or `plugin`; required)
- `pluginName` + `marketplace` + `sourceRepo` (strings — present when `scope` is `plugin`: the plugin's name, its owning marketplace, and its upstream repo URL)
- `title` (≤ 80 chars)
- `description` (1-3 sentences)
- `recommendation` (concrete change)
- `codeExcerpt` (3 consecutive lines, verbatim)
- `source` (string — the authoritative citation; required, format above)
- `clarify` (boolean, default `false`)
- `clarificationQuestion` (string, required when `clarify: true`)

## Phase 3 — Sanity-check + deduplicate + prioritize

**First, read `${CLAUDE_SKILL_DIR}/protocols/finding-validation.md`** into lead context (deferred from Track A — see Phase 1). Apply the hard-fail + non-empty + smoke-parse discipline: anchors `Contain before opening` AND `Source-citation validation`, abort `[ABORT — SHARED FILE MISSING]` on failure.

Findings arrive as the results returned in each reviewer's completion notification; there is no task list to read (`../shared/subagent-reporting.md`).

0.0. **Reviewer roll-call** (canonical: `../shared/subagent-reporting.md` "Lead-side: reviewer roll-call"): reconcile the Phase 2 spawn list against the results actually returned. A reviewer that returned nothing, an empty result, or an error is `UNREPORTED` — a failure, never a clean dimension. Record `unreportedCount` and the dimension names, then apply the canonical's three consumer rules:
   1. **Render** every member by name in the Phase 7 `Audit integrity` section (`"<dimension>-reviewer returned nothing — its dimension was NOT audited"`).
   2. **Latch a non-zero Phase 7 exit.**
   3. **Block every clean-result path** — including the Phase 4 tier menu (see Phase 4) and the base summary line (`protocols/phase7-report.md`, sole owner of every summary form's wording), neither of which may read as a complete result while any dimension is `UNREPORTED`.

   Runs first because every later step is computed over the delivered set. Rationale: `protocols/rationale.md` "Phase 3 step 0.0".
1. **`file` containment + codeExcerpt sanity-check** — apply the step 1 body in `${CLAUDE_SKILL_DIR}/protocols/finding-validation.md`: a reviewer-supplied `file` is opened only after `realpath` resolves it under a dispatched skill's own directory (`realpath` unavailable ⇒ abort, never degrade), then the cited range is matched `line-1 … line+1` and the validated target `P` is handed to step 2. **Count `rejectionCount` and `unverifiableCount` as you route, across steps 1 AND 2**: 1a's containment failure and 1b's excerpt-window slip both increment `unverifiableCount`, so counting step 2 alone leaves a run whose only defects are step-1 routings at zero and fires neither advisor (`protocols/finding-validation.md` "What a routing actually does to the finding").
2. **Source-citation validation** — apply the step 2 body in that same file: the five `source` branches with their `[REJECTED]` vs `Audit integrity` routings, each reading the authoritative Track B scope tag of `P` rather than the reviewer-echoed `scope`.
3. **Dedup** — group findings by `(file, line, dimension)`. Cross-dimension duplicates on the same line are flagged with `[CROSS-DIM]` for the user.
4. **Per-reviewer 25%-rejection escalation** — if any reviewer had ≥ 25% of its findings **`[REJECTED]`** (count only genuine rejections: `codeExcerpt mismatch` and `citation broken`; **exclude every `Audit integrity` routing**, including out-of-set `file` citations, missing sources, and excerpt-window slips), flag a Phase 7 `Audit integrity` item: `<dimension> reviewer had a high hallucination rate this run (N/M rejected). Consider re-running with --only=<other-dimensions> and treating <dimension> output cautiously.` The exclusion is load-bearing — this counter is the skill's only hallucination signal, and folding contract slips into it manufactures false positives against reviewers whose findings are substantively correct.
5. **Sort** by severity → confidence → file path.
6. **Partition by `clarify`**: findings with `clarify: true` move to a "Needs clarification" tier. The remaining findings sort into the standard Critical/High/Medium/Speculative tiers.

## Phase 4 — User approval gate

**Roll-call gate (mandatory, first thing in this phase, `--auto-approve` included).** If `unreportedCount > 0`, print and carry into the report:
`⚠ <n> dimension(s) UNREPORTED — <names>; the tiers below are NOT the complete finding set.`
The tier menu is a clean-result path under `../shared/subagent-reporting.md` rule 3 — without this, a run that lost four of seven reviewers presents a two-finding menu as the whole audit.

### Conditional advisor (mandatory trigger)

**Position: fires BEFORE the [Clarify] flow and before the `--auto-approve` exit below, on the full post-dedup finding set.** Both the Clarify flow and the tier menu can drop findings, so a call placed after either would report a distribution that no longer matches the set it is meant to sanity-check.

Call `advisor()` if EITHER (interactive):
- Total finding count ≥ 20, OR
- Any single dimension contributes ≥ 60% of all findings (skewed-reviewer signal).

Under `--auto-approve` this call is **narrowed, NOT skipped**: instead call it if `rejectionCount`, `unreportedCount` or `unverifiableCount` is `>= 1`. That is the explicit decision `../shared/advisor-criteria.md` "Auto-approve compatibility" requires: a headless run has no human in the loop, so skipping both advisors would leave the least-supervised runs least verified.

Pass: total findings (**the pre-drop count**), per-dimension breakdown, top 3 critical/high titles, reference-fetch status (fresh/stale/missing). **Single-fire**: do not call advisor again in this phase.

**Consume the response.** Render the advisor's concerns immediately above the tier menu so the user sees them while deciding, and carry them into Phase 7's `ADVISOR NOTES:`. A call nothing reads meets the letter of criterion 1 and not its function. On conflict with evidence already gathered, apply the canonical's conflict-reconcile rule rather than silently switching.

### [Clarify] flow (before tier menu)

**Only here may an `--auto-approve` run leave the phase**, both gates above having run: skip the [Clarify] flow and the tier menu and proceed to Phase 7. Findings flagged `clarify: true` render in their original tier with a `[CLARIFICATION SKIPPED — auto-approve]` qualifier so the user can revisit them manually.

Otherwise, if any findings have `clarify: true`, present them one at a time **before** the standard tier menu so the user resolves judgment calls in-line:

```
━━━ Needs clarification (N findings) ━━━

Finding 1 of N — <skill>/SKILL.md:<line>   <dimension>   <severity>
  <title>
  <description>
  Recommendation: <recommendation>
  Source: <source>

Reviewer asks:
  <clarificationQuestion>
```

`AskUserQuestion`:
- **Apply this finding** — promote to its severity tier; user accepts the recommendation.
- **Drop this finding** — discard; user judges the recommendation doesn't fit their workflow.
- **Defer to Phase 7 with note** — render in Phase 7 with the clarification question shown so the user can decide later.
- **Abort** — cancel the audit.

After all clarify findings are resolved, proceed to the tier menu below. The `clarify` partition does **not** re-evaluate the advisor trigger (single-fire, "Conditional advisor" above): this flow iterates per finding, and re-firing per finding is exactly the per-iteration re-fire `../shared/advisor-criteria.md` "Single-fire on retry loops" bars.

### Findings-first approval display (tier menu)

```
Tier 1 — Critical & High (N findings)
  X critical | Y high
  Dimensions: <dim1> (<n1>), <dim2> (<n2>), ...

Tier 2 — Medium (M findings)
  Dimensions: ...

Tier 3 — Speculative (K findings)
  Dimensions: ...
```

`AskUserQuestion` per tier:
- **Approve all** — accept all findings in this tier (they render in Phase 7).
- **Review individually** — expand the full finding list for cherry-picking. Each individual finding gets `[Keep] | [Drop]`.
- **Skip tier** — drop the entire tier.
- **Abort** — cancel.

Phase 5 (auto-fix) and Phase 6 (validation) are intentionally **skipped in v1** — skill files are markdown specifications without a test harness; auto-fixing them is a future feature (tracked in issue #15).

## Phase 7 — Cleanup and report

### Order of operations (durability first)

**Read `${CLAUDE_SKILL_DIR}/protocols/phase7-report.md`** into lead context (body load deferred from Track A, where its presence and both anchors were already grep-guarded), under the hard-fail + non-empty + smoke-parse discipline: anchors `Findings Report` AND `Summary: N findings across M skills`, abort `[ABORT — SHARED FILE MISSING]` on failure. Re-confirm rather than trusting the Phase 1 result: the file can change between the two points, and this is the read whose content is actually rendered. That abort must print without the template, the file that just failed to load.

Then, in this order: **1.** render the console report · **2.** write the archival file if `--report`/`--report-path` is set · **3.** call the declare-done advisor · **4.** emit any advisor concerns under `ADVISOR NOTES:` (trailing on the console, prepended in the file), re-rendering that block and rewriting the file (same-day overwrite is already sanctioned in `protocols/report-write.md`).

**Durable before the advisor call, not after** — `../shared/advisor-criteria.md` criterion 2. Advising first left a whole run existing only in lead context until the call returned.

### Declare-done advisor (gated on non-triviality)

Call `advisor()` IF ANY of these non-triviality predicates is true (otherwise skip — `shared/advisor-criteria.md`'s "Unconditional advisor on every run" anti-pattern says trivially-clean small runs shouldn't burn budget):

- `findingCount >= 3`, OR
- `dimensionCount >= 3` (i.e., `--only=` was not narrow), OR
- `rejectionCount >= 1` OR `unverifiableCount >= 1` (Phase 3 rejected a finding, or could not check its source: reviewer-quality signals worth a second opinion), OR
- `unreportedCount >= 1`, OR `dimensionCount == 0` (coverage was lost: the same reviewer-quality class as a rejection, and the worse one, since it is coverage rather than noise. The zero-dimension case is total loss, and every counter above reads `0` because nothing was ever spawned, so without naming it here the least-supervised failure would get no advisor at all), OR
- An abort condition fired in any earlier phase.

The `findingCount` threshold is **flat at 3**, not derived from effort, per Phase 2, "No effort-adaptive overlay".

Pass: total findings, per-dimension breakdown, abort status (if any), unreported dimensions, and reference-fetch status. Under `--auto-approve` this call is **narrowed, not skipped**: fire it on the Phase 4 narrowing condition, on the Phase 2 zero-dimension guard, or when an abort fired. The guard needs naming here because it leaves every Phase 4 counter at `0` and sets no abort, so the narrowing would otherwise evaluate false on precisely the headless run that audited nothing. Phase 7 has no loop, so no single-fire flag is needed; the call site is reached at most once per run by construction.

If the advisor flags concerns about reviewer drift or an over-narrow dimension mix, surface them under `ADVISOR NOTES:` so the user sees them alongside the findings. **Where that block lands differs by surface, and the durability-first order above is why**: the console report was printed at step 1 and a console stream cannot be rewritten, so on the console the notes follow it as a trailing block; in the archival file step 4 re-renders the report with `ADVISOR NOTES:` prepended at the top and rewrites the file (`protocols/report-write.md`, "Two writes, by design"). Same content, same single rendering, two placements.

### Final report

Print the report below (always). When `--report` (or `--report-path=<path>`) is set, **also** write the rendered report to an archival markdown file per `### Save report` below — otherwise no file is written beyond the Phase 1 Track C cache update.

### Report structure

Render the findings report per the template in `${CLAUDE_SKILL_DIR}/protocols/phase7-report.md` (read at this phase's opening step). The scope-tag rendering rules and naming contract below modify how that template is filled.

**Scope-tag rendering rules** (single-scope simplifications):
- **`Roots` line**: always rendered on a personal/project run — the report's only unconditional statement of which directories were audited. **Name only the roots that actually contributed an audited skill**: if `effectiveScope=both` but one side yielded none, name the contributing side alone, or `Roots:` prints a root the `Discovered:` line omitted as empty and the two halves of one report contradict each other. (The `both`-collapse rule in `personal-project-scope.md` cannot catch this — it fires only when a root is *absent*, not present-but-empty.) Append `[auto-scoped to project — …]` only when `autoNarrowed=true` **and the run did not abort** (`protocols/rationale.md` "`Roots:` line"). Omit the line only under `--plugin`.
- **`By scope` rollup line**: render only when `count(distinct scopes in approved findings) > 1`. When a run produces findings in just one scope, drop the `By scope:` line entirely.
- **Inline `[personal]` / `[project]` tag on each finding**: render only when the same scope-count check is `> 1`. When findings are single-scope, drop the bracket prefix (no ambiguity to disambiguate). Two-space pad after `[project]` keeps the column aligned with `[personal]`.
- **`By skill` rollup in Action items**: only append `[personal]` / `[project]` to skill names when the same name appears in both scopes (collision case). Otherwise the bare name suffices.
- **Plugin runs (`--plugin`) override the single-scope simplification**: always render the `Plugin: <name> (…, source repo: <url>) [third-party — verify against plugin docs]` header line (in place of `By scope:`) and an inline `[plugin: <name>]` prefix on every finding — even though a plugin run is single-scope — because the report must always surface which plugin the finding is about and that it is third-party. **Two-marketplace collision** (a `<name>` resolved in two marketplaces — the audit-both case): qualify every per-finding tag, the `Skills audited:` list, the `By skill` rollup, and the Phase 1 `plugin=<name> (skills: …)` discovery-summary segment as `<name>@<mp>` so same-named skills from different marketplaces stay distinguishable, and repeat the `Plugin:` header line once per marketplace.

**Naming contract**: The "Action items" rollup is **mandatory** on every report — never omitted, never empty when findings > 0. It is the single answer to "what do I need to do?". The "Audit integrity" section is a meta-section about the audit run itself (reviewer-quality, citation validity); an empty Audit-integrity section means the audit was clean, NOT that the user has nothing to act on.

**Never emit the string "ACTION REQUIRED"** — not as a section heading, and not as the routing verb. Use `route to Audit integrity` for both, which names the destination an item actually reaches. The ban covers the routing verb wherever it appears, including the reviewer instructions and `protocols/finding-validation.md`, not just headings. Rationale: `protocols/rationale.md` "Naming contract".

### Save report

Only when `--report` or `--report-path=<path>` was parsed (else skip this step entirely). Follow `${CLAUDE_SKILL_DIR}/protocols/report-write.md` (read into lead context at Phase 1 Track A under its conditional guard): derive the destination from `effectiveScope` (or the sanitized `--report-path`), apply `../shared/gitignore-enforcement.md` against the resolved path (advisory write-side — warn if tracked, inform-with-glob if not ignored; no `.gitignore` mutation, since `Edit` is disallowed), then atomically write the **exact rendered report text** printed above (including the `Generated:` line and any abort marker). This step is step 2 of "Order of operations (durability first)" and therefore runs **before** the declare-done advisor, so the first write cannot carry an `ADVISOR NOTES:` block; step 4 re-runs it with that block prepended when the advisor returns concerns (`protocols/report-write.md`, "Two writes, by design"). A write failure is **non-fatal** — emit one advisory line and continue; the console report is the record. On success, print `Report written: <path>`.

### Abort-mode reporting

On any abort condition, render the marker per `../shared/abort-markers.md` (the canonical source). The four `abortReason` values skill-audit emits are:

| `abortReason` | Marker (rendered by canonical) | When |
|---------------|--------------------------------|------|
| `unmatched-scope` | `[ABORT — UNMATCHED SCOPE]` | Phase 1 Track B discovered zero skills; also the in-Track-B aborts in `protocols/personal-project-scope.md` (cross-scope conflict, bare-positional 0-match, bare-positional-gitignored) |
| `shared-file-missing` | `[ABORT — SHARED FILE MISSING]` | A guarded protocol read failed — Track A, or a deferred read at Phase 3 / Phase 7, or `shadow-detection.md` |
| `realpath-unavailable` | `[ABORT — REALPATH UNAVAILABLE]` | `realpath` is absent where containment depends on it: the Phase 1 Track B availability probe (personal/project), Phase 3 step 1a, and `--plugin` skills-dir resolution |
| `user-abort` | `[ABORT — USER ABORT]` | User chose `[Abort]` at any approval gate |

**Exit codes.** All four markers force a non-zero Phase 7 exit, as do `unreportedCount > 0` and the Phase 2 zero-dimension guard (both are lost coverage, and both are markerless: `abortMode` stays `false`); a report-write failure, `rejectionCount`, `unverifiableCount` and `refSkippedCount` do **not**. Those are caught defects rather than lost coverage: a rejected finding is dropped by design, and an unverifiable one is still rendered, except the containment-failure class, which surfaces as an `Audit integrity` note carrying its title instead of as a finding. `refSkippedCount` is the deliberate exception to that framing: it *is* lost coverage, but a reference the run could not fetch is documented graceful degradation (`protocols/refs-cache.md`, "Same rule per key", loaded at Track C), so it qualifies the Phase 7 summary line and is named in `Audit integrity` instead of failing the run. `../shared/abort-markers.md` "Exit-code contribution" already declares the marker half; consumers own only the abort wording (`../shared/phase1-track-a-protocol.md` "Abort rendering") and the non-marker conditions here. Without this list an `unmatched-scope` or `user-abort` run that audited nothing could exit 0 and pass CI.

**Argument-parse rejections are plain exits, not aborts** — they fire before Phase 1, where no Phase 7 state exists to render, so they emit their message and exit with no marker or `abortReason`.

Track C failures do NOT trigger abort — they degrade gracefully (stale cache → warning; no cache → skip `feature-adoption-reviewer`).

## Phase 8 — Optional: file follow-up issues (future)

**Not implemented in v1** (tracked in issue #16). When implemented, would create a GitHub issue per `Critical` finding (analogous to `/jr-audit` Phase 8) so high-severity findings get tracked outside the conversation.

## Edge cases

The full case→behavior reference table lives in `${CLAUDE_SKILL_DIR}/edge-cases.md` (loaded on demand — reference material, not read at Phase 1). It covers auto-scope behaviors (foreign repo with/without skills, filtered runs, worktrees), plugin object-source handling, two-marketplace collisions, CWD-under-personal-root, `--add-dir`, model-alias drift, `disable-model-invocation` description weight, `gh`-unavailable degradation, and `--scope-only` edge behaviors.
