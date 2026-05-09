# Advisor Call Criteria

**Canonical source** for *when* and *how* a skill should call `advisor()`. Currently consumed by `/skill-audit`'s `advisor-coverage-reviewer` to evaluate other skills' coverage. The criteria here are extracted from Anthropic's published advisor tool guidance (see "Source" below) so they apply portably to any user's machine — they are **not** taken from any individual user's personal `CLAUDE.md`.

## Source

The rules in this file mirror the Claude Code advisor tool's documented behavior. When auditing a skill, treat these rules as authoritative; if Anthropic's published guidance changes, update this file (and bump the file's `Last verified` timestamp at the bottom).

## When to call advisor

A skill SHOULD call `advisor()`:

1. **Before substantive work** — before writing, before committing to an interpretation that informs substantive edits, before building on an unverified assumption. Orientation (finding files, fetching a source, seeing what's there) is **not** substantive work and does not require an advisor call. **Writing, editing, dispatching subagents, and declaring an answer are.**
2. **Before declaring done on non-trivial work** — call advisor before the final report renders or the skill returns control. The advisor sees the full transcript and catches direction drift cheaply. Make the deliverable **durable** (write the file, save the result, commit the change) **before** the advisor call so a session interruption mid-call doesn't lose work.
3. **When stuck** — errors recurring, approach not converging, results that don't fit. The advisor is the cheaper alternative to thrashing in the same wrong direction.
4. **Before a change of approach** — when the skill is mid-execution and considering a strategy pivot (e.g., abandoning convergence, switching dispatch strategy), advisor's full-transcript view is highest-value here.

A skill MAY skip advisor on:
- **Short reactive tasks** where the next action is dictated by tool output the skill just read. The advisor adds most of its value on the first call, before the approach crystallizes.
- **Mechanical phases** with no judgment calls (config reads, deduplication, file enumeration). These are the same kind of "orientation" work that doesn't trigger criterion 1 above.

## How to call advisor (gating + guards)

Calls MUST be guarded so they don't fire excessively or in ways that drain budget:

- **Single-fire on retry loops** — when a phase has a max-retry counter (e.g., validate-fix loop, regression-fix loop), call advisor at most **once per run** in the stuck-loop branch. Use a boolean flag (`phaseNAdvisorFired = true` after the first call) to prevent re-fires on subsequent retries within the same run.
- **Conditional triggers on quality signals** — gate calls on "this looks suspicious" predicates rather than firing every time:
  - **Skewed-dimension** — a single reviewer dimension contributing ≥ 60% of all findings (the strongest empirical hallucination cue).
  - **Findings-volume** — total finding count crossing a threshold (e.g., ≥ 20).
  - **Iteration depth** — convergence iteration ≥ 3 (`/review`) or ≥ 2 (`/audit`).
- **Mode gating** — calls that only make sense in a particular mode should be gated by the flag (e.g., `/ship`'s pre-merge advisor only fires when `--merge` is set; the no-merge default leaves the advisor dormant).
- **Auto-approve compatibility** — if the skill supports `--auto-approve` / headless execution, decide explicitly whether the advisor still fires in that mode. The general rule: keep advisor calls active in headless mode for any branch that mutates user code or commits to an irreversible decision, since a wrong call is exactly what advisor catches.

## When advisor advice and primary-source evidence conflict

If the skill has retrieved primary-source evidence that points one way (file says X, command output shows Y) and the advisor points another, do **not** silently switch. Surface the conflict in one more advisor call: "I found X, you suggest Y, which constraint breaks the tie?". The advisor saw the evidence but may have underweighted it; a reconcile call is cheaper than committing to the wrong branch. A passing self-test is not evidence the advice is wrong — it's evidence the test doesn't check what the advice is checking.

## How `/skill-audit` applies these rules

`advisor-coverage-reviewer` evaluates an audited skill's `advisor()` call sites against the criteria above and may flag:

| Finding kind | Severity | Trigger |
|---|---|---|
| Missing pre-substantive-edit advisor | high | Skill dispatches subagents that mutate user code (Phase 5 / dispatch points) without an advisor call gating the dispatch. |
| Missing declare-done advisor on non-trivial work | medium | Skill renders a final report after a multi-phase run with no advisor checkpoint anywhere. |
| Missing stuck-loop advisor | medium | Skill has a retry-with-max-retries loop with no advisor call in the max-retries-exhausted branch. |
| Missing single-fire guard | high | A retry-loop advisor call is placed inside the loop body without a `phaseNAdvisorFired` boolean (or equivalent), causing the call to re-fire every iteration. |
| Unconditional advisor on every run | medium | An advisor call fires on every invocation regardless of finding volume, dimension skew, or iteration depth — wastes budget on small / clean runs. |
| Mode-gating mismatch | medium | An advisor that should fire only in a specific mode (e.g., `--merge`) fires unconditionally, or vice versa. |
| Conflict-reconcile pattern absent | low | Skill silently overrides advisor advice when its own data conflicts, without a reconcile call. (Hard to detect statically — speculative confidence by default.) |

Each finding from `advisor-coverage-reviewer` MUST cite (a) the line in the audited skill and (b) the rule above the finding violates (e.g., `shared/advisor-criteria.md:<line>`).

## Last verified

`2026-05-09` — Anthropic's advisor tool description (verbatim text in this conversation's system prompt) was the source. Re-verify against the current Claude Code release notes (see `https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md`) when this file is more than 90 days old. Stale advisor criteria silently mis-rate skills.
