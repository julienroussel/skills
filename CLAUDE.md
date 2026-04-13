# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of personal Claude Code skills (slash commands) — `/audit`, `/review`, `/ship` — plus companion shell CLIs that partner with those skills. Each skill is a `SKILL.md` file in its own directory; companion CLIs live under `bin/`. There is no application code, no build system, no tests — just markdown skill definitions and shell scripts.

## Repo structure

```
audit/SKILL.md   — full codebase audit swarm
review/SKILL.md  — multi-agent PR review swarm
ship/SKILL.md    — ship working-tree changes via PR (split analysis, branching, CI, merge)
bin/tackle       — bootstrap a Claude Code session for a PR/issue/scratch worktree
                   (drops a marker that /ship reads to rename the scratch branch in place)
```

## Skill file anatomy

Each `SKILL.md` has:
1. **YAML frontmatter** — `name`, `description`, `argument-hint`, `effort`, `disable-model-invocation: true`, `user-invocable: true`
2. **HTML comment block** — declares plugin dependencies, required CLI tools, cache files read/written, and required Claude Code tools
3. **Body** — phased execution plan with argument parsing, flag conflict resolution, display protocol, and detailed per-phase instructions

## Shared conventions across all three skills

- **Phased execution**: Every skill runs in numbered phases. Each phase has a prominent `━━━` header and a running cumulative timeline (`Phase 1 ✓ (3s) → Phase 2 ✓ (18s) → ...`).
- **Parallel-first**: Tracks within a phase run simultaneously via multiple tool calls in a single message. Independent Bash/Read/Grep calls are always batched.
- **Silent agents, noisy lead**: Reviewer/implementer subagents report via TaskCreate and SendMessage only — no console output. Only the lead agent prints progress.
- **Shared cache files** in `.claude/`: `review-profile.json` (stack/package-manager detection), `review-baseline.json` (validation command baselines), `review-config.md` (suppressions and auto-learned rules), `audit-history.json` (append-only audit log).
- **Model routing**: Reviewer and implementer agents spawn with `model: "opus"`. Mechanical phases (context gathering, dedup, validation, cleanup) use the default model.
- **Severity rubric**: critical → high → medium → low, with confidence levels certain → likely → speculative. Low-severity findings are dropped unless trivially fixable.
- **Reviewer dimension boundaries**: Strict ownership of finding categories to prevent duplicates (e.g., silent failures → error-handling-reviewer, not security or typescript).
- **`nofix` mode**: Every skill that implements fixes supports a findings-only mode that skips implementation and validation phases.

## Plugin dependencies

Required: `agent-teams@claude-code-workflows` (team-reviewer, team-implementer, TeamCreate/TeamDelete).

Optional: `pr-review-toolkit@claude-plugins-official` (silent-failure-hunter, type-design-analyzer, code-simplifier), `security-scanning@claude-code-workflows` (STRIDE methodology).

## Key design decisions

- `/audit` and `/review` share the same cache files and stack detection logic (Track C). Changes to one skill's caching format must be mirrored in the other.
- `/review` has a convergence loop (`--converge`) that wraps Phases 2-6 in a repeatable cycle with auto-approval. It includes a fresh-eyes security pass after convergence.
- `/ship` handles both single-PR and multi-PR (stacked/independent) flows. Split analysis uses semantic grouping heuristics with dependency detection between groups.
- Auto-learned suppressions (Phase 4.5 in audit/review) require 2+ rejections of the same pattern before adding a rule — single rejections are treated as situational.
