# `/jr-skill-audit` — Edge cases

**Reference material** for `/jr-skill-audit`, loaded on demand — NOT read at Phase 1 Track A (these are case→behavior mappings, not load-bearing procedure, so no hard-fail guard applies). `jr-skill-audit/SKILL.md`'s `## Edge cases` section points here. Update here to update the edge-case reference.

| Case | Behavior |
|------|----------|
| Cache > 7 days old, network unavailable | Use stale cache + `[STALE: cached YYYY-MM-DD]` warning. `feature-adoption-reviewer` runs but tags every finding `[Source: cached YYYY-MM-DD]`. |
| Cache missing, network unavailable | Skip `feature-adoption-reviewer` with a Phase 7 warning. Other 5 dimensions run normally. |
| Bare `/jr-skill-audit` with zero skills installed | `[ABORT — UNMATCHED SCOPE]` and the (empty) "Available skills" hint. Should never trigger in practice — `/jr-doctor` would already flag a broken skills install. |
| Skill with `model:` field referencing a model alias added after this skill was last updated | `frontmatter-reviewer` cites the live skills-doc model section: if the alias is in the doc, finding is dropped; if not, flagged as `WARN_MODEL`. |
| Skill referencing a `shared/<name>.md` that exists but was renamed | `shared-drift-reviewer` flags as broken-ref (mirrors `/jr-doctor` Group I). Cross-references the canonical name if the renamed file is found via `git log --diff-filter=R`. |
| Skill with `disable-model-invocation: true` AND a non-empty `description` exceeding 1,024 chars | `frontmatter-reviewer` flags as `medium`: when DMI is true, the description isn't loaded into context, so verbose descriptions are dead weight in `/`-menu listings. |
| `--plugin=<name>` (plugin audit) | Resolves to the plugin's git-backed marketplace clone (`~/.claude/plugins/marketplaces/<mp>/<source>/skills/`); audits git-tracked skills only, all 7 dimensions, every finding tagged `[third-party — verify against plugin docs]`. Read-only/advisory — owned by the plugin author. |
| `--plugin=<name>` not declared by any marketplace | `[ABORT — UNMATCHED SCOPE]`: `Plugin <name> not found. Available plugins: <union of plugins[].name>.` |
| `--plugin=<name>` whose marketplace is not a git repo (e.g. `claude-plugins-official`) | Warn and skip (`… non-git marketplace …; skill-audit only audits git-versioned skills.`); abort if it was the sole resolution. |
| `--plugin=<name>` with an external object-form `source` (`git-subdir`/`url`, e.g. `pensyve`) | Warn and skip at Track B step 1 (`… uses an external (git-subdir/url) source, not an in-marketplace path …`); abort if it was the sole resolution. Vendored-elsewhere plugins aren't reachable via the marketplace clone. |
| Same plugin `<name>` declared by two marketplaces | Audit both; the `marketplace` tag disambiguates findings. |
| Bare `/jr-skill-audit` invoked from a tackle worktree | The worktree path counts as project scope; `.claude/skills/` inside the worktree (and parents up to the worktree's repo root) is audited alongside personal skills. |
| CWD is `~` or under `~/.claude/skills/` | Project walk skips any dir whose realpath resolves under personal-root, preventing duplicate iteration. Result: personal-only audit, no synthetic shadow findings. |
| `--scope-only=project` from a dir with no `.claude/skills/` anywhere in the walk | Empty target set → `[ABORT — UNMATCHED SCOPE]` per the canonical mapping. The abort message includes `--scope-only=project` so the user can drop the flag and retry. |
| Same skill name in personal + project (deliberate per-repo override) | Lead emits `scope-resolution` finding with `clarify: true`. User picks "Drop this finding" in the Phase 4 [Clarify] flow. The personal AND project SKILL.md files are still both audited; the finding is the ONLY collision-driven artifact. |
| `--add-dir` directories at session start | Out of scope (v2 candidate). `/jr-skill-audit` has no access to the running session's `--add-dir` set. If a user's monorepo workflow depends on `--add-dir`-mounted skills, they should run `/jr-skill-audit` from each mount root separately. |
| Bare positional `<name>` with `--scope-only=personal` but `<name>` only in project | Abort per flag-conflict block: `Skill <name> not found in personal scope (exists in project: drop --scope-only or use --scope-only=project).` |
| `gh` CLI not installed or unauthenticated | Track C `claude-code-changelog` fetch fails. `feature-adoption-reviewer` falls back to skills-doc only (changelog evidence missing). Phase 7 warns. |
| Skill legitimately needs `opus` despite mechanical-looking phases | `model-routing-reviewer` sets `clarify: true` with a `clarificationQuestion` rather than asserting a finding — premium tier is often a deliberate headroom choice, and a hard finding would re-fire on every re-run. |
