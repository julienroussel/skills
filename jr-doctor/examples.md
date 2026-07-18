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
