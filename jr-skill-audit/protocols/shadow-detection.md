# Shadow-detection finding shape — `/jr-skill-audit`

**Canonical finding shape** for the lead-synthesized `scope-resolution` finding emitted when a
skill basename is present in BOTH personal and project scopes. `jr-skill-audit/SKILL.md`'s
"Shadow detection (lead-side synthesis)" section points here; read this on demand **only when a
cross-scope collision is detected** (not at Phase 1 Track A — reference material, like
`edge-cases.md`). The finding routes through Phase 3 (sanity-check + dedup) and Phase 4
([Clarify] flow) like any reviewer finding; no Phase 2 reviewer agent is involved.

## Finding shape

```
file:                  <personal SKILL.md path>            # anchor for codeExcerpt
line:                  <line of `name:` in personal frontmatter; line 1 if absent>
                       # Phase 3 step 1 clamps line-1 to [1, file-end], so line=1
                       # (the opening `---`) is a safe fallback when `name:` is missing.
dimension:             scope-resolution                     # lead-emitted, NOT in --only= enum
severity:              medium
confidence:            certain
title:                 Skill <name> exists in both personal and project scopes
description:           Personal: <personal path>. Project: <project path>. At runtime,
                       personal overrides project (per
                       https://code.claude.com/docs/en/skills#where-skills-live) —
                       the project version is hidden when invoked in this directory.
recommendation:        If intentional, document the override in the project SKILL.md.
                       If unintentional, remove the duplicate.
codeExcerpt:           3 verbatim lines centered on `line` — i.e., [line-1, line, line+1],
                       clamped to [1, file-end]. Matches Phase 3 step 1's read window.
source:                https://code.claude.com/docs/en/skills:#where-skills-live
scope:                 personal                             # dominant scope at runtime
clarify:               true
clarificationQuestion: Is the project version of <name> an intentional per-repo
                       override? If yes, drop this finding.
```

## Why this shape

Anchoring on the personal skill keeps the Phase 3 sanity-check single-file (no multi-file logic
needed); the `source` URL is a `cache/refs.json` key so Phase 3 step 2 validation passes;
`clarify: true` prevents re-fire on intentional overrides (mirrors `model-routing-reviewer`);
`scope: personal` (the runtime winner) keeps Phase 7's "By scope" rollup from double-counting.
