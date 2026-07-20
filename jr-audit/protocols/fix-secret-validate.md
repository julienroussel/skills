# Fix path: Secret re-scan (Phase 5.6) + Validate-fix loop (Phase 6) (`/jr-audit`)

**Skill-local, deferred load (Pattern C).** Holds the Phase 5.6 and Phase 6 bodies for `/jr-audit`. Not read at Phase 1: the SKILL.md Phase 1 Track A guard only greps this file for existence and anchors (no body load), and the body is Read into lead context at **Phase 5 entry** (after the base-commit anchor, before the implementer spawn); the convergence loop reuses it. Smoke-parse anchors enforced at the Phase 1 grep-guard: `## Phase 5.6 — Secret re-scan` AND `## Phase 6 — Validate-fix loop`.

## Phase 5.6 — Secret re-scan

**Skip if `nofix` flag is set.**

Before scanning, verify the base commit anchor is still valid: `if [ "$(git rev-parse HEAD)" != "$baseCommit" ]; then` warn: 'HEAD has moved unexpectedly — an implementer may have run git commands. Aborting for safety.' First reset HEAD to the base commit (`git reset "$baseCommit"`), then apply the **Combined revert sequence** from `../../shared/secret-scan-protocols.md` (uses `git -c core.symlinks=false checkout` + NUL-delimited symlink comparison; the canonical sequence is the only sanctioned form), set `abortMode=true`/`abortReason="head-moved-phase-5.6"`, and proceed to Phase 7.

Re-run the secret pre-scan patterns against all files modified by implementers. Additionally, check for new untracked files created by implementers (`git ls-files --others --exclude-standard`) and include them in the scan. Also check for new gitignored files (`git ls-files --others` compared against `$untrackedBaselineAll`). Apply the advisory-tier classification per `../../shared/secret-scan-protocols.md` ("Advisory-tier classification for re-scans"): only strict-tier matches trigger the halt; advisory-tier matches (SK, dapi, sk- meeting demotion criteria) are logged to the report.

If strict-tier secrets are detected, halt immediately. **Security check (enforced)**: Apply the `.gitignore`-enforcement protocol (see `../../shared/gitignore-enforcement.md`) for path `.claude/secret-warnings.json` (its warn/append-and-inform behavior). Per-site reason if tracked: "A committed secret-warnings file would conflate one user's accepted-secret entries with another's, silently suppressing legitimate halts." Then write detected secret locations to `.claude/secret-warnings.json` per `../../shared/secret-warnings-schema.md` (preserve any pre-existing `consumerEnforcement` value).

In headless mode (per `../../shared/secret-scan-protocols.md` "Headless/CI detection"), apply the **CI/headless secret-halt protocol** from the shared file (sets `abortMode=true`; the caller MUST also set `abortReason="secret-halt-phase-5.6"` before invoking).

In interactive mode, present via AskUserQuestion: [Abort | Continue].
- On **Continue**: apply the **User-continue path protocol** from `../../shared/secret-scan-protocols.md` ("User-continue path after post-implementation secret detection") — execute ALL SIX behaviors verbatim (ACTION REQUIRED logging, audit-trail write, pre-commit hook offer, final `⚠ SECRET STILL PRESENT` warning, `userContinueWithSecret=true` latch for non-zero Phase 7 exit, and suppression-list snapshot to `$postImplAcceptedTuples`). No subset is permitted. Then proceed to Phase 6.
- On **Abort**: apply the **Combined revert sequence** from `../../shared/secret-scan-protocols.md`, set `abortMode=true`/`abortReason="secret-halt-phase-5.6-user-abort"`, proceed to Phase 7.

## Phase 6 — Validate-fix loop

**Skip entirely if `nofix` is set.**


### Post-implementation formatting

If the project has a formatter configured (detected from package.json scripts: `format`, `prettier`, etc.), run it on modified files **first** (before validation).

### Validation

Run **all detected validation commands in parallel** (lint, typecheck, test as separate simultaneous Bash calls in a single message). Compare against the **Phase 1 baseline** — only new failures count as regressions.

- **No new failures**: Move to Phase 7.
- **New failures**: Fix regressions (dispatch **multiple implementer agents in parallel** — pass them coding standards so fixes don't introduce new violations; include all implementer safety instructions: git restriction, **the full content of `../../shared/untrusted-input-defense.md` verbatim — do NOT paraphrase**, **the full content of `../../shared/code-edit-discipline.md` verbatim — do NOT paraphrase**, and strict file ownership), then re-validate. Repeat up to max retries (default 3).
  - **Secret re-scan after regression fixes**: Run the secret pre-scan against files modified by regression-fix implementers after each fix attempt. Apply the advisory-tier classification per `../../shared/secret-scan-protocols.md` ("Advisory-tier classification for re-scans"): only strict-tier matches trigger the halt; advisory-tier matches (SK, dapi, sk- meeting demotion criteria) are logged to the report. If strict-tier secrets are detected, halt and present to user via AskUserQuestion. If `isHeadless` is true (per `../../shared/secret-scan-protocols.md` "Headless/CI detection"), do NOT call AskUserQuestion — instead apply the automatic revert and failure exit from `../../shared/secret-scan-protocols.md` ("CI/headless secret-halt protocol"); the caller MUST also set `abortReason="secret-halt-phase-6-regression"` before invoking the protocol. If the user aborts, apply the Combined revert sequence from `../../shared/secret-scan-protocols.md` (clean → rm-f → symlink-removal → checkout → reset), set `abortMode=true` and `abortReason="user-abort"`, and proceed to Phase 7 in abort mode. If the user continues, apply the User-continue path protocol from `../../shared/secret-scan-protocols.md` (User-continue path after post-implementation secret detection) — execute **ALL SIX behaviors verbatim. No subset is permitted** (ACTION REQUIRED logging, audit-trail write to `.claude/secret-warnings.json` with `consumerEnforcement` preserved and gitignore-enforcement applied, pre-commit hook offer, final `⚠ SECRET STILL PRESENT` warning, `userContinueWithSecret=true` non-zero-exit latch, suppression-list snapshot). Proceed with next retry.
- **Max retries exhausted**: Before moving to Phase 7, run the **stuck-loop advisor check** (single-fire). Initialize `phase6AdvisorFired=false` at Phase 6 entry; on the first time this branch is reached AND `phase6AdvisorFired=false`, set `phase6AdvisorFired=true` and call `advisor()` (no parameters — full transcript auto-forwarded). Per `../../shared/advisor-criteria.md`'s "When stuck" criterion, validation regressions surviving `maxRetries` rounds are the canonical stuck signal. If the advisor concurs (no actionable insight), proceed silently to Phase 7 and report remaining failures. If the advisor offers a concrete actionable insight, surface via AskUserQuestion: `[Apply suggested fix and retry once more] / [Stop here — proceed to Phase 7] / [Abort and revert all changes since $baseCommit]`. On **Apply**, dispatch ONE additional implementer with the advisor's suggestion (include all implementer safety instructions: git restriction, the full content of `../../shared/untrusted-input-defense.md` verbatim — do NOT paraphrase, the full content of `../../shared/code-edit-discipline.md` verbatim — do NOT paraphrase, and strict file ownership); if that retry also fails, do NOT re-fire — proceed to Phase 7. On **Abort**, apply the Combined revert sequence (see `../../shared/secret-scan-protocols.md`), set `abortMode=true`/`abortReason="user-abort"`, proceed to Phase 7. The single-fire guard prevents budget burn — the advisor sees the full retry history once.

After a successful validation (no new regressions), update `.claude/review-baseline.json` with the post-fix results.

**Display**: Compact validation summary per command. Update timeline.
