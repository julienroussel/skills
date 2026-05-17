# Phase 5.6 — Pre-Commit Hook Offer + Install Error-Code Matrix

**Canonical procedure** for installing the temporary git pre-commit hook that blocks commits containing detected secret patterns. Referenced by `review/SKILL.md` Phase 5.6. Triggered by behavior 3 of the User-continue path protocol in `../shared/secret-scan-protocols.md`.

## Why install the hook

`secret-warnings.json` is an audit trail only until `/ship` enforces it (currently NOT IMPLEMENTED — see `/review` Cross-skill contract status). To add automated enforcement locally, install a scoped pre-commit hook. The hook scans **staged blob content** (`git show ":$f"`), not the working-tree file — so a user cannot stage a secret then scrub it from the working tree without re-staging to bypass.

## Offer flow

When the 'Continue' path is taken and `secret-warnings.json` has been written:

- **Interactive mode** (`isHeadless=false`): AskUserQuestion `Install a temporary pre-commit hook to block commits containing the detected secret patterns? Options: [Install hook (recommended)] / [Skip — I will handle it manually]`.
- **Headless/CI mode** (`isHeadless=true`): skip the offer. CI environments typically have their own pre-commit enforcement.
- **`FLOCK_AVAILABLE=false`**: install the hook anyway. The per-session filename strategy uses the glob enumeration in the template, which handles per-session files correctly. Log to Phase 7 report: `Pre-commit hook installed (per-session filename strategy active — flock unavailable on this platform)`.

## Install procedure

If the offer is accepted:

1. **Write patterns file** (BEFORE invoking the install script): write the list of detected secret regexes (one per line, no shell interpolation) to `.claude/secret-hook-patterns.txt`. Apply the `.gitignore`-enforcement protocol from `../shared/gitignore-enforcement.md` to that path before write — warn if tracked, append to `.gitignore` if absent. Per-site reason if tracked: "A committed patterns file could be tampered to weaken or disable specific secret-detection rules across all future commits — the additive baseline patterns hardcoded in the hook template still fire, but extension patterns (the broader Phase 1 set) would silently regress."

2. **Invoke the install script**:

```bash
installErr=$(mktemp)
"$CLAUDE_SKILL_DIR/scripts/install-pre-commit-secret-guard.sh" 2>"$installErr"
ec=$?
case $ec in
  0) : ;;  # installed (or idempotent no-op)
  2)
    cat "$installErr" >&2
    # Phase 7 report appends: "ACTION REQUIRED: pre-commit hook NOT installed — template SHA-256 mismatch OR template file missing entirely. Reinstall /review from canonical source."
    ;;
  4)
    cat "$installErr" >&2
    # Phase 7 report appends: "ACTION REQUIRED: pre-commit hook block on disk is stale; manually delete the BEGIN/END block and re-run /review to reinstall the canonical template."
    ;;
  5)
    cat "$installErr" >&2
    # Phase 7 report appends: "ACTION REQUIRED: pre-commit hook NOT installed — multiple claude-secret-guard blocks detected (TAMPERING SUSPECTED). Manually remove ALL blocks between '# BEGIN claude-secret-guard' and '# END claude-secret-guard' in .git/hooks/pre-commit, then re-run /review."
    ;;
  1|3)
    cat "$installErr" >&2
    # Skip-class: exit 1 (jq absent, no shasum/sha256sum, missing .git, flock contention within
    # 30s wait) is user-fixable; exit 3 means the user has their own pre-commit hook that
    # /review will not touch. Both are logged as one-line skip reasons in the Phase 7 report
    # under "Skipped".
    ;;
  *)
    cat "$installErr" >&2
    echo "WARNING: install script returned unexpected exit code $ec — caller dispatch out of sync with scripts/install-pre-commit-secret-guard.sh" >&2
    # Phase 7 report appends: "ACTION REQUIRED: pre-commit install script returned unrecognized exit code $ec — caller/script dispatch drift; update review/protocols/pre-commit-hook-offer.md case-block to handle exit $ec."
    ;;
esac
rm -f "$installErr"
```

The case-block above MUST cover every exit code defined by the install script's exit-codes block (`scripts/install-pre-commit-secret-guard.sh`). When adding a new exit code on either side, update both files in the same commit.

The install script gates the canonical template (`templates/pre-commit-secret-guard.sh.tmpl`) on: SHA-256 verification (defends against tampering), `jq` availability, `.git` directory presence, idempotent-reinstall short-circuit, shebang compatibility check (existing hooks must be bash-compatible). On failure, it writes a one-line skip reason to stderr and exits non-zero. Do NOT let an implementer construct an ad-hoc variant of the hook at runtime — the canonical template is the only sanctioned form.

## Hook design invariants

(Read `templates/pre-commit-secret-guard.sh.tmpl` for the canonical implementation; anyone modifying the template MUST preserve these.)

- **Tamper-resistant**: an additive hardcoded baseline (AWS, Anthropic, GitHub, Stripe, PEM) cannot be silently disabled by editing `.claude/secret-hook-patterns.txt`; extension patterns extend, never replace, the baseline.
- **Fails closed**: the hook does NOT self-remove and refuses to run when `.claude/secret-warnings*.json` is absent — disarming requires explicit user action between the BEGIN/END markers. No sentinel to forge.
- **Scans the index, not the working tree**: content comes from `git show ":$f"` (with a working-tree fallback for previously-staged paths in the audit trail).
- **Path allowlist + POSIX ERE only**: hook validates each path against `^[a-zA-Z0-9_/.-]+$` before any filesystem op; patterns file is POSIX ERE (no `\s`/`\d`/`\w`/`\b`/lookbehinds — those fail under BSD/macOS `grep -E`). Non-boundary checks (e.g., `dapi` prefix) live in `/review` post-match inspection, not in the pattern.
- **Bash, not sh**: the install step pins `#!/usr/bin/env bash` and uses bash-only arrays. Top-level `set -eo pipefail`; per-file inner shell is `bash -c 'set -eo pipefail; ...'` so semantics propagate.
- **Never logs secret content**: matched line numbers via `grep -aEn | head -1 | cut -d: -f1`, never the matched line itself — hook stdout is captured in commit logs / CI / shell history.
- **No `eval`, no `$(...)` on filenames** — paths read via `jq -r ... | xargs -0 ...` (NUL-delimited).

## Disarming

The hook does NOT self-remove. When all warnings are resolved, the user must disarm it explicitly by deleting the block between the `# BEGIN claude-secret-guard` and `# END claude-secret-guard` markers in `.git/hooks/pre-commit`. Explicit user action is the fail-closed semantics — no sentinel to forge.
