#!/usr/bin/env bash
# establish-base-anchor.sh — capture pre-Phase-5 baselines + validate symlinks
#
# Called by /review at Phase 5 entry, before spawning implementers. Captures
# NUL-safe baselines for untracked files and symlinks (referenced by all
# subsequent revert sites), probes NUL_SORT_AVAILABLE, validates that no
# filename in the baseline contains a newline, and validates that every
# pre-existing symlink resolves inside REPO_ROOT.
#
# Read-only with respect to the working tree. Mutates only:
#   - three mktemp files (paths returned in JSON output on success only;
#     an EXIT trap removes them on every failure path so they don't leak —
#     a `_keep=1` sentinel is set immediately before the success printf so
#     the caller can consume the paths)
#   - exit code 3 + stderr marker on validation failure
#
# ─────────────────────────────────────────────────────────────────
# Usage:
#   ./establish-base-anchor.sh <baseCommit>
#
# Output (stdout, on success only — single-line JSON):
#   {"untrackedBaseline":"/tmp/...","untrackedBaselineAll":"/tmp/...","symlinkBaseline":"/tmp/...","NUL_SORT_AVAILABLE":true|false}
#
# Output (stderr, on failure):
#   [REVERT BLOCKED — <reason>]
#
# Exit codes:
#   0 — success, all baselines captured, JSON state on stdout
#   1 — invalid arguments (missing or malformed baseCommit)
#   3 — validation failure (caller MUST set abortMode=true with the abortReason
#       printed below and proceed to Phase 7 in abort mode)
#
# ─────────────────────────────────────────────────────────────────
# Abort-condition matrix (kept in sync with /review SKILL.md):
#
#   Stderr marker                                           | abortReason
#   --------------------------------------------------------|------------------------------
#   [REVERT BLOCKED — REPO_ROOT UNSET]                      | repo-root-unset
#   [REVERT BLOCKED — READLINK FAILED] <symlink>            | symlink-readlink-failed
#   [REVERT BLOCKED — READLINK RETURNED EMPTY] <symlink>    | symlink-readlink-empty
#   [REVERT BLOCKED — SYMLINK DANGLING OR UNRESOLVABLE] ... | symlink-dangling
#   [REVERT BLOCKED — SYMLINK ESCAPES REPO] ...             | symlink-escape
#   [REVERT BLOCKED — NUL-SORT UNAVAILABLE + NEWLINE IN PATH] | nul-sort-newline
#   [REVERT BLOCKED — FIND TRAVERSAL FAILED] <rc>            | find-traversal-failed
#
# The caller parses the marker and assigns abortReason accordingly. Adding a
# new abort site here REQUIRES adding the matching abortReason to /review's
# allowed-values list AND to ../shared/abort-markers.md.

set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "[REVERT BLOCKED — USAGE] Expected: $0 <baseCommit>" >&2
  exit 1
fi

baseCommit="$1"

# Validate hash format (SHA-1 or SHA-256). Rejects anything else fail-closed.
case "$baseCommit" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *)
    echo "[REVERT BLOCKED — USAGE] baseCommit must be a SHA-1 (40-char) or SHA-256 (64-char) hex hash" >&2
    exit 1
    ;;
esac

# ── EXIT trap: cleanup mktemp baselines on every non-success path ──
# The three baseline paths are emitted in JSON only on the success path; every
# `exit 1`/`exit 3` site below would otherwise leak them. Set `_keep=1` right
# before the success printf so the caller can consume the paths. `${var:-}`
# parameter expansion guards against unset vars under `set -u` if the trap
# fires before a given mktemp has been assigned.
_keep=0
findErrFiles=()
_cleanup() {
  if [ "${_keep:-0}" != "1" ]; then
    rm -f "${untrackedBaseline:-}" "${untrackedBaselineAll:-}" "${symlinkBaseline:-}"
  fi
  # findErr mktemps would otherwise leak if `set -e` aborts between mktemp and
  # the _check_find_traversal call that normally rm's them. Cleaned on every
  # exit path (success and failure both). The array-empty guard is required
  # because the script runs under `set -u` and expanding an empty unquoted
  # array would error.
  if [ "${#findErrFiles[@]}" -gt 0 ]; then
    rm -f "${findErrFiles[@]}"
  fi
}
trap _cleanup EXIT

# ── Helper: run `find . -type l -print0 ...` with fail-closed traversal ──
# GNU find returns non-zero on partial traversal, but BSD find on macOS exits
# 0 even when chmod-000 subdirs cause "Permission denied" diagnostics — so
# checking $? alone misses the contract violation. Validate BOTH: rc != 0 OR
# stderr contains a known traversal-failure substring. On failure, emit the
# canonical [REVERT BLOCKED — FIND TRAVERSAL FAILED] marker + abort-reason
# and exit 3. The caller's 2>"$anchorErr" capture surfaces the diagnostic.
#
# Args:
#   $1 — rc captured from the find invocation
#   $2 — path to the find-stderr capture file
# Side effects: rm -f the stderr file before exit (the EXIT trap doesn't know
#   about it). Exits 3 on validation failure.
_check_find_traversal() {
  local rc="$1"
  local errFile="$2"
  local stderrContent=""
  if [ -s "$errFile" ]; then
    stderrContent=$(cat "$errFile")
  fi
  if [ "$rc" -ne 0 ] \
     || printf '%s' "$stderrContent" | grep -qE 'Permission denied|Operation not permitted|Not a directory'; then
    if [ -n "$stderrContent" ]; then
      printf '%s\n' "$stderrContent" >&2
    fi
    echo "[REVERT BLOCKED — FIND TRAVERSAL FAILED] find exited $rc; partial symlink baseline would weaken the symlink-escape gate" >&2
    echo "[ABORT-REASON: find-traversal-failed]" >&2
    rm -f "$errFile"
    exit 3
  fi
  rm -f "$errFile"
}

# ── Step 0: Resolve REPO_ROOT, fail closed if unset, and cd into it ──
# Resolved BEFORE baselining so that subsequent `find . -type l` and
# `git ls-files` invocations enumerate from the repo root, not from whatever
# subdirectory the caller invoked /review from. Without this, repo-wide
# symlinks in untouched subtrees would evade the symlink-escape gate.
# An unset REPO_ROOT would make the Step 5 case-arm match every absolute path
# (because empty matches empty and "/*" matches any absolute path), silently
# bypassing the entire symlink-escape check. Fail closed instead.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "[REVERT BLOCKED — REPO_ROOT UNSET]" >&2
  echo "[ABORT-REASON: repo-root-unset]" >&2
  exit 3
fi
cd "$REPO_ROOT" || {
  echo "[REVERT BLOCKED — REPO_ROOT UNSET]" >&2
  echo "[ABORT-REASON: repo-root-unset]" >&2
  exit 3
}

# ── Step 1: Capture baselines to mktemp files ──
untrackedBaseline=$(mktemp)
git ls-files --others --exclude-standard -z > "$untrackedBaseline"

untrackedBaselineAll=$(mktemp)
git ls-files --others -z > "$untrackedBaselineAll"

symlinkBaseline=$(mktemp)
# Fail-closed on partial traversal: a permission-denied subdir would leave the
# baseline incomplete, weakening the symlink-escape gate (and misclassifying
# the missing symlinks as "newly created during the run" on revert, causing
# unrelated user symlinks to be rm'd). Capture stderr so the BSD-find
# silent-partial-output failure mode is detected (see `_check_find_traversal`).
findErr=$(mktemp)
findErrFiles+=("$findErr")
set +e
find . -type l -print0 > "$symlinkBaseline" 2>"$findErr"
rc=$?
set -e
_check_find_traversal "$rc" "$findErr"

# ── Step 2: Probe NUL_SORT_AVAILABLE (sort -z + comm -z) ──
# macOS ships an Apple-patched sort with -z but BSD comm WITHOUT -z, so probing
# sort alone is NOT a sufficient proxy. Verify both. Empirically: stock macOS
# sort -z exits 0; comm -z file file fails with "illegal option -- z".
NUL_SORT_AVAILABLE=true
if ! printf 'a\0' | sort -z >/dev/null 2>&1; then
  NUL_SORT_AVAILABLE=false
fi
if [ "$NUL_SORT_AVAILABLE" = "true" ]; then
  _t1=$(mktemp); _t2=$(mktemp)
  printf 'a\0' > "$_t1"; printf 'a\0' > "$_t2"
  if ! comm -z "$_t1" "$_t2" >/dev/null 2>&1; then
    NUL_SORT_AVAILABLE=false
  fi
  rm -f "$_t1" "$_t2"
fi

# ── Step 3: If NUL_SORT_AVAILABLE=false, validate no newlines in paths ──
# When falling back to tr-based delimiting, embedded newlines make the fallback
# unsafe. Detect with perl -0 (BSD awk on macOS does NOT support RS='\0').
if [ "$NUL_SORT_AVAILABLE" = "false" ]; then
  newlineInBaseline=$(perl -0 -ne 'BEGIN{$c=0} $c++ if /\n/; END{print $c+0}' < "$symlinkBaseline")
  # Same fail-closed find pattern as Step 1: capture stderr + rc rather than
  # silently swallowing them with `2>/dev/null` (BSD find on macOS exits 0 on
  # partial traversal, so a stderr+rc check is required to detect it).
  findErr=$(mktemp)
  findErrFiles+=("$findErr")
  findOut=$(mktemp)
  set +e
  find . -type l -print0 > "$findOut" 2>"$findErr"
  rc=$?
  set -e
  _check_find_traversal "$rc" "$findErr"
  newlineInCurrent=$(perl -0 -ne 'BEGIN{$c=0} $c++ if /\n/; END{print $c+0}' < "$findOut")
  rm -f "$findOut"
  if [ "${newlineInBaseline:-0}" -gt 0 ] || [ "${newlineInCurrent:-0}" -gt 0 ]; then
    echo "[REVERT BLOCKED — NUL-SORT UNAVAILABLE + NEWLINE IN PATH]" >&2
    echo "[ABORT-REASON: nul-sort-newline]" >&2
    exit 3
  fi
fi

# ── Step 5: Symlink-escape validation (every pre-existing symlink) ──
# git checkout follows pre-existing symlinks, so a baseline symlink pointing
# outside the repo is a write-through-symlink primitive. The post-loop gate
# in step 6 enforces abort BEFORE checkout runs. Loop and gate live in the
# same script invocation so a `break` cannot escape the abort latch.
abortReason=""
while IFS= read -r -d '' f; do
  if ! target=$(readlink "$f" 2>/dev/null); then
    echo "[REVERT BLOCKED — READLINK FAILED] $f" >&2
    abortReason="symlink-readlink-failed"
    break
  fi
  if [ -z "$target" ]; then
    echo "[REVERT BLOCKED — READLINK RETURNED EMPTY] $f" >&2
    abortReason="symlink-readlink-empty"
    break
  fi
  case "$target" in
    /*) abs="$target" ;;
    *)  abs="$(cd "$(dirname "$f")" && pwd -P)/$target" ;;
  esac
  canonical_dir=$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P || true)
  if [ -z "$canonical_dir" ]; then
    echo "[REVERT BLOCKED — SYMLINK DANGLING OR UNRESOLVABLE] $f -> $target" >&2
    abortReason="symlink-dangling"
    break
  fi
  canonical="$canonical_dir/$(basename "$abs")"
  case "$canonical" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) : ;;
    *)
      echo "[REVERT BLOCKED — SYMLINK ESCAPES REPO] $f -> $canonical (target outside $REPO_ROOT)" >&2
      abortReason="symlink-escape"
      break
      ;;
  esac
done < "$symlinkBaseline"

# ── Step 6: Post-loop gate — halt before any caller-side checkout ──
if [ -n "$abortReason" ]; then
  echo "[ABORT-REASON: $abortReason]" >&2
  exit 3
fi

# ── Success: emit JSON state ──
# Disarm the EXIT-trap cleanup so the caller can consume the baseline paths.
_keep=1
printf '{"untrackedBaseline":"%s","untrackedBaselineAll":"%s","symlinkBaseline":"%s","NUL_SORT_AVAILABLE":%s}\n' \
  "$untrackedBaseline" "$untrackedBaselineAll" "$symlinkBaseline" "$NUL_SORT_AVAILABLE"
