# Phase 3 finding validation — `/jr-audit`

**Skill-local.** The Phase 3 step 0 (citation sanity-check) and step 0.5 (claim verification) bodies.
Read into lead context **at Phase 3 entry**, at point of use (deferred / Pattern C): presence and both
headings are grep-guarded at Phase 1 without loading, then this body is Read and re-guarded here. The
guard anchors are declared at the `SKILL.md` read site and deliberately not restated in this header,
so a body-stripped truncation that kept only the header cannot false-pass.

Steps 0.0 and 1-6 stay in `SKILL.md`. Apply the two steps below **in order**, immediately after the
step 0.0 roll-call and before dedup.

## Step 0 — Sanity-check findings (reject hallucinations)

**Freeze-anchor recheck first.** Recompute the Phase 2 freeze anchor; if it differs from the spawn
value, the reviewed tree moved mid-pass — warn (`[FREEZE BROKEN — reviewed tree moved during pass]`)
and flag this pass tree-moved (`../../shared/audit-history-schema.md` "Skip stats-exempt rejections
when the reviewed tree moved during a pass").

Then, before dedup, iterate every finding and verify its citation is real. Each reviewer was required
to submit — per finding — a `file`, a `line`, and a `codeExcerpt` (3 consecutive lines from the cited
file **starting at `line`**, verbatim with original whitespace; mandated in the reviewer prompt
assembled in Phase 2).

**Batch the checks.** Run all checks in parallel via Bash — batch all file-existence tests and
line-count queries into a single multi-call message: `test -f "$file" && wc -l < "$file"` per finding.

**Dedupe by file before reading.** Many findings cluster in the same file, so build a set of unique
`(file, min-line, max-line)` tuples first, fetch each unique file once (batching all unique reads into
a single message in parallel with the Bash checks), cache the content, then derive each finding's
excerpt range from the cached content.

**Reject a finding** (drop it from the collected set) when any of:

- (a) the `file` does not exist relative to the scope root;
- (b) `line` is not a positive integer;
- (c) `line` exceeds the file's line count;
- (d) **content-excerpt mismatch** — read `file` lines `[line, line+2]` via the Read tool and compare
  against the reviewer's `codeExcerpt` after normalizing both sides (strip trailing whitespace per
  line; collapse any run of blank lines to a single blank; treat tabs and spaces as equivalent when
  the only difference is indentation). If no line in `[line, line+2]` matches any line in the excerpt
  after normalization, reject. If the excerpt is missing or empty on a finding, treat that as
  hallucination evidence and reject.

**Output-scanning tolerance (apply BEFORE the comparison).** The harness scans a subagent's report
before it reaches the lead and may rewrite it, inserting a backslash to neutralize instruction-shaped
text — control tags (`<system-reminder>` and the other harness envelope tags), `antml:` model-layer
tags, a forged `[harness:` line prefix, and `Human:`/`Assistant:` turn markers. Some of those
categories also prepend a `[harness: subagent output matched instruction-shaped pattern(s): …]`
marker line, but **turn markers are neutralized silently, with no marker emitted at all** — so never
condition the un-escape on having seen a marker. Before comparing:

1. Ignore any such leading marker line.
2. Strip a harness-inserted backslash from instruction-shaped lines.

Never reject as `excerpt-mismatch` solely because the harness escaped one — the file side is read
fresh and unscanned, so a genuine quote still matches once the escape is removed (claim stamped +
re-verification method: `../../jr-review/protocols/finding-sanity-check.md`).

**Logging.** Log each rejection under `[REJECTED — INVALID CITATION]` with the reviewer's dimension
name, the cited `file:line`, the reason (one of: missing-file / bad-line / line-out-of-range /
excerpt-missing / excerpt-mismatch), and — for excerpt-mismatch rejections — a 2-line diff showing
what the reviewer claimed vs. what the file actually contains. On a tree-moved pass, tag
`excerpt-mismatch` rejections `statsExempt` (still dropped, but excluded from the rejection rate and
from the Save-audit-history stats). Include all rejections in the Phase 7 report.

**Escalation.** Track the rejection rate per reviewer dimension over assessable findings
(`statsExempt` rejections and their findings excluded from both numerator and denominator); if a
single reviewer exceeds 25% rejection, emit a Phase 7 `ACTION REQUIRED` note so the user can
investigate whether that reviewer hit its turn limit or was confused by the file set.

**Why the content check exists.** It catches a subtler hallucination than the line-range check alone:
real line number + fabricated problem description. If the reviewer couldn't quote the line, they
probably couldn't read the line.

## Step 0.5 — Verify claims (reject + cap hallucinated external facts)

Apply `../../shared/claim-verification.md`. For every finding that survived step 0, the **lead** (not
the reviewer) classifies it by scanning its title/description for external-authority language
(`deprecated`, `removed in`, `as of version`, `violates the rules of`, `OWASP`, `CVE-`, `WCAG`,
`best practice`, version numbers tied to a behavior claim), defaulting to **external-authority when
in doubt**. A finding is code-internal only when its correctness is provable from the cited excerpt
plus other local files (already covered by step 0).

**Grounding order, per claim:**

1. **Local grounding first** — try the project's own internal official documentation (pinned
   dependency version in `package.json`/lockfile, local `.d.ts`/type defs, config). If grounded, keep
   the finding and tag the grounding source.
2. **Otherwise fetch an authoritative source by default** (skip only under `--no-verify-claims`) per
   the doctrine's source-fetch discipline, **within this skill's granted fetch surface**:
   `Bash(gh api *)` alone, i.e. `gh api …/contents/<path>` raw markdown for a GitHub-hosted authority.
   `WebFetch`, `curl` and `glab api` are NOT granted here, so an authority with no GitHub-hosted
   source has **no fetch path in this skill**: classify it `unreachable` and take the Tier-1
   cap-and-defer route below. GitHub-hosted authorities still verify normally, so this is a narrowed
   reach, not a loss of Tier 2.

**Forge carve-out.** This `gh api` fetches an *external authority* (docs), so it stays `gh` even when
the user's repo is on GitLab — external-authority carve-out, `../../shared/forge-detection.md` §e;
only user-repo forge ops switch with the detected forge.

**Outcomes:**

- `confirmed` → keep and tag `[verified: <source> <date>]`.
- `refuted` → drop the finding, logged under `[REJECTED — CLAIM REFUTED BY SOURCE]` with the cited
  `file:line`, the claim, and the contradicting source.
- `unreachable` / `ambiguous` / `--no-verify-claims` → fall through to the cap.

**The cap (fall-through).** Where verification was skipped, unreachable, or uncorroborable, cap the
finding's confidence to `speculative` and tag it `[unverified external claim]`. Its original severity
is preserved for display (see step 3).

**Budget + escalation.** Verify each unique claim-source at most once per run (in-memory dedup; no
persisted cache in v1). Track a per-reviewer `refuted` rate; if a single dimension exceeds 25%
refuted, emit a Phase 7 `ACTION REQUIRED` note (mirrors step 0's escalation).
