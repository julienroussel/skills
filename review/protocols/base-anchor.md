# Phase 5 — Base Commit Anchor + Combined Revert Sequence

**Canonical procedure** for capturing the pre-Phase-5 baselines and reverting on any subsequent abort. Referenced by `review/SKILL.md` Phase 5 and every later abort site that needs to roll back implementer/simplification edits.

## Anchor capture (run once at Phase 5 entry)

```bash
baseCommit=$(git rev-parse HEAD)
anchorErr=$(mktemp)
state=$("$CLAUDE_SKILL_DIR/scripts/establish-base-anchor.sh" "$baseCommit" 2>"$anchorErr")
ec=$?
case $ec in
  0)
    untrackedBaseline=$(printf '%s' "$state" | jq -r .untrackedBaseline)
    untrackedBaselineAll=$(printf '%s' "$state" | jq -r .untrackedBaselineAll)
    symlinkBaseline=$(printf '%s' "$state" | jq -r .symlinkBaseline)
    NUL_SORT_AVAILABLE=$(printf '%s' "$state" | jq -r .NUL_SORT_AVAILABLE)
    rm -f "$anchorErr"
    ;;
  1)
    cat "$anchorErr" >&2
    rm -f "$anchorErr"
    echo "Failed to capture a valid commit hash — cannot proceed with implementation." >&2
    exit 1
    ;;
  3)
    abortMode=true
    abortReason=$(grep -oE '\[ABORT-REASON: [a-z-]+\]' "$anchorErr" | sed -E 's/.*: ([a-z-]+)\]/\1/' | head -n 1)
    [ -z "$abortReason" ] && abortReason="anchor-error"
    cat "$anchorErr" >&2   # surface the human [REVERT BLOCKED — *] marker
    rm -f "$anchorErr"
    # Caller calls TeamDelete (no wait) if a team was created in Phase 2,
    # then transfers control to Phase 7 in abort mode. Phase 7 runs steps 1, 2,
    # and 4 only; step 3 is skipped so secret-warnings.json audit trail persists.
    ;;
  *)
    abortMode=true; abortReason="anchor-error"
    cat "$anchorErr" >&2
    rm -f "$anchorErr"
    ;;
esac
```

The script's header comment carries the canonical abort-condition matrix (`[REVERT BLOCKED — *]` marker → `abortReason` mapping). **Adding a new abort condition** requires updating: the script, /review's `abortReason` allowed-values list (now defined in `shared/abort-markers.md`), and `shared/abort-markers.md` itself.

## Symlink-escape validation

The script runs symlink-escape validation BEFORE returning success — any pre-existing symlink whose canonical target lies outside the repo halts BEFORE any later revert can write through it. The pre-checkout validation is belt-and-braces; `core.symlinks=false` (in step 3 of the revert sequence below) is the primary defense.

## NUL-delimited baseline outputs

On success, the script returns NUL-delimited mktemp paths in JSON; the lead agent parses them and uses them as inputs to every later revert.

- **Never store NUL-delimited file contents in shell variables** at downstream sites — `xargs -0`, `comm -z`, and `diff -z` read directly from these temp files.
- The `NUL_SORT_AVAILABLE` flag is a probe of `sort -z` AND `comm -z` together. Stock macOS ships `sort` with `-z` but `comm` without — both must be checked. The flag tells downstream sites whether to use `comm -z` directly or fall back to a `tr '\0' '\n'` + perl-newline-validation path.
- When `NUL_SORT_AVAILABLE=false`, log it in the Phase 7 report ("degraded mode — never silent", same convention as `FLOCK_AVAILABLE=false`). For CI/build systems on macOS, document that `brew install coreutils` (then alias `gsort`/`gcomm`) restores the canonical path.

## Combined revert sequence

Used by every later revert site that references `$baseCommit`:

1. **Clean untracked files**: `git clean -fd -- <newUntrackedFiles>` (compared against `$untrackedBaseline`).
2. **Clean new gitignored files**: `rm -f -- <newGitignoredFiles>` (compared against `$untrackedBaselineAll`; `git clean` skips gitignored).

   *Cross-platform note*: on both BSD and GNU coreutils, `rm -f --` removes the symlink itself (does not follow); but `rm -rf` on a symlinked path follows on GNU. Stay with `rm -f` for individual files.

3. **Detect and remove new symbolic links**: compare `find . -type l -print0` against `$symlinkBaseline` using NUL-delimited comparison.

   - When `NUL_SORT_AVAILABLE=true`: `comm -z -23 <(find . -type l -print0 | sort -z) <(sort -z "$symlinkBaseline")`.
   - When `NUL_SORT_AVAILABLE=false`: validated `tr`-fallback path.

   *Accepted residual risk*: a TOCTOU window exists between symlink detection and checkout — mitigated by the agent-isolation model (exploiting it requires a subagent ignoring the git-command restriction) AND by step 4 below using `core.symlinks=false`.

4. **Restore working tree**: `git -c core.symlinks=false checkout "$baseCommit" -- .`. Git writes symlinks as plain text files containing the target path, eliminating the write-through-symlink primitive AND closing the enumeration→checkout TOCTOU.

5. **Reset index**: `git reset "$baseCommit" -- .` (handles staged new files not present at `$baseCommit`).

If `--converge` is set, the convergence loop also uses this anchor for file tracking (see convergence-protocol.md "File tracking mechanism").
