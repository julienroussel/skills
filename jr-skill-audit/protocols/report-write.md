# Phase 7 report-write procedure (`/jr-skill-audit`)

**Skill-local.** The archival report-write body for `/jr-skill-audit` Phase 7 `--report`. Read into lead
context at Phase 1 Track A **only when `--report` or `--report-path` is set** (hard-fail + non-empty +
smoke-parse on two body-only anchors declared at the SKILL.md read site — not restated in this header, so a
body-stripped truncation cannot false-pass). Applied at Phase 7 `### Save report`, after the report has
been rendered to the console per `phase7-report.md`.

The file body written is the **exact rendered report** (the filled `phase7-report.md`, including the
`Generated:` line and any abort marker) — one rendering, used for both console and file. Do NOT assemble a
second body.

**Two writes, by design.** SKILL.md Phase 7 "Order of operations (durability first)" writes the file at
step 2, *before* the declare-done advisor, so an interrupted run still leaves the report on disk; step 4
then re-renders that same body with the `ADVISOR NOTES:` block prepended and rewrites the file (the
same-day overwrite already sanctioned by the rename step below). The second write is the one rendering plus
the notes, never a differently-assembled variant. The console stream is append-only and was printed at
step 1, so it carries the notes as a trailing block instead; the file is the copy that has them at the
top. A run with no advisor concerns, or one where the advisor was skipped, writes once and the two
surfaces are byte-identical.

jr-skill-audit runs no secret-value redaction (it audits skill
*specifications* and loads no secret-pattern catalog), so the file carries the same content the console
showed — the added persistence risk of a written file is handled by the gitignore-enforcement step below,
not by redaction. This is a scoped carve-out from `shared/display-protocol.md`'s report-body redaction
rule (which binds the code-reviewing consumers `/jr-review` and `/jr-audit`). **Residual risk:** under
`--plugin` the audited specs are *untrusted third-party* SKILL.md files and the report is written
out-of-repo (no gitignore mitigation there), so a secret-shaped string in such a spec would persist
un-redacted — a documented known limitation (see `edge-cases.md`).

## Derive the report path

Let `DATE = $(date -u +%Y-%m-%d)`. Resolve `reportPath` by the first matching case:

1. **`--report-path=<p>` set** — sanitize `<p>` per "`--report-path` sanitization" below → `reportPath`.
   If the sanitized value names an existing directory or ends with `/`, append `skill-audit-${DATE}.md`
   inside it.
2. **`--plugin=<name>`** — `reportPath = ~/.claude/skill-audit-reports/skill-audit-plugin-<name>-${DATE}.md`.
   Never write into the third-party marketplace clone — it is owned by the plugin author.
3. **`effectiveScope == project`** — `reportPath = <cwdRepoRoot>/.claude/skill-audit-${DATE}.md`, where
   `cwdRepoRoot = $(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)`. The containing repo
   self-identifies the report, so no scope label is added to the filename.
   **Guard the empty result: `project` scope does not imply a git repo.** `--scope-only=project` sets
   `effectiveScope` unconditionally and `projectRoots` fills from any directory holding `.claude/skills/`,
   git-backed or not; outside a repo `rev-parse` exits 128 and prints nothing, deriving
   `/.claude/skill-audit-<date>.md` at the filesystem root, outside every intended root, and where the
   gitignore probe below self-disables too. So if `cwdRepoRoot` is empty, derive no path: skip the
   archival write per "Failure is non-fatal" below with `<reason>` = `project scope has no containing git
   repo; no default report path`. `--report-path=<path>` remains available for such a run. (The `2>/dev/null`
   matches the `containerRepo` probe below; without it the 128 leaks its stderr into the console report.)
4. **`effectiveScope == personal` or `both`** —
   `reportPath = ~/.claude/skill-audit-reports/skill-audit-<effectiveScope>-${DATE}.md`.

For the cases that derive a `~/…` path (cases 2 and 4), **expand a leading `~`/`~/` in `reportPath` to `$HOME` by string-prefix replacement** before any use — a literal `~` inside a double-quoted shell word does NOT expand and would create a `~` directory in CWD, silently landing the intended out-of-repo report inside the current tree (same rule as `--report-path` sanitization below). Then `mkdir -p "$(dirname "$reportPath")"` (grant `Bash(mkdir -p *)`; keep the resolved path double-quoted).

Only `~/.claude/skill-audit-reports/**` is pre-authorised by the frontmatter Write grant (the Write step
only, from any CWD; the atomic rename below is a separate Bash grant and is not covered). A project-scope
`<cwdRepoRoot>/.claude/**` path is pre-authorised **only when the run was invoked
from the repo root** (`Write(.claude/skill-audit-*)` is CWD-anchored, per Claude Code's permissions doc); from a
subdirectory the Write prompts, and under `--auto-approve`/headless it is skipped (see "Failure is
non-fatal"). A custom `--report-path` is never pre-authorised. In every not-pre-authorised case the user
may add their own `permissions.allow` rule (e.g. `Write(/.claude/**)` in `.claude/settings.json`) for a
prompt-free run.

## Gitignore enforcement (dynamic, unconditional)

Apply `shared/gitignore-enforcement.md` (read at Phase 1 Track A) against `reportPath` — always run the
probe; it no-ops when the path is not inside a repo. Let `reportDir` be the directory containing
`reportPath`, then:

```
containerRepo=$(git -C "$reportDir" rev-parse --show-toplevel 2>/dev/null)
```

- **`containerRepo` empty** (out-of-repo path — the personal/both/plugin default): nothing to enforce; skip.
- **`containerRepo` non-empty** — let `rel` be `reportPath` relative to `containerRepo`:
  1. **Tracked check** — `git -C "$containerRepo" ls-files --error-unmatch "$rel" 2>/dev/null`. If it
     exits 0 (tracked), **warn** — or, under `--auto-approve`/headless, log the warning to the report's
     `Audit integrity` section — with the reason: *"skill-audit reports carry audited skill paths, line
     numbers, and 3-line code excerpts — they should not be committed."* Do NOT untrack (the user may have
     committed it deliberately).
  2. **Ignored check** — `git -C "$containerRepo" check-ignore -q --no-index "$rel"`. **`--no-index` is
     mandatory**: without it `check-ignore` skips any *tracked* file and exits non-zero whatever the
     rules say, so a report that is both committed and correctly ignored would be reported as
     un-ignored and the user advised to add a glob already in `.gitignore`. If it returns non-zero (not
     ignored), **inform** the user (advisory, no mutation) with a glob derived from the *resolved* path,
     never a hardcoded one: for the default/project path (`rel = .claude/skill-audit-<date>.md`) suggest
     `.claude/skill-audit-*` — one glob covers every dated report **and** its `.md.tmp` atomic sidecar;
     for a custom `--report-path` whose `rel` is elsewhere, suggest `<rel>` and `<rel>.tmp` (or a covering
     glob under `$(dirname "$rel")`). Message: *"This report is not gitignored. Add `<suggested-pattern>`
     to `<containerRepo>/.gitignore` to keep it (and its `.tmp` sidecar) uncommitted."* jr-skill-audit
     does NOT auto-append — `Edit` is disallowed and the report is findings-only output; this mirrors
     `/jr-audit`'s own `--out` inside-repo handling (jr-audit/SKILL.md `### Save report`).

## Atomic write

Write the rendered report body to `"${reportPath}.tmp"`, then `mv "${reportPath}.tmp" "$reportPath"`,
overwriting if `reportPath` exists. Two cases legitimately overwrite: a same-day, same-scope **re-run**
replaces its predecessor (matching `/jr-audit`), and **within one run** the step-4 rewrite replaces the
step-2 write once the advisor has returned (see "Two writes, by design" above). **No `--` separator.** A grant's literal part is matched against the command string, so a
`--` sitting as the first token after `mv` matches none of the narrow `mv` grants in frontmatter; it is
also unnecessary, because both operands derive from the one sanitized `reportPath` and every case above
resolves to an absolute path (`$HOME`, `$PWD`, or a repo root), so neither can be read as an option.

A `mv` the frontmatter grants do not match prompts in addition to the `Write`, and under
`--auto-approve`/headless it cannot prompt, so the archival write is skipped per "Failure is non-fatal"
below; the grant-narrowing rationale (and why a findings-only skill does not take a bare `mv *`) lives in
`docs/skill-anatomy.md` "Grant and model rationale, by skill". **Every rename this section issues is such
a case**: the absolute-path property above is what defeats the two grants meant to cover it, since
`Bash(mv ~/.claude/skill-audit-reports/*)` and `Bash(mv .claude/skill-audit-*)` are a literal-`~` and a
relative pattern, and Claude Code documents `~/` and CWD anchoring for Read/Edit and Cd **path** patterns
only, never for Bash rules, whose pattern is matched against the command string as written.

<!-- harness-claim-verified: 2026-08-08 -->
<!-- Checked 2026-08-08 against the permissions doc ("Tool-specific permission rules" -> Bash, and ->
     Read and Edit): the Bash subsection specifies `*` wildcard matching over the command string and
     names no path anchors; the `~/path` "path from home directory" row belongs to the Read/Edit
     pattern table, which the Cd subsection explicitly borrows and the Bash subsection does not. Doc
     read only, NOT a live probe of the matcher. Re-verify against a real prompt, or re-read that
     section, before relying on either grant. -->


What bounds the destination is the sanitizer plus the `Write`, not the `mv` grant: "`--report-path`
sanitization" below rejects shell/glob-active characters and any destination inside a skills directory,
and the rename's source `"${reportPath}.tmp"` has to be created by `Write` first. The tmp+rename avoids a
torn file if the run is interrupted mid-write, mirroring the refs.json atomic pattern (SKILL.md Phase 1
Track C). After a successful write, print the saved path on its own line: `Report written: <reportPath>`.

## Failure is non-fatal

The console report is the primary deliverable; the file is archival. If `mkdir -p`, the Write, or the `mv`
fails for any reason — permission denied, disk full, a declined interactive Write prompt, or an
`--auto-approve`/headless run where a not-pre-authorised path cannot prompt — do NOT abort and do NOT force
a non-zero exit on that account. Emit one line: *"Report file not written: <reason>. Console output above
is the record."* and continue to normal Phase 7 completion.

**When the Write succeeded and only the rename failed, the `.tmp` sidecar is orphaned and no cleanup is
possible**: this skill grants no `rm` at all, so `"${reportPath}.tmp"` stays on disk until the user
removes it. That is the expected outcome, not a bug to work around, so name the file in the same line
rather than leaving it unmentioned: *"Report file not written: <reason>. A partial copy is at
<reportPath>.tmp; remove it manually. Console output above is the record."*

Exit code is still governed by the existing
rules — an unrelated abort or `unreportedCount > 0` still exits non-zero; a report-write failure alone does
not.

## `--report-path` sanitization

Mirrors `/jr-audit`'s `--out` sanitizer (jr-audit/SKILL.md "Parameter sanitization"; if a third consumer
appears, promote to `shared/`). The resolved directory is passed to `mkdir -p`, so: reject values
containing control characters (NUL, newline, carriage return) or any shell/glob-active character (a
backtick, or any of `$ \ " ' ; | & < > ( ) { } * ? [ ] !`), with the error
`Invalid --report-path: unsupported character.`; every other character (letters, digits,
`/ . - _ ~ + , @ =`, space) is a literal path character. Expand a LEADING `~` or `~/` to `$HOME` by
string-prefix replacement (never by passing the raw value through an unquoted shell); resolve a
non-absolute result against `$PWD`. `..` is permitted (the destination is user-chosen). Double-quote the
resolved path in `mkdir -p` and any shell context; hand the resolved absolute path to the Write tool
(which runs no shell).

**Reject destinations inside a skills directory.** Because `..` and absolute paths are both permitted,
nothing else stops `--report-path=~/.claude/skills/jr-audit/SKILL.md` from overwriting an audited skill
with a findings report, and the skill states "**Findings-only**, never modifies skill files" twice as a
headline invariant. Apply the check at "Derive the report path" step 1, **after** the
`skill-audit-${DATE}.md` append and **before** `mkdir -p`: the pre-append value's parent is the wrong
operand (for `--report-path=~/.claude/skills/jr-audit` it is the skills root itself and the audited
skill dir is the value, so both arms of the predicate look one level too high), and running after
`mkdir -p` would already have created a directory inside the audited tree. Both the dispatched skill
directories and `realpath` itself are settled by then: Track B has run, and it aborts
`realpath-unavailable` when the binary is absent.

1. **Expand a leading `~`/`~/` to `$HOME` by string-prefix replacement on both operands** before
   comparing. A literal `~` inside a double-quoted word does not expand, so comparing against the
   literal string `~/.claude/skills/` never matches and the reject silently never fires.
2. **Resolve the deepest existing ancestor**: the destination's parent need not exist yet at this point
   and plain `realpath` fails on a path that does not, so start at `dirname "$reportPath"` and walk up
   with `dirname` until the candidate is a directory. Any component created below it lands inside
   whatever that ancestor resolves to, so it is the correct operand.
3. **Canonicalize BOTH sides** and compare with the trailing-slash discipline of
   `finding-validation.md` "Contain before opening", against `$HOME/.claude/skills` and against each
   dispatched skill directory:

   ```
   destCanon="$(realpath -- "$destDir")"
   skillsRootCanon="$(realpath -- "$HOME/.claude/skills")"
   case "$destCanon/" in "$skillsRootCanon"/*) reject ;; esac
   for skillDir in <each dispatched skill directory, Track B>; do
     skillDirCanon="$(realpath -- "$skillDir")"
     case "$destCanon/" in "$skillDirCanon"/*) reject ;; esac
   done
   ```

   The trailing `/` on the left makes the predicate **inclusive of the skills root itself** (`*` matches
   the empty string), so `--report-path=~/.claude/skills/x.md` is caught as well as anything nested under
   a skill, while `…/skills-archive/` still does not match `…/skills/*`.
   **The loop is not redundant with the `$HOME` arm**: under a project-scope or `--plugin` audit the
   dispatched directories are `<repo>/.claude/skills/<name>` or a marketplace clone, neither of which any
   `$HOME/.claude/skills` comparison covers, so the `$HOME` arm alone lets a `--report-path` pointing
   inside an audited skill through the guard the headline "never modifies skill files" invariant rests on.
4. **Fail closed**: if any `realpath` above exits non-zero or returns empty, reject. Resolving only the left
   side, or falling through on an error, fails **open** here (the reject never fires) whenever
   `~/.claude/skills` or a parent is a symlink, routine under `stow`/`chezmoi`. Keep the two variants
   apart. A *symlink mismatch* fails **closed** in `finding-validation.md` (findings dropped, loudly) and
   **open** here. An *empty or errored* operand fails **open at both**, and by the same mechanism:
   `"$root"/*` collapses to `/*`, which matches every absolute path; here that silences the reject, and
   in a `keep` arm it admits everything. Both sites therefore spell the empty/error check out explicitly
   (`finding-validation.md` "Contain before opening", "Fail closed on an unresolvable operand"); neither
   inherits it by reference, because the safe fallthrough differs between them.

Rejection message: `Invalid --report-path: destination is inside a skills directory; /jr-skill-audit
never writes into audited skills.` This fires at Phase 7, not at argument parse, so it is **not** an
abort and does not force a non-zero exit: skip the archival write per "Failure is non-fatal" above,
emitting that section's single advisory line with this message as `<reason>`. The console report is
unaffected.
