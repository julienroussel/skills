# Reviewer Dimension Boundaries, Severity, and Confidence

**Canonical source** for rules duplicated across `/audit` and `/review`. Both skills read this file at Phase 1 Track A and pass the content to reviewers as context. Update here to update both skills.

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
| Circular import | `architecture-reviewer` (`/audit` only) | typescript, performance |
| Dependency with CVE | `security-reviewer` | dependency |
| Outdated dep without CVE | `dependency-reviewer` (`/audit` only) | security |
| Color contrast | `accessibility-reviewer` | css |
| Unused CSS | `css-reviewer` (`/audit` only) | performance |
| Stale comment | `comment-reviewer` (`/audit` only) | any other dimension |
| Type design quality | `typescript-reviewer` | architecture |

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
