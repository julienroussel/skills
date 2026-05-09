# Phase 3 Step 0 — Finding Sanity-Check (Reject Hallucinations)

**Canonical procedure** for validating reviewer findings before dedup. Referenced by `review/SKILL.md` Phase 3 step 0.

## What every reviewer was required to submit (per finding)

`file`, `line`, and a `codeExcerpt` — 3 consecutive lines from the cited file starting at `line`, verbatim with original whitespace.

## Validation procedure

For each finding, verify the citation is real. Run **all checks in parallel** via batched Bash (single multi-call message):

1. **File-existence check**:
   - Working-tree mode and branch mode: `file` must exist on disk.
   - `--pr` mode: `file` must appear in the PR's changed-files list (from `gh pr view --json files` at Phase 1 PR mode) OR be a local consumer file flagged by cross-file impact analysis.

2. **Line validity**: `line` must be a positive integer not exceeding the file's line count.

3. **Content-excerpt match**: Read `file` lines `[line, line+2]` and compare against the reviewer's `codeExcerpt`. Normalize both sides before comparison: strip trailing whitespace per line; collapse any run of blank lines to a single blank; treat tabs and spaces as equivalent when the only difference is indentation. If no line in `[line, line+2]` matches any line in the excerpt after normalization, reject the finding.

## Source-of-truth by mode

- **Working-tree mode** and **branch mode**: read from the local file via the Read tool. Branch mode is safe for local Read because the Phase 1 behind-upstream guard aborts when local HEAD lags upstream, so the local working tree reliably reflects HEAD plus uncommitted edits at dispatch time.

- **Branch-mode caveat — uncommitted edits to committed-on-branch hunks**: in branch mode, the diff fed to reviewers includes the committed-on-branch segment (`git diff "$mergeBase"..HEAD`) whose line numbers are HEAD-relative, but the working tree may have unrelated uncommitted edits that have shifted those lines. Reviewers are instructed to read the `codeExcerpt` from the local working-tree file (not from the diff hunk), so the displacement is naturally absorbed. If a reviewer cites a HEAD-relative line and the working tree has displaced it, the codeExcerpt will not match and the finding will be rejected — which is the correct behavior, because the committed change has been further edited and the original cite no longer applies.

- **`--pr` mode**: read from the PR's post-image (the file as it appears in the PR's head commit), NOT the local checkout. Fetch the PR snapshot metadata once at Phase 1 PR mode setup:

  ```bash
  gh pr view <N> --json headRefOid,baseRepository -q '.headRefOid + "\t" + .baseRepository.owner.login + "\t" + .baseRepository.name'
  ```

  Split into `prHeadSha`, `prOwner`, `prRepo` (tab-delimited so repo names with hyphens stay intact). Cache `tmpDir=$(mktemp -d -t review-pr-snap.XXXXXX)` for the run.

  For each unique file cited in PR mode, URL-encode the path:
  ```bash
  encodedPath=$(printf '%s' "$file" | jq -sRr @uri)
  gh api "repos/$prOwner/$prRepo/contents/$file?ref=$prHeadSha" \
    -H 'Accept: application/vnd.github.raw' > "$tmpDir/$encodedPath"
  ```

  Read excerpt lines from `$tmpDir/$encodedPath` instead of the local file. If `gh api` returns 404 for a file the reviewer cited (file is in `gh pr view --json files` but contents fetch fails — typically a renamed file where the reviewer cited a stale path), reject the finding under `[REJECTED — INVALID CITATION]` reason `pr-file-fetch-failed`.

## Dedup-by-file optimization

Many findings cluster in the same file. Build a set of unique `(file, min-line, max-line)` tuples first, fetch each unique file once (batching all unique fetches into a single message in parallel with the Bash checks), cache the content, then derive each finding's excerpt range from the cached content.

## Cross-file consumer carve-out

A finding may cite a file OUTSIDE the PR's changed-files list when it's a cross-file impact flagged by `trace_path` (graph-backed) or grep against a changed export. For those findings, fall back to reading the local working-tree file (the consumer is unmodified by the PR so working-tree and PR-base agree). Detect by checking whether `file` is in the cached `gh pr view --json files` list; if NOT in the list, run the excerpt match against the local file via Read instead of `gh api`.

## Temp-dir cleanup

On Phase 7 entry, `rm -rf "$tmpDir"` regardless of abort mode (it's just a snapshot cache).

## Rejection logging

If the excerpt is missing or empty, treat as hallucination evidence and reject. Log each rejection under `[REJECTED — INVALID CITATION]` with:
- the reviewer's dimension name
- the cited `file:line`
- the reason: one of `missing-file`, `bad-line`, `line-out-of-range`, `excerpt-missing`, `excerpt-mismatch`, `pr-file-fetch-failed`
- For `excerpt-mismatch`: a 2-line diff showing what the reviewer claimed vs what the file actually contains.

Include all rejections in the Phase 7 report. Track the rejection rate per reviewer dimension; if a single reviewer exceeds 25% rejection, emit a Phase 7 `ACTION REQUIRED` note.

## Why this catches subtler hallucinations than line-range alone

A reviewer that fabricates a problem description but cites a real line number passes a line-range check. The content-excerpt match additionally requires that the reviewer could actually quote the line — if they couldn't quote it, they probably couldn't read it.
