# Phase 7 report-write procedure (`/jr-skill-audit`)

**Skill-local.** The archival report-write body for `/jr-skill-audit` Phase 7 `--report`. Read into lead
context at Phase 1 Track A **only when `--report` or `--report-path` is set** (hard-fail + non-empty +
smoke-parse on two body-only anchors declared at the SKILL.md read site — not restated in this header, so a
body-stripped truncation cannot false-pass). Applied at Phase 7 `### Save report`, after the report has
been rendered to the console per `phase7-report.md`.

The file body written is the **exact console-rendered report** (the filled `phase7-report.md`, including
the `Generated:` line, any `ADVISOR NOTES:` prepend, and any abort marker) — one rendering for console and
file. Do NOT assemble a second body. jr-skill-audit runs no secret-value redaction (it audits skill
*specifications* and loads no secret-pattern catalog), so the file carries exactly what the console
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
   `cwdRepoRoot = $(git -C "$PWD" rev-parse --show-toplevel)`. The containing repo self-identifies the
   report, so no scope label is added to the filename.
4. **`effectiveScope == personal` or `both`** —
   `reportPath = ~/.claude/skill-audit-reports/skill-audit-<effectiveScope>-${DATE}.md`.

For the cases that derive a `~/…` path (cases 2 and 4), **expand a leading `~`/`~/` in `reportPath` to `$HOME` by string-prefix replacement** before any use — a literal `~` inside a double-quoted shell word does NOT expand and would create a `~` directory in CWD, silently landing the intended out-of-repo report inside the current tree (same rule as `--report-path` sanitization below). Then `mkdir -p "$(dirname "$reportPath")"` (grant `Bash(mkdir -p *)`; keep the resolved path double-quoted).

Only `~/.claude/skill-audit-reports/**` is pre-authorised by the frontmatter Write grant (prompt-free from
any CWD). A project-scope `<cwdRepoRoot>/.claude/**` path is pre-authorised **only when the run was invoked
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
  2. **Ignored check** — `git -C "$containerRepo" check-ignore -q "$rel"`. If it returns non-zero (not
     ignored), **inform** the user (advisory, no mutation) with a glob derived from the *resolved* path,
     never a hardcoded one: for the default/project path (`rel = .claude/skill-audit-<date>.md`) suggest
     `.claude/skill-audit-*` — one glob covers every dated report **and** its `.md.tmp` atomic sidecar;
     for a custom `--report-path` whose `rel` is elsewhere, suggest `<rel>` and `<rel>.tmp` (or a covering
     glob under `$(dirname "$rel")`). Message: *"This report is not gitignored. Add `<suggested-pattern>`
     to `<containerRepo>/.gitignore` to keep it (and its `.tmp` sidecar) uncommitted."* jr-skill-audit
     does NOT auto-append — `Edit` is disallowed and the report is findings-only output; this mirrors
     `/jr-audit`'s own `--out` inside-repo handling (jr-audit/SKILL.md `### Save report`).

## Atomic write

Write the rendered report body to `"${reportPath}.tmp"`, then `mv -- "${reportPath}.tmp" "$reportPath"`
(grants `Write(…)`, `Bash(mv *)`) — overwrite if `reportPath` exists (a same-day, same-scope re-run
replaces its predecessor, matching `/jr-audit`). The tmp+rename avoids a torn file if the run is
interrupted mid-write; it mirrors the refs.json atomic pattern (SKILL.md Phase 1 Track C). After a
successful write, print the saved path on its own line: `Report written: <reportPath>`.

## Failure is non-fatal

The console report is the primary deliverable; the file is archival. If `mkdir -p`, the Write, or the `mv`
fails for any reason — permission denied, disk full, a declined interactive Write prompt, or an
`--auto-approve`/headless run where a not-pre-authorised path cannot prompt — do NOT abort and do NOT force
a non-zero exit on that account. Emit one line: *"Report file not written: <reason>. Console output above
is the record."* and continue to normal Phase 7 completion. Exit code is still governed by the existing
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
