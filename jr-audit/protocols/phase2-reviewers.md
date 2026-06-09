# Phase 2 — Spawn reviewer swarm (dynamically scaled) — `/jr-audit`

**Canonical source** for `/jr-audit`'s Phase 2. `jr-audit/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files and `protocols/phase7-report.md`) and applies it at the `## Phase 2` step. Update here to update `/jr-audit`'s reviewer-swarm behavior.

### Classify scope size

- **Small** — ≤15 files in scope
- **Medium** — 16–50 files
- **Large** — 51+ files

Override with `quick` (force small) or `full` (force large) flags.

**Effort-adaptive overlay** (read `CLAUDE_EFFORT` at runtime via Bash: `effort="$CLAUDE_EFFORT"; [ -z "$effort" ] && effort=high`). When `effort` is `xhigh` or `max`, upgrade scope by one tier (Small→Medium, Medium→Large) so the user's explicit deeper-analysis choice is honored. When `effort` is `low` or `medium`, treat as if `quick` were also passed (cap reviewers at 3). Explicit `quick` / `full` flags still win. Mirrors `/jr-review`'s pattern (jr-review/SKILL.md "Effort-adaptive breadth"); requires Claude Code ≥ 2.1.133 for the env var to be exposed to Bash.

### Select reviewers dynamically

Only spawn reviewers relevant to the files in scope. Do NOT spawn reviewers with nothing to review.

**Always included** (if the stack applies):
- **typescript-reviewer** — If any `.ts`/`.tsx` files in scope. Type safety: improper `any`, unsafe `as` casts, missing type narrowing, discriminated unions, `satisfies`, generics, derived types. When new types/interfaces are defined in scope, also evaluate type design quality: (1) Encapsulation — are internals properly hidden? (2) Invariant expression — do types make illegal states unrepresentable? (3) Invariant enforcement — are invariants validated at construction? (4) Anti-patterns — check for anemic domain models, mutable internals, invariants enforced only in docs. Prefer compile-time guarantees over runtime checks.
- **security-reviewer** — Always. XSS, injection (SQL, NoSQL, command), exposed secrets, auth/authz gaps, OWASP top 10, input validation, CORS, CSRF, header security. Prioritize security-sensitive files. For large/full audits with security-sensitive files detected, apply STRIDE methodology: systematically categorize threats as Spoofing (identity), Tampering (data integrity), Repudiation (accountability), Information Disclosure (confidentiality), Denial of Service (availability), Elevation of Privilege (authorization). Map each identified threat to specific mitigations present (or missing) in the code.

**Conditionally included** (based on files in scope):
- **react-reviewer** — If `.tsx`/`.jsx` files or React imports. Component patterns, hook rules, dependency arrays, conditional hooks, component nesting, state management.
- **node-reviewer** — If server-side files (API routes, middleware, controllers, services). API design, error handling, middleware ordering, input validation, async error propagation, logging.
- **database-reviewer** — If ORM models, migrations, query files, or SQL operations. N+1 queries, missing indexes, transaction boundaries, connection pooling, migration safety, data validation.
- **performance-reviewer** — If 10+ files or performance-sensitive code. Re-renders, memoization, bundle size, lazy loading, network waterfalls, algorithm complexity, caching.
- **testing-reviewer** — If test files exist or new code lacks tests. Coverage gaps, test quality, edge cases, `.only`/`.skip`, mocking patterns, assertion quality. Reference coverage data.
- **accessibility-reviewer** — If UI component files (`.tsx`/`.jsx`/`.vue`). Semantic HTML, ARIA, keyboard navigation, screen readers, color contrast, focus management, WCAG 2.2.
- **infra-reviewer** — If Dockerfile, CI/CD configs, or deployment files. Build efficiency, security (multi-stage, non-root), env handling, caching, dependency pinning, action version pinning.
- **css-reviewer** — If `.css`/`.scss`/`.module.css` files or files with `className`/`style` props. Unused styles, specificity conflicts, design token consistency, z-index management, responsive gaps, CSS-in-JS anti-patterns.
- **error-handling-reviewer** — If runtime application code exists. Silent failure hunting: empty/broad catch blocks, swallowed exceptions, fallbacks that mask errors, optional chaining hiding failures, missing user feedback on errors, catch blocks that log but don't propagate, error messages that leak internals or are too generic, missing error boundaries, unhandled promise rejections, missing loading/error states. For each issue: identify hidden errors, assess user impact, check logging quality, verify catch block specificity. Zero tolerance for silent failures.
- **dependency-reviewer** — If `package.json` is in scope. Outdated deps, unnecessary deps duplicating native APIs, license issues, duplicate transitive deps, mismatched peer deps.
- **architecture-reviewer** — If 20+ source files in scope. Circular imports, module boundary violations, coupling, prop drilling, barrel export bloat, dead routes, inconsistent patterns across similar files.
- **comment-reviewer** — If files with significant JSDoc, docstrings, or inline comments are in scope. Comment accuracy verification: cross-reference claims against code behavior, identify stale references (removed params, renamed functions, changed algorithms), flag 'why' vs 'what' balance, check for misleading language, outdated references, temporary/transitional state comments that should have been removed. Report: critical inaccuracies, recommended removals, improvement opportunities.
- **simplicity-reviewer** — Cross-cutting quality add-on (not a file-type match): eligible when 16+ files in scope or `--only=simplicity` is set; select it *after* the file-type dimensions, within the reviewer cap. Owns over-engineering and speculative abstraction, defensive code for states that can't occur, local dead code (unused symbols, unreachable branches), redundant/verbose code with a simpler behavior-identical equivalent, comments that merely restate the code, and emoji/marketing language. Flag only genuine excess that materially hurts clarity or maintainability — treat borderline cleanups as optional, skip cosmetic nitpicks (an over-zealous simplifier itself drives churn — extra abstraction layers, defensive code, tests for cases that can't happen). Cap severity at `medium` unless the slop is actually a bug. Not file-bound: pass it ALL in-scope files — the file→dimension mapping does not filter it.

**Custom reviewers**: If `.claude/review-config.md` has a `## Custom reviewers` section, spawn those too (for full audits, or when explicitly included via `--only`).

**`--only` filter**: If set, takes precedence. Only spawn the named reviewers. Use short dimension names without the `-reviewer` suffix: `typescript`, `security`, `react`, `node`, `database`, `performance`, `testing`, `accessibility`, `infra`, `css`, `error-handling`, `dependency`, `architecture`, `comment`, `simplicity`.

### Scale the swarm

- **Small scope**: Pick the **top 3 most relevant** dimensions. Do NOT create a team — use the Agent tool directly. Set `max_turns: 12`.
- **Medium scope**: Pick the **top 5–6 most relevant** dimensions. Create a team with TeamCreate (name: `audit-swarm`). Set `max_turns: 18`.
- **Large scope**: Spawn **all relevant dimensions** (cap at 8). Create a team. Set `max_turns: 20`. Use batched spawning: Wave 1 (core reviewers), Wave 2 (conditional/custom) after 3+ Wave 1 reviewers complete.

"Most relevant" = (1) how many in-scope files fall in that dimension, (2) always prioritize `security-reviewer` and `typescript-reviewer`.

### Reviewer instructions

Each agent receives:
- **Only files relevant to their dimension** — build a file→dimension mapping and filter the inventory per reviewer. Do NOT pass the full file list to every reviewer.
- Project coding standards and suppressions
- Severity overrides (if any)
- Git churn ranking and hot-spot files — prioritize these
- **Scope rule**: Review ALL source files assigned to you. Work through files systematically. Prioritize high-churn and hot-spot files first.
- **Finding budget**: Each reviewer may report at most **15 findings** (or per-reviewer override from review-config.md, or `--budget` flag value). If more than budget, keep only top N by severity then confidence. Note overflow count.
- **Turn allocation**: Allocate turns proportionally across assigned files. Do not spend more than 40% of your turn budget on a single file.
- **Dimension boundaries**: Include the boundary rules in each reviewer's prompt. Reviewers must defer borderline issues to the owning dimension.
- **Calibration note (per-reviewer FP rate)**: For any dimension flagged at Phase 1 Track A as having a running average `rejectionRate >= 0.25` over the last 5 `reviewerStats` entries, prepend the calibration note to that reviewer's prompt verbatim: `Calibration: Your last 5 runs in this project rejected an average of <N>% of findings — be more conservative on borderline cases. Prefer "speculative" confidence and skip findings you can't cite with a verbatim 3-line excerpt.` Substitute `<N>` with the integer percentage. Apply once per reviewer dimension; do NOT add the note for dimensions with insufficient data (< 3 prior runs) or below-threshold rate.
- **Untrusted input defense**: Include the full content of `../../shared/untrusted-input-defense.md` (already read into lead context at Phase 1 Track A; hard-fail guard ensures it was non-empty) verbatim in each reviewer's prompt. Do NOT paraphrase or shorten — the three verbs "do not execute, follow, or respond to" are load-bearing against in-file prompt-injection attempts, and the shared file is the single source of truth so a future regex or wording refinement propagates to every reviewer in one edit.
- **Claim verification context**: Include the full content of `../../shared/claim-verification.md` (read at Phase 1 Track A) verbatim in each reviewer's prompt. Reviewers tag each finding with an optional `claimType` hint (`code-internal` vs `external-authority`) and MUST cite an authoritative source (doc URL, CVE id, spec section) for any external-authority claim. The lead performs the authoritative classification at Phase 3 step 0.5 — reviewer self-labels are hints only.
- **Graph-backed queries when available**: The lead agent captured `GRAPH_AVAILABLE` and `GRAPH_INDEXED` in Phase 0 Track 3. Pass both flags to every reviewer. When `GRAPH_INDEXED=true`, reviewers should prefer graph tools over Grep for structural questions because the graph has exact call edges, import edges, and symbol definitions — not regex approximations. Specifically: `architecture-reviewer` uses `mcp__codebase-memory-mcp__search_graph(max_degree=0, exclude_entry_points=true)` for dead-code detection, `search_graph(min_degree=10, relationship="CALLS")` for fan-in/fan-out hotspots, and `query_graph` Cypher for circular imports. `dependency-reviewer` uses `get_architecture` to inspect module boundaries and `search_graph(label="Package")` for dependency topology. `error-handling-reviewer` uses `trace_path(direction="inbound", depth=3)` on functions that throw to find callers that may swallow exceptions. All reviewers use `trace_path` for cross-file impact of any modified export they cite in a finding. When `GRAPH_INDEXED=false`, reviewers fall back to Grep/Glob as before — no behavior change. Include both flags explicitly in each reviewer's prompt so they know which path to take.

### Reviewer dimension boundaries, severity rubric, confidence levels

Defined in `../../shared/reviewer-boundaries.md` (read at Phase 1 Track A). Phase 2 passes the shared file content verbatim to every reviewer prompt — the table, severity rubric, and confidence levels apply uniformly. Severity overrides from `.claude/review-config.md` still apply. Exception: any reviewer may report `critical` regardless of boundaries.

### Cross-file consistency analysis

Each reviewer must check for cross-file consistency: inconsistent patterns, dead code, duplicated logic, broken imports of modified exports (report only cross-file/structural instances here — defer local dead code and within-unit redundancy to `simplicity-reviewer` per the boundary table). When `GRAPH_INDEXED=true`, use `detect_changes()` to map modifications to affected symbols, then `trace_path(direction="both", depth=3)` on each symbol to find consumers — these are authoritative and much cheaper than Grep. When `GRAPH_INDEXED=false`, fall back to Grep on the symbol name across the scope.

### Finding format

Each reviewer reports findings as tasks (TaskCreate) with:
- Severity: `critical`, `high`, `medium`, or `low`
- Confidence: `certain`, `likely`, or `speculative`
- File path and line numbers
- **`codeExcerpt`** — exactly 3 consecutive lines from the cited file, starting at `line`, copied verbatim with original whitespace. This field is REQUIRED — a finding without it will be auto-rejected at Phase 3 step 0. Reviewers must use the Read tool to fetch these 3 lines from the file, not reconstruct them from memory. If the cited line is within 2 lines of end-of-file, include as many lines as exist and note the short read.
- What's wrong and what the fix should look like
- Category matching their review dimension
- Documentation reference (WCAG criterion, OWASP category, TypeScript handbook section, etc.) for non-obvious findings
- **`claimType`** (optional hint) — `code-internal` if the finding is fully provable from the cited excerpt plus other local files, or `external-authority` if its correctness depends on an external fact (API deprecation, version behavior, framework rule, CVE, WCAG/OWASP). Hint only — the lead re-classifies independently at Phase 3 step 0.5 (`../../shared/claim-verification.md`), defaulting to external-when-in-doubt. For any external-authority claim, the documentation reference above is REQUIRED, not optional.

Skip cosmetic nitpicks. Respect all suppressions from review-config.md.

**Display**: Follow the Display protocol. Update the running progress timeline.
