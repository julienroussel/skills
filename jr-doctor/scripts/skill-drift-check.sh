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
    echo "$model" | grep -qE '^(inherit|haiku|sonnet|opus|fable|claude-(haiku|sonnet|opus)-[0-9]+-[0-9]+(-[0-9]+)?(\[[a-z0-9]+\])?)$' \
      || echo "WARN_MODEL:$name:$model"
  fi
  echo "$fm" | grep -qE '^description:' || echo "FAIL_NO_DESC:$name"

  # 4. Inline duplication of canonical shared content. Drift if a Group D
  #    smoke-parse anchor appears inline AND the corresponding shared/ ref
  #    is absent. (Anchor + reference together is the canonical pattern.)
  #    Scans this skill's `protocols/*.md` as well as its SKILL.md: the bodies
  #    that carry canonical anchors have been moving out of SKILL.md into
  #    protocols/, and a SKILL.md-only scan loses coverage with every such
  #    extraction while still reporting green. The reference is required in the
  #    same file as the anchor, not merely somewhere in the skill — a per-skill
  #    test would pass for every skill here by construction and so could never
  #    fail. Checks 8 and 11 already glob `*/protocols/*.md` the same way. The
  #    marker names the FILE, not the skill, so a hit is actionable.
  check_inline_drift() {
    anchor="$1"; shared_path="$2"
    for cid_f in "$skill_md" "${d}protocols"/*.md; do
      [ -f "$cid_f" ] || continue
      if grep -F -- "$anchor" "$cid_f" >/dev/null 2>&1; then
        grep -E "shared/${shared_path}" "$cid_f" >/dev/null 2>&1 \
          || echo "WARN_INLINE_DRIFT:${cid_f#"$HOME"/.claude/skills/}:${shared_path}"
      fi
    done
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
  check_inline_drift 'Code-edit discipline'                  'code-edit-discipline\.md'
  check_inline_drift '[REJECTED — CLAIM REFUTED BY SOURCE]'  'claim-verification\.md'
  check_inline_drift 'Command equivalence table'             'forge-detection\.md'
  check_inline_drift 'Model override semantics'              'model-override\.md'
  check_inline_drift 'Spawn rule: never pass'                'subagent-reporting\.md'
  # 16 of the canonical's 17 rows are covered. `phase1-track-a-protocol.md` is
  # deliberately excluded: every consumer both hardcodes its `Canonical Anchor
  # Table` self-check AND references the file, so an inline-vs-reference test
  # cannot distinguish drift there.
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
      # GNU date (mac `gdate`, Linux `date`) parses ISO with -d; mac stock `date` is
      # BSD (needs -j -f). Probe -d capability rather than assume absent-gdate == BSD.
      if command -v gdate >/dev/null 2>&1; then
        fetched_epoch=$(gdate -d "$fetched" +%s 2>/dev/null)
      elif date -d @0 +%s >/dev/null 2>&1; then
        fetched_epoch=$(date -d "$fetched" +%s 2>/dev/null)
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

# 8. Harness-claim staleness (one-shot; scans shared/*.md, every SKILL.md, */protocols/*.md, docs/*.md).
#    A `<!-- harness-claim-verified: YYYY-MM-DD -->` marker dates the last time a
#    harness-behaviour assertion (tool grants, spawn/return semantics, CLI JSON
#    field names) was re-verified against the running harness. Warn past 90 days —
#    harness behaviour drifts across Claude Code/plugin releases, so a dated
#    assertion left unchecked becomes stale certainty (canonical: docs/skill-anatomy.md
#    "Re-verifying a harness claim"; the /jr-doctor Group J probe live-checks the
#    spawn/tool claims every run). Absent markers are NOT a failure — opt-in per file.
hc_now=$(date +%s)
for f in "$HOME"/.claude/skills/shared/*.md "$HOME"/.claude/skills/*/SKILL.md "$HOME"/.claude/skills/*/protocols/*.md "$HOME"/.claude/skills/docs/*.md; do
  [ -f "$f" ] || continue
  grep -oE '<!-- harness-claim-verified: [0-9]{4}-[0-9]{2}-[0-9]{2} -->' "$f" 2>/dev/null \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | while IFS= read -r hcd; do
    [ -z "$hcd" ] && continue
    # Round-trip the date (parse, then re-format): a shape-valid but calendar-invalid
    # stamp (e.g. 2026-02-30) makes gdate emit empty OR BSD `date` silently roll over
    # to another day — neither is a real verification date, so signal it rather than
    # swallow it (matching check 7's loud-fail-on-unparseable convention).
    # Backend: mac `gdate` and Linux `date` are GNU (parse with -d); mac stock `date`
    # is BSD (needs -j -f). `command -v gdate` alone is wrong — on Linux `date` IS GNU
    # and there is no `gdate` — so probe GNU -d capability directly (`date -d @0`).
    if command -v gdate >/dev/null 2>&1; then
      hc_epoch=$(gdate -d "$hcd" +%s 2>/dev/null); hc_rt=$(gdate -d "$hcd" +%Y-%m-%d 2>/dev/null)
    elif date -d @0 +%s >/dev/null 2>&1; then
      hc_epoch=$(date -d "$hcd" +%s 2>/dev/null); hc_rt=$(date -d "$hcd" +%Y-%m-%d 2>/dev/null)
    else
      hc_epoch=$(date -j -f "%Y-%m-%d" "$hcd" +%s 2>/dev/null); hc_rt=$(date -j -f "%Y-%m-%d" "$hcd" +%Y-%m-%d 2>/dev/null)
    fi
    hc_label="${f#"$HOME"/.claude/skills/}"
    if [ -n "$hc_epoch" ] && [ "$hc_rt" = "$hcd" ]; then
      hc_age=$(( (hc_now - hc_epoch) / 86400 ))
      [ "$hc_age" -gt 90 ] && echo "WARN_HARNESS_CLAIM_STALE:$hc_label:$hcd:$hc_age"
    else
      echo "WARN_HARNESS_CLAIM_UNPARSEABLE:$hc_label:$hcd"
    fi
  done
done

# 9. Restated-canonical-rule linkage (one-shot; issue #88). A rule with a single
#    canonical home (shared/*.md or a skill-local protocols/*.md) that is legitimately
#    restated inline (restate-and-guard) must carry a resolvable
#    `(canonical: <home> "<section>")` pointer within ±5 lines of the restated token,
#    in any SKILL.md or protocols/*.md EXCEPT the rule's own home. Catches the
#    semantic/verbatim restatements check 4 cannot see: check 4 tests only for a bare
#    `shared/<file>` mention and scans SKILL.md only; this requires the pointer FORM and
#    scans protocols/*.md too (docs/skill-anatomy.md "Restating a canonical rule inline").
#    The registry is a small allowlist of high-value restatements — grow it like check 4's
#    anchor list as more restate-and-guard cases are sanctioned.
#      Row = check_restate_linkage TOKEN(grep -F, ASCII+distinctive) HOME SECTION(grep -F) ID
#      SECTION must be a ')'-free substring of a home heading: the pointer-span extraction below
#      stops at the first ')', so a ')' inside the section would leave it silently unvalidated.
#    Two fail-loud guards (each mirrors check 7's non-empty convention): a token that
#    matches nothing (WARN_RESTATE_TOKEN_UNUSED) or a registry section absent from its
#    home (WARN_RESTATE_HOME_SECTION_MISSING) means the row is stale — without them the
#    check would certify GREEN while covering nothing.
check_restate_linkage() {
  token="$1"; home="$2"; section="$3"; id="$4"
  home_full="$HOME/.claude/skills/$home"
  home_re=$(basename "$home" | sed 's/\./\\./g')   # escape . (the only ERE metachar in a .md basename)

  # fail-loud A: the token must be restated in at least one non-home consumer file.
  used_somewhere=no
  for f in "$HOME"/.claude/skills/*/SKILL.md "$HOME"/.claude/skills/*/protocols/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *"/$home") continue;; esac
    if grep -Fq -- "$token" "$f"; then used_somewhere=yes; break; fi
  done
  [ "$used_somewhere" = no ] && echo "WARN_RESTATE_TOKEN_UNUSED:$id"

  # fail-loud B: the registry's declared section must resolve to a heading in the home.
  if [ ! -f "$home_full" ] || ! grep -E '^#{1,6} ' "$home_full" | grep -Fq -- "$section"; then
    echo "WARN_RESTATE_HOME_SECTION_MISSING:$id:$section"
  fi

  # linkage: every inline restatement needs a resolvable pointer within ±5 lines.
  for f in "$HOME"/.claude/skills/*/SKILL.md "$HOME"/.claude/skills/*/protocols/*.md; do
    [ -f "$f" ] || continue
    case "$f" in *"/$home") continue;; esac          # never flag the canonical home itself
    label="${f#"$HOME"/.claude/skills/}"
    grep -Fn -- "$token" "$f" | cut -d: -f1 | while IFS= read -r ln; do
      [ -z "$ln" ] && continue
      lo=$((ln > 5 ? ln - 5 : 1)); hi=$((ln + 5))
      # Require the POINTER FORM `(canonical: …<home>…)`, not a bare filename mention:
      # a restated token's ±5 window can legitimately contain non-pointer mentions of the
      # home file (e.g. a Phase 1 read-list) that must NOT count as linkage.
      ptr=$(sed -n "${lo},${hi}p" "$f" | grep -oE "\(canonical:[^)]*${home_re}[^)]*\)" | head -1)
      if [ -n "$ptr" ]; then
        # Pointer present → if it names a "section", that section must resolve in the home.
        # Parse the section from the pointer SPAN only (grep -o above), not the whole line, so a
        # section-less pointer sharing a line with later quoted text can't mis-capture it as a section.
        psec=$(printf '%s' "$ptr" | sed -n 's/.*"\([^"]*\)".*/\1/p')
        if [ -n "$psec" ] && [ -f "$home_full" ] && ! grep -E '^#{1,6} ' "$home_full" | grep -Fq -- "$psec"; then
          echo "WARN_RESTATE_UNRESOLVED:$label:$ln:$id"
        fi
      else
        echo "WARN_RESTATE_UNLINKED:$label:$ln:$id"
      fi
    done
  done
}
check_restate_linkage 'Calibration: Your last 5 runs' 'shared/audit-history-schema.md' 'reviewerStats[]' 'fp-calibration-note'

# 10. Guard-mode mismatch (one-shot). A smoke-parse anchor declared line-anchored
#     (`^...`) CANNOT be verified with `grep -F`: -F treats `^` as a literal, never
#     matches a healthy file, and the hard-fail guard then aborts Phase 1 on EVERY
#     run of that skill. Shipped once for real (/jr-ship multi-pr-flow, 2026-07-27).
#     Links each affirmative "via/with `grep -F`" instruction to the anchor ROW for
#     the same target file, so a -F instruction governing plain anchors elsewhere in
#     the file (the legitimate shared-anchor case) does not false-positive.
for f in "$HOME"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  gm_name=$(basename "$(dirname "$f")")
  grep -nE '(via|with) `grep -F`' "$f" 2>/dev/null | while IFS=: read -r gm_ln gm_rest; do
    printf '%s\n' "$gm_rest" | grep -oE '[a-z0-9-]+\.md' | sort -u | while read -r gm_tgt; do
      [ -n "$gm_tgt" ] || continue
      # the ANCHOR ROW for this target: a list line naming it followed by `: `
      if grep -E "^[[:space:]]*[-*] .*\`[^\`]*${gm_tgt}\`: " "$f" 2>/dev/null | grep -q '`\^'; then
        echo "FAIL_GUARD_MODE:$gm_name:$gm_ln:$gm_tgt"
      fi
    done
  done
done

# 11. Malformed harness-claim marker (one-shot). Check 8 matches only the exact
#     `<!-- harness-claim-verified: YYYY-MM-DD -->` form. A marker that lost its
#     comment delimiters (e.g. a bulk relocation that stripped `<!--`) is invisible
#     to check 8 while still LOOKING present to a reader: zero coverage, no signal.
#     Counts the bare token vs the well-formed marker; a shortfall means a stripped
#     or reshaped marker. Lines that merely NAME the token in prose are excluded by
#     requiring a date to follow it.
for f in "$HOME"/.claude/skills/shared/*.md "$HOME"/.claude/skills/*/SKILL.md \
         "$HOME"/.claude/skills/*/protocols/*.md "$HOME"/.claude/skills/docs/*.md; do
  [ -f "$f" ] || continue
  hm_all=$(grep -cE 'harness-claim-verified: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$f" 2>/dev/null)
  hm_all=${hm_all:-0}
  hm_ok=$(grep -cE '<!-- harness-claim-verified: [0-9]{4}-[0-9]{2}-[0-9]{2} -->' "$f" 2>/dev/null)
  hm_ok=${hm_ok:-0}
  if [ "$hm_all" -gt "$hm_ok" ] 2>/dev/null; then
    echo "WARN_HARNESS_CLAIM_MALFORMED:${f#$HOME/.claude/skills/}:$((hm_all - hm_ok))"
  fi
done

# 12. Protocol-file anchor guard (one-shot). Two failure modes of the same guard:
#       a) TAIL-UNGUARDED — a multi-anchor grep-guard only makes a truncated body fail if the
#          DEEPEST anchor sits near the end. An anchor in the middle lets a tail truncation
#          pass while dropping the rest of the procedure — including, in the shipped case,
#          every irreversible step of a multi-PR flow. Warns below 60% of the file.
#          Depth is the deepest anchor's FIRST occurrence, not the last-declared one:
#          declaration order is not depth order, and `grep -Fq` is satisfied by the first hit.
#       b) UNRESOLVABLE — a declared anchor that is renamed away or deleted, or a protocol
#          file that cannot be read. Both make the consumer skill hard-fail its Phase 1 guard
#          on EVERY run, so they are the fatal half; the previous version emitted nothing for
#          either and graded only (a), which is the inverted-consequence grading this fixes.
#     Extraction: the five swarm skills declare anchors in four different connector shapes, and
#     a `/jr-ship`-only row pattern left the other 25 protocol files uncovered. The awk
#     below is shape-agnostic — it tokenises the backticked spans of a line, marks the ones
#     naming a protocol file of THIS skill, and reads the anchors that follow:
#       - declaration row  — a short connector (`: `, ` — `, ` — anchors `, ` must contain `)
#                            straight after the file token; 1+ anchors, so a single-anchor
#                            guard is covered too.
#       - prose paragraph  — otherwise the LAST run of 2+ backticked tokens joined by ` AND `
#                            in that file's span. Last, not first: those paragraphs open with
#                            a "verify presence: `[ -f ]` the file AND `grep -Eq`" clause that
#                            is itself an AND-run, and taking the first would grade that.
#     Only a token that is either shaped `protocols/<x>.md` or followed by a declaration
#     connector ends the preceding file's span, so a bare cross-reference mid-sentence
#     ("beside `fix-secret-validate.md`") no longer steals the anchors that follow it.
#     `^`-prefixed anchors are matched at line start, mirroring the `grep -Eq` the declaring
#     skill runs — several protocol files quote their own anchors in header prose, and a plain
#     substring match would report that line-3 quote as the guard depth.
#     Known gap: a declared file that no longer exists is only reported when the declaration
#     spells the `protocols/` prefix; a bare-basename declaration of a deleted file cannot be
#     told from prose. The consumer's own Phase 1 hard-fail still catches that case loudly.
for f in "$HOME"/.claude/skills/*/SKILL.md; do
  [ -f "$f" ] || continue
  ta_dir=$(dirname "$f")
  awk -v DIR="$ta_dir" -v NAME="$(basename "$ta_dir")" '
    function base(t,   b) { b = t; sub(/.*\//, "", b); return b }
    function isproto(t,   b, p, r) {
      if (t ~ /(^|\/)protocols\/[a-z0-9-]+\.md$/) return 1
      b = base(t)
      if (b !~ /^[a-z0-9-]+\.md$/) return 0
      p = DIR "/protocols/" b
      if (p in EX) return EX[p]
      r = (getline junk < p); close(p)
      EX[p] = (r >= 0) ? 1 : 0
      return EX[p]
    }
    function emit(m) { if (!(m in SEEN)) { SEEN[m] = 1; print m } }
    function grade(fil, k, A,   path, l, r, i, tot, pat, anch, deep, hit) {
      path = DIR "/protocols/" fil
      tot = 0; r = 0
      while ((r = (getline l < path)) > 0) {
        tot++
        for (i = 1; i <= k; i++) {
          if (i in hit) continue
          pat = A[i]; anch = 0
          if (substr(pat, 1, 1) == "^") { anch = 1; pat = substr(pat, 2) }
          gsub(/\\/, "", pat)
          if (anch) { if (index(l, pat) == 1) hit[i] = tot }
          else      { if (index(l, pat) > 0)  hit[i] = tot }
        }
      }
      close(path)
      # An unreadable or empty target is the vacuous pass this check exists to close:
      # report it instead of skipping, exactly as a missing anchor is reported.
      if (r < 0)    { emit("FAIL_ANCHOR_UNREADABLE:" NAME ":" fil ":unreadable"); return }
      if (tot == 0) { emit("FAIL_ANCHOR_UNREADABLE:" NAME ":" fil ":empty"); return }
      deep = 0
      for (i = 1; i <= k; i++) {
        if (!(i in hit)) { emit("FAIL_ANCHOR_MISSING:" NAME ":" fil ":" A[i]); return }
        if (hit[i] > deep) deep = hit[i]
      }
      if (tot > 40 && deep * 100 / tot < 60)
        emit("WARN_ANCHOR_TAIL_UNGUARDED:" NAME ":" fil ":" deep "/" tot)
    }
    {
      line = $0
      gsub(/\\`/, "\001", line)   # protect a backtick escaped inside an anchor
      n = 0; rest = line
      while (match(rest, /`[^`]*`/) > 0) {
        n++
        T[n]  = substr(rest, RSTART + 1, RLENGTH - 2)
        GP[n] = substr(rest, 1, RSTART - 1)
        rest  = substr(rest, RSTART + RLENGTH)
      }
      for (i = 1; i <= n; i++)
        D[i] = (isproto(T[i]) && (T[i] ~ /protocols\// || (i < n && GP[i+1] ~ /^(: | (—|--) (anchors )?| must contain )$/)))
      for (i = 1; i <= n; i++) {
        if (!D[i]) continue
        q = n + 1
        for (j = i + 1; j <= n; j++) if (D[j]) { q = j; break }
        s = 0
        if (i + 1 < q && GP[i+1] ~ /^(: | (—|--) (anchors )?| must contain )$/) s = i + 1
        if (!s) {
          for (j = i + 1; j < q; j++) if (GP[j+1] == " AND " && j + 1 < q) s = j
          if (s) { while (s > i + 1 && GP[s] == " AND ") s-- }
        }
        if (!s) continue
        e = s; k = 0
        while (e + 1 < q && GP[e+1] == " AND ") e++
        for (j = s; j <= e; j++) { a = T[j]; gsub(/\001/, "`", a); k++; A[k] = a }
        grade(base(T[i]), k, A)
        for (j = 1; j <= k; j++) delete A[j]
      }
    }
  ' "$f"
done

# 13. Unresolved canonical pointer (one-shot). Generalises check 9's section test to
#     EVERY inline `(canonical: <file> "<section>")` pointer, not just registry tokens:
#     `<section>` must be a substring of a heading in the target, per
#     docs/skill-anatomy.md "Pointer format". A pointer naming a bold bullet or a
#     numbered list item resolves to nothing for the reader who follows it.
for f in "$HOME"/.claude/skills/*/SKILL.md "$HOME"/.claude/skills/*/protocols/*.md; do
  [ -f "$f" ] || continue
  cp_name=${f#$HOME/.claude/skills/}
  cp_dir=$(dirname "$f")
  grep -oE '\(canonical: `[^`]+\.md` "[^"]+"\)' "$f" 2>/dev/null | sort -u | while read -r cp_ptr; do
    cp_file=$(printf '%s' "$cp_ptr" | sed -n 's/.*`\([^`]*\.md\)`.*/\1/p')
    cp_sec=$(printf '%s' "$cp_ptr" | sed -n 's/.*"\([^"]*\)".*/\1/p')
    [ -n "$cp_file" ] && [ -n "$cp_sec" ] || continue
    cp_full="$cp_dir/$cp_file"
    [ -f "$cp_full" ] || { echo "WARN_CANON_PTR_NOFILE:$cp_name:$cp_file"; continue; }
    if ! grep -E '^#{1,6} ' "$cp_full" | grep -Fq -- "$cp_sec"; then
      echo "WARN_CANON_PTR_UNRESOLVED:$cp_name:$cp_file:$cp_sec"
    fi
  done
done

# 14. isHeadless env-var drift (one-shot). /jr-doctor re-expands the canonical
#     isHeadless predicate inline, which shared/secret-scan-protocols.md otherwise
#     forbids ("Defined once here and referenced by name elsewhere — do NOT re-expand
#     or abbreviate the predicate at individual sites"). The carve-out is real —
#     /jr-doctor never Reads that file, so it needs an executable copy — but the copy
#     is drift-prone by construction and nothing detected it: check 4's anchor for
#     this file is a string jr-doctor does not contain. A CI variable added to the
#     canonical would silently never reach jr-doctor, and --fix would keep prompting
#     in an unrecognised CI instead of auto-disabling. Derive BOTH sets at runtime so
#     the two cannot diverge unnoticed (same technique as check 7's abortReason enum).
#     Both spellings are extracted on both sides: `$CI` and the braced `${CI}` / `${CI:-}`.
#     The bare form is what both predicates happen to use today, but the check exists to
#     catch a FUTURE edit to the canonical, and a maintainer writing the idiomatic guarded
#     form would otherwise add a variable the extractor cannot see — failing open in the
#     dangerous direction (missing-in-jr-doctor).
ih_canon="$HOME/.claude/skills/shared/secret-scan-protocols.md"
ih_doctor="$HOME/.claude/skills/jr-doctor/SKILL.md"
if [ ! -f "$ih_canon" ] || [ ! -f "$ih_doctor" ]; then
  echo "WARN_ISHEADLESS_DRIFT:unparseable:canonical-or-jr-doctor-file-missing"
else
  ih_a=$(awk '/isHeadless=\$\(/{f=1} f{print} f && /echo false\)/{exit}' "$ih_canon" 2>/dev/null \
         | grep -oE '\$\{?[A-Z][A-Z0-9_]*' | tr -d '${' | sort -u)
  ih_b=$(awk '/is_headless=\$\(/{f=1} f{print} f && /^\)/{exit}' "$ih_doctor" 2>/dev/null \
         | grep -oE '\$\{?[A-Z][A-Z0-9_]*' | tr -d '${' | sort -u)
  if [ -n "$ih_a" ] && [ -n "$ih_b" ]; then
    # Missing from jr-doctor is the dangerous direction: an unrecognised CI is treated
    # as interactive. The reverse (extra locally) is reported too — it means the
    # canonical dropped a signal jr-doctor still honours.
    ih_missing=$(printf '%s\n' "$ih_a" | grep -vxF "$ih_b" | tr '\n' ' ' | sed 's/ *$//')
    ih_extra=$(printf '%s\n' "$ih_b" | grep -vxF "$ih_a" | tr '\n' ' ' | sed 's/ *$//')
    [ -n "$ih_missing" ] && echo "FAIL_ISHEADLESS_DRIFT:missing-in-jr-doctor:$ih_missing"
    [ -n "$ih_extra" ] && echo "WARN_ISHEADLESS_DRIFT:extra-in-jr-doctor:$ih_extra"
  else
    echo "WARN_ISHEADLESS_DRIFT:unparseable:one-or-both-predicate-blocks-not-found"
  fi
fi

# 15. jr-ship inline anchor-table drift (one-shot). /jr-ship is the ONE consumer that
#     does not read shared/phase1-track-a-protocol.md at runtime, so it hard-copies
#     anchor rows and itself declares they "MUST stay in sync with the canonical anchor
#     table ... or the guard silently goes stale" — with nothing enforcing it. Group D
#     validates shared FILES against the canonical table, not jr-ship's COPY of it, and
#     check 4 passes because jr-ship both inlines and references shared/<file>. Derive
#     both sides at runtime and compare anchor sets per file.
#     Every skip path emits: the previous version fell through silently on a deleted row, a
#     typo'd filename and an unparseable canonical row, and /jr-doctor renders a silent check
#     as a green `✓ jr-ship anchor sync` — a guard certifying a comparison it never made.
sp_canon="$HOME/.claude/skills/shared/phase1-track-a-protocol.md"
sp_ship="$HOME/.claude/skills/jr-ship/SKILL.md"
if [ ! -f "$sp_canon" ] || [ ! -f "$sp_ship" ]; then
  echo "WARN_SHIP_ANCHOR_UNCOMPARED:setup:canonical-or-skill-file-missing"
else
  # (a) Coverage. Every shared file jr-ship READS at Phase 1 must have an inline anchor row.
  #     Both sides are derived at run time (as in check 7/14), so a row deleted outright — or
  #     one whose filename is mistyped, which leaves the real file unguarded just the same —
  #     surfaces here instead of vanishing into the per-row loop's lookup miss below.
  sp_reads=$(grep -oE '^- Read `\.\./shared/[a-z0-9-]+\.md`' "$sp_ship" 2>/dev/null \
             | sed 's|^- Read `\.\./shared/||; s/`$//' | sort -u)
  sp_rows=$(grep -oE '^- `[a-z0-9-]+\.md`: ' "$sp_ship" 2>/dev/null \
            | sed 's/^- `//; s/`: $//' | sort -u)
  if [ -z "$sp_reads" ] || [ -z "$sp_rows" ]; then
    echo "WARN_SHIP_ANCHOR_UNCOMPARED:setup:read-list-or-anchor-list-not-found"
  else
    printf '%s\n' "$sp_reads" | while IFS= read -r sp_r; do
      [ -n "$sp_r" ] || continue
      printf '%s\n' "$sp_rows" | grep -qxF -- "$sp_r" \
        || echo "FAIL_SHIP_ANCHOR_ROW_MISSING:$sp_r"
    done
  fi
  # (b) Content. Only bare `<file>.md` rows: a `protocols/<file>.md` row is skill-local and
  #     has no canonical counterpart, so the `/`-free pattern excludes it by construction.
  grep -oE '^- `[a-z0-9-]+\.md`: .*' "$sp_ship" 2>/dev/null | while IFS= read -r sp_row; do
    sp_file=$(printf '%s' "$sp_row" | sed -n 's/^- `\([^`]*\)`:.*/\1/p')
    [ -n "$sp_file" ] || continue
    sp_have=$(printf '%s' "$sp_row" | sed 's/^- `[^`]*`: //' \
              | grep -oE '`[^`]+`' | sed 's/^`//;s/`$//' | sort -u)
    # Canonical row: | `<file>` | <anchors> |  -> field 3 under FS='|'. Require exactly
    # 4 fields so a row whose anchors contain an escaped pipe (e.g. reviewer-boundaries)
    # is skipped rather than mis-split into a false mismatch.
    sp_want=$(awk -F'|' -v f="$sp_file" '
      $0 ~ ("^\\| `" f "` \\|") && NF == 4 { print $3 }' "$sp_canon" 2>/dev/null \
              | grep -oE '`[^`]+`' | sed 's/^`//;s/`$//' | sort -u)
    if [ -z "$sp_want" ]; then
      # Nothing to compare against — say which of the two reasons it was, never nothing.
      if grep -qF -- "| \`$sp_file\` |" "$sp_canon" 2>/dev/null; then
        echo "WARN_SHIP_ANCHOR_UNCOMPARED:$sp_file:canonical-row-unparseable"
      else
        echo "WARN_SHIP_ANCHOR_UNCOMPARED:$sp_file:no-canonical-row"
      fi
      continue
    fi
    if [ "$sp_have" != "$sp_want" ]; then
      echo "FAIL_SHIP_ANCHOR_DRIFT:$sp_file"
    fi
  done
fi
