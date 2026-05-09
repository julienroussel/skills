# /doctor — Output Mocks

Reference output for the report shapes /doctor emits. The full-pass mock and variations below are kept here to keep the main `SKILL.md` body lean.

## Full pass (~25 lines)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 /doctor — Claude Code Setup Health Check
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/doctor at /Users/jroussel/.claude/skills
Mode: report-only          Repo: ~/.claude/skills (in-repo, has-remote)

Global setup
  ✓ CLI tools (4/4)         git, gh (auth), jq, claude
  ✓ Optional CLI (2/2)      rtk, wt
  ✓ settings.json (5/5)     parseable, advisorModel set, agent-teams enabled, .claude/** allowed, defaultMode=plan
  ✓ Optional plugins (3/3)  pr-review-toolkit, security-scanning, worktrunk
  ✓ Skills installed (4/4)  audit, review, ship, tackle
  ✓ Shared files (3/3)      smoke-parse OK
  ✓ Hooks (3/3)             no-claude-attribution, cbm-code-discovery-gate, cbm-session-reminder
  ✓ Hooks wired (4/4)       rtk + no-claude-attribution + cbm-gate + cbm-session-reminder
  ✓ Skill drift (7/7)       line counts, shared refs, frontmatter, inline-copy
  ✓ Template hash           review/templates/pre-commit-secret-guard.sh.tmpl matches install script
  ✓ Refs cache              skill-audit/cache/refs.json fetched 3 days ago

Claude Code runtime
  ✓ claude CLI version      2.1.126
  ✓ Required env vars (1/1) CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
  ✓ Recommended env vars    CLAUDE_CODE_NO_FLICKER=1
  ℹ Optional tunables       (all defaults)
                            For /audit/review users on big monorepos, consider:
                              BASH_MAX_TIMEOUT_MS=1800000     (30-min validation cap)
                              MCP_TIMEOUT=120000              (slower codebase-memory-mcp startup)

Current repo (~/.claude/skills)
  ✓ Repo basics (3/3)
  ✓ Gitignore coverage
  ✓ GitHub remote

Optional integrations
  ⚠ codebase-memory MCP     not configured  (recommended for /audit, /review structural queries)

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
    ⚠ .claude/ directory missing   Hint: created on first audit/review run; not blocking
  ⚠ Gitignore coverage
    ⚠ .gitignore missing       Hint: --fix can create it with the canonical patterns
  ⚠ No GitHub remote           Hint: required for /ship and /review --pr; gh repo create
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
  ✓ Template hash   review/templates/pre-commit-secret-guard.sh.tmpl matches install script
  ⚠ Refs cache      skill-audit/cache/refs.json is 45 days old (cached 2026-03-25)
                    Hint: /skill-audit --refresh-refs
```

## Skill drift failure

Template hash mismatch — the install path will abort with exit 2 until reconciled:

```
Global setup
  ✓ Skill drift (7/7)
  ✓ Refs cache      skill-audit/cache/refs.json fetched 3 days ago
  ✗ Template hash   review/templates/pre-commit-secret-guard.sh.tmpl SHA-256 differs from EXPECTED_TEMPLATE_SHA256
      expected: c7bb9a8727aaabb98658acc0e3462b0652d2edf8388e1cc7d761264280acf0fd
      actual:   <new hash>
      Hint: if the template change is intentional, update EXPECTED_TEMPLATE_SHA256 in
            review/scripts/install-pre-commit-secret-guard.sh per its 4-step maintenance contract.
```
