# Reviewer Dimension Boundaries, Severity, and Confidence

**Canonical source** for reviewer-dimension boundaries plus the severity/confidence rubrics, passed to reviewers/translators as context (the dimension table is review/audit-specific; the rubrics apply more broadly). Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section.

## Dimension ownership (prevents duplicate findings)

Each reviewer owns a **primary responsibility**. Borderline issues are deferred to the owning dimension.

| Issue | Owner | Not |
|-------|-------|-----|
| Missing error boundary | `error-handling-reviewer` | react, performance |
| `any` enabling injection | `typescript-reviewer` | security |
| Missing `key` prop | `react-reviewer` | performance |
| Inline function causing re-render | `performance-reviewer` | react |
| Missing `useMemo` / `useCallback` | `performance-reviewer` | react |
| Unhandled promise rejection | `error-handling-reviewer` | typescript, security |
| Silent failure (empty catch) | `error-handling-reviewer` | security, typescript |
| Circular import | `architecture-reviewer` (`/jr-audit` only) | typescript, performance |
| Dependency with CVE | `security-reviewer` | dependency |
| Outdated dep without CVE | `dependency-reviewer` (`/jr-audit` only) | security |
| Color contrast | `accessibility-reviewer` | css |
| Unused CSS | `css-reviewer` (`/jr-audit` only) | performance |
| Stale comment | `comment-reviewer` (`/jr-audit` only) | any other dimension |
| Type design quality | `typescript-reviewer` | architecture |
| Over-engineering / needless abstraction | `simplicity-reviewer` | architecture, typescript |
| Defensive code for impossible states | `simplicity-reviewer` | error-handling |
| Local dead code (unused symbol, unreachable branch) | `simplicity-reviewer` | architecture |
| Redundant / verbose code with a simpler equivalent | `simplicity-reviewer` | performance |
| Comment that merely restates the code | `simplicity-reviewer` | comment (owns stale) |
| Missing `:key` in `v-for` | `vue-reviewer` | performance |
| Lost reactivity (destructured `reactive`/`ref`) | `vue-reviewer` | performance |
| Mutable default argument | `python-reviewer` | error-handling |
| Missing `declare(strict_types=1)` | `php-reviewer` | security |
| Breaking change to public API contract | `api-contract-reviewer` | typescript, node |
| Frontend↔backend DTO drift | `api-contract-reviewer` | typescript |
| Missing telemetry on critical path | `observability-reviewer` | error-handling |
| User PII written to logs | `observability-reviewer` | security |
| Hardcoded user-facing string | `i18n-reviewer` | accessibility |
| Broken / invalid mermaid syntax | `mermaid-reviewer` | comment |
| Mermaid diagram drifted from code | `mermaid-reviewer` | comment, architecture |

`vue-reviewer` owns Vue component & reactivity patterns (SFC structure, Composition/Options API, lifecycle, `v-for` keys), symmetric with `react-reviewer`; it defers a11y to `accessibility-reviewer` and render cost to `performance-reviewer`. `php-reviewer` and `python-reviewer` own language-idiom and language-version concerns for their respective files, deferring injection/XSS to `security-reviewer`, ORM/query issues to `database-reviewer`, and silent-failure/error-swallowing to `error-handling-reviewer`. `api-contract-reviewer` owns the public API surface (breaking changes, request/response schema consistency, cross-stack DTO drift, versioning), deferring internal type-safety to `typescript-reviewer` and persistence concerns to `database-reviewer`. `observability-reviewer` owns logging/metrics/tracing *signal quality* (is the system observable, is PII kept out of logs), deferring *swallowed* errors to `error-handling-reviewer` and secret *storage* to `security-reviewer`. `i18n-reviewer` owns localization readiness (hardcoded strings, missing keys, locale formatting), deferring semantic-HTML/ARIA to `accessibility-reviewer`. `mermaid-reviewer` owns fenced ` ```mermaid ` diagram blocks — syntax validity plus drift between the diagram and the code it documents — deferring prose-comment/docstring accuracy to `comment-reviewer` and cross-module structural concerns to `architecture-reviewer`.

`simplicity-reviewer` owns *within-unit* excess (over-engineering, local dead code, redundancy, comments that restate code, defensive code for impossible states). *Between-module* structure (dead routes, coupling, circular imports) stays with `architecture-reviewer`; *inaccurate* comments with `comment-reviewer`; *type* complexity with `typescript-reviewer`; *runtime* cost with `performance-reviewer`. Runs in both `/jr-review` (diff-scoped) and `/jr-audit` (scope-wide). Findings are code-internal — settled by the `codeExcerpt` sanity-check, no external-authority verification.

**Exception**: any reviewer may report a `critical` finding regardless of boundaries.

## Severity calibration rubric

All reviewers use this shared rubric (subject to overrides from `.claude/review-config.md`):

- **critical** — Will cause bugs, data loss, security vulnerabilities, or crashes in production. Examples: SQL injection, unhandled null dereference on a required path, missing auth check on a protected route, infinite re-render loop, unsafe migration that locks a production table, command injection via unsanitized input.
- **high** — Likely to cause issues under normal usage or significantly degrades code quality. Examples: missing error boundary around async operation, `any` type that defeats downstream type checking, missing key prop in a mapped list, N+1 query in a list endpoint, unvalidated user input passed to a database query, missing rate limiting on a public API.
- **medium** — Won't break anything but misses an opportunity for meaningful improvement. Examples: missing `useMemo` on an expensive computation, `as` cast that could be replaced with type narrowing, missing test for a new edge case, missing index on a frequently queried column, missing error state in a data flow.
- **low** — Minor improvement, borderline nitpick. *Dropped unless trivially fixable.*

## Confidence levels

- **certain** — Demonstrably wrong, violates a documented standard, or will break at runtime.
- **likely** — Fairly confident but depends on context that can't be fully verified.
- **speculative** — Suspects an issue but not sure. Requires human judgment.
