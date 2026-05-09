# Phase 8 — Follow-up issue tracking

**Canonical procedure** for `/review` Phase 8. Referenced by `review/SKILL.md` Phase 8. Loaded at Phase 1 Track A under the same hard-fail + smoke-parse discipline as the other protocol files.

## When to run / skip

**Skip if `quick` is set. Skip if `nofix` is set AND `--pr` is NOT set** — in nofix-without-PR mode, the user chose findings-only and doesn't want follow-up issues. But in PR mode, Phase 8 posts findings as a PR comment, which is the primary output.

**Run this phase if**: (1) `--pr` mode is active (always — to comment findings on the PR), OR (2) there are findings that were user-approved but intentionally NOT implemented (architectural issues too large for auto-fix, contested findings). User-rejected findings are NOT candidates.

**Headless/CI mode** (when `isHeadless` is `true` — see `../../shared/secret-scan-protocols.md` → "Headless/CI detection" for the canonical predicate, including the full CI env var list and `--auto-approve` short-circuit): Skip Phase 8 issue creation — do not create GitHub issues without explicit per-run human consent. **Exception**: if `--pr` is set, still post the consolidated PR comment (the user explicitly provided a PR number, implying consent to comment on that PR). Apply report redaction to the PR comment body before posting. Note any skipped candidates in the Phase 7 report under "Skipped" so the operator can review them. Rationale: Phase 8 creates externally visible artifacts (GitHub issues, PR comments) that may expose file paths, line numbers, and vulnerability descriptions. Auto-creating these in CI could publish internal findings on public repositories without the operator's consent.

## Step 1: Fetch existing issues

Run `gh issue list --state open --json number,title,state,labels --limit 200` to get all open issues (not just `review-followup` — the user may have relabeled follow-up issues manually).

## Step 2: Deduplicate against existing issues

For each skipped finding, check if **any open issue** already covers it — regardless of its labels. Apply a **deterministic-first matching policy**:

1. **Structural match (required first pass).** A candidate finding matches an existing issue if ANY of the following is true:
   - **File-path + line-range overlap**: the finding and the issue reference the same file path AND their line ranges overlap within ±5 lines.
   - **Shared exported symbol**: the finding and the issue reference the same function, class, type, or other exported symbol name (extracted from the finding description / issue title/body).
   - **Shared `category` field**: the finding and the issue share the same `category` value (one of the enum values defined in the `priorFindings` schema — `missing-null-check`, `injection-risk`, `silent-failure`, etc.).
2. **Free-text / semantic similarity (tie-breaker only).** Semantic similarity of titles and descriptions may ONLY be used as a tie-breaker when a candidate has a structural match against multiple open issues (to pick the best one) — NOT as a primary match criterion. A candidate with zero structural matches is `new` regardless of textual similarity.

**Dedup decision logging (required)**: Every dedup match decision MUST be logged to the Phase 7 report under a new "Dedup decisions" subsection rendered in the Phase 8 area of the report (see `phase7-cleanup-report.md` report item 8). Emit one line per decision in the form:

- `<candidate> → matched #<N> because <reason>` (reason is one of `file+line overlap`, `shared symbol: <name>`, `shared category: <value>`, or `semantic tie-breaker over #<other>`)
- `<candidate> → new (no structural match found)`

This log is the audit trail a human can use to validate why a finding was treated as a duplicate and is required even in headless/CI mode.

## Step 3: Identify candidates for new issues

From the skipped findings, keep only those that:
1. Are **not already tracked** by any existing open issue
2. Have severity **medium or higher**
3. Are **actionable** — there is a concrete fix or investigation path (not just an observation)

If no candidates remain, output `No new follow-up issues needed — all skipped findings are already tracked or too low priority.` and skip to the end.

## Step 4: Present candidates to user

Show each candidate with a one-line summary, then use AskUserQuestion as a menu:

- **Create all** — create GitHub issues for all candidates
- **Review individually** — present each candidate one by one via AskUserQuestion menus (create / skip per candidate)
- **Skip all** — do not create any issues

## Step 5: Create approved issues

For each approved candidate:

**Public repository check** (PR mode only): Before posting findings as PR comments, check the **target repository's** visibility — NOT the local checkout's. `gh repo view --json visibility` reads the current-repo config, which is incorrect when the PR originates from a private fork against a public upstream; that path would return `PRIVATE` and leak security findings unredacted to the public upstream. Resolve the target repo first: `target=$(gh pr view <number> --json baseRepository -q '.baseRepository.owner.login + "/" + .baseRepository.name')`, then query visibility: `visibility=$(gh repo view "$target" --json visibility -q '.visibility')`. If the PR targets a different repo than the local checkout (e.g., fork → upstream), elevate the visibility check to the target repo and, in interactive mode, require explicit consent via AskUserQuestion before posting any findings: 'PR target repository (`$target`, visibility: `$visibility`) differs from the local checkout. Post findings to the target? Options: [Post all findings] / [Omit security findings] / [Skip PR comment]'. In headless/CI mode with a cross-repo PR, default to skipping the PR comment entirely and note the skip in the Phase 7 report. If the target repository is `PUBLIC` and any findings have dimension `security`, warn in interactive mode via AskUserQuestion: 'Target repository is public. Security findings in PR comments will be publicly visible. Options: [Post all findings] / [Omit security findings from comment] / [Skip PR comment]'. In headless/CI mode, automatically omit security-dimension findings from the PR comment body and append a note: 'N security finding(s) omitted from this public PR comment — see the local review report for details.'

**In PR mode** (`--pr`): Use `gh pr comment <number>` to post a **single consolidated comment** on the PR with all findings formatted as a checklist. Do not create one comment per finding. Before posting, redact any strings matching the canonical pattern catalog from `../../shared/secret-patterns.md` from the comment body. Replace with `[REDACTED]`.

**In normal mode**: Run `gh issue create --label review-followup` with:
- A concise title describing the problem and desired outcome
- A body containing: Context (which review, date), Problem description, Affected files, Suggested fix, and Priority
- **Sanitize the title and body**: Before creating, redact any strings matching the canonical pattern catalog from `../../shared/secret-patterns.md` in both the title and body. Replace with `[REDACTED]`.

## Display

Output a compact summary:
```
Phase 8 — Follow-up issues
  Existing:  4 open issues checked
  Skipped:   11 findings checked
  Duplicates: 9 already tracked
  Created:   2 new issues (#46, #47)
```
