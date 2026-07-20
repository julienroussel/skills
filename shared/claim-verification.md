# Claim Verification (Anti-Hallucination Doctrine)

**Canonical source** for how a skill establishes that a finding/claim is *true* before it surfaces or acts
on it. Read at Phase 1 (Track A or single-track) and passed to reviewers/translators as context (or applied
lead-side). Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each
skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section;
per-skill relationships to the doctrine are in the "Applicability" table below.

## Purpose — the gap this closes

The `codeExcerpt` + Phase 3 sanity-check (`jr-review/protocols/finding-sanity-check.md`, and `/jr-audit`'s inline
Phase 3 step 0) own **citation integrity**: they re-read the cited `file:line` and reject any finding whose
3-line excerpt doesn't match the real file. That proves *the cited line exists verbatim* — it catches fabricated lines and fabricated
descriptions of lines the reviewer couldn't read.

It does **not** prove *the claim about that line is true*. A reviewer can quote a real line perfectly and
still assert a false external fact about it: "this API is deprecated," "removed in Node 18," "this violates
the rules of hooks," "this is CVE-2023-…," "WCAG requires this." Those rest on the reviewer model's training
knowledge — exactly where hallucination lives. (Proof-case: a single WebFetch once reported a non-existent
`ultra` effort value as real; the actual value is `xhigh`.) **This file owns claim correctness for facts not
provable from local code.**

## Claim taxonomy

Every *finding* is one of two kinds (a skill's own assertions about its runtime are a third scope, not a finding — governed under **Harness claims** below):

- **Code-internal claim** — correctness is fully provable from the cited excerpt plus other local files
  (e.g., "this value is null here," "this catch block is empty," "this prop is never passed," "this import is
  unused"). Already verified by `codeExcerpt` + the Phase 3 sanity-check. **No external check needed.**
- **External-authority claim** — correctness depends on a fact NOT present in the local code: API/library
  deprecation, version-specific behavior, framework rules ("rules of hooks"), language-spec semantics,
  security advisories/CVEs, standards compliance (WCAG/OWASP), or "best practice per `<authority>`." **This is
  the hallucination-prone class** and the subject of the rest of this file.

**Signal lexicon** (non-exhaustive) used to detect external-authority claims in a finding's title/rationale:
`deprecated`, `removed in`, `as of version`, `no longer`, `per the docs`, `per the spec`, `violates the rules
of`, `OWASP`, `CVE-`, `WCAG`, `best practice`, `the standard requires`, `browsers no longer`, and any version
number tied to a behavior claim.

## Harness claims (the skill's own assertions, not findings)

A skill also asserts facts about the **runtime
it runs on** — which tools a role has, whether a spawn returns its result, what an env var exposes, what a
CLI's JSON fields are called. That is not a third *finding* kind (the author is the skill, not a reviewer), but
its correctness profile is an external-authority claim's — volatile, training-drawn, not provable from the repo
— so the same rule applies one level up: tie it to a checked fact (never memory or a commit message),
**date-stamp it** with a `<!-- harness-claim-verified: YYYY-MM-DD -->` marker (`/jr-doctor` Group I warns past
90 days) and re-verify on a Claude Code / plugin upgrade, and **prefer a live probe to prose** where one is
possible. `shared/subagent-reporting.md` ("Verified behaviour") and `shared/forge-detection.md` (§c) are the
model tables; `/jr-doctor` Group J is the live probe; methodology is in `docs/skill-anatomy.md` "Re-verifying a
harness claim".

## Independent detection (lead, not reviewer)

The **lead agent** — not the reviewer — classifies each surviving finding at Phase 3 by scanning its
title/rationale against the signal lexicon, and **defaults to external-when-in-doubt**. A finding is treated
as code-internal ONLY if its correctness is demonstrably provable from local files; anything carrying
external-authority language is external. Any reviewer-supplied `claimType` hint is a **hint, never the gate**
— the model that hallucinates the claim is the same one that would self-report it as verified. This mirrors
why `codeExcerpt` works: the guarantee comes from the lead re-reading independently, not from the reviewer's
own assurance.

**A dismissal is a claim, too.** Rejecting a finding — or waving a risk off as already-handled — asserts a
property exactly as a finding does, and the same rule governs it: test the property actually relied on, not a
proxy for it. "This value is safe because its sink is `@tsv`-escaped" is sound only if `@tsv` neutralises the
specific threat; `@tsv` escapes `\t \n \r \\` and nothing else, so it does not cover C1/NEL/LS/PS, and a
dismissal that checked only that the value *rendered* never tested what it claimed. Before dropping a finding
on a because-clause, verify the because-clause to the same standard you would apply to the finding — an
unverified dismissal auto-applied is the same unchecked autonomous decision this file bars, pointed the other
way.

## Grounding hierarchy (cheapest-authoritative first)

1. **Cited code** → resolves code-internal claims. Already enforced.
2. **Internal official documentation** — local and authoritative for THIS project, and cheap to check: the
   pinned dependency version in `package.json`/lockfile, local `.d.ts`/type definitions, project config,
   `CLAUDE.md`, ADRs. If an external-authority claim is grounded here (e.g., the "deprecated" API matches the
   project's actually-pinned version), keep the finding at its earned confidence and tag the grounding source.
3. **Authoritative external source** — fetched **by default** when local grounding can't settle an
   external-authority claim (Tier 2 below). Skipped only when `--no-verify-claims` is set or the source is
   unreachable/uncorroborable, in which case the Tier 1 cap-and-defer fallback applies.

## Tier 1 — local grounding + the cap-and-defer fallback

Classification and local grounding (the hierarchy above) always run first. When an external-authority claim
is **not** groundable locally and Tier 2 verification did **not** confirm it (the source was
unreachable/uncorroborable, or `--no-verify-claims` was set): cap its confidence to `speculative`, tag it
`[unverified external claim]`, and route it to the user. This plugs into the existing tiered approval —
`speculative` is already Tier 3 ("Requires human judgment", `shared/reviewer-boundaries.md`) — so there is no
new approval UI: the cap is a *classification + cap* layered on existing machinery. **This is the fallback for
when a fact cannot be checked — not the default. The default is to check it (Tier 2).**

### False-negative containment (the inverse risk)

Capping unconfirmed claims trades a false-positive (hallucination) for a possible false-negative: a *real*
"deprecated in vN" gets defaulted-to-external, can't be grounded locally, and verification is unavailable
(offline or `--no-verify-claims`) → capped to `speculative`. That trade is intended, but it must not silently
bury a real high-severity issue. Two guards:

- A `speculative` cap **surfaces** the finding (Tier 3); it is **never silently dropped**.
- The existing "drop `low` unless trivially fixable" rule **must not** apply to a finding whose *only* reason
  for its lowered status is an unverified-external cap. Preserve the finding's original severity for display,
  marked `[unverified — needs confirmation]`, so a genuine `high`-severity deprecation stays visible instead
  of being demoted into oblivion.

## Tier 2 behavior (active verification — ON BY DEFAULT)

By default, for each external-authority claim not settled by local grounding, fetch an authoritative source
to confirm or refute it. This is the **default in every mode** (interactive and headless) — on uncertainty,
check the documentation rather than guess or defer. `--no-verify-claims` opts out (offline / speed); when the
fetch is genuinely impossible, the Tier 1 fallback applies.

- **Source-fetch discipline (hard constraint).** NEVER trust a single WebFetch summarization for a
  load-bearing or verbatim claim — a lone WebFetch can fabricate text. Use, in priority order: (a) `gh api
  repos/<org>/<repo>/contents/<path>` raw markdown for GitHub-hosted docs/changelogs; (b) the document's raw
  `.md`/`.txt` variant; (c) if only an HTML page exists, fetch it AND cross-check the load-bearing token
  against a second independent fetch or the raw source. Always cite the fetched source + date on the outcome.
  **Forge-independence:** the CLI for an authority fetch follows the *authority's* host, not the user's repo
  forge — GitHub-hosted authorities (e.g. `anthropics/claude-code`) stay on `gh api` even when the user's repo
  is on GitLab; reach for `glab api projects/:fullpath/repository/files/<path>/raw` only when the authority is
  itself gitlab-hosted (`forge-detection.md` §(e)).
- **Outcomes:**
  - `confirmed` → keep the finding, tag `[verified: <source> <date>]`.
  - `refuted` → REJECT the finding, logged under `[REJECTED — CLAIM REFUTED BY SOURCE]` with the cited
    `file:line`, the claim, and the contradicting source — this is the hallucination caught at its root.
  - `unreachable` / `ambiguous` → fall back to Tier 1 (cap to `speculative` + route/defer).
- **Cache (v1 = in-memory per-run).** Verify each unique claim-source once per run and reuse the result for
  the remainder of that run; no persisted file in v1. (Upgrade path if cross-run reuse proves worthwhile:
  a persisted `.claude/claim-verification-cache.json` modeled on `jr-skill-audit/cache/refs.json` — 7-day TTL,
  stale-fallback, atomic write, `.gitignore`-checked. Not in v1.)
- **On by default** in every mode; `--no-verify-claims` opts out for offline/speed (the Tier 1 cap-and-defer
  fallback then applies). Local grounding resolves many claims with no network fetch, so the fetch cost is
  bounded to the residual. For `/jr-skill-audit` verification is always-on with no opt-out — its live refs-cache +
  Phase 3 source-citation validation are the reference implementation of Tier 2.

## Headless branch (mirrors the secret-scan halt)

With no user to prompt (headless / `--auto-approve` / CI), verification still runs by default: a **confirmed**
external-authority claim is a checked fact and may be auto-applied like any other approved finding; a
**refuted** claim is rejected. Only a claim that **cannot be verified** (source unreachable/uncorroborable, or
`--no-verify-claims` set) is capped to `speculative` and **deferred + reported, never auto-applied** — a run
that had to defer ≥ 1 such finding surfaces it as an escalation in the consumer's Phase 7 report for the
user (the escalation-section label is owned per-consumer, not fixed here) — an
informational marker that is not itself among the Phase 7 exit-code conditions (`/jr-review`'s
`phase7-cleanup-report.md` → "Phase 7 exit-code rules"), so the deferral alone does not force a non-zero exit. The skill never
silently auto-applies what it could not verify, but it no longer defers what it *can* verify.

## No autonomous critical decision without a checked fact

A consequential autonomous action — applying a fix, writing a suppression rule, auto-approving in a
convergence pass, merging a PR — may proceed **without** a fresh user prompt ONLY when its basis is a checked
fact: a code-internal claim verified by `codeExcerpt`, a Tier-2-`confirmed` external claim, or an explicit
prior user approval covering it. When the basis is an unverified external claim or genuine ambiguity, prompt
the user (interactive) or defer + report (headless). This is the general rule the secret-continue gate, the
finding-approval tiers, and the advisor pre-dispatch/pre-merge gates all already instantiate.

## Applicability

| Skill | Relationship to this doctrine |
|-------|-------------------------------|
| `/jr-audit`, `/jr-review` | Full consumers — Track-A read; Phase 3 lead classification + verify (default-on) with cap-and-defer fallback; Phase 4 approval routing; `--no-verify-claims` opts out of the fetch. |
| `/jr-skill-audit` | Reference Tier-2 implementation — its refs-cache + Phase 3 source-citation validation already enforce this doctrine; Track-A read for the shared smoke-parse. |
| `/jr-ship` | No findings, but its CI-fix diagnosis can rest on external facts — those must be grounded/confirmed via an authoritative source (the source-fetch discipline above) before the existing user confirm-gate, not asserted from memory. |
| `/jr-tackle` | Ad-hoc work that makes external claims — its rigor protocol applies the source-fetch discipline above. |
| `/jr-i18n` | Full consumer — Track-A read; per-locale findings classified at Phase 3 (mechanical → `certain`, locale-rule → fetch-verified via `gh api`, naturalness → human-gated `speculative`); the no-auto-write property + Phase 4 gate satisfy the no-consequential-action-without-a-checked-fact rule. |
| `/jr-mermaid` | Lead-applied — "the generated diagram is valid Mermaid" is the checkable claim, verified at Phase 4 (mmdc render or structural self-check); no reviewers, no fetch. |
| `/jr-doctor` | Read-only, factual-local-only checks (no external-authority claims); in-scope-but-exempt. Group D smoke-parses this file like every other `shared/*.md`. |
| `/codebase-memory`, `/find-skills` | Outputs are tool-returned data (graph edges / registry metadata), not model-synthesized claims, so the doctrine does not govern their *outputs* — but any interpretive recommendation they layer on top does. |

## Last verified

`2026-07-19` — Added the **Harness claims** scope (a skill's own assertions about its runtime: date-stamp +
re-verify-on-trigger + prefer a live probe; `/jr-doctor` Group J / Group I enforce). Source-fetch discipline
mirrors the WebFetch-fabrication constraint (raw `.md` / `gh api` / corroboration over a lone WebFetch summary).
Re-verify the lexicon and grounding hierarchy against current reviewer behavior when this file is more than 90
days old.
