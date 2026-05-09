# Shared Secret-Scan Protocols

**Canonical source** for the secret-scan behavioral rules common to `/audit` and `/review` (and consumed by the pre-commit hook installed by `/review`). Both skills read this file at Phase 1 Track A. Update here to update both skills.

`/review` consumes ALL sections (it has full headless/CI support and post-implementation re-scan flows). `/audit` consumes the **Advisory-tier classification** section only — at the time of writing `/audit` is interactive-only and does not run a CI/headless secret-halt protocol or User-continue path.

## Headless/CI detection (`isHeadless`)

`isHeadless` is the canonical predicate used at every site that changes behavior for unattended execution. Defined once here and referenced by name elsewhere — do NOT re-expand or abbreviate the predicate at individual sites; inconsistent re-expansion has historically caused divergent behavior between phases.

`isHeadless` is `true` if ANY of the following is true:

1. The `--auto-approve` flag is set. This is the authoritative signal for non-interactive intent.
2. Any of these CI environment variables is non-empty: `CI`, `GITHUB_ACTIONS`, `GITLAB_CI`, `JENKINS_URL`, `BUILDKITE`, `CIRCLECI`, `TF_BUILD`, `DRONE`, `WOODPECKER_CI`, `TEAMCITY_VERSION`.
3. Stdin is not a terminal (`[ ! -t 0 ]`) — catches cases where AskUserQuestion would hang because the user cannot respond (e.g., `echo y | /review`).

### `AUTO_APPROVE` export (mandatory)

After argument parsing completes (Phase 1 pre-checks, before any tracks run), if `--auto-approve` was parsed, the lead agent MUST `export AUTO_APPROVE=1` for the remainder of the session so the canonical `isHeadless` shell predicate resolves correctly. The shell-only check is intentional — it lets every site that uses `isHeadless` run a single self-contained `bash -c '...'` invocation without re-implementing the OR-chain in agent state. Failure to export `AUTO_APPROVE` silently downgrades headless behavior to interactive (defeats the entire purpose of `--auto-approve`).

### Post-export self-check (mandatory)

Immediately after the `export AUTO_APPROVE=1`, run a self-check in the SAME Bash tool invocation:

```bash
bash -c 'export AUTO_APPROVE=1; [ -n "$AUTO_APPROVE" ] || { echo "[CONTRACT VIOLATION — AUTO_APPROVE NOT EXPORTED]" >&2; exit 2; }'
```

If the `bash -c` invocation exits with a non-zero status, treat it as a contract-violation halt and terminate the run with a non-zero exit code. Do NOT continue past this gate even if other phases would run successfully without `AUTO_APPROVE` set. The single-quoted `bash -c` argument is required so the inner shell expands `$AUTO_APPROVE` against its inherited environment rather than the outer shell expanding it before the spawn. The export and self-check MUST execute in the same Bash tool invocation — the Claude Code harness does not persist shell state across separate Bash tool calls; splitting them would have the second call see an empty `$AUTO_APPROVE` and fire a spurious halt.

Hard-exit at this site is appropriate: the export runs before any team is created, any audit trail is written, or any findings exist, so there is no Phase 7 state to render and no team to clean up — a plain `exit 2` is sufficient and does not need to route through the abort-mode machinery.

### Implementation (shell)

```bash
isHeadless=$([ -n "$AUTO_APPROVE" ] || [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ] \
  || [ -n "$GITLAB_CI" ] || [ -n "$JENKINS_URL" ] || [ -n "$BUILDKITE" ] \
  || [ -n "$CIRCLECI" ] || [ -n "$TF_BUILD" ] || [ -n "$DRONE" ] \
  || [ -n "$WOODPECKER_CI" ] || [ -n "$TEAMCITY_VERSION" ] || [ ! -t 0 ] \
  && echo true || echo false)
```

### Verification

At the start of Phase 1 Track B (after argument parsing), the lead SHOULD evaluate `isHeadless` once and log it: `Detected mode: headless=<true|false>` (use `shared/display-protocol.md`'s timeline format).

Every reference to "headless/CI mode" in `/review` resolves to `isHeadless=true`. Sites affected: Phase 1 step 1 (staged-secret check), step 6 (diff size), step 7 (secret pre-scan), Phase 4 (`--auto-approve` interactive warning), Phase 5.6, Phase 6 regression re-scan, Convergence Phase 5.6, Fresh-eyes fix cycle, Phase 7 step 3(b) (unverified-entry acknowledgment prompt), and Phase 8 (follow-up issue creation). All sites MUST evaluate the same predicate; phase-specific exceptions (e.g., Phase 8's `--pr` carve-out) must be spelled out at that site.

## CI/headless secret-halt protocol

When a secret re-scan detects strict-tier matches and `isHeadless=true`: do not use AskUserQuestion. Instead, halt immediately and run the combined revert sequence below. Each invoking site MUST set `abortReason` BEFORE invoking the protocol so Phase 7 step 16 can render the correct marker (see `shared/abort-markers.md`):

- Phase 1 pre-implementation case: `abortReason="secret-halt-phase-1"` → marker `[SECRET DETECTED — NO REVERT NEEDED]`.
- Phase 5.6: `abortReason="secret-halt-phase-5.6"`.
- Phase 6 regression re-scan: `abortReason="secret-halt-phase-6-regression"`.
- Convergence Phase 5.6: `abortReason="secret-halt-convergence-5.6"`.
- Fresh-eyes fix cycle: `abortReason="secret-halt-fresh-eyes"`.

### Combined revert sequence

1. **Clean untracked files first** — they may contain secrets introduced by implementers and would not be removed by `git checkout` if interrupted. Compare current `git ls-files --others --exclude-standard -z` (NUL-delimited) against `$untrackedBaseline`; log the list under `[REVERT — Untracked files removed]` in the Phase 7 report; delete new entries with `git clean -fd -- <newUntrackedFiles>`.
2. **Clean new gitignored files** — also run `git ls-files --others -z` (without `--exclude-standard`) and compare against `$untrackedBaselineAll` to detect files written to gitignored paths. `git clean` skips them; pipe through `xargs -0 rm -f --` or individually double-quote each path. Use NUL-delimited output throughout to safely handle filenames containing spaces, glob characters, or other shell metacharacters.
3. **Detect and remove new symbolic links** — compare `find . -type l -print0` against the pre-Phase-5 symlink baseline file at `$symlinkBaseline` (NUL-delimited) using `comm -z -23 <(find . -type l -print0 | sort -z) <(sort -z "$symlinkBaseline")`. Remove any new symlinks BEFORE checkout to prevent writes through symlinks to locations outside the repository.
4. **Restore working tree** — `git -c core.symlinks=false checkout "$baseCommit" -- .`. The `core.symlinks=false` flag causes git to write symlinks as plain text files containing the target paths, eliminating the write-through-symlink primitive AND closing the TOCTOU window between enumeration and checkout.
5. **Reset index** — `git reset "$baseCommit" -- .` to unstage any new files that do not exist at `$baseCommit`.

### Pre-vs-post-implementation branch

If `$baseCommit` is not yet established (e.g., secret detected in Phase 1 before implementers run), no automated modifications exist to revert — log the secret match details to the Phase 7 report with a `[SECRET DETECTED — NO REVERT NEEDED]` label and transfer control to Phase 7 in abort mode.

Otherwise (when `$baseCommit` exists and changes were reverted), log with `[SECRET DETECTED — CHANGES REVERTED]` and transfer to Phase 7 in abort mode.

### Team cleanup

If a team was created in Phase 2, call `TeamDelete` to clean up agents — do NOT wait for shutdown confirmations. Phase 7 will exit non-zero per its exit-code rules.

### Setting `abortMode=true`

The protocol sets `abortMode=true` before transferring control to Phase 7 (see Phase 7 "Abort-mode execution"). The caller MUST also set `abortReason` to the value listed above for the invoking site.

## User-continue path after post-implementation secret detection

When a post-implementation secret re-scan (Phase 5.6, Phase 6 regression re-scan, Convergence Phase 5.6, Fresh-eyes fix cycle) OR the Phase 1 pre-implementation secret pre-scan detects a strict-tier match AND the user chooses `Continue` at the interactive AskUserQuestion prompt (i.e., the user is knowingly accepting the secret into the working tree rather than aborting + unstaging / reverting), the implementing site MUST execute ALL SIX behaviors below — no subset or substitution is permitted. The suppression list `$postImplAcceptedTuples` is shared across Phase 1 and post-implementation sites so a Phase-1-accepted match does not re-fire in any subsequent re-scan against the same value.

### Mandatory execution order

The six behaviors split into "register now" (synchronous at the Continue site) and "execute later" (Phase 7 driven). This split exists because behavior 4 depends on Phase 7 having rendered the report first.

**Register now, BEFORE behavior 2's audit-trail write** (synchronous):
- Behavior 1 (ACTION REQUIRED log entry registered in the Phase 7 report queue).
- Behavior 5 (set `userContinueWithSecret=true` latch immediately — CANNOT be unset downstream).
- Behavior 6 (append the accepted `(file, line, patternType, valueHash)` tuple to `$postImplAcceptedTuples` immediately — so any subsequent re-scan in the SAME run sees it already-accepted).

**Then run behavior 2** (audit-trail write). Behavior 2 contains a conditional hard-exit on shared-path-validation failure → `[AUDIT TRAIL REJECTED — PATH VALIDATION]`. If behavior 2 hard-exits, the "register now" behaviors above have already fired, so the exit-code latch, suppression list, and report-queue entry survive — only the audit-trail-file persistence is missed.

**Then run behavior 3** (pre-commit hook offer). May execute before or after behavior 2 in the interactive order, but MUST execute before any halt that terminates the run. If behavior 2 hard-exits and behavior 3 has not yet run, skip it — the audit trail is already rejected, so the hook would have nothing consistent to enforce.

**Execute later (Phase 7 driven)**: Behavior 4 fires AFTER Phase 7 has rendered the main report. It reads the behavior-1 entries from the report queue, performs a final re-scan against each listed file, and emits the standalone `⚠ SECRET STILL PRESENT: [file:line] — do NOT commit without removing it.` warning if any secret is still present. Behavior 4's execution is gated on `userContinueWithSecret=true` (or equivalently on the presence of behavior-1 entries in the report) — it does NOT re-check whether behavior 2 succeeded, because the warning is about the working tree, not the audit trail.

**Rationale for the split**: dropping behavior 4 after a behavior-2 hard-exit would hide the working-tree secret from the operator's terminal; the register-now split ensures behaviors 1/5/6 survive the hard-exit so Phase 7 can still run behavior 4 using the registered state. Dropping behavior 3 after a hard-exit is acceptable because the audit trail is already known-bad and the hook depends on a consistent audit trail.

### The six behaviors

1. **ACTION REQUIRED logging**: log to the Phase 7 report under a prominent `ACTION REQUIRED: Secrets detected in working tree` section, preserving the file path(s), line number(s), and pattern type(s) of each detected secret. File paths and line numbers are NOT redacted (only matched secret values are redacted).

2. **Audit-trail write**: append the detected secret locations to `.claude/secret-warnings.json` per `shared/secret-warnings-schema.md` (atomic-rename + `flock`, or per-session filename fallback when `FLOCK_AVAILABLE=false`). Apply the shared path validation block to every `file` value before writing; on validation failure apply the schema's Validation-failure halt protocol (emit `[AUDIT TRAIL REJECTED — PATH VALIDATION]`, log the rejected path and reason, exit non-zero). This closes the window where a writer-accepted Continue decision silently drops a secret from the audit trail.

3. **Pre-commit hook offer**: run the Pre-commit hook offer sequence defined in the owning skill's Phase 5.6, subject to its existing skip conditions (headless/CI mode → skip; `FLOCK_AVAILABLE=false` → skip with the per-session-fallback log line). The hook is the only user-actionable commit blocker and MUST be offered at every Continue site, not only at Phase 5.6.

4. **Final `⚠ SECRET STILL PRESENT` warning**: after Phase 7 report output, perform a final secret re-scan on the files listed in the ACTION REQUIRED section. If the secret is still present, emit the standalone warning: `⚠ SECRET STILL PRESENT: [file:line] — do NOT commit without removing it.`

5. **Non-zero exit (latched)**: set a run-scoped flag `userContinueWithSecret=true` that CANNOT be unset for the remainder of the run — a subsequent clean re-scan on retry, a clean Phase 6 validation, or any other intervening success does NOT clear it. Exit the review with a non-zero status code whenever `userContinueWithSecret=true` at Phase 7 (see each skill's Phase 7 exit-code rules). This latch ensures wrapping scripts and CI observe the Continue-with-secret condition regardless of downstream retry outcomes.

6. **Suppression-list snapshot**: snapshot each detected `(file, line, patternType, valueHash)` tuple and ADD it to the run-scoped `$postImplAcceptedTuples` suppression list (a NUL-delimited temp file, created lazily at first use with `mktemp`). The list is keyed on the exact 4-tuple. `valueHash` is a SHA-256 hex digest of the matched secret substring (the literal characters that matched the canonical regex for `patternType`):

    ```bash
    valueHash=$(printf '%s' "$matchedValue" | shasum -a 256 | awk '{print $1}')
    ```

    Including `valueHash` prevents secret-laundering: a subsequent implementer who mutates the accepted line to contain a DIFFERENT secret value of the same `patternType` at the same `line` will hash differently, the 4-tuple will NOT match the suppression list, and the new value re-fires the halt. Subsequent post-implementation scans (Phase 5.6 next iteration, Convergence Phase 5.6, Fresh-eyes, Phase 6 regression re-scan) MUST compute the match's `valueHash` and treat any match whose full 4-tuple appears in this list as "already-accepted" and NOT re-fire a halt on it. The suppression list is additive within a single run — the user's "Continue" decision persists across subsequent iterations for the SAME value only. This prevents repeated prompts for the same accepted secret, prevents the retroactive-revert penalty where a later user abort wipes earlier convergence fixes, AND prevents laundering a new secret past the halt via line-content mutation.

### Why all six are mandatory

Behaviors 1-6 are unified because silently dropping any one of them degrades safety:

- Dropping (3) removes the only automated commit-blocker.
- Dropping (4) or (5) hides the condition from CI wrappers.
- Dropping (1) or (2) hides it from the audit trail and from `/ship`'s future enforcement contract.
- Dropping (6) re-prompts the user on every subsequent iteration and makes a later abort retroactively revert earlier accepted fixes.

## Advisory-tier classification for re-scans

All post-implementation secret re-scans (Phase 5.6, Phase 6 regression re-scan, Convergence Phase 5.6) AND Phase 7 step 3(c) `"other"` full-scan apply the same strict/advisory tier classification.

**Strict tier** (always halt): all patterns by default.

**Advisory tier** (report in findings but do not halt): specific patterns with high false-positive rates (`SK`, `sk-`, `dapi`) may be demoted to advisory when they meet deterministic demotion criteria defined in each skill's Phase 1 Track B step 7 (the criteria differ slightly between skills based on scope — `/review` reviews diffs, `/audit` reviews full files). Advisory-tier matches are included in the Phase 7 report for human review.

**Halt vs. line-update semantics**:
- Phase 5.6 / Phase 6 / Convergence 5.6: only **strict-tier matches trigger the halt**. Advisory matches are logged but do not halt.
- Phase 7 step 3(c) full-scan: only strict-tier matches **count toward line-update / persistence decisions**. Advisory matches do not.

**Phase-1-vs-post-implementation distinction**:
- At Phase 1 (pre-implementation), ALL pattern matches including `SK`/`sk-`/`dapi` are treated as **strict tier**. Rationale: Phase 1 scans the user's own code changes where false-positive tolerance should be lower, and the user is present (or in CI, should be explicitly halted) to make an informed decision.
- At post-implementation re-scans, the demotion criteria fire — implementers/simplification-agents may legitimately introduce non-secret content that pattern-matches.
- Phase 7 step 3(c) is treated as post-implementation (advisory-tier demotions apply).

**Escalation overrides demotion**: at any tier, an `SK`/`sk-`/`dapi` match in an assignment context (preceded by `=`, `:`, or following a variable name containing `key`/`secret`/`token`/`auth`) or in a config/environment file escalates back to strict, regardless of demotion criteria. Each skill specifies its own assignment-context detection.

**Never silently dismiss**: advisory-tier matches MUST always be surfaced in the Phase 7 report (file path, line number, pattern type — these are NOT redacted; only matched values are redacted).
