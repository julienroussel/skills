#!/usr/bin/env bash
# Group I — skill drift checks. Iterates ~/.claude/skills/*/SKILL.md and emits
# stable marker lines on stdout that the /jr-doctor SKILL.md parses verbatim. See
# the "Marker semantics" table in /jr-doctor SKILL.md for the marker → status →
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
    echo "$model" | grep -qE '^(inherit|haiku|sonnet|opus|claude-(haiku|sonnet|opus)-[0-9]+-[0-9]+(-[0-9]+)?(\[[a-z0-9]+\])?)$' \
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
  # Canonical anchor source: ~/.claude/skills/shared/phase1-track-a-protocol.md
  # (Canonical Anchor Table). Each row below corresponds to a row in the
  # canonical table, but the substrings may differ in shape — the canonical's
  # anchors drive the Phase 1 Track A smoke-parse (file integrity), while the
  # script's anchors detect when a consumer SKILL.md INLINES canonical content
  # instead of referencing `shared/<file>` (drift detection). Use whichever
  # substring most reliably identifies inlined canonical content. Keep each
  # `shared_path` matching the canonical's filename; dynamic parsing of the
  # canonical at runtime is a known follow-up.
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
  check_inline_drift 'Before substantive work'               'advisor-criteria\.md'
done

# 5. Template SHA-256 drift (one-shot; not per-skill). /jr-review's installer
#    hardcodes EXPECTED_TEMPLATE_SHA256; /jr-doctor surfaces drift earlier so
#    the user can update the constant before the install path starts failing.
tmpl="$HOME/.claude/skills/jr-review/templates/pre-commit-secret-guard.sh.tmpl"
script="$HOME/.claude/skills/jr-review/scripts/install-pre-commit-secret-guard.sh"
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

# 6. /jr-skill-audit live-references cache freshness (one-shot; not per-skill).
#    Mirrors the template-hash drift mechanism — without it, the cache rots
#    silently and feature-adoption-reviewer audits against stale data.
cache="$HOME/.claude/skills/jr-skill-audit/cache/refs.json"
if [ -d "$HOME/.claude/skills/jr-skill-audit" ]; then
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

# 7. abortReason enum drift (one-shot; not per-skill). Every abortReason="<lit>"
#    a skill SETS must be declared in shared/abort-markers.md's mapping table, or
#    it falls through the runtime `case` to `*) → [ABORT — UNLABELED]` — a contract
#    violation the model catches only after the fact. The allowed set is derived
#    from abort-markers.md at run time (no hardcoded copy), so the two cannot drift.
#    Scope notes that ARE the check's soundness (each earned by a real miss):
#      - used values are extracted with the enum grammar [a-zA-Z][a-zA-Z0-9._-]*,
#        NOT a bare "[^"]+". Two failure modes bound this: a class that OMITS '.'
#        silently drops dotted values (head-moved-phase-5.6); a bare "[^"]+" is too
#        greedy and matches this check's OWN documentation and a sed pattern
#        (abortReason="//; s/) as if they were setters. The grammar includes '.'
#        and '-' (so real values pass) and rejects '<', '/', ' ' (so placeholder
#        mentions like abortReason="<value>" and sed junk do not).
#      - the declared set is scoped to the mapping-table rows only, NOT the whole
#        file: abort-markers.md's Anti-patterns section names an EXAMPLE typo
#        (serect-halt-phase-1) that a whole-file match would wrongly accept.
#      - secret-halt-* is a documentation glob; the runtime `case` has no glob arm,
#        so a new secret-halt variant not enumerated in the table SHOULD orphan.
markers="$HOME/.claude/skills/shared/abort-markers.md"
if [ -f "$markers" ]; then
  declared=$(awk '/^## Reason/{f=1;next} f&&/^## /{exit} f&&/^\|/{print}' "$markers" \
               | sed 's/^| *//; s/ *|.*//' \
               | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
  used=$(grep -rhoE 'abortReason="[a-zA-Z][a-zA-Z0-9._-]*"' "$HOME"/.claude/skills \
           --include='*.md' --include='*.sh' 2>/dev/null \
           | sed 's/^abortReason="//; s/"$//' | sort -u)
  declared_count=$(printf '%s\n' "$declared" | grep -c .)
  used_count=$(printf '%s\n' "$used" | grep -c .)
  if [ "$declared_count" -eq 0 ]; then
    # Mapping table stubbed/truncated — fail rather than vacuous-pass every value.
    echo "FAIL_ABORT_MARKERS_TABLE_EMPTY"
  elif [ "$used_count" -eq 0 ]; then
    # Extraction matched nothing though setters are known to exist — the regex is
    # broken, not the repo. Fail rather than certify clean.
    echo "FAIL_ABORT_REASON_EXTRACTION_EMPTY"
  else
    printf '%s\n' "$used" | while IFS= read -r v; do
      [ -z "$v" ] && continue
      if ! printf '%s\n' "$declared" | grep -qxF "$v"; then
        # Name every setter site so the author can find the typo.
        grep -rn -- "abortReason=\"$v\"" "$HOME"/.claude/skills \
          --include='*.md' --include='*.sh' 2>/dev/null \
          | sed "s|^$HOME/.claude/skills/|FAIL_ABORT_REASON_ORPHAN:$v:|"
      fi
    done
  fi
fi
