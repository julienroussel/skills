# Phase 7 report template (`/jr-skill-audit`)

**Skill-local.** The findings-report layout for `/jr-skill-audit` Phase 7. Read into lead context at Phase 1 Track A (hard-fail + non-empty + smoke-parse on two body-only anchors, declared at the SKILL.md read site so they are not restated here — restating an anchor in this header would let a body-stripped truncation false-pass the smoke-parse) and rendered at Phase 7 per the "Scope-tag rendering rules" and "Naming contract" that remain in SKILL.md Phase 7.

## Report template

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /jr-skill-audit — Findings Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Generated: <YYYY-MM-DDThh:mm:ssZ>
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
  <items from Phase 3 sanity-check + reviewer-quality issues — codeExcerpt rejections, out-of-set `file` citations, missing source citations, ≥25% reviewer rejection rate>
  <UNREPORTED dimensions from Phase 3 step 0.0, named: "<dimension>-reviewer returned nothing — its dimension was NOT audited">
  (Empty section means the audit itself was clean — distinct from "no findings".)

Summary: N findings across M skills.   Total: <elapsed>
```

The `Generated:` line is `date -u +%Y-%m-%dT%H:%M:%SZ` (ISO-8601 UTC), rendered on every run — in the
console report and, under `--report`, in the archival file (`protocols/report-write.md`). It is additive
to the two smoke-parse anchors (the title line and the `Summary:` line), which are unchanged.
