# Subagent reporting contract

**Canonical source** for how a spawned subagent's work reaches the lead, and for how the lead accounts for a subagent that returns nothing. Read at Phase 1 (Track A) by `/jr-audit`, `/jr-review`, `/jr-skill-audit`, and `/jr-i18n`; applied by the lead at every Agent-spawn site, every findings-collection site, and every clean-result output.

## Spawn rule: never pass `name:` to a work-producing subagent

A subagent spawned **without** `name:` is a task. It runs, ends, and its final response is delivered to the lead in its completion notification (the `<result>` field) — the channel every collection site reads.

A subagent spawned **with** `name:` is a persistent teammate. It does not terminate with a return value: it ends a turn and goes idle awaiting messages, and **its final response never reaches the lead**. Everything it found is lost unless it is separately messaged.

So: **do not pass `name:`** when spawning a reviewer, translator, or implementer whose output the run depends on. `name:` buys mid-flight addressability and costs the return channel. No phase in these skills needs to message a worker mid-flight, so the trade is never worth taking.

`name:` was adopted repo-wide in the 2.1.178 implicit-team migration purely as the replacement for the removed `TeamCreate`, together with the assumption that teammates "finish their assigned work and end their own turns". That assumption is false, and it is what made findings vanish silently (issue #70). Spawning without `name:` is not a workaround; it is the absence of the defect.

### Verified behaviour

Full 2×2, both variables crossed. In the 2026-07-16 run (against `agent-teams` v1.0.3), each agent was given a known token as its entire final response and told not to message; each named agent was afterwards confirmed **alive and already finished** by asking it directly, so these are genuine non-deliveries and not slow ones:

| `subagent_type` | `name:` | Report reaches the lead? |
|---|---|---|
| `jr-reviewer` (repo-local) | no | **Yes** — in the completion notification's `<result>` |
| `jr-reviewer` (repo-local) | **yes** | **No** |
| none (default) | no | **Yes** — same `<result>` channel |
| none (default) | **yes** | **No** |

Provenance: the `jr-reviewer` rows relabel that original two-type cross-product. Only the `jr-reviewer` unnamed→`<result>` cell was separately re-verified (2026-07-18 against `.claude/agents/jr-reviewer.md`, identical); the named-`jr-reviewer` row follows from the type-independence the original run established across two types (below), not a fresh measurement, and the `default` rows are built-in behaviour carried over.

**`name:` is the sole determinant; `subagent_type` is irrelevant to it.** Both types return when unnamed and both go silent when named. Switching agent types neither fixes nor causes this: the repo-local `jr-reviewer` type spawned with `name:` loses findings exactly the same way the default type does.

The mechanism is visible in the notification shape: an unnamed spawn produces a task notification carrying a `<result>` field; a named spawn produces an idle notification (`"idleReason":"available"`) that has **no result field at all**. There is no slot for a named agent's return value.

`TaskCreate` is a separate dead end, not an alternative: the repo-local `jr-reviewer` and `jr-implementer` defs grant no task tools at all (their `tools:` lists are `Read, Glob, Grep, Bash` and `Read, Write, Edit, Glob, Grep, Bash`), and the lead itself has no `TaskList`. Tasks are unusable as a channel in either direction.

This table is harness behaviour and can change across Claude Code and plugin releases: re-verify after an upgrade (methodology: `../docs/skill-anatomy.md` "Re-verifying a harness claim").

## Subagent-facing block (pass verbatim)

> **Your final response IS your report.** It is returned to the lead when your turn ends; nothing else you emit reaches it. Put everything you found in it.
>
> - **If you found nothing, say so explicitly** (for example, "no findings for <dimension>"). Do not end your turn silently: the lead cannot tell silence apart from a clean result, so silence is reported as a failure, not as a pass.
> - **Report the scope you actually covered, not just what you found.** Name what you checked and what you did not reach — a reviewer or translator says which files or locales it examined; an implementer that fixed the named instances says whether the same defect has other sites it did not touch. A partial pass reported as a complete one is the same silent loss as an empty return, one level up.
> - Do NOT use `TaskCreate`: you do not have it, and calling it will fail.
> - Do NOT use `SendMessage` to deliver findings: the repo-local reviewer/implementer types do not grant it, so calling it will fail; and even where it is available, no lead phase reads messages, so anything sent that way is lost. Your final response is the only channel.
> - Do not print progress to the console. Your console output is not visible to the user.

## Lead-side: reviewer roll-call

Returning is the norm, not a guarantee: a subagent can error, be skipped by the user, exhaust its turn budget, or return an empty result. The lead MUST account for **every** subagent it spawned, reconciling the spawn list against the results actually returned, before the phase closes.

| Returned | Classification |
|---|---|
| Findings | Normal processing. |
| An explicit "no findings" | Clean dimension. |
| Nothing, an empty result, or an error | `UNREPORTED`. A failure, never a clean dimension. |

A lost **implementer** is the same failure in a different phase, and every downstream gate reports success on it: no finding is marked `addressed`, so fix-verification verifies an empty set and prints `0/0 fixes verified`, and validation passes trivially because unmodified code still lints. Its assigned findings were **not attempted** — never report them as "remaining", which reads as a user decision.

**The state is run-level and monotonic.** `unreported` is a set that accumulates across the **whole run**: every roll-call appends to it (each pass's reviewers and each implementer dispatch are the usual ones, but the rule is every roll-call the skill runs, whatever the phase), and nothing ever resets or decrements it. `unreportedCount` means `|unreported|` for the run, and every consumer below reads that run-level value.

A loop may track a **separate** per-pass value for its own termination decision ("did *this* iteration converge?"), and must name it distinctly (`passUnreported`). **Every roll-call appends each `UNREPORTED` member to BOTH the run-level `unreported` set AND `passUnreported`** — a roll-call is the only producer of either, so a loop that reads `passUnreported` without a roll-call writing it reads an empty set forever and its guard silently never fires. **The loop MUST reset `passUnreported` to empty at the start of each iteration, before that iteration's first roll-call**; the run-level set is never reset. `passUnreported` MUST NOT reach a report, an exit code, or a persisted snapshot. Making the counter per-pass reopens the defect one loop deeper: a pass that loses a reviewer *while other reviewers still produce findings* leaves a non-empty `modifiedFiles`, so the loop's zero-findings and no-files-changed guards never evaluate; a later clean pass then overwrites the count to zero, and the run renders nothing, exits `0`, and publishes a score.

**`UNREPORTED` is load-bearing state and MUST be consumed.** A consumer that computes it and then drops it has rebuilt the original defect with extra steps. Every consumer therefore:

1. **Renders every member by name in the Phase 7 report**, in that skill's report-integrity section, whenever the set is non-empty. Source that report item from the run-level set, never from a list of spawn sites: any roll-call added later latches `unreportedCount` into the non-zero exit whether or not the item was updated, and an exit code the report cannot explain is the defect the item exists to prevent. Name each member per its kind — a lost reviewer dimension was **not reviewed/audited**; a lost implementer's assigned findings were **not attempted** (never "remaining", which reads as a user decision); a lost single-purpose agent's pass **did not run**.
2. **Exits non-zero** when any dimension is `UNREPORTED`, alongside the other "the run did not do what it claims" conditions. Under headless/CI the exit code is the only channel a machine reads.
3. **Blocks every clean-result path**: no `no findings` / `clean` / `all clear` output, and no `converged = true`, while any dimension is `UNREPORTED`. This applies to convergence passes and the fresh-eyes gate exactly as it applies to the first pass.

The third rule is the one that closes issue #70. A zero-findings short-circuit that fires without consulting the roll-call reports a lost swarm as a clean run.
