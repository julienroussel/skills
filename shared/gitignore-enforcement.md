# `.gitignore` Enforcement for Cache and Audit-Trail Files

**Canonical source** for the write-safety protocol applied at every cache-write and audit-trail-write site in `/audit` and `/review`. Update here to update all sites.

## The protocol (applied before every matching write)

Before writing `<PATH>` (a `.claude/*.json` or `.claude/*.md` file produced by `/audit` or `/review`):

1. Check whether the path is tracked by git:
   ```bash
   git ls-files --error-unmatch "<PATH>" 2>/dev/null
   ```
2. **If tracked**: emit a warning (or log to the Phase 7 report in headless/CI mode) that the file is tracked. The specific warning text depends on the file — see the "Why" column below for the security rationale so the warning is informative. Do not auto-untrack; the user may have intentionally committed it.
3. **If not in `.gitignore`**: append the path (or a glob covering it) to `.gitignore` automatically and inform the user: `Added <PATH> to .gitignore.`

## Sites that apply this protocol

| Skill | Path | Why it must not be committed |
|-------|------|------------------------------|
| `/audit` + `/review` | `.claude/review-profile.json` | Stack detection cache. A poisoned cache could set `validationCommands` to all-null, silently disabling validation, or inject shell metacharacters that execute in Phase 6. |
| `/audit` + `/review` | `.claude/review-baseline.json` | Validation baseline. A committed baseline with inflated failure counts could make real regressions appear pre-existing, silently passing Phase 6 validation. |
| `/audit` + `/review` | `.claude/review-config.md` | Auto-learned suppressions. A committed config with crafted suppression rules could silence security findings across all future runs. |
| `/audit` | `.claude/audit-history.json` | Audit history. A committed history with manipulated false-positive rates could bias reviewer calibration. |
| `/audit` | `.claude/audit-report-YYYY-MM-DD.md` (glob: `.claude/audit-report-*.md`) | Audit reports contain finding descriptions, code excerpts, and potentially redacted secret locations. |
| `/review` | `.claude/secret-warnings.json` (+ per-session variants `.claude/secret-warnings-*.json`) | Secret audit trail. Records file paths, line numbers, and pattern types where secret patterns were detected — committing exposes the locations of current or historical secrets. |
| `/review` | `.claude/secret-hook-patterns.txt` | Pre-commit hook regex patterns. /review writes this file (one regex per line) before invoking the pre-commit hook installer; the hook then reads it at runtime. A committed patterns file could be tampered to weaken or disable specific secret-detection rules across all future commits — the additive baseline patterns hardcoded in the hook template still fire, but extension patterns (the broader set) would silently regress. |

## Ancillary files (in `.gitignore` but no per-write protocol)

These files are produced as transient or error-path artifacts of the protocol-checked writes above. They should be in `.gitignore` so a `git add .` does not pick them up, but they do NOT warrant the per-write `git ls-files --error-unmatch` check — the check would fire on every atomic rename or `flock` invocation, adding overhead to a hot path with no extra safety value (the underlying persistent file already passed the check). Consumers (`/doctor`'s gitignore-coverage check) MUST include these patterns in the canonical pattern set even though no skill invokes the per-write protocol on them:

| Pattern | Producer | Why it must not be committed |
|---------|----------|------------------------------|
| `.claude/secret-warnings*.json.tmp` | Atomic-rename intermediate (Phase 5.6 + Phase 7 step 3 prune; secret-warnings-schema "Atomic write") | Mid-write file that should be `mv`d away within milliseconds — but a crash mid-write leaves it persisting with the same content as the real audit trail. |
| `.claude/secret-warnings*.json.lock` | `flock(1)` lock file (secret-warnings-schema "Atomic write") | Empty by design; never contains secret content but accumulates as orphaned lock files if a crash skips cleanup. |
| `.claude/secret-warnings*.json.corrupt-*` | Schema-failure backup (secret-warnings-schema "Schema-failure backup") | Contains the same content as the audit trail at the moment validation failed — equivalent persistence-of-secret-locations risk. Persistent (timestamped, never auto-deleted). |

## Anti-patterns

- **Don't skip the protocol on `--auto-approve` / CI mode** — the check still runs, but its warning is logged to the Phase 7 report rather than emitted interactively. Skipping entirely defeats the defense.
- **Don't rely on `.gitignore` alone** — a committed `.gitignore` that excludes the path is not the same as the path not being tracked. Always run `git ls-files --error-unmatch` first.
- **Don't delete the file when it's tracked** — the user may have committed it deliberately (e.g., a team's shared review-config.md). Warn and let them decide.
- **Don't batch writes across sites** — each site applies the protocol independently. A single Phase 7 run may write `audit-history.json`, `audit-report-*.md`, and `review-config.md`; each needs its own check.
