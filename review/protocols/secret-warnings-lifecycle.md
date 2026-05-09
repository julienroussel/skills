# Phase 7 Step 3 — Secret-Warnings Lifecycle

**Canonical procedure** for pruning, status transitions, and pattern-type absorption in `.claude/secret-warnings*.json`. Referenced by `review/SKILL.md` Phase 7 step 3. Applied for every entry in every `secret-warnings*.json` file when `abortMode=false`.

## Sub-step (a) — Schema validation

Validate the file against `../shared/secret-warnings-schema.md` (apply its shared path validation block — allowlist regex PLUS the `..` / leading-dot / leading-hyphen segment checks — to the `file` field of every entry). On validation failure, follow the schema-failure backup protocol from that shared file: back up to `.claude/secret-warnings.json.corrupt-$(date +%s)` via `mv`; if the backup itself fails halt with `[SECRET-WARNINGS BACKUP FAILED]` and exit non-zero; on successful backup emit a Phase 7 ACTION REQUIRED entry. Any backup triggered here contributes to the non-zero Phase 7 exit code — do NOT silently drop entries.

## Sub-step (b) — File-existence check + lifecycle

For each entry's `file` field, test `[ -r "$file" ]`.

If the file is missing OR unreadable:
- Do NOT remove the entry.
- If the entry's current `status` is `"acknowledged"`, preserve it (do NOT overwrite with `"unverified"`).
- Otherwise, mark `status: "unverified"` and surface in the Phase 7 report: `ACTION REQUIRED: Cannot verify secret-warnings entry <file>:<line> — file missing or unreadable`.

A "no match" for a missing file must never be interpreted as "resolved".

### Lifecycle of `unverified` entries (`missingRunCount` + counter reset)

Track an integer `missingRunCount` on the entry. On each run where the file is missing OR unreadable, compute the new value by examining the entry's PRIOR state:

- If prior `status` was NOT `"unverified"` (i.e., `"active"`, `"acknowledged"`, or absent on a legacy entry): `missingRunCount = 1` — first run confirming the file is missing.
- If prior `status` WAS `"unverified"`: increment by 1. Do NOT reset to `1` on re-confirmation.

After 3 consecutive `/review` runs where the file remains missing (`missingRunCount` reaches `3`), the entry becomes eligible for pruning. Log each eviction: `expired unverified entry: <file>:<line> — file missing for 3 runs`.

In **interactive mode**, per `unverified` entry, AskUserQuestion: `Acknowledge entry <file>:<line>? Options: [Acknowledge — stop surfacing] / [Keep — surface in future runs]`. On Acknowledge, write `status: "acknowledged"` and stop surfacing in subsequent reports.

In **headless/CI mode**, do NOT auto-acknowledge — entry is report-only until a future interactive run handles it.

### Re-acknowledge prompt for override-flipped entries

For each entry whose `status` was flipped from `"acknowledged"` to `"active"` by sub-step (c)'s acknowledge-status override during this run (i.e., the marker `Previously acknowledged secret is now confirmed present: <file>:<line>` was surfaced), in **interactive mode** AskUserQuestion: `The secret at <file>:<line> was previously acknowledged and is now confirmed present again. Options: [Re-acknowledge — stop surfacing] / [Keep surfacing until resolved]`.

On **Re-acknowledge**: set `status: "acknowledged"`. Suppress further surfacing in this run's report and in subsequent runs until the next override trigger fires per (c)'s conditions (a different line, a different `patternType`, or a missing→present file transition). A rescan matching at exactly the same `(file, line, patternType)` on a continuously-present file will NOT re-fire the override.

On **Keep surfacing**: preserve `status: "active"` — entry continues to surface each run.

In **headless/CI mode**, do NOT auto-re-acknowledge — report-only.

### Reset on file re-appearance

Whenever sub-step (c) is invoked (file exists and is readable), unconditionally reset `missingRunCount = 0` and, if `status` is `"unverified"`, reset to `"active"` (but preserve `"acknowledged"` — those transition back to `"active"` only via the acknowledge-status override below). This makes the lifecycle symmetric: missing → increment; present → reset. Without this reset, a file that oscillates between missing and present would accumulate a non-consecutive `missingRunCount` and either be prematurely evicted or remain stuck in `unverified` despite confirmation that the secret is present.

## Sub-step (c) — Whole-file pattern rescan

When the file exists and is readable, scan the **entire file** (not only the originally recorded line) for the canonical regex corresponding to the entry's `patternType`. Look up the canonical regex in the Phase 1 pattern table (Track B step 7) — NEVER use `patternType` as a literal regex.

### `patternType: "other"` — full-scan fallback

When `patternType == "other"` (catch-all enum value for patterns without a dedicated label), scan using the full Phase 1 pre-scan regex union (Track B step 7) — NOT a single canonical sub-pattern. Apply the same decision matrix as for known `patternType` values (no match → remove; match at original line → unchanged; match at different line → update `line`).

#### Advisory-tier filter for `"other"` full-scan

The "Advisory-tier classification for re-scans" (`../shared/secret-scan-protocols.md`) classifies matches into strict and advisory tiers. For the `"other"` full-scan, only strict-tier matches count toward the line-update / persistence decision. Advisory-tier matches are logged to the Phase 7 report and treated as "no match" for line-update / persistence purposes.

To preserve audit-trail integrity across runs where a file's advisory-classification criteria may drift (e.g., a file moved into a `test/` directory after the entry was written), an `"other"` entry whose ONLY remaining matches are advisory-tier is NOT pruned outright — instead, kept with `status: "unverified"` and surfaced in the Phase 7 report as `ACTION REQUIRED: secret-warnings entry <file>:<line> — only advisory-tier matches remain; verify manually that the underlying pattern has been resolved before the entry can be pruned.` This prevents silent audit-trail deletion based on transient path-classification criteria.

#### Pattern-type non-absorption rule

When the full-scan matches a sub-pattern whose dedicated enum label differs from `"other"`, do NOT automatically absorb the match into the existing `"other"` entry. First, check whether the full-scan ALSO finds any match whose pattern has NO dedicated enum label (i.e., a genuinely `"other"`-class pattern such as `npm_`, `pypi-`, `sbp_`, `hvs.`, `dop_v1_`, `dp.st.`, `dapi`, `shpat_`, `GOCSPX-`, `AccountKey=`, `vc_`, `glpat-`, `dckr_pat_`, `nfp_`). Note: `sk-ant-` has the dedicated `anthropic-key` enum and is NOT `"other"`-class.

**Decision matrix**:

- **Some `"other"`-class match remains** (at original line or shifted): keep the `"other"` entry; update `line` to the remaining `"other"`-class match if it moved. For each co-occurring dedicated-label match, atomically (i) append a new entry to the current `secret-warnings.json` with the detected specific-label `patternType`, the current `line`, and `detectedAt = now` (apply Phase 5.6's atomic-rename + flock semantics); (ii) if `.claude/secret-hook-patterns.txt` exists and does not already contain the canonical regex for the detected label, append it. Then emit a Phase 7 note: `A different pattern type (<specific-label>) was also detected at <file>:<new-line>. A new entry of the specific type may be created by the next Phase 5.6 re-scan if an implementer modifies this file.` This closes the window where a confirmed secret is invisible to the commit-blocker between now and the next Phase 5.6 re-scan.

- **No `"other"`-class match remains** AND at least one dedicated-label match exists: the original `"other"` pattern has been resolved, but a co-occurring match of a different type is present. Atomically create new entries for each co-occurring dedicated-label match (same two-step append as above — secret-warnings.json entry + patterns-file entry). Only after the new entries are persisted may the `"other"` entry be removed. This ensures the audit trail never has a window where a detected secret is untracked.

- **No matches at all** (neither `"other"`-class nor dedicated-label): standard "no match → remove" — the secret has been resolved.

This preserves the resolution path for entries whose underlying pattern has no dedicated enum label, prevents silent mis-labeling of the audit trail, and keeps the `patternType` field reliable for future `/ship` enforcement filtering.

#### Interaction with the acknowledge-status override

For pattern-type-absorbed matches, bypass the acknowledge-status override — absorbed matches do NOT count as "this rescan finds a match" for override purposes. The Phase 7 absorption note is the sole audit record for those matches. A subsequent Phase 5.6 re-scan creating a new entry of the specific type will retrigger the normal acknowledge-status lifecycle if that new entry later becomes `acknowledged`. This prevents (a) sub-step (b)'s re-acknowledge AskUserQuestion from referencing an entry just pruned in the same run and (b) double-reporting the same match as both an override flip AND an absorption note. Newly-created dedicated-label entries participate in normal override lifecycle in future runs; the bypass applies only to the transient absorption event within this run.

If no entry in the pattern table matches the `patternType` value (unknown type — reachable only if schema validation has been weakened or bypassed), mark the warning `unverified` with `ACTION REQUIRED: unknown patternType <value>` and do NOT prune.

### Decision matrix for known `patternType` values

- **No match anywhere in the file** → secret has been removed. Remove the entry.
- **Match at the originally recorded `line`** → entry unchanged.
- **Match at a different line** (e.g., formatter shifted it) → update `line` in place. The secret is still present; only its location moved.

### Acknowledge-status override (fires BEFORE the decision matrix above)

If the entry's `status` is `"acknowledged"`, check the override trigger. The trigger fires when ANY of:
1. The rescan finds a match at a DIFFERENT line than the recorded `line` (formatter shift, edit, or relocation).
2. The rescan finds a match whose `patternType` differs from the recorded `patternType` (a different class of secret now matches in this file).
3. The file transitioned missing→present between the prior run and this run (captured by sub-step (b)'s `missingRunCount`-reset path).

If NONE of these conditions are met (i.e., the rescan matches at exactly the recorded `(file, line, patternType)` and the file has been continuously present), do NOT fire the override — preserve `status: "acknowledged"` and do NOT surface an ACTION REQUIRED marker; the prior acknowledgment still applies.

When the override DOES fire: reset `status` to `"active"` and surface a new ACTION REQUIRED entry: `Previously acknowledged secret is now confirmed present: <file>:<line>`. Then fall through to the decision matrix above (line update or unchanged). Interactive mode also offers an in-band re-acknowledge path — see sub-step (b)'s "Re-acknowledge prompt for override-flipped entries".

## Sub-step (d) — Atomic write-back

After processing all entries in a given file, write the pruned result back atomically (same atomic-rename + flock requirements as Phase 5.6). Preserve the top-level `consumerEnforcement` field.

## Sub-step (e) — Empty-array cleanup

If the `warnings` array is empty after pruning, delete the warnings file unconditionally. No hook coordination is performed. The hook does NOT self-remove — by design, per the "no sentinel to forge" invariant in the pre-commit hook template (Phase 5.6). Disarming requires explicit user action.

If the pre-commit hook is still installed (i.e., `.git/hooks/pre-commit` exists and contains the line `# BEGIN claude-secret-guard`) at the time the warnings file is deleted, emit a Phase 7 ACTION REQUIRED entry: `Pre-commit hook still installed. Manually remove the block between '# BEGIN claude-secret-guard' and '# END claude-secret-guard' in .git/hooks/pre-commit when ready to disarm.`

After processing all `secret-warnings*.json` files, if none remain, the review is clean of audit-trail entries; log this in the report.
