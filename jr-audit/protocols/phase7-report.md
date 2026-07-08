# Phase 7 Report Contents — `/jr-audit`

**Canonical source** for the `/jr-audit` Phase 7 final-report enumeration. `jr-audit/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files) and applies it at the Phase 7 "Report contents" step. Update here to update `/jr-audit`'s report shape.

**Display**: Output the final progress timeline with all phases and total duration.

Summarize:

**Health verdict + score** (lead the report with this): a one-line overall health verdict plus the **health score** (0–100) computed per the *Health score* section at the bottom of this file, with the arithmetic shown, e.g. `62/100 — 1 high + 3 medium + 4 low remaining (band 41–70)`. Written for someone who reads only this line.
**Hidden bombs** (immediately after, only if any CRITICAL remains): every remaining 🔴 CRITICAL, one terse line each with `id` + `file:line`. Omit the section entirely if none remain.

1. **Mode**: Scope used (full/path/quick), flags set, `nofix` if applicable
2. **Stack detected**: Package manager, validation commands found, key frameworks
3. **Audited**: Files in scope, exclusions applied, directory breakdown
3.5. **Standardisation** (only if the lens is on AND off-target components exist): the technology-standardisation migration map — a table `component | current stack | on-target? | target | effort | coupling` classifying each in-scope component against the standardisation target (Track C step 7.5). **Strategic direction, NOT defects** — never severity-graded, tiered, auto-fixed, or validated. Omit when the lens is off or every component is on-target (per the non-empty rule below).
4. **Reviewers**: Spawned/skipped/timed-out with per-reviewer finding counts
5. **Findings**: Total per dimension, breakdown by severity and confidence, deduplication stats, root-cause clusters with blast radius. **Claim verification** (when external-authority claims were found): confirmed / refuted (`[REJECTED — CLAIM REFUTED BY SOURCE]`) / capped-to-`speculative` (`[unverified external claim]`) counts; the sources cited (verification is default-on).
5.5. **Strengths**: genuinely positive, evidence-backed observations derived from *this run's own signals* — dimensions that returned zero findings, a passing validation baseline, healthy test coverage, no criticals, low FP-rates. Cite the signal (e.g. `security: 0 findings across 8 auth-sensitive files`). Do NOT invent strengths or soften real findings; omit if there is nothing concrete to cite.
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
16.5. **Remediation roadmap** (the unfixed work, grouped by urgency): take the findings NOT resolved this run (in `nofix`, all of them; in fix mode, the skipped + contested + remaining-failure findings) and group them **now / next / later** by severity then fix-effort — `now` = criticals + cheap highs; `next` = remaining highs + expensive-but-important; `later` = mediums/lows. One line per item with `id` + `file:line`. This is the read-this-to-plan-the-work section; omit if nothing is left unfixed.
17. **False positive rates**: Per-dimension rates. Flag dimensions above 40%
18. **Report file**: Path to saved report

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A".

## Health score (canonical formula)

Computed by the lead at Phase 7 from the **remaining** findings — in `nofix` mode all findings; in
fix mode the findings NOT successfully fixed (skipped + contested + remaining-failures). **Exclude**
`info` findings and the standardisation map entirely (off-target is never a defect). Let `C/H/M/L`
be the remaining counts by severity:

- `C >= 1` → band **0–40**: `score = max(0, round(40 - 10*(C-1) - 3*H - 1*M - 0.25*L))`
- `C = 0, H >= 1` → band **41–70**: `score = max(41, round(70 - 5*(H-1) - 2*M - 0.5*L))`
- `C = 0, H = 0, (M+L) >= 1` → band **71–99**: `score = min(99, max(71, round(100 - 3*M - 1*L)))`
- `C = 0, H = 0, M = 0, L = 0` → **100**

Properties: a single critical can never score above 40, a single high never above 70; monotonic in
severity; deterministic given the counts, so it is comparable across apps and across re-runs. It is
a **heuristic, not a metric** — always show the arithmetic in the *Health verdict* line and in
`.claude/health.json`. The identical value is written to `.claude/health.json` (see `SKILL.md`
Phase 7 "Save health snapshot") so `/jr-rollup` can aggregate it across apps.
