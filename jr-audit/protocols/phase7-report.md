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
5. **Findings**: Total per dimension, breakdown by severity and confidence, deduplication stats, root-cause clusters with blast radius. **Claim verification** (when external-authority claims were found): confirmed / refuted (`[REJECTED — CLAIM REFUTED BY SOURCE]`) / capped-to-`speculative` (`[unverified external claim]`) counts; the sources cited (verification is default-on). Also record any `[SEVERITY CORRECTED — …]` entries from Phase 3 step 4.4. This item is **aggregates only**; the per-finding detail belongs to item 19, which is where every `id` used here resolves.
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
16.5. **Remediation roadmap** (the unfixed work, grouped by urgency): take the findings NOT resolved this run (in `nofix`, all of them; in fix mode, the skipped + contested + remaining-failure findings) and group them **now / next / later** by severity then fix-effort — `now` = criticals + cheap highs; `next` = remaining highs + expensive-but-important; `later` = mediums/lows. One line per item with `id` + `file:line`, using the ids minted at Phase 3 step 4.5. **"All of them" is literal**: every unresolved finding gets its own line. Collapsing a group into an id range (`T6`-`T14`) or a prose sentence ("the type-quality tail") is a spec violation, not a summary, because it silently drops findings from the only planning surface in the report. If a bucket is long, it is long. This is the read-this-to-plan-the-work section; omit only if nothing is left unfixed.
17. **False positive rates**: Per-dimension rates. Flag dimensions above 40%
18. **Report file**: Path to saved report
19. **Findings register** (appendix; place after every narrative section — items 19 and 20 are the only appendices, in that order): **every** finding that survived Phase 3, one row each, grouped by dimension, keyed by the ids minted at Phase 3 step 4.5. Columns: `id | severity | confidence | file:line | what is wrong | fix`. Carry the tags inline (`[verified: <source> <date>]`, `[unverified external claim]`, `[severity corrected]`). Two reasons this section exists and cannot be folded into another: (a) it is what makes every `id` cited elsewhere in the report resolvable, since items 5 and 16.5 both reference ids but neither defines them; (b) it is the **only** place the reviewers' actual analysis survives, because item 5 keeps aggregates and item 16.5 keeps one-liners, so neither preserves severity, confidence, the failure mode, or the fix. A reader who cannot resolve an id to a `file:line` and a fix has a summary, not a report. Under `nofix` this **is** the deliverable: no fix was applied, so the register is the entire work product and the rest of the report is commentary on it. Also record, under a short "disclosed gaps" heading, any findings reviewers dropped for budget and any dimension not spawned, so truncation is never mistaken for coverage.

20. **Methodology audit trail** (appendix; place after item 19): the process failures that occurred *during this audit* and how each was resolved — so the report can be weighed rather than taken on faith. One row per failure: **what went wrong**, **what would have reached the user had it not been caught**, and **the resolution**. Group by who caught it (the `advisor()` calls vs the lead), because that attribution is the section's main signal.

    **The bar (prevents boilerplate).** Record a **failure or correction**, not a process narration. Qualifying: a finding that was about to be wrongly merged, dropped, mis-severitied, or omitted; a stale user decision about to ride into a later phase; a summary that contradicted the register; a reviewer briefed incorrectly; a reviewer that timed out or returned unusable output; the report leaking a secret (see "Post-write redaction verification", below); an advisor concern that changed the run. NOT qualifying: "8 reviewers were spawned", "dedup ran", "the advisor concurred", or any step that simply worked. Per the non-empty rule below, a run with no failures **omits item 20 entirely** — silence means clean, and that is the correct output for a clean run. Do NOT pad it to demonstrate diligence.

    **State the blind spot explicitly (mandatory).** This section can only record failures that were *caught*, and the lead compiling it is the same agent that made them — so it systematically under-reports. In practice most entries originate from `advisor()` rather than lead self-detection; say so where true. An item 20 that reads as a list of things the lead heroically noticed is miscalibrated: the honest framing is that an independent reviewer caught most of them, which is the argument for that step rather than evidence the lead was thorough. Also distinguish failures caught **systematically** (a check fired) from those caught **incidentally** (noticed by luck) — an incidental catch means the process has no guard there, and that is the more useful signal of the two.

    **Do not let this section substitute for a fix.** If a failure has a mechanisable guard, the guard belongs in the skill and the entry belongs here — not the entry instead of the guard. A recurring item 20 entry is a defect report against `/jr-audit` itself; treat it as one.

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A". **Exception: item 19 is mandatory whenever at least one finding survives Phase 3.** It is never abbreviated, sampled, range-collapsed, or dropped for length; if the report feels long, cut narrative sections, never the register.

## Post-write redaction verification (mandatory)

Applied by the lead at Phase 7 immediately after the report file is written (`SKILL.md` → "Save report"), and after any later edit that touches finding text. Redaction itself is specified in `../../shared/display-protocol.md` ("Console output redaction", which covers written report bodies as well as the console); this section verifies that it actually happened.

**Applying the rule is not evidence the rule was applied.** Re-scan the **written file on disk** with the canonical pattern catalog (`../../shared/secret-patterns.md`) and halt on any hit. An instruction the lead skips produces no error, so nothing else catches a silent leak in the one artifact most likely to be copied out of the repo. Empirically observed (2026-07-16, `/Users/julien.roussel/dev/etl`): a run detected live credentials at Phase 1, correctly reported them as a `critical`, then **wrote the live password verbatim into the findings register** — caught only incidentally, when the user asked for the report to be copied outside the repo's `.gitignore` protection.

```bash
# $REPORT is the actual saved path (default .claude/audit-report-YYYY-MM-DD.md, or the --out target)
grep -nEi "<token-prefix-union from ../../shared/secret-patterns.md>" "$REPORT"
grep -nEi "<quoted-assignment + env-assignment patterns from ../../shared/secret-patterns.md>" "$REPORT"
```

Apply the same `grep -Ei` invocation flag and per-line length cap as every other consumer of the catalog (`../../shared/secret-patterns.md` → "Portability and evaluation-time safeguards", "Invocation flag").

**On any hit**: do NOT emit the report path as a completed deliverable. Redact the offending value in the file, re-run the scan until clean, and record the event under item 20 ("Methodology audit trail", above). If a hit cannot be redacted without destroying the finding, halt with `[REPORT REDACTION FAILED]` and exit non-zero rather than emitting the file — the marker is registered in `../../shared/abort-markers.md` under "Markers rendered outside the abortReason mapping".

**Known gap this does NOT close**: the scan is regex-based, so a secret in a format absent from the catalog (internal hostname, RFC1918 address, customer name, bespoke token shape) passes it. A clean scan means "no *catalogued* pattern present", never "no sensitive content present". When the report quotes a credential file at all, prefer describing the value (`14-char password`) over reproducing it — the cited `file:line` is what the reader acts on.

**`--out` interaction**: scan the **resolved `--out` target**, not the default path. An `--out` destination outside the repo gets no `.gitignore` protection (see `SKILL.md` → "Save report"), making it the highest-risk emission and the one that most needs the scan.

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
