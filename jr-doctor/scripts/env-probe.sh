#!/usr/bin/env bash
# Groups A/B/C/E/F/G/H — environment probe. Emits stable marker lines on stdout that
# /jr-doctor SKILL.md grades. Same contract as scripts/skill-drift-check.sh: the script
# reports FACTS, the lead applies the ✓/⚠/✗ grading. New markers MUST be added to the
# "Marker semantics" table in jr-doctor/examples.md — the script and the table are
# co-authored.
#
# Usage: env-probe.sh <REPO_ROOT|none> <yes|no>
#   $1  absolute repo root, or the literal "none" when the caller is not in a git repo
#       (Group F is then skipped)
#   $2  "yes" inside a tackle worktree, which suppresses the .claude/worktrees/
#       tracked-cache markers; "no" otherwise
#   Both are required and neither defaults. An argument that never arrived must not read as
#   a genuine "not in a repo" or "not a worktree" answer, so an empty or malformed one is
#   reported through PROBE_ARGS: and the facts that depend on it are withheld.
#
# Every marker is `^[A-Z][A-Z0-9_]*:` shaped. A group that finds nothing emits nothing
# for that condition — absence of a marker is the pass, exactly as in skill-drift-check.sh.
# Absence is only a pass on a run that reached the end, so the final line is
# `PROBE_COMPLETE: ok`. Without it the output was truncated or the script died, and no
# group may be graded from it.

set -u

if [ "$#" -lt 2 ]; then
  echo "PROBE_ARGS: got $# argument(s), expected 2 (<repo-root|none> <yes|no>)"
fi
REPO_ROOT="${1:-}"
IS_TACKLE_WORKTREE="${2:-}"
case "$IS_TACKLE_WORKTREE" in
  yes|no) ;;
  *) echo "PROBE_ARGS: worktree flag was '$IS_TACKLE_WORKTREE', expected yes|no; .claude/worktrees/ entries are reported below, not suppressed"
     IS_TACKLE_WORKTREE=no ;;
esac
SETTINGS="$HOME/.claude/settings.json"
SKILLS="$HOME/.claude/skills"
have_jq=no
command -v jq >/dev/null 2>&1 && have_jq=yes

# ---------- Group A — CLI tools ----------
echo "GROUP: A"
for c in git jq claude rtk wt; do
  command -v "$c" >/dev/null 2>&1 || echo "CLI_MISSING: $c"
done

gh_present=no; glab_present=no
command -v gh   >/dev/null 2>&1 && gh_present=yes
command -v glab >/dev/null 2>&1 && glab_present=yes
echo "FORGE_CLI: gh=$gh_present glab=$glab_present"

if [ "$gh_present" = yes ]; then
  if gh auth status >/dev/null 2>&1; then echo "GH_AUTH: ok"; else echo "GH_AUTH: failed"; fi
else
  echo "GH_AUTH: absent"
fi
if [ "$glab_present" = yes ]; then
  if glab auth status >/dev/null 2>&1; then echo "GLAB_AUTH: ok"; else echo "GLAB_AUTH: failed"; fi
else
  echo "GLAB_AUTH: absent"
fi
if command -v rtk >/dev/null 2>&1; then
  if rtk --version 2>&1 | grep -qE '^rtk '; then echo "RTK_VARIANT: ok"; else echo "RTK_VARIANT: unknown"; fi
else
  echo "RTK_VARIANT: absent"
fi

# ---------- Group B — settings.json ----------
echo "GROUP: B"
if [ ! -f "$SETTINGS" ]; then
  echo "SETTINGS: absent"
elif [ "$have_jq" = no ]; then
  # `jq empty` exits 127 when jq is not installed, so the negation below used to blame a
  # perfectly healthy settings.json and send the user off to repair it. Report the cause.
  echo "SETTINGS: no-jq"
elif ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  echo "SETTINGS: unparseable"
else
  echo "SETTINGS: ok"
  if [ -n "$(jq -r '.advisorModel // empty' "$SETTINGS" 2>/dev/null)" ]; then
    echo "ADVISOR_MODEL: set"
  else
    echo "ADVISOR_MODEL: missing"
  fi
  echo "PLUGIN_WORKTRUNK: $(jq -r '.enabledPlugins["worktrunk@worktrunk"] // "missing"' "$SETTINGS" 2>/dev/null)"
  # Each required rule reported on its own: a count cannot tell two copies of one rule from
  # one copy of each, and it cannot name the one that is actually missing.
  for rule in 'Edit(.claude/**)' 'Write(.claude/**)'; do
    [ -n "$(jq -r --arg r "$rule" '.permissions.allow // [] | map(select(. == $r)) | .[0] // empty' "$SETTINGS" 2>/dev/null)" ] \
      || echo "PERM_MISSING: $rule"
  done
  echo "DEFAULT_MODE: $(jq -r '.permissions.defaultMode // "missing"' "$SETTINGS" 2>/dev/null)"
fi

# ---------- Group C — skills installed + shared files + agents ----------
echo "GROUP: C"
for f in jr-audit/SKILL.md jr-review/SKILL.md jr-ship/SKILL.md \
         bin/tackle bin/seed-project-memory bin/tackle-top \
         shared/reviewer-boundaries.md shared/untrusted-input-defense.md shared/gitignore-enforcement.md \
         docs/worktree-architecture.md; do
  [ -e "$SKILLS/$f" ] || echo "FILE_MISSING: $f"
done
for b in bin/tackle bin/seed-project-memory bin/tackle-top; do
  [ -x "$SKILLS/$b" ] || echo "NOT_EXECUTABLE: $b"
done
# Scripts a skill invokes directly rather than through an interpreter: a cleared exec bit
# takes out the phase that calls it. env-probe.sh is listed for completeness but cannot
# report its own cleared bit: the lead then gets no output at all, which is the case the
# PROBE_COMPLETE: sentinel covers.
for s in jr-doctor/scripts/env-probe.sh jr-doctor/scripts/skill-drift-check.sh \
         jr-review/scripts/establish-base-anchor.sh jr-review/scripts/install-pre-commit-secret-guard.sh; do
  if [ ! -f "$SKILLS/$s" ]; then
    echo "FILE_MISSING: $s"
  elif [ ! -x "$SKILLS/$s" ]; then
    echo "NOT_EXECUTABLE: $s"
  fi
done
# -e follows the symlink, so a dangling ~/.claude/agents link still reports MISSING_AGENT.
for a in jr-reviewer jr-implementer; do
  [ -e "$HOME/.claude/agents/$a.md" ] || echo "MISSING_AGENT: ~/.claude/agents/$a.md"
done
# jr-reviewer must stay read-only: no Write/Edit tools (/jr-i18n's no-write rests on this). A native
# subagent with NO tools: line inherits ALL tools (incl. Write/Edit), so a missing tools: line must FAIL,
# not pass silently. Scan only the YAML frontmatter so a body mention of "Write/Edit" can't false-fire.
if [ -e "$HOME/.claude/agents/jr-reviewer.md" ]; then
  fm=$(awk 'NR==1 && /^---/{f=1; next} f && /^---/{exit} f' "$HOME/.claude/agents/jr-reviewer.md")
  if ! printf '%s\n' "$fm" | grep -qE '^tools:'; then
    echo "AGENT_NOT_READONLY: jr-reviewer has no 'tools:' line (a subagent with no tools list inherits ALL tools, incl. Write/Edit)"
  else
    # Whole tool names only. A substring match on Write|Edit also fires on TodoWrite, a
    # built-in that writes no repo file. Normalise the three YAML spellings (`tools: A, B`,
    # a `- B` block list, and a `[A, B]` flow sequence, quoted or not) to one token per line
    # so the comparison below is exact.
    granted=$(printf '%s\n' "$fm" | awk '
      function toks(s,   n, a, i) {
        gsub(/[][",]/, " ", s); gsub("\047", " ", s)
        n = split(s, a, /[ \t]+/)
        for (i = 1; i <= n; i++) if (a[i] != "") print a[i]
      }
      /^tools:/                   { intools = 1; sub(/^tools:[[:space:]]*/, ""); toks($0); next }
      intools && /^[[:space:]]*-/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); toks($0); next }
      /^[^[:space:]]/             { intools = 0 }
    ')
    for t in Write Edit MultiEdit NotebookEdit; do
      if printf '%s\n' "$granted" | grep -qxF -- "$t"; then
        echo "AGENT_NOT_READONLY: jr-reviewer tools: grants $t"
        break
      fi
    done
  fi
fi

# ---------- Group E — hooks + memory dir ----------
echo "GROUP: E"
for h in no-claude-attribution cbm-code-discovery-gate cbm-session-reminder; do
  [ -x "$HOME/.claude/hooks/$h" ] || echo "HOOK_MISSING: $h"
done
[ -d "$HOME/.claude/projects" ] || echo "PROJECTS_DIR_MISSING: ~/.claude/projects"
# jq -r + stdout-empty checks (NOT jq -e, which exits non-zero on no-match).
# The `?` after `[]` suppresses jq errors when an array is missing entirely.
if [ -f "$SETTINGS" ] && [ "$have_jq" = yes ] && jq empty "$SETTINGS" >/dev/null 2>&1; then
  [ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Bash")) | .hooks[].command | select(. == "rtk hook claude")' "$SETTINGS" 2>/dev/null)" ] || echo "HOOK_NOT_WIRED: rtk hook claude"
  [ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Bash")) | .hooks[].command | select(. == "~/.claude/hooks/no-claude-attribution")' "$SETTINGS" 2>/dev/null)" ] || echo "HOOK_NOT_WIRED: no-claude-attribution"
  [ -n "$(jq -r '.hooks.PreToolUse[]? | select(.matcher | test("Read")) | .hooks[].command | select(. == "~/.claude/hooks/cbm-code-discovery-gate")' "$SETTINGS" 2>/dev/null)" ] || echo "HOOK_NOT_WIRED: cbm-code-discovery-gate"
  [ -n "$(jq -r '.hooks.SessionStart[]? | .hooks[].command | select(. == "~/.claude/hooks/cbm-session-reminder")' "$SETTINGS" 2>/dev/null)" ] || echo "HOOK_NOT_WIRED: cbm-session-reminder"
else
  # Three states have to stay distinguishable: wired (no marker), not wired
  # (HOOK_NOT_WIRED:), and never checked. Silence alone graded the last one as 4/4 wired.
  echo "HOOK_WIRING: unchecked"
fi

# ---------- Group F — per-repo checks ----------
echo "GROUP: F"
if [ "$REPO_ROOT" = none ]; then
  echo "REPO: none"
elif [ -z "$REPO_ROOT" ]; then
  # Not the same thing as "not in a git repo": the caller passed nothing, so every check
  # below is withheld rather than skipped, and the lead is told which of the two happened.
  echo "REPO: unknown"
else
  echo "REPO: $REPO_ROOT"
  [ -f "$REPO_ROOT/CLAUDE.md" ]  || echo "REPO_MISSING: CLAUDE.md"
  [ -d "$REPO_ROOT/.claude" ]    || echo "REPO_MISSING: .claude"
  [ -f "$REPO_ROOT/.gitignore" ] || echo "REPO_MISSING: .gitignore"
  # Which forge, not just "a forge": whether a missing gh or glab matters depends on the host
  # this repo needs, and collapsing both to "forge" made that join impossible. Same predicate
  # as before (any remote, either host); github wins when both appear.
  remotes=$(git -C "$REPO_ROOT" remote -v 2>/dev/null)
  case "$remotes" in
    *github.com*) echo "REPO_REMOTE: github" ;;
    *gitlab.com*) echo "REPO_REMOTE: gitlab" ;;
    *)            echo "REPO_REMOTE: none" ;;
  esac

  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # Everything below is a git query. Without this guard an unusable REPO_ROOT returned
    # empty output from each one and absence-is-the-pass certified the repo clean.
    echo "REPO_QUERY_FAILED: $REPO_ROOT is not a usable git work tree"
  else
    # Tracked-cache scan. One call with its status checked: the previous four calls each
    # discarded stderr and ignored their exit status, so any git failure read as "no tracked
    # cache files" for the check whose whole job is catching a committed secret-warnings.json.
    tracked=$(git -C "$REPO_ROOT" ls-files -- \
      .claude/review-profile.json .claude/review-baseline.json .claude/review-config.md \
      .claude/audit-history.json .claude/health.json .claude/secret-warnings.json \
      .claude/secret-hook-patterns.txt '.claude/audit-report-*.md' \
      '.claude/secret-warnings-*.json' '.claude/worktrees/' 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "REPO_QUERY_FAILED: git ls-files exited non-zero in $REPO_ROOT"
    else
      printf '%s\n' "$tracked" | while IFS= read -r p; do
        [ -n "$p" ] || continue
        case "$p" in
          .claude/worktrees/*) [ "$IS_TACKLE_WORKTREE" = yes ] && continue ;;
        esac
        echo "TRACKED_CACHE: $p"
      done
    fi

    # Gitignore coverage.
    #
    # WHAT THIS CHECKS: whether the repo's own .gitignore stops each canonical cache path
    # from being committed. git is the arbiter, not a line match. A line match was wrong in
    # both directions: `.claude/**`, `/.claude/` and bare `.claude` are blanket forms git
    # honours but it did not recognise, and a later `!.claude/secret-warnings.json` negation
    # re-includes that path under `.claude/*` while it still read as covered.
    # IN SCOPE: the repo's tracked .gitignore files, i.e. the protection a collaborator
    # inherits on clone.
    # OUT OF SCOPE, deliberately: core.excludesFile (neutralised below) and
    # .git/info/exclude. Both make git ignore the path on this machine only, so counting
    # them as coverage would certify a repo whose next contributor commits the file. git
    # offers no flag to suppress .git/info/exclude, so that one is a known, accepted gap.
    # --no-index so an already-tracked path is judged on the rules alone; tracked-ness is
    # what TRACKED_CACHE: above reports.
    if [ ! -f "$REPO_ROOT/.gitignore" ]; then
      echo "GITIGNORE_ABSENT: $REPO_ROOT/.gitignore"
    else
      for entry in \
        '.claude/review-profile.json' \
        '.claude/review-baseline.json' \
        '.claude/review-config.md' \
        '.claude/audit-history.json' \
        '.claude/health.json' \
        '.claude/audit-report-*.md|.claude/audit-report-2026-01-01.md' \
        '.claude/secret-warnings.json' \
        '.claude/secret-warnings-*.json|.claude/secret-warnings-1.json' \
        '.claude/secret-hook-patterns.txt' \
        '.claude/secret-warnings*.json.tmp|.claude/secret-warnings.json.tmp' \
        '.claude/secret-warnings*.json.lock|.claude/secret-warnings.json.lock' \
        '.claude/secret-warnings*.json.corrupt-*|.claude/secret-warnings.json.corrupt-1' \
        '.claude/worktrees/|.claude/worktrees/probe'; do
        pat=${entry%%|*}    # canonical pattern: what is reported, and what --fix appends
        probe=${entry#*|}   # a concrete path the pattern must match (equals pat when no |)
        git -C "$REPO_ROOT" -c core.excludesFile=/dev/null \
          check-ignore --no-index -q -- "$probe" >/dev/null 2>&1
        rc=$?
        case $rc in
          0) ;;
          1) echo "GITIGNORE_MISSING_PATTERN: $pat" ;;
          *) echo "REPO_QUERY_FAILED: git check-ignore exited $rc in $REPO_ROOT"
             break ;;
        esac
      done
    fi
  fi
fi

# ---------- Group H — Claude Code runtime ----------
echo "GROUP: H"
for v in CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS CLAUDE_CODE_NO_FLICKER CLAUDECODE CLAUDE_CODE_ENTRYPOINT; do
  eval "val=\${$v:-}"
  if [ -n "$val" ]; then echo "ENV: $v=$val"; else echo "ENV: $v=<unset>"; fi
done
if command -v claude >/dev/null 2>&1; then
  echo "CLAUDE_VERSION: $(claude --version 2>&1 | head -1)"
fi
# Optional tunables — printed only when explicitly set, so the report stays compact.
for v in BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS MCP_TIMEOUT MCP_TOOL_TIMEOUT \
         MAX_THINKING_TOKENS MAX_MCP_OUTPUT_TOKENS CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY \
         DISABLE_TELEMETRY DISABLE_AUTOUPDATER CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC; do
  val=$(printenv "$v" 2>/dev/null) && [ -n "$val" ] && echo "TUNABLE: $v=$val"
done

# ---------- Group G — codebase-memory-mcp probe ----------
# Ordered last on purpose. `claude mcp list` is the one network call in this script: it
# contacts every configured MCP server and can spawn npx (measured at 6.6s of an 8.0s run),
# so a stalled or unreachable server must not delay or truncate the groups that need no
# network, including the CLAUDE_VERSION line the report header wants.
echo "GROUP: G"
if command -v claude >/dev/null 2>&1; then
  # Bound it wherever a timeout binary exists. Base macOS userland ships neither `timeout`
  # nor `gtimeout` (both arrive with homebrew coreutils), so degrade to an unbounded call
  # there rather than dropping the probe.
  mcp_timeout=""
  if command -v timeout >/dev/null 2>&1; then
    mcp_timeout="timeout 15"
  elif command -v gtimeout >/dev/null 2>&1; then
    mcp_timeout="gtimeout 15"
  fi
  mcp_out=$($mcp_timeout claude mcp list 2>&1)
  mcp_rc=$?
  if [ "$mcp_rc" -eq 124 ]; then
    echo "MCP_CBM: unprobeable (claude mcp list timed out after 15s)"
  elif printf '%s\n' "$mcp_out" | grep -qE 'codebase-memory(-mcp)?'; then
    echo "MCP_CBM: configured"
  else
    echo "MCP_CBM: not-configured"
  fi
else
  echo "MCP_CBM: unprobeable (claude CLI not on PATH)"
fi

# Completion sentinel, deliberately the last line. Absence-is-the-pass only holds for a run
# that reached here, so its absence means "nothing was graded", not "seven clean groups".
echo "PROBE_COMPLETE: ok"
exit 0
