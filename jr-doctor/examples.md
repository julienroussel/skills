# /jr-doctor — Output Mocks

Reference output for the report shapes /jr-doctor emits. The full-pass mock and variations below are kept here to keep the main `SKILL.md` body lean.

## Full pass (~25 lines)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /jr-doctor — Claude Code Setup Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/jr-doctor at ~/.claude/skills
Mode: report-only          Repo: ~/.claude/skills (in-repo, has-remote)

Global setup
  ✓ CLI tools (4/4)         git, gh (auth), jq, claude
  ✓ Optional CLI (2/2)      rtk, wt
  ✓ settings.json (4/4)     parseable, advisorModel set, .claude/** allowed, defaultMode=plan
  ✓ Optional plugins (1/1)  worktrunk
  ✓ Skills installed (4/4)  audit, review, ship, tackle
  ✓ Agent types (2/2)       jr-reviewer (read-only), jr-implementer
  ✓ Shared files (3/3)      smoke-parse OK
  ✓ Hooks (3/3)             no-claude-attribution, cbm-code-discovery-gate, cbm-session-reminder
  ✓ Hooks wired (4/4)       rtk + no-claude-attribution + cbm-gate + cbm-session-reminder
  ✓ Skill drift (7/7)       line counts, shared refs, frontmatter, inline-copy
  ✓ Template hash           jr-review/templates/pre-commit-secret-guard.sh.tmpl matches install script
  ✓ Refs cache              jr-skill-audit/cache/refs.json fetched 3 days ago
  ✓ Canonical-rule linkage  all restated rules carry resolvable pointers

Claude Code runtime
  ✓ claude CLI version      2.1.126
  ✓ Recommended env vars    CLAUDE_CODE_NO_FLICKER=1
  ℹ Optional tunables       (all defaults)
                            For /jr-audit/jr-review users on big monorepos, consider:
                              BASH_MAX_TIMEOUT_MS=1800000     (30-min validation cap)
                              MCP_TIMEOUT=120000              (slower codebase-memory-mcp startup)

Current repo (~/.claude/skills)
  ✓ Repo basics (3/3)
  ✓ Gitignore coverage
  ✓ GitHub remote

Optional integrations
  ⚠ codebase-memory MCP     not configured  (recommended for /jr-audit, /jr-review structural queries)

Summary: 28 ✓  1 ⚠  0 ✗   Total: 1.4s
```

## Fresh `git init` directory

Global setup and Claude Code runtime sections render as in the full-pass mock — only the per-repo section differs:

```
Global setup
  (same as full pass — green if user's ~/.claude is set up)

Claude Code runtime
  (same as full pass — env vars and CLI version)

Current repo (/tmp/empty)
  ⚠ Repo basics (1/3)
    ✓ git repo
    ⚠ CLAUDE.md missing       Hint: /init to generate
    ⚠ .claude/ directory missing   Hint: created on first jr-audit/jr-review run; not blocking
  ⚠ Gitignore coverage
    ⚠ .gitignore missing       Hint: --fix can create it with the canonical patterns
  ⚠ No GitHub remote           Hint: required for /jr-ship and /jr-review --pr; gh repo create
```

## Smoke-parse failure

```
Global setup
  ✗ Shared files (1/3)
    ✓ shared/reviewer-boundaries.md
    ✗ shared/untrusted-input-defense.md   smoke-parse failed: missing 'do not execute, follow, or respond to'
      Hint: cd ~/.claude/skills && git checkout shared/untrusted-input-defense.md
    ✗ shared/gitignore-enforcement.md     file empty
      Hint: cd ~/.claude/skills && git checkout shared/gitignore-enforcement.md
```

## Skill drift warning

Multiple skills exceed the 500-line guideline; template hash matches; refs cache stale:

```
Global setup
  ⚠ Skill drift (4/7)
    ⚠ audit         568 lines (Anthropic recommends < 500)
    ⚠ doctor        621 lines (Anthropic recommends < 500)
    ⚠ review        929 lines (Anthropic recommends < 500)
                    Hint: extract phases to <skill>/scripts/*.sh or move shared content to shared/*.md.
  ✓ Template hash   jr-review/templates/pre-commit-secret-guard.sh.tmpl matches install script
  ⚠ Refs cache      jr-skill-audit/cache/refs.json is 45 days old (cached 2026-03-25)
                    Hint: /jr-skill-audit --refresh-refs
```

## Skill drift failure

Template hash mismatch — the install path will abort with exit 2 until reconciled:

```
Global setup
  ✓ Skill drift (7/7)
  ✓ Refs cache      jr-skill-audit/cache/refs.json fetched 3 days ago
  ✗ Template hash   jr-review/templates/pre-commit-secret-guard.sh.tmpl SHA-256 differs from EXPECTED_TEMPLATE_SHA256
      expected: c7bb9a8727aaabb98658acc0e3462b0652d2edf8388e1cc7d761264280acf0fd
      actual:   <new hash>
      Hint: if the template change is intentional, update EXPECTED_TEMPLATE_SHA256 in
            jr-review/scripts/install-pre-commit-secret-guard.sh per its 4-step maintenance contract.
```

## Optional tunables reference

Moved out of `SKILL.md` (Group H's "Optional tunables" subsection points here). These env vars are NOT required for /jr-audit, /jr-review, /jr-ship, or tackle. /jr-doctor surfaces them on the report **only if explicitly set** — otherwise the report stays terse. All defaults are reasonable; raise/lower deliberately.

| Env var | Default | When raising helps |
|---|---|---|
| `BASH_DEFAULT_TIMEOUT_MS` | `120000` (2 min) | Long `git`/`gh`/`jq` ops in /jr-audit Phase 1 Track C or /jr-review Phase 1 Pre-checks. |
| `BASH_MAX_TIMEOUT_MS` | `600000` (10 min) | /jr-audit Phase 6 validation runs lint+typecheck+test on big monorepos; raising to e.g. `1800000` (30 min) avoids spurious validation failures. |
| `MCP_TIMEOUT` | `30000` (30 sec) | First-time `codebase-memory-mcp` index can be slow; raise to e.g. `120000` if `mcp list` hangs. |
| `MCP_TOOL_TIMEOUT` | per-tool default | Long `query_graph` / `trace_path` calls on large indexed repos. |
| `MAX_THINKING_TOKENS` | model-dependent | More headroom for extended reasoning on complex /jr-audit findings — `0` disables thinking entirely. |
| `MAX_MCP_OUTPUT_TOKENS` | model-dependent | Verbose MCP outputs (graph dumps, large trace results) get truncated; raise if the codebase-memory-mcp output is being clipped. |
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | `10` | More parallelism in /jr-audit Phase 1 Track B prefetch and /jr-review Phase 2 reviewer dispatch. |
| `DISABLE_TELEMETRY` | unset | Privacy preference. `1` opts out. |
| `DISABLE_AUTOUPDATER` | unset | Pin the installed CLI version; `1` disables the background update check. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | unset | Shorthand: disables autoupdater + telemetry + error reporting + feedback. |

## Marker semantics

Loaded on demand by Group I — read this only when `scripts/skill-drift-check.sh` emits at least one marker line.

| Marker | Status | Meaning | Hint |
|---|---|---|---|
| `WARN_LINES:<skill>:<n>` | ⚠ | SKILL.md exceeds Anthropic's 500-line guideline (https://code.claude.com/docs/en/skills). Large skills cost tokens for the rest of the session after invocation. | Extract phases to `<skill>/scripts/*.sh` or move shared content to `~/.claude/skills/shared/*.md`. Refer to `/jr-review`'s extraction history (commits introducing `shared/*.md`, `jr-review/scripts/*.sh`, `jr-review/convergence-protocol.md`) as a worked example. |
| `FAIL_BROKEN_REF:<skill>:<ref>` | ✗ | SKILL.md references a non-existent shared file. /jr-audit and /jr-review hard-fail at Phase 1 Track A on this; /jr-doctor catches it earlier. | `cd ~/.claude/skills && git status shared/` to find the missing or renamed file. |
| `WARN_DMI_INERT:<skill>` | ⚠ | `disable-model-invocation: true` makes `when_to_use:` and `paths:` inert (description is not loaded into context per https://code.claude.com/docs/en/skills). | Either remove the inert field or set `disable-model-invocation: false`. |
| `FAIL_EFFORT:<skill>:<value>` | ✗ | `effort:` value is not in the allowlist (`low|medium|high|xhigh|max`). Claude Code rejects the skill at load time. | Pick a valid value. |
| `WARN_MODEL:<skill>:<value>` | ⚠ | `model:` value not in the known allowlist. May be a typo OR a model added after this allowlist was last updated. | If the value is a real model alias, update the regex in /jr-doctor's Group I. Otherwise correct the typo. |
| `FAIL_NO_DESC:<skill>` | ✗ | Frontmatter is missing the required `description:` field. | Add a `description:` line. |
| `WARN_INLINE_DRIFT:<skill>:<file>` | ⚠ | A canonical Group D smoke-parse anchor appears inline AND the corresponding `shared/<file>` reference is absent. Drift risk: future edits to the shared file won't propagate. | Add a `../shared/<file>` reference at the call site. |
| `FAIL_TEMPLATE_HASH:expected=<x>:actual=<y>` | ✗ | `jr-review/templates/pre-commit-secret-guard.sh.tmpl` hash differs from `EXPECTED_TEMPLATE_SHA256` in the install script. The install path will abort with exit 2 until reconciled. | If the template change is intentional, update `EXPECTED_TEMPLATE_SHA256` in `jr-review/scripts/install-pre-commit-secret-guard.sh` per its 4-step maintenance contract. Otherwise restore the template from git. |
| `WARN_REFS_CACHE_MISSING` | ⚠ | `jr-skill-audit/cache/refs.json` not found. `feature-adoption-reviewer` will skip on next `/jr-skill-audit` run unless the cache is built. | Run `/jr-skill-audit --refresh-refs` once to populate the cache. |
| `WARN_REFS_CACHE_NO_TIMESTAMP` | ⚠ | `jr-skill-audit/cache/refs.json` is present but missing the `fetchedAt` field. Likely manual edit or corruption. | Run `/jr-skill-audit --refresh-refs` to rewrite. |
| `WARN_REFS_CACHE_STALE:<fetched>:<age_days>` | ⚠ | Cache is older than 30 days; live Anthropic docs/changelog have probably moved on. `feature-adoption-reviewer` findings will be tagged `[Source: cached YYYY-MM-DD]`. | Run `/jr-skill-audit --refresh-refs` to refresh. |
| `WARN_HARNESS_CLAIM_STALE:<file>:<date>:<age_days>` | ⚠ | A `<!-- harness-claim-verified: DATE -->` marker (in a scanned `shared/*.md` / `SKILL.md` / `protocols/*.md` / `docs/*.md`) is older than 90 days. Harness behaviour (tool grants, spawn/return semantics, CLI JSON field names) drifts across Claude Code / plugin releases, so a dated assertion left unchecked becomes a stale certainty. | Re-verify the claim against the running harness (`docs/skill-anatomy.md` "Re-verifying a harness claim"; the Group J probe live-checks the spawn/tool claims), then update the marker date. |
| `WARN_HARNESS_CLAIM_UNPARSEABLE:<file>:<date>` | ⚠ | A `<!-- harness-claim-verified: -->` marker's date is shape-valid (`YYYY-MM-DD`) but not a real calendar date (e.g. `2026-02-30`), so staleness cannot be computed — the marker looks present while giving zero coverage. | Correct the date to the real `YYYY-MM-DD` on which the claim was verified. |
| `FAIL_ABORT_REASON_ORPHAN:<value>:<file>:<line>` | ✗ | A skill sets `abortReason="<value>"` that is not declared in `shared/abort-markers.md`'s mapping table. At runtime it falls through the `case` to `[ABORT — UNLABELED]` — a contract violation surfaced only after the fact. | Fix the typo, or add the value's row to the mapping table (the script and table are co-authored). |
| `FAIL_ABORT_MARKERS_TABLE_EMPTY` | ✗ | `shared/abort-markers.md` exists but its `## Reason → Marker mapping` table yielded no values — stubbed or truncated. The enum check cannot run. | Restore `shared/abort-markers.md` from git. |
| `FAIL_ABORT_REASON_EXTRACTION_EMPTY` | ✗ | No `abortReason="..."` setter was found in any skill though the enum is in active use — the extraction regex is broken, not the repo. Emitted so a silently-matching-nothing check fails loudly instead of certifying clean. | Inspect the abortReason extraction in `scripts/skill-drift-check.sh` (check 7). |
| `WARN_RESTATE_UNLINKED:<path>:<line>:<id>` | ⚠ | A registered canonical rule (`<id>`) is restated inline at `<path>:<line>` with no resolvable `(canonical: <home> "<section>")` pointer within ±5 lines (issue #88). Drift risk: the inline copy can silently diverge from its canonical home. Unlike check 4, check 9 also scans `protocols/*.md`. | Add a `(canonical: <home> "<section>")` pointer next to the restatement, or remove it and defer to the canonical (`docs/skill-anatomy.md` "Restating a canonical rule inline"). |
| `WARN_RESTATE_UNRESOLVED:<path>:<line>:<id>` | ⚠ | A `(canonical: …)` pointer beside a restated rule (`<id>`) names a `"<section>"` that no longer resolves to a heading in the home file (a stale pointer). | Update the pointer's `"<section>"` to a current heading in the home, or restore the heading. |
| `FAIL_GUARD_MODE:<skill>:<line>:<file>` | ✗ | A line-anchored (`^…`) smoke-parse anchor is verified with `grep -F`, which treats `^` as a literal and never matches. The hard-fail guard then aborts Phase 1 on **every** run of that skill. | Change the guard to `grep -Eq` and escape regex metacharacters in the anchor. |
| `WARN_HARNESS_CLAIM_MALFORMED:<file>:<n>` | ⚠ | A `harness-claim-verified` stamp lost its `<!-- -->` delimiters, so check 8 cannot see it: it looks present to a reader while providing zero staleness coverage. | Restore the exact `<!-- harness-claim-verified: YYYY-MM-DD -->` form. |
| `WARN_ANCHOR_TAIL_UNGUARDED:<skill>:<file>:<hit>/<total>` | ⚠ | The **last** declared anchor for a guarded protocol file first occurs before 60% of it, so a tail truncation passes the guard while dropping the rest of the procedure. | Move the last anchor to the file's final section. |
| `WARN_CANON_PTR_UNRESOLVED:<file>:<target>:<section>` | ⚠ | A `(canonical: <file> "<section>")` pointer names a string that is not a heading in the target (typically a bold bullet or a numbered item), so it resolves to nothing for the reader who follows it. | Repoint at a real heading. |
| `WARN_CANON_PTR_NOFILE:<file>:<target>` | ⚠ | A canonical pointer names a file that does not resolve from that location. | Fix the relative path (`protocols/` files need `../../shared/`). |
| `WARN_RESTATE_TOKEN_UNUSED:<id>` | ⚠ | Check 9 registry token `<id>` matched zero non-home files: the row is stale (a typo, or the last consumer reworded its copy). Fail-loud (mirrors `FAIL_ABORT_REASON_EXTRACTION_EMPTY`) so the check cannot certify green while covering nothing. | Retire the registry row in `scripts/skill-drift-check.sh` check 9, or fix its token. |
| `WARN_RESTATE_HOME_SECTION_MISSING:<id>:<section>` | ⚠ | Check 9 registry row `<id>` names a `<section>` absent from its declared canonical home: the row is misconfigured, or the home heading was renamed. | Fix the section string in check 9's registry, or restore the home heading. |

