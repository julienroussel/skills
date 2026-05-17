#!/usr/bin/env bash
# install-pre-commit-secret-guard.sh — install the /review pre-commit secret-guard hook
#
# Called by /review at Phase 5.6 only when (a) the user accepted the User-continue
# path AND (b) chose [Install hook] at the AskUserQuestion. Appends the canonical
# template (delimited by `# BEGIN claude-secret-guard` / `# END claude-secret-guard`)
# to `.git/hooks/pre-commit`. Refuses to install if any prerequisite fails — ad-hoc
# variants are out of scope.
#
# ─────────────────────────────────────────────────────────────────
# Usage:
#   install-pre-commit-secret-guard.sh
#
# Output (stderr, on any non-zero exit):
#   one or more reason lines suitable for the Phase 7 report skip-log
#
# Stderr wording convention:
#   "Pre-commit hook installation aborted — …"  → tamper-class (exit 2, 4, or 5); the operator
#     must NOT install and should audit the source.
#   "Pre-commit hook installation skipped — …"  → user-fixable prerequisite or
#     environmental issue (exit 1 or 3); the operator resolves and re-runs.
#   "Pre-commit hook block already installed — no-op."  → idempotent re-install success
#     (exit 0); no action required.
# Operators with log-grep alerting should match on the leading phrase to bucket by class.
#
# Exit codes:
#   0 — installed (or block already present and idempotent re-install was a no-op)
#   1 — prerequisite missing (jq absent, .git missing, no shasum/sha256sum on PATH,
#       flock contention) — user-fixable; the operator installs the missing
#       binary (or moves to a real git working tree) and re-runs
#   2 — template SHA-256 mismatch OR template file missing entirely (tampering or
#       corrupted install) — DO NOT install
#   3 — incompatible existing hook (non-bash shebang) — caller logs skip and moves on
#   4 — stale hook block on disk (installed body differs from canonical template) —
#       caller surfaces as ACTION REQUIRED; user must manually disarm + re-run
#   5 — multiple claude-secret-guard blocks present (TAMPERING SUSPECTED) — caller
#       surfaces as ACTION REQUIRED; user must manually remove ALL blocks + re-run
#
# Distinction between exit 1 and exit 2: BOTH the no-hash-tool branch (the "else"
# arm of the "command -v shasum"/"command -v sha256sum" ladder) and the missing-template
# branch (the [ ! -f "$templatePath" ] guard immediately preceding it) bypass the
# SHA-256 verification. They diverge on cause and remediation:
#   - No hash tool: environmental (BusyBox / hardened minimal container with neither
#     shasum nor sha256sum). Recoverable by installing coreutils. → exit 1.
#   - Missing template: skill files are incomplete; either an interrupted install or
#     a tamper signal. NOT recoverable by the operator without re-fetching the canonical
#     skill source — manually recreating the template would bypass the SHA check
#     against an unknown body. → exit 2.
#
# Caller dispatch contract: see review/protocols/pre-commit-hook-offer.md
# "Install procedure" — its `case $ec in ... esac` block MUST cover every exit code
# above. When adding a new exit code here, update the caller in the same commit.
#
# ─────────────────────────────────────────────────────────────────
# SHA-256 verification
#
# Maintenance contract: when the canonical template changes intentionally, all
# four steps below MUST land in a single commit. The hash check is the only
# tamper-evidence the install path has — a stale EXPECTED hash silently breaks
# every user's install path with exit 2 (which mimics a tamper signal).
#
#   1. Edit `../templates/pre-commit-secret-guard.sh.tmpl`.
#   2. Run `shasum -a 256 ../templates/pre-commit-secret-guard.sh.tmpl`.
#   3. Update `EXPECTED_TEMPLATE_SHA256` below to the new hash.
#   4. Commit all three (template + script + any prose) together. /doctor's
#      template-hash drift check (Group I, when implemented) catches step 3
#      omissions; until then, the cryptic exit-2 in the field IS the signal.

set -euo pipefail

EXPECTED_TEMPLATE_SHA256="33cef21e2deb906ab20588d41a6b009c91d0f2cbca3d603ee635dc3e58a63616"

scriptDir=$(cd "$(dirname "$0")" && pwd -P)
templatePath="$scriptDir/../templates/pre-commit-secret-guard.sh.tmpl"

if [ ! -f "$templatePath" ]; then
  echo "Pre-commit hook installation aborted — template file is missing entirely; SHA-256 verification cannot run." >&2
  echo "  expected path: $templatePath" >&2
  echo "  Reinstall the skill from the canonical source. This is a tamper-class signal — do NOT manually recreate the template." >&2
  exit 2
fi

# ── SHA-256 verification (mandatory) ──
if command -v shasum >/dev/null 2>&1; then
  actualHash=$(shasum -a 256 "$templatePath" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  actualHash=$(sha256sum "$templatePath" | awk '{print $1}')
else
  echo "Pre-commit hook installation skipped — neither shasum nor sha256sum available; cannot verify template integrity" >&2
  exit 1
fi

if [ "$actualHash" != "$EXPECTED_TEMPLATE_SHA256" ]; then
  echo "Pre-commit hook installation aborted — template SHA-256 mismatch." >&2
  echo "  expected: $EXPECTED_TEMPLATE_SHA256" >&2
  echo "  actual:   $actualHash" >&2
  echo "  path:     $templatePath" >&2
  echo "  Reinstall the skill from the canonical source, or update EXPECTED_TEMPLATE_SHA256 in this script after a deliberate template change." >&2
  exit 2
fi

# ── Prerequisite checks ──
if ! command -v jq >/dev/null 2>&1; then
  echo "Pre-commit hook installation skipped — jq is not installed (required by hook to parse secret-warnings*.json)" >&2
  exit 1
fi

# Resolve git dir + hooks dir via plumbing — handles plain checkouts AND
# git worktrees (where .git is a *file*, not a directory) AND honors core.hooksPath.
gitDir=$(git rev-parse --git-dir 2>/dev/null) || {
  echo "Pre-commit hook installation skipped — not in a git working tree" >&2
  exit 1
}
hooksDir=$(git rev-parse --git-path hooks 2>/dev/null) || hooksDir="$gitDir/hooks"
mkdir -p "$hooksDir"
hookPath="$hooksDir/pre-commit"

# ── Acquire exclusive lock BEFORE the idempotent check ──
# Serializes the entire decide-then-append region across concurrent installs
# (e.g. parallel /review invocations across worktrees that share .git/hooks).
# Without this, two invocations could both pass the idempotent check on a
# fresh hook and both append, producing duplicate blocks. flock is best-effort:
# if unavailable on the platform, proceed without it. Uses a 30-second
# timed wait (-w 30) so genuine contention surfaces as exit 1 instead of
# hanging Phase 5.6 indefinitely.
#
# Side effect: `exec 9<>"$hookPath"` creates the file if missing. Downstream
# checks that previously used `[ -f ]` to detect a missing hook now use
# `[ -s ]` (empty-file check) — equivalent for the create-with-shebang path
# and more correct semantically. The FD is held until process exit; the lock
# releases when the process terminates (no explicit `flock -u` required).
if command -v flock >/dev/null 2>&1; then
  touch "$hookPath"
  exec 9<>"$hookPath"
  if ! flock -x -w 30 9; then
    echo "Pre-commit hook installation skipped — could not acquire lock on $hookPath within 30s" >&2
    exit 1
  fi
fi

# ── Idempotent re-install check (with stale-block detection) ──
if [ -f "$hookPath" ] && grep -qE '^# BEGIN claude-secret-guard$' "$hookPath"; then
  # Detect multi-block tampering before extraction — awk's range pattern would
  # otherwise concatenate every BEGIN..END pair into a single buffer and the
  # hash would be misleading.
  beginCount=$(grep -cF "# BEGIN claude-secret-guard" "$hookPath")
  endCount=$(grep -cF "# END claude-secret-guard" "$hookPath")
  if [ "$beginCount" -gt 1 ] || [ "$endCount" -gt 1 ]; then
    echo "Pre-commit hook installation aborted — multiple claude-secret-guard blocks present ($beginCount BEGIN, $endCount END markers); TAMPERING SUSPECTED." >&2
    echo "  Marker lines:" >&2
    grep -nE '^# (BEGIN|END) claude-secret-guard$' "$hookPath" >&2
    echo "  Manual action: open $hookPath, remove ALL claude-secret-guard blocks, then re-run /review." >&2
    exit 5
  fi
  # The on-disk block was appended verbatim from $templatePath. Compare its
  # hash to the canonical template hash ($actualHash, computed above). If they
  # differ, the user's hook contains a stale template body — refuse the no-op
  # and require manual disarm + reinstall, otherwise SHA-256 verification only
  # protects the install path and never catches post-install drift.
  existingBlockFile=$(mktemp)
  trap 'rm -f "$existingBlockFile"' EXIT
  awk '/^# BEGIN claude-secret-guard$/,/^# END claude-secret-guard$/' "$hookPath" > "$existingBlockFile"
  if command -v shasum >/dev/null 2>&1; then
    existingHash=$(shasum -a 256 "$existingBlockFile" | awk '{print $1}')
  else
    existingHash=$(sha256sum "$existingBlockFile" | awk '{print $1}')
  fi
  rm -f "$existingBlockFile"
  if [ "$existingHash" != "$actualHash" ]; then
    echo "Pre-commit hook installation aborted — installed block is STALE; on-disk body differs from canonical template." >&2
    echo "  expected (template): $actualHash" >&2
    echo "  on-disk (block):     $existingHash" >&2
    echo "  Manual action: delete the block between '# BEGIN claude-secret-guard' and" >&2
    echo "  '# END claude-secret-guard' in $hookPath, then re-run /review to reinstall." >&2
    exit 4
  fi
  echo "Pre-commit hook block already installed — no-op." >&2
  exit 0
fi

# ── Existing-hook compatibility check ──
# Use [ -s ] not [ -f ] so an empty file (created as a side effect of the
# early FD open above) flows to the create-with-shebang branch instead of
# tripping the "shebang not bash-compatible (found: )" arm.
if [ -s "$hookPath" ]; then
  firstLine=$(head -n 1 "$hookPath")
  case "$firstLine" in
    "#!/usr/bin/env bash"|"#!/bin/bash"|"#!/usr/local/bin/bash") : ;;
    *)
      echo "Pre-commit hook installation skipped — existing hook shebang is not bash-compatible (found: $firstLine)" >&2
      exit 3
      ;;
  esac
fi

# ── Append the template (delimited by BEGIN/END markers) ──
# If hook is empty (no content), create it with shebang first. Use [ ! -s ]
# rather than [ ! -f ] because the early FD open above may have already
# created the file as a side effect.
if [ ! -s "$hookPath" ]; then
  printf '#!/usr/bin/env bash\n' > "$hookPath"
  chmod 0755 "$hookPath"
fi

# Newline before block if existing hook does not end with one.
if [ -s "$hookPath" ] && [ "$(tail -c 1 "$hookPath" | od -An -c | tr -d ' ')" != '\n' ]; then
  printf '\n' >> "$hookPath"
fi

cat "$templatePath" >> "$hookPath"
chmod 0755 "$hookPath"

echo "Pre-commit hook installed at $hookPath. To disarm: delete the block between '# BEGIN claude-secret-guard' and '# END claude-secret-guard' in that file."
