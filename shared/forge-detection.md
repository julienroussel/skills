# Forge Detection (GitHub `gh` ↔ GitLab `glab`)

**Canonical source** for (1) which CLI drives the **user's own repo** — `gh` for GitHub, `glab`
for GitLab — and (2) the `gh`↔`glab` command, JSON-field, and terminology mapping applied at every
user-forge call-site. Read at Phase 1 by `/jr-ship` (inline), `/jr-review` and `/jr-audit` (Track A,
under the hard-fail + smoke-parse guard in `phase1-track-a-protocol.md`); `/jr-doctor` Group D
smoke-parses it. The companion shell CLIs (`bin/tackle`, `bin/tackle-top`) cannot read this file at
runtime — they implement the same detection natively and MUST stay in sync with it.

**Scope.** Detection is a **gitlab.com-only hostname heuristic** (no self-hosted/Enterprise
auth-probe ladder). The `CLAUDE_FORGE=github|gitlab` env var is an explicit override for testing or
ambiguous hosts.

**Out of scope (do NOT forge-switch): external-authority fetches.** A `gh api …/contents/…` (or any
fetch) that targets a *fixed external* repo — Anthropic's `anthropics/claude-code`, a framework's
docs/changelog — to verify an external-authority claim STAYS `gh` regardless of the user's forge. It
is not about the user's repo. See section (e).

---

## (a) Detection algorithm

Compute **once per run**, before the first forge-dependent call. Precedence: `CLAUDE_FORGE`
override → origin-host heuristic → default `gh` + warning. (In `bin/tackle`, a forge parsed from an
explicit PR/MR **URL argument** outranks both — a gitlab.com URL cannot be served by `gh`.)

```bash
# Parse the host from origin, covering SCP (git@HOST:owner/repo.git),
# https://HOST/..., and ssh://git@HOST[:port]/... forms. POSIX sed only (no Perl \b).
forge_host() {
  git remote get-url origin 2>/dev/null \
    | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#[:/].*$##'
}

case "${CLAUDE_FORGE:-}" in
  github) FORGE=github; CLI=gh ;;
  gitlab) FORGE=gitlab; CLI=glab ;;
  *) host=$(forge_host)
     case "$host" in
       github.com|github.*) FORGE=github; CLI=gh ;;
       gitlab.com|gitlab.*) FORGE=gitlab; CLI=glab ;;
       *) FORGE=github; CLI=gh
          echo "Forge auto-detect: unknown host '${host:-none}' — defaulting to gh. Set CLAUDE_FORGE=gitlab to override." >&2 ;;
     esac ;;
esac
```

The warning string `Forge auto-detect:` is load-bearing (smoke-parse anchor). The default-to-`gh`
branch never silently degrades: it always prints the one-line warning naming the unknown host.

**Experimental advisory (when `FORGE=gitlab`).** Until the §(c) `-F json` field names are confirmed
against a live gitlab.com MR/issue (Milestone 2), every consumer that will perform a **user-repo glab
op** MUST surface a single one-line advisory before the first such op — e.g. *"GitLab support is
experimental (pre-Milestone-2): glab field mappings are unverified — output may be incomplete."*
Auto-detection stays on (you cannot verify M2 without exercising the path, and `CLAUDE_FORGE`
overrides), but the user is told the path is unverified rather than left to debug a confusing
partial failure. Skills that make **no** user-repo glab op (e.g. `/jr-audit`, whose sole `gh` use is
the external-authority carve-out) do not emit it.

**Ordering note (multi-track Phase 1):** if a skill's parallel Phase-1 batch already contains a
forge-dependent call (e.g. `/jr-ship`'s default-branch `gh repo view`), detection MUST run *before*
the batch and that call MUST be sequenced out of it — you cannot gate an in-batch call on in-batch
detection (they race).

---

## (b) Command equivalence table

Operation | GitHub (`gh`) | GitLab (`glab`) | Notes
---|---|---|---
auth status | `gh auth status` | `glab auth status` | exit-code check
default branch | `gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name'` | `glab api projects/:fullpath \| jq -r .default_branch` | field TBD; `glab api` has NO `--jq` (pipe to jq); both fall back to `git symbolic-ref --short refs/remotes/origin/HEAD`
repo visibility | `gh repo view --json visibility` | `glab api projects/:fullpath \| jq -r .visibility` | field TBD
create PR/MR | `gh pr create --title T --body B [--label L] [--assignee @me] [--draft]` | `glab mr create -t T -d B [-l L] [-a @me] [--draft] [-b BASE] [--remove-source-branch] -y` | flags verified
view PR/MR | `gh pr view N --json <fields>` | `glab mr view N -F json --jq <remap>` | fields verified §c (`--pr` subset)
list PR/MR | `gh pr list --head BR --state open --json <fields>` | `glab mr list --source-branch BR -F json` | fields TBD; `--head`→`--source-branch`
diff | `gh pr diff N --no-color` | `glab mr diff N --color=never` | `--color=never` (glab defaults to `--color=auto`) is the `--no-color` equivalent — without it, piped output may be colorized
merge | `gh pr merge N --squash --delete-branch` | `glab mr merge N --squash --remove-source-branch --auto-merge=false -y` | **`--auto-merge=false` is REQUIRED** — glab enables merge-when-pipeline-succeeds by default, so without it the MR does NOT merge immediately like `gh pr merge` does (flags --help-verified)
edit base | `gh pr edit N --base BR` | `glab mr update N --target-branch BR` | flags --help-verified
comment | `gh pr comment N --body B` | `glab mr note N -m B` |
issues list | `gh issue list --state open --json <fields>` | `glab issue list -O json` | fields TBD; **`glab issue list` is the lone exception — JSON is `-O json`, NOT `-F json`** (its `-F` is `--output-format`=details/ids/urls). Open is the default — there is **no `--state` flag** (`-c`/`--closed`, `-A`/`--all` change it)
issue create | `gh issue create --title T --body B [--label L]` | `glab issue create -t T -d B [-l L] [-y]` | flags verified
**CI watch** | `gh pr checks N --watch --fail-fast` | `glab ci status --live -b BR` | **ADAPTATION, not a rename** — see (e). `-F json` is incompatible with `--live` (parse text status, or do a separate non-live call for JSON)
**CI failed logs** | `gh run list …` + `gh run view ID --log-failed` | `glab ci status` + `glab ci trace`/`glab ci get` | **ADAPTATION** — multi-job
**user-repo raw file @ref** | `gh api "repos/{owner}/{repo}/contents/{path}?ref={sha}" -H 'Accept: application/vnd.github.raw'` | `glab api "projects/{url-encoded-project}/repository/files/{url-encoded-path}/raw?ref={sha}"` | **STRUCTURAL** — project path AND file path URL-encoded (`jq -sRr @uri`), no raw header; ✅ verified 2026-07-10 (explicit encoded project, subgroup + nested path OK)
generic api | `gh api <path>` | `glab api <path>` | `repos/{owner}/{repo}/…` → `projects/:fullpath/…`; MRs/issues keyed by `iid`

**Two separate verification problems — do NOT conflate them** (conflating them is what let a `--jq`
flag bug hide in the "can't verify yet" bucket):
- **Flags / interface — verifiable NOW via `--help`, no auth or live repo needed** (glab 1.102.0).
  Confirmed: `mr create/view/list/merge/update/diff/checkout/note`, `issue create/list`, `ci status`,
  `repo view`, plus the gotchas baked into the table above (`--auto-merge=false` on merge, `--color=never`
  on diff, `glab api` has no `--jq`, `-F json` ≠ `--live` on `ci status`). **When adding a new glab command
  to this table, run its `--help` first** — a wrong flag in this canonical table propagates everywhere.
- **`-F json` field names — genuinely need a live gitlab.com MR/issue** (see (c)). These can't be read from
  `--help` (gh emits camelCase, glab emits its own struct) and stay implementation-time TBD.

> **Verified flag note (glab 1.102.0):** `glab mr view|list`, `glab issue view`, and `glab repo
> view` accept `-F json --jq '<expr>'` (built-in jq filter, like `gh --json --jq`). **`glab issue list`
> is the exception** — it puts JSON under `-O/--output` and reuses `-F` for `--output-format`
> (`details`/`ids`/`urls`), so use `-O json` (it still supports `--jq`). **`glab api` does
> NOT** accept `--jq` — it has only `--output json|ndjson`, so pipe its raw output to external `jq`
> (`glab api <path> | jq -r '<expr>'`), never `glab api … --jq`.

---

## (c) JSON-field mapping table (`--pr` subset verified 2026-07-10; the rest still Milestone-2, do NOT assert from memory)

`gh --json` emits gh's own camelCase (`headRefName`, `isDraft`) — NOT raw GitHub API fields. `glab
-F json` emits the raw GitLab REST object, which **cannot be verified from a GitHub-only repo**. The
rows the `/jr-review --pr` path consumes are now **confirmed against a live gitlab.com MR**
(`ecorobotix/maya/web!4151`, 2026-07-10); every remaining `_?_`/TBD cell must still be confirmed
against a real MR/issue before use. Listed below are exactly the gh fields the call-sites consume.

Purpose | gh field | glab field | Status
---|---|---|---
head branch | `headRefName` | `.source_branch` | ✅ verified 2026-07-10 (MR !4151)
head commit SHA | `headRefOid` | `.sha` (== `.diff_refs.head_sha`) | ✅ verified 2026-07-10 (MR !4151)
base repo owner / name | `baseRepository.owner.login` / `.name` | not consumed for `--pr` (route from `TARGET_PROJECT`; `.project_id` / `.references.full` exist if needed) | n/a
draft state | `isDraft` | `.draft` (or `.work_in_progress`) | ✅ verified 2026-07-10 (MR !4151)
review decision | `reviewDecision` | _?_ (GitLab approvals — likely derived, no 1:1) | TBD (unconsumed)
merge state | `mergeStateStatus` | _?_ (GitLab `detailed_merge_status`?) | TBD (unconsumed)
default branch | `defaultBranchRef.name` | _?_ (`default_branch`?) | TBD (branch-mode)
visibility | `visibility` | `.visibility` (on the project object, per §b; not live-probed) | TBD
changed files | `files[].path` | `GET …/merge_requests/:iid/diffs` → `.[].new_path` (NOT in `mr view`; also `.old_path` / `.deleted_file` / `.renamed_file`) | ✅ verified 2026-07-10 (MR !4151, 95 files)
number / iid | `number` | `.iid` | ✅ verified 2026-07-10 (MR !4151)
title / body | `title` / `body` | `.title` / `.description` | ✅ verified 2026-07-10 (MR !4151)
updated time | `updatedAt` | `.updated_at` | TBD (unconsumed)
CI run id / result | `databaseId` / `conclusion` | _?_ | TBD (unconsumed)

---

## (d) Terminology map

GitHub | GitLab
---|---
pull request (PR) | merge request (MR)
PR number `#N` | MR iid `!N` (issues `#N`) — **separate iid namespaces** on GitLab
checks / CI run / GitHub Actions | pipeline / job / GitLab CI
`--delete-branch` | `--remove-source-branch`
`--base` | `--target-branch`
`--head` (list filter) | `--source-branch`
`repos/{owner}/{repo}` | `projects/:fullpath` (or `:id`)

User-facing output (logs, summaries, prompts) should use MR / pipeline / iid vocabulary when
`FORGE=gitlab`.

---

## (e) Per-site application rule + graceful degradation

- **Branch on `$FORGE` at each user-forge call-site.** Detection runs once (section a); never
  re-detect mid-run.
- **External-authority carve-out (critical).** The discriminator for any `gh api …/contents/…` is
  *what the owner/repo operand resolves to*. The user's **own** repo (`$prOwner/$prRepo`, the local
  origin) → switch with `$FORGE`. A **fixed external** authority (`anthropics/claude-code`, a
  framework's docs repo) → **stay `gh`** even on a GitLab user-repo; only reach for `glab api` when
  that authority is itself gitlab-hosted. Same command shape, opposite disposition.
- **CI is reimplemented, not renamed.** GitHub checks attach to a *PR*; GitLab pipelines attach to a
  *branch/commit*, and a pipeline has multiple jobs. Port the control-flow — the wait timeout, the
  "no pipeline yet → proceed" short-circuit, pass/fail detection, and per-job failed-log fetch — do
  not token-swap the command. **Top Milestone-2 verification (silent-failure risk, distinct from the
  cosmetic field renames — check this FIRST):** confirm `glab ci status --live`'s *exit code* reflects
  pipeline pass/fail; if it exits 0 regardless of outcome, `/jr-ship`'s CI-failure loop never fires on
  GitLab — a green-washed failure that GitHub would have caught.
- **Graceful-degradation gaps:**
  - `gh issue develop` (branch linked to an issue) has **no `glab` equivalent** → on GitLab, fall
    back to a plain local branch off the default branch and skip the link.
  - **`iid` vs number ambiguity.** A GitLab issue `#5` and MR `!5` coexist (separate namespaces);
    GitHub's number space is shared. When a bare number is ambiguous, prefer the URL and disambiguate
    by resource type.
  - **Inline review comments** use GitLab's notes model (optional diff position; many notes are
    positionless) → fold into a general "Discussion" rather than forcing per-line mapping.
- **allowed-tools.** Each consuming skill mirrors its existing `gh` posture into `glab` entries —
  mirror both what is allowlisted and what is deliberately withheld (a skill that keeps `gh pr
  comment` out of its allowlist keeps `glab mr note` out too).
