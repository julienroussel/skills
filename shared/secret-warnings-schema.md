# `secret-warnings.json` Schema

**Canonical source** for the schema, validation rules, and atomic-write requirements of `.claude/secret-warnings.json` (and per-session variants `.claude/secret-warnings-*.json`). `/review` reads this file at Phase 1 Track A and applies the rules at every read/write site. `/ship` will consume the same schema once it implements the cross-skill enforcement contract (currently NOT IMPLEMENTED — see "Cross-skill contract status" in `/review`).

## Top-level schema

Every `secret-warnings*.json` file MUST include a top-level `consumerEnforcement` field so consumers can detect enforcement status at runtime:

```json
{
  "consumerEnforcement": "not-implemented",
  "warnings": [
    { "file": "src/auth.ts", "line": 42, "patternType": "aws-key", "detectedAt": "2026-05-09T12:34:56Z" }
  ]
}
```

The `consumerEnforcement` value is `"not-implemented"` until `/ship` (or another consumer) implements the block-on-match contract; at that point it flips to `"enforced"`.

## Per-entry required fields

| Field | Type | Validation |
|-------|------|------------|
| `file` | string | Allowlist regex `^[a-zA-Z0-9_][-a-zA-Z0-9/_.]*$` PLUS the shared path validation block below. Spaces are deliberately disallowed so the allowlist matches the pre-commit hook's ALLOW_RE (`^[a-zA-Z0-9_/.-]+$`), preventing a writer-accepted-but-hook-rejected path from silently disabling the commit-blocker for other entries in the same file. Rare cross-platform paths containing spaces must be normalized (renamed or relative-path-adjusted) before a secret warning is written. |
| `line` | positive integer | — |
| `patternType` | string enum | One of the values in the `patternType` enum below. |
| `detectedAt` | ISO 8601 timestamp | Parseable by `date -d` / JavaScript `Date.parse`. |

## Per-entry optional fields

| Field | Type | Default | Purpose |
|-------|------|---------|---------|
| `status` | enum: `"active" \| "unverified" \| "acknowledged"` | `"active"` | Lifecycle marker maintained by Phase 7 step 3(b)/(c). |
| `missingRunCount` | integer | absent | Tracks consecutive `/review` runs where the entry's referenced file was missing. Increments in step 3(b); resets to `0` when the file re-appears in step 3(c). After 3 consecutive runs missing, the entry becomes eligible for pruning. |

Validators MUST accept entries carrying `status` or `missingRunCount` and MUST NOT fail validation on their presence.

## Shared path validation

In addition to the allowlist regex above, every `file` value (read or written) MUST pass these checks (mirrors `--scope` checks 4-6 in `/review`'s "Parameter sanitization"):

1. Reject paths containing any `\.{2,}` substring (`..`, `...`, etc.) — directory-traversal guard.
2. Reject paths where any segment starts with `.` (matches `(^|/)\.`) — block hidden directories and bare `.` segments.
3. Reject paths where any segment starts with `-` (matches `(^|/)-`) — argument-injection guard for shell commands that use the path.

These checks apply at every read site (Phase 5.6 append, Phase 7 step 3 prune, the pre-commit hook's `jq`-produced path).

## `patternType` enum

Schema validators MUST reject any `patternType` value not in this enum (route through the corrupt-file backup path):

`aws-key`, `stripe-key`, `openai-key`, `anthropic-key`, `github-token`, `slack-token`, `slack-webhook`, `discord-webhook`, `google-api-key`, `twilio-sid`, `private-key-pem`, `jwt`, `sendgrid-key`, `generic-url-credentials`, `database-url`, `generic-env-assignment`, `generic-quoted-assignment`, `other`.

These labels are derived from the Phase 1 secret-pre-scan pattern names. Writers SHOULD select the most specific enum value matching the detected pattern and SHOULD NOT default to `"other"` when a specific label exists. `"other"` is reserved for patterns genuinely lacking a dedicated enum value (e.g., `npm_`, `pypi-`, `dapi`, `glpat-`).

## Validation-failure halt

If the path value under audit-trail write fails the shared path validation above (e.g., a cross-platform path containing spaces on macOS/Windows), the writer MUST NOT silently drop the entry. Instead:

1. Halt the run with a distinct marker `[AUDIT TRAIL REJECTED — PATH VALIDATION]` in the Phase 7 report.
2. Log the rejected path (UNREDACTED — file paths are NOT secret values) and the reason for rejection (which character or pattern tripped the check).
3. Exit the review with a non-zero status.

This parallels `[SECRET-WARNINGS BACKUP FAILED]` — validation failure at the audit-trail-write path is a hard failure, never a silent drop, because the alternative is a secret that evades the pre-commit hook and any future `/ship` enforcement.

## Schema-failure backup

On any schema validation failure during read (`Phase 5.6` append OR `Phase 7 step 3` prune):

1. Back up the offending file to `.claude/secret-warnings.json.corrupt-$(date +%s)` using `mv` (atomic-rename on the same filesystem).
2. **Backup-failure handling**: if the backup `mv` or `cp` itself fails (disk full, permission error, filename collision from low-resolution `date +%s`), halt with a distinct marker `[SECRET-WARNINGS BACKUP FAILED]` in the Phase 7 report. Do NOT touch the original file. Exit with a non-zero status.
3. On successful backup, emit a Phase 7 ACTION REQUIRED entry: `ACTION REQUIRED: secret-warnings.json failed schema validation and was backed up to <path>. Inspect manually before any future /review run.`
4. Backup-path strings (including `.claude/secret-warnings.json.corrupt-<ts>`) are NOT redacted by the Phase 7 line-by-line redaction — only matched secret values are redacted.

Do NOT silently drop entries or start a fresh file without the backup — the prior contents may be the only record of detected secrets.

**Phase 7 exit-code contribution**: whenever any schema-validation backup is triggered during the run, Phase 7 exits with a non-zero status (see each skill's Phase 7 exit-code rules).

## Atomic write (mandatory)

The read-append-write cycle on `.claude/secret-warnings.json` MUST use the atomic-rename pattern: write the updated JSON to `.claude/secret-warnings.json.tmp` and then `mv .claude/secret-warnings.json.tmp .claude/secret-warnings.json` (atomic on the same POSIX filesystem). Additionally, the full read-append-write cycle MUST be wrapped in a file lock: `flock .claude/secret-warnings.json.lock bash -c '<read-append-write>'` (Linux/macOS).

Both requirements are mandatory — atomic-rename alone does not prevent lost-update races between concurrent readers, and `flock` alone does not prevent partial writes on crash.

### `flock(1)` availability probe

Before the first write attempt in a `/review` run, probe for `flock(1)` with a platform-agnostic check:

```bash
if command -v flock >/dev/null 2>&1; then FLOCK_AVAILABLE=true; else FLOCK_AVAILABLE=false; fi
```

This probe checks for the binary, not `uname` or OS — a stock macOS install lacks `flock` while a Homebrew-installed one has it, and the probe discriminates correctly either way. If `FLOCK_AVAILABLE=false`, this deterministically triggers the per-session filename fallback. Whenever the per-session fallback is activated for any reason, log the decision in the Phase 7 report: `Per-session filename strategy active — flock unavailable on this platform (e.g., stock macOS)`. This ensures the degraded mode is never silent.

### Per-session filename fallback (hard requirement)

If the execution environment cannot guarantee BOTH atomic-rename AND `flock` (e.g., `FLOCK_AVAILABLE=false`), fall back to per-session filenames as a hard requirement: use `secret-warnings-${baseCommit:0:8}-${CLAUDE_SESSION_ID:-$(date +%s)}.json` as the filename. The `$CLAUDE_SESSION_ID` env var (exposed by Claude Code v2.1.138+) is per-session unique and avoids the timestamp-collision risk of fast back-to-back runs within the same wall-clock second. The `:-$(date +%s)` fallback preserves backwards-compatibility for older Claude Code versions that do not expose the variable. Each `/review` (or `/audit`) run writes its own file, eliminating the concurrent-writer problem. This is a hard fallback, not an optional optimization.

For CI matrix builds sharing a workspace, use the per-session filename strategy by default. Consumers (`/ship`, the pre-commit hook) MUST glob `.claude/secret-warnings*.json` to enumerate all matching files.
