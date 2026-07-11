# PR/MR URL Mode (`/jr-review --pr=<url>`)

**Canonical procedure** for parsing a full GitHub PR / GitLab MR **URL** passed to `--pr`, pinning the forge from the URL host, and enforcing the same-repo guard. Read into lead context at Phase 1 **only when the `--pr` value contains `://`** (mirrors the conditional `branch-mode.md` read under `--branch`), and applied **before forge detection and any tracks fire** (the URL host pins `FORGE`, which the forge-detection step and every PR-mode call consume). Referenced by `jr-review/SKILL.md` Phase 1 "PR mode". Smoke-parse anchors enforced at the read site: `Parse the forge URL` AND `Same-repo guard`.

A bare-integer `--pr=<N>` never triggers this file; `SKILL.md` handles it directly (current-repo iid, `remote=false`). This procedure runs only for a URL value and produces `FORGE`, `TARGET_PROJECT`, `iid`, and `remote` for the PR-mode phases. The parser mirrors `bin/tackle` (the companion CLIs re-implement the same logic natively and MUST stay in sync); the shell below is the reference form.

## Parse the forge URL

Match the `--pr` value against the two recognized shapes; reject anything else. Both regexes are unanchored at the tail, so `?query`, `#anchor`, and a trailing `/` are harmlessly ignored.

- **GitHub** (`bin/tackle:1697`): `^https?://github\.com/([^/]+/[^/]+)/(pull|issues)/([0-9]+)` → `TARGET_PROJECT`=group 1 (exactly `owner/repo`), `type`=group 2, `iid`=group 3, `FORGE=github`.
- **GitLab** (`bin/tackle:1711`): `^https?://gitlab\.com/(.+)/-/(merge_requests|issues)/([0-9]+)` → `TARGET_PROJECT`=group 1 (nested `group[/subgroup…]/project`; greedy `(.+)` backtracks to the sole `/-/`), `type`=group 2, `iid`=group 3, `FORGE=gitlab`.
- **Neither** → abort: `Invalid --pr URL: expected a github.com PR (…/pull/N) or gitlab.com MR (…/-/merge_requests/N) URL, or a bare integer.`

**Reject issue URLs**: if `type` is `issues`, abort: ``--pr reviews a merge/pull request, not an issue. On GitLab, issue #N and MR !N are separate iid namespaces (../../shared/forge-detection.md §d).`` `/jr-review` reviews a diff; an issue has none.

**Validate `TARGET_PROJECT`** through the same allowlist `bin/tackle`'s `_validate_owner_repo` (`bin/tackle:67-93`) enforces before a repo path flows into `-R` / `glab api projects/…` / log output: **first reject the whole value if it contains any control char** (do this BEFORE splitting, because the `IFS='/' read` split truncates at a newline, so a per-segment check alone would miss anything after an embedded newline, per `bin/tackle:73-76`); then split on `/`, require ≥2 non-empty segments, and reject any segment that equals `..`, contains `..`, or fails `^[A-Za-z0-9_.][A-Za-z0-9_.-]*$`. The leading-character class is load-bearing: it rejects a leading `-` (flag injection into `-R`) and `%` (pre-encoding smuggle into `projects/…`). On failure abort: `Invalid project path parsed from URL; must be a valid owner/repo (GitHub) or namespace/project (GitLab) path.`

**FORGE precedence (load-bearing).** The URL host pins `FORGE` and **overrides both `CLAUDE_FORGE` and the origin-host heuristic**: a gitlab.com URL cannot be served by `gh`, and an off-repo run from a GitHub (or origin-less) directory would otherwise mis-detect `FORGE` from the local origin and run `gh` against a GitLab MR. Precedence: **URL-pin > `CLAUDE_FORGE` > origin-host** (mirrors the pin at `bin/tackle:1701/1717` and the honor at `bin/tackle:1738-1740`). Apply this pin before `SKILL.md`'s **Detect the forge** step (Phase 1 Pre-checks) computes `FORGE`.

## Same-repo guard

Decide whether the MR lives in *this* repo (`remote=false`, full-fidelity review) or elsewhere (`remote=true`, off-repo, cross-file analysis degraded).

1. **Extract the origin host + path** (a generic, host-agnostic reimplementation; note `build_forge_url` at `bin/tackle:786-790` is gitlab.com-anchored with no port-strip step, so this is a different sed). Do NOT use `forge_host()` (`../../shared/forge-detection.md:30-33`), which deliberately strips the path. Handles SCP (`git@host:owner/repo.git`), `https://…`, and `ssh://git@host[:port]/…`, stripping `.git` and a trailing `/`; the port-strip is anchored to a following `/` (`^:[0-9]+/`) so a digit-leading SCP namespace (e.g. `git@gitlab.com:3mcompany/webapp.git`) is preserved, not corrupted to `mcompany/webapp`:
   ```bash
   originUrl=$(git remote get-url origin 2>/dev/null)
   originHost=$(printf '%s' "$originUrl" | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#[:/].*$##')
   originPath=$(printf '%s' "$originUrl" | sed -E 's#^[a-z]+://##; s#^[^@]*@##; s#^[^:/]+##; s#^:[0-9]+/#/#; s#^[:/]##; s#\.git$##; s#/$##')
   ```
   If `git remote get-url origin` fails or is empty (no origin), treat `originHost`/`originPath` as empty.
2. **Also extract the URL's host** (`urlHost`) from the `--pr` value the same way, and lowercase `urlHost`, `originHost`, `TARGET_PROJECT`, and `originPath` before comparing (GitHub and GitLab both treat host and namespace case-insensitively).
3. **Compute `remote`**: `remote = ( urlHost != originHost ) OR ( TARGET_PROJECT != originPath )`. Comparing the **host too** prevents a `gitlab.com/foo/bar` URL from falsely matching a `github.com/foo/bar` origin. An empty `originPath` (no origin) ⇒ `remote = true`.
4. **Gate (off-repo review is GitLab-only)**:
   - `remote == false` → **in-repo**: proceed. `TARGET_PROJECT` equals the current repo; SKILL.md PR mode routes GitLab explicitly through it (`-R "$TARGET_PROJECT"` / `projects/<enc>`, never `:fullpath`), while GitHub keeps its shipped current-repo resolution.
   - `remote == true` and `FORGE == github` → abort: `GitHub off-repo review isn't supported. cd into a clone of <TARGET_PROJECT> and re-run, or use --branch.` Off-repo review is a GitLab-only feature; a GitHub PR URL is accepted only from within its own clone (`--allow-remote` does not apply to GitHub).
   - `remote == true` and `FORGE == gitlab` and `--allow-remote` **not** set → abort: `MR is in <TARGET_PROJECT>, but this repo is <originPath or 'no origin remote'>. cd into a clone of <TARGET_PROJECT> and re-run, or pass --allow-remote to review it from here (cross-file impact analysis will be limited).`
   - `remote == true` and `FORGE == gitlab` and `--allow-remote` set → **off-repo**: proceed, and route every user-forge `glab` call to `TARGET_PROJECT` (see `SKILL.md` PR mode, `finding-sanity-check.md`, `phase8-followups.md`). Because `remote == true` means the MR lives in a different (possibly public) project, `phase8-followups.md` Step 5's target-visibility check, cross-repo consent prompt, and public-repo security-finding omission MUST run against `TARGET_PROJECT` (NOT the local checkout) before any `glab mr note` is posted, the GitLab analogue of its GitHub fork→upstream gate. Print one line, `Reviewing GitLab MR !<iid> in <TARGET_PROJECT> from outside its clone; cross-file impact analysis is limited (local tree is not the MR's repo).`, and set a Phase-7 report caveat to the same effect.

## Outputs

Set `FORGE`, `TARGET_PROJECT`, `iid`, and `remote` for the PR-mode phases. Always double-quote `"$TARGET_PROJECT"` and `"$iid"` in constructed commands (the allowlist above makes the value safe; quoting guards against word-splitting regardless).
