# Worktree architecture: `bin/tackle` ↔ `/ship`

This file documents the contract between the `tackle` CLI and the `/ship` skill. It is imported into the project CLAUDE.md only when needed (`@docs/worktree-architecture.md`) so non-tackle work doesn't pay the token cost of loading it. **Edit this file when changing how worktrees, marker files, or cleanup paths work — both ends of the contract must stay aligned.**

## Role split
- **`bin/tackle`** — user-invoked shell CLI. Not a skill; Claude does not invoke it. Bootstraps Claude Code sessions against a GitHub PR/issue (`tackle <N>`) or an empty scratch worktree (`tackle --scratch`).
- **`/ship`** — skill Claude invokes when the user types `/ship`. Consumes the worktree state tackle set up.
- **Coordination**: no IPC. They agree on filesystem conventions (paths + marker files). Changing one end of the contract requires changing the other.

## Worktree layout convention
- All tackle worktrees live at `<repo>/.claude/worktrees/<id>/`.
- `<id>` = `<N>-<slug>` for PR/issue worktrees (slug from PR/issue title), `scratch-<ts>-<pid>` for scratch worktrees.
- Branch naming per mode:
  - **Scratch**: branch equals `<id>` (tackle uses `git worktree add -b <scratch-id>`).
  - **Issue**: branch equals `<id>` (tackle uses `gh issue develop --name <N>-<slug>`, or a local-branch fallback with the same name).
  - **PR**: branch is the PR's own branch name (via `gh pr checkout <N>`), NOT `<id>`. Fork PRs use the PR branch directly; if the branch is already checked out elsewhere, tackle falls back to a local name `<N>-<slug>`.
- `/ship` treats any worktree whose path contains the segment `/.claude/worktrees/` as tackle-managed (`IS_TACKLE_WORKTREE=true`) and ephemeral — it auto-removes them after merge. (Running `/ship` inside a PR worktree is unusual; use `git push` to update the existing PR instead.)

## Why tackle does NOT use `claude -w`
- `claude -w <name>` forces the branch to be named `worktree-<name>` (Claude Code convention).
- That defeats tackle's naming scheme (`<N>-<slug>` / `scratch-<id>`) and conflicts with `/ship`'s conventional-commit branch derivation.
- tackle creates worktrees itself via raw `git worktree add` and invokes Claude with `claude --name <id>` for a friendly session label without the branch-name constraint. **Do not replace `--name` with `-w` — it breaks the architecture.**

## Scratch-session contract
- `tackle --scratch` creates a placeholder branch `scratch-<ts>-<pid>` from HEAD and drops a marker at `<worktree>/.git/info/scratch-session` whose contents are the scratch-id.
- `.git/info/` is the worktree-scoped git info dir (resolves to `<repo>/.git/worktrees/<id>/info/` for linked worktrees). It is **never committed** and is auto-cleaned when the worktree is pruned — no `.gitignore` entry needed.
- `/ship` Phase 1 reads this marker. If non-empty AND matches current HEAD, it sets `IS_SCRATCH=true` and `SCRATCH_ID=<marker>`.
- When set, `/ship` step 6 **renames the placeholder branch in place** via `git branch -m <SCRATCH_ID> <derived-name>` instead of creating a new branch. It then `rm`s the marker so re-running `/ship` on the same worktree doesn't retrigger the rename path.
- Stale marker (scratch-id ≠ current HEAD): warn "stale scratch marker", treat as non-scratch, continue normal flow.

## Tackle-type marker
- After creating any worktree (PR / issue / scratch), tackle writes the mode to `<worktree>/.git/info/tackle-type` — one of `pr`, `issue`, or `scratch`. Same worktree-scoped, never-committed, auto-pruned pattern as `scratch-session`.
- Read on resume by `read_tackle_type()` to drive the right behavior without an extra `gh` API call. Currently consumed by the prefill-prompt feature in `launch_claude()` (chooses "tackle issue" vs "tackle PR" template). Older worktrees from before this marker existed return empty → graceful no-op.
- Don't conflate with `scratch-session`: the scratch marker is a runtime contract with `/ship` (presence + match-vs-HEAD triggers in-place rename); `tackle-type` is a runtime hint local to tackle.

## Per-session context injection
- tackle writes PR/issue-specific context — title, URL, body, comments, reviews, instructions — into `<worktree>/CLAUDE.local.md`, delimited by `<!-- tackle-context-begin -->` and `<!-- tackle-context-end -->`. The `inject_claude_local_md()` function (`bin/tackle`) handles idempotent replacement: re-running `tackle <N>` rewrites the block in place.
- `CLAUDE.local.md` is auto-loaded by Claude Code alongside `CLAUDE.md`, so the session sees the context without the repo's real project-standards file being touched.
- tackle appends `CLAUDE.local.md` to the worktree-scoped `.git/info/exclude` on every inject, so the file can never be staged or committed from inside the worktree. Same pattern as the scratch-session marker: worktree-scoped, never committed, auto-cleaned when `git worktree prune` runs.
- `/ship` and `/review` need no special handling: the file is invisible to git from inside the worktree (via the exclude entry), and `CLAUDE.md` itself is untouched — so `/review`'s Phase 1 Track A and `/audit`'s equivalent read the real project standards, not PR context.

## Worktree-aware cleanup in `/ship`
`/ship` runs from any worktree. A secondary worktree cannot `git checkout <base>` (dual-checkout protection) and cannot `git branch -d` the currently-checked-out branch. So step 15 (single-PR) and step 12-multi (split-PR) split into two paths.

Detection primitives computed in Phase 1 (step 1b):
- `CURRENT_WORKTREE` = `git rev-parse --show-toplevel`
- `IS_SECONDARY` = `git rev-parse --git-dir` ≠ `git rev-parse --git-common-dir`
- `PRIMARY_WORKTREE` = first `worktree` entry from `git worktree list --porcelain`
- `IS_TACKLE_WORKTREE` = `CURRENT_WORKTREE` contains `/.claude/worktrees/`

Cleanup paths:
- **Path A (primary worktree)**: existing behavior — `checkout <base> && pull --ff-only && branch -d`.
- **Path B (secondary worktree)**: `git -C $PRIMARY_WORKTREE pull --ff-only origin <base>` (non-fatal warn on failure), then by category:
  - Tackle/scratch (`IS_TACKLE_WORKTREE=true` OR `IS_SCRATCH=true`): `cd $PRIMARY_WORKTREE && git worktree remove $CURRENT_WORKTREE --force && git branch -D <branch>`.
  - User-managed secondary: `git checkout --detach && git branch -D <branch>`. Worktree kept; warn the user.

## Anti-patterns (don't do these)
- **Don't use `claude -w` in tackle.** Forces `worktree-<name>` branch prefix and breaks the deferred-naming contract with `/ship`. tackle must create worktrees itself and launch Claude with `claude --name`.
- **Don't `git checkout <base>` from a secondary worktree.** Git's dual-checkout protection will fail. Use `git -C $PRIMARY_WORKTREE` for any operation targeting the base branch.
- **Don't delete the scratch marker before `/ship` step 6 runs.** Breaks rename detection; `/ship` will silently fall into the create-new-branch path.
- **Don't put tackle under `skills/<name>/`.** The `skills/` subtree has semantic meaning for Claude Code's skill loader. tackle is a CLI, not a skill; it lives at `bin/tackle` with a symlink from `~/.local/bin/tackle` for `$PATH` invocation.
- **Don't commit the scratch marker or the `.claude/worktrees/` directory.** Marker is in `.git/info/` precisely to avoid this. Worktree dirs should be in the consuming repo's `.gitignore`.
- **Don't inject tackle context into `<worktree>/CLAUDE.md`.** The repo's CLAUDE.md is read as authoritative project standards by `/review` and `/audit`; injecting per-session PR context there causes both skills to mis-read the standards and exposes the content to accidental commit. Always write to `<worktree>/CLAUDE.local.md` and register it in `.git/info/exclude` (same pattern as the scratch-session marker).
- **Don't expect cleanup in `--no-merge` / `--draft` / `--split-only` flows.** Step 15 / 12-multi are skipped in those modes — tackle worktrees persist until manually removed via `tackle --cleanup` or `git worktree remove`.
