# Shared Cache Schema Validation

**Canonical source** for the schema-validation rules applied before trusting `.claude/review-profile.json` and `.claude/review-baseline.json` cached values; applied at every cache-read site by the skills that co-own these caches. Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section.

## review-profile.json (stack detection cache)

Before using any cached field, verify ALL of:

- **(a) version**: `version` is the integer `1`. Reject other types or values.
- **(b) validationCommands shape**: `validationCommands` is an object (not null, not array).
- **(c) cache-poisoning guard**: if `package.json` exists on disk but every value in `validationCommands` is null, treat the cache as stale and force re-detection — this prevents a poisoned cache from silently disabling validation.
- **(d) packageManager allowlist**: `packageManager` is one of `bun`, `pnpm`, `yarn`, `npm`. Reject any other value and force re-detection. (Interpolated into Phase 6 shell commands; allowlist prevents command injection via poisoned cache.)
- **(e) lockFile allowlist**: `lockFile` is one of `bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, or `null`. Reject other values and force re-detection.
- **(f) command shape allowlist**: each non-null entry in `validationCommands` matches `^(bun|pnpm|yarn|npm) run [a-zA-Z0-9_-]+$` OR `^make [a-zA-Z0-9_-]+$`. Reject any value containing shell metacharacters (`;`, `&&`, `||`, `|`, `` ` ``, `$(`, `>`, `<`) and force re-detection. (These values are executed as shell commands in Phase 6; a poisoned cache could inject arbitrary commands.)

The cache-write step also enforces the `.gitignore` check for `.claude/review-profile.json` per `gitignore-enforcement.md` to prevent committed cache manipulation.

**Canonical write shape** (the structure `/jr-review` Track C and `/jr-audit` write — referenced from both, not duplicated inline):

```json
{
  "version": 1,
  "generatedAt": "<ISO timestamp>",
  "sourceTimestamps": {
    "package.json": "<mtime or null>",
    "tsconfig.json": "<mtime or null>",
    "Makefile": "<mtime or null>"
  },
  "packageManager": "<bun|pnpm|yarn|npm>",
  "lockFile": "<filename or null>",
  "validationCommands": {
    "lint": "<command or null>",
    "typecheck": "<command or null>",
    "test": "<command or null>",
    "format": "<command or null>"
  },
  "frameworks": ["<detected from dependencies, e.g. next, react, tailwindcss, drizzle-orm>"]
}
```

## review-baseline.json (validation baseline cache)

Before using cached baseline results, verify:

- **(a) results shape**: `results` is an object (not null, not array).
- **(b) exit-code type**: each entry's `exitCode` is an integer.
- **(c) timestamp sanity**: `generatedAt` is a valid ISO 8601 timestamp not in the future.

If any check fails, treat the cache as stale and re-run the validation commands.

**Canonical write shape** (referenced from `/jr-review` Track D, not duplicated inline):

```json
{
  "generatedAt": "<ISO timestamp>",
  "ttlMinutes": 10,
  "results": {
    "lint": { "exitCode": 0, "issueCount": 3 },
    "typecheck": { "exitCode": 0, "errorCount": 0 },
    "test": { "exitCode": 0, "passCount": 42, "failCount": 0, "summary": "<first 5 lines of output>" }
  }
}
```

## Binary availability probe (review-profile.json only)

Even when all schema checks pass, the cached `packageManager` may no longer resolve (nvm version switch, package manager uninstalled, devDependencies pruned). Before trusting:

1. Run the detected package manager with `--version` (e.g., `bun --version`, `pnpm --version`). Cap each invocation at a 2-second timeout.
2. If the probe fails (exit non-zero, binary not on PATH), force full re-detection regardless of timestamps.
3. **Same-session shortcut**: if `lastProbedAt` is set within the last 60 seconds, skip the probe — a binary that resolved 60 seconds ago is overwhelmingly likely to still resolve. Otherwise run the probe and write `lastProbedAt: <epoch-seconds>` to the cache as part of the next write step.

## When to invalidate review-baseline.json

Always invalidate `review-baseline.json` whenever `review-profile.json` is invalidated — a stack change implies the baseline expectations are stale.
