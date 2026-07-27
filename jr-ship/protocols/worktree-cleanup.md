# Worktree-Aware Cleanup

**Canonical procedure** for the post-CI cleanup shared by single-PR step 15 and multi-PR step 12-multi. Read at Phase 1 under the hard-fail + smoke-parse guard; the anchors are declared at the `jr-ship/SKILL.md` read site and deliberately not restated here, since a header that quotes its own anchors lets a body-stripped truncation false-pass the guard. The call sites own their run/skip conditions (when CI must be green, `--draft`/`--merge` interactions); this file owns the cleanup body.

**Parameters** (set by the call site before applying):

- `BRANCHES` — the local branch name(s) to delete. Single-PR step 15 passes one (`<branch-name>`); multi-PR step 12-multi passes every sub-PR branch (`<branch1> <branch2> ...`).
- `DELETE_SCRATCH` — `true` only at the multi-PR site when `IS_SCRATCH=true`: the sub-PR branches were created fresh, leaving the original scratch branch orphaned. (Single-PR mode renames the scratch branch in place, so it passes `false`.)
- `SUMMARY_STEP` — the caller's summary step (`16` or `13-multi`), referenced in the worktree-removed note below.

## Consent basis for branch/worktree deletion

The `git branch -d/-D` and `git worktree remove --force` operations below are the documented `/jr-ship` cleanup contract — invoking `/jr-ship` without `--draft` is the user's authorization for them. They are effect-safe: cleanup is gated on CI success, which runs only after the branch(es) were pushed, so every commit is preserved on the remote plus the open PR(s); `git branch -D` only drops local refs. Do NOT add a separate confirmation prompt here — with `--draft`, no cleanup runs at all.

## Path A — primary worktree (`IS_SECONDARY=false`)

```
git checkout <base-branch>
git pull --ff-only
git branch -d $BRANCHES
```

If `DELETE_SCRATCH=true`: also delete the orphaned scratch branch and remove the marker:

```
git branch -D <SCRATCH_ID> 2>/dev/null || true
rm "$(git rev-parse --git-dir)/info/scratch-session"
```

## Path B — secondary worktree (`IS_SECONDARY=true`)

`git checkout <base>` would fail (base is checked out in the primary), so cleanup runs against the primary:

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
     git branch -D $BRANCHES 2>/dev/null || true
     ```

     If `DELETE_SCRATCH=true`: also `git branch -D <SCRATCH_ID> 2>/dev/null || true`.

     After this the shell's cwd is `$PRIMARY_WORKTREE`. In the `SUMMARY_STEP` summary, note: `Worktree removed. Now at <PRIMARY_WORKTREE>.`
   - **User-managed secondary worktree** (not under `.claude/worktrees/`, no scratch marker): keep the worktree; detach HEAD and delete the branch(es).

     ```
     git checkout --detach
     git branch -D $BRANCHES
     ```

     Warn: `Worktree at <CURRENT_WORKTREE> is now detached. Remove with 'git worktree remove <path>' when done.`
