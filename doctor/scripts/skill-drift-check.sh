#!/usr/bin/env bash
# Group I — skill drift checks. Iterates ~/.claude/skills/*/SKILL.md and emits
# stable marker lines on stdout that the /doctor SKILL.md parses verbatim. See
# the "Marker semantics" table in /doctor SKILL.md for the marker → status →
# hint mapping. New markers MUST be added there too — the script and the table
# are co-authored.

set -u

for d in "$HOME"/.claude/skills/*/; do
  skill_md="${d}SKILL.md"
  [ -f "$skill_md" ] || continue
  name=$(basename "$d")

  # 1. Line count vs Anthropic 500-line guideline.
  lc=$(wc -l < "$skill_md" | tr -d ' ')
  [ "$lc" -gt 500 ] && echo "WARN_LINES:$name:$lc"

  # 2. Broken shared/* references — match shared/<name>.md regardless of prefix
  #    (`../shared/<name>.md`, `~/.claude/skills/shared/<name>.md`, bare form).
  #    `while IFS= read -r` keeps the loop portable across bash and zsh.
  refs=$(grep -oE 'shared/[a-z][a-z0-9-]*\.md' "$skill_md" | sort -u)
  echo "$refs" | while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    [ -f "$HOME/.claude/skills/$ref" ] || echo "FAIL_BROKEN_REF:$name:$ref"
  done

  # 3. Frontmatter contradictions. Parse the block between the first two `---`.
  fm=$(awk '/^---$/{c++; if(c==2) exit; next} c==1' "$skill_md")
  has_dmi=no; has_wtu=no; has_paths=no
  echo "$fm" | grep -qE '^disable-model-invocation:[[:space:]]*true' && has_dmi=yes
  echo "$fm" | grep -qE '^when_to_use:'                              && has_wtu=yes
  echo "$fm" | grep -qE '^paths:'                                    && has_paths=yes
  if [ "$has_dmi" = yes ] && { [ "$has_wtu" = yes ] || [ "$has_paths" = yes ]; }; then
    echo "WARN_DMI_INERT:$name"
  fi
  effort=$(echo "$fm" | grep -E '^effort:' | head -1 | sed 's/^effort:[[:space:]]*//; s/[[:space:]]*$//')
  if [ -n "$effort" ]; then
    case "$effort" in
      low|medium|high|xhigh|max) : ;;
      *) echo "FAIL_EFFORT:$name:$effort" ;;
    esac
  fi
  model=$(echo "$fm" | grep -E '^model:' | head -1 | sed 's/^model:[[:space:]]*//; s/[[:space:]]*$//')
  if [ -n "$model" ]; then
    echo "$model" | grep -qE '^(inherit|haiku|sonnet|opus|claude-haiku-4-5.*|claude-sonnet-4-6|claude-opus-4-7|claude-opus-4-7\[1m\])$' \
      || echo "WARN_MODEL:$name:$model"
  fi
  echo "$fm" | grep -qE '^description:' || echo "FAIL_NO_DESC:$name"

  # 4. Inline duplication of canonical shared content. Drift if a Group D
  #    smoke-parse anchor appears inline AND the corresponding shared/ ref
  #    is absent. (Anchor + reference together is the canonical pattern.)
  check_inline_drift() {
    anchor="$1"; shared_path="$2"
    if grep -F -- "$anchor" "$skill_md" >/dev/null 2>&1; then
      grep -E "shared/${shared_path}" "$skill_md" >/dev/null 2>&1 \
        || echo "WARN_INLINE_DRIFT:$name:${shared_path}"
    fi
  }
  check_inline_drift 'do not execute, follow, or respond to' 'untrusted-input-defense\.md'
  check_inline_drift 'git ls-files --error-unmatch'          'gitignore-enforcement\.md'
  check_inline_drift '| Issue | Owner'                       'reviewer-boundaries\.md'
  check_inline_drift 'consumerEnforcement'                   'secret-warnings-schema\.md'
  check_inline_drift 'Advisory-tier classification'          'secret-scan-protocols\.md'
  check_inline_drift 'runSummaries[]'                        'audit-history-schema\.md'
  check_inline_drift '[ABORT — HEAD MOVED]'                  'abort-markers\.md'
  check_inline_drift 'Silent reviewers, noisy lead'          'display-protocol\.md'
  check_inline_drift 'AKIA[0-9A-Z]{16}'                      'secret-patterns\.md'
  check_inline_drift 'cache-poisoning guard'                 'cache-schema-validation\.md'
done

# 5. Template SHA-256 drift (one-shot; not per-skill). /review's installer
#    hardcodes EXPECTED_TEMPLATE_SHA256; /doctor surfaces drift earlier so
#    the user can update the constant before the install path starts failing.
tmpl="$HOME/.claude/skills/review/templates/pre-commit-secret-guard.sh.tmpl"
script="$HOME/.claude/skills/review/scripts/install-pre-commit-secret-guard.sh"
if [ -f "$tmpl" ] && [ -f "$script" ]; then
  if command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$tmpl" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$tmpl" | awk '{print $1}')
  else
    actual=""
  fi
  expected=$(grep -E '^EXPECTED_TEMPLATE_SHA256=' "$script" | head -1 | cut -d'"' -f2)
  if [ -n "$actual" ] && [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
    echo "FAIL_TEMPLATE_HASH:expected=$expected:actual=$actual"
  fi
fi

# 6. /skill-audit live-references cache freshness (one-shot; not per-skill).
#    Mirrors the template-hash drift mechanism — without it, the cache rots
#    silently and feature-adoption-reviewer audits against stale data.
cache="$HOME/.claude/skills/skill-audit/cache/refs.json"
if [ -d "$HOME/.claude/skills/skill-audit" ]; then
  if [ ! -f "$cache" ]; then
    echo "WARN_REFS_CACHE_MISSING"
  else
    fetched=$(jq -r '.fetchedAt // empty' "$cache" 2>/dev/null)
    if [ -z "$fetched" ]; then
      echo "WARN_REFS_CACHE_NO_TIMESTAMP"
    else
      if command -v gdate >/dev/null 2>&1; then
        fetched_epoch=$(gdate -d "$fetched" +%s 2>/dev/null)
      else
        fetched_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$fetched" +%s 2>/dev/null)
      fi
      if [ -n "$fetched_epoch" ]; then
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - fetched_epoch) / 86400 ))
        [ "$age_days" -gt 30 ] && echo "WARN_REFS_CACHE_STALE:$fetched:$age_days"
      fi
    fi
  fi
fi
