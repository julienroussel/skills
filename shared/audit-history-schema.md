# `.claude/audit-history.json` Schema

**Canonical source** for the cross-skill schema of `.claude/audit-history.json` — the registry shared between `/audit` and `/review` for cross-run rejection-rate tracking, reviewer-FP calibration, and global-memory promotion suppression. Both skills read this file at Phase 1 Track A (with schema-derivations described in each skill's own Phase 1) and append to it at Phase 7. Update here to update both skills.

## Top-level structure

```json
{
  "runs": [],
  "runSummaries": [],
  "reviewerStats": [],
  "lastPromptedAt": {}
}
```

If the file does not exist, create it with the structure above. If the file is in an older array-only format (legacy `/audit` schema before this layout), tolerate the mismatch and upgrade in place before appending — preserve any pre-existing entries under `runSummaries[]` so anything that read the old array shape can still find them after the upgrade.

## Field semantics

### `runs[]` (append-only)

One entry per `(dimension, category)` rejection observed during a run. Either Phase 4 user-rejection OR Phase 3 step 0 hallucination-rejection counts; both signal accuracy degradation.

```jsonc
{
  "runId": "<UUIDv4 — same for all entries from a single run>",
  "skill": "audit" | "review",
  "dimension": "<dimension name, e.g., security, typescript>",
  "category": "<category enum, e.g., injection-risk, missing-null-check>",
  "rejected": true,
  "totalFindings": <integer>,
  "runAt": "<ISO 8601 timestamp>"
}
```

Used at Phase 4.5 cross-run promotion: count `rejected=true` entries grouped by `dimension+category`, deduped by `runId`. Skills only append `rejected: true` records — there is no `rejected: false` entry for accepted findings.

### `runSummaries[]` (append-only)

One rolled-up entry per skill invocation keyed by `runId`:

```jsonc
{
  "runId": "<UUIDv4>",
  "skill": "audit" | "review",
  "date": "<ISO 8601 date>",
  "scope": "<scope description>",
  "flags": "<flags string>",
  "filesAudited": <integer>,    // /audit only
  "filesReviewed": <integer>,   // /review only
  "reviewersSpawned": <integer>,
  "findingCounts": { ... },
  "approvedCount": <integer>,
  "rejectedCount": <integer>,
  "validationDelta": { ... },
  "phaseTimings": { ... },
  "runAt": "<ISO 8601 timestamp>"
}
```

Each skill picks its own `filesAudited` vs `filesReviewed` field name; consumers must accept either. All other fields are common.

### `reviewerStats[]` (append-only)

One entry per reviewer dimension that produced findings in a run:

```jsonc
{
  "runId": "<UUIDv4>",
  "skill": "audit" | "review",
  "dimension": "<dimension name>",
  "totalFindings": <integer>,
  "rejectedFindings": <integer>,
  "rejectionRate": <float, 0.0..1.0>,
  "runAt": "<ISO 8601 timestamp>"
}
```

`rejectionRate = rejectedFindings / max(totalFindings, 1)`. `rejectedFindings` includes BOTH Phase 3 step 0 hallucination-rejections (citation invalid) AND Phase 4 user rejections — they signal accuracy degradation either way. Skip dimensions with `totalFindings == 0` (no entry written).

Used at Phase 1 Track A: take the last 5 entries per dimension across both skills and compute the running average `rejectionRate`. If ≥ 0.25, prepend a calibration note to that reviewer's Phase 2 prompt (per each skill's Phase 1 spec).

**Ordering**: Consumers MUST use **array-order** ("last 5 by array index") to compute calibration windows, NOT sort by `runAt`. The append-only invariant guarantees array-order = chronological order under correct atomic writes (mandated for Phase 7 step 5; see "Atomic-write requirement" in the Read-side integrity check section). Sorting by `runAt` would be exploitable via backdated forged entries — the integrity check has only an upper bound on timestamps. This array-order requirement is a checkable contract, not an implementation detail.

### `lastPromptedAt` (overwritten per key)

Object map keyed by `<dimension>:<category>` → ISO 8601 timestamp. Written on every cross-run global-memory promotion offer (regardless of Yes/No). Read before offering a promotion: **skip** if fewer than 2 rejected runs are recorded with `runAt > lastPromptedAt[<dimension>:<category>]`.

This map IS overwritten per key — it's the only field in the schema that mutates in place. The other arrays are append-only.

## Append-only invariant

`runs[]`, `runSummaries[]`, and `reviewerStats[]` are append-only across the file's lifetime. `lastPromptedAt` is overwritten per key on each promotion offer. Skills MUST NOT delete or rewrite entries.

## Read-side integrity check (mandatory)

`reviewerStats[]` drives runtime FP-rate calibration: `/audit` and `/review` Phase 1 Track A take the last 5 entries per dimension and prepend a "be more conservative" calibration note to that reviewer's Phase 2 prompt when the running average `rejectionRate >= 0.25`. The file is gitignored to prevent accidental commit, but `.gitignore` does NOT defend against local writes by a prompt-injected subagent with `Bash` access (the threat model `shared/untrusted-input-defense.md` exists to mitigate). Without a read-side integrity check, a partial forge — e.g., five `reviewerStats[]` entries with `dimension: "security"` and `rejectionRate: 1.0` appended without matching `runSummaries[]` entries — silently downgrades security findings across all future `/audit`, `/review`, and `/skill-audit` runs in this repo until the file is rotated. The check below catches partial forgeries and orphan entries that fail referential integrity.

**Threat-model coverage (explicit limitation)**: this check is a **structural integrity gate**, NOT a cryptographic trust anchor. It defends against partial / orphan forgeries. It does **NOT** defend against a coordinated forge where the attacker writes consistent entries to all three arrays at once — every field in `runSummaries[]` is forgeable from in-band data the attacker already controls (`runId`, `skill`, `date`, `flags`, `runAt`). The check raises attack cost from "append 5 lines to one array" to "append ~10 lines coordinated across arrays". A future hardening pass could add an HMAC over canonical-JSON keyed by a per-repo secret stored at `.claude/audit-history.key` (gitignored, 0600); that work is out of scope for this revision and is tracked separately. Operators of high-value repos who need stronger guarantees should not rely on this check alone.

Before any consumer skill computes a derived value from `runs[]`, `runSummaries[]`, or `reviewerStats[]`, validate cross-array referential integrity:

1. **Quarantine sentinel (check first)**: glob for `.claude/audit-history.json.corrupt-[0-9]*` files. If any exist, treat audit-history as quarantined for THIS run regardless of whether the current `audit-history.json` is otherwise clean: skip both derivations, skip Phase 4.5 cross-run promotion, and emit `ACTION REQUIRED: prior quarantine artifact(s) present: <list>; calibration remains disabled until those files are deleted.` This persists the quarantine state across runs without an additional sidecar file — the corrupt-file's existence IS the sentinel. Acknowledgment = manual deletion by the operator after inspection.
2. **Cross-array `runId` reachability**: build the set R of all `runId` values in `runSummaries[]`. For every entry in `runs[]` and every entry in `reviewerStats[]`, verify its `runId` is in R. Any orphan (entry whose `runId` does not appear in `runSummaries[]`) → quarantine.
3. **Timestamp sanity**: every entry's `runAt` must parse as ISO 8601 and must not exceed `now + 60s` (allows minor clock skew between writers; rejects far-future dates that signal forgery). Out-of-range → quarantine. Note: there is intentionally no lower bound — legitimate stale repos have old entries — so backdating defeats this check. Combined with the array-order requirement on consumers (see `reviewerStats[]` "Ordering" below), backdated forgeries cannot push legitimate entries out of the calibration window.

**Quarantine protocol** (on validation failure at step 2 or 3): write the backup to `.claude/audit-history.json.corrupt-$(printf '%010d' $(date +%s))` (10-digit zero-padded epoch — matches the step 1 sentinel glob `.corrupt-[0-9]*` and avoids collisions with user-created `.corrupt-bak` style manual backups); if the `mv` itself fails, halt with `[AUDIT-HISTORY BACKUP FAILED]` and exit non-zero (the marker is registered in `shared/abort-markers.md` under "Markers rendered outside the abortReason mapping"). On successful backup, enumerate ALL existing quarantine artifacts via the same glob `.claude/audit-history.json.corrupt-[0-9]*` and emit a Phase 7 `ACTION REQUIRED` entry naming the full set: `audit-history.json failed integrity check (<reason>) — quarantined to <new-backup-path>. Total quarantine artifacts present: <list-from-glob>. FP-rate calibration disabled. Inspect each backup, then DELETE all listed artifacts to acknowledge and re-enable calibration on the next run.` Enumerating the full set prevents the failure mode where step 2/3's singular message only names the new backup while a stale prior `.corrupt-*` keeps step 1 firing forever — the operator following the message verbatim must clear ALL quarantine artifacts. Then proceed with the run treating audit-history as **absent** (skip the calibration prepend; skip Phase 4.5 cross-run promotion; the Phase 7 step 5 append still creates a fresh file with this run's entries).

The quarantine becomes self-clearing only when the operator deletes the `.corrupt-*` file — step 1 above re-fires every run as long as any corrupt-file remains. This converts a one-time integrity event into a persistent ACTION REQUIRED until human acknowledgment, preventing the silent re-enablement that would otherwise occur on the next clean run.

**Atomic-write requirement at Phase 7 step 5**: writes to `audit-history.json` MUST use the same atomic-rename pattern as `secret-warnings.json` (see `shared/secret-warnings-schema.md` "Atomic write" for the canonical specification: `flock(1)` for cross-process serialization, write to `<path>.tmp`, fsync, `mv` to final path). **Divergence from secret-warnings on `FLOCK_AVAILABLE=false`**: secret-warnings uses a per-session-filename fallback because consumers glob `secret-warnings*.json` to enumerate all sessions' findings. **audit-history does NOT** — both `/review` and `/audit` Phase 1 read the fixed path `.claude/audit-history.json`, so a per-session fallback would silently disable cross-run calibration on macOS-without-Homebrew-flock. Instead, on `FLOCK_AVAILABLE=false`, fall back to atomic-rename-only (`<path>.tmp` + `mv`, which is atomic on POSIX) and accept the lost-update race — realistic concurrency on `/review` / `/audit` is single-user (one invocation at a time per repo), so the race window is negligible. Log the platform divergence in the Phase 7 report under `[FLOCK UNAVAILABLE — atomic-rename-only mode for audit-history]` so operators see the degraded mode (matches the `NUL_SORT_AVAILABLE=false` "degraded mode — never silent" convention). **Why mandatory**: a non-atomic Phase 7 append that crashes mid-write (Ctrl-C, OOM, host reboot) leaves orphan entries — the read-side integrity check will then quarantine a *legitimate* file on the next run, eroding operator trust in the check. False-positive quarantines from interrupted writes are the main reason operators stop reading ACTION REQUIRED entries. With atomic writes, partial state is impossible: either the new file is in place (passes integrity) or the old file is unchanged (still passes integrity).

Rationale: the quarantine path degrades safely — calibration is disabled but the run still completes, and the operator is forced to acknowledge before the file is regenerated cleanly. Silent acceptance of a forged file would convert a transient injection event into persistent quiet-mode for the security dimension.

## Schema-mismatch handling

On read, tolerate missing keys and treat them as empty arrays/objects (e.g., a file with only `runs` defined → treat `runSummaries`, `reviewerStats` as `[]` and `lastPromptedAt` as `{}`). Never overwrite a malformed file without a `.corrupt-<ts>` backup — mirror the `secret-warnings.json` schema-validation pattern (see `shared/secret-warnings-schema.md`).

## `.gitignore` enforcement

Apply the `.gitignore`-enforcement protocol (`shared/gitignore-enforcement.md`) for `.claude/audit-history.json` at every write site.

**Per-site reason if tracked**: "Audit history holds per-run rejection counts and timestamps used to drive global memory promotion — committing it would conflate one user's preference signals with other contributors' and could silently silence findings for all users."

## Skip in abort mode

When a skill is in abort mode (`abortMode=true`), skip the audit-history write entirely. A reverted run has no honest accuracy signal. Note in the Phase 7 report under `[AUDIT-HISTORY SKIPPED — abort mode]`.
