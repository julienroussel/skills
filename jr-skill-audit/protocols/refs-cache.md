# Track C — live Anthropic references cache (`/jr-skill-audit`)

**Skill-local.** The Phase 1 Track C body: the `.gitignore` advisory probe on the cache path, the
cache schema, refresh trigger + procedure, the content-shape assertions, both fallbacks, the
per-key usability rule, and the per-dimension reference-excerpt allocation. Read into lead context
**at Track C entry**, under hard-fail + non-empty + smoke-parse (anchors declared at the SKILL.md
read site and deliberately not restated here, so a body-stripped truncation cannot false-pass).

**Headroom, not a token saving**: Track C runs on every invocation, so this file loads on every
invocation and the per-run cost is unchanged. Full reasoning: the repo `CLAUDE.md`.

## Cache schema

```json
{
  "fetchedAt": "2026-05-09T12:34:56Z",
  "refsSpecVersion": 3,
  "refs": {
    "skills-doc":     { "url": "https://code.claude.com/docs/en/skills",     "content": "...", "ok": true },
    "env-vars-doc":   { "url": "https://code.claude.com/docs/en/env-vars",   "content": "...", "ok": true },
    "sub-agents-doc": { "url": "https://code.claude.com/docs/en/sub-agents", "content": "...", "ok": true },
    "claude-code-changelog": { "url": "gh:anthropics/claude-code:CHANGELOG.md", "content": "...", "ok": true }
  }
}
```

## `.gitignore` advisory probe (on entry, before the refresh branches)

Apply `../../shared/gitignore-enforcement.md` to the cache path (advisory, no mutation — `Edit` is
disallowed) **before the Refresh logic branches**, so both arms are covered. `cache/refs.json` is the
run's **validation oracle**, not an output artifact, so a committed or poisoned copy silently governs
which citations pass (`rationale.md` "Track C cache"). That risk is live on the within-TTL arm, which
*loads* the cache without rewriting it, so the probe cannot sit on the refresh arm alone. Let
`cacheRepo=$(git -C "${CLAUDE_SKILL_DIR}" rev-parse --show-toplevel 2>/dev/null)`; if non-empty, with
`rel` the cache path relative to it. **Anchor `-C` on the skill directory, never on `cache/`**:
`cache/` does not exist until the Refresh procedure's `mkdir -p` (step 1) and this probe deliberately
precedes that branch, so `git -C` on it exits 128 with empty output, leaves `cacheRepo` empty and
silently skips **both** advisories, on a first run and on every fresh clone, exactly when the advice
matters most. `${CLAUDE_SKILL_DIR}` always exists, and both checks below take the cache path as an
argument, so neither needs it on disk (`ls-files` and `check-ignore --no-index` answer for paths that
do not exist yet).

- **Tracked check** — `git -C "$cacheRepo" ls-files --error-unmatch "$rel"`. Exit 0 → **warn** that the cache is committed and a stale copy governs validation. Do NOT untrack.
- **Ignored check** — `git -C "$cacheRepo" check-ignore -q --no-index "$rel"`. Non-zero → **inform**: add `<skill-dir-relative>/cache/` to `.gitignore` (one glob covers the JSON and its `.tmp`). **`--no-index` is mandatory**: without it `check-ignore` skips *tracked* files and exits non-zero whatever the rules say — i.e. it fails on exactly the file this check exists to catch.

## Refresh logic

1. If `--refresh-refs` is set OR the cache file is missing OR `fetchedAt` is older than 7 days OR the cache is **missing any ref key the schema above declares** OR **any declared key fails the content-shape assertion in step 4** OR its `refsSpecVersion` differs from the current spec version (**`3`** — bump this integer, here and in the schema, whenever you add/remove a ref key or change a fetch prompt in step 2) → refresh. A ref-set or fetch-prompt change therefore self-heals on the next run instead of silently serving a stale/incomplete set within the TTL.
2. Otherwise → load from cache silently.

## Refresh procedure (best-effort; partial-success is allowed)

1. `mkdir -p "${CLAUDE_SKILL_DIR}/cache"`.
2. **Fetch the `.md` raw variant of each doc, not the HTML page**: `https://code.claude.com/docs/en/skills.md`, `…/env-vars.md`, `…/sub-agents.md`. The raw variant returns the full document instead of a small-model summary, which is what makes the content trustworthy (see the limitation note below for why prompt-targeting an HTML fetch is not a substitute). **Record the canonical URL without the `.md` suffix as the `url` key** in `refs.json` — Phase 3 step 2's URL branch matches on that key, so the suffix must not leak into it.

   Sections that must survive, and are asserted in step 4: skills doc → **frontmatter reference table** + **substitution variables table** + **`Skill content lifecycle`** + the **500-line tip**; env-vars → the **complete named env-var table**, including the subagent controls (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_EFFORT`) — note `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION` was **removed in v2.1.224 and is now a no-op**, so it is deliberately not required here and a reviewer should flag any audited skill still relying on it; sub-agents → **supported-frontmatter-fields table** + **model-resolution order** + **available-tools / background-default** rules + **concurrency / spawn-depth caps**.
3. `gh api repos/anthropics/claude-code/contents/CHANGELOG.md --jq .content | base64 -d | head -c 60000` for the latest changelog. (gh is preferred over WebFetch for github.com URLs per WebFetch's own guidance.) Trim to 60 KB so the cache stays bounded; the most recent ~30 versions easily fit.
4. **Assert content shape BEFORE writing** (mandatory — a confidently-wrong cache is more dangerous than a missing one, see the limitation note). For each fetched source, require every substring below to be present (case-sensitive, `grep -F`); on failure set that source's `ok: false` and `content: ""` rather than caching a truncated or summarised fetch:

   | Key | Required substrings |
   |---|---|
   | `skills-doc` | `\$ARGUMENTS` AND `CLAUDE_SKILL_DIR` AND `Skill content lifecycle` AND `disable-model-invocation` |
   | `env-vars-doc` | `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` AND `CLAUDE_CODE_SUBAGENT_MODEL` AND `CLAUDE_EFFORT` |
   | `sub-agents-doc` | `permissionMode` AND `maxTurns` AND `initialPrompt` |
   | `claude-code-changelog` | `## 2.1.` |

   `ok: true` over content that fails these anchors is the failure mode; neither the flag nor Phase 3's URL-key check detects it.

5. Write `cache/refs.json` atomically (write to `cache/refs.json.tmp`, then `mv`), including the current `refsSpecVersion`. Surface any `ok: false` source in the Phase 7 report under "Reference fetch status".

**Known limitation — WebFetch summarization. Prompt-targeting is NOT a mitigation**: WebFetch on an HTML page returns a small-model summary, not raw markup, and naming the tables to preserve does not reliably keep them (measured and refuted — `rationale.md` "Track C cache"). Hence the `.md` raw variant (step 2) and the fail-closed content assertion (step 4). The `gh api` changelog path returns raw markdown and never had this problem.

## Fallbacks

**Fallback to stale cache**: if the refresh fails entirely (no network, gh unauth, etc.) AND a previous `cache/refs.json` exists, use it and prepend `[STALE: cache from <fetchedAt>]` to every reviewer prompt that consumes it. Reviewers must add `[Source: cached YYYY-MM-DD]` to any finding citing a source from the stale cache so the user can judge freshness. **Re-apply the step-4 content assertions to the stale content before use**, and treat any key that fails them as `ok: false` for this run, surfacing it under "Reference fetch status" exactly as step 5 does. `[STALE: …]` is an *age* marker, not a *shape* one, and a failed step-4 assertion is itself one of the triggers that sent this run to a refresh (step 1), so the key that landed here is frequently the unusable one; without the re-check a reviewer receives empty content and reasons over nothing.

**Fallback to no cache**: if the refresh fails AND no prior cache exists, no ref key is usable, so the per-key usability rule below applies here unchanged: mark as **skipped** in Phase 2 every dimension whose `Receives` cell names a Track C key (`frontmatter-reviewer`, `token-efficiency-reviewer`, `feature-adoption-reviewer`: **three** of the seven), warn in the Phase 7 report (`Reference fetch failed and no prior cache exists. Skipped: <dimensions>.`), and continue with the other **four**, whose `Receives` cells name none. Do NOT abort the run: those four don't need live refs. Skipping `feature-adoption-reviewer` alone would leave the other two citing a skills doc they never received, which is the ungrounded-finding failure this fallback exists to prevent.

## Same rule per key

**Governing EVERY load path (within-TTL, stale-fallback, and post-refresh alike), not just the no-cache fallback**: `ok: false` is not usable content, so **skip** every dimension whose `Receives` cell below names that key (a failed `skills-doc` skips three), report each in `Audit integrity` as skipped for a missing reference, and count it in `refSkippedCount`, which qualifies the Phase 7 summary line (`phase7-report.md`) without changing the exit code. These skips compose with `--only=`, so they can empty the reviewer set outright; Phase 2's zero-dimension guard catches that. Rationale for making it path-independent: a missing cache is safe because the reviewer is skipped, whereas a confidently-wrong one is not, because the reviewer runs (`rationale.md` "Track C cache"), so the remedy has to attach to the key's usability, never to which branch loaded it.

## Per-reviewer reference excerpts (token budget)

Each reviewer receives ONLY the references it needs (mirrors the principle "skills load on demand"). Excerpts are pulled from `cache/refs.json`. The Refresh logic above normally repopulates a newly-added or version-stale key before this point; if a schema-declared key is still absent (an offline refresh could not fetch it), the reviewer proceeds with the refs present but the run is **partial, not silently omitted** — render `Refs: partial (<missing-keys>)` on the discovery line and add a note under the Phase 7 "Reference fetch status" naming the missing key(s) and recommending `--refresh-refs`:

| Dimension | Receives |
|-----------|----------|
| `frontmatter-reviewer` | `skills-doc` Frontmatter reference table + Available string substitutions table. |
| `advisor-coverage-reviewer` | `shared/advisor-criteria.md` (full). NO Track C refs needed. |
| `token-efficiency-reviewer` | `skills-doc` Skill content lifecycle section + 500-line Tip. |
| `shared-drift-reviewer` | The **11 `shared/*.md` files Track A read** (already in lead context; the authoritative list is Phase 1 Track A in `SKILL.md`). NO Track C refs. ⚠ **Not the full set** — `shared/` holds 17; drift against the other six is **out of scope for this run** and must be stated as such, not implied covered. `/jr-doctor` Group D is the backstop. |
| `feature-adoption-reviewer` | `skills-doc` (Frontmatter reference + Substitutions tables) + `sub-agents-doc` (subagent frontmatter / model-resolution / background-default / caps) + `env-vars-doc` (subagent + effort env vars) + `claude-code-changelog` (head ~30 versions). |
| `safety-protocols-reviewer` | `shared/untrusted-input-defense.md` + `shared/gitignore-enforcement.md` + `shared/secret-scan-protocols.md` + `shared/subagent-reporting.md` (all already in lead context from Phase 1 Track A reads; gitignore-enforcement and secret-scan-protocols so it can flag missing gitignore-enforcement applications and verify secret-scan tier semantics, subagent-reporting for the spawn-correctness check). NO Track C refs. |
| `model-routing-reviewer` | NO Track C refs — reasons over the audited skill's own phase descriptions + frontmatter `model`/`effort` fields (already in the full `SKILL.md` content every reviewer receives per Phase 2). |
