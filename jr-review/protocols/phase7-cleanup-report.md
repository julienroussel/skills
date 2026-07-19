# Phase 7 — Cleanup and report

**Canonical procedure** for `/jr-review` Phase 7 (cleanup + report rendering). Referenced by `jr-review/SKILL.md` Phase 7. Loaded at Phase 1 Track A under the same hard-fail + smoke-parse discipline as the other protocol files.

## Phase 7 preamble

Phase 7 is the terminal cleanup phase and runs on every exit path. Some paths mark the run as aborted via the `abortMode` flag.

## Run-scoped flags initialization (mandatory)

At program start, in this exact order:

1. Parse arguments (per "Arguments" section in `SKILL.md`).
2. Initialize all four run-scoped boolean flags to `false` unconditionally: `abortMode=false`, `convergenceFailed=false`, `userContinueWithSecret=false`, `freshEyesMandatory=false`. Additionally, initialize the run-scoped string `abortReason=""` (empty string), the run-scoped counter `unreportedCount=0`, and the run-scoped set `unreported=[]` (empty).
3. Run flag-conflict resolution (which may set `freshEyesMandatory=true` if `--auto-approve` and `--converge` are both active per the rules in "Flag conflicts").
4. Begin Phase 1.

No subsequent re-init is permitted — flag-conflict resolution AFTER step 2 ensures defaults are not clobbered. The boundary is pinned precisely at this ordering because flag-conflict resolution may legitimately set `freshEyesMandatory=true` before Phase 1 runs; initializing flags AFTER conflict resolution would overwrite that legitimate setting. Pinned ordering is stricter than the prior "before Phase 1" phrasing, which was too coarse.

Flag semantics:

- `abortMode=false` — set to `true` by any abort path (see the "Abort-mode execution" enumeration below).
- `convergenceFailed=false` — set to `true` when the convergence loop hits `maxIterations` without converging.
- `userContinueWithSecret=false` — latched to `true` by the User-continue path protocol's behavior 5 (see `../../shared/secret-scan-protocols.md`). Trigger sites: Phase 1 user-Continue at the interactive secret pre-scan prompt, Phase 5.6 user-Continue, Phase 6 regression-fix user-Continue, Convergence Phase 5.6 user-Continue, and the Fresh-eyes fix cycle user-Continue. CANNOT be unset for the remainder of the run.
- `freshEyesMandatory=false` — set to `true` when `--auto-approve` is combined with `--converge` (either explicitly or auto-added by headless logic).
- `abortReason=""` — set alongside `abortMode=true` at any abort site. Used by step 16 of the report to render the corresponding marker. Allowed values are defined in `../../shared/abort-markers.md` (single source of truth for the enum). Reset to `""` only at program start; subsequent abort sites overwrite as needed (typically only one fires per run).
- `unreportedCount=0` / `unreported=[]` (empty): the run-level, monotonic reviewer-roll-call state (`../../shared/subagent-reporting.md` "Lead-side: reviewer roll-call"). Phase 3 step 0.0 and every later roll-call only **append** `UNREPORTED` members, nothing resets it, and `unreportedCount` is `|unreported|`. Initialized here so a clean run (where the roll-call appends nothing) reaches the Phase 3 `unreportedCount == 0` clean-review gate and the Phase 7 / 8 `> 0` exit and report gates with a defined `0` / `[]` rather than an unset value. This is **not** the `--converge` loop's per-pass `passUnreported` (loop-owned, reset each iteration per the above); the run-level set is never reset.

These unconditional defaults are critical because multiple paths reach Phase 7 without Phase 6 or the convergence loop ever running: (i) Phase 3 zero-findings skip, (ii) `nofix` flag, (iii) Phase 4.5 → Phase 7 in nofix flows, (iv) `--converge` not set, (v) Phase 1 halts before any user-continue or abort decision. On those paths, the flags must already be `false` (and `unreportedCount` already `0`, `unreported` already empty) at program start so step 3's gate and the exit-code rules can decide correctly without checking for unset-variable semantics. The `abortMode` flag gates step 3 (and step 5's audit-history write, called out separately at that step); steps 1, 2, 4, and 6 run in all modes.

## Phase 7 exit-code rules

Phase 7 exits with a non-zero status when any of the following occurred during the run: `abortMode=true`, `convergenceFailed=true`, **`unreportedCount > 0`** (any spawned subagent returned nothing — the run did not cover what it claims; `../../shared/subagent-reporting.md`. Load-bearing under headless/CI, where the exit code is the only channel a machine reads: without it, a review whose entire swarm went silent exits 0 and CI records a green review over an unreviewed diff), any secret halt, any schema-validation backup was triggered, any `[ABORT — HEAD MOVED]` marker was rendered, `userContinueWithSecret=true` (latched by any of Phase 1 user-Continue at the interactive secret pre-scan prompt, Phase 5.6 user-Continue, Phase 6 regression-fix user-Continue, Convergence Phase 5.6 user-Continue, or Fresh-eyes fix cycle user-Continue), or any `[AUDIT TRAIL REJECTED — PATH VALIDATION]` marker was rendered.

## Per-session filename banner (flock unavailable)

If `FLOCK_AVAILABLE=false`, append to the Phase 7 report a banner: `To avoid per-session filename mode and use a single shared secret-warnings.json file, install GNU coreutils: brew install coreutils (then re-run /jr-review).` This banner complements the existing per-session-fallback skip log (see Phase 5.6 `flock(1)` availability probe) by giving the user a concrete remediation. Emit the banner unconditionally when `FLOCK_AVAILABLE=false`, regardless of whether any secret warnings were written in this run.

## Steps

1. **Subagent teardown (none needed)**: Reviewer/implementer subagents are spawned **without `name:`** (`../../shared/subagent-reporting.md` "Spawn rule"), so they are tasks that terminate on return — not teammates. There is nothing to release and no `shutdown_request` to originate (`TeamCreate`/`TeamDelete` were removed in 2.1.178). This step is retained as a documented no-op **only** to preserve the `steps 1, 2, 4, 6 / skip 3` numbering contract that every abort-mode site references; do not renumber or delete it. Proceed to the next step.
2. If fixes were applied (not `nofix` mode), run `git diff --stat` to show a summary of all files the review swarm touched.
3. If any `.claude/secret-warnings*.json` files exist, prune resolved entries per `secret-warnings-lifecycle.md` (the canonical procedure for the five sub-steps a–e: schema validation + corrupt-file backup, file-existence check + missingRunCount lifecycle + acknowledge override prompt, whole-file pattern rescan + `"other"` full-scan fallback + pattern-type non-absorption rules, atomic write-back, empty-array cleanup with hook-still-installed warning).

   **Skip this step entirely when `abortMode` is true** — in abort mode the audit trail must persist unmodified. A partial or reverted run is not evidence that secrets have been resolved.

   **Abort-mode execution**: Triggered when `abortMode` is true. Allowed `abortReason` values are listed in `../../shared/abort-markers.md`. When `abortMode=true`, skip step 3 entirely — the audit trail must persist; a reverted or partially-executed run has not resolved any secrets and pruning would be unsafe. The abort-mode skip applies ONLY to step 3 (and step 5's audit-history write, called out separately at that step); steps 1, 2, 4, and 6 run in all modes.

4. **Report redaction**: Apply the canonical line-by-line console-output redaction rule from `../../shared/display-protocol.md` ("Console output redaction" section) using the canonical pattern catalog in `../../shared/secret-patterns.md`. Both files are already loaded at Phase 1 Track A. File paths (including the `.claude/secret-warnings.json.corrupt-<ts>` backup-path strings) are NOT redacted — only matched secret values are redacted. This is critical in CI/headless mode where console output is persisted in build logs that may be publicly accessible.

5. **Save audit history (`.claude/audit-history.json`)**: Update the cross-skill registry per the schema in `../../shared/audit-history-schema.md`. Create the file as `{"runs": [], "runSummaries": [], "reviewerStats": [], "lastPromptedAt": {}}` if it doesn't exist; tolerate older array-only formats (legacy `/jr-audit` schema) by upgrading them in place to the new schema before appending — preserve any old entries under `runSummaries[]`.

   Write in this order (atomic, same `flock` + `.tmp` + `mv` pattern as `secret-warnings.json`):
   - Append one `runSummaries[]` entry: `{runId, skill: "review", date, scope, flags, filesReviewed, reviewersSpawned, findingCounts, approvedCount, rejectedCount, validationDelta, phaseTimings, runAt}`. `runId` is a fresh UUIDv4 generated at Phase 7. `runAt` is ISO 8601.
   - Append one `runs[]` entry per (dimension, category) rejection observed in Phase 4 OR Phase 3 step 0 hallucination-rejection, **excluding `statsExempt` rejections** (excerpt-mismatches on a pass whose reviewed tree moved — `../../shared/audit-history-schema.md` "Skip stats-exempt rejections when the reviewed tree moved during a pass"): `{runId, skill: "review", dimension, category, rejected: true, totalFindings, runAt}`.
   - Append one `reviewerStats[]` entry per reviewer dimension that produced findings: `{runId, skill: "review", dimension, totalFindings, rejectedFindings, rejectionRate, runAt}`. `rejectedFindings` includes BOTH Phase 3 step 0 hallucination-rejections (citation invalid) AND Phase 4 user rejections — they signal accuracy degradation either way — but **`statsExempt` rejections (and the findings they came from) are excluded from both `rejectedFindings` and `totalFindings`** (excerpt-mismatches on a tree-moved pass carry no accuracy signal; same canonical section as the `runs[]` bullet). When any dimension had rejections excluded this way, note it in the report under `[REVIEWERSTATS EXEMPTED — tree moved during pass]` (dimension + count). Skip dimensions with `totalFindings == 0` (so a dimension whose every finding was exempt writes no entry).
   - The `lastPromptedAt` map is only updated by Phase 4.5 cross-run promotion offers (already covered there).

   **Skip this write entirely when `abortMode=true`** — same rationale as step 3: a reverted run has no honest accuracy signal. Note in the Phase 7 report under `[AUDIT-HISTORY SKIPPED — abort mode]`.

   **Security check (enforced)**: Apply the `.gitignore`-enforcement protocol (see `../../shared/gitignore-enforcement.md`, read at Phase 1 Track A) for path `.claude/audit-history.json`. Core command: `git ls-files --error-unmatch .claude/audit-history.json 2>/dev/null` — warn if tracked; if absent from `.gitignore`, append it and inform the user. Per-site reason if tracked: "audit-history holds per-run rejection counts and timestamps used to drive global memory promotion — committing it would conflate one user's preference signals with other contributors' and could silently silence findings for all users."

6. **Cleanup base-commit-anchor temp files**:

   ```bash
   if [ -n "${untrackedBaseline:-}" ]; then
     rm -f -- "$untrackedBaseline" "$untrackedBaselineAll" "$symlinkBaseline"
   fi
   ```

   These are the three mktemp paths returned by `${CLAUDE_SKILL_DIR}/scripts/establish-base-anchor.sh` on success (see `base-anchor.md` "Anchor capture"). Run **unconditionally regardless of `abortMode`** — they are transient state, not an audit trail. The `[ -n "${untrackedBaseline:-}" ]` guard makes this a safe no-op when Phase 5 never ran (variable unset); checking just `untrackedBaseline` is sufficient because the three are set together at anchor-capture time. All in-flight revert sequences have already completed by Phase 7, so the temps are no longer needed by any downstream step.

## Display

Output the final progress timeline with all phases and total duration. Only include phases that were actually executed:

```
Full:      Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → Phase 3 ✓ (2s) → Phase 4 ✓ (5s) → Phase 5 ✓ (19s) → Phase 6 ✓ (8s) → Phase 7 ✓ (2s) → Phase 8 ✓ (5s)  Total: 62s
Quick:     Phase 1 ✓ (2s) → Phase 2 ✓ (12s) → Phase 3 ✓ (1s) → Phase 4 ✓ (3s) → Phase 7 ✓ (1s)  Total: 19s
Clean:     Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → Phase 3 ✓ (1s) → Phase 7 ✓ (1s)  Total: 23s
Converge:  Phase 1 ✓ (3s) → Pass 1 [P2-6] ✓ (45s) → Pass 2 [P2-6] ✓ (22s) → Pass 3 [P2-3] ✓ (8s) → Phase 7 ✓ (2s)  Total: 80s
```

**Compact report** (for `quick` or `nofix` mode): Output only Mode, Reviewed (files + reviewers), Findings (summary table), User decisions, **Action required whenever non-empty**, **and Coverage-gaps item 7(b) whenever `unreportedCount > 0`**. Skip Cross-file impacts, Auto-learned, Fixed, Contested, Validation, Diff summary, Skipped, and Remaining failures sections, and skip Coverage-gaps item 7(a) (file-level gaps). Item 7(b) and the Action-required lead-in are the sections the compact form may never drop when non-empty: `quick` mode narrows *how much* is reviewed, never whether the report admits a dimension went missing or a secret was left in the working tree.

**Full report** (default): Summarize:

**Action required (if any)** (lead the summary with this): the home for every `ACTION REQUIRED: …` line routed to Phase 7 during the run — the User-continue-with-secret entry (behavior 1 of `../../shared/secret-scan-protocols.md`, rendered first and prominently), the per-reviewer ≥25% hallucination-rejection (Phase 3 step 0) and ≥25% claim-refuted (Phase 3 step 0.5) escalations, the >30%-unverified-dimension and unverified-`critical` fix notes (Phase 5.55), and the secret-warnings / pre-commit-hook maintenance entries. **Mandatory whenever non-empty, in the compact report as well as the full one** — a run that drops it in `quick`/`nofix` mode has reproduced the #74 gap. The literal `ACTION REQUIRED` label is intentional and is the by-name anchor that behavior 4's final re-scan reads (`../../shared/secret-scan-protocols.md`: "the files listed in the ACTION REQUIRED section"); it diverges from `/jr-skill-audit`, which bans the label — the divergence is documented in the repo `CLAUDE.md` "Shared conventions".

1. **Mode**: Which mode was used (small/medium/large, nofix/quick/full/PR if flags set, converge if `--converge`). If `--converge` was set, explicitly state whether convergence succeeded or hit the max-iterations limit (e.g., `converge (succeeded at pass 3)` vs `converge (did not converge — max iterations reached with N remaining findings)`). The latter corresponds to `convergenceFailed = true` and causes Phase 7 to exit with a non-zero status.
2. **Convergence** (if `--converge` was set): Number of iterations, per-iteration summary (files reviewed, findings count, outcome), whether fresh-eyes pass ran and its result, total convergence duration. Include the convergence summary table from the Display protocol.
3. **Stack detected**: Package manager, validation commands found, key frameworks identified
4. **Reviewed**: Number of files examined, list of reviewer agents and their dimension (only the ones that were spawned). If `--converge`, show per-iteration reviewer breakdown.
5. **Findings**: Total findings per reviewer, breakdown by severity and confidence, number deduplicated/dropped. If `--converge`, show cumulative totals across all iterations. **Claim verification** (when external-authority claims were found): confirmed / refuted (`[REJECTED — CLAIM REFUTED BY SOURCE]`) / capped-to-`speculative` (`[unverified external claim]`) counts; the sources cited (verification is default-on).
6. **Cross-file impacts**: Any consumer breakage detected outside the direct diff
7. **Coverage gaps**: (a) Files that reviewers failed to examine (from Phase 3 coverage check). (b) **Every member of the run-level `unreported` set**, each rendered by name — sourced from that set per rule 1 of `../../shared/subagent-reporting.md`, which owns that rule and the reason for it. Render each member using one of: `<dimension> returned nothing — that dimension was NOT reviewed` / `<implementer> returned nothing — its N findings were NOT attempted` / `simplification agent returned nothing — the Phase 5.5 pass did NOT run`. Keep these strings distinct — `phase8-followups.md` matches them by source. A member whose roll-call site already defines its own string (the fresh-eyes agent's `Fresh-eyes: UNREPORTED — …`, `../convergence-protocol.md`) is rendered as that site defines it; do not restate it here. **Mandatory whenever non-empty, in the compact report as well as the full one** — a run that hides an unreported dimension because it was in `quick` mode has reproduced issue #70. An empty (b) means every spawned subagent accounted for; it never means "no reviewers were spawned".
8. **User decisions**: Number of tasks approved, rejected, aborted (convergence-pass auto-approvals counted separately)
9. **Auto-learned**: Any new suppressions added to `.claude/review-config.md` (or "none" if no patterns detected)
10. **Fixed**: List of improvements applied, grouped by category. If `--converge`, group fixes by iteration (or "N/A — findings-only mode" if `nofix`)
11. **Contested**: Findings that implementers flagged as contested, with their reasoning
12. **Validation**: Final pass/fail status per command, baseline vs post-fix comparison. If `--converge`, show per-iteration validation results (or "N/A" if `nofix` or no validation commands detected)
13. **Diff summary**: Output of `git diff --stat` showing exactly what changed (or "N/A" if `nofix`)
14. **Skipped**: Any findings intentionally left unchanged, with reasoning
15. **Remaining failures** (if any): Unresolved validation regressions after max retries, or unconverged findings if max iterations reached
16. **Abort markers (if any)**: When `abortMode=true`, render the marker corresponding to `abortReason` per the canonical mapping in `../../shared/abort-markers.md` (single source of truth for both the `abortReason` enum AND the markers that fire outside the table). Implementation: Bash `case "$abortReason" in ... ;; esac` with one arm per row — no glob arm; typos fall through to `*) → [ABORT — UNLABELED]` and surface the contract violation.

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A".
