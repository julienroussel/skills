# Worktree-Aware Cleanup

**Canonical procedure** for the post-CI cleanup shared by single-PR step 15 and multi-PR step 12-multi. Read at Phase 1 under the hard-fail + smoke-parse guard; the anchors are declared at the `jr-ship/SKILL.md` read site and deliberately not restated here, since a header that quotes its own anchors lets a body-stripped truncation false-pass the guard. The call sites own their run/skip conditions (when CI must be green, `--draft`/`--merge` interactions); this file owns the cleanup body.

**Parameters** (set by the call site before applying):

- `BRANCHES` — the local branch name(s) to delete. Single-PR step 15 passes one (`<branch-name>`); multi-PR step 12-multi passes every sub-PR branch (`<branch1> <branch2> ...`).
- `DELETE_SCRATCH` — `true` only at the multi-PR site when `IS_SCRATCH=true`: the sub-PR branches were created fresh, leaving the original scratch branch orphaned. (Single-PR mode renames the scratch branch in place, so it passes `false`.)
- `SUMMARY_STEP` — the caller's summary step (`16` or `13-multi`), referenced in the worktree-removed note below.

## Consent basis for branch/worktree deletion

The `git branch -d/-D` and `git worktree remove --force` operations below are the documented `/jr-ship` cleanup contract — invoking `/jr-ship` without `--draft` is the user's authorization for them. They are effect-safe: cleanup is gated on CI success, which runs only after the branch(es) were pushed, so every commit is preserved on the remote plus the open PR(s); `git branch -D` only drops local refs. Do NOT add a separate confirmation prompt here — with `--draft`, no cleanup runs at all.

**What that argument does and does not cover.** It covers **committed** content only. It says nothing about files that were never committed — and step 8 (`../SKILL.md`, "Exclude secrets") *guarantees* such files exist by design: it refuses to stage `.env*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `credentials*`, `*secret*`, `id_rsa*`, `id_ed25519*`, `.npmrc`, `.pypirc` and merely warns. Those files stay untracked (usually gitignored too) in the worktree. `git worktree remove --force` is precisely the flag that overrides git's refusal to remove a worktree holding untracked or modified files — git's own docs: *"Only clean worktrees (no untracked files and no modification in tracked files) can be removed. Unclean worktrees … can be removed with `--force`."* So on the tackle/scratch path the credential files the skill deliberately protected from the remote were deleted from the only place they existed, with nothing on the remote to restore them, on an ordinary no-`--merge` ship. The **Untracked-content guard** below is the required precondition for that removal; it is not a "separate confirmation prompt" of the kind this paragraph bars, which concerns the branch/worktree refs themselves.

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

     **Untracked-content guard (mandatory, before the removal).** Enumerate what the removal would
     destroy, and read the producer's own status — never treat an empty capture from a failed command
     as "nothing to lose":

     ```
     raw=$(git -C "$CURRENT_WORKTREE" -c core.quotePath=false ls-files --others); ec=$?
     leftovers=$(printf '%s\n' "$raw" | grep -E '^"|(^|/)(\.env[^/]*|[^/]*\.(pem|key|p12|pfx|jks)|credentials[^/]*|[^/]*secret[^/]*|id_rsa[^/]*|id_ed25519[^/]*|\.npmrc|\.pypirc)$')
     n=$(printf '%s\n' "$leftovers" | grep -c .)
     ```

     `ec` is captured on its own line, **before** any filtering. Folding the `grep` into that same
     pipeline would make `$?` the filter's status (`1` whenever it simply matched nothing), which
     silently retires the fail-closed branch below.

     Omit `--exclude-standard` deliberately: `.env` and friends are normally **gitignored**, and
     `--exclude-standard` would hide exactly the files this guard exists to protect. Filter by
     **name** instead, against step 8's denylist. Unfiltered, the raw enumeration also returns every
     ignored build artifact (`node_modules`, `dist`, local caches), so `leftovers` is non-empty on
     essentially every ship from a tackle or scratch worktree: the guard always refuses, the removal
     path becomes unreachable in practice, and the one signal that matters is buried in the noise.

     **What this filter defends.** Irreversible loss of credential files that exist only here.
     *In scope*: step 8's denylist matched against each path's final component, case-sensitively (the
     same spelling step 8 uses); plus any path git C-quotes (leading `"`), which is how a name
     containing a newline, quote or backslash arrives — unrepresentable, therefore never silently
     dropped. *Knowingly out of scope*: uncommitted content that is not credential-shaped (step 8
     stages and pushes that, so the removal does not lose it), and files whose secret nature is
     visible only in their contents — this guard reads names, not bodies.

     `-c core.quotePath=false` is **load-bearing, not cosmetic**. It narrows git's quoting to paths it
     cannot print literally (newline, quote, backslash), which is what keeps one path on one line and
     makes `n` a true count; those paths still arrive quoted, so the `^"` clause still catches them.
     Drop the setting and git also quotes every non-ASCII name, so an ordinary `café.txt` is swept in
     as leftovers on every run and the guard reverts to refusing unconditionally.

     - `ec` non-zero → enumeration failed. Do **not** remove the worktree; keep it, log
       `Worktree kept: could not enumerate untracked content (git ls-files exit <ec>).`, and continue
       with branch cleanup only. Fail closed: an unverifiable worktree is never force-removed.
     - `ec` zero and `leftovers` **empty** → nothing uncommitted is at risk; proceed with the removal
       below as before.
     - `ec` zero and `leftovers` **non-empty** → do **not** force-remove. List the paths (one per
       line, exactly as `git ls-files` printed them) and ask, with `<n>` taken from `n` above:
       `AskUserQuestion`: `<n> uncommitted credential-shaped file(s) exist only in this worktree and are not on the remote: <paths>. Options: [Keep the worktree] / [Delete it and lose these files]`.
       Default to **[Keep the worktree]**; on that choice log
       `Worktree kept: <n> credential-shaped file(s) would have been lost.` and skip to the branch deletion.
       Only on an explicit **[Delete it and lose these files]** proceed to the removal.
       In **headless mode** (`../../shared/secret-scan-protocols.md` "Headless/CI detection") there is
       nobody to ask: keep the worktree and log the same line. Never auto-delete unreviewed content.

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
