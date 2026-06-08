# File-overlap check — `/jr-ship`

**Canonical source** for `/jr-ship`'s post-create *File-overlap warning*. `jr-ship/SKILL.md` reads this file into lead context at Phase 1 (under the hard-fail + smoke-parse guard, alongside `ci-failure-handling.md` and the `shared/*.md` files) and applies it at Phase 3a step 11a and Phase 3b step 10a-multi. Update here to update the procedure.

The check is **informational only** — it never blocks the merge, never asks the user a question, never returns a non-green outcome. Any failure to compute (gh error, jq error, gh too old) is logged with a one-line `Overlap check skipped: <reason>` and execution continues to the caller's next step.

**Forge note:** the `gh pr view`/`gh pr list --json …` commands below are the GitHub reference form. On GitLab (`FORGE=gitlab`, see `../../shared/forge-detection.md`) they map to `glab mr view`/`glab mr list -F json`, but the jq filters here assume gh-shaped field names (`.files[].path`, `.number`, `.title`, `.isDraft`, `.updatedAt`) — remap them to glab's `-F json` field names (forge-detection.md §c, confirmed against a live GitLab MR at implementation). Since the check is informational only, if the GitLab field mapping is not yet confirmed, log `Overlap check skipped: forge field mapping unconfirmed` and fall through rather than guessing.

## Inputs

- `PR_NUMBER` (single-PR mode only): the PR number (MR iid on GitLab) created in Phase 3a step 11.
- `BATCH_PR_NUMBERS`: JSON array of PR numbers that should be excluded from the open-PR scan — the PRs created in this `/jr-ship` invocation. Single-PR mode passes `[PR_NUMBER]`; multi-PR mode passes every sub-PR number from step 10-multi. Used so the batch's own splits do not flag each other (their splits are intentional per Phase 2).

## Procedure

### 1. Fetch this PR's (or the batch's) files

**Single-PR mode** (`BATCH_PR_NUMBERS` has one entry equal to `PR_NUMBER`):

```
my_files=$(gh pr view "$PR_NUMBER" --json files --jq '[.files[].path] | unique | .[]' 2>/dev/null)
```

The jq filter is `[.files[].path] | unique | .[]` rather than `... | sort -u` so the command stays inside `/jr-ship`'s `allowed-tools` (`Bash(gh pr view *)` + the in-flight `--jq` filter — no separate `sort` invocation). The output is newline-delimited and deduplicated.

**Batch mode** (`BATCH_PR_NUMBERS` has 2+ entries): build a per-sub-PR file map by calling `gh pr view --json files` once per sub-PR (same `--jq` form as above for dedup). Conceptually `{ "<num>": ["path1", "path2", ...], ... }`. The batch-mode warning attributes each open-PR overlap to the specific sub-PR(s) it intersects.

If any of these calls fails OR returns no `files` field, log `Overlap check skipped: failed to fetch files for PR #<n>` and return (the caller continues — see Outcome below).

### 2. Fetch currently-open PRs with their files

```
open_prs=$(gh pr list --state open --json number,title,isDraft,updatedAt,files --limit 100 2>/dev/null)
```

- On non-zero exit OR empty stdout: log `Overlap check skipped: gh pr list failed` and return.
- If the returned objects do not carry a `files` field (older `gh` versions that do not support `--json files` for `pr list`): log `Overlap check skipped: gh version too old for --json files on pr list; upgrade gh to enable overlap check` and return.
- If the list is empty (no other open PRs in this repo): print `Overlap check: no other open PRs in this repo. ✓` and return.

### 3. Intersect

`--argjson` expects a JSON value, but `my_files` from step 1 is newline-delimited bash text. Convert it first:

```
MY_FILES_JSON=$(printf '%s\n' "$my_files" | jq -R . | jq -s .)
```

(In batch mode, do the same per sub-PR and assemble the `{ "<num>": [...] }` object via jq.)

Then a single jq pass excludes `BATCH_PR_NUMBERS` and keeps PRs with non-empty file intersection:

```
echo "$open_prs" | jq --argjson batch "$BATCH_PR_NUMBERS" --argjson my "$MY_FILES_JSON" '
  [.[]
   | select((.number as $n | $batch | index($n)) | not)
   | {number, title, isDraft, updatedAt,
      overlap: ([.files[].path] | map(select(. as $p | $my | index($p))))}
   | select(.overlap | length > 0)]
'
```

In batch mode, the filter additionally records which sub-PR each matched path came from so the display block can attribute it correctly.

- Empty result → print `Overlap check: no open PRs touch overlapping files. ✓` and return.
- Non-empty → emit the warning block (Step 4).

### 4. Display the warning

Use the phase-header convention from `../../shared/display-protocol.md`:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 FILE-OVERLAP WARNING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Currently-open PRs that touch overlapping files:

  #38 "Refactor auth module" (open, updated 3d ago):
    src/auth/session.ts
    src/auth/index.ts

  #51 "Fix login redirect" (DRAFT, updated 1d ago):
    src/auth/session.ts

These PRs touch the same files as PR #<n>. Once one merges, the others will
need rebase, and semantic conflicts may slip past CI. Consider coordinating
merge order or reviewing the other PRs before proceeding.
```

In batch mode, replace the trailing paragraph with `These PRs touch the same files as one or more sub-PRs in this batch (#<n1>, #<n2>, ...)` and prefix each path line with the sub-PR number that owns the overlap: `    src/auth/session.ts (in #42)`.

PR titles are stripped of control characters before display (per the `../../shared/display-protocol.md` console-redaction rule). File paths are printed verbatim — they are never interpolated into any shell command.

`updatedAt` is rendered as a relative timestamp (`3d ago`, `5h ago`, `2w ago`). If the relative-time conversion fails, fall back to the raw ISO-8601 date.

If the `gh pr list --limit 100` call returned exactly 100 PRs, append this note after the warning block (or after the success line, whichever applies):

```
(showing first 100 open PRs; repos with more may have additional overlap)
```

## Outcome returned to the caller

- **Always success / always informational**. The check never returns an outcome that would cause the caller to halt or branch. Every documented failure mode logs a one-line `Overlap check skipped: <reason>` and falls through. The caller — Phase 3a step 12 (single-PR) or Phase 3b step 11a-multi (multi-PR) — runs next regardless.

## Out of scope (v1)

- **Function/symbol-level overlap** via `codebase-memory-mcp` `trace_path`. A future iteration could intersect *symbols* touched by both diffs instead of file paths — useful for detecting hot-spot files where the file-path intersection over-fires. Requires both diffs to be index-able, so out of scope for v1.
- **`--dry-run` "what-if" overlap** computed from the working-tree diff vs base. `--dry-run` exits at Phase 2 step 5 before any PR is created, so step 11a never runs in v1.
- **Rename tracking**. If PR A renamed `foo.ts` → `bar.ts` and PR B modifies `foo.ts`, the file-path intersection will miss the overlap. Out of scope for v1.
- **Cross-base awareness**. A PR targeting `develop` and one targeting `main` that share files are still flagged — the user judges relevance from the displayed `(open, updated 3d ago)` line and the title.
- **Many-overlap display collapse**. If a hot-spot file (e.g., `.github/workflows/ci.yml`, `package.json`, `tsconfig.json`) is touched by 5+ open PRs, the warning lists each overlap individually and the noise drowns the signal. A future iteration could cap display at N=5 PRs per overlapping file with a "(M more PRs also overlap on this file)" tail, or collapse common files to a per-file summary line. Out of scope for v1; if it shows up in practice, drop into `gh pr list --search 'is:open <file>'` manually.
