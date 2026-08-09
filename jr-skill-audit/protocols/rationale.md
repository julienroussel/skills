# `/jr-skill-audit` — design rationale

**Maintainer reference. Never read at runtime.** These paragraphs used to sit inline in `SKILL.md`,
where they cost ~6,700 characters of resident context on every run to carry ~1,900 characters of
operative rule. The rules themselves stay in `SKILL.md`; the *why* lives here.

The rationale protects a maintainer editing the file on disk, who can open a sibling file trivially.
The runtime never consults it. Each section below names the `SKILL.md` site it explains.

## Empty-discovery guard — why it reports a cause, not just an absence

*(`SKILL.md` Phase 1 Track B, "Empty-discovery guard".)*

On an unfiltered run the dominant way to reach this guard is **not** that no skills exist: it is that
every candidate was dropped as gitignored (the auto-narrow fallback restores personal, its step 2
excludes them, and the set empties again). The `Excluded (gitignored):` segment that would explain this
prints only in the discovery summary **after** all tracks, so it is unreachable from an abort that fires
before it.

`abortReason` stays `unmatched-scope` on both branches: the canonical mapping in
`shared/abort-markers.md` recognises no other value here, and an unrecognised one renders
`[ABORT — UNLABELED]` as a contract violation.

With any filter present the argument-naming rule owns the message instead, and the two branches stop
being exhaustive — `--scope=foo*` can match nothing having excluded nothing, so a count of 0 would no
longer mean the enumeration was empty. That is why the branch is scoped to the fully-unfiltered run only.

## Shadow detection — why it groups the enumerated set, not the surviving one

*(`SKILL.md` "After all tracks complete".)*

A shadow is a property of the directory you are standing in, not of what you chose to audit, so grouping
the surviving set would blind the check whenever a filter narrowed the run.

**Gitignored candidates are deliberately included**: Claude Code's runtime does not consult
`.gitignore`, so an externally-maintained personal skill still loads and still shadows a same-named
project skill. The collision is real and renaming the project skill is actionable, even though that
skill's own contents stay out of the audit.

The finding fires even when only one side is audited, anchoring on the personal `SKILL.md`, which stays
readable either way.

## Phase 3 step 0.0 — why the roll-call runs first

*(`SKILL.md` Phase 3, step 0.0.)*

Every later step — rejection rates, dedup, the report's completeness claim — is computed over the
delivered set, so a silently-missing dimension would otherwise be indistinguishable from one with
nothing to say.

**Why `unreportedCount` latches into a non-zero exit rather than only rendering:** `Audit integrity` is
a console channel a human may or may not read, whereas under headless the exit code is the only signal a
machine gets. Rendering alone would leave this skill computing `UNREPORTED` and then dropping it — the
exact anti-pattern `shared/subagent-reporting.md` names.

## `Roots:` line — why the auto-scope qualifier has an abort carve-out

*(`SKILL.md` Phase 7, "Scope-tag rendering rules".)*

The `[auto-scoped to project — …]` qualifier is appended only when `autoNarrowed=true` **and the run did
not abort**, never when `autoScope=project` was merely computed.

The abort carve-out matters because the auto-narrow fallback's empty arm leaves `autoNarrowed=true`
deliberately, and that arm is reached only after the fallback has already restored personal and found
nothing auditable there. The qualifier's `--scope-only=both to include personal` advice would send the
user to a scope this very run just tried and exhausted. On an aborting run the guard's own message states
the cause, so the qualifier adds nothing but a false lead.

The `Roots:` line itself is never omitted on a personal/project run because it is the report's only
unconditional statement of which directories were audited, and under the auto-scope default the same
command audits different skills in different directories.

## Naming contract — why "ACTION REQUIRED" was retired as a section label

*(`SKILL.md` Phase 7, "Naming contract".)*

The "Action items" rollup answers *"what do I need to do?"*. The "Audit integrity" section is a
meta-section about the audit run itself (reviewer-quality, citation validity); an empty Audit-integrity
section means the audit was clean, **not** that the user has nothing to act on.

Past versions conflated the two via an "ACTION REQUIRED" label scoped to the meta-section only. That
conflation caused the lead to render "ACTION REQUIRED: None" while leaving **28 findings un-rolled-up**.

The label is therefore banned as a *section heading*. Note the historical trap this created: the ban was
written while "ACTION REQUIRED" remained the live **routing verb** in the reviewer instructions and
throughout `finding-validation.md` — sixteen sites — so the skill simultaneously banned and used the same
string. The routing verb is now `route to Audit integrity`, which names the destination the item actually
reaches.

## Track C cache — why the raw `.md` fetch and the content assertion exist

*(`SKILL.md` Phase 1 Track C, steps 2 and 4-5.)*

The skill previously fetched the HTML doc pages via WebFetch with prompts naming the tables to
preserve, and claimed that "works around most of the lossy-summarization risk in practice".

**Measured and refuted, 2026-08-07.** A cache built by exactly that procedure recorded six environment
variables as absent from the env-vars page — `CLAUDE_EFFORT`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`,
`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`, `CLAUDE_CODE_MAX_SUBAGENTS_PER_SESSION`,
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_SUBAGENT_MODEL` — when all six are genuine table
rows. The page is ~357 KB; the fetch truncated mid-alphabet at `CLAUDE_CODE_D*`. It stayed wrong for 10
days, and every check the skill had (`ok: true`, Phase 3's URL-key match) passed it.

**The asymmetry that makes this worth guarding:** a *missing* cache is safe, because "Fallback to no
cache" skips `feature-adoption-reviewer` outright. A *confidently wrong* cache is not, because the
reviewer runs and reasons over it. So the guard belongs on the write, not the read.

**Why the cache is a gitignore-enforcement site at all.** Canonical: `shared/gitignore-enforcement.md`,
whose validation-oracle class (`review-profile.json`) `refs.json` belongs to. `SKILL.md` Track C restates
it at the probe, where a linear reader needs it; a third copy here would only add a drift surface.

## Token budget — why the threshold is characters

*(`SKILL.md` "After all tracks complete".)*

A line count is a proxy a dense file defeats. This skill's own body carries ~77,000 characters over
499 lines, about 154 chars/line and roughly 3× a conventional markdown file of that length. It clears
the skills-doc 500-line tip with a single line to spare, so a budget check keyed on lines
under-reports its real cost threefold; the compaction budget (first 5,000 tokens of a skill
retained) is measured in tokens, not lines.
