# Claude Code Skills

Personal skills and companion CLIs for [Claude Code](https://claude.ai/code), tailored to my own workflows and preferences. These are shared for reference and inspiration, not as ready-made solutions. If you use them, expect to adapt them to your own setup — don't reuse blindly.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| **audit** | `/audit [path] [nofix\|full\|quick] [--only=dims] [--exclude=glob]` | Full codebase audit using a swarm of specialized expert agents. Scales dynamically with preflight estimation, validation baselines, and audit history. |
| **review** | `/review [nofix\|full\|quick\|--converge[=N]\|--auto-approve] [--only=dims] [--scope=path] [--pr=N]` | Multi-agent PR review. Spawns specialized reviewers, deduplicates findings, gets approval, auto-fixes, and validates. Converge mode loops until clean. |
| **ship** | `/ship [message] [--draft\|--no-split\|--no-merge\|--dry-run\|--validate]` | Ship working-tree changes via PR. Analyzes changes for coherent splitting into sub-PRs, handles branching, CI wait, squash-merge, and cleanup. |

## Companion CLIs

Shell utilities that partner with the skills. Not invoked by Claude — you run them from your terminal.

| Command | Path | Description |
|---------|------|-------------|
| `tackle` | `bin/tackle` | Bootstrap a Claude Code session for a GitHub PR/issue or a scratch worktree. Creates an isolated worktree at `.claude/worktrees/<id>/`, pre-loads context into `CLAUDE.local.md` (auto-loaded by Claude, not committed), launches Claude with `--dangerously-skip-permissions` for non-review sessions (or `--permission-mode plan` with `--review`), and pre-types a starter prompt into the input box (not submitted; macOS only — needs Accessibility permission, see Setup). `tackle --scratch` drops a marker that `/ship` detects to rename the scratch branch in place from the diff. |

## Setup on a new device

```bash
git clone git@github.com:julienroussel/skills.git ~/.claude/skills
ln -sf ~/.claude/skills/bin/tackle ~/.local/bin/tackle
```

**macOS only — one-time Accessibility permission for `tackle`'s prompt prefill**: System Settings → Privacy & Security → Accessibility → enable your terminal app (Terminal.app or iTerm2). Without it, `tackle` still works but the starter prompt won't be pre-typed into Claude's input box. Edit the `PROMPT_*_TEMPLATE` constants at the top of `bin/tackle` to customize the starter prompts.

## Plugin dependencies

Required:

- `agent-teams@claude-code-workflows` — team-reviewer, team-implementer agents

Optional (enhance skills but not strictly needed):

- `pr-review-toolkit@claude-plugins-official` — silent-failure-hunter, type-design-analyzer, code-simplifier
- `security-scanning@claude-code-workflows` — STRIDE methodology (used by audit)
