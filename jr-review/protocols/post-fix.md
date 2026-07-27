# Post-fix path: Simplification (Phase 5.5) + Fix verification (Phase 5.55) (`/jr-review`)

**Skill-local, deferred load (Pattern C).** Holds the Phase 5.5 and Phase 5.55 bodies. Not read at
Phase 1: the Phase 1 Track A guard only greps this file for existence and its anchors, and the body
is Read into lead context at **Phase 5 entry**, alongside `fix-secret-validate.md`. Phase 5 is
skipped entirely under `nofix` — and `--pr` implies `nofix` — so every findings-only and remote-PR
review never loads this file at all.

Smoke-parse anchors are declared at the SKILL.md read site, deliberately NOT restated here: a header
that quotes its own anchors lets a body-stripped truncation false-pass the guard.

Paths here are relative to `<skill>/protocols/`, so shared protocols are `../../shared/…`.

## Phase 5.5 — Simplification pass

**Skip if `nofix` or `quick` is set, or if fewer than 3 findings were implemented.**

Spawn a **single Agent** using the Agent tool directly (independent of the Phase 2 reviewers) and **no `name:`** (`../../shared/subagent-reporting.md` "Spawn rule" — a named agent is a persistent teammate whose final response never reaches the lead); give it a distinct `description` instead. Pass it the list of files modified by Phase 5 implementers. The agent reviews the modified files for post-fix simplification opportunities:
- Reduce unnecessary complexity/nesting introduced by fixes
- Eliminate redundancy between fix code and existing code
- Improve naming clarity where fixes introduced new variables/functions
- Replace nested ternaries with switch/if-else if introduced
- Ensure fixes follow project standards (ES modules, function keyword, explicit types)

This is a lightweight pass — only flag changes that are clear wins. Do NOT re-review unchanged code. Apply simplifications directly (no separate approval gate).

**Roll-call (mandatory)**: apply the roll-call from `../../shared/subagent-reporting.md` to this spawn. Only an agent that **explicitly reports** "no improvements" prints the skip line. An agent that returns nothing, an empty result, or an error is `UNREPORTED`: it latches `unreportedCount` and is named in the Phase 7 Coverage-gaps item 7(b) — never rendered as a silent skip, which is exactly what a clean pass looks like from the outside. **Do not assume the tree is clean**: the agent applies simplifications in place, so one that errors or exhausts its turn budget *after* editing returns nothing while leaving unreviewed edits behind — diff the modified-file set against the pre-5.5 snapshot and report those files under item 7(b) too, since no `improvements applied` count can be printed for them.

Instruct the simplification agent: "Do NOT run any `git` commands. Only modify files using the Write/Edit tools." Then include the full content of `../../shared/untrusted-input-defense.md` (read into lead context at Phase 1 Track A) verbatim in the simplification-agent prompt. Do NOT paraphrase. Additionally include the full content of `../../shared/code-edit-discipline.md` verbatim, prefixed with the Phase-5.5-specific lead-in defined in `../SKILL.md` **"Model requirements"** ("Your assignment is to simplify only when…") — keep the two prompt-construction sites in sync. Additionally include the **Subagent-facing block** of `../../shared/subagent-reporting.md` verbatim, so an agent that finds nothing says so rather than ending its turn silently.

**Display**: `Phase 5.5 — Simplification: N improvements applied` (or skip line if none)

## Phase 5.55 — Fix verification (read-after-write)

**Skip if `nofix` flag is set** (no fixes were applied). Skip findings marked `contested` by their implementer (the implementer explicitly declined to fix; there is nothing to verify).

For each finding that Phase 5 marked as "addressed", the lead agent performs a targeted re-read to confirm the fix actually resolved the cited issue. This catches the failure mode where an implementer technically modified the file but did not address the finding (e.g., added `// @ts-expect-error` instead of handling the null, renamed a variable but left the bug, or fixed the wrong line). The check is lightweight and strictly additive — it does NOT re-review the rest of the file.

For each addressed finding, **in parallel** (batch Read calls into a single message across findings):

1. Re-read the cited `file` over the range `[line - 5, line + 5]` (clamped to file bounds).
2. Evaluate against the finding's description and suggested fix: is the issue described as "wrong" still present at (or near) the cited line? Consider small line-number drift (±5) from the implementer's edit.
3. Classify the finding into one of:
   - **verified**: the fix is visible and plausibly resolves the cited issue. No action.
   - **unverified**: the fix is not visible, the cited line is unchanged, or the fix looks like a suppression (`@ts-expect-error`, `eslint-disable`, swallowing catch) rather than a resolution. Mark the finding with a `verified=false` flag and surface in the Phase 7 report under `ACTION REQUIRED: Fix did not resolve cited issue: <dimension>/<category> at <file>:<line>`.
   - **moved**: the cited line no longer contains the problem but the fix is at a different nearby line (common with formatter adjustments). Treat as verified and note the line shift in the Phase 7 report.

**Thresholds**:
- If more than **30% of findings** in a single dimension are `unverified`, surface a Phase 7 `ACTION REQUIRED` note: `High unverified rate in <dimension> (<N>/<M>). Review implementer output manually.` Do NOT auto-revert — `unverified` is a soft flag that informs the user, not a halt signal. The user decides whether to run `/jr-review` again or revert.
- If any `critical`-severity finding is `unverified`, escalate to a single targeted AskUserQuestion in interactive mode: `Critical finding "<description>" may not have been resolved. Options: [Accept as-is — I'll verify manually] / [Revert all Phase 5 changes and re-run]`. In headless/CI mode, skip the prompt but keep the ACTION REQUIRED entry and exit non-zero.

**Display**: `Phase 5.55 — Verification: M/N fixes verified (K unverified, L moved)` (or skip line if zero fixes).
