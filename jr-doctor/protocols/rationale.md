# Design rationale — `/jr-doctor`

**Maintainer reference. NEVER read at runtime.** No phase of `jr-doctor/SKILL.md` loads this file, it
carries no smoke-parse anchor, and nothing in it is an instruction. It exists so that reasoning which
only a maintainer (or an auditing reviewer) needs stops costing tokens on every session, which matters
more here than elsewhere: `/jr-doctor` is the `effort: low` diagnostic, so its always-loaded header is
the part of it that should be cheapest.

Each section names the `SKILL.md` site it explains. Same pattern as
`jr-ship/protocols/rationale.md` and `jr-skill-audit/protocols/rationale.md`.

## No advisor call anywhere in the skill

*(`SKILL.md` header comment, "Tools NOT used".)*

**Deliberate, not an omission.** Every check in this skill is a narrow yes/no file read or a
`command -v` probe: there is no interpretation to second-guess, which is the MAY-skip "mechanical
phases with no judgment calls" carve-out in `../../shared/advisor-criteria.md`. The only mutation is
an append-only `.gitignore` line, gated on a per-change `AskUserQuestion` showing the exact text
(Phase 4), so there is no substantive-edit boundary for a pre-dispatch advisor to guard, and no retry
loop for a stuck-loop advisor to catch.

**Do not re-raise this as a missing-advisor finding without first showing one of those three has
changed** (a check that interprets rather than reads, a mutation that is not the confirmed
`.gitignore` append, or a retry loop). An audit re-derives this question every run otherwise.
