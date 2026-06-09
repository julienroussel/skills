# Personal/Project Scope Discovery (`/jr-skill-audit`, non-`--plugin` path)

**Canonical procedure** for the personal + project scope-root discovery, enumeration, filtering, and gitignore exclusion. Read into lead context at Phase 1 Track A **only when `--plugin` is NOT set** (the complementary conditional to `plugin-scope.md`, which is read only under `--plugin`; the two paths are mutually exclusive). Returns the surviving target set tagged `scope = personal | project`, consumed by the lead-side shadow detection and Phase 2 dispatch. Smoke-parse anchors enforced at the read site: `Scope roots` AND `Gitignore exclusion`.

**Scope roots** (computed before any enumeration) — personal/project path (when `--plugin` is NOT set):

- **`realpath` availability probe**: run `command -v realpath >/dev/null 2>&1` once and store `REALPATH_AVAILABLE=true|false`. When `false`, the skip conditions and dedupe step below fall back to literal trailing-slash path comparison (`case "$dir/" in "$personalRoot"/*) ;; esac`) instead of `realpath`-normalized paths — slightly less symlink-robust but functionally equivalent for the common case (direct duplicates still caught; symlink aliases not collapsed).
- **personalRoot**: `${HOME}/.claude/skills`. Always enumerated; `--scope-only=project` drops personal candidates post-enumeration (see "Apply `--scope-only` filter" below).
- **projectRoots**: discovered by walking parents. **Walked unconditionally** — even with `--scope-only=personal` — so the cross-scope conflict probe below can detect cases where bare positional `<name>` resolves only in the dropped scope and produce the specific conflict message. Walk-start = `$PWD`; walk-stop = `git -C "$PWD" rev-parse --show-toplevel 2>/dev/null` (or `$PWD` if not in a git repo). Iterate from walk-start via repeated `dirname "$dir"` (quoted) until reaching walk-stop inclusive (extra safety: break if `dirname` returns the same value, i.e., at `/`).
- **Per-walked-dir filter**: for each `<dir>`, add `<dir>/.claude/skills` to `projectRoots` only if `[ -d "$dir/.claude/skills" ]` is true AND BOTH skip conditions are false. Skip if either: (a) `<dir>` is at or under `<personalRoot>` — use `realpath`-normalized paths when `REALPATH_AVAILABLE=true`, else literal trailing-slash comparison (append `/` to both sides so `/a/b` never matches `/a/bb`); or (b) `<dir>/.claude/skills` (when it exists) equals `<personalRoot>` — same `realpath`/literal switch. Condition (b) catches the case where walk-start is a *parent* of personal-root (e.g., CWD is `$HOME`) — without it, the project walk would discover personal-root as a project-root and double-count.

This matches the documented Claude Code runtime behavior (per `https://code.claude.com/docs/en/skills#automatic-discovery-from-parent-and-nested-directories` — project skills load from `.claude/skills/` in the starting directory and every parent up to the repository root). Nested-on-demand discovery (e.g., `packages/frontend/.claude/skills/` from a root-started session) and `--add-dir`-mounted skills are runtime-only behaviors `/jr-skill-audit` does not have a signal for; they're out of scope here.

**Enumerate SKILL.md candidates** from each scope root, dedupe by path (using `realpath` when `REALPATH_AVAILABLE=true` to catch symlinks and any project root that resolves to personal; else literal-path dedupe — direct duplicates still caught), and tag each surviving candidate with `scope = personal | project`.

**Apply the argument-set filter** (runs BEFORE `--scope-only` so cross-scope conflicts can be detected):
1. **Bare positional** (`/jr-skill-audit <name>`): keep candidates whose directory basename == `<name>` in EITHER scope.
2. **`--scope=<glob>`**: keep candidates whose directory basename matches the glob in EITHER scope.
3. **No filter**: keep all candidates from both scopes. Skip directories without a `SKILL.md` (e.g., `bin/`, `docs/`, `shared/`).

**Cross-scope conflict probe** (only when `--scope-only` is set AND `<name>` is the bare positional): if the argument-filter result is **non-empty AND** every match is in the dropped scope, abort with the specific conflict message. (Empty result falls through to the generic "Available skills" hint at "Bare positional resolution" below — the empty case means `<name>` doesn't exist in EITHER scope.)
- `--scope-only=personal`, matches only in project → `Skill <name> not found in personal scope (exists in project: drop --scope-only or use --scope-only=project).`
- `--scope-only=project`, matches only in personal → `Skill <name> not found in project scope (exists in personal: drop --scope-only or use --scope-only=personal).`

**Apply `--scope-only` filter** to the argument-filter result:
- `--scope-only=personal`: drop project candidates.
- `--scope-only=project`: drop personal candidates.
- Neither flag: keep both.

**Bare positional resolution** (final, after both filters): 0 matches → abort with the "Available skills: personal=<list> project=<list>" hint from the sanitization rule. 1 match → audit it. ≥ 2 matches → audit ALL surviving matches. The common case is exactly 2 (one personal + one project, possible only when neither `--scope-only` is set), but the parent-walk can also surface multiple project roots with the same skill name (e.g., `repo/.claude/skills/<name>` AND `repo/packages/frontend/.claude/skills/<name>` from a session started under `frontend`). The shadow-detection finding (lead-side, see "After all tracks complete" in SKILL.md) emits one `scope-resolution` finding per basename appearing in BOTH personal and project scopes; project-internal duplicates (same name across multiple walked project roots) are audited but not synthetically flagged — Claude Code's exact collision-resolution behavior for multiple walked project roots is runtime-dependent and outside `/jr-skill-audit`'s scope to specify, and the user can manually deduplicate if needed.

**Gitignore exclusion (mandatory, per scope)**: After enumeration, drop any skill whose directory is gitignored — those skills are externally maintained (e.g., installed via `npx skills`), not owned by this repo, so findings on them are not actionable here and a local fix would be clobbered on the next update. Apply per-scope independently:
- **Personal scope**: one batched call `git -C "$personalRoot" check-ignore <basename>/SKILL.md ...` — every path it prints is ignored; remove from the target set. Exit 128 (`$personalRoot` not a git repo) → skip personal gitignore filtering only.
- **Project scope**: per project root R (each `<walked-dir>/.claude/skills`), one batched call `git -C "$R" check-ignore <basename>/SKILL.md ...`. The enclosing repo's `.gitignore` is consulted automatically via git's normal walk. Exit 128 → skip filtering for that root only.

**Bare positional** + gitignored: if the single named skill is gitignored in its only resolving scope, abort with `<name> is gitignored in <scope> (externally maintained) — /jr-skill-audit audits repo-owned skills only.` **`--scope` / no-filter**: exclude silently, but list the excluded skill names (with `[personal]` / `[project]` tags) in the Phase 1 discovery summary so the scope reduction is visible.

Return the surviving target set (each tagged `scope=personal|project`) to SKILL.md Track B, which then runs the shared "For each surviving target" read + the "Empty-discovery guard".
