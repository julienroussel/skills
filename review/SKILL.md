---
name: review
description: Multi-agent PR review swarm. Spawns specialized reviewers, deduplicates findings, gets approval, auto-fixes, and validates. Scales dynamically based on diff size.
argument-hint: "[nofix|full|quick|--refresh-stack|--refresh-baseline|--only=dims|--scope=path|--pr=N] [max-retries]"
effort: high
disable-model-invocation: true
user-invocable: true
---

<!-- Dependencies:
  Required plugins:
    - agent-teams@claude-code-workflows        — team-reviewer agents (Phase 2), team-implementer agents (Phase 5), TeamCreate/TeamDelete (Phase 2/7)
  Enhanced by plugins (integrated methodologies):
    - pr-review-toolkit@claude-plugins-official — pr-test-analyzer → testing-reviewer, code-simplifier → Phase 5.5, silent-failure-hunter → error-handling
  Required CLI:
    - git                                       — diff, status, log (Phase 1), diff --stat (Phase 7)
    - gh                                        — pr diff, pr view, pr comment (--pr mode); issue list, issue create (Phase 8)
  Cache files written:
    - .claude/review-profile.json               — stack detection cache (Track C)
    - .claude/review-baseline.json              — validation baseline cache (Track D)
    - .claude/review-config.md                  — auto-learned suppressions (Phase 4.5)
  Required tools:
    - Agent, TaskCreate, TaskList, TeamCreate, TeamDelete, SendMessage, AskUserQuestion
    - Bash, Read, Write, Glob, Grep
-->

Review the current changes as if you were doing a PR review.

**Arguments**: $ARGUMENTS

Parse arguments as space-separated tokens. Recognized flags:
- `nofix` — Findings-only mode. Skip Phase 5 (implementation) and Phase 6 (validation). Just report findings and stop.
- `full` — Force the full swarm even for small diffs.
- `quick` — Force lightweight mode (max 2 reviewers) even for large diffs. Also skips Track D baseline and outputs compact report.
- `--refresh-stack` — Force re-detection of package manager, validation commands, and stack info. Use after changing package.json scripts or switching package managers.
- `--refresh-baseline` — Force re-run of validation baseline even if a cached baseline exists within TTL.
- `--only=<dimensions>` — Run only the specified reviewer dimensions (comma-separated). All others are skipped. Example: `--only=security`, `--only=typescript,testing`.
- `--scope=<path>` — Limit review to files under this path prefix. Example: `--scope=src/api/`.
- `--pr=<number>` — Review a remote PR instead of working-tree changes. Fetches the PR diff via `gh`, forces `nofix` mode (can't edit remote files). Phase 8 comments on the PR instead of creating standalone issues.
- Any number (e.g., `3`) — Max validation retries (default: 3).

Examples: `/review`, `/review nofix`, `/review quick`, `/review full 5`, `/review nofix quick`, `/review --refresh-stack`, `/review --only=security`, `/review --scope=src/api/`, `/review --pr=123`, `/review --pr=456 --only=security`, `/review --scope=src/api/ --only=typescript,node`

### Flag conflicts

- `full` + `quick` — `quick` wins (it's the explicit override for speed). Ignore `full`.
- `--refresh-baseline` + (`quick` | `nofix` | `--pr`) — Track D is skipped in these modes, so `--refresh-baseline` is silently ignored.
- `--pr` implies `nofix` — do not warn, just apply.

## Model requirements

- **Reviewer agents** (Phase 2) and **implementer agents** (Phase 5): Spawn with `model: "opus"`. Include in each agent's prompt: "Analyze deeply and consider edge cases before reporting. Accuracy matters more than speed."
- **Simplification agent** (Phase 5.5): Spawn with `model: "opus"` — it modifies code and needs the same quality bar as implementers.
- **All other phases** (context gathering, dedup, validation, cleanup): Default model is fine — these are mechanical steps.

## Display protocol

All console output from the review must follow these rules to keep the swarm readable.

**Every phase**: Record the start time and output the phase header before doing anything else.

### Phase headers

Use prominent visual separators between phases:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE 3 — Deduplicate & Prioritize
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Sub-phases (4.5) use a lighter separator: `── Phase 4.5 — Auto-learn from rejections ──`

### Running progress timeline

After each phase completes, output a single-line cumulative timeline:

```
Phase 1 ✓ (3s)  →  Phase 2 ✓ (28s)  →  Phase 3 (running...)   Total: 31s
```

### Silent reviewers, noisy lead

**Reviewer and implementer agents must not output progress text.** They create finding tasks silently via TaskCreate and report completion via SendMessage. Only the **lead agent** outputs progress to the user.

Instruct every reviewer: "Do not output progress messages. Report findings only via TaskCreate. Your console output is not visible to the user."

### Compact reviewer progress table (Phase 2)

After all reviewers finish, output a single summary table instead of per-reviewer messages:

```
Phase 2 complete — 4 reviewers finished in 18s, 12 raw findings

  Reviewer            Findings  Turns  Status
  ─────────────────────────────────────────────
  typescript              5      12/15  ✓
  node-api                3       8/15  ✓
  security                2       9/15  ✓
  testing                 2       7/15  ✓
```

Use `✓` for completed, `⏱` for timed out (hit max_turns without finishing all files). Timed-out reviewer findings are still included — they just didn't cover every file. While reviewers are running, output at most one interim update per 30 seconds: `Phase 2 — Reviewing... 2/4 complete, ~7 findings so far (12s)`

### Findings approval display (Phase 4)

**Always show all findings with full details** before asking for approval. For each finding, display:
- Severity and confidence (e.g., `critical / certain`)
- File path and line numbers
- What's wrong and what the fix should look like
- Reviewer dimension (e.g., `typescript`, `security`)

Group findings by confidence tier (certain → likely → speculative), and within each tier sort by severity.

Then present AskUserQuestion **as a menu** (never a free-text prompt) with these options:
- **Approve all** — approve every finding
- **Approve critical/high, review rest** — auto-approve findings that are both certain-confidence AND critical-or-high-severity, then present all remaining findings individually
- **Review individually** — present each finding one by one via AskUserQuestion menus (approve / reject per finding)
- **Abort** — cancel the review

### Phase 5/6 compact display

For implementers:
```
Phase 5 — 3 implementers dispatched (strict file ownership)
Phase 5 complete — 12/13 findings addressed, 1 contested (19s)
```

For validation:
```
Phase 6 — Validating...
  lint:      ✓ pass (0 new issues)
  typecheck: ✓ pass (0 new errors)
  test:      ✓ pass (42/42)
```

## Phase 1 — Gather context and detect stack

### Pre-checks

Verify `git --version` succeeds. If `--pr` is set, also verify `gh auth status`. If either fails, warn the user and abort.

### PR mode (if `--pr=<number>` is set)

When reviewing a remote PR, replace Tracks B and D:
- **Track B (PR)**: Run in parallel: `gh pr diff <number> --no-color` (get the diff), `gh pr view <number> --json title,body,commits,files` (PR metadata and context). Use the PR diff as the change set. Force `nofix` mode (can't edit remote files). Skip Track D entirely.
- **Still apply safety checks to the PR diff**: diff size guard (step 6), secret pre-scan (step 7), and scope filter (step 4) from normal Track B apply to the PR diff too.
- **Cross-file impact caveat**: Reviewers Grep the local codebase for consumers of changed exports, but the local checkout may differ from the PR's target branch. Note this limitation in the report if the local branch doesn't match the PR base.
- Tracks A and C proceed as normal (project standards and stack info still apply for reviewer selection).

### Normal mode (no `--pr`)

Maximize parallelism — run all tracks simultaneously using parallel tool calls.

### Track A — Read configuration (parallel with Tracks B and C)

Read **all of the following files in parallel** using multiple Read tool calls in a single message:
- `CLAUDE.md`, `AGENTS.md`, `.claude/CLAUDE.md` (project standards, if they exist)
- `.claude/review-config.md` (suppressions, tuning, overrides from past reviews)

These rules override generic best practices. If a pattern is suppressed, no reviewer should flag it.

### Track B — Collect diff and git context (parallel with Tracks A and C)

Run **all of the following git commands in parallel** using multiple Bash tool calls in a single message:
- `git diff --no-color` (unstaged changes). If `--scope` is set, append `-- <path>` to scope at the git level.
- `git diff --cached --no-color` (staged changes). If `--scope` is set, append `-- <path>`.
- `git status` (untracked files)
- `git log --format="%h %s" -10` (recent commit context — subject lines only)

After the above complete:
1. **Staged secret file check**: If any staged/untracked files match `.env*`, `*.pem`, `*.key`, `credentials*`, `*secret*`, warn: "Sensitive files are staged: [list]. Consider unstaging before review."
2. **Merge conflict check**: If the diff contains `<<<<<<<` or `>>>>>>>` markers, abort with: "Merge conflicts detected. Resolve conflicts before running /review."
3. **Empty diff check**: If the combined diff (staged + unstaged + untracked) is empty, stop with: "Nothing to review — no changes detected."
4. **Scope filter**: If `--scope=<path>` is set, filter untracked files to only include those under the path prefix (the diff was already scoped at the git level above).
5. Read any untracked files in full.
6. **Diff size guard**: Count total changed lines. If exceeding **3,000 lines**, warn via AskUserQuestion: "This diff is large (N lines). Options: [Continue] / [Use quick mode] / [Scope to path] / [Abort]". If exceeding **8,000 lines**, strongly recommend splitting.
7. **Secret pre-scan**: Grep the diff AND untracked file contents for common secret patterns: `(AKIA[0-9A-Z]{16}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|gho_|github_pat_|xox[bpas]-[a-zA-Z0-9-]+|-----BEGIN .* PRIVATE KEY|SG\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+|AIza[0-9A-Za-z_-]{35})`, connection strings `(mongodb\+srv://|postgres://|mysql://)[^\s]*@`, and lines with `(password|secret|token|api_key)\s*[:=]\s*["'][^"']{8,}`. If matches found, warn via AskUserQuestion BEFORE spawning reviewers: "Potential secrets detected in diff: [list]. Options: [Continue anyway] / [Abort and unstage]".

### Track C — Detect stack and validation (parallel with Tracks A and B)

**Stack profile cache**: Check `.claude/review-profile.json` to avoid re-detecting unchanged stack info.

1. Read `.claude/review-profile.json` (if it exists) **and** run `stat -f %m package.json tsconfig.json Makefile 2>/dev/null` — both in parallel.

2. **If the profile exists AND `--refresh-stack` was NOT passed:**
   Compare the current modification timestamps of `package.json`, `tsconfig.json`, and `Makefile` against the cached `sourceTimestamps`. If all match (and files that were absent are still absent), the cache is valid:
   - Use cached `packageManager`, `lockFile`, and `validationCommands` directly.
   - Output: `Stack: cached (${packageManager}, ${Object.keys(validationCommands).join('+')})`
   - Skip to Track D with cached validation commands.

3. **If the profile is missing, timestamps differ, or `--refresh-stack` was passed** — run full detection:
   - Read `package.json` in parallel with checking for lock files (`bun.lockb`, `pnpm-lock.yaml`, `yarn.lock`) and reading `tsconfig.json`, `Makefile`, `docker-compose.yml`.
   - Detect **validation commands** from `package.json` scripts: look for `lint`, `typecheck`/`type-check`/`tsc`, `test`, `validate`. Build a list using the detected package manager. If a `Makefile` has matching targets, use those. If no commands found, skip validation phases.
   - **Write cache**: Save results to `.claude/review-profile.json`:
     ```json
     {
       "version": 1,
       "generatedAt": "<ISO timestamp>",
       "sourceTimestamps": {
         "package.json": <mtime or null>,
         "tsconfig.json": <mtime or null>,
         "Makefile": <mtime or null>
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
   - Output: `Stack: detected (${packageManager}, ${Object.keys(validationCommands).join('+')}) — cached for next run`

### Track D — Establish validation baseline (skip if `nofix`, `quick`, or PR mode)

**Baseline cache**: Check `.claude/review-baseline.json` to avoid re-running slow validation commands on rapid back-to-back reviews.

1. Read `.claude/review-baseline.json` (if it exists).
2. **If the cache exists, is within TTL (default 10 minutes), AND `--refresh-baseline` was NOT passed**: Use cached baseline results. Output: `Baseline: cached (${age}m old, TTL ${ttl}m)`. Skip running validation commands.
3. **Otherwise**: Run **all detected validation commands in parallel** (lint, typecheck, test as separate simultaneous Bash calls in a single message). Store outputs as the baseline. Write results to `.claude/review-baseline.json`:
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
   Output: `Baseline: fresh (lint+typecheck+test) — cached for 10m`

Invalidate the baseline cache automatically whenever `.claude/review-profile.json` is invalidated (stack change implies baseline change). Pre-existing failures are NOT the review's responsibility — only new regressions introduced by fixes count.

### After all tracks complete

Store the list of changed files, project standards, review config rules, commit context, stack info, and validation commands.

**Build file→dimension mapping**: Classify each changed file into one or more reviewer dimensions (typescript, react, node, database, performance, testing, accessibility, infra, error-handling). This mapping drives: (1) which reviewers to spawn, (2) which files each reviewer receives. If `--only` is set AND `--scope` is set, verify the intersection is non-empty — if no files match the requested dimensions within the scope, stop with: "No files match --only=${dims} within --scope=${path}. Nothing to review."

## Phase 2 — Spawn reviewers (dynamically scaled)


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
- **node-reviewer** — If server-side files changed (API routes, middleware, controllers, services, server entry points). API design conventions (REST/GraphQL), error handling patterns, middleware ordering, input validation, async error propagation, logging, environment config.
- **database-reviewer** — If ORM models, migration files, query builders, or files with SQL/database operations changed. N+1 queries, missing indexes, transaction boundaries, connection pooling, migration safety (e.g., locking tables in production), data validation at the persistence layer.
- **performance-reviewer** — If 5+ files changed or performance-sensitive code is touched (rendering logic, data fetching, loops, caching). Unnecessary re-renders, missing memoization, bundle size impact, lazy loading, network waterfalls, algorithm complexity, caching opportunities.
- **testing-reviewer** — If test files changed, or if new code was added without corresponding tests. Behavioral coverage over line coverage: identify critical untested paths (error paths, edge cases, business logic, negative tests), evaluate test quality (tests behavior not implementation, resilient to refactoring, DAMP principles), check for implementation coupling (mocks that mirror implementation details), rate gap criticality (1-10 scale: 9-10 critical, 7-8 important, 5-6 edge cases, 3-4 nice-to-have). No `.only`/`.skip` in committed code.
- **accessibility-reviewer** — If UI component files (`.tsx`/`.jsx`/`.vue`/`.svelte`) changed. Semantic HTML, ARIA attributes, keyboard navigation, screen reader compatibility, color contrast, focus management, WCAG 2.2 compliance.
- **infra-reviewer** — If `Dockerfile`, `docker-compose.yml`, CI/CD configs (`.github/workflows/`, `.gitlab-ci.yml`), or deployment/config files changed. Build efficiency, security best practices (multi-stage builds, non-root users), environment variable handling, caching strategies, dependency pinning.
- **error-handling-reviewer** — If runtime application code changed. Silent failure hunting: empty/broad catch blocks, swallowed exceptions, fallbacks that mask errors, optional chaining hiding failures, missing user feedback on errors, catch blocks that log but don't propagate, error messages that leak internals or are too generic. For each issue: identify hidden errors, assess user impact, check logging quality, verify catch block specificity. Zero tolerance for silent failures.

**`--only` filter**: If set, takes precedence. Only spawn the named reviewers regardless of diff size or file classification. Use short dimension names without the `-reviewer` suffix: `security`, `typescript`, `react`, `node`, `database`, `performance`, `testing`, `accessibility`, `infra`, `error-handling`.

### Reviewer dimension boundaries

To minimize duplicate findings, each reviewer owns a **primary responsibility** and defers borderline issues:

- Missing error boundary: `error-handling-reviewer` (not react or performance)
- `any` enabling injection: `typescript-reviewer` (not security)
- Missing `key` prop: `react-reviewer` (not performance)
- Inline function causing re-render: `performance-reviewer` (not react)
- Missing `useMemo`/`useCallback`: `performance-reviewer` (not react)
- Unhandled promise rejection: `error-handling-reviewer` (not typescript or security)
- Silent failure (empty catch): `error-handling-reviewer` (not security or typescript)

Exception: any reviewer may report a **critical** finding regardless of boundaries.

### Scale the swarm

- **Small diff**: Pick the **top 2 most relevant** dimensions. Do NOT create a team — use the Agent tool directly with `subagent_type: "agent-teams:team-reviewer"` for each. Set `max_turns: 10`.
- **Medium diff**: Pick the **top 3–4 most relevant** dimensions. Create a team with TeamCreate (name: `review-swarm`). Set `max_turns: 15`.
- **Large diff**: Spawn **all relevant dimensions** (up to 6 max). Create a team with TeamCreate (name: `review-swarm`). Set `max_turns: 20`.

"Most relevant" is determined by: (1) how many changed files fall in that dimension, (2) always prioritize `security-reviewer` and `typescript-reviewer`.

### Reviewer instructions

Each agent receives:
- **Only the files and diff hunks relevant to their dimension** (use the file→dimension mapping from Phase 1). Do NOT pass the full diff to every reviewer.
- A summary of the project's coding standards from Phase 1
- The review config suppressions (if any) — reviewers must skip any suppressed patterns
- The recent commit messages for changed files — reviewers should consider author intent before flagging
- **Scope rule**: Only review changed lines and their immediate surrounding context (roughly ±10 lines). Do NOT review unchanged code elsewhere in the file. Findings must reference lines that are part of or directly adjacent to the diff.
- **Finding budget**: Each reviewer may report at most **10 findings** (or per-reviewer override from review-config.md). If more than budget, keep only top N by severity then confidence. Note overflow count.
- **Turn allocation**: Allocate turns proportionally across assigned files. If you have 15 turns and 5 files, spend roughly 3 turns per file. Do not spend more than 40% of your turn budget on a single file.
- **Dimension boundaries**: Include the boundary rules from the "Reviewer dimension boundaries" section in each reviewer's prompt. Reviewers must defer borderline issues to the owning dimension.

### Severity calibration rubric

All reviewers must use this shared rubric to ensure consistent severity ratings:

- **critical** — Will cause bugs, data loss, security vulnerabilities, or crashes in production. Examples: SQL injection, unhandled null dereference on a required path, missing auth check on a protected route, infinite re-render loop, unsafe migration that locks a production table.
- **high** — Likely to cause issues under normal usage or significantly degrades code quality. Examples: missing error boundary around async operation, `any` type that defeats downstream type checking, missing key prop in a mapped list, N+1 query in a list endpoint, unvalidated user input passed to a database query.
- **medium** — Won't break anything but misses an opportunity for meaningful improvement. Examples: missing `useMemo` on an expensive computation, `as` cast that could be replaced with type narrowing, missing test for a new edge case, missing index on a frequently queried column.
- **low** — Minor improvement, borderline nitpick. Examples: slightly better variable name, optional chaining that could replace a ternary, test description could be more specific. *These are dropped unless trivially fixable.*

### Confidence levels

Every finding must include a confidence level alongside its severity:

- **certain** — The reviewer is sure this is a real issue. The code is demonstrably wrong, violates a documented standard, or will break at runtime.
- **likely** — The reviewer is fairly confident but the issue depends on context they can't fully verify.
- **speculative** — The reviewer suspects an issue but isn't sure. Requires human judgment.

### Cross-file impact analysis

After reviewing the diff itself, each reviewer must also check whether changed exports (functions, types, components, constants) have dependents elsewhere in the codebase. Use Grep to search for imports of any modified export. If a change could break or degrade a consumer, flag it as a finding with the appropriate severity — even if the consumer file is outside the diff scope.

### Finding format

Each reviewer must report findings as tasks (using TaskCreate) with:
- Severity: `critical`, `high`, `medium`, or `low` (using the shared rubric above)
- Confidence: `certain`, `likely`, or `speculative`
- The file path and line numbers (must be within the diff scope, or a consumer file if flagged by cross-file impact analysis)
- What's wrong and what the fix should look like
- Category matching their review dimension

Instruct reviewers to skip cosmetic nitpicks. Only report findings that improve correctness, type safety, security, performance, accessibility, or measurably improve readability. Respect all suppressions from `.claude/review-config.md`.

**Display**: Follow the Display protocol — output "Reviewing..." with periodic 30-second updates, then the compact reviewer summary table when all reviewers complete. Update the running progress timeline.

## Phase 3 — Deduplicate and prioritize


After all reviewers complete (or hit their turn budget), read the full task list (TaskList). As the lead:

1. **Deduplicate**: If multiple reviewers flagged the same code location, merge into one task and keep the most actionable description. Use the highest confidence level among the merged findings. **Exception**: if merged findings have contradictory suggested fixes (e.g., "add type assertion" vs "remove type assertion"), keep both as separate findings and flag the conflict for the user in Phase 4.
2. **Drop low-value items**: Delete tasks with severity `low` unless they are trivially fixable.
3. **Prioritize**: Reorder by severity first, then by confidence within the same severity level — `certain` before `likely` before `speculative`.
4. **Assign file ownership**: Group tasks by file. Each file should be owned by at most one implementer agent to prevent conflicts.
5. **Verify reviewer coverage**: For each reviewer, check that findings or explicit "no issues" notes exist for all files in their scope. If a reviewer missed files (no findings AND no explicit clearance), note the gap in the Phase 7 report.

**Display**: Output a compact dedup summary: `18 raw → 12 deduplicated (4 merged, 2 dropped)`. Update the running progress timeline.

**Zero findings**: If no findings remain after dedup, skip Phases 4-6 and 8. Output: "Clean review — no findings. All changed code looks good." Proceed directly to Phase 7 for cleanup and a compact report.

## Phase 4 — User approval gate


**Display**: Show the finding count header first: `Phase 4 — N findings for approval`. Then show all findings with full details (severity, confidence, file, line numbers, description, suggested fix, reviewer dimension) grouped by confidence tier and sorted by severity.

Then use AskUserQuestion **as a menu** (always provide selectable options, never ask the user to type free text) with:
- **Approve all** — approve every finding
- **Approve critical/high, review rest** — auto-approve findings that are both certain-confidence AND critical-or-high-severity, then present all remaining findings individually
- **Review individually** — present each finding one by one via AskUserQuestion menus (approve / reject per finding)
- **Abort** — cancel the review without making changes

If the user aborts, skip to Phase 7 (cleanup). Otherwise, delete any tasks the user rejected and proceed.

**If `nofix` flag is set**: After approval/review, skip directly to Phase 7 — do not implement or validate. The approved findings serve as the review output.

## Phase 4.5 — Auto-learn from rejections

If the user rejected any tasks, analyze the rejected findings for patterns and automatically append learned suppressions to `.claude/review-config.md`. Create the file if it doesn't exist.

Rules for auto-learning:
- Only add a suppression if **2 or more rejected findings share the same pattern** (same reviewer dimension + same type of issue) within this review OR across recent reviews. Check existing entries in `## Auto-learned suppressions` — if a pattern was rejected once before and once now, that counts as 2. A single rejection might be situational — a repeated rejection is a preference.
- Write each suppression as a clear, scoped rule. Include the reviewer dimension and the specific pattern. Example: `- [react-reviewer] Do not suggest extracting sub-components for components under 100 lines`
- Append under a `## Auto-learned suppressions` section, with a date stamp for each entry.
- Never overwrite or remove existing rules in the file — only append.

If no patterns are detected in the rejections (all were one-offs), skip this step.

**Note**: If an auto-learned suppression is wrong, the user can manually edit `.claude/review-config.md` to remove it. The skill will never auto-remove suppressions — only append.

## Phase 5 — Spawn implementer swarm

**Skip this phase entirely if `nofix` flag is set.**


Spawn **all implementer agents in parallel** using multiple Agent tool calls in a single message. Use `subagent_type: "agent-teams:team-implementer"`. If a team was created in Phase 2 (medium/large diffs), set `team_name: "review-swarm"`. For small diffs (no team), omit `team_name` and use the Agent tool directly. Each implementer receives:

- A set of user-approved tasks scoped to specific files (strict file ownership — no two implementers touch the same file), including each finding's confidence level
- The original diff context for those files
- The project coding standards summary
- Clear instructions on what to fix. For `speculative` findings, instruct the implementer to verify the issue exists in context before applying a fix — skip if the finding turns out to be a false positive.

The number of implementers depends on how many independent file groups exist. Aim for 2–4 implementers max to keep coordination manageable. **All implementers must be spawned in a single message** so they run concurrently.

An implementer may mark a finding as **contested** if the fix would introduce worse problems, the finding is incorrect given the full file context, or the fix conflicts with another finding. Contested findings are reported back to the lead and included in the Phase 7 report — they are NOT retried.

**Display**: Follow the Display protocol — show compact implementer summary: `N implementers dispatched → M/N findings addressed (Xs)`. Update the running progress timeline.

## Phase 5.5 — Simplification pass

**Skip if `nofix` or `quick` is set, or if fewer than 3 findings were implemented.**

Spawn a **single Agent** using the Agent tool directly (not via TeamCreate — this agent is independent of the `review-swarm` team). Pass it the list of files modified by Phase 5 implementers. The agent reviews the modified files for post-fix simplification opportunities:
- Reduce unnecessary complexity/nesting introduced by fixes
- Eliminate redundancy between fix code and existing code
- Improve naming clarity where fixes introduced new variables/functions
- Replace nested ternaries with switch/if-else if introduced
- Ensure fixes follow project standards (ES modules, function keyword, explicit types)

This is a lightweight pass — only flag changes that are clear wins. Do NOT re-review unchanged code. Apply simplifications directly (no separate approval gate). If no improvements found, skip silently.

**Display**: `Phase 5.5 — Simplification: N improvements applied` (or skip line if none)

## Phase 6 — Validate-fix loop

**Skip this phase entirely if `nofix` flag is set.**

### Post-implementation formatting

If the project has a formatter configured (detected from review-profile: `format` command), run it on modified files **first** before validation to prevent lint failures caused by formatting drift.

### Validation

Run **all detected validation commands in parallel** (lint, typecheck, test as separate simultaneous Bash calls in a single message). In `quick` mode (no baseline was collected), just check pass/fail — no baseline comparison. Otherwise, compare against the **Phase 1 baseline** — only new failures count as regressions.

- **No new failures**: Move to Phase 7.
- **New failures found**: Analyze and fix regressions (dispatch **multiple implementer agents in parallel** if fixes span multiple files — pass them the project coding standards so fixes don't introduce new violations), then re-validate with all commands in parallel again. Repeat up to the max retry count (default 3). Do NOT re-review — only fix what the validation tools report as new regressions.
- **Max retries exhausted**: Move to Phase 7 and report the remaining failures.

After a successful validation (no new regressions), update `.claude/review-baseline.json` with the post-fix results so the next review has an accurate baseline.

**Display**: Show compact validation summary as defined in the Display protocol. Show each validation command result separately. Update the running progress timeline.

## Phase 7 — Cleanup and report


1. If a team was created, send **all shutdown requests in parallel** (multiple SendMessage calls with `type: "shutdown_request"` in a single message). Wait up to 30 seconds for confirmations — proceed with TeamDelete even if some agents don't respond. (Skip if no team was created for small diffs.)
2. If fixes were applied (not `nofix` mode), run `git diff --stat` to show a summary of all files the review swarm touched.

**Display**: Output the final progress timeline with all phases and total duration. Only include phases that were actually executed:
```
Full:  Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → Phase 3 ✓ (2s) → Phase 4 ✓ (5s) → Phase 5 ✓ (19s) → Phase 6 ✓ (8s) → Phase 7 ✓ (2s) → Phase 8 ✓ (5s)  Total: 62s
Quick: Phase 1 ✓ (2s) → Phase 2 ✓ (12s) → Phase 3 ✓ (1s) → Phase 4 ✓ (3s) → Phase 7 ✓ (1s)  Total: 19s
Clean: Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → Phase 3 ✓ (1s) → Phase 7 ✓ (1s)  Total: 23s
```

**Compact report** (for `quick` or `nofix` mode): Output only Mode, Reviewed (files + reviewers), Findings (summary table), User decisions. Skip Cross-file impacts, Coverage gaps, Auto-learned, Fixed, Contested, Validation, Diff summary, Skipped, and Remaining failures sections.

**Full report** (default): Summarize:

1. **Mode**: Which mode was used (small/medium/large, nofix/quick/full/PR if flags set)
2. **Stack detected**: Package manager, validation commands found, key frameworks identified
3. **Reviewed**: Number of files examined, list of reviewer agents and their dimension (only the ones that were spawned)
4. **Findings**: Total findings per reviewer, breakdown by severity and confidence, number deduplicated/dropped
5. **Cross-file impacts**: Any consumer breakage detected outside the direct diff
6. **Coverage gaps**: Files that reviewers failed to examine (from Phase 3 coverage check)
7. **User decisions**: Number of tasks approved, rejected, aborted
8. **Auto-learned**: Any new suppressions added to `.claude/review-config.md` (or "none" if no patterns detected)
9. **Fixed**: List of improvements applied, grouped by category (or "N/A — findings-only mode" if `nofix`)
10. **Contested**: Findings that implementers flagged as contested, with their reasoning
11. **Validation**: Final pass/fail status per command, baseline vs post-fix comparison, number of validate-fix iterations needed (or "N/A" if `nofix` or no validation commands detected)
12. **Diff summary**: Output of `git diff --stat` showing exactly what changed (or "N/A" if `nofix`)
13. **Skipped**: Any findings intentionally left unchanged, with reasoning
14. **Remaining failures** (if any): Unresolved validation regressions after max retries

Only include sections that have non-empty content. Skip sections that would just say "none" or "N/A".

## Phase 8 — Follow-up issue tracking

**Skip if `quick` is set. Skip if `nofix` is set AND `--pr` is NOT set** — in nofix-without-PR mode, the user chose findings-only and doesn't want follow-up issues. But in PR mode, Phase 8 posts findings as a PR comment, which is the primary output.

**Run this phase if**: (1) `--pr` mode is active (always — to comment findings on the PR), OR (2) there are findings that were user-approved but intentionally NOT implemented (architectural issues too large for auto-fix, contested findings). User-rejected findings are NOT candidates.

### Step 1: Fetch existing issues

Run `gh issue list --state open --json number,title,state,labels --limit 200` to get all open issues (not just `review-followup` — the user may have relabeled follow-up issues manually).

### Step 2: Deduplicate against existing issues

For each skipped finding, check if **any open issue** already covers it — regardless of its labels. Match by semantic similarity of titles and descriptions — a finding is already tracked if an open issue addresses the same root cause, even if worded differently.

### Step 3: Identify candidates for new issues

From the skipped findings, keep only those that:
1. Are **not already tracked** by any existing open issue
2. Have severity **medium or higher**
3. Are **actionable** — there is a concrete fix or investigation path (not just an observation)

If no candidates remain, output `No new follow-up issues needed — all skipped findings are already tracked or too low priority.` and skip to the end.

### Step 4: Present candidates to user

Show each candidate with a one-line summary, then use AskUserQuestion as a menu:

- **Create all** — create GitHub issues for all candidates
- **Review individually** — present each candidate one by one via AskUserQuestion menus (create / skip per candidate)
- **Skip all** — do not create any issues

### Step 5: Create approved issues

For each approved candidate:

**In PR mode** (`--pr`): Use `gh pr comment <number>` to post a **single consolidated comment** on the PR with all findings formatted as a checklist. Do not create one comment per finding.

**In normal mode**: Run `gh issue create --label review-followup` with:
- A concise title describing the problem and desired outcome
- A body containing: Context (which review, date), Problem description, Affected files, Suggested fix, and Priority
- **Sanitize the body**: Before creating, redact any strings matching secret patterns (API keys, tokens, connection strings, passwords). Replace with `[REDACTED]`.

**Display**: Output a compact summary:
```
Phase 8 — Follow-up issues
  Existing:  4 open issues checked
  Skipped:   11 findings checked
  Duplicates: 9 already tracked
  Created:   2 new issues (#46, #47)
```
