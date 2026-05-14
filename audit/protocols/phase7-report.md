# Phase 7 Report Contents — `/audit`

**Canonical source** for the `/audit` Phase 7 final-report enumeration. `audit/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files) and applies it at the Phase 7 "Report contents" step. Update here to update `/audit`'s report shape.

**Display**: Output the final progress timeline with all phases and total duration.

Summarize:

1. **Mode**: Scope used (full/path/quick), flags set, `nofix` if applicable
2. **Stack detected**: Package manager, validation commands found, key frameworks
3. **Audited**: Files in scope, exclusions applied, directory breakdown
4. **Reviewers**: Spawned/skipped/timed-out with per-reviewer finding counts
5. **Findings**: Total per dimension, breakdown by severity and confidence, deduplication stats, root-cause clusters with blast radius
6. **Hot spots**: High-churn and historically problematic files with finding density
7. **Security-sensitive files**: Detected files and findings targeting them
8. **Cross-file consistency**: Issues found across file boundaries
9. **User decisions**: Approved/rejected per tier, rejection reasons summary
10. **Auto-learned**: New suppressions added (or "none")
11. **Fixed**: Improvements applied grouped by category (or "N/A — findings-only mode" if `nofix`)
12. **Validation**: Pass/fail per command, baseline vs post-fix, iterations needed (or "N/A" if `nofix`)
13. **Diff summary**: `git diff --stat` (or "N/A" if `nofix`)
14. **Skipped**: Findings intentionally left unchanged with reasoning
15. **Remaining failures** (if any): Unresolved regressions after max retries
16. **Contested**: Findings that implementers flagged as contested, with their reasoning
17. **False positive rates**: Per-dimension rates. Flag dimensions above 40%
18. **Report file**: Path to saved report

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A".
