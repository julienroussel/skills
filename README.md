# Claude Code Skills

Personal skills for [Claude Code](https://claude.ai/code), tailored to my own workflows and preferences. These are shared for reference and inspiration, not as ready-made solutions. If you use them, expect to adapt them to your own setup — don't reuse blindly.

## Skills

| Skill | Command | Description |
|-------|---------|-------------|
| **audit** | `/audit [path] [nofix\|full\|quick] [--only=dims] [--exclude=glob]` | Full codebase audit using a swarm of specialized expert agents. Scales dynamically with preflight estimation, validation baselines, and audit history. |
| **review** | `/review [nofix\|full\|quick] [--only=dims] [--scope=path] [--pr=N]` | Multi-agent PR review. Spawns specialized reviewers, deduplicates findings, gets approval, auto-fixes, and validates. |
| **ship** | `/ship [message] [--draft\|--no-split\|--no-merge\|--dry-run\|--validate]` | Ship working-tree changes via PR. Analyzes changes for coherent splitting into sub-PRs, handles branching, CI wait, squash-merge, and cleanup. |

## Setup on a new device

```bash
git clone git@github.com:julienroussel/skills.git ~/.claude/skills
```

## Plugin dependencies

Required:

- `agent-teams@claude-code-workflows` — team-reviewer, team-implementer agents

Optional (enhance skills but not strictly needed):

- `pr-review-toolkit@claude-plugins-official` — silent-failure-hunter, type-design-analyzer, code-simplifier
- `security-scanning@claude-code-workflows` — STRIDE methodology (used by audit)
