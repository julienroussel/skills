# Run-scoped flags and exit codes — `/jr-audit`

**Canonical source** for `/jr-audit`'s program-start run-scoped flag initialization and for its Phase 7 exit codes. `jr-audit/SKILL.md` reads this file into lead context at Phase 1 Track A (under the hard-fail + non-empty + smoke-parse guard, alongside the `shared/*.md` files); the first section governs program start, before Phase 1, and the second governs every exit path. **The Phase 7 report shape is not here**: it lives in `phase7-report-body.md` (deferred, read at Phase 7 entry). Change what the report renders there, not here.

## Run-scoped flags initialization (mandatory)

At program start, before Phase 1:

1. Parse arguments (per the "Arguments" section in `SKILL.md`).
2. Initialize all three run-scoped boolean flags to `false` unconditionally: `abortMode=false`, `convergenceFailed=false`, `userContinueWithSecret=false`. Additionally, initialize the run-scoped string `abortReason=""` (empty string), the run-scoped counter `unreportedCount=0`, and the run-scoped set `unreported=[]` (empty).
3. Run flag-conflict resolution (per "Flag conflicts" in `SKILL.md`).
4. Begin Phase 1.

This is the **single** program-start initialization site — the mirror of `/jr-review`'s `protocols/phase7-cleanup-report.md` "Run-scoped flags initialization", and the reason the two skills' exit-code rules below "must not drift". It is unconditional: the exit-code rules read these values on **every** exit path, but most paths never enter the `--converge` loop or reach an abort/user-continue site — a clean non-converge run reaches Phase 7 having touched none of them (no flag set, and its Phase 3 roll-call appended nothing to `unreported`). Initializing here guarantees the exit-code gate reads a defined `false`/`""`/`0`/`[]` rather than relying on unset-variable semantics.

`/jr-audit` has no `freshEyesMandatory` flag (no fresh-eyes pass — see `../convergence-protocol.md`) and no `publicationWithheld` flag (no Phase 8: `/jr-audit` publishes nothing to a forge, so no pre-publication redaction scan can withhold an artifact here). Both are `/jr-review`-only. `/jr-audit`'s flag-conflict resolution (step 3) currently sets none of these run-scoped flags, so ordering step 2 before step 3 is defensive rather than load-bearing today; keep it so a future conflict rule that latches a flag cannot be clobbered by a later default (the trap `/jr-review` documents at its init site).

The `--converge` loop adds only its **own** state (`iteration`, `convergenceStartTime`, `tmpDir`, `allModifiedFiles`, `iterationLog`, `passUnreported`) on top of these — it does NOT re-initialize the flags above (`../convergence-protocol.md` "Initialization").

Flag semantics:

- `abortMode=false` — set to `true` by any abort path; gates the abort-mode marker render (SKILL.md Phase 7) and the exit-code rule below. `abortReason` is set alongside it.
- `abortReason=""` — set alongside `abortMode=true` at each abort site to one of the values in `../../shared/abort-markers.md` (single source of truth for the enum). Reset to `""` only here; typically one abort site fires per run.
- `convergenceFailed=false` — set to `true` by any `--converge` termination-without-convergence path (`../convergence-protocol.md`).
- `userContinueWithSecret=false` — latched to `true` by the User-continue path protocol's behavior 5 (`../../shared/secret-scan-protocols.md`), at **three** user-Continue sites: the **Phase 1 pre-scan** (SKILL.md step 6.5, "User-continue path applies to Phase 1 too"), Phase 5.6, and the Phase 6 regression-fix re-scan. CANNOT be unset for the remainder of the run. The Phase 1 site is the one to keep in view: a user who accepts a secret there, before any implementer runs, leaves every exit condition below false unless the latch fires.
- `unreportedCount=0` / `unreported=[]` (empty): the run-level, monotonic reviewer-roll-call state (`../../shared/subagent-reporting.md` "Lead-side: reviewer roll-call"). Phase 3 step 0.0 and every later roll-call only **append** `UNREPORTED` members, nothing resets it, and `unreportedCount` is `|unreported|`. Initialized here so a clean run (where the roll-call appends nothing) reaches the Phase 3 `unreportedCount == 0` clean-audit gate and the Phase 7 `> 0` exit / health-score gates with a defined `0` / `[]` rather than an unset value. This is **not** the `--converge` loop's per-pass `passUnreported` (loop-owned, reset each iteration per the above); the run-level set is never reset.

## Exit-code rules

Phase 7 exits with a **non-zero** status when any of the following occurred during the run:

- `abortMode=true` (any `abortReason`).
- `convergenceFailed=true` (any convergence termination path, per `../convergence-protocol.md`).
- **`unreportedCount > 0`** — any spawned subagent returned nothing (`../../shared/subagent-reporting.md` rule 2). The run did not cover what it claims, and under headless the exit code is the only channel a machine reads.
- `userContinueWithSecret=true` (the latched User-continue path, `../../shared/secret-scan-protocols.md`).
- Any exit-forcing **marker** was rendered — the marker set is owned by `../../shared/abort-markers.md` ("Exit-code contribution").

This list is the single source of truth for `/jr-audit`'s exit code; `abort-markers.md` owns only the marker subset. Mirrors `/jr-review`'s `protocols/phase7-cleanup-report.md` ("Phase 7 exit-code rules"), which carries the same non-marker conditions plus its `/jr-review`-only `publicationWithheld` (the one documented divergence, per the flag note above) — the two skills must not otherwise drift.

