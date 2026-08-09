# Phase 7 report template (`/jr-skill-audit`)

**Skill-local.** The findings-report layout for `/jr-skill-audit` Phase 7. Read into lead context **at Phase 7, at point of use** (hard-fail + non-empty + smoke-parse on two body-only anchors, declared at the SKILL.md read site and deliberately not restated here, since restating an anchor in this header would let a body-stripped truncation false-pass the smoke-parse). Rendered per the "Scope-tag rendering rules" and "Naming contract" that remain in SKILL.md Phase 7.

## Report template

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /jr-skill-audit — Findings Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generated: <YYYY-MM-DDThh:mm:ssZ>
Skills audited: <names>   Dimensions: <selected>   Findings: N (X dropped, Y kept)
Reviewer tier: <default (opus; sonnet for frontmatter) | Model override: <tier>>   Lead: <frontmatter model>
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
    — findings whose citation could not be verified render in their ORIGINAL tier with an
      [unverified — needs confirmation] tag, not here and not dropped; their reviewer-quality
      note goes to Audit integrity. See protocols/finding-validation.md.

═══ Action items (n) ═══
All N approved findings above require user action. Roll-up by tier and skill:
  Critical: <c>   High: <h>   Medium: <m>   Speculative: <s>
  By skill: <skill1>[personal] (<n1>), <skill1>[project] (<n2>), <skill2> (<n3>), ...   # tags ONLY on names that collide across scopes
  [Clarify] items still awaiting decision: <count> (referenced by index above)

Audit integrity (n):
  <items from Phase 3 sanity-check + reviewer-quality issues — codeExcerpt rejections, out-of-set `file` citations, missing source citations, ≥25% reviewer rejection rate>
  <UNREPORTED dimensions from Phase 3 step 0.0, named: "<dimension>-reviewer returned nothing — its dimension was NOT audited">
  <dimensions skipped for a missing reference (Track C "Same rule per key"), named with the failed key: "<dimension>-reviewer skipped — <ref-key> unavailable">
  (Empty section means the audit itself was clean — distinct from "no findings".)

Summary: N findings across M skills.   Total: <elapsed>
Summary (INCOMPLETE): N findings across M skills; <causes>.   Total: <elapsed>   # replaces the line above whenever unreportedCount > 0 OR refSkippedCount > 0
    # <causes> := "K dimension(s) UNREPORTED (<names>)" and/or "J dimension(s) skipped for a missing reference (<names>)", joined by "; " when both apply
Summary (INCOMPLETE): 0 reviewer dimensions ran; nothing was audited.   Total: <elapsed>   # replaces both lines above whenever dimensionCount == 0
```

**Exactly one `Summary:` form renders**, and this file is its **sole owner**: no other file specifies a
summary string. SKILL.md names the forms and points here (its Zero-dimension guard and its roll-call
consumer rule 3 both do), so the lead never has two authorities and no tiebreak; the base-line literal
SKILL.md quotes at its two read sites is a smoke-parse anchor **on this file**, not a second specification
of the output. Precedence is three-way and total: `dimensionCount == 0` wins outright, else the qualified
form, else the base line.

- **Zero-dimension form** — whenever `dimensionCount == 0` (`jr-skill-audit/SKILL.md` "Zero-dimension
  guard"). That path pins both other counters at `0` because nothing was ever spawned, so a rule keyed on
  them alone would render the clean base line over a run that audited nothing. Note the distinct
  `Summary (INCOMPLETE):` prefix: a total-failure line that reused the base line's prefix would be matched
  as an ordinary one by a log grep or a skimming reader.
- **Qualified form** — whenever `unreportedCount > 0` OR `refSkippedCount > 0`, naming **every** cause that
  applies. One form carrying both causes is what keeps "exactly one" true when they fire together.
- **Base line** — only when `unreportedCount == 0` AND `refSkippedCount == 0` AND `dimensionCount > 0`.

The summary is a clean-result path under `../../shared/subagent-reporting.md` rule 3 (enumerated as consumer
rule 3 at SKILL.md Phase 3 step 0.0), so it may not read as a whole audit while any dimension is
`UNREPORTED`. It repeats what `Audit integrity` already names because a reader who stops at the last line
would otherwise take a partial run for a complete one.

**Why `refSkippedCount` qualifies the line although the run still exits 0.** A dimension skipped for a
missing reference (SKILL.md Track C, "Same rule per key") is never spawned, so the Phase 3 roll-call, which
reconciles against the *spawn list*, leaves `unreportedCount` at `0` while `dimensionCount` stays above
zero; and one failed `skills-doc` retires three dimensions at once. Unqualified, a run that covered under
half its dimensions would end on the base line: the same reader-misled-by-the-last-line failure the
paragraph above exists to prevent. It changes the wording only. A per-key skip is documented graceful
degradation and contributes no non-zero exit (SKILL.md "Exit codes").

The `Generated:` line is `date -u +%Y-%m-%dT%H:%M:%SZ` (ISO-8601 UTC), rendered on every run — in the
console report and, under `--report`, in the archival file (`protocols/report-write.md`). It is additive
to the two smoke-parse anchors (the title line and the `Summary:` line), which are unchanged.
