# Standardisation target — /jr-audit migration-map lens

Generic reference for `/jr-audit`'s optional **standardisation** lens: a technology-standardisation
migration map that classifies each in-scope component as **on-target** or an **off-target migration
candidate** against a target *you* define. Strategic, not a defect (see Rules). This file contains
**no target of its own** — the target is configured privately, per repo.

## Activation (opt-in, per repo)

The lens is **off by default**. It turns on for a repo only when that repo's
`.claude/review-config.md` contains a `## Standardisation target` section (read at Phase 1). No such
section ⇒ no classification and no report section. Keeping the target in the audited repo's own
(private) `review-config.md` means your organisation's strategy never has to live in this skills
repo.

Define it in `<your-repo>/.claude/review-config.md`, for example:

    ## Standardisation target

    - Web → <your chosen web stack>
    - Scripting / services → <language>, only where it earns its place (e.g. data science / ML)
    - Legacy backend (<framework>) → <target backend>
    - Infra → <your IaC tool>

    Applicability: <optional — e.g. "only when the repo is one of ours"; omit to always classify>

Everything below is generic mechanism; the specifics above are yours.

## Classification (generic)

For each in-scope component the lead (Track C, no subagent) reads its manifest to determine its
stack and marks it on-target or a migration candidate against the configured target. Record one row
per component: `component | current stack | on-target? | target | effort (S/M/L) | coupling`.

## Rules

- **Component granularity, never per-file.** One row per app / service / module.
- **Strategic, NOT a defect.** Off-target is not a bug. The lens produces NO findings, NO severity,
  and is NEVER auto-fixed or validated — it is report-only, and never affects the health score.
- **Effort** is a rough S / M / L per component; **coupling** notes what makes a migration hard.
- **Grounded, not opinion.** Classify against the *configured* target, not the model's own idea of
  what is "legacy".
