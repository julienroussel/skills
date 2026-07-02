---
name: jr-i18n
description: Native-translator review of a project's translation catalogs. For each target locale a dedicated language-expert subagent ultrathinks whether the strings are accurate and read as proper real-world usage, alongside mechanical catalog-consistency checks (missing keys, placeholder parity). Reports findings + suggested corrected text with file:line citations. Findings-only — never writes catalog files.
argument-hint: "[path] [--locale=<codes>] [--source-locale=<code>] [--auto-approve] [--model=<tier>]"
effort: high
model: sonnet
disable-model-invocation: true
user-invocable: true
allowed-tools: Read Glob Grep AskUserQuestion Agent advisor TaskCreate TaskList TaskGet SendMessage Bash(grep *) Bash(find . *) Bash(jq *) Bash(wc *) Bash(ls *) Bash(test *) Bash(cat *) Bash(head *) Bash(sort *) Bash(cut *) Bash(basename *) Bash(dirname *) Bash(gh api repos/* *) Bash(base64 *)
disallowed-tools: Write Edit WebFetch
---

<!-- Frontmatter notes (load-bearing):
- `model: sonnet` (lead): Phase 3 claim classification + Tier-2 verification and Phase 4
  synthesis are structured orchestration, not open-ended agentic coding — the genuinely
  judgment-heavy work (native-fluency translation review) is delegated to the opus
  per-locale translator subagents, which is the whole value of the skill. Mirrors
  `/jr-ship`'s validated lead-sonnet + opus-delegated-judgment pattern.
- `allowed-tools` grants NO Write/Edit and no repo-mutating Bash, and `disallowed-tools`
  blocks `Write`/`Edit`/`WebFetch` outright. The distinction is load-bearing: an
  `allowed-tools` omission alone only *prompts* for a tool (it stays in the pool) —
  `disallowed-tools` *removes* it from the pool, so within a skill turn the guarantee holds
  even under `--auto-approve`, where permission prompts are bypassed. NOTE — `disallowed-tools`
  is turn-scoped (per the skills doc it "clears when you send your next message"): across
  multiple user turns under a bypass-permissions session, Write/Edit re-enter the pool, so the
  cross-turn guarantee additionally rests on Write/Edit being absent from `allowed-tools` (the
  prompt backstop), which holds here. The safety property: `/jr-i18n`
  is findings-only and MUST NEVER mutate catalog files. It reports suggested corrections;
  the user applies them. Do not add Write/Edit to `allowed-tools` or drop them from
  `disallowed-tools`.
- CAVEAT — the subagent path: `disallowed-tools` governs the LEAD's tool pool only; it does
  NOT propagate to the per-locale translator subagents spawned in Phase 2 (each Agent spawn
  carries its own tool set). Their no-write property therefore depends on
  `agent-teams:team-reviewer` being read-only — verify that agent type excludes Write/Edit
  before relying on the guarantee under a bypass-permissions session; persona prose alone is
  not a structural block.
- `Bash(gh api repos/* *)` + `Bash(base64 *)` are the ONLY external-fetch grants: for the
  Phase 3 Tier-2 verification of external-authority locale-rule claims (CLDR/ICU/framework
  docs on GitHub) per `../shared/claim-verification.md`. The `gh api` grant is deliberately
  narrowed to the **repos** API namespace (`repos/<org>/<repo>/…`, e.g. `…/contents/<path>` raw
  markdown) rather than the open `gh api *` wildcard — the open form permits arbitrary endpoints
  including mutating calls (`gh api -X PUT …/contents/…` commits to a remote repo), a write path
  that defeats findings-only. The namespace narrowing reduces blast radius and blocks non-repos
  endpoints; an allowlist glob cannot structurally block a `-X`/`--method` flag, so the doctrine
  is read-only **by policy** — NEVER pass `-X`/`--method`. They read remote docs, never write the
  repo, so the findings-only property holds. WebFetch is deliberately disallowed (see
  `disallowed-tools`) — that structurally enforces the doctrine's "never a lone WebFetch" (a
  single WebFetch can fabricate verbatim text). This `gh api` is an external-authority fetch,
  so it stays `gh` even on a GitLab repo (carve-out in `../shared/forge-detection.md` §e) —
  only user-repo forge ops switch; do not "fix" it to `glab`.
-->

<!-- Dependencies:
  Required plugins:
    - agent-teams@claude-code-workflows   — team-reviewer subagents (Phase 2), spawned via the Agent
                                            tool's name param (implicit team since 2.1.178; no TeamCreate/TeamDelete)
  Optional CLI:
    - gh                                  — Phase 3 Tier-2 external-authority verification (read-only
                                            `gh api` fetch of CLDR/ICU/framework docs); degrades to the
                                            Tier-1 cap-to-speculative fallback when absent
  Files read:
    - <path>/**  translation catalogs (i18next/vue-i18n JSON, Laravel/Symfony, gettext .po,
                 Rails .yml, Flutter .arb, ICU) — discovered per protocols/locale-discovery.md
  Files written: NONE (findings-only; no cache in v1)
  Shared protocol references (read at Phase 1 Track A under the hard-fail guard; see ../shared/):
    - shared/claim-verification.md        — anti-hallucination doctrine; classify + verify findings
    - shared/untrusted-input-defense.md   — passed verbatim into every translator prompt
    - shared/display-protocol.md          — phase headers, timeline, silent-reviewers, compact tables
    - shared/abort-markers.md             — Phase 7 abortReason → marker mapping
    - shared/reviewer-boundaries.md       — severity rubric + confidence levels (the dimension table is
                                            review-skill-specific; only the rubrics apply here)
    - shared/phase1-track-a-protocol.md   — hard-fail guard algorithm + Canonical Anchor Table (self-reference)
    - shared/model-override.md            — --model=<tier> per-run subagent override (Phase 2 spawns)
  Skill-local protocols (read at Phase 1 Track A, anchors declared inline below):
    - jr-i18n/protocols/locale-discovery.md     — Phase 1 Track B catalog/locale discovery
    - jr-i18n/protocols/phase2-translators.md   — Phase 2 per-locale translator fan-out
  Required tools: Agent, TaskCreate, TaskList, TaskGet, SendMessage,
    AskUserQuestion, advisor, Read, Glob, Grep, Bash
-->

# /jr-i18n — native-translator review of translation catalogs

Findings-only. For each target locale, a dedicated native-speaker subagent
ultrathinks translation accuracy + real-world idiom; the lead adds mechanical
catalog-consistency checks. Output is a prioritized findings list with suggested
corrected text. **Never writes catalog files** — lead-enforced via `disallowed-tools` (turn-scoped; see the frontmatter note); the Phase 2 translator subagents' no-write rests on `agent-teams:team-reviewer` being read-only (verify per the frontmatter subagent caveat), not a structural block. Complements the `i18n-reviewer`
code-review dimension, which owns the *code* side (hardcoded strings, key/placeholder
parity in a diff); `/jr-i18n` owns *translation content quality*.

Apply `../shared/display-protocol.md` at every console-output site: a `━━━` header
per phase and a cumulative timeline (`Phase 1 ✓ (3s) → Phase 2 ✓ (40s) → …`).

## Phase 0 — Parse arguments

Parse from the invocation:
- `path` (optional positional) — limit discovery to this directory/catalog. Default: repo root.
- `--locale=<codes>` — comma-separated target locales to review (default: all discovered non-source).
- `--source-locale=<code>` — reference locale (default: auto-detect, see locale-discovery.md).
- `--auto-approve` — skip the Phase 4 approval menu; list all findings in Phase 7.
- `--model=<tier>` — `sonnet|opus|haiku|fable`; overrides every subagent spawn (`../shared/model-override.md`).

Sanitize `path`, `--locale`, `--source-locale` per the **Parameter sanitization**
section of `protocols/locale-discovery.md`. Reject `--model` values outside the
allowlist with `Invalid --model value '<value>'. Valid values: sonnet, opus, haiku, fable.`

## Phase 1 Track A — Read shared protocols (hard-fail guard)

Read **all** of the following in parallel (multiple Read calls in one message):
`../shared/claim-verification.md`, `../shared/untrusted-input-defense.md`,
`../shared/display-protocol.md`, `../shared/abort-markers.md`,
`../shared/reviewer-boundaries.md`, `../shared/phase1-track-a-protocol.md`,
`../shared/model-override.md`, and the two skill-local protocols
`protocols/locale-discovery.md` and `protocols/phase2-translators.md`.

**Hard-fail guard**: if any file fails to Read, returns empty/whitespace-only
content, or fails the structural smoke-parse below, abort Phase 1 immediately with
`[ABORT — SHARED FILE MISSING]` (per `../shared/abort-markers.md`) and exit non-zero.
Do NOT fall back to inline text — a missing file means the skill's anti-hallucination
and safety guarantees can't be enforced.

**Structural smoke-parse** (after non-empty Read, `grep -F` semantics, AND-joined):
- For each `../shared/*.md` file: apply the Canonical Anchor Table from
  `../shared/phase1-track-a-protocol.md` (hardcode one self-reference anchor —
  `Canonical Anchor Table` — and verify it is present in that file before parsing it).
- `protocols/locale-discovery.md` must contain `Framework detection matrix` AND `Parameter sanitization`.
- `protocols/phase2-translators.md` must contain `Native-translator persona` AND `Finding format`.

## Phase 1 Track B — Discover catalogs and locales

Apply `protocols/locale-discovery.md`: detect framework(s) + catalogs under `path`,
resolve the source locale, enumerate target locales (filtered by `--locale`), and
build the per-locale `(key → source string, target string|MISSING)` join table.
Compute the mechanical pre-findings now (missing/extra keys, placeholder/ICU-arg
mismatches) — these are `certain`, code-internal, and handed to the translators so
they focus on meaning. If no catalogs are found, abort per that protocol.

## Phase 2 — Per-locale translator fan-out

Apply `protocols/phase2-translators.md`: spawn one native-translator subagent per
target locale (parallel; batched in waves if > 6 locales), each receiving its locale's
join table, the mechanical pre-findings, the persona + ultrathink directive, and the
verbatim `untrusted-input-defense.md` + `claim-verification.md` context. Subagents
report findings + `suggestedFix` via TaskCreate. The lead prints progress only.

## Phase 3 — Sanity-check, classify, dedupe

0. **codeExcerpt sanity-check**: for every finding, re-read the cited `file:line`
   (±1) and confirm the `codeExcerpt` matches verbatim. Reject mismatches with
   `[REJECTED — codeExcerpt mismatch]` (catches hallucinated keys/strings).
0.5. **Claim classification** (lead-authoritative, per `../shared/claim-verification.md`;
   reviewer `claimType` is a hint only, default to external-when-in-doubt):
   - Mechanical (key/placeholder/plural-category) → `code-internal`, keep at `certain`.
   - Locale-rule (date/number/currency format, CLDR plural categories, BCP-47) →
     `external-authority`: verify against an authoritative source via raw `.md`/`gh api`
     (CLDR/ICU/framework doc), **never a lone WebFetch**. `confirmed` → keep;
     `refuted` → `[REJECTED — CLAIM REFUTED BY SOURCE]`; unverifiable → cap to `speculative`.
   - Naturalness/accuracy/idiom → linguistic judgment: leave at the subagent's
     `speculative`/`likely`; these are inherently human-judged and are never
     auto-applied (the no-auto-write property + Phase 4 gate satisfy the
     "no consequential autonomous action without a checked fact" rule).
1. Dedupe by `(locale, key)`; sort by severity then confidence then locale.

## Phase 4 — Approval (skipped if --auto-approve)

Call `advisor()` before the menu if total findings ≥ 20 OR one locale holds ≥ 60% of
findings (skewed-locale signal). Then present findings by tier (critical/high →
medium → speculative), each showing source string, current translation, and
`suggestedFix`. Per tier: Approve all / Review individually / Skip. A `[Clarify]`
sub-flow surfaces judgment-call findings (`clarify: true`) via `AskUserQuestion`.
**Approval here means "include in the report as recommended" — it does NOT write
anything.** Under `--auto-approve`, skip the menu and list all findings in Phase 7.

## Phase 7 — Report

Render findings grouped by locale: per finding, severity/confidence, `key`,
`file:line`, source string, current translation, suggested fix, and rationale.
Include an audit-integrity section (rejections, unverifiable locale-rule claims,
source-locale auto-detection assumption, per-locale finding counts and overflow).
End with an action-items rollup the user can apply by hand. **No file writes** —
confirm the working tree is untouched.

Call `advisor()` to declare done when the run is non-trivial: findings ≥ 5 OR
locales ≥ 3 OR rejections ≥ 1 OR an abort fired. Trivially-clean small runs skip the
advisor (per the "unconditional advisor on every run" anti-pattern in
`../shared/advisor-criteria.md`).

## Edge cases

- **Source == only locale** (no targets): nothing to review; report and exit.
- **`.pot` template / empty target**: every key is "missing in target" → mechanical
  findings only; skip the translator subagent for an entirely-empty locale (note it).
- **Pluralization frameworks** (ICU, gettext `nplurals`): a missing plural *category*
  for the locale is a mechanical `certain` finding; correctness of the plural *wording*
  is a naturalness finding.
- **Glossary/terminology file present**: pass it to subagents; a consistent project
  term is not "unnatural".
