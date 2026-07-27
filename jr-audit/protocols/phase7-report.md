# Phase 7 Report Contents — `/jr-audit`

**Canonical source** for the `/jr-audit` Phase 7 final-report enumeration. `jr-audit/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files) and applies it at the Phase 7 "Report contents" step. Update here to update `/jr-audit`'s report shape.

## Run-scoped flags initialization (mandatory)

At program start, before Phase 1:

1. Parse arguments (per the "Arguments" section in `SKILL.md`).
2. Initialize all three run-scoped boolean flags to `false` unconditionally: `abortMode=false`, `convergenceFailed=false`, `userContinueWithSecret=false`. Additionally, initialize the run-scoped string `abortReason=""` (empty string), the run-scoped counter `unreportedCount=0`, and the run-scoped set `unreported=[]` (empty).
3. Run flag-conflict resolution (per "Flag conflicts" in `SKILL.md`).
4. Begin Phase 1.

This is the **single** program-start initialization site — the mirror of `/jr-review`'s `protocols/phase7-cleanup-report.md` "Run-scoped flags initialization", and the reason the two skills' exit-code rules below "must not drift". It is unconditional: the exit-code rules read these values on **every** exit path, but most paths never enter the `--converge` loop or reach an abort/user-continue site — a clean non-converge run reaches Phase 7 having touched none of them (no flag set, and its Phase 3 roll-call appended nothing to `unreported`). Initializing here guarantees the exit-code gate reads a defined `false`/`""`/`0`/`[]` rather than relying on unset-variable semantics.

`/jr-audit` has no `freshEyesMandatory` flag (no fresh-eyes pass — see `../convergence-protocol.md`); it is `/jr-review`-only. `/jr-audit`'s flag-conflict resolution (step 3) currently sets none of these run-scoped flags, so ordering step 2 before step 3 is defensive rather than load-bearing today; keep it so a future conflict rule that latches a flag cannot be clobbered by a later default (the trap `/jr-review` documents at its init site).

The `--converge` loop adds only its **own** state (`iteration`, `convergenceStartTime`, `tmpDir`, `allModifiedFiles`, `iterationLog`, `passUnreported`) on top of these — it does NOT re-initialize the flags above (`../convergence-protocol.md` "Initialization").

Flag semantics:

- `abortMode=false` — set to `true` by any abort path; gates the abort-mode marker render (SKILL.md Phase 7) and the exit-code rule below. `abortReason` is set alongside it.
- `abortReason=""` — set alongside `abortMode=true` at each abort site to one of the values in `../../shared/abort-markers.md` (single source of truth for the enum). Reset to `""` only here; typically one abort site fires per run.
- `convergenceFailed=false` — set to `true` by any `--converge` termination-without-convergence path (`../convergence-protocol.md`).
- `userContinueWithSecret=false` — latched to `true` by the User-continue path protocol's behavior 5 (`../../shared/secret-scan-protocols.md`), at the Phase 5.6 and Phase 6 regression-fix user-Continue sites. CANNOT be unset for the remainder of the run.
- `unreportedCount=0` / `unreported=[]` (empty): the run-level, monotonic reviewer-roll-call state (`../../shared/subagent-reporting.md` "Lead-side: reviewer roll-call"). Phase 3 step 0.0 and every later roll-call only **append** `UNREPORTED` members, nothing resets it, and `unreportedCount` is `|unreported|`. Initialized here so a clean run (where the roll-call appends nothing) reaches the Phase 3 `unreportedCount == 0` clean-audit gate and the Phase 7 `> 0` exit / health-score gates with a defined `0` / `[]` rather than an unset value. This is **not** the `--converge` loop's per-pass `passUnreported` (loop-owned, reset each iteration per the above); the run-level set is never reset.

## Exit-code rules

Phase 7 exits with a **non-zero** status when any of the following occurred during the run:

- `abortMode=true` (any `abortReason`).
- `convergenceFailed=true` (any convergence termination path, per `../convergence-protocol.md`).
- **`unreportedCount > 0`** — any spawned subagent returned nothing (`../../shared/subagent-reporting.md` rule 2). The run did not cover what it claims, and under headless the exit code is the only channel a machine reads.
- `userContinueWithSecret=true` (the latched User-continue path, `../../shared/secret-scan-protocols.md`).
- Any exit-forcing **marker** was rendered — the marker set is owned by `../../shared/abort-markers.md` ("Exit-code contribution").

This list is the single source of truth for `/jr-audit`'s exit code; `abort-markers.md` owns only the marker subset. Mirrors `/jr-review`'s `protocols/phase7-cleanup-report.md` ("Phase 7 exit-code rules"), which carries the same non-marker conditions — the two skills must not drift.

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
5. **Findings**: Total per dimension, breakdown by severity and confidence, deduplication stats, root-cause clusters with blast radius. **Claim verification** (when external-authority claims were found): confirmed / refuted (`[REJECTED — CLAIM REFUTED BY SOURCE]`) / capped-to-`speculative` (`[unverified external claim]`) counts; the sources cited (verification is default-on). Also record any `[SEVERITY CORRECTED — …]` entries from Phase 3 step 4.4. This item is **aggregates only**; the per-finding detail belongs to item 19, which is where every `id` used here resolves.
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

**Applying the rule is not evidence the rule was applied.** Re-scan the **written file on disk** with the canonical pattern catalog (`../../shared/secret-patterns.md`) and halt on any hit. An instruction the lead skips produces no error, so nothing else catches a silent leak in the one artifact most likely to be copied out of the repo. Empirically observed (2026-07-16): a run detected live credentials at Phase 1, correctly reported them as a `critical`, then **wrote the live password verbatim into the findings register** — caught only incidentally, when the user asked for the report to be copied outside the repo's `.gitignore` protection.

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

Compute `healthScore` (0–100) per the **Health score (canonical formula)** in
`${CLAUDE_SKILL_DIR}/protocols/phase7-report.md` from the **remaining** findings (exclude `info` and
the standardisation map). Write a compact latest-run snapshot to `.claude/health.json` so
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
`protocols/phase7-report.md` item 4 expands each into its kind-specific line, so a name a reader
cannot place serves neither. A
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
