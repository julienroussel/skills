# Skill anatomy & extraction architecture

**When to load**: bring this doc into context with `@docs/skill-anatomy.md` when (a) adding a new skill, (b) extracting content from an existing `SKILL.md`, (c) deciding where a new piece of content belongs, or (d) onboarding a contributor to the repo. Not auto-loaded — the per-session token cost outweighs the benefit on day-to-day skill *use*.

This doc explains the *framework* this repo uses, not any specific skill's behavior. For per-skill behavior, read the relevant `SKILL.md`.

---

## The five tiers

Content in this repo lives in one of five places. Each tier has a distinct purpose, lifecycle, and token-cost profile.

| Tier | Path shape | Loaded when | Token cost |
|------|-----------|-------------|------------|
| **SKILL.md body** | `<skill>/SKILL.md` | Once per session that lists or invokes the skill | Recurring across the whole session per the skills-doc lifecycle: every line is paid every turn |
| **`shared/*.md`** | `shared/<name>.md` | At Phase 1 Track A of the consuming skill (under hard-fail + smoke-parse guard) | Recurring within the run, but skipped entirely on sessions that don't invoke a consumer |
| **`<skill>/protocols/*.md`** | `<skill>/protocols/<name>.md` | Same as `shared/*.md`, but only one skill consumes it | Same as shared/ — pay-on-run, not pay-on-list |
| **`<skill>/scripts/*.sh`** | `<skill>/scripts/<name>.sh` | Executed via Bash; content never enters context unless the lead Reads it for debugging | Zero context cost (executable; output may enter context) |
| **`<skill>/templates/*`** | `<skill>/templates/<name>.<ext>` | Read by a script (typically with SHA-256 verification before use) | Zero context cost unless the lead Reads it directly |

Two tiers above the table are out of scope here:
- `CLAUDE.md` — repo-level constants and conventions, loaded into every session in this repo. Use sparingly; everything in it pays the everyone-everywhere tax.
- `docs/*.md` — narrative explainers loaded on-demand via `@docs/<file>.md` (this file is one).

---

## Where does new content go?

Apply this decision tree top-to-bottom. The first rule that matches wins.

1. **Is it executable code (bash, python, etc.)?** → `<skill>/scripts/`. Don't put shell logic in `SKILL.md` prose; the model has to parse the prose, then re-emit the bash, and any escape-sequence drift breaks silently. A script is a single source of truth that the model invokes via Bash.

2. **Is it a static blob the model shouldn't be free to rewrite (regex catalogs, hook templates, schema literals)?** → `<skill>/templates/`. Always read it from disk; for security-critical templates (e.g., the pre-commit hook body), the consuming script should SHA-256-verify it before use.

3. **Is it consumed by two or more skills?** → `shared/*.md`. The whole point of `shared/` is to eliminate inline duplication between consumers. If only one skill needs it, put it under that skill (next rule).

4. **Is it a procedure of more than ~30 lines, consumed at one phase, with stable boundaries?** → `<skill>/protocols/`. Examples: Phase 5.6 pre-commit hook offer, Phase 7 cleanup body, Phase 8 follow-up issues. The skill body shrinks; the procedure lives in one place that's loaded under the same hard-fail discipline as `shared/*.md`.

5. **Is it a one-paragraph rule or a tight 3–5 line procedure tied to a specific phase?** → keep inline in `SKILL.md`. Extracting a 5-line block to its own file costs more in cross-reference cognitive load than it saves in line count.

6. **Is it narrative documentation about the *framework itself* (cross-component contracts, architecture decisions, onboarding context)?** → `docs/*.md` (this file is an example). Loaded on-demand via `@docs/`.

### Quick examples

| Content | Tier | Why |
|---------|------|-----|
| Bash command to compute merge-base | inline in SKILL.md | One-liner; extracting wastes tokens |
| Combined revert sequence (clean → rm-f → checkout → reset) | `<skill>/protocols/base-anchor.md` | ~50 lines, one consumer (`/jr-review`), stable boundary |
| Severity rubric `critical|high|medium|low` | `shared/reviewer-boundaries.md` | Two consumers (`/jr-audit`, `/jr-review`); passed verbatim into reviewer prompts |
| Forge `gh`↔`glab` command/field mapping | `shared/forge-detection.md` | Multiple consumers (`/jr-audit`, `/jr-review`, `/jr-ship`); the `bin/` CLIs mirror the detection natively. Note the external-authority `gh api` carve-out — a shared rule consumed identically, not a per-consumer carve-out |
| Pre-commit hook body | `<skill>/templates/pre-commit-secret-guard.sh.tmpl` | Static blob; SHA-256 verified before append; must NOT be model-rewritten at runtime |
| `establish-base-anchor.sh` | `<skill>/scripts/` | Executable; needs deterministic output |
| When to use `--branch` vs `--pr` vs bare `/jr-review` | inline in SKILL.md (Arguments section) | Per-skill UX detail; nobody else needs it |
| Tackle ↔ ship marker contract | `docs/worktree-architecture.md` | Cross-component contract; neither side owns it |

---

## The smoke-parse anchor convention

Every `shared/*.md` and `<skill>/protocols/*.md` file declares (implicitly) a **load-bearing substring** that consumers verify with `grep -F` after Read. The substring is a string that *must* be present in the file for it to be functional — typically a heading, a key identifier, or a canonical command.

### Why anchors exist

A non-empty file isn't necessarily a *correct* file. Consider a file truncated mid-table by a botched edit: the Read returns 3 KB of content (passes the non-empty check), but the section the consumer needs isn't there. The smoke-parse catches that.

### Naming the anchor

Pick a substring that is:

1. **Load-bearing** — if it disappears, the file is functionally broken. Examples: a key heading (`Severity calibration rubric`), a canonical command (`git ls-files --error-unmatch`), a load-bearing identifier (`freshEyesMandatory`).
2. **Stable across reasonable rewordings** — don't anchor on prose that authors might tweak (`This protocol applies to...`). Anchor on names, headings, or command literals.
3. **Specific enough to be unique** — don't anchor on `Phase 1 ✓` if the file is shared across consumers that all use that string. Pick something the file uniquely contains.
4. **Distributed across the file** — a single top-of-file anchor doesn't catch mid-file truncation. **2 anchors minimum** for files > 100 lines (one near the top, one near the middle or end). **3 anchors (top/middle/bottom) for files > 200 lines** — without an end-of-file anchor, a truncation that drops the second half passes both top and middle checks. Worked example: `convergence-protocol.md` originally used 2 anchors (`priorFindings`:24, `freshEyesMandatory`:142) both in the top half of a 164-line file, leaving everything after line 142 open to silent truncation. A third bottom anchor (`Proceed to Phase 7 (cleanup and report)`:163) closes the gap (resolved issue #22).

### Where the anchor lives

There are two patterns, by file type:

**`shared/*.md`** — anchors live in **`shared/phase1-track-a-protocol.md`**'s Canonical Anchor Table. Each row maps a shared file to its required substrings; every consumer applies the same algorithm against this table at runtime. Consumers do not declare per-file anchors. Example row from the canonical:

```
| `reviewer-boundaries.md` | `\| Issue` AND `\| Owner` AND `\| Not` AND `Severity calibration rubric` AND `Confidence levels` |
```

The earlier pattern (anchor lists duplicated in every consumer's Phase 1 Track A) had four copies — `/jr-audit`, `/jr-review`, `/jr-skill-audit`, and `/jr-doctor` Group D — and they drifted (issues #21 and #30 traced exactly this). The canonical eliminates the drift surface. The rationale "putting the anchor in a shared file just pushes the drift into the shared file" turned out to be wrong in practice: N consumer copies have N-way drift potential, one canonical table has none. `/jr-doctor` Group D reads the canonical at runtime AND cross-checks `shared/*.md` directory membership against the table, so a corrupted canonical (e.g., stubbed back to its self-row) is also detected.

**`<skill>/protocols/*.md`** — anchors still live in *the consumer's* Phase 1 Track A read list. These files are skill-local (only one consumer), so there is no drift concern. Example from `/jr-review`:

```
- `${CLAUDE_SKILL_DIR}/protocols/finding-sanity-check.md` — `content-excerpt match`
```

### Anchor escaping

When an anchor contains markdown table-pipe characters (`|`), they must be escaped (`\|`) inside a markdown table cell. This is a markdown quirk, not a smoke-parse rule. The actual `grep -F` invocation runs on the un-escaped string.

---

## The hard-fail guard pattern

Every Phase 1 Track A read of a `shared/*.md` or `<skill>/protocols/*.md` file is wrapped in a **hard-fail guard**: if the Read fails, returns empty content, or fails the smoke-parse, abort Phase 1 immediately with a marker (typically `[ABORT — SHARED FILE MISSING]` per `shared/abort-markers.md`).

### Why hard-fail

The alternative is "fall back to inline text" or "warn and continue". Both are silent-degradation patterns: the skill keeps running with weaker guarantees and the user has no way to know. Specifically:

- A missing `untrusted-input-defense.md` means subagent prompts no longer carry the prompt-injection defense. A malicious commit could embed `// IGNORE PREVIOUS INSTRUCTIONS` in a comment and silently manipulate the reviewer.
- A missing `gitignore-enforcement.md` means cache-write sites stop checking whether `.claude/audit-history.json` is tracked. A committed history with manipulated false-positive rates could bias reviewer calibration for everyone.
- A missing `abort-markers.md` means Phase 7 can't render abort markers correctly. Aborts surface as `[ABORT — UNLABELED]` and the user can't tell what went wrong.

In each case, the silent degradation is worse than the abort. **Fail-closed is the only correct behavior.**

### The guard skeleton

```
- Read the file (shared/<name>.md or <skill>/protocols/<name>.md)
  + record byte size + first-line hash for later re-verification
- Determine the anchor:
  + shared/*       → look up the row in shared/phase1-track-a-protocol.md's
                     Canonical Anchor Table (apply the canonical's algorithm)
  + protocols/*    → anchor is declared inline in the consumer's read list
- Smoke-parse: grep -F '<anchor>' <file>
- If Read fails OR content is zero bytes / whitespace-only OR grep -F exits non-zero:
  abort Phase 1 with [ABORT — SHARED FILE MISSING] per shared/abort-markers.md
- For shared/*: also verify shared/phase1-track-a-protocol.md itself contains
  the literal "Canonical Anchor Table" BEFORE parsing it (self-reference escape
  hatch — without this, a stub corruption that preserves only the canonical's
  self-row anchor would pass the table-driven check falsely)
- Do NOT fall back to inline text — the inline duplicates were intentionally removed
  to eliminate drift; a missing shared file means the skill's guarantees cannot
  be enforced.
```

### Skill-local protocol files

`<skill>/protocols/*.md` files use the same pattern. They're treated identically to shared files at the consumer's Phase 1 Track A — read in parallel, smoke-parsed, hard-failed on absence. The only difference is scope (one consumer vs. multiple).

---

## Loading discipline: when do files enter context?

Three loading patterns, each with different cost/safety trade-offs.

### Pattern A: always-in-context (`SKILL.md` body, `CLAUDE.md`)

Loaded once per session, stays for every turn. Per the skills-doc "Skill content lifecycle": *every line is a recurring token cost*. Use this tier *only* for:

- Per-session standing instructions (frontmatter, conventions, suppressions)
- The skill's phase scaffolding (Phase 1 → Phase N, with the procedural body)
- Cross-cutting rules that apply throughout (severity rubric *summary*, not the canonical body)

The 500-line skills-doc tip is a soft cap on this tier. `/jr-review` at 640 lines is over the cap — issue #20 tracks getting it under.

### Pattern B: Phase 1 Track A under hard-fail guard (`shared/*.md`, `<skill>/protocols/*.md`)

Loaded when the skill *runs*. The Read happens at Phase 1 Track A, content stays in the run's context until completion. Use this tier for:

- Multi-paragraph rules consumed at one or more later phases
- Procedures that are too long to inline gracefully
- Schema definitions, regex catalogs, marker enums
- Anything that must be available before the consuming phase fires (because reading it on-demand mid-phase risks the file being missing exactly when needed)

This is the right default for content > 30 lines. The hard-fail guard ensures the skill can't run with the file missing — there's no silent degradation.

### Pattern C: on-demand at the consumer phase (rare)

Read at the moment the content is needed, no Phase 1 pre-load. Use this tier *only* when the consumer phase is itself optional and may not run, AND when the content is genuinely peripheral. In practice, this repo doesn't use Pattern C — the Phase-1-Track-A pre-load is cheap enough that on-demand reads aren't worth the complexity.

### Which pattern to pick

If in doubt, **default to Pattern B**. The Phase-1-Track-A pre-load is the same cost as on-demand and it gives you the fail-closed property for free. Pattern A is the most expensive tier; only put content there if it's genuinely needed across the whole session.

---

## `allowed-tools` narrowing

Skills that grant `allowed-tools` pre-authorize the listed tools without per-call confirmation. Two competing pressures:

- **Too narrow** → user gets prompted on every step, skill stalls in `--auto-approve` / headless mode.
- **Too broad** → destructive operations execute without user oversight (e.g., a blanket `Bash(rm -rf .claude/*)` lets the lead wipe audit trails without confirmation).

### Rules of thumb

1. **Scope to the actual paths and subcommands used.** `Bash(mv .claude/*)` not `Bash(mv *)`. `Bash(git -c core.symlinks=false checkout *)` not `Bash(git -c *)`. Each tool entry should reflect a real call site, not a category.
2. **Prefer per-call confirmation for irreversible operations.** `git push --force`, `git reset --hard`, `gh pr merge`, `rm -rf` outside `.claude/` should NOT be in `allowed-tools` — let the user confirm each invocation.
3. **Add a frontmatter-notes HTML comment block when omissions are deliberate.** Example from `/jr-review`:
   ```
   <!-- Frontmatter notes (load-bearing):
   - allowed-tools deliberately PROMPTS for: arbitrary rm, destructive git
     (checkout/reset/clean/commit/rm/add) outside the implementer-managed
     revert sequence, gh pr comment/create/merge, gh issue create, and any
     Write/Edit OUTSIDE .claude/** and .gitignore. These mutate user code or
     external state and should remain a per-call decision.
   -->
   ```
   This is documentation for future-you: a year from now, you'll wonder why some destructive op isn't pre-authorized. The note explains the omission was intentional.
4. **Auto-authorize agent-management + scoped writes.** `AskUserQuestion`, `Agent`, `advisor`, `Write(.claude/**)`, `Edit(.claude/**)`, `Write(.gitignore)`, `Edit(.gitignore)` are needed by every documented phase; absent these the skill stalls on permission prompts. Do **not** grant `TaskCreate`/`TaskList`/`TaskGet`/`TaskUpdate`: the lead does not have them, no `agent-teams` reviewer role has `TaskCreate`, and granting them in `allowed-tools` advertises a reporting channel that silently loses findings.
5. **Spawn work-producing subagents WITHOUT `name:`** (canonical: `shared/subagent-reporting.md`). A subagent's final response returns to the lead only when it is unnamed; `name:` makes it a persistent teammate that goes idle instead of returning, and its findings are lost with no error anywhere (issue #70). `name:` buys mid-flight addressability, which no documented phase needs. Give each spawn a distinct `description` instead — that is what the progress display renders. The lead must also **roll-call** its spawn list against the results actually returned: a subagent that returns nothing is `UNREPORTED`, never a clean dimension, and that state must be rendered, must set a non-zero exit, and must block every clean-result path. `TeamCreate`/`TeamDelete` were removed in 2.1.178 and must not be re-introduced.

---

## Shared file write rules

When *modifying* a `shared/*.md` or `<skill>/protocols/*.md` file:

1. **Preserve the smoke-parse anchor.** If the canonical row says `git ls-files --error-unmatch` is required, that exact string must remain in the file. Re-wording the canonical command breaks every consumer's Phase 1 Track A.
2. **Update the right anchor location.**
   - For `shared/*`: update the row in `shared/phase1-track-a-protocol.md`'s Canonical Anchor Table. Single source of truth — every consumer verifies against this table at runtime, so no consumer-by-consumer follow-ups.
   - For `<skill>/protocols/*`: update the consumer's Phase 1 Track A read list directly. Only one consumer; no canonical exists.
3. **Don't introduce per-consumer carve-outs.** If `/jr-audit` needs section X but `/jr-review` doesn't, that's a sign the section belongs in `<audit>/protocols/` rather than `shared/`. Shared files should be consumed identically by all consumers.
4. **Bump dates / verification stamps when applicable.** `shared/advisor-criteria.md` has a `Last verified` footer that should be updated when the file is reviewed against Anthropic's published guidance.
5. **Adding a new `shared/*.md` file**: follow the "Rules for adding a new `shared/*.md` file" section in `shared/phase1-track-a-protocol.md` (create file → choose anchor → add row to canonical table → update consumer read lists → update CLAUDE.md inventory → run `/jr-doctor` to confirm Group D coverage). Also update `jr-doctor/scripts/skill-drift-check.sh` if the file has consumer-inlining risk (most shared files do).

---

## Drift detection

Two skills exist specifically to keep this architecture from drifting:

| Skill | Coverage | Trigger |
|-------|----------|---------|
| `/jr-doctor` Group I | Narrow yes/no factual checks: SKILL.md line count, broken `shared/*` references, frontmatter validity, inline duplication of canonical content (via anchor match), pre-commit-hook template SHA-256 drift, `/jr-skill-audit` refs-cache freshness | Run `/jr-doctor` periodically; fast, no agents |
| `/jr-skill-audit` | Opinionated multi-dimension audit (frontmatter, advisor-coverage, token-efficiency, shared-drift, feature-adoption, safety-protocols). Cites live Anthropic docs (skills doc, CHANGELOG) at runtime | Run after structural changes to skills; `/jr-skill-audit <skill>` for one skill |

**Run both of these regularly.** The architecture pays for itself only if drift gets caught early. A `shared-drift-reviewer` finding ("inline duplication of `untrusted-input-defense.md` content at `/jr-audit/SKILL.md:432`") is the canonical signal that someone forgot to reference the shared file and copy-pasted instead.

### Re-verifying a harness claim

Some shared files assert **harness behaviour** — which tools a role has, whether a spawn returns its result, what an env var exposes, what a CLI's JSON fields are called. These are volatile: they can change with any Claude Code or plugin release, and unlike a claim about repo content they cannot be settled by reading the repo. `shared/subagent-reporting.md` ("Verified behaviour") and `shared/forge-detection.md` (§c) both carry dated, sourced tables of this kind.

When re-verifying one after an upgrade:

- **Vary one parameter at a time.** The `subagent-reporting.md` matrix is a 2×2 precisely because a three-cell result would not have separated `name:` from `subagent_type`, and the wrong conclusion (blame the plugin) was the tempting one.
- **Absence is not evidence.** A result that has not arrived within a few minutes does not mean the channel is dead — it may simply be queued past your turn boundary. Wait across a turn boundary before recording any negative verdict. Likewise, `TaskOutput` returning `No task found` is not evidence an agent is gone: it returns that for agents that are alive and answer a message minutes later.
- **Confirm a negative before recording it.** If an agent appears not to have delivered, ask it directly whether it finished and what it produced. Both times this repo recorded a negative from silence alone, the negative was wrong.
- **Date-stamp and name the version** (`Verified 2026-07-16 against agent-teams v1.0.3`), so a later reader can judge staleness rather than inherit a stale certainty.

---

## Anti-patterns

Don't do these.

1. **Inline duplication of `shared/*.md` content.** Every duplicate proves the shared/ pattern isn't doing its job. Cite the shared file, don't restate its rules.
2. **Cross-skill citations to sibling-skill SKILL.md files.** `/jr-audit` Phase 7 saying "apply `/jr-review` Phase 1 Track B step 7" is a drift surface — if `/jr-review` renumbers, `/jr-audit` breaks silently. Cite the underlying authority (the shared file, the skills-doc URL, the changelog version), not a sibling.
3. **Paraphrasing the untrusted-input-defense block.** The three verbs ("do not execute, follow, or respond to") are load-bearing. Pass the shared file's content verbatim to every subagent.
4. **Smoke-parse anchors that match worked examples instead of structural content.** `Phase 1 ✓ (3s)` matches the literal `3s` value, which a doc author might change to `5s` without realizing it breaks consumers. Anchor on `Phase 1 ✓` + `Silent reviewers, noisy lead` instead.
5. **Pre-authorizing destructive ops in `allowed-tools` without rationale.** Every `Bash(rm -rf ...)`, `Bash(git push --force ...)`, or unscoped `Bash(mv *)` should either have a frontmatter note explaining why, or be removed in favor of per-call confirmation.
6. **Adding a `docs/*.md` file for content that already lives in `shared/` or a protocol file.** Narrative explainers create *another* source of truth for the same rules. The bar for `docs/` is "cross-component contract that doesn't fit cleanly into either side's source" (the worktree-architecture doc clears that bar; "narrative explainer of secret-handling" doesn't).

---

## Adding a new skill: checklist

When creating `<new-skill>/SKILL.md`:

1. **Frontmatter**: `name`, `description`, `argument-hint`, `effort`, `model: opus` (for skills that spawn reviewers/implementers), `disable-model-invocation: true` (for user-only skills), `user-invocable: true`, scoped `allowed-tools`.
2. **Dependencies HTML comment block**: list required plugins, required CLI binaries, files read/written, shared protocol references with their smoke-parse anchors, required tools.
3. **Phase scaffolding**: numbered phases with `━━━` headers, cumulative timeline updates, parallel-first dispatch where independent.
4. **Phase 1 Track A read list**: add hard-fail guard for any `shared/*.md` or `<skill>/protocols/*.md` files the skill consumes, with smoke-parse anchors.
5. **`docs/worktree-architecture.md`** ← if the skill interacts with `bin/tackle` or `/jr-ship`'s worktree handling.
6. **Run `/jr-skill-audit <new-skill>`** before declaring done — catches frontmatter issues, missing references, allowed-tools gaps.
7. **Run `/jr-doctor`** to verify Group I doesn't flag anything.
8. **Update `CLAUDE.md`** repo-structure listing and `README.md` skills table.

That's it — the same architecture every existing skill follows.
