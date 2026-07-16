---
name: jr-skill-audit
description: Audit Claude Code skill files (SKILL.md) for 2026-feature alignment, advisor coverage, frontmatter validity, token efficiency, shared-file drift, safety-protocol consistency, and model-tier routing. Reviewers cite live Anthropic docs + changelog (fetched at runtime, cached) so findings are grounded, not hallucinated. Reports a prioritized improvements list with file:line citations. Findings-only — never modifies skill files.
argument-hint: "[skill-name] [--scope=<glob>] [--scope-only=personal|project|both] [--plugin=<name>] [--only=<dims>] [--model=<tier>] [--auto-approve] [--refresh-refs]"
effort: high
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Write(~/.claude/skills/jr-skill-audit/cache/**) Glob Grep WebFetch AskUserQuestion Agent advisor TaskCreate TaskList SendMessage Bash(grep *) Bash(wc *) Bash(find . *) Bash(ls *) Bash(stat *) Bash(awk *) Bash(sed *) Bash(jq *) Bash(test *) Bash([ *) Bash(shasum *) Bash(sha256sum *) Bash(cut *) Bash(head *) Bash(tail *) Bash(sort *) Bash(printf *) Bash(date *) Bash(basename *) Bash(dirname *) Bash(command -v *) Bash(realpath *) Bash(git -C * check-ignore *) Bash(git -C * rev-parse *) Bash(git -C * ls-files *) Bash(gh api repos/anthropics/claude-code/contents/CHANGELOG.md *) Bash(base64 *) Bash(mkdir -p *) Bash(mv *) Bash(echo *)
disallowed-tools: Edit
---

<!-- Frontmatter notes:
- `model: sonnet` (lead): Phase 3 source-citation verification is a mechanical match against the
  Track C refs cache, and Phase 4 synthesis (plus the lead-emitted scope-resolution dimension) is
  structured orchestration, not open-ended agentic coding. The genuinely judgment-heavy work (spec
  review across the 7 reviewer dimensions) is delegated to opus subagents. Mirrors `/jr-ship`'s
  validated lead-sonnet + opus-delegated-judgment pattern.
- `Write` is scoped to `~/.claude/skills/jr-skill-audit/cache/**` — the refs.json cache is the skill's ONLY write target (it is findings-only and never modifies skill files). Do not broaden the grant; any new write site must extend the path scope explicitly. NOTE — the literal `~/.claude/skills/jr-skill-audit/cache/**` is intentional and is NOT switched to `${CLAUDE_SKILL_DIR}/cache/**` to match the body's substitution: the skills doc documents `${CLAUDE_SKILL_DIR}` only for bash-injection use and states allowed-tools substitution support ONLY for `${CLAUDE_PROJECT_DIR}` (v2.1.196+). `${CLAUDE_SKILL_DIR}` in `allowed-tools` is undocumented, so a literal `${CLAUDE_SKILL_DIR}` here would risk a never-matching grant (every cache write would then prompt). The hardcoded path is correct for the personal install (the skill's by-design home); it only diverges from the body under a project/plugin install, where the write degrades to a per-call prompt rather than failing. Revisit if/when Anthropic documents `${CLAUDE_SKILL_DIR}` substitution in allowed-tools.
-->

<!-- Dependencies:
  Required plugins:
    - agent-teams@claude-code-workflows        — team-reviewer agents (Phase 2), spawned via Agent name param (implicit team since 2.1.178)
  Required CLI:
    - gh                                        — Phase 1 Track C: `gh api repos/anthropics/claude-code/contents/CHANGELOG.md`
                                                  for changelog content (gh handles GitHub auth + redirects;
                                                  preferred over WebFetch per WebFetch's own guidance for github.com URLs)
  Files read:
    - ~/.claude/skills/*/SKILL.md               — every repo-owned personal skill (gitignored / externally-maintained skills excluded — see Phase 1 Track B)
    - <walked-dir>/.claude/skills/*/SKILL.md    — project-scoped skills, walked from $PWD up to repo root.
                                                  An unfiltered run from a foreign repo that has its own skills audits
                                                  these ALONE (auto-scope); elsewhere they are audited alongside personal.
                                                  Pin with --scope-only=personal|project|both
    - ~/.claude/skills/<name>/scripts/*.sh      — referenced helper scripts (existence + executable bit)
    - ~/.claude/skills/<name>/templates/*       — referenced templates (existence)
    - ~/.claude/plugins/marketplaces/<mp>/<source>/skills/*/SKILL.md
                                                — git-tracked plugin skills, opt-in via --plugin=<name> (resolved from
                                                  known_marketplaces.json + each marketplace's .claude-plugin/marketplace.json)
    - ${CLAUDE_SKILL_DIR}/cache/refs.json       — cached Anthropic docs + changelog (Phase 1 Track C);
                                                  refreshed on stale (>7 days) or --refresh-refs
    - ${CLAUDE_SKILL_DIR}/protocols/plugin-scope.md — Track B `--plugin` scope-resolution procedure;
                                                  read at Phase 1 Track A ONLY when --plugin is set (conditional)
    - ${CLAUDE_SKILL_DIR}/protocols/personal-project-scope.md — Track B personal/project scope-resolution procedure; read at Phase 1 Track A ONLY when --plugin is NOT set (complementary conditional to plugin-scope.md)
    - ${CLAUDE_SKILL_DIR}/edge-cases.md         — case→behavior reference table; loaded on demand (NOT Track-A-read)
  Out of scope in v1 (tracked in GitHub issues):
    - Auto-fix mode (Phase 5/6 implementer + validation)        — issue #15
    - Phase 8 file follow-up GitHub issues                       — issue #16
    - Archival report file (.claude/skill-audit-report-*.md)     — issue #19
  Shared protocol references (read at Phase 1 Track A; see ../shared/):
    - shared/reviewer-boundaries.md             — severity rubric (`critical|high|medium|low`) + confidence
                                                  levels (`certain|likely|speculative`); the dimension-ownership
                                                  table is `/jr-audit`/`/jr-review`-specific and replaced inline below
                                                  for skill-audit's seven dimensions
    - shared/untrusted-input-defense.md         — passed verbatim into every reviewer prompt
    - shared/display-protocol.md                — phase headers, timeline, silent-reviewers, compact tables
    - shared/abort-markers.md                   — Phase 7 abortReason → marker mapping
    - shared/advisor-criteria.md                — canonical advisor-call rules; passed to advisor-coverage-reviewer
                                                  verbatim. Portable spec extracted from Anthropic's published
                                                  advisor guidance (NOT from any user's personal CLAUDE.md, which
                                                  would tie findings to whoever ran the skill last)
    - shared/gitignore-enforcement.md           — passed to safety-protocols-reviewer so it can flag missing
                                                  applications of the protocol in audited skills
    - shared/secret-scan-protocols.md           — passed to safety-protocols-reviewer to verify secret-scan tier semantics where applicable
    - shared/claim-verification.md              — anti-hallucination doctrine; skill-audit's Track C + Phase 3
                                                  source-validation are its reference Tier-2 implementation
    - shared/phase1-track-a-protocol.md         — hard-fail guard algorithm + Canonical Anchor Table (self-reference)
    - shared/model-override.md                  — --model=<tier> per-run subagent model override (Phase 2 spawns)
  Files written:
    - ${CLAUDE_SKILL_DIR}/cache/refs.json       — Track C live-references cache (timestamp + URL → content map)
  Required tools:
    - Agent, TaskCreate, TaskList, SendMessage, AskUserQuestion, advisor
    - Bash, Read, WebFetch, Glob, Grep, Write
-->

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
- `--model=<tier>` — Override the model for **every subagent spawned this run** (`sonnet|opus|haiku|fable`); nested spawns inherit it. Does NOT change the lead (frontmatter applies before argument parsing — run `/model <tier>` first for a uniform run). Compatible with all other flags. Canonical semantics: `../shared/model-override.md`.

**Examples**: `/jr-skill-audit`, `/jr-skill-audit review`, `/jr-skill-audit --scope=*-reviewer`, `/jr-skill-audit --scope-only=project`, `/jr-skill-audit --scope-only=both`, `/jr-skill-audit --plugin=agent-teams`, `/jr-skill-audit --only=frontmatter,advisor-coverage`, `/jr-skill-audit --auto-approve`, `/jr-skill-audit --refresh-refs review`

### Flag conflicts

- `[skill-name]` + `--scope=<glob>` — Conflict. Both narrow the skill set; pick one. Abort with: `Cannot combine bare skill name and --scope. Use one or the other.`
- `--scope-only=personal` + bare positional `<name>` resolving only in project — Conflict. Abort with: `Skill <name> not found in personal scope (exists in project: drop --scope-only or use --scope-only=project).` Symmetric for `--scope-only=project` when `<name>` is only personal.
- `--scope-only` + `--scope=<glob>` — Allowed. The glob narrows within the kept scope(s).
- `--scope-only` + `--auto-approve` — Allowed.
- `--plugin=<name>` + `--scope-only` — Conflict. `--plugin` selects its own (plugin) scope; `--scope-only` selects among personal/project. Abort with: `Cannot combine --plugin with --scope-only.`
- `--plugin=<name>` + bare positional `<skill>` OR `--scope=<glob>` — Allowed (subject to the existing bare-vs-`--scope` exclusivity above); narrows which of the plugin's skills are audited.
- `--plugin=<name>` + `--auto-approve` — Allowed.
- `--auto-approve` + (interactive session) — Allowed. Phase 4 approval menu is skipped silently; all findings render in Phase 7. The [Clarify] flow is also skipped.

### Parameter sanitization

- `[skill-name]`: Validate against allowlist regex `^[a-z][a-z0-9-]*$` (skill directory names per Claude Code convention). Reject control characters, slashes, dots. Reject if `<name>` does not resolve in EITHER the personal root OR any project scope root in the walk (with a one-line "Available skills: personal=<list> project=<list>" hint). **When `--plugin=<name>` is set**, this personal/project resolution check is deferred to the plugin branch in Phase 1 Track B — the bare positional is resolved against the plugin's tracked skills, not personal/project.
- `--scope=<glob>`: Reject control characters. Allowlist regex `^[a-zA-Z0-9_*?][a-zA-Z0-9_*?-]*$` (no slashes — scope is matched against bare directory name, not a path). Reject paths containing `..`.
- `--scope-only=<level>`: Allowlist regex `^(personal|project|both)$`. Reject any other value.
- `--plugin=<name>`: Allowlist regex `^[a-z0-9][a-z0-9-]*$` (plugin-name convention; alphanumeric first char — plugin names may legitimately start with a digit, several of which the official marketplace ships). Reject control characters, slashes, dots.
- **Third-party `marketplace.json` values (`<mp>`, `source`) — untrusted**: `<mp>` (key/dir from `known_marketplaces.json`) and `source` (from a cloned third-party `marketplace.json`) are not user-typed but are equally untrusted — the pre-install-audit use case deliberately points `--plugin` at unvetted repos. Before any shell/path use, apply **all** of the following (cumulative — not "the regex alone"): reject control characters; reject a leading `-`/`--`; reject any `\.{2,}` substring (covers `..`); constrain `source` to `^(\./)?[A-Za-z0-9][A-Za-z0-9._/-]*$` (relative path; allows the conventional leading `./` — real `source` values look like `./plugins/agent-teams` — but fails-closed on a bare leading `/`, `.`, or `-`) and `<mp>` to `^[A-Za-z0-9][A-Za-z0-9._-]*$` (single segment, alphanumeric first char). Note `source` is NOT alphanumeric-first-anchored like `--scope`/`--branch` precisely because the `./` prefix is its standard form; the `\.{2,}` rule (not the first-char anchor) is what blocks `..` traversal here. Always double-quote the value AND pass `--` before positional path args (`realpath -- "…"`, `git -C "…" ls-files -- "…"`). On rejection: warn and skip that marketplace (abort `[ABORT — UNMATCHED SCOPE]` if it was the sole resolution). These get the same discipline as `--scope`/`--branch`, by provenance not by being user-typed.
- `--only=<dims>`: Trim whitespace per value. Validate each is one of `frontmatter`, `advisor-coverage`, `token-efficiency`, `shared-drift`, `feature-adoption`, `safety-protocols`, `model-routing`. Reject unknown values.
- `--model=<tier>`: Allowlist regex `^(sonnet|opus|haiku|fable)$`. Reject any other value with: `Invalid --model value '<value>'. Valid values: sonnet, opus, haiku, fable.` (per `../shared/model-override.md`).

### Model requirements

- **Reviewer agents** (Phase 2): Spawn with `model: "opus"` (or the `--model` override when set — `../shared/model-override.md`). Each reviewer receives the full `SKILL.md` content, the inline dimension scope, the `shared/untrusted-input-defense.md` block verbatim, and the **per-dimension reference excerpt** from Track C (see Phase 2). Reviewers do **not** receive the live skill's runtime context — they read the file as a specification document, not as executable behavior.
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
- `../shared/gitignore-enforcement.md` — passed to `safety-protocols-reviewer` so it can flag missing applications of the protocol in audited skills.
- `../shared/secret-scan-protocols.md` — passed to `safety-protocols-reviewer` so it can verify an audited skill references the correct secret-scan tier semantics (strict/advisory classification, demotion criteria) where applicable.
- `../shared/claim-verification.md` — anti-hallucination doctrine; skill-audit's Track C live-refs + Phase 3 source-citation validation are its reference **Tier 2** implementation (see the Track C "Doctrine anchor" note).
- `../shared/phase1-track-a-protocol.md` — algorithm + Canonical Anchor Table consumed by the structural smoke-parse below.
- `../shared/model-override.md` — `--model=<tier>` subagent model-override semantics, applied at the Phase 2 reviewer spawns.

**Hard-fail guard**: if any shared file fails to Read, returns empty content, or fails the structural smoke-parse below, abort Phase 1 immediately with `[ABORT — SHARED FILE MISSING]` (per `../shared/abort-markers.md`) and exit non-zero. Do NOT fall back to inline text.

**Structural smoke-parse** (mandatory, after non-empty Read): apply the smoke-parse algorithm and Canonical Anchor Table from `../shared/phase1-track-a-protocol.md` — each row of the canonical's table lists the required substrings for one shared file (case-sensitive, `grep -F` semantics, AND-joined within a row). **Self-reference escape hatch (hardcoded)**: before parsing the canonical's table, verify `../shared/phase1-track-a-protocol.md` itself contains the literal string `Canonical Anchor Table` — a stub corruption of the canonical that preserves only its self-row anchor would otherwise pass the table-driven check. If any file fails the smoke-parse (self check OR any row check), abort Phase 1 with `[ABORT — SHARED FILE MISSING]` as above.

**Skill-local protocol files (conditional — exactly one per run)**: when `--plugin=<name>` is set, also Read `${CLAUDE_SKILL_DIR}/protocols/plugin-scope.md` into lead context (parallel with the shared files above) and apply the same hard-fail + non-empty + smoke-parse discipline — abort with `[ABORT — SHARED FILE MISSING]` if it is absent, empty, or fails its anchors `Locate the marketplace` AND `Enumerate git-tracked skills` (case-sensitive `grep -F`). When `--plugin` is NOT set, Read `${CLAUDE_SKILL_DIR}/protocols/personal-project-scope.md` instead (same discipline; anchors `Scope roots` AND `Gitignore exclusion`) — the two are mutually exclusive, so exactly one is read per run (mirrors `/jr-review`'s conditional `convergence-protocol.md` read under `--converge`).

### Track B — Discover skill targets

Enumerate skill directories matching the argument set, across personal and project scopes.

**Plugin scope** (when `--plugin=<name>` is set): short-circuit the personal/project discovery below and follow the plugin-scope resolution procedure (marketplace location, git-tracking enumeration, symlink/containment canonicalization, tagging) in `${CLAUDE_SKILL_DIR}/protocols/plugin-scope.md` — read into lead context at Phase 1 Track A **only when `--plugin` is set** (mirrors how `/jr-review` reads `convergence-protocol.md` only under `--converge`). On success it tags each surviving target `scope=plugin` and skips to "For each surviving target" below; the personal/project discovery, gitignore filtering, and shadow detection are all bypassed (plugin scope is exclusive).

**Personal/project scope** (when `--plugin` is NOT set): follow the discovery procedure in `${CLAUDE_SKILL_DIR}/protocols/personal-project-scope.md` — read into lead context at Phase 1 Track A under the non-`--plugin` conditional (hard-fail + non-empty + smoke-parse anchors `Scope roots` AND `Gitignore exclusion`; abort `[ABORT — SHARED FILE MISSING]` per `../shared/abort-markers.md` if absent/empty/invalid; the complementary conditional to `plugin-scope.md`). It computes the personal + project scope roots (`realpath` probe, parent-walk with the under-`personalRoot` / equals-`personalRoot` skip conditions) plus the auto-scope default (project-only for an unfiltered run from a git repo other than the personal skills repo that has skills of its own; `both` everywhere else — including the skills repo, where project scope is empty, so that run is unchanged), enumerates and dedupes SKILL.md candidates tagged `scope=personal|project`, applies the argument-set filter then the scope filter (with the cross-scope conflict probe in between), resolves the bare positional when one was provided (0 → "Available skills" abort; 1 → audit; ≥ 2 → audit all), drops gitignored (externally-maintained) skills per scope, then applies the auto-narrow fallback — returning the surviving target set plus `effectiveScope`, `autoNarrowed`, `autoNarrowFallbackFired`, and `excludedCandidates` (consumed by the Phase 1 `Scope:` line and its fallback variant, the Empty-discovery guard, and the Phase 7 `Roots:` line). The bare-positional-gitignored abort and the silent `--scope`/no-filter exclusion-with-listing both live in that protocol.

For each surviving target, read the `SKILL.md` plus enumerate `<skill>/scripts/*.sh` and `<skill>/templates/*` as supplementary inputs (existence + executable bit only — content reads only when a reviewer cites them). For plugin scope these paths are under the resolved `~/.claude/plugins/marketplaces/<mp>/<source>/`.

**Empty-discovery guard**: if zero skills resolve (e.g., `--scope=foo*` matches nothing, `--scope-only=project` from a dir with no `.claude/skills/` in the walk, or `--plugin=<name>` whose marketplace is non-git or whose `<source>/skills/` has no tracked SKILL.md), abort with `[ABORT — UNMATCHED SCOPE]` per the canonical mapping. The abort message includes the active `--scope-only`, `--plugin`, or `--scope` value (if set) so the user can correct or drop the argument and retry — a mistyped glob must report the glob that matched nothing, not a scope diagnosis. An auto-scope narrowing can never reach this guard with candidates still standing (the auto-narrow fallback in `protocols/personal-project-scope.md` un-narrows first), so reaching it on a **fully unfiltered run** — no `--scope-only`, no `--plugin`, no `--scope`, no bare positional — means nothing survived in either scope; say that, rather than naming an argument the user never passed.

**Report the cause, not just the absence.** On an unfiltered run the dominant way to arrive here is not that no skills exist: it is that every candidate was dropped as gitignored (the fallback restores personal, its step 2 excludes them, and the set empties again). The `Excluded (gitignored):` segment that would explain this prints only in the discovery summary after all tracks, so it is unreachable from this abort. On that fully-unfiltered run only, branch on `excludedCandidates` (returned by `protocols/personal-project-scope.md`), keeping `abortReason=unmatched-scope` either way (the canonical mapping in `../shared/abort-markers.md` recognises no other value here, and an unrecognised one renders `[ABORT — UNLABELED]` as a contract violation). With any filter present the argument-naming rule above still owns the message, and these two cases stop being exhaustive: `--scope=foo*` can match nothing having excluded nothing, so a count of 0 would no longer mean the enumeration was empty.
- **Excluded count > 0**: name them, e.g. `Nothing auditable: N skill(s) found but all excluded as gitignored (externally maintained): <names with [personal]/[project] tags>.` Externally-maintained skills are not repo-owned, so this is a scope outcome the user can act on, not a missing-file error.
- **Excluded count == 0**: the enumeration really was empty; keep the flat "nothing is auditable in either scope" wording.

### Track C — Live Anthropic references (cached with TTL)

Reviewers cite live documentation so findings stay current as Claude Code ships features. The cache lives at `${CLAUDE_SKILL_DIR}/cache/refs.json` with a 7-day TTL.

> **Doctrine anchor**: this Track C live-references cache plus the Phase 3 step 2 source-citation validation are the reference **Tier 2** implementation of `../shared/claim-verification.md` — fetching authoritative sources (here, `gh api` raw changelog + WebFetch docs) and refusing to surface a finding whose cited source cannot be confirmed. verification is always-on for `/jr-skill-audit` with no opt-out (active verification is its whole purpose; `--no-verify-claims` is not offered here). The doctrine's outcomes map as: source key present in `refs.json` with `ok:true` (or a confirmed `changelog:`/shared-file line) → `confirmed`; `[REJECTED — citation broken]` / `[REJECTED — citation outside plugin tree]` → `refuted`; `ACTION REQUIRED` (source not in cache, missing, or sibling-skill) → `unverifiable`, routed to the user rather than silently dropped.

**Cache schema**:

```json
{
  "fetchedAt": "2026-05-09T12:34:56Z",
  "refs": {
    "skills-doc":     { "url": "https://code.claude.com/docs/en/skills",     "content": "...", "ok": true },
    "env-vars-doc":   { "url": "https://code.claude.com/docs/en/env-vars",   "content": "...", "ok": true },
    "claude-code-changelog": { "url": "gh:anthropics/claude-code:CHANGELOG.md", "content": "...", "ok": true }
  }
}
```

**Refresh logic**:
1. If `--refresh-refs` is set OR the cache file is missing OR `fetchedAt` is older than 7 days → refresh.
2. Otherwise → load from cache silently.

**Refresh procedure** (best-effort; partial-success is allowed):
1. `mkdir -p "${CLAUDE_SKILL_DIR}/cache"`.
2. WebFetch `https://code.claude.com/docs/en/skills` and `https://code.claude.com/docs/en/env-vars`. Each prompt should ask the model to return the **frontmatter reference table** + **substitution variables table** + the **`Skill content lifecycle`** + the **500-line tip** for the skills doc; for env-vars, return the full content.
3. `gh api repos/anthropics/claude-code/contents/CHANGELOG.md --jq .content | base64 -d | head -c 60000` for the latest changelog. (gh is preferred over WebFetch for github.com URLs per WebFetch's own guidance.) Trim to 60 KB so the cache stays bounded; the most recent ~30 versions easily fit.
4. Write `cache/refs.json` atomically (write to `cache/refs.json.tmp`, then `mv`). Set `ok: false` for any source that failed and surface the failure in the Phase 7 report under "Reference fetch status".

**Known limitation — WebFetch summarization**: WebFetch returns AI-summarized content extracted by a small model from the prompt, not raw HTML. Citation validation by URL key works regardless (the URL is in the cache or it isn't), but `feature-adoption-reviewer`'s reasoning over content fidelity has a ceiling — if the small model summarized away a feature mention, the reviewer won't see it. The `gh api` path for the changelog returns raw markdown without this limitation. For the skills/env-vars docs, the prompt asks for the specific tables/sections, which works around most of the lossy-summarization risk in practice.

**Fallback to stale cache**: if the refresh fails entirely (no network, gh unauth, etc.) AND a previous `cache/refs.json` exists, use it and prepend `[STALE: cache from <fetchedAt>]` to every reviewer prompt that consumes it. Reviewers must add `[Source: cached YYYY-MM-DD]` to any finding citing a source from the stale cache so the user can judge freshness.

**Fallback to no cache**: if the refresh fails AND no prior cache exists, mark `feature-adoption-reviewer` as **skipped** in Phase 2 (its findings would be ungrounded), warn in the Phase 7 report (`Reference fetch failed and no prior cache exists. feature-adoption-reviewer skipped.`), and continue with the other five dimensions. Do NOT abort the run — the other dimensions don't need live refs.

### After all tracks complete

**Shadow detection (lead-side synthesis)**: group the **enumerated** discovery candidates by directory basename — the set *before* the argument-set filter, the scope filter, **and gitignore exclusion**. Both roots are always enumerated regardless of flags (`protocols/personal-project-scope.md`), and a shadow is a property of the directory you are standing in, not of what you chose to audit; grouping the surviving set instead would blind the check whenever a scope filter (or the auto-scope default) narrowed the run. **Gitignored candidates are deliberately included**: Claude Code's runtime does not consult `.gitignore`, so an externally-maintained personal skill still loads and still shadows a same-named project skill. The collision is real and the fix (rename the project skill) is actionable, even though the gitignored skill's own *contents* are excluded from the audit as non-actionable. For each basename appearing in BOTH `personal` and `project` scopes, the lead synthesizes one `scope-resolution` finding (full spec in the "Shadow detection" subsection below) — these flow into Phase 3 alongside reviewer findings. The finding fires even when only one side is audited: it anchors on the personal SKILL.md (`protocols/shadow-detection.md`), which stays readable either way.

**Scope line (mandatory whenever `autoNarrowed=true`)**: the auto-scope default makes the same bare command audit different skills in different directories, so an auto-narrowed run MUST say so and name the root it picked, on its own line above the summary:
```
Scope: project (auto — <cwdRepoRoot> has its own skills; --scope-only=both to include personal)
```
Gate on `autoNarrowed` (set by `protocols/personal-project-scope.md` at "Resolve `effectiveScope`"), NEVER on `autoScope`: the proposal can compute `project` on a run that audits both (any bare positional or `--scope=<glob>`), and the auto-narrow fallback clears it when it un-narrows. Reading the proposal would assert a narrowing that did not happen.

**Scope line, fallback variant (mandatory whenever `autoNarrowFallbackFired=true`)**: here the fallback un-narrowed the run, so `autoNarrowed=false` correctly suppresses the block above and no `[auto-scoped to project]` qualifier is owed. But the scope outcome still turned on `$PWD`: the project root was tried and yielded nothing auditable. Without a line saying so the run is byte-identical to one where auto-scope never applied, and a user standing in a repo that has a `.claude/skills/` directory is never told why none of it was audited. Print instead:
```
Scope: personal (<projectRoot(s)> has no auditable skills; falling back to personal)
```
Name `projectRoot(s)` from the returned contract, never a path synthesised from `cwdRepoRoot`: `projectRoots` is built by a parent-walk from `$PWD` up to the repo root (`protocols/personal-project-scope.md`), so the root that actually came up empty may sit below `cwdRepoRoot` and `<cwdRepoRoot>/.claude/skills` need not exist at all. Synthesising it would make the one line whose purpose is to record which root was tried name a directory that never held skills, and contradict the Phase 7 `Roots:` line, which is already plural-aware. (The non-fallback variant above may keep `<cwdRepoRoot>`: it claims only that the *repo* has skills, which is true.) Gate this on `autoNarrowFallbackFired`, never on `autoNarrowed` or `autoScope`: the fallback deliberately clears `autoNarrowed` to `false`, so reusing that gate would suppress the one line the fallback path exists to surface. The two Scope-line variants are mutually exclusive by construction: the fallback sets `autoNarrowed=false` at the same step it sets `autoNarrowFallbackFired=true`, so at most one gate is ever live.

Print a one-line summary. Omit scope segments that are empty (e.g., a personal-only run drops the `project=` segment, and `Shadowed: none` is omitted when both scopes have zero overlap):
```
Discovered N skill(s): personal=<p-list> project=<j-list>   |   Shadowed: <colliding-names>   |   Excluded (gitignored): <names with [personal]/[project] tags | "none">   |   M reviewer dimensions selected   |   Refs: <fresh|cached YYYY-MM-DD|stale|missing>
```
For a `--plugin` run, render `Discovered N skill(s): plugin=<name> (skills: <s-list>)   |   M reviewer dimensions selected   |   Refs: <…>` instead — the `personal=`/`project=`/`Shadowed:` segments are bypassed.

If a skill exceeds **2,000 lines**, warn before dispatch: huge skills cost reviewer-token budget and convergence-quality drops. Recommend the user narrow with `--only=<dims>` to focus on a single dimension first.

### Shadow detection (lead-side synthesis)

When the Track-B grouping above yields a basename present in both scopes, the lead synthesizes the finding directly — no Phase 2 reviewer agent is involved. The finding routes through Phase 3 (sanity-check + dedup) and Phase 4 ([Clarify] flow) like any other finding.

**Finding shape + rationale**: read `${CLAUDE_SKILL_DIR}/protocols/shadow-detection.md` on demand (only when a cross-scope collision is detected — it is reference material, NOT a Phase 1 Track A hard-fail read, mirroring `edge-cases.md`). It carries the exact `scope-resolution` finding shape (anchor field, `clarify: true`, `source` as a `cache/refs.json` key, `scope: personal` as the runtime winner) and the design rationale.

## Phase 2 — Spawn reviewer swarm

Spawn each selected reviewer dimension as a `agent-teams:team-reviewer` agent. Reviewers run **in parallel** within a single tool-use message.

**Per-skill dispatch metadata (lead-side, mandatory)**: when handing each reviewer its list of per-skill assignments, include `scope: personal|project|plugin` alongside the SKILL.md path so the reviewer can echo it back on every finding per requirement #7 in "Reviewer instructions" below. For `plugin` scope, also pass `pluginName`, `marketplace`, and `sourceRepo`, and prepend a one-line third-party preamble to the reviewer prompt: *"This is a THIRD-PARTY plugin skill authored by someone other than the user; findings are advisory (the user cannot directly edit it) — tag each `[third-party — verify against plugin docs]` and do not treat the user's `~/.claude/skills/shared/*.md` as canonical for it."* This is the single source of truth for the `scope` field on findings — reviewers MUST NOT infer scope from the file path (paths can be ambiguous under symlinks; the lead's tag set by Track B's enumeration is authoritative).

**Effort-adaptive overlay** (read `CLAUDE_EFFORT` at runtime via Bash: `effort="$CLAUDE_EFFORT"; [ -z "$effort" ] && effort=high`). At `xhigh|max`, lower the Phase 7 declare-done advisor's non-triviality threshold (e.g., `findingCount >= 3` instead of `>= 5`) so deeper-effort runs are more likely to receive a second opinion. At `low|medium`, keep the standard threshold. Mirrors `/jr-review`'s pattern; requires Claude Code ≥ 2.1.133.

### Per-reviewer reference excerpts (token budget)

Each reviewer receives ONLY the references it needs (mirrors the principle "skills load on demand"). Excerpts are pulled from `cache/refs.json`:

| Dimension | Receives |
|-----------|----------|
| `frontmatter-reviewer` | `skills-doc` Frontmatter reference table + Available string substitutions table. |
| `advisor-coverage-reviewer` | `shared/advisor-criteria.md` (full). NO Track C refs needed. |
| `token-efficiency-reviewer` | `skills-doc` Skill content lifecycle section + 500-line Tip. |
| `shared-drift-reviewer` | The full canonical `shared/*.md` set (already in lead context from Track A). NO Track C refs. |
| `feature-adoption-reviewer` | `skills-doc` (Frontmatter reference + Substitutions tables) + `claude-code-changelog` (head ~30 versions). |
| `safety-protocols-reviewer` | `shared/untrusted-input-defense.md` + `shared/gitignore-enforcement.md` + `shared/secret-scan-protocols.md` (all already in lead context from Phase 1 Track A reads; the latter two loaded specifically for this dimension so it can flag missing gitignore-enforcement applications and verify secret-scan tier semantics). NO Track C refs. |
| `model-routing-reviewer` | NO Track C refs — reasons over the audited skill's own phase descriptions + frontmatter `model`/`effort` fields (already in the full `SKILL.md` content every reviewer receives per Phase 2). |

### Dimension table

| Dimension | Owns | Stays out of |
|-----------|------|--------------|
| `frontmatter-reviewer` | Required fields (`description` per [skills doc](https://code.claude.com/docs/en/skills)); allowed values for `effort` and `model` (verified against the live doc); contradictions (`disable-model-invocation: true` → `description` is NOT in context, making `when_to_use` and `paths` inert per the doc's invocation-control table); `description + when_to_use` exceeding the 1,536-character cap; missing `name` falling through to directory-name fallback when explicit naming would aid clarity. | Body content (token-efficiency dimension); model-tier appropriateness (model-routing dimension). |
| `advisor-coverage-reviewer` | `advisor()` call sites against `../shared/advisor-criteria.md`: substantive-edit boundaries, declare-done points, stuck-loop signals; gating quality (single-fire guards, conditional triggers based on finding count or skewed dimensions); placement (before substantive work, not after). Each finding MUST cite the violated rule by `shared/advisor-criteria.md:<line>`. | Other call sites' specific phrasing (token-efficiency dimension). |
| `token-efficiency-reviewer` | Line count vs. live skills-doc 500-line tip; large inline blocks that should be `${CLAUDE_SKILL_DIR}/scripts/*` or `shared/*.md` extractions; per-phase prose density; redundant prose between phases; tables/code blocks that could collapse. **Skill content lifecycle** (the doc's section name): every line is a recurring token cost across the whole session — flag aggressively. | Frontmatter character cap (frontmatter dimension); model-tier cost (model-routing dimension). |
| `shared-drift-reviewer` | Inline duplicates of `shared/*.md` content (every duplicate proves the shared/ pattern isn't doing its job); missing references where shared files apply (e.g., subagent prompt without `untrusted-input-defense.md` reference); smoke-parse substring presence at every Read site of a shared file. | Whether the shared file itself is the right design (architecture concern, out of scope here). |
| `feature-adoption-reviewer` | 2026 substitutions used vs. **what the live skills-doc lists** (`${CLAUDE_EFFORT}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`, `$ARGUMENTS`, `$N`, `$name`); `allowed-tools` minimization (over-permissive grants like blanket `Bash(*)` without rationale); features adopted by Anthropic post-skill-creation that the skill could leverage (cross-reference the changelog). Every finding MUST cite the doc URL (`https://code.claude.com/docs/en/skills:<heading>`) or a changelog version (`changelog:<version>`). | Whether to add a feature at all if not present (advisor-coverage / token-efficiency may flag instead). |
| `safety-protocols-reviewer` | Untrusted-input defense applied at **every** subagent prompt site (reviewer, implementer, simplifier, convergence, fresh-eyes); gitignore-enforcement applied at every `.claude/*` cache/audit-trail write site; secret-scan tier classification correctly referenced when applicable; explicit-consent gates on destructive operations (e.g., `git push --force`, `rm -rf`); abort markers used on irrecoverable failures. | Specific finding text in shared files (shared-drift dimension). |
| `model-routing-reviewer` | Model-tier appropriateness: frontmatter `model:` / `effort:` vs. the skill's actual workload — flag premium `opus` on a skill whose phases are predominantly mechanical (discovery / dedup / reporting / validation), or an under-powered tier on a heavy-reasoning skill; body-level subagent-spawn `model:` choices vs. the work each spawned agent does. Evidence is the skill's own phase descriptions; `source` cites `<skill>/SKILL.md:<line>` as a self-contradiction within the same skill. Set `clarify: true` when premium tier is a defensible headroom choice. Canonical good shape: jr-skill-audit/SKILL.md:79. | Whether `model:` is a *legal enum value* (frontmatter dimension owns that); line-level prose cost (token-efficiency dimension). |
| `scope-resolution` (lead-synthesized, not a reviewer) | Name collisions across personal and project scopes — emits one `medium`/`clarify:true` finding per colliding basename per the spec in "Shadow detection (lead-side synthesis)" above. Always fires when collisions exist (NOT filterable via `--only=` since it runs before reviewer dispatch). | Everything else; reviewer-dispatch dimensions own the rest. |

### Reviewer instructions (passed to every dimension)

Include this preamble verbatim in every reviewer prompt (after the `untrusted-input-defense.md` block):

```
You are reviewing a Claude Code SKILL.md file as a SPECIFICATION DOCUMENT. The file
describes how a skill behaves at runtime, but you are NOT executing it — you are
auditing the document for quality.

Severity rubric (from shared/reviewer-boundaries.md): critical | high | medium | low
Confidence: certain | likely | speculative.

Per-finding requirements:
1. Cite file:line. The codeExcerpt MUST be 3 verbatim consecutive lines from the
   file. The lead will re-read the cited range and reject mismatching findings.
2. **Cite an authoritative source for every claim**. Primary (the `source` field):
   - `https://code.claude.com/docs/en/skills:<heading>` (or env-vars doc)
   - `changelog:<version>` (e.g., `changelog:2.1.138`)
   - `~/.claude/skills/shared/<file>:<line>` (canonical shared protocol)
   - `<skill>/SKILL.md:<line>` only when citing a self-contradiction within the SAME
     audited skill (the `file` and `source` reference the same SKILL.md).
   For `scope=plugin` findings, the valid forms are exactly the live-doc URL, the
   `changelog:<version>`, or the plugin's OWN `<marketplace-skill-path>/SKILL.md:<line>`
   self-contradiction. Do NOT cite `~/.claude/skills/shared/<file>` — those are the
   auditing user's protocols, not canonical for a third-party skill.
   Cross-skill citations (e.g., a finding on `/jr-audit` whose `source` cites
   `/jr-review`'s line N) are NOT primary evidence — they're sibling-skill conventions
   and may themselves drift. If a finding is grounded in a sibling skill, cite the
   underlying authority (live doc OR shared protocol) as `source` and mention the
   sibling skill in `description` as supporting context. Findings whose `source`
   is a sibling skill are routed to ACTION REQUIRED. Findings without any source
   citation are routed to ACTION REQUIRED so reviewer-quality issues surface
   rather than being silently dropped.
3. Stay within your dimension's ownership. If a finding belongs to another
   dimension, defer to that reviewer.
4. Calibrate confidence honestly. Use `speculative` when you cannot verify.
5. **Set `clarify: true` when the recommendation is genuinely workflow-dependent**
   (e.g., "this skill could use --converge but maybe your workflow doesn't need
   iterative refinement"). Provide a one-sentence `clarificationQuestion` the
   user can answer in Phase 4. Use sparingly: clarify is for judgment calls, not
   for findings you weren't sure about technically (use `speculative` for those).
6. Drop `low` severity unless the fix is trivial.
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

Every reviewer finding must include:
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

1. **codeExcerpt sanity-check** — Read `<file>` from `line-1` to `line+1` (clamped to `[1, file-end]` for findings near file boundaries), normalize whitespace, exact match. Reject mismatches with `[REJECTED — codeExcerpt mismatch]` and increment the per-reviewer rejection counter.
2. **Source-citation validation** — for every finding, validate the `source` field:
   - URL form (`https://...`) → strip the trailing citation-format suffix first: match `:[a-zA-Z#_][^:/]*$` (a colon followed by an identifier or `#anchor` at the end of the string, no path separator). This deliberately does NOT match `:` followed by digits (port numbers) or `:` mid-path. The remaining base URL MUST be a key in `cache/refs.json` whose `ok: true`. Mismatched URLs go to `ACTION REQUIRED` (not silent drop). Do NOT re-WebFetch — the cache is the source of truth for this run.
   - `changelog:<version>` → MUST appear as a `## <version>` heading in the cached changelog content.
   - `~/.claude/skills/shared/<file>:<line>` → re-Read and confirm the cited line exists. Mismatches → `ACTION REQUIRED`. **On a `scope=plugin` finding this form is invalid regardless of whether the line exists** — route to `ACTION REQUIRED` (`third-party skill measured against the user's shared protocols`); without this guard the existing line would wrongly pass and defeat the third-party preamble.
   - `<skill>/SKILL.md:<line>` → re-Read and confirm (generic re-Read, no path prefix — accepts a plugin's `marketplaces/.../SKILL.md` self-contradiction path). Mismatches → `[REJECTED — citation broken]`. For `scope=plugin` findings, the cited path MUST resolve within the plugin's canonical tracked tree (`<root>/<relpath>/` from Track B step 3); a path outside it → `[REJECTED — citation outside plugin tree]` (stops an adversarial third-party SKILL.md from steering a validation-time Read elsewhere).
   - Missing or malformed `source` → `ACTION REQUIRED: <dimension>-reviewer omitted source citation on finding "<title>" (<file>:<line>). Reviewer-quality issue.`
3. **Dedup** — group findings by `(file, line, dimension)`. Cross-dimension duplicates on the same line are flagged with `[CROSS-DIM]` for the user.
4. **Per-reviewer 25%-rejection escalation** — if any reviewer rejected ≥ 25% of its findings (excluding ACTION REQUIRED routings), flag a Phase 7 `ACTION REQUIRED`: `<dimension> reviewer had a high hallucination rate this run (N/M rejected). Consider re-running with --only=<other-dimensions> and treating <dimension> output cautiously.`
5. **Sort** by severity → confidence → file path.
6. **Partition by `clarify`**: findings with `clarify: true` move to a "Needs clarification" tier. The remaining findings sort into the standard Critical/High/Medium/Speculative tiers.

## Phase 4 — User approval gate

If `--auto-approve` is set, **skip this phase entirely** (and skip the [Clarify] flow) and proceed to Phase 7. Findings flagged `clarify: true` render in their original tier with a `[CLARIFICATION SKIPPED — auto-approve]` qualifier so the user can revisit them manually.

### Conditional advisor (mandatory trigger)

Before rendering the menu, call `advisor()` if EITHER:
- Total finding count ≥ 20, OR
- Any single dimension contributes ≥ 60% of all findings (skewed-reviewer signal).

Pass: total findings, per-dimension breakdown, top 3 critical/high titles, reference-fetch status (fresh/stale/missing). **Single-fire**: do not call advisor again in this phase.

### [Clarify] flow (before tier menu)

If any findings have `clarify: true`, present them one at a time **before** the standard tier menu so the user resolves judgment calls in-line:

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

After all clarify findings are resolved, proceed to the tier menu below. The clarify flow is **not** subject to the per-phase advisor single-fire guard above; the advisor fires (if it fires at all) once total findings cross the threshold, regardless of which tier they end up in.

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

### Declare-done advisor (gated on non-triviality)

Before rendering the final report, call `advisor()` IF ANY of these non-triviality predicates is true (otherwise skip — `shared/advisor-criteria.md`'s "Unconditional advisor on every run" anti-pattern says trivially-clean small runs shouldn't burn budget):

- `findingCount >= 5`, OR
- `dimensionCount >= 3` (i.e., `--only=` was not narrow), OR
- `rejectionCount >= 1` (Phase 3 codeExcerpt or citation validation rejected at least one finding — reviewer-quality signal worth a second opinion), OR
- An abort condition fired in any earlier phase.

Pass: total findings, per-dimension breakdown, abort status (if any), and reference-fetch status. Skip entirely in `--auto-approve` mode where the user has already opted out of all gates. Phase 7 has no loop, so no single-fire flag is needed; the call site is reached at most once per run by construction.

If the advisor flags concerns about reviewer drift or an over-narrow dimension mix, surface them inline at the top of the report under `ADVISOR NOTES:` so the user sees them alongside the findings.

### Final report

Print the report below. **No file is written in v1** beyond the cache update — archival report file is tracked in issue #19.

### Report structure

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /jr-skill-audit — Findings Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Skills audited: <names>   Dimensions: <selected>   Findings: N (X dropped, Y kept)
Roots: personal=<personalRoot>   project=<projectRoot(s)>   [auto-scoped to project — --scope-only=both to include personal]
By scope: personal=<n> (skills: <p-list>)   project=<m> (skills: <j-list>)
Plugin: <name>  (marketplace: <mp>, source repo: <url>)  [third-party — verify against plugin docs]

Reference fetch status:
  skills-doc            ✓ fresh (2026-05-09)
  env-vars-doc          ✓ fresh
  claude-code-changelog ⚠ stale (cached 2026-04-12, > 30 days)
  Hint: re-run with --refresh-refs to update.

═══ Critical (n) ═══
[1] [personal] <skill>/SKILL.md:<line>   <dimension>   <title>
    <description>
    Recommendation: <recommendation>
    Source: <citation>
    Excerpt:
      <line-1>
      <line>
      <line+1>
[2] [project]  <skill>/SKILL.md:<line>   <dimension>   <title>
    ...

═══ High (n) ═══   ... (same format)
═══ Medium (n) ═══ ... (same format)
═══ Speculative (n) ═══ ... (only if --auto-approve was set OR Tier 3 was approved)

═══ Action items (n) ═══
All N approved findings above require user action. Roll-up by tier and skill:
  Critical: <c>   High: <h>   Medium: <m>   Speculative: <s>
  By skill: <skill1>[personal] (<n1>), <skill1>[project] (<n2>), <skill2> (<n3>), ...   # tags ONLY on names that collide across scopes
  [Clarify] items still awaiting decision: <count> (referenced by index above)

Audit integrity (n):
  <items from Phase 3 sanity-check + reviewer-quality issues — codeExcerpt rejections, missing source citations, ≥25% reviewer rejection rate>
  (Empty section means the audit itself was clean — distinct from "no findings".)

Summary: N findings across M skills.   Total: <elapsed>
```

**Scope-tag rendering rules** (single-scope simplifications):
- **`Roots` line**: always rendered on a personal/project run, never omitted — it is the report's only unconditional statement of which directories were audited, and under the auto-scope default the same command audits different skills in different directories, so a report without it is ambiguous. List the roots named by `effectiveScope` — the authoritative record of what was audited (`protocols/personal-project-scope.md`). Append the `[auto-scoped to project — …]` qualifier only when `autoNarrowed=true` **and the run did not abort**, never when `autoScope=project` was merely computed. The abort carve-out matters because the fallback's empty arm leaves `autoNarrowed=true` deliberately (`protocols/personal-project-scope.md`), and that arm is reached only after the fallback has already restored personal and found nothing auditable there: the qualifier's `--scope-only=both to include personal` advice would send the user to a scope this very run just tried and exhausted. On an aborting run the guard's own message states the cause, so the qualifier adds nothing but a false lead. Omit the line only on a `--plugin` run, where the `Plugin:` header already names the source.
- **`By scope` rollup line**: render only when `count(distinct scopes in approved findings) > 1`. When a run produces findings in just one scope, drop the `By scope:` line entirely.
- **Inline `[personal]` / `[project]` tag on each finding**: render only when the same scope-count check is `> 1`. When findings are single-scope, drop the bracket prefix (no ambiguity to disambiguate). Two-space pad after `[project]` keeps the column aligned with `[personal]`.
- **`By skill` rollup in Action items**: only append `[personal]` / `[project]` to skill names when the same name appears in both scopes (collision case). Otherwise the bare name suffices.
- **Plugin runs (`--plugin`) override the single-scope simplification**: always render the `Plugin: <name> (…, source repo: <url>) [third-party — verify against plugin docs]` header line (in place of `By scope:`) and an inline `[plugin: <name>]` prefix on every finding — even though a plugin run is single-scope — because the report must always surface which plugin the finding is about and that it is third-party. **Two-marketplace collision** (a `<name>` resolved in two marketplaces — the audit-both case): qualify every per-finding tag, the `Skills audited:` list, the `By skill` rollup, and the Phase 1 `plugin=<name> (skills: …)` discovery-summary segment as `<name>@<mp>` so same-named skills from different marketplaces stay distinguishable, and repeat the `Plugin:` header line once per marketplace.

**Naming contract**: The "Action items" rollup is **mandatory** on every report — never omitted, never empty when findings > 0. It is the single answer to "what do I need to do?". The "Audit integrity" section is a meta-section about the audit run itself (reviewer-quality, citation validity); an empty Audit-integrity section means the audit was clean, NOT that the user has nothing to act on. Past versions of this skill conflated the two via an "ACTION REQUIRED" label that was scoped to the meta-section only — that conflation caused the lead to render "ACTION REQUIRED: None" while leaving 28 findings un-rolled-up. Do NOT reuse the "ACTION REQUIRED" label.

### Abort-mode reporting

On any abort condition, render the marker per `../shared/abort-markers.md` (the canonical source). The three `abortReason` values skill-audit emits are:

| `abortReason` | Marker (rendered by canonical) | When |
|---------------|--------------------------------|------|
| `unmatched-scope` | `[ABORT — UNMATCHED SCOPE]` | Phase 1 Track B discovered zero skills |
| `shared-file-missing` | `[ABORT — SHARED FILE MISSING]` | Phase 1 Track A hard-fail guard tripped |
| `user-abort` | `[ABORT — USER ABORT]` | User chose `[Abort]` at any approval gate |

Track C failures do NOT trigger abort — they degrade gracefully (stale cache → warning; no cache → skip `feature-adoption-reviewer`).

## Phase 8 — Optional: file follow-up issues (future)

**Not implemented in v1** (tracked in issue #16). When implemented, would create a GitHub issue per `Critical` finding (analogous to `/jr-audit` Phase 8) so high-severity findings get tracked outside the conversation.

## Edge cases

The full case→behavior reference table lives in `${CLAUDE_SKILL_DIR}/edge-cases.md` (loaded on demand — reference material, not read at Phase 1). It covers auto-scope behaviors (foreign repo with/without skills, filtered runs, worktrees), plugin object-source handling, two-marketplace collisions, CWD-under-personal-root, `--add-dir`, model-alias drift, `disable-model-invocation` description weight, `gh`-unavailable degradation, and `--scope-only` edge behaviors.
