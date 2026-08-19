# Model Override (`--model=<tier>`)

**Canonical source** for the per-run subagent model-override flag (`--model=<tier>`). Each consumer reads this file at Phase 1 (Track A or inline) and applies the rules below at every Agent-spawn call site. Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section.

## Flag and sanitization

- Flag: `--model=<tier>`. Allowlist regex `^(sonnet|opus|haiku|fable)$` — the Agent tool's model enum. Full model IDs (e.g. `claude-opus-4-8`) are rejected.
- On rejection, abort argument parsing with: `Invalid --model value '<value>'. Valid values: sonnet, opus, haiku, fable.`
- Composes with every other flag in every consumer; no flag conflicts.

## Model override semantics

When `--model=<tier>` is set, **every subagent spawn** in the run passes `model: "<tier>"` to the Agent tool, replacing the per-site preset:

- Sites that hardcode a premium tier (e.g. `model: "opus"` reviewers, implementers, simplification, split-analysis, CI-fix, fresh-eyes) use `<tier>` instead.
- Sites documented as "default model is fine" (mechanical phases that spawn agents) ALSO pass `<tier>` — the override is total, not premium-sites-only.
- Nested spawns inherit their parent's model unless explicitly set, so the override propagates to sub-agents-of-sub-agents automatically; consumers only need to honor it at the spawns they issue directly.

**Default when `--model` is NOT set: `opus` for every override-governed spawn.** The judgment-bearing spawn sites — reviewers, implementers, simplification, split-analysis, CI-fix, fresh-eyes — each document a `model: "opus"` preset, so absent the flag they run on opus and MUST carry an explicit `model:` rather than be left unset to inherit the lead (which may be on any tier). Mechanical phases (context-gathering, dedup, validation, cleanup) are lead-run and keep the session default unless `--model` is set (per the total-override rule above) — they are cheap by design and not pinned to opus. The lead's own model is governed by frontmatter and is out of scope for this flag.

## Lead-model caveat

The flag does NOT change the lead agent's model: frontmatter `model:` is applied when the skill is invoked, before the body parses arguments — no flag can retroactively override it.

**Setting the session model first does NOT work around this — do not advise it.** The skills doc's `model` row states the field is the "Model to use when this skill is active. The override applies for the rest of the current turn", and it offers `inherit` as a *separate* value "to keep the active model". A concrete value therefore **replaces** whatever `/model` selected, for as long as the skill runs: `/model opus` followed by `/jr-review` (frontmatter `model: sonnet`) still runs the lead on sonnet.

For a genuinely uniform run there are only two levers, both deliberate edits rather than session state:

- Edit the skill's frontmatter `model:` to the tier you want, or
- set it to `inherit`, which makes the lead follow the session model — but note that un-pins a lead tier several skills pin on purpose (see the repo `CLAUDE.md` model-routing convention), so treat it as a design change, not a per-run workaround.

`--model=<tier>` remains the correct and complete mechanism for **subagents**, which is where the judgment-bearing work happens.

## Advisor model (out of scope for `--model`)

`--model` governs **worker subagents only** — it does NOT retarget the `advisor()` tool. `advisor()` is parameter-less; its model is the global `advisorModel` setting (read at session start), changed via the `/advisor <tier>` command, not by any skill flag. This separation is intentional: the advisor is an *independent* second-opinion reviewer, often deliberately a different/stronger tier than the workers it reviews.

For a fully-uniform run (workers AND advisor on one tier), set both:

```
/advisor <tier>
/jr-review --model=<tier>
```

A skill must NOT mutate `advisorModel` in `settings.json` to honor `--model`: that setting is global (affects concurrent sessions), is typically loaded at session start (a mid-run edit may not take effect), and a save/restore is fragile across aborts.

## Display rule

When the flag is set, append `Model override: <tier>` to the consumer's Phase 1 discovery/summary line so the override is visible in the run header.
