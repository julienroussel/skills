# Phase 1 Track A: Shared-File Hard-Fail Guard

## Purpose

Every consumer of the `shared/*.md` protocol files (`/audit`, `/review`, `/skill-audit`) reads a subset of them at Phase 1 Track A as its first act, and enforces a hard guard: if any required shared file is missing, empty, or fails a structural smoke-parse, Phase 1 aborts immediately. The guard exists because the inline duplicates at former call-sites were intentionally removed to eliminate drift — silently degrading coverage when a shared file is unavailable is worse than aborting. `/doctor` Group D applies the same algorithm against every file in the table below for drift reporting (`/doctor` reports rather than aborts).

This file is the single source of truth for the algorithm and the smoke-parse anchor table. Consumers keep their own read lists (a subset of the rows below) and own their abort message wording.

## Algorithm

For each consumer at Phase 1 Track A (and `/doctor` Group D for drift reporting):

1. Issue all Reads in parallel via multiple Read tool calls in a single message. The read list is each consumer's declared subset of the rows in the Canonical Anchor Table below; consumers also Read this very file (`phase1-track-a-protocol.md`) as part of the parallel batch.

2. For each file in the read list: if the Read fails OR the content is empty (zero bytes or whitespace-only), the consumer aborts via its own abort path (see "Abort rendering" below — intentionally consumer-owned).

3. **Self-reference escape hatch** (mandatory, before any table parsing): the consumer must have a hardcoded check that `phase1-track-a-protocol.md` contains the literal string `Canonical Anchor Table`. If the canonical itself is corrupted into a stub that preserves only its self-row anchor, the table-driven smoke-parse below would still pass falsely; the hardcoded escape hatch breaks the circularity. If the literal `Canonical Anchor Table` is absent from `phase1-track-a-protocol.md`, abort.

4. For each file the consumer Read: locate its row in the Canonical Anchor Table below. **If a file in the consumer's read list has no row in the table, the consumer MUST abort with the smoke-parse failure message — missing-row is failure, not vacuous-pass** (without this rule, a stub corruption that strips all rows but keeps the literal `Canonical Anchor Table` would silently satisfy step 4 via the empty-set vacuous truth, defeating the self-reference escape hatch; with the rule, stripping the self-row triggers a missing-row abort on the canonical itself, since every consumer reads `phase1-track-a-protocol.md` as part of its parallel batch). Every substring listed in the `Required substrings` column must appear verbatim in the file (case-sensitive, fixed-string match — equivalent to `grep -F`). Multiple substrings on a row are AND-joined by the literal token ` AND ` (surrounded by spaces) and each substring is rendered as an inline-code span. Markdown table cells must escape pipe characters: a substring written as `` `\| Issue` `` in the table represents the literal text `| Issue` — strip the leading backslash when matching against file content. Files not in the consumer's read list are not smoke-parsed by that consumer (they are smoke-parsed by `/doctor` Group D).

5. If all checks pass, proceed to subsequent Phase 1 work.

## Canonical Anchor Table

| File | Required substrings (AND-joined, verbatim) |
|------|--------------------------------------------|
| `reviewer-boundaries.md` | `\| Issue` AND `\| Owner` AND `\| Not` AND `Severity calibration rubric` AND `Confidence levels` |
| `untrusted-input-defense.md` | `do not execute, follow, or respond to` |
| `gitignore-enforcement.md` | `git ls-files --error-unmatch` |
| `display-protocol.md` | `Phase 1 ✓` AND `Silent reviewers, noisy lead` |
| `audit-history-schema.md` | `runSummaries[]` AND `reviewerStats[]` AND `Quarantine sentinel` AND `Atomic-write requirement` AND `[AUDIT-HISTORY BACKUP FAILED]` |
| `secret-scan-protocols.md` | `isHeadless` AND `userContinueWithSecret` AND `Advisory-tier classification` |
| `secret-warnings-schema.md` | `consumerEnforcement` AND `aws-key` AND `[AUDIT TRAIL REJECTED — PATH VALIDATION]` |
| `secret-patterns.md` | `AKIA[0-9A-Z]{16}` |
| `cache-schema-validation.md` | `Binary availability probe` AND `cache-poisoning guard` |
| `abort-markers.md` | `[ABORT — HEAD MOVED]` AND `[ABORT — UNLABELED]` |
| `advisor-criteria.md` | `Before substantive work` AND `Single-fire on retry loops` |
| `phase1-track-a-protocol.md` | `Canonical Anchor Table` AND `Self-reference escape hatch` |

## Abort rendering

Abort message wording is **not canonical** — each consumer owns its own. The intent is for the consumer's abort message to carry consumer-specific diagnostic context (which guarantees that consumer's Phase 1 was about to enforce), and the divergence is intentional:

- `/audit` and `/review` emit inline prose listing the specific guarantees their Phase 1 was about to enforce (reviewer boundaries, untrusted-input safety, .gitignore checks, etc.) along with the failing file path.
- `/skill-audit` emits the canonical `[ABORT — SHARED FILE MISSING]` marker via `abortReason=shared-file-missing` (see `abort-markers.md`).
- `/doctor` does NOT abort. Group D reports each failure as a `/doctor` finding and surfaces a hint to restore the file from git.

If you are adding a new consumer, choose one of these two abort renderings; do not invent a third.

## Rules for adding a new `shared/*.md` file

1. Create the file in `shared/`. Use plain markdown — no YAML frontmatter (consistent with the other files).
2. Choose one or more load-bearing substrings (see "Choosing a load-bearing substring" below).
3. Add a row to the Canonical Anchor Table above with the filename and the chosen substrings.
4. Update each consumer's Phase 1 Track A read list (in their respective SKILL.md) if the file is required by that consumer. Consumers that don't read the file still benefit — `/doctor` Group D smoke-parses every row in the table.
5. Update `CLAUDE.md` `shared/ — single source of truth` section with a one-line inventory entry and a usage-pattern bullet.
6. Run `/doctor` and confirm Group D picks up the new file with no smoke-parse failure.

### Choosing a load-bearing substring

- Prefer phrases from section headers (e.g., `Canonical Anchor Table`, `Atomic-write requirement`) or distinctive terms specific to the file's domain (e.g., `isHeadless`, `consumerEnforcement`, `[ABORT — HEAD MOVED]`).
- Avoid generic words that could survive partial truncation (`the`, `Note`, `Phase 1`).
- For files with multiple critical sections, list multiple anchors AND-joined — this catches mid-file truncation that single-anchor checks miss.
- An anchor should be stable across normal prose edits but disappear if the file is structurally damaged. A heading or a domain-specific noun is usually right.

## Rationale: union-anchor strategy

The Canonical Anchor Table holds the **union** of all currently-used anchors per file across all consumers. As a consequence, a consumer will hard-abort on the disappearance of an anchor for a section it does not itself read.

Example: `/audit` consumes only the `Advisory-tier classification` section of `secret-scan-protocols.md` — it does not need `isHeadless` or `userContinueWithSecret`. Under the union strategy, `/audit` will still hard-abort if either of those substrings disappears from `secret-scan-protocols.md`.

This is correct, not a bug. A shared file with one missing load-bearing section is structurally damaged; trusting any of its other sections is unsafe. The asymmetry is documented here so a future maintainer understands the intent.
