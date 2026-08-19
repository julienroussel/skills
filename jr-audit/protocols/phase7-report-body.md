# Phase 7 report body — `/jr-audit`

**Skill-local.** The Phase 7 rendering and persistence body: the final-report enumeration, the
post-write redaction verification gate, the health-score formula, and the audit-history / health-snapshot /
base-anchor-temp-cleanup steps. Read into lead context **at Phase 7 entry**, at point of use
(deferred / Pattern C); presence and both guard anchors are grep-checked at Phase 1 without loading.
The guard anchors are declared at the `SKILL.md` read site and deliberately not restated here.

Split out of `phase7-report.md`, which keeps the two things this file must NOT hold: the **run-scoped
flags initialization** (a program-start contract, read before Phase 1) and the **exit-code rules**
(read on every exit path).

**Display**: Output the final progress timeline with all phases and total duration.

Summarize:

**Health verdict + score** (lead the report with this): a one-line overall health verdict plus the **health score** (0–100) computed per the *Health score* section at the bottom of this file, with the arithmetic shown, e.g. `62/100 — 1 high + 3 medium + 4 low remaining (band 41–70)`. Written for someone who reads only this line. **When `unreportedCount > 0`, emit no number here** — print `Health: NOT SCORED — incomplete run (<names> returned nothing)` instead, matching the `healthScore: null` this run writes to `health.json`. The console must not lead with `62/100` on a run whose snapshot says `null`; that is one run publishing two contradictory verdicts, and the console is the one a human acts on.
**Hidden bombs** (immediately after, only if any CRITICAL remains): every remaining 🔴 CRITICAL, one terse line each with `id` + `file:line`. Omit the section entirely if none remain.
**Action required (if any)** (immediately after Hidden bombs): the home for every `ACTION REQUIRED: …` line routed to Phase 7 during the run — the User-continue-with-secret entry (behavior 1 of `../../shared/secret-scan-protocols.md`, rendered first and prominently), the per-reviewer ≥25% hallucination-rejection (Phase 3 step 0) and ≥25% claim-refuted (Phase 3 step 0.5) escalations, and the >30%-unverified-dimension and unverified-`critical` fix notes (Phase 5.55). **Mandatory whenever non-empty** (governed by the non-empty rule below; never abbreviated). The literal `ACTION REQUIRED` label is intentional and is the by-name anchor that behavior 4's final re-scan reads (`../../shared/secret-scan-protocols.md`: "the files listed in the ACTION REQUIRED section"); it diverges from `/jr-skill-audit`, which bans the label — the divergence is documented in the repo `CLAUDE.md` "Shared conventions".

1. **Mode**: Scope used (full/path/quick), flags set, `nofix` if applicable
2. **Stack detected**: Package manager, validation commands found, key frameworks
3. **Audited**: Files in scope, exclusions applied, directory breakdown
3.5. **Standardisation** (only if the lens is on AND off-target components exist): the technology-standardisation migration map — a table `component | current stack | on-target? | target | effort | coupling` classifying each in-scope component against the standardisation target (Track C step 7.5). **Strategic direction, NOT defects** — never severity-graded, tiered, auto-fixed, or validated. Omit when the lens is off or every component is on-target (per the non-empty rule below).
4. **Reviewers**: Spawned/skipped/timed-out with per-reviewer finding counts, plus **every member of the run-level `unreported` set**, rendered per rule 1 of `../../shared/subagent-reporting.md` (which owns the source-it-from-the-set rule and why). This skill's per-kind strings: `<dimension> returned nothing — that dimension was NOT audited` / `<implementer> returned nothing — its N findings were NOT attempted`. Mandatory whenever non-empty. A non-empty set also forces a non-zero exit and bars both the "Clean audit" string and **any numeric health score at all** (item 1 prints `NOT SCORED`; `health.json` gets `healthScore: null`) — a score computed over a silently-lost dimension misreports the codebase, and a lost `security-reviewer` would silently lift the band.
5. **Findings**: Total per dimension, breakdown by severity and confidence, deduplication stats, root-cause clusters with blast radius. **Claim verification** (canonical: `../../shared/claim-verification.md`; when external-authority claims were found): confirmed / refuted (`[REJECTED — CLAIM REFUTED BY SOURCE]`) / capped-to-`speculative` (`[unverified external claim]`) counts; the sources cited (verification is default-on). Also record any `[SEVERITY CORRECTED — …]` entries from Phase 3 step 4.4. This item is **aggregates only**; the per-finding detail belongs to item 19, which is where every `id` used here resolves.
5.5. **Strengths**: genuinely positive, evidence-backed observations derived from *this run's own signals* — dimensions that returned zero findings, a passing validation baseline, healthy test coverage, no criticals, low FP-rates. Cite the signal (e.g. `security: 0 findings across 8 auth-sensitive files`). Do NOT invent strengths or soften real findings; omit if there is nothing concrete to cite. **Never derive a strength from a dimension in Phase 3 step 0.0's `UNREPORTED` set** — an unreported dimension returns zero findings by definition, and its file count comes from the Phase 1 inventory, so the example above is forgeable verbatim about a dimension that never ran. Its zero is an absence of evidence (`../../shared/subagent-reporting.md` rule 3).
6. **Hot spots**: High-churn and historically problematic files with finding density
7. **Security-sensitive files**: Detected files and findings targeting them. If `security-reviewer` is `UNREPORTED`, say so here instead of printing a finding count — "8 files detected, 0 findings" about a dimension that never ran reads as a clean security result.
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
17. **False positive rates**: Per-dimension rates (excluding `statsExempt` rejections — excerpt-mismatches on a pass whose reviewed tree moved, `../../shared/audit-history-schema.md`). Flag dimensions above 40%. If any dimension had rejections exempted, surface `[REVIEWERSTATS EXEMPTED — tree moved during pass]` with the dimension + count.
18. **Report file**: Path to saved report
19. **Findings register** (appendix; place after every narrative section — items 19 and 20 are the only appendices, in that order): **every** finding that survived Phase 3, one row each, grouped by dimension, keyed by the ids minted at Phase 3 step 4.5. Columns: `id | severity | confidence | file:line | what is wrong | fix`. Carry the tags inline (`[verified: <source> <date>]`, `[unverified external claim]`, `[severity corrected]`). Two reasons this section exists and cannot be folded into another: (a) it is what makes every `id` cited elsewhere in the report resolvable, since items 5 and 16.5 both reference ids but neither defines them; (b) it is the **only** place the reviewers' actual analysis survives, because item 5 keeps aggregates and item 16.5 keeps one-liners, so neither preserves severity, confidence, the failure mode, or the fix. A reader who cannot resolve an id to a `file:line` and a fix has a summary, not a report. Under `nofix` this **is** the deliverable: no fix was applied, so the register is the entire work product and the rest of the report is commentary on it. Also record, under a short "disclosed gaps" heading, any findings reviewers dropped for budget, any dimension not spawned, and any dimension that was spawned but is `UNREPORTED`, so truncation is never mistaken for coverage.

20. **Methodology audit trail** (appendix; place after item 19): the process failures that occurred *during this audit* and how each was resolved — so the report can be weighed rather than taken on faith. One row per failure: **what went wrong**, **what would have reached the user had it not been caught**, and **the resolution**. Group by who caught it (the `advisor()` calls vs the lead), because that attribution is the section's main signal.

    **The bar (prevents boilerplate).** Record a **failure or correction**, not a process narration. Qualifying: a finding that was about to be wrongly merged, dropped, mis-severitied, or omitted; a stale user decision about to ride into a later phase; a summary that contradicted the register; a reviewer briefed incorrectly; a reviewer that timed out or returned unusable output; the report leaking a secret (see "Post-write redaction verification", below); an advisor concern that changed the run. NOT qualifying: "8 reviewers were spawned", "dedup ran", "the advisor concurred", or any step that simply worked. Per the non-empty rule below, a run with no failures **omits item 20 entirely** — silence means clean, and that is the correct output for a clean run. Do NOT pad it to demonstrate diligence.

    **State the blind spot explicitly.** This section can only record failures that were *caught*, and the lead compiling it is the same agent that made them — so it systematically under-reports. In practice most entries originate from `advisor()` rather than lead self-detection; say so where true. An item 20 that reads as a list of things the lead heroically noticed is miscalibrated: the honest framing is that an independent reviewer caught most of them, which is the argument for that step rather than evidence the lead was thorough. Also distinguish failures caught **systematically** (a check fired) from those caught **incidentally** (noticed by luck) — an incidental catch means the process has no guard there, and that is the more useful signal of the two.

    **Do not let this section substitute for a fix.** If a failure has a mechanisable guard, the guard belongs in the skill and the entry belongs here — not the entry instead of the guard. A recurring item 20 entry is a defect report against `/jr-audit` itself; treat it as one.

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A". **Exception: item 19 is mandatory whenever at least one finding survives Phase 3.** It is never abbreviated, sampled, range-collapsed, or dropped for length; if the report feels long, cut narrative sections, never the register.

## Post-write redaction verification (mandatory)

Applied by the lead at Phase 7 immediately after the report file is written (`SKILL.md` → "Save report"), and after any later edit that touches finding text. Redaction itself is specified in `../../shared/display-protocol.md` ("Console output redaction", which covers written report bodies as well as the console); this section verifies that it actually happened.

**Applying the rule is not evidence the rule was applied.** Re-scan the **written file on disk** with the canonical pattern catalog (`../../shared/secret-patterns.md`) and halt on any hit or scan failure. An instruction the lead skips produces no error, so nothing else catches a silent leak in the one artifact most likely to be copied out of the repo. Empirically observed (2026-07-16): a run detected live credentials at Phase 1, correctly reported them as a `critical`, then **wrote the live password verbatim into the findings register** — caught only incidentally, when the user asked for the report to be copied outside the repo's `.gitignore` protection.

```bash
# $REPORT is the actual saved path (default .claude/audit-report-YYYY-MM-DD.md, or the --out target)
# Capture both: an uncaptured `grep -nEi` prints the matching line, which IS the credential.
outA=$(grep -nEi -- "<token-prefix-union from ../../shared/secret-patterns.md>" "$REPORT"); ecA=$?
outB=$(grep -nEi -- "<quoted-assignment + env-assignment patterns from ../../shared/secret-patterns.md>" "$REPORT"); ecB=$?
```

Apply the same `grep -Ei` invocation flag, per-line length cap, and **Scan-status check** as every other consumer of the catalog (`../../shared/secret-patterns.md` → "Portability and evaluation-time safeguards", "Invocation flag"). Two properties of that form are load-bearing here:

- **Capturing `ecA`/`ecB`** is what makes the next rule decidable: a grep that rejects the union exits 2 and prints nothing, so a rule branching on hits alone certifies an unscanned report as clean. grep is the sole command in each capture, so `$?` is grep's own status and no pipeline tail can mask it.
- **Capturing `outA`/`outB`** is what stops the verification from becoming a second leak. `grep -nEi` writes `<lineno>:<the entire matching line>` to stdout, so an uncaptured invocation republishes the credential into the tool-output block the operator sees, at the one site whose whole purpose is that a secret reached a persisted report. `-n` is retained because the redaction below needs the locations: read them from the `<lineno>:` prefix of `$outA`/`$outB` and never echo the captured text itself (`../../shared/display-protocol.md` "Console output redaction"; the same rule this file states below as preferring `14-char password` over the value).

**Non-emission rule (on any hit, OR on either status above 1)**: do NOT emit the report path as a completed deliverable.

- **On a hit**: redact the offending value in the file, re-run the scan until clean, and record the event under item 20 ("Methodology audit trail", above) as line numbers plus pattern type only. Item 20 is written into this same report, so quoting the matched value there relocates the leak rather than recording it. If a hit cannot be redacted without destroying the finding, halt with `[REPORT REDACTION FAILED]` and exit non-zero rather than emitting the file — the marker is registered in `../../shared/abort-markers.md` under "Markers rendered outside the abortReason mapping".
- **On a status above 1**: the scan never ran, so the file is **uncertified**, not clean. Re-run once after resolving the cause; if the status stays above 1, halt with `[REPORT REDACTION FAILED]`, cite the exit status, and exit non-zero. Record it under item 20 as well.

**Known gap this does NOT close**: the scan is regex-based, so a secret in a format absent from the catalog (internal hostname, RFC1918 address, customer name, bespoke token shape) passes it. A clean scan means "no *catalogued* pattern present", never "no sensitive content present". When the report quotes a credential file at all, prefer describing the value (`14-char password`) over reproducing it — the cited `file:line` is what the reader acts on.

**`--out` interaction**: scan the **resolved `--out` target**, not the default path. An `--out` destination outside the repo gets no `.gitignore` protection (see `SKILL.md` → "Save report"), making it the highest-risk emission and the one that most needs the scan.

## Health score (canonical formula)

**Precondition (mandatory): a run with `unreportedCount > 0` is NOT SCORED.** Do not compute this
formula at all — the counts it reads cover only the dimensions that reported, so every input is
already wrong. Emit `NOT SCORED` per item 1 and `healthScore: null` per the `health.json`
incomplete-run gate.

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


### Save audit history

Update `.claude/audit-history.json` per the canonical schema in `../../shared/audit-history-schema.md`. Create the file with the empty four-key shape if it doesn't exist; tolerate older array-only formats by upgrading them in place per the shared file's "Schema upgrade" rules.

Per-run appends with `skill: "audit"`:
- One entry to `runs[]` per (dimension, category) rejection from Phase 4 OR Phase 3 step 0 hallucination rejection, **excluding `statsExempt` rejections** (excerpt-mismatches on a pass whose reviewed tree moved — `../../shared/audit-history-schema.md` "Skip stats-exempt rejections when the reviewed tree moved during a pass"). Only rejection records are appended.
- One entry to `runSummaries[]` keyed by a fresh UUIDv4 `runId`.
- One entry per producing dimension to `reviewerStats[]` (skip dimensions with `totalFindings == 0`). `rejectedFindings` counts Phase 3 step 0 + Phase 4 rejections together; **`statsExempt` rejections (and the findings they came from) are excluded from both `rejectedFindings` and `totalFindings`** (excerpt-mismatches on a tree-moved pass carry no accuracy signal; same canonical section as the `runs[]` bullet), so a dimension whose every finding was exempt hits the `totalFindings == 0` skip. When any dimension had rejections excluded this way, note it in the report under `[REVIEWERSTATS EXEMPTED — tree moved during pass]`.
- `lastPromptedAt` is owned by Phase 4.5 only.

**Atomic-write + per-session-filename fallback** rules apply per `../../shared/secret-warnings-schema.md` "Atomic write" section (the `flock(1)` probe and post-flock fallback are shared between secret-warnings.json and audit-history.json).

**Security check (enforced)**: cache-write protocol for `.claude/audit-history.json` (command + reason: SKILL.md "Cache-write security checks").

### Save health snapshot

Compute `healthScore` (0–100) per the **Health score (canonical formula)** section above in this
file, from the **remaining** findings (exclude `info` and the standardisation map). Write a compact
latest-run snapshot to `.claude/health.json` so
`/jr-rollup` can aggregate this app's health across the estate.

**Incomplete-run gate (mandatory)**: when `unreportedCount > 0` (the run-level `unreported` set, which every roll-call in the run appends to — `../../shared/subagent-reporting.md`), write `"healthScore": null` and populate `"unreported"` with **every member of that set, by name** — lost reviewer dimensions and lost implementers alike. `|unreported|` MUST equal `unreportedCount` — a member counted but not listed renders estate-wide as `incomplete(unscored)`, so nobody can tell which dimension went unchecked without re-running the audit. **Never publish a numeric score for a run whose swarm went partly silent**: this is the roll-call's rule 3 applied to the one path that *persists* the result, where a lost `security-reviewer` would yield zero findings, a fabricated `100`, and a GREEN band on an app nobody checked. `healthScore: null` is already first-class in `bin/jr-rollup`, so no `schemaVersion` bump is needed.

**Security check (enforced)**: cache-write protocol for `.claude/health.json` (command + reason: SKILL.md "Cache-write security checks").

Write **atomically** (`.claude/health.json.tmp` + `mv`) — a latest-snapshot overwrite (NOT append-only), so no `flock` is needed, but tmp+rename avoids a torn file if interrupted. Canonical shape (`schemaVersion: 1`):

```json
{
  "schemaVersion": 1,
  "app": "<repo dir or package name>",
  "path": "<path audited, repo-relative or absolute>",
  "commit": "<git rev-parse --short HEAD, or null>",
  "date": "<ISO 8601>",
  "scope": "<scope description>",
  "mode": "audit | nofix",
  "healthScore": 0,
  "scoreReasoning": "<the arithmetic, e.g. '62 = 70 - 2*3 - 0.5*4 (band 41-70)'>",
  "counts": { "critical": 0, "high": 0, "medium": 0, "low": 0, "info": 0 },
  "standardisation": { "offTarget": 0, "components": 0 },
  "unreported": [],
  "runId": "<the same UUIDv4 as this run's audit-history runSummaries entry>"
}
```

`counts` are the **remaining** findings (post-fix in fix mode; all findings in `nofix`). Set
`standardisation` to `null` when the lens is off. `unreported` names **every member of the run-level
`unreported` set** — each reviewer dimension and each implementer that returned nothing this run
(`[]` on a complete run). Entries are **flat strings** (`bin/jr-rollup` rejects anything else as
`bad-schema`), short, comma-free, and **self-identifying by kind**: `bin/jr-rollup` renders them
comma-joined in its estate STATUS cell, recomputed from `unreported` itself and prefixed `lost:`
(`incomplete(lost:security-reviewer,p1/impl-2)`; its `--json` `reason` carries the bare join), and
item 4 above expands each into its kind-specific line, so a name a reader cannot place serves
neither. A
dimension name already carries `-reviewer`; name an implementer so it reads as one AND qualify it by
pass (e.g. `p1/impl-2`) — the set spans the whole run, so a pass-agnostic `impl-2` lost in two
different passes collapses to one member and under-reports the count.
When it is non-empty, `healthScore` MUST be `null` per the incomplete-run gate above, and `counts`
describe only the dimensions that did report.
`runId` links the snapshot to `audit-history.json` `runSummaries[]`. Overwrite the file each run
(latest snapshot only).

### Base-anchor temp cleanup (mandatory)

Delete the three `mktemp` baseline files captured at Phase 5 (`SKILL.md` → "Base commit anchor"):

```bash
if [ -n "${untrackedBaseline:-}" ]; then
  rm -f -- "$untrackedBaseline" "$untrackedBaselineAll" "$symlinkBaseline"
fi
```

Run **unconditionally regardless of `abortMode`** — these are transient state, not an audit trail, so an
aborted run must clean them up too. The `[ -n … ]` guard makes this a no-op on `nofix` runs, where Phase 5
never executed and the variables are unset. Without this step every non-`nofix` run leaks three temp files,
and `--converge` leaks them per run. Mirrors `jr-review/protocols/phase7-cleanup-report.md`.
