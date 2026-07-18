# Phase 2 — Spawn reviewers (dynamically scaled) — `/jr-review`

**Canonical source** for `/jr-review`'s Phase 2. `jr-review/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files) and applies it at the `## Phase 2` step. Update here to update `/jr-review`'s reviewer-swarm behavior.

### Effort-adaptive breadth (`CLAUDE_EFFORT`)

At Phase 2 entry, the lead agent reads the `CLAUDE_EFFORT` env var (per Claude Code v2.1.133, exposed to the Bash tool). Use this exact Bash invocation — do NOT use the dollar-brace skill-substitution form anywhere in this skill body:

```bash
effort="$CLAUDE_EFFORT"; [ -z "$effort" ] && effort=high
```

The value resolves to one of `low`, `medium`, `high`, `xhigh`, `max`. If empty (uncommon — Pro/Max users on Opus 4.6/4.7 default to `high` since v2.1.117), the `[ -z ... ]` fallback assigns `high`.

**Why the env-var approach (and not skill substitution)**: Claude Code's skill-substitution syntax — the dollar sign, an open brace, `CLAUDE_EFFORT`, a close brace — gets resolved at skill-load time, baking one literal value into the prose. That would break this section's conditional table because every reference would resolve to the same loaded value instead of branching. Reading the env var via Bash at execution time produces a real branchable variable.

This drives **swarm breadth** — reasoning *depth* is already governed by the model and the `effort` frontmatter.

Effort tier table (applied as overlays on top of the diff-size selection below):

| `CLAUDE_EFFORT` | Reviewer cap | Default `--converge` (when bare `--converge` is passed) |
|--------------------|--------------|---------------------------------------------------------|
| `low`, `medium`    | Cap at **2** reviewers regardless of diff size. Treat as if `quick` were also passed. | **2** (minimum allowed by `--converge` validation). |
| `high` (default)   | No change. Dimensions selected per "Scale the swarm" below. | **3** (current behavior). |
| `xhigh`, `max`     | Allow up to **8** dimensions on Large diffs (was 6); Medium diff allowed 5 (was 4). | **5**. |

The effort overlay applies BEFORE the explicit `quick`/`full` flag override (`quick` and `full` still win — the user is opting in to a specific size). If `--only=` is set, the reviewer cap is the minimum of (effort cap, len(--only list)).

**Where this affects the rest of the skill:**
- Phase 1 step parameter-validation for `--converge=N`: when the user passes bare `--converge`, the parser substitutes the effort-adaptive default from this table into the `=N` value before applying the 2–10 range check. An explicit `--converge=N` is unaffected.
- "Scale the swarm" section below: caps use the effort-adjusted reviewer count.
- Convergence Phase 2: convergence-pass scaling rules ("max 2 reviewers" exception when modifiedFiles ≤ 10) are unchanged — convergence passes are intentionally lighter than the first pass.

### Determine diff size

Count changed files and total changed lines from the diff:
- **Small** — 1–3 files and <100 changed lines
- **Medium** — 4–10 files or 100–500 changed lines
- **Large** — 11+ files or 500+ changed lines

Override with `quick` (force small) or `full` (force large) flags.

### Select reviewers dynamically

Using the file→dimension mapping from Phase 1, select only the relevant review dimensions. Do NOT spawn reviewers for dimensions that have no changed files to review.

**Always included** (if the stack applies):
- **typescript-reviewer** — If any `.ts` or `.tsx` files changed. Type safety: improper `any`, unsafe `as` casts, missing type narrowing, discriminated unions, `satisfies`, generics, derived types. Deep type-level TypeScript expertise.
- **security-reviewer** — Always included for any diff. XSS vectors, injection risks (SQL, NoSQL, command), exposed secrets, insecure dependencies, auth/authz gaps, OWASP top 10. For backend: input validation, rate limiting, CORS, CSRF, header security.

**Conditionally included** (based on changed files):
- **react-reviewer** — If `.tsx`/`.jsx` files or files importing React are changed. Component patterns, hook rules, effect dependency arrays, conditional hooks, component definitions inside components, state management, re-render patterns.
- **vue-reviewer** — If `.vue` files (or files importing `vue`) are changed. SFC patterns, reactivity (`ref`/`reactive`/`computed`/`watch`), Composition vs Options API, lifecycle hooks, `v-for` `:key`, props/emits typing, lost-reactivity pitfalls (destructured `reactive`/`ref`), component nesting. Mirror of react-reviewer; defers a11y to accessibility, render cost to performance.
- **node-reviewer** — If server-side JavaScript or TypeScript files changed (`.js`/`.mjs`/`.cjs`/`.ts`) — API routes, middleware, controllers, services, server entry points. API design conventions (REST/GraphQL), error handling patterns, middleware ordering, input validation, async error propagation, logging, environment config. Backend-scoped: defer frontend component concerns to react/vue and general type-safety to typescript.
- **php-reviewer** — If `.php` files are changed. PHP language-version idioms (typed properties, enums, `readonly`, `match`, nullsafe `?->`), `declare(strict_types=1)`, PSR-12 style, null safety, exception patterns, framework conventions (Laravel/Symfony DI & services). Defers ORM N+1 to database, template XSS/escaping to security.
- **python-reviewer** — If `.py` files are changed. Pythonic idioms, type hints (PEP 484/585), mutable default arguments, context managers, comprehensions, f-strings, dataclasses/pydantic, async/await correctness, dependency/venv hygiene. Coordinates bare-`except` with error-handling.
- **api-contract-reviewer** — If API-surface files changed: route handlers, controllers, GraphQL schemas/resolvers, OpenAPI/Swagger specs, DTOs/serializers, shared cross-stack type definitions, or client API-call sites. Breaking changes to public contracts, request/response schema consistency, frontend↔backend DTO drift, versioning, validation coverage at trust boundaries. Defers auth to security, persistence to database, internal type-safety to typescript.
- **database-reviewer** — If ORM models, migration files, query builders, or files with SQL/database operations changed. N+1 queries, missing indexes, transaction boundaries, connection pooling, migration safety (e.g., locking tables in production), data validation at the persistence layer.
- **performance-reviewer** — If 5+ files changed or performance-sensitive code is touched (rendering logic, data fetching, loops, caching). Unnecessary re-renders, missing memoization, bundle size impact, lazy loading, network waterfalls, algorithm complexity, caching opportunities.
- **testing-reviewer** — If test files changed, or if new code was added without corresponding tests. Behavioral coverage over line coverage: identify critical untested paths (error paths, edge cases, business logic, negative tests), evaluate test quality (tests behavior not implementation, resilient to refactoring, DAMP principles), check for implementation coupling (mocks that mirror implementation details), rate gap criticality (1-10 scale: 9-10 critical, 7-8 important, 5-6 edge cases, 3-4 nice-to-have). No `.only`/`.skip` in committed code.
- **accessibility-reviewer** — If UI component or server-rendered template files (`.tsx`/`.jsx`/`.vue`/`.svelte`/`.html`/`.blade.php`/`.twig`/`.j2`/`.jinja`) changed. Semantic HTML, ARIA attributes, keyboard navigation, screen reader compatibility, color contrast, focus management, WCAG 2.2 compliance.
- **i18n-reviewer** — If user-facing UI, template, or string-catalog files changed. Hardcoded user-facing strings, missing/orphaned translation keys, key parity across locale catalogs, placeholder/interpolation-token parity (e.g. `{count}` / ICU MessageFormat args present in every locale's copy of a key), untranslated fallbacks and machine-translation artifacts (mojibake, leftover source-language text), locale-sensitive date/number/currency formatting, pluralization rules, RTL/text-direction handling. Mechanical catalog-consistency checks (key + placeholder parity) are code-internal and provable; defer native translation-accuracy judgment ("is this idiomatic real-world usage?") to the standalone `/jr-i18n` skill, and semantic-HTML/ARIA to accessibility.
- **infra-reviewer** — If `Dockerfile`, `docker-compose.yml`, CI/CD configs (`.github/workflows/`, `.gitlab-ci.yml`), IaC files (`.tf`/`.tfvars` Terraform, CloudFormation templates, Kubernetes manifests, Pulumi), or deployment/config files changed. Build efficiency, security best practices (multi-stage builds, non-root users), environment variable handling, caching strategies, dependency pinning. For IaC: cloud-resource security (public S3 buckets, over-permissive IAM / security groups, unencrypted resources, secrets hardcoded in `.tf`), provider/module version pinning, state-management hygiene, resource tagging.
- **error-handling-reviewer** — If runtime application code changed. Silent failure hunting: empty/broad catch blocks, swallowed exceptions, fallbacks that mask errors, optional chaining hiding failures, missing user feedback on errors, catch blocks that log but don't propagate, error messages that leak internals or are too generic. For each issue: identify hidden errors, assess user impact, check logging quality, verify catch block specificity. Zero tolerance for silent failures.
- **observability-reviewer** — If runtime application/service code changed. Structured logging presence and quality, appropriate log levels, missing metrics/tracing/telemetry on critical paths, correlation IDs, alerting hooks, and PII/secrets leaking into logs. Defers swallowed/suppressed errors to error-handling, secret storage to security.
- **mermaid-reviewer** — If changed markdown/`.mdx` (or any) files contain ` ```mermaid ` fenced blocks. Mermaid **syntax validity** (the block parses/renders — `certain`, code-internal) and **diagram drift vs code** (does the architecture/sequence/ER/flow diagram still match the code it documents — cite the diverging code as an external/cross-file claim). Scope is the diagram block itself; prose-comment accuracy is out of scope here.
- **simplicity-reviewer** — Cross-cutting quality add-on (not a file-type match): select it *after* the file-type dimensions above, and only when 5+ files changed or `--only=simplicity` is set, within the effort cap. Owns over-engineering and speculative abstraction, defensive code for states that can't occur, local dead code (unused symbols, unreachable branches), redundant/verbose code with a simpler behavior-identical equivalent, comments that merely restate the code, and emoji/marketing language. Flag only genuine excess that materially hurts clarity or maintainability — treat borderline cleanups as optional and skip cosmetic nitpicks (an over-zealous simplifier itself drives churn — extra abstraction layers, defensive code, tests for cases that can't happen). Cap severity at `medium` unless the slop is actually a bug. Not file-bound: pass it ALL changed files — the file→dimension mapping does not filter it.

**`--only` filter**: If set, takes precedence. Only spawn the named reviewers regardless of diff size or file classification. Use short dimension names without the `-reviewer` suffix: `security`, `typescript`, `react`, `vue`, `node`, `php`, `python`, `api-contract`, `database`, `performance`, `testing`, `accessibility`, `i18n`, `infra`, `error-handling`, `observability`, `mermaid`, `simplicity`.

### Reviewer dimension boundaries, severity rubric, confidence levels

Defined in `../../shared/reviewer-boundaries.md` (read at Phase 1 Track A and passed verbatim to every reviewer prompt). Severity overrides from `.claude/review-config.md` still apply. Exception: any reviewer may report `critical` regardless of boundaries.

### Scale the swarm

Apply diff-size selection first, then clamp the reviewer count to the effort-adaptive cap from "Effort-adaptive breadth" above.

All sizes spawn reviewers the same way — via the Agent tool with `subagent_type: "jr-reviewer"` and **no `name:`** (canonical: `../../shared/subagent-reporting.md` "Spawn rule"). Passing `name:` makes the reviewer a persistent teammate whose final response never reaches the lead, which silently loses its findings; unnamed, it returns its report in its completion notification. Give each reviewer a distinct `description` instead — that is what the progress table renders. There is no `TeamCreate` step, and `team_name` is accepted but ignored. Diff size governs only the reviewer **count**:
- **Small diff**: Pick the **top 2 most relevant** dimensions.
- **Medium diff**: Pick the **top 3–4 most relevant** dimensions (5 if `CLAUDE_EFFORT` is `xhigh`/`max`).
- **Large diff**: Spawn **all relevant dimensions** (up to 6 max — or up to 8 max if `CLAUDE_EFFORT` is `xhigh`/`max`).

When `CLAUDE_EFFORT` is `low` or `medium`, force the reviewer count to 2 regardless of diff size (treat as if `quick` were also passed). The `quick` and `full` explicit flags still override these defaults.

"Most relevant" is determined by: (1) how many changed files fall in that dimension, (2) always prioritize `security-reviewer` and `typescript-reviewer`.

### Freeze the reviewed tree during the pass

**The reviewed tree is frozen from the first reviewer spawn until Phase 3 step 0's `codeExcerpt` compare completes.** In that window the lead MUST NOT change any in-scope file — not dispatch an implementer, not run a tree-mutating command (`git checkout/reset/clean`, `rm`, `perl -i`, `mv`), not apply an obvious fix or correct a typo it noticed. Every fix waits for Phase 5, which exists for exactly this. A reviewer cannot be an independent check on a tree the checker is editing, and step 0's excerpt match will reject a *correct* finding about code that moved underneath the reviewer (reason `excerpt-mismatch`), which — uncorrected — poisons that reviewer's cross-run FP-calibration. Applies in working-tree and `--branch` mode; `--pr` reads an immutable `gh api` snapshot and is exempt. Under `--converge` the freeze re-arms **per pass**: the between-pass Phase 5/5.5/6 edits are the intended fix path, and each pass reviews a settled tree.

To make a violation detectable rather than merely trusted, capture a content signature over the in-scope files at spawn, using only granted primitives — hash the working-tree content of the reviewed set: `FREEZE_ANCHOR=$(git -c core.quotepath=false diff HEAD | shasum | awk '{print $1}')` (add `git ls-files --others --exclude-standard -z | xargs -0 shasum` for untracked in-scope files, and `git diff "$mergeBase"..HEAD` in `--branch` mode). Do NOT hash a newline-joined file-list scalar via `printf '%s\0' "$list"` — a quoted scalar emits a single record, so `xargs -0` passes one multi-line non-existent filename and the anchor silently becomes the empty-string hash, a constant that never detects a move (`convergence-protocol.md` NUL-safety rule). Phase 3 step 0 recomputes it; if it moved, this pass's `excerpt-mismatch` rejections are marked stats-exempt (canonical: `../../shared/audit-history-schema.md` "Skip stats-exempt rejections when the reviewed tree moved during a pass").

### Reviewer instructions

Each agent receives:
- **Only the files and diff hunks relevant to their dimension** (use the file→dimension mapping from Phase 1). Do NOT pass the full diff to every reviewer.
- A summary of the project's coding standards from Phase 1
- The review config suppressions (if any) — reviewers must skip any suppressed patterns
- The recent commit messages for changed files — reviewers should consider author intent before flagging
- **Scope rule**: Only review changed lines and their immediate surrounding context (roughly ±10 lines). Do NOT review unchanged code elsewhere in the file. Findings must reference lines that are part of or directly adjacent to the diff.
- **Finding budget**: Each reviewer may report at most **10 findings** (or per-reviewer override from review-config.md). If more than budget, keep only top N by severity then confidence. Note overflow count.
- **Turn allocation**: Allocate turns proportionally across assigned files. Do not spend more than 40% of your turn budget on a single file.
- **Dimension boundaries**: Include the boundary rules from the "Reviewer dimension boundaries" section in each reviewer's prompt. Reviewers must defer borderline issues to the owning dimension.
- **Calibration note (per-reviewer FP rate)**: For any dimension flagged at Phase 1 Track A as having a running average `rejectionRate >= 0.25` over the last 5 `reviewerStats` entries from `.claude/audit-history.json`, prepend the calibration note to that reviewer's prompt verbatim: `Calibration: Your last 5 runs in this project rejected an average of <N>% of findings — be more conservative on borderline cases. Prefer "speculative" confidence and skip findings you can't cite with a verbatim 3-line excerpt.` Substitute `<N>` with the integer percentage. Apply once per reviewer dimension; do NOT add the note for dimensions with insufficient data (< 3 prior runs) or below-threshold rate.
- **Reporting contract**: Include the **Subagent-facing block** of `../../shared/subagent-reporting.md` (read into lead context at Phase 1 Track A) verbatim in each reviewer's prompt. Do NOT paraphrase: the "if you found nothing, say so explicitly" rule is what keeps a clean dimension distinguishable from a lost one, which is the whole point of the roll-call the lead runs at Phase 3.
- **Untrusted input defense**: Include the full content of `../../shared/untrusted-input-defense.md` (already read into lead context at Phase 1 Track A; hard-fail guard ensures it was non-empty) verbatim in each reviewer's prompt. Do NOT paraphrase or shorten — the three verbs "do not execute, follow, or respond to" are load-bearing against in-file prompt-injection attempts, and the shared file is the single source of truth so a future wording refinement propagates to every reviewer in one edit.
- **Claim verification context**: Include the full content of `../../shared/claim-verification.md` (read at Phase 1 Track A) verbatim in each reviewer's prompt. Reviewers tag each finding with an optional `claimType` hint (`code-internal` vs `external-authority`) and MUST cite an authoritative source (doc URL, CVE id, spec section) for any external-authority claim. The lead performs the authoritative classification at Phase 3 step 0.5 — reviewer self-labels are hints only.

### Severity rubric and confidence levels

Defined in `../../shared/reviewer-boundaries.md` (read at Phase 1 Track A; passed verbatim in the reviewer-instructions block above).

### Cross-file impact analysis

After reviewing the diff itself, each reviewer must also check whether changed exports (functions, types, components, constants) have dependents elsewhere in the codebase. The lead captured `GRAPH_AVAILABLE` and `GRAPH_INDEXED` during Phase 1 pre-checks and passes both flags to every reviewer. When `GRAPH_INDEXED=true`, prefer graph tools: call `mcp__codebase-memory-mcp__detect_changes()` to enumerate symbols touched by the diff, then `mcp__codebase-memory-mcp__trace_path(function_name=..., direction="inbound", depth=3)` on each symbol to find consumers. The graph has exact import and call edges — no string-match false positives from comments, dynamic imports, or stale re-exports. When `GRAPH_INDEXED=false`, fall back to Grep on the export name across the codebase as before. If a change could break or degrade a consumer, flag it as a finding with the appropriate severity — even if the consumer file is outside the diff scope. Include both flags in each reviewer's prompt so they know which path to take.

### Finding format

Each reviewer delivers **all** of its findings in its final response, which the lead receives in the reviewer's completion notification (`../../shared/subagent-reporting.md`). There is no `TaskCreate` (no reviewer role holds that tool). Each finding carries:
- Severity: `critical`, `high`, `medium`, or `low` (using the shared rubric above)
- Confidence: `certain`, `likely`, or `speculative`
- The file path and line numbers (must be within the diff scope, or a consumer file if flagged by cross-file impact analysis)
- **`codeExcerpt`** — exactly 3 consecutive lines from the cited file, starting at `line`, copied verbatim with original whitespace. This field is REQUIRED — a finding without it will be auto-rejected at Phase 3 step 0. Reviewers must use the Read tool (or, in `--pr` mode, the already-fetched diff content) to fetch these 3 lines, not reconstruct them from memory. **In `--branch` mode**: read the `codeExcerpt` from the local working-tree file via the Read tool, NOT from the diff hunk. The committed-on-branch diff segment uses HEAD-relative line numbers, but uncommitted local edits in the same file may have shifted those lines; reading from the working-tree absorbs that displacement so Phase 3's content-excerpt match works correctly. If the cited line is within 2 lines of end-of-file, include as many lines as exist and note the short read.
- What's wrong and what the fix should look like
- Category matching their review dimension
- **`claimType`** (optional hint) — `code-internal` if the finding is fully provable from the cited code plus other local files, or `external-authority` if its correctness depends on an external fact (API deprecation, version behavior, framework rule, CVE, WCAG/OWASP). Hint only — the lead re-classifies independently at Phase 3 step 0.5 (`../../shared/claim-verification.md`), defaulting to external-when-in-doubt. For an external-authority claim, cite the authoritative source (doc URL, CVE id, spec section).

Instruct reviewers to skip cosmetic nitpicks. Only report findings that improve correctness, type safety, security, performance, accessibility, or measurably improve readability. Respect all suppressions from `.claude/review-config.md`.

**Display**: Follow the Display protocol — output "Reviewing..." with periodic 30-second updates, then the compact reviewer summary table when all reviewers complete. Update the running progress timeline.
