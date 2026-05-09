# Abort Marker Rendering

**Canonical source** for the `abortReason` → rendered-marker mapping used by `/audit`, `/review`, and `/skill-audit`'s Phase 7 cleanup. All three skills read this file at Phase 1 Track A and apply the rules below when rendering the report. Update here to update every skill.

## When to render

A skill renders an abort marker in its Phase 7 report only when `abortMode=true`. Each abort site that sets `abortMode=true` MUST also set `abortReason` to one of the values below. Implementations render via Bash `case "$abortReason" in ... ;; esac` (no glob — every value is matched explicitly).

## Reason → Marker mapping

| `abortReason` value(s) | Rendered marker |
|------------------------|-----------------|
| `head-moved-phase-5.6`, `head-moved-convergence-start`, `head-moved-convergence-5.6`, `head-moved-fresh-eyes-pre-spawn`, `head-moved-fresh-eyes-findings` | `[ABORT — HEAD MOVED]` |
| `symlink-escape` | `[REVERT BLOCKED — SYMLINK ESCAPES REPO]` |
| `symlink-readlink-failed` | `[REVERT BLOCKED — READLINK FAILED]` |
| `symlink-readlink-empty` | `[REVERT BLOCKED — READLINK RETURNED EMPTY]` |
| `symlink-dangling` | `[REVERT BLOCKED — SYMLINK DANGLING OR UNRESOLVABLE]` |
| `nul-sort-newline` | `[REVERT BLOCKED — NUL-SORT UNAVAILABLE + NEWLINE IN PATH]` |
| `find-traversal-failed` | `[REVERT BLOCKED — FIND TRAVERSAL FAILED]` — `establish-base-anchor.sh` step 1's `find -type l -print0` exited non-zero (typically permission-denied on a subdirectory). A partial symlink baseline would weaken the symlink-escape gate and misclassify missing symlinks as newly-created on revert. |
| `repo-root-unset` | `[REVERT BLOCKED — REPO_ROOT UNSET]` |
| `anchor-error` | `[ABORT — ANCHOR ERROR]` — script invocation returned an unexpected exit code OR the stderr-marker parse fell through. Caller surfaces the script's stderr in the Phase 7 report. |
| `fresh-eyes-terminal-failure` | `[FRESH-EYES TERMINAL FAILURE]` |
| `secret-halt-*` (all secret-halt variants: `secret-halt-phase-1`, `secret-halt-phase-5.6`, `secret-halt-phase-5.6-user-abort`, `secret-halt-phase-6-regression`, `secret-halt-convergence`, `secret-halt-convergence-5.6`, `secret-halt-convergence-5.6-user-abort`, `secret-halt-fresh-eyes`, `secret-halt-fresh-eyes-user-abort`) | Use the `[SECRET DETECTED — ...]` markers rendered by the secret-halt protocol (`[SECRET DETECTED — CHANGES REVERTED]` post-implementation, `[SECRET DETECTED — NO REVERT NEEDED]` pre-implementation). Do NOT render an additional `[ABORT — *]` marker — avoid duplicate emission for the same event. |
| `user-abort`, `user-abort-convergence`, `user-abort-phase-5-dispatch` | `[ABORT — USER ABORT]` |
| `unmatched-scope` | `[ABORT — UNMATCHED SCOPE]` — `/skill-audit` Phase 1 Track B discovered zero skills matching the user's filter (bare positional or `--scope=<glob>`). Caller appends an "Available skills: ..." hint. |
| `shared-file-missing` | `[ABORT — SHARED FILE MISSING]` — `/skill-audit` Phase 1 Track A hard-fail guard tripped (any of the six shared protocol files was missing, empty, or failed structural smoke-parse). Distinct from `/audit` and `/review`'s reuse of an inline message because skill-audit has a smaller shared-file set. |
| `*` (anything else, including unset) | `[ABORT — UNLABELED]` — **contract violation**: `abortMode=true` was set without a recognised `abortReason`. Surface as `ACTION REQUIRED` so the gap is visible. |

## Markers rendered outside the `abortReason` mapping

Some markers are rendered by their owning protocol independently of `abortReason`. These continue to fire in addition to the table above:

- `[SECRET DETECTED — CHANGES REVERTED]` — CI/headless secret-halt protocol, post-implementation case.
- `[SECRET DETECTED — NO REVERT NEEDED]` — CI/headless secret-halt protocol, pre-implementation case (no `$baseCommit` yet).
- `[REVERT — Untracked files removed]` — CI/headless secret-halt protocol, files cleaned during revert.
- `[AUDIT TRAIL REJECTED — PATH VALIDATION]` — Phase 5.6 schema-validation block / User-continue path behavior 2; emitted when a writer's `file` value fails shared path validation.
- `[SECRET-WARNINGS BACKUP FAILED]` — Phase 5.6 / Phase 7 step 3(a); emitted when the corrupt-file backup `mv`/`cp` itself fails (disk full, permission error, filename collision).
- `[AUDIT-HISTORY BACKUP FAILED]` — `shared/audit-history-schema.md` quarantine protocol (Read-side integrity check); emitted when the corrupt-file backup `mv` itself fails (disk full, permission error, filename collision). Direct analogue of `[SECRET-WARNINGS BACKUP FAILED]`. Halts the run with non-zero exit.

## Exit-code contribution

All markers in this file contribute to the non-zero Phase 7 exit code per each skill's exit-code rules. Specifically: any `[ABORT — *]`, any `[REVERT BLOCKED — *]`, any `[SECRET DETECTED — *]`, `[FRESH-EYES TERMINAL FAILURE]`, `[AUDIT TRAIL REJECTED — PATH VALIDATION]`, `[SECRET-WARNINGS BACKUP FAILED]`, and `[AUDIT-HISTORY BACKUP FAILED]` force the run to exit non-zero. The unlabeled fallback `[ABORT — UNLABELED]` ALSO forces non-zero (the contract violation is itself a failure signal).

## Anti-patterns

- **Don't emit two markers for the same event.** A `secret-halt-*` reason that has already produced a `[SECRET DETECTED — ...]` marker MUST NOT additionally emit `[ABORT — *]`. The mapping table is explicit about this.
- **Don't render markers when `abortMode=false`.** Phase 7 exit-code rules trigger non-zero exit for several non-abort conditions (`convergenceFailed=true`, `userContinueWithSecret=true`, schema-validation backup), but those have their own surface text and are NOT rendered through this table.
- **Don't add a glob arm in the `case` statement.** Every reason value must be matched explicitly so a typo (e.g., `serect-halt-phase-1`) falls through to `*) → [ABORT — UNLABELED]` and surfaces the contract violation. A `secret-halt-*) ...` glob arm would silently absorb typos.
