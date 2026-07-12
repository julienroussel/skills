# Display Protocol

**Canonical source** for the console-output rules (phase headers, timeline, silent-reviewers, compact tables, redaction). Read at Phase 1 and applied across every phase. Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section.

The rules below are skill-agnostic. **Phase 4 finding-approval displays are skill-specific** (e.g., `/jr-review`'s approve-all/critical+high/individual menu vs `/jr-audit`'s tiered Tier 1/2/3 progressive disclosure) and stay inline in each skill. **Convergence display variants** also stay in the owning skill since the iteration shape differs.

## General rule

All console output must keep the swarm readable. **Every phase**: Record the start time and output the phase header before doing anything else.

## Phase headers

Use prominent visual separators between phases:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 PHASE 3 — Deduplicate & Prioritize
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Sub-phases (e.g., 4.5) use a lighter separator: `── Phase 4.5 — Auto-learn from rejections ──`

## Running progress timeline

After each phase completes, output a single-line cumulative timeline:

```
Phase 1 ✓ (3s)  →  Phase 2 ✓ (28s)  →  Phase 3 (running...)   Total: 31s
```

Skill-specific phase numbering applies (e.g., `/jr-audit` starts at Phase 0 for preflight). The format is otherwise identical.

## Silent reviewers, noisy lead

**Reviewer and implementer agents must not output progress text.** They create finding tasks silently via TaskCreate and report completion via SendMessage. Only the **lead agent** outputs progress to the user.

Instruct every reviewer: "Do not output progress messages. Report findings only via TaskCreate. Your console output is not visible to the user."

## Compact reviewer progress table (Phase 2)

After all reviewers finish, output a single summary table instead of per-reviewer messages:

```
Phase 2 complete — 4 reviewers finished in 18s, 12 raw findings

  Reviewer            Findings  Status
  ─────────────────────────────────────────────
  typescript              5      ✓
  node-api                3      ✓
  security                2      ✓
  testing                 2      ✓
```

Use `✓` for completed, `⏱` for a reviewer that ended before finishing all its files (partial findings still included). While reviewers are running, output at most one interim update per 30 seconds: `Phase 2 — Reviewing... 2/4 complete, ~7 findings so far (12s)`.

## Phase 5/6 compact display

For implementers:

```
Phase 5 — 3 implementers dispatched (strict file ownership)
Phase 5 complete — 12/13 findings addressed, 1 contested (19s)
```

For validation:

```
Phase 6 — Validating...
  lint:      ✓ pass (0 new issues)
  typecheck: ✓ pass (0 new errors)
  test:      ✓ pass (42/42)
```

## Console output redaction

**Interactive mode**: Apply the secret pre-scan patterns from `/jr-review` Phase 1 Track B step 7 (the canonical pattern set used by both skills) **line-by-line** to all console output derived from reviewed files, agent responses, validation tool output, finding descriptions, contested finding messages, implementer error messages, or code excerpts. Replace matches with `[REDACTED]`. Line-by-line application bounds regex evaluation time and prevents pathological backtracking on large outputs.

**Headless/CI mode**: Where the skill supports headless/CI mode (currently `/jr-review` only — `/jr-audit` is interactive-only as of this writing), apply the redaction universally to ALL console output, not just content derived from reviewed files. Build logs in CI may be publicly accessible. Skills that add headless support later MUST adopt this universal-redaction rule.

Phase 7's report redaction remains the final safety net, but earlier redaction prevents secrets from appearing in real-time console output.
