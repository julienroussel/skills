# Shared Cache Schema Validation

**Canonical source** for the schema-validation rules applied before trusting `.claude/review-profile.json` and `.claude/review-baseline.json` cached values. `/audit` and `/review` co-own these caches; both apply this protocol at every cache-read site.

## review-profile.json (stack detection cache)

Before using any cached field, verify ALL of:

- **(a) version**: `version` is the integer `1`. Reject other types or values.
- **(b) validationCommands shape**: `validationCommands` is an object (not null, not array).
- **(c) cache-poisoning guard**: if `package.json` exists on disk but every value in `validationCommands` is null, treat the cache as stale and force re-detection — this prevents a poisoned cache from silently disabling validation.
- **(d) packageManager allowlist**: `packageManager` is one of `bun`, `pnpm`, `yarn`, `npm`. Reject any other value and force re-detection. (Interpolated into Phase 6 shell commands; allowlist prevents command injection via poisoned cache.)
- **(e) lockFile allowlist**: `lockFile` is one of `bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, or `null`. Reject other values and force re-detection.
- **(f) command shape allowlist**: each non-null entry in `validationCommands` matches `^(bun|pnpm|yarn|npm) run [a-zA-Z0-9_-]+$` OR `^make [a-zA-Z0-9_-]+$`. Reject any value containing shell metacharacters (`;`, `&&`, `||`, `|`, `` ` ``, `$(`, `>`, `<`) and force re-detection. (These values are executed as shell commands in Phase 6; a poisoned cache could inject arbitrary commands.)

The cache-write step also enforces the `.gitignore` check for `.claude/review-profile.json` per `gitignore-enforcement.md` to prevent committed cache manipulation.

## review-baseline.json (validation baseline cache)

Before using cached baseline results, verify:

- **(a) results shape**: `results` is an object (not null, not array).
- **(b) exit-code type**: each entry's `exitCode` is an integer.
- **(c) timestamp sanity**: `generatedAt` is a valid ISO 8601 timestamp not in the future.

If any check fails, treat the cache as stale and re-run the validation commands.

## Binary availability probe (review-profile.json only)

Even when all schema checks pass, the cached `packageManager` may no longer resolve (nvm version switch, package manager uninstalled, devDependencies pruned). Before trusting:

1. Run the detected package manager with `--version` (e.g., `bun --version`, `pnpm --version`). Cap each invocation at a 2-second timeout.
2. If the probe fails (exit non-zero, binary not on PATH), force full re-detection regardless of timestamps.
3. **Same-session shortcut**: if `lastProbedAt` is set within the last 60 seconds, skip the probe — a binary that resolved 60 seconds ago is overwhelmingly likely to still resolve. Otherwise run the probe and write `lastProbedAt: <epoch-seconds>` to the cache as part of the next write step.

## When to invalidate review-baseline.json

Always invalidate `review-baseline.json` whenever `review-profile.json` is invalidated — a stack change implies the baseline expectations are stale.
