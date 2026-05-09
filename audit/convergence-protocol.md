# /audit — Convergence Loop Protocol

**Skill-local protocol** for `/audit --converge`. Mirrors the role of `review/convergence-protocol.md` but with /audit-specific defaults (lower `maxIterations`, advisor at iter ≥ 2 instead of ≥ 3, no fresh-eyes pass).

Read into lead context at Phase 1 Track A only when `--converge` is set; hard-fail (Phase 1 abort) if missing or fails the smoke-parse anchor `pre-iteration advisor check`.

## Initialization

At program start (once, before any iteration):

```text
iteration=1
convergenceFailed=false
abortMode=false
abortReason=""
convergenceStartTime=$(date +%s%3N)
tmpDir=$(mktemp -d -t audit-converge.XXXXXX)
allModifiedFiles=[]
iterationLog=[]
```

Set a cleanup trap: `trap 'rm -rf "$tmpDir"' EXIT` (no-op if Phase 7 already removed `$tmpDir` explicitly). Parse `--converge[=N]` to set `maxIterations` (default 2, clamped to `[2, 5]` per Flag conflicts).

## File tracking mechanism

Convergence iterates over the set of files that the *previous* iteration's implementers modified. Capture the working-tree diff against `baseCommit` BEFORE Phase 5 and AFTER Phase 6 of each iteration:

```bash
git diff --name-only -z "$baseCommit" > "$tmpDir/iter-${iteration}-pre.list"
# ... Phase 5 + Phase 6 of iteration ...
git diff --name-only -z "$baseCommit" > "$tmpDir/iter-${iteration}-post.list"
sort -uz "$tmpDir/iter-${iteration}-post.list" > "$tmpDir/iter-${iteration}-post.sorted"
sort -uz "$tmpDir/iter-${iteration}-pre.list"  > "$tmpDir/iter-${iteration}-pre.sorted"
comm -z -23 "$tmpDir/iter-${iteration}-post.sorted" "$tmpDir/iter-${iteration}-pre.sorted" \
  > "$tmpDir/iter-${iteration}-modified.list"
```

If `sort -z` or `comm -z` are unavailable (BSD/macOS without GNU coreutils), reuse the `tr '\0' '\n'` + perl-newline-detection fallback documented in `/review` Phase 5 ("NUL-sort availability fallback"). Refuse to proceed (set `convergenceFailed=true`, `abortReason="nul-sort-newline"`, halt loop) if any path contains a newline byte after the fallback — the comparison cannot be done safely.

## Iteration termination conditions

Check at the start of each new iteration:

1. **`modifiedFiles` empty** — no files changed by the previous iteration's implementers. Converged successfully. Skip remaining iterations and proceed to Phase 7.
2. **`iteration > maxIterations`** — max iterations reached without convergence. Set `convergenceFailed=true`. Output banner: `⚠ Convergence did not converge — N findings remain unaddressed after <maxIterations> iterations.` Phase 7 must exit non-zero.
3. **Wall-clock timeout exceeded** — if `Date.now() - convergenceStartTime > 900000` (15 min), halt the loop. Output: `Convergence timed out after 15 minutes. Proceeding to Phase 7.` Note in Phase 7 report under `Remaining failures`. Set `convergenceFailed=true`.
4. **HEAD moved unexpectedly** — before each iteration, verify `[ "$(git rev-parse HEAD)" = "$baseCommit" ]`. If not, an implementer ran a git command. Apply the **Combined revert sequence** from `../shared/secret-scan-protocols.md`, set `abortMode=true`/`abortReason="head-moved-convergence-start"`, halt loop, proceed to Phase 7 in abort mode.
5. **Pre-iteration advisor check (iteration ≥ 2)** — if the upcoming iteration is 2+ (i.e., we're about to start the FIRST convergence pass after the initial audit), call `advisor()` (no parameters — full transcript auto-forwarded) before spawning the new pass. Two consecutive iterations producing fixes that themselves produce findings is a signal the loop may be chasing a wrong root cause. The advisor sees `iterationLog` and can spot drift. If the advisor concurs, proceed silently. If the advisor raises a concrete concern (e.g., "iteration 1 introduced regressions in the same dimension that the initial pass flagged — the fix strategy may be wrong"), halt the loop and present via AskUserQuestion: `Advisor flagged a convergence concern before iteration N: <one-line summary>. Options: [Continue iterating] / [Stop here — proceed to Phase 7] / [Abort and revert all changes since $baseCommit]`. On **Stop here**, set `convergenceFailed=false` (deliberate early stop, not a failure) and proceed to Phase 7. On **Abort**, apply the Combined revert sequence, set `abortMode=true`/`abortReason="user-abort-convergence"`, proceed to Phase 7 in abort mode. The advisor runs at most `maxIterations - 1` times per `/audit --converge` invocation. (`/audit`'s threshold is iteration ≥ 2 vs `/review`'s ≥ 3 because `/audit`'s default `maxIterations` is lower (2 vs 3) — proportionally, drift detection should fire earlier.)

## For each convergence pass

1. **Re-scope to `modifiedFiles` only**: pass the modified-file list to Phase 2 reviewer prompts via `xargs -0 -a "$tmpDir/iter-${iteration}-modified.list"`. Do NOT re-scope to the full codebase — convergence only re-audits what implementers touched.
2. **Re-run Phases 2 → 6** in sequence, with these constraints:
   - **Phase 2**: spawn fewer reviewers — top 3 dimensions only (regardless of `quick`/`full` setting). Convergence passes are about catching regressions, not full coverage.
   - **Phase 3 step 0**: codeExcerpt content check still applies (working-tree mode — `/audit` has no `--pr` mode).
   - **Phase 4 approval**: pre-approval advisor check (skewed-dimension / high-volume signals) STILL applies; the user re-approves each pass's findings interactively.
   - **Phase 4.5**: append to `.claude/audit-history.json` with the same `runId` as the initial pass (a single `/audit` invocation produces one logical history entry; convergence iterations are sub-events). Add an `iteration` field to `runs[]` and `reviewerStats[]` entries written during convergence so per-pass FP rates are visible.
   - **Phase 5 pre-dispatch advisor check**: SKIP — the advisor already ran for the initial dispatch; re-running adds latency without proportional benefit. The pre-iteration advisor check (#5 above) covers convergence-specific concerns.
   - **Phase 5.55** fix verification still runs.
   - **Phase 5.6** secret re-scan still runs. If a secret halt fires in any iteration, set `abortMode=true`/`abortReason="secret-halt-convergence"`, halt loop, proceed to Phase 7 in abort mode.
   - **Phase 6** validation still runs. Max retries reset to the configured cap each iteration (do NOT carry over remaining retries from the previous pass).
3. **Append iteration record** to `iterationLog`: `{iteration, modifiedFileCount, newFindings, approvedCount, rejectedCount, validationDelta, durationMs}`. The advisor sees this in the next pre-iteration check.
4. **Update `allModifiedFiles`**: union of all per-iteration `modifiedFiles` lists (deduped). Phase 7 report uses this to summarize cumulative impact.
5. Increment `iteration` and loop back to the termination check.

## Display

Output a per-iteration banner like `▷ Convergence iteration 2/2 — re-auditing 7 modified files`. Update timeline.

## Phase 7 integration

When convergence runs, the Phase 7 report's `Mode` field MUST state convergence outcome: `converged after N iterations`, `did not converge after N iterations (max reached)`, `did not converge (timeout)`, or `convergence aborted: <reason>`. If `convergenceFailed=true` from any termination path, Phase 7 exits non-zero (mirrors `/review`'s Phase 7 exit-code rules).
