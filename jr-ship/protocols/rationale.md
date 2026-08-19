# Design rationale — `/jr-ship`

**Maintainer reference. NEVER read at runtime.** No phase of `jr-ship/SKILL.md` loads this file and
it carries no smoke-parse anchor.

## No advisor checkpoint on the default path

*(`SKILL.md` "Phase 3a: Single-PR Flow".)*

**Deliberate, not an omission.** All four of this skill's `advisor()` sites are mode-gated (step 5
multi-PR, step 14 `--merge`, step 11b-multi multi-PR + `--merge`, and the CI stuck-loop at its
2-cycle cap), so a default run — no `--merge`, splitting not recommended, CI green — reaches step 16
with none of them having fired.

`../../shared/advisor-criteria.md` names "renders a final report after a multi-phase run with no
advisor checkpoint anywhere" as a declare-done trigger; this site is the documented exception, on
three mitigations that bound the blast radius:

1. **Nothing is merged** — the default path stops after CI and leaves the PR open, so a human
   reviews before anything reaches the base branch.
2. The branch and its commits are **fully recoverable** — no history is rewritten and no remote ref
   is force-updated.
3. The **`--merge` path, which is the irreversible one, does gate on `advisor()`** at step 14.

**Do not re-raise this as a missing-advisor finding without first showing one of the three
mitigations has gone.**
