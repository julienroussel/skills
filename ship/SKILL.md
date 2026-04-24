---
name: ship
description: Ship working-tree changes via PR. Analyzes changes for coherent splitting into sub-PRs. Handles branching, CI wait, squash-merge, and cleanup.
argument-hint: "[message] [--draft|--base|--no-split|--no-merge|--dry-run|--split-only|--validate|--label]"
effort: high
model: opus
disable-model-invocation: true
user-invocable: true
---

<!-- Dependencies:
  Required plugins:
    - (none — this skill uses CLI tools directly, no subagent types)
  Required CLI:
    - git                                       — status, diff, checkout, commit, push, branch, branch -D, rev-parse
    - gh                                        — repo view (default branch), pr create, pr view, pr checks, pr merge, pr edit (merge requirements, CI wait, stacked PR retargeting)
  Optional:
    - github@claude-plugins-official            — GitHub MCP for authenticated API access (not strictly required if gh CLI is authenticated)
    - codebase-memory-mcp (MCP)                 — detect_changes + trace_path used in Phase 2 step 3 (group-dependency detection) when the repo is indexed. Import-parse heuristic fallback when unavailable.
    - .claude/review-profile.json               — reuses stack cache from /review for --validate flag
  Required tools:
    - Bash, Read, Write, Glob, AskUserQuestion, Agent (split analysis only), advisor (pre-merge + pre-split-commit sanity checks)
-->

## Ship Changes via PR

Ship the current working-tree changes through one or more pull requests and merge once CI passes. Automatically analyzes changes for coherent splitting opportunities.

**Arguments**: $ARGUMENTS

Parse arguments as space-separated tokens. Recognized flags:

- `--draft`: Create the PR(s) as drafts and skip the CI wait and merge steps.
- `--base <branch>`: Target a branch other than the repo's default branch. If omitted, auto-detect via `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` (fallback to `main`).
- `--dry-run`: Perform split analysis and show the full plan (branch names, PR titles, file groups, commands) but execute nothing. Useful for previewing what `/ship` would do.
- `--no-split`: Skip the split analysis entirely and ship everything as a single PR.
- `--split-only`: Create sub-PRs but do not wait for CI or merge.
- `--no-merge`: Create the PR(s) but skip CI wait and merge.
- `--validate`: Run lint/typecheck/test before creating the PR. If any fail, stop and report. Use detected validation commands from `.claude/review-profile.json` if available.
- `--label <labels>`: Add comma-separated labels to all created PRs. Example: `--label feature,auth`.
- Any remaining text is used as the commit message / PR title.

Examples: `/ship`, `/ship --draft`, `/ship fix login bug --no-split`, `/ship --base develop --split-only`, `/ship --validate`, `/ship --label feature,v2`

### Flag conflicts

- `--no-split` + `--split-only` — `--no-split` wins. Ignore `--split-only`.
- `--draft` + `--no-merge` — compatible. PR is created as draft, no CI wait or merge.
- `--draft` + `--split-only` — compatible. PRs are created as drafts, no CI wait or merge.
- `--dry-run` overrides everything — nothing is executed regardless of other flags.

### Philosophy

Default to splitting when changes span distinct concerns. A coherent change should stay together — split only when groups make sense in isolation. See Phase 2 step 2 for the specific heuristics.

### Model requirements

- **Split analysis** (Phase 2 — steps 2–5): If delegating to a sub-agent, spawn with `model: "opus"`. Include in the prompt: "Analyze file relationships and dependencies deeply before classifying groups."
- **All other phases**: Default model is fine — these are mechanical git/gh operations.

### Display protocol

Use phase headers consistent with `/review` and `/audit`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE 1 — Pre-flight
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

After each phase completes, output a running timeline: `Phase 1 ✓ (2s) → Phase 2 ✓ (5s) → Phase 3a (running...)  Total: 7s`

#### Phase 1: Pre-flight

Run **all of the following in parallel**:

- `git status`
- `git diff --no-color` (full diff — needed for split analysis, secret scanning, and issue reference detection)
- `git diff --cached --no-color` (staged changes)
- `git rev-parse --abbrev-ref HEAD` (current branch)
- `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` (default branch, unless `--base` is set)
- Read `.github/PULL_REQUEST_TEMPLATE.md` (if it exists — cache for PR creation later)
- `cat "$(git rev-parse --git-dir)/info/scratch-session" 2>/dev/null` (scratch-session marker from `tackle --scratch`)
- `git rev-parse --show-toplevel` (current worktree path)
- `git rev-parse --git-dir` and `git rev-parse --git-common-dir` (for primary-vs-secondary detection)
- `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'` (primary worktree path — first entry)

After detecting the base branch (step 4), also run `git rev-list --count <base>..HEAD` to count commits ahead (needed for step 2).

After the above complete:

1. **Detect base branch**: Use `--base` value if provided, otherwise use the auto-detected default branch. Store for all subsequent steps.

1a. **Detect scratch session**: If the scratch-session marker read above is non-empty, store `IS_SCRATCH=true` and `SCRATCH_ID=<marker contents>`. Verify `SCRATCH_ID` equals the current branch (from the `rev-parse --abbrev-ref HEAD` above). On mismatch, log a warning ("stale scratch marker") and treat as non-scratch. Otherwise set `IS_SCRATCH=false`.

1b. **Detect worktree context** (used by step 15 / step 12-multi for worktree-aware cleanup):

- `CURRENT_WORKTREE` = output of `git rev-parse --show-toplevel`
- `IS_SECONDARY` = `true` iff `git rev-parse --git-dir` != `git rev-parse --git-common-dir`
- `PRIMARY_WORKTREE` = first `worktree` path from `git worktree list --porcelain`
- `IS_TACKLE_WORKTREE` = `true` iff `CURRENT_WORKTREE` contains the path segment `/.claude/worktrees/` (tackle-managed temporary worktree)

2. **Empty check**: If there are no staged or unstaged changes and no untracked files, stop with "Nothing to ship."
3. **Branch ancestry check**: If the current branch is NOT the base branch AND has commits ahead of the base branch (from `git rev-list`), warn via AskUserQuestion: "You are on branch '${branch}' which is ${N} commits ahead of '${base}'. Shipping from here will include all those commits in the PR. Options: [Continue — include all commits] / [Ship only uncommitted changes] / [Abort]".
   - If the user chooses **Ship only uncommitted changes**: Run `git stash --include-untracked`, `git checkout <base-branch>`, `git stash pop`. If stash pop has conflicts, abort with: "Could not cleanly apply your changes to ${base}. Resolve manually." Continue the flow from the base branch.
4. **Secret content scan**: Grep the diff for secret patterns (same patterns as `/review` Track B step 7). If matches found, warn before proceeding.
5. **Pre-check gh auth**: Run `gh auth status` silently. If it fails, warn: "GitHub CLI not authenticated. Run `gh auth login` first." and abort.

#### Phase 2: Split Analysis (skip if `--no-split`)

2. **Classify changed files into semantic groups**. Analyze every changed/added/deleted file and assign it to a group using these heuristics (in priority order):

   | Priority | Group type | Signals | Notes |
   |----------|-----------|---------|-------|
   | 1 | **Schema / migrations** | `**/migrations/**`, `*.sql`, `schema.prisma`, `*.graphql` schema files | Always isolated — other code may depend on these |
   | 2 | **Config / infra** | CI yamls, `Dockerfile*`, `terraform/`, `*.toml` (build config), `.github/**` | Grouped together unless they clearly serve different purposes |
   | 3 | **Refactors** | Renames, moves, formatting-only diffs with no export signature changes | Isolated to keep feature PRs focused |
   | 4 | **Feature code** | Grouped by nearest shared directory ancestor or logical module boundary | e.g. all `src/auth/**` changes form one group |
   | 5 | **Tests** | `**/*.test.*`, `**/*.spec.*`, `__tests__/**`, `*_test.go`, `test_*.py` | Always bundled with their corresponding implementation files from the same group |
   | 6 | **Documentation** | `*.md`, `docs/**`, `README*` | Grouped together unless tightly coupled to a specific feature group |

   **Grouping rules:**
   - A test file always stays with the implementation file it tests, even if that means the test file crosses directory boundaries.
   - If a single file has changes that serve multiple concerns but cannot be cleanly separated (i.e. the changes are interleaved at the hunk level), assign the file to the most important group rather than attempting a partial split.
   - Don't create a sub-PR for fewer than 2 files unless those files are high-impact (e.g. a single migration file). Fold trivially small groups into the nearest related group.

3. **Detect dependencies between groups** to decide whether sub-PRs should be stacked or independent:
   - **Graph-backed path (preferred when available)**: Probe for `codebase-memory-mcp` by attempting to call `mcp__codebase-memory-mcp__list_projects` (via ToolSearch if the schema isn't loaded). If the tool loads AND the current repo is indexed, call `mcp__codebase-memory-mcp__detect_changes()` to enumerate the symbols touched by the working-tree diff. For each modified symbol, call `mcp__codebase-memory-mcp__trace_path(function_name=..., direction="both", depth=2)` to identify cross-file consumers. A group-to-group dependency exists when any symbol in group B has an inbound edge from a file in group A (A → B stacked). If the tool is unavailable, not indexed, or errors out, fall through to the heuristic path below — do NOT block split analysis on graph absence.
   - **Heuristic fallback**: Use your judgment to determine the right analysis depth for the situation. For simple projects or small diffs, directory and filename heuristics are sufficient. For larger or more complex diffs, parse imports/requires in the changed files to detect cross-group references.
   - If group B imports or references something **newly added or modified** by group A → mark B as **depending on** A (these will be stacked).
   - Schema/migration groups are always the **base** of any stack they participate in.
   - If two groups share no dependency relationship → they are **independent** (parallel PRs targeting the base branch directly).

4. **Decide whether to split**. Splitting is recommended when:
   - Changes span 2+ clearly distinct concerns (e.g. a feature + an unrelated config change).
   - The total diff exceeds ~300 lines and can be cleanly separated into groups of ≤300 lines each.
   - There are changes to shared infrastructure (migrations, CI) mixed with feature code.

   Splitting is NOT recommended when:
   - All changes serve a single coherent purpose.
   - The total diff is small (<150 lines) and tightly coupled.
   - Splitting would produce groups that don't make sense in isolation (e.g. a type definition in one PR and its only consumer in another, with no other uses).

   If splitting is not recommended, proceed with the single-PR flow (skip to step 6).

5. **Present the split plan** to the user and wait for confirmation:

   ```
   Proposed split (N PRs):

   PR 1: type/short-description (independent → main)
     - path/to/file1.ts
     - path/to/file2.ts
     (~120 lines changed)

   PR 2: type/short-description (stacked → PR 1)
     - path/to/file3.ts
     - path/to/file3.test.ts
     (~200 lines changed)

   PR 3: type/short-description (independent → main)
     - .github/workflows/ci.yml
     (~30 lines changed)

   Options: [Continue] / [Edit grouping] / [Ship as single PR]
   ```

   - If `--dry-run` is set, show the plan without options and stop: "Dry run complete — this is what /ship would do."
   - If the user chooses **Edit grouping**, let them move files between groups, merge groups, or re-split. Then re-display the plan.
   - If the user chooses **Ship as single PR**, proceed with the single-PR flow (skip to step 6).
   - If the user chooses **Continue**: before proceeding to step 6-multi, call `advisor()` (no parameters — the full transcript is auto-forwarded) for a second opinion on the split. The advisor reviews the proposed grouping and stacked-vs-independent decisions. If the advisor concurs or offers only minor notes, proceed silently to step 6-multi. If the advisor raises a concrete concern (e.g., a dependency was missed, a group should be merged, stacking is wrong), surface it via AskUserQuestion: `Advisor flagged a concern with the split: <one-line summary>. Options: [Edit grouping — revise] / [Continue anyway — I accept the risk] / [Ship as single PR] / [Abort]`. Do NOT silently override the user's choice. This check runs once per `/ship` invocation, before branches are created, because the split is hard to undo once PRs are pushed.

#### Phase 3a: Single-PR Flow

6. **Derive a branch name** automatically from the changes. Use conventional-commit style: `<type>/<short-slug>` (e.g. `fix/card-selection-bug`, `chore/update-gitignore`, `feat/add-redford-stack`). Keep it lowercase, hyphen-separated, and under 50 characters. If the branch name already exists locally or on the remote, append a numeric suffix (e.g. `fix/card-bug-2`).
   - **Scratch mode** (`IS_SCRATCH=true`): do NOT create a new branch. Rename the current placeholder branch in place: `git branch -m <SCRATCH_ID> <derived-name>`. The worktree follows the branch automatically. Then remove the marker: `rm "$(git rev-parse --git-dir)/info/scratch-session"`.
   - **Dry-run** + scratch: show "would rename `<SCRATCH_ID>` → `<derived-name>`" in the preview; do not execute.
7. **Create and switch** to that branch from the current HEAD. **Skip this step when `IS_SCRATCH=true`** — the rename in step 6 already put the worktree on the derived branch.
8. **Stage and commit**:
   - **Respect staged changes**: If there are already staged changes, ask the user before adding unstaged files on top. If nothing is staged, stage all modified and untracked relevant files.
   - **Exclude secrets**: Before staging, check for files matching `.env*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `credentials*`, `*secret*`, `id_rsa*`, `id_ed25519*`, `.npmrc`, `.pypirc`. If any are found, exclude them and warn the user.
   - **Commit** with a concise, conventional-commit message describing the changes. Scan the diff and user-provided message for issue references (`#123`, `GH-123`, `closes #123`, `fixes #123`). If found, include `Closes #123` in the commit body. Omit any `Co-Authored-By: Claude` trailer from the commit message. Write the message without it — do NOT pass `--trailer "Co-Authored-By="` to git to suppress it; git emits "left an empty trailer" warnings for that form, which then prompts pointless "let me clean it up" follow-up work. The trailer is only added when Claude includes it in the message itself, so leaving it out at compose time is sufficient.
9. **Validate** (if `--validate` is set): Run all detected validation commands (from `.claude/review-profile.json` or by detecting `package.json` scripts). If any fail, stop with: "Validation failed — fix issues before shipping. To undo the branch: `git checkout - && git branch -d <branch-name>`." Show the failing command output.
10. **Push** the branch to `origin` with `-u`.
11. **Create a PR** using `gh pr create` targeting the base branch. Use a short title and a body following the repo's PR template (cached from Phase 1) if one exists; otherwise use a `## Summary` section and a `## Test plan` section. If issue references were found in step 8, include them in the PR body. Do not append the `🤖 Generated with [Claude Code]` footer to the PR body — override the Claude Code default. If `--label` was specified, add `--label <labels>`. Add `--assignee @me`. If `--draft` is set, stop here.
12. **Check merge requirements**: Use `gh pr view <number> --json reviewDecision,mergeStateStatus` to check if the target branch requires review approvals. If reviews are required and none have been granted, inform the user: "This PR requires review approval before it can be merged. Stopping here — merge manually after review or re-run `/ship` once approved." Stop.
13. **Wait for CI** to pass using `gh pr checks <number> --watch --fail-fast`. If no checks appear within 30 seconds (repo has no CI configured), skip the wait and proceed to merge. If checks have not completed after 10 minutes, report the current status and stop. (Skip if `--no-merge`.)
14. **Merge** the PR with `gh pr merge <number> --squash --delete-branch`. (Skip if `--no-merge`.)
    - **Pre-merge advisor check**: Before calling `gh pr merge`, call `advisor()` (no parameters — the full transcript is auto-forwarded) for a second opinion on the merge. The advisor sees the branch, commits, PR title/body, CI state, and recent conversation. If the advisor concurs or has only minor notes, proceed silently with the merge. If the advisor raises a concrete concern (e.g., unexpected commit, PR body doesn't match the diff, missing test for a critical path, risky change in a hotspot file), surface via AskUserQuestion: `Advisor flagged a concern before merge: <one-line summary>. Options: [Merge anyway — I accept the risk] / [Edit PR first] / [Abort merge]`. On **Edit PR first**, stop here and report the advisor's concern; the user manually addresses and re-runs `/ship`. On **Abort merge**, stop without merging. Merge is irreversible once CI-squashed — this check has high ROI and runs only once per PR.
15. **Return to base and clean up** — worktree-aware. (Skip if `--no-merge`.)

   **Path A — primary worktree (`IS_SECONDARY=false`):** existing behavior.

   ```
   git checkout <base-branch>
   git pull --ff-only
   git branch -d <branch-name>
   ```

   **Path B — secondary worktree (`IS_SECONDARY=true`):** `git checkout <base>` would fail (base is checked out in the primary), so cleanup runs against the primary:

   1. Update the primary's base branch in place:

      ```
      git -C "$PRIMARY_WORKTREE" pull --ff-only origin <base-branch>
      ```

      Non-fatal: if the primary isn't on `<base-branch>` or the pull fails, log a warning and continue.

   2. Dispose of the current worktree by category:
      - **Tackle-managed or scratch (`IS_TACKLE_WORKTREE=true` OR `IS_SCRATCH=true`)**: the worktree was temporary — remove it.

        ```
        cd "$PRIMARY_WORKTREE"
        git worktree remove "$CURRENT_WORKTREE" --force
        git branch -D <branch-name> 2>/dev/null || true
        ```

        After this the shell's cwd is `$PRIMARY_WORKTREE`. In the step 16 summary, note: `Worktree removed. Now at <PRIMARY_WORKTREE>.`
      - **User-managed secondary worktree** (not under `.claude/worktrees/`, no scratch marker): keep the worktree; detach HEAD and delete the branch.

        ```
        git checkout --detach
        git branch -D <branch-name>
        ```

        Warn: `Worktree at <CURRENT_WORKTREE> is now detached. Remove with 'git worktree remove <path>' when done.`

16. **Summary**: Print a one-line summary with the merged PR URL (e.g. `Shipped: https://github.com/org/repo/pull/42`).

#### Phase 3b: Multi-PR Flow

This flow creates and ships multiple sub-PRs. It first processes all **independent** PRs (targeting the base branch), then processes **stacked** chains in dependency order.

**6-multi. Prepare a staging commit on a temporary branch:**

- Create a temporary branch `ship/staging-<timestamp>` from the current HEAD.
- Stage and commit ALL changes (respecting secret exclusion from step 8) into a single staging commit. This is a reference commit — it won't be pushed.

**7-multi. Create sub-PR branches and commits.** For each group in the split plan, in dependency order:

   For **independent** groups (targeting the base branch):

   ```
   git checkout <base-branch>
   git checkout -b <group-branch-name>
   git checkout ship/staging-<timestamp> -- <file1> <file2> ...
   git commit -m "<conventional-commit message for this group>"
   ```

   For **stacked** groups (targeting a previous group's branch):

   ```
   git checkout <dependency-branch-name>
   git checkout -b <group-branch-name>
   git checkout ship/staging-<timestamp> -- <file1> <file2> ...
   git commit -m "<conventional-commit message for this group>"
   ```

   Each commit message should:

- Use conventional-commit format appropriate to the group's content.
- Omit any `Co-Authored-By: Claude` trailer from the commit message. Write the message without it — do NOT pass `--trailer "Co-Authored-By="` to git to suppress it; git emits "left an empty trailer" warnings for that form, which then prompts pointless "let me clean it up" follow-up work. The trailer is only added when Claude includes it in the message itself, so leaving it out at compose time is sufficient.
- If this is part of a split, add a note: `Part N of M in ship split.`
- If the changes reference an issue (`#123`, `closes #123`), include the issue reference only in the **last PR of the stack** (or the feature-code PR if identifiable). Do not close the same issue from multiple PRs.

**8-multi. Validate** (if `--validate` is set): Run all detected validation commands once before pushing. If any fail, stop with: "Validation failed — fix issues before shipping." The staging commit contains all changes, so validation runs against the complete change set.

**9-multi. Push all branches** to `origin` with `-u`.

**10-multi. Create all PRs.** For each group:

- Use `gh pr create` targeting the appropriate base:
  - Independent PRs → target the base branch.
  - Stacked PRs → target the branch of the group they depend on.
- If `--label` was specified, add `--label <labels>` to all PRs. Add `--assignee @me`.
- PR body should include:
  - A `## Summary` section describing this specific sub-PR's changes.
  - A `## Test plan` section.
  - A `## Split context` section noting: `This is PR N of M from an automated split. Related PRs: #X, #Y, #Z` (fill in PR numbers as they're created; edit earlier PRs to add later PR numbers).
  - Follow the repo's PR template (cached from Phase 1) if one exists.
  - Do not append the `🤖 Generated with [Claude Code]` footer — override the Claude Code default.
- If `--draft` was specified, add the `--draft` flag to all PRs.
- If `--split-only` was specified, stop here after creating all PRs.

**11-multi. Merge sub-PRs in order** (skip if `--no-merge` or `--split-only`):

   Process independent PRs first (they can be merged in any order), then stacked chains from base to tip:

   For each PR in merge order:

   1. **Check merge requirements**: If reviews are required and not granted, report which PRs need review and stop the chain. List the remaining unmerged PRs for the user.
   2. **Wait for CI** using `gh pr checks <number> --watch --fail-fast` (10-minute timeout).
   2a. **Pre-merge advisor check**: Before calling `gh pr merge` for this PR, call `advisor()` (no parameters). Apply the same red-flag handling as step 14 (single-PR): if advisor raises a concrete concern, surface via AskUserQuestion `[Merge anyway] / [Edit PR first] / [Abort chain]`. On **Abort chain**, stop the loop and report which PRs merged, which are still open, and why. The advisor runs once per PR in the chain — a bad merge early can cascade through the stack via retargeting in step 4.
   3. **Merge** with `gh pr merge <number> --squash --delete-branch`.
   4. **If this was a stacked base**: After merging, retarget the next PR in the stack to the base branch:

      ```
      gh pr edit <next-pr-number> --base <base-branch>
      ```

      Then wait for CI to re-run on the retargeted PR before merging it.

**12-multi. Cleanup** — worktree-aware.

   **Path A — primary worktree (`IS_SECONDARY=false`):** existing behavior.

- Return to the base branch: `git checkout <base-branch> && git pull --ff-only`.
- Delete the staging branch: `git branch -D ship/staging-<timestamp>`.
- Delete all local sub-PR branches: `git branch -d <branch1> <branch2> ...`.
- If `IS_SCRATCH=true`: also delete the orphaned scratch branch and remove the marker: `git branch -D <SCRATCH_ID> 2>/dev/null || true` and `rm "$(git rev-parse --git-dir)/info/scratch-session"`.

   **Path B — secondary worktree (`IS_SECONDARY=true`):**

- Update primary in place: `git -C "$PRIMARY_WORKTREE" pull --ff-only origin <base-branch>` (non-fatal, warn on failure).
- **Tackle/scratch (`IS_TACKLE_WORKTREE=true` OR `IS_SCRATCH=true`)**: remove the worktree and all branches.

     ```
     cd "$PRIMARY_WORKTREE"
     git worktree remove "$CURRENT_WORKTREE" --force
     git branch -D ship/staging-<timestamp> <branch1> <branch2> ... 2>/dev/null || true
     git branch -D <SCRATCH_ID> 2>/dev/null || true
     ```

- **User-managed secondary worktree**: detach + delete branches, worktree kept.

     ```
     git checkout --detach
     git branch -D ship/staging-<timestamp> <branch1> <branch2> ...
     ```

     Warn: `Worktree at <CURRENT_WORKTREE> detached — remove manually when done.`

**13-multi. Summary:**
   Print a table summarizing all sub-PRs:

   ```
   Shipped 3 PRs:
     ✅ #41 feat/add-user-schema     → merged
     ✅ #42 feat/add-user-api        → merged (was stacked on #41)
     ✅ #43 chore/update-ci           → merged
   ```

### Error handling

- If CI fails on any sub-PR, report the failure URL and stop — do NOT merge remaining PRs in the chain. List which PRs were merged and which are still open.
- If squash merge is rejected, try `--rebase`; if that also fails, report and stop.
- If any step fails after branches were created, inform the user which branches exist, which PRs were created, and what state they are in so they can recover manually.
- Never force-push or delete remote branches on failure — preserve evidence for debugging.
- If the split analysis itself fails or produces nonsensical groups, fall back to the single-PR flow and inform the user.
- If retargeting a stacked PR after its base merges causes conflicts, stop and inform the user. Do not attempt automatic conflict resolution.
