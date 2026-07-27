# Multi-PR flow (`/jr-ship` Phase 3b)

**Skill-local, conditional load.** Holds the Phase 3b multi-PR body: creating and shipping several
sub-PRs — independent ones first (targeting the base branch), then stacked chains in dependency
order. Not read at Phase 1: `/jr-ship` greps this file for existence and its anchors at Phase 1, and
Reads the body only when Phase 2 step 5 confirms a split (or `--split-only` was passed). Every
single-PR, `--no-split`, resume-mode and `--dry-run` run therefore never loads it.

Smoke-parse anchors are declared at the SKILL.md read site, deliberately NOT restated here: a header
that quotes its own anchors lets a body-stripped truncation false-pass the guard.

Paths in this file are relative to `<skill>/protocols/`, so shared protocols are `../../shared/…`.

#### Phase 3b: Multi-PR Flow

This flow creates and ships multiple sub-PRs. It first processes all **independent** PRs (targeting the base branch), then processes **stacked** chains in dependency order.

**Resume mode does NOT enter Phase 3b.** Phase 2 (split analysis) is skipped in resume mode, so there's no group/dependency information to drive ordered merging. Resume always uses the single-PR Phase 3a flow against `RESUME_PR_NUMBER`. If the user originally ran `/jr-ship --split-only`, only the PR matching the current branch will be resumed — the other branches need to be merged manually (see step 13-multi summary footer).

**6-multi. Prepare a staging commit on a temporary branch:**

- Create a temporary branch `jr-ship/staging-<timestamp>` from the current HEAD.
- Stage and commit ALL changes (respecting secret exclusion from step 8) into a single staging commit. This is a reference commit — it won't be pushed.

**7-multi. Create sub-PR branches and commits.** For each group in the split plan, in dependency order:

   For **independent** groups (targeting the base branch):

   ```
   git checkout <base-branch>
   git checkout -b <group-branch-name>
   git checkout jr-ship/staging-<timestamp> -- <file1> <file2> ...
   git commit -m "<conventional-commit message for this group>"
   ```

   For **stacked** groups (targeting a previous group's branch):

   ```
   git checkout <dependency-branch-name>
   git checkout -b <group-branch-name>
   git checkout jr-ship/staging-<timestamp> -- <file1> <file2> ...
   git commit -m "<conventional-commit message for this group>"
   ```

   Each commit message should:

- Use conventional-commit format appropriate to the group's content.
- Omit any `Co-Authored-By: Claude` trailer — same rule and rationale as the single-PR commit (step 8): leave it out at compose time; do NOT use `--trailer "Co-Authored-By="` to suppress it.
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
- **After all sub-PR branches have been pushed and PRs created**, delete the local staging branch: `git branch -D jr-ship/staging-<timestamp>`. Its sole purpose was to serve as a reference for `git checkout <staging> -- <files>` during the per-group commits in step 7-multi; it's no longer needed. This runs in default mode AND `--merge` mode. Deleting it here rather than relying on step 12-multi is deliberate: that cleanup is skipped on `--draft`, on any CI failure in 11a-multi, and on any merge failure in 11b-multi, so the staging branch would leak on each of those paths.

**10a-multi. File-overlap check** (skip if `--no-overlap-check` is set — print `Overlap check skipped (--no-overlap-check).` and continue): Apply the procedure in `overlap-check.md` (loaded in Phase 1) once for the entire batch — pass `BATCH_PR_NUMBERS=[<all sub-PR numbers created in step 10-multi>]` so PRs in the same batch do not flag each other (their splits are intentional per Phase 2). The procedure runs in batch mode: fetch each sub-PR's files via `gh pr view --json files`, query open PRs once via `gh pr list`, and group findings by which open PR has overlap with which sub-PR(s). Non-fatal in every case — any gh/jq error logs `Overlap check skipped: <reason>` and continues to step 11a-multi. Informational only; never blocks the chain. When `--merge` is set, the per-PR pre-merge `advisor()` at step 11b-multi sees the warning via transcript context.

**11a-multi. Wait for CI on each PR** (always runs, in dependency order):

   Process independent PRs first (they can be checked in any order), then stacked chains from base to tip. For each PR:

   1. **Check merge requirements**: Use `gh pr view <number> --json reviewDecision,mergeStateStatus`. If reviews are required and not granted, print an informational note (`"Note: PR #<N> needs review approval before it can be merged."`) — do not stop. With `--merge` set: stop the chain instead and list the remaining unmerged PRs.
   2. **Wait for CI** using `gh pr checks <number> --watch --fail-fast` (10-minute timeout). **If a check fails**, `git checkout` that sub-PR's branch and invoke the **CI-failure handling** procedure (`ci-failure-handling.md`, read at Phase 1) scoped to it: if it returns **green**, continue the wait pass with the next PR; if it returns **not-green** (or CI times out), report the failure URL and stop the wait pass — do NOT proceed to 11b-multi.

**11b-multi. Merge sub-PRs in order** (**run only if `--merge`**):

   Same dependency order as 11a-multi. For each PR:

   1. **Pre-merge advisor check**: Before calling `gh pr merge` for this PR, call `advisor()` (no parameters). Apply the same red-flag handling as step 14 (single-PR): if advisor raises a concrete concern, surface via AskUserQuestion `[Merge anyway] / [Edit PR first] / [Abort chain]`. On **Abort chain**, stop the loop and report which PRs merged, which are still open, and why. The advisor runs once per PR in the chain — a bad merge early can cascade through the stack via retargeting in step 3.
   2. **Merge** with `gh pr merge <number> --squash --delete-branch`.
   3. **If this was a stacked base**: After merging, retarget the next PR in the stack to the base branch:

      ```
      gh pr edit <next-pr-number> --base <base-branch>
      ```

      Then wait for CI to re-run on the retargeted PR (re-enter 11a-multi step 2 for that PR) before merging it.

**12-multi. Cleanup** — worktree-aware. (**Run after CI passes on every sub-PR in 11a-multi** — both with and without `--merge`. With `--merge`, runs after 11b-multi merges every sub-PR. Without `--merge`, runs as soon as 11a-multi confirms CI passed on every sub-PR — local sub-PR branches and tackle worktree are removed, but remote branches and PRs remain open for review. Skip if `--draft`, if any CI failed in 11a-multi, or if any merge failed in 11b-multi. The staging branch was already deleted in step 10-multi.)

   Apply the worktree-aware cleanup procedure from `${CLAUDE_SKILL_DIR}/protocols/worktree-cleanup.md` (read at Phase 1) with `BRANCHES=<branch1> <branch2> ...` (every sub-PR branch), `DELETE_SCRATCH=$IS_SCRATCH` (sub-PR branches are created fresh, leaving the original scratch branch orphaned), `SUMMARY_STEP=13-multi`.

**13-multi. Summary:**
   Print a table summarizing all sub-PRs.

   **Default mode** (no `--merge`):

   ```
   Shipped 3 PRs (open for review):
     🟢 #41 feat/add-user-schema     → open (CI: passed)
     🟢 #42 feat/add-user-api        → open (CI: passed, stacked on #41)
     🟢 #43 chore/update-ci           → open (CI: passed)

   Returned to <base>; local sub-PR branches deleted (worktree handling per step 12-multi path).
   Merge after review with the GitHub UI or `gh pr merge <N> --squash --delete-branch` for each PR.
   ```

   **`--merge` mode**:

   ```
   Shipped 3 PRs:
     ✅ #41 feat/add-user-schema     → merged
     ✅ #42 feat/add-user-api        → merged (was stacked on #41)
     ✅ #43 chore/update-ci           → merged
   ```

