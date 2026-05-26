---
name: tackle
description: Wrap an ad-hoc task with rigor instructions — ultrathink, verify findings against current sources or advisor(), ask clarifying questions early, bias toward smallest viable change, cite file:line for code claims, call advisor() before declaring done. In-session equivalent of bin/tackle's "in plan mode, ultrathink to tackle ..." prefill.
argument-hint: <task description>
effort: max
model: opus
disable-model-invocation: true
user-invocable: true
---

<!-- Frontmatter notes:
- This skill is intentionally minimal: a prompt wrapper, not an audit-class skill.
  No shared/*.md references, no Phase 1 Track A guard, no protocols/ or scripts/.
- "in plan mode" in the body is declarative text only — a skill body cannot engage
  Claude Code's harness plan mode (user action only: Shift+Tab or
  --permission-mode plan). The body instructs Claude to treat irreversible
  actions as requiring explicit user confirmation regardless of harness state.
  No upfront AskUserQuestion gate — bin/tackle launches fresh sessions where
  "Enabled plan mode" never appears in context, so an auto-detect-and-nudge
  gate would fire on every PR/issue invocation. The "Ask clarifications early"
  step in the rigor protocol naturally surfaces intent before substantive work.
- Symmetric with bin/tackle's prompt prefill (bin/tackle:19-21). Out-of-session
  bootstrap = bin/tackle. In-session rigor wrap = /tackle.
-->

ultrathink

You have been invoked via `/tackle`. The task is at the end after `Task:`. Apply the rigor protocol below to that task.

## Plan-mode discipline

This skill cannot engage Claude Code's harness plan mode from its body — that's a user action (Shift+Tab or `--permission-mode plan` at startup). Whether or not the harness is actually in plan mode, treat irreversible actions (file writes, commits, external sends, destructive shell commands) as requiring explicit user confirmation. Read-only orientation (file reads, grep, web fetches, `advisor()`) is fine without confirmation.

## Rigor protocol

1. **Ask clarifications early.** Before substantive work, surface task ambiguities via `AskUserQuestion`. Do not assume — ask.
2. **Verify everything.** Any claim about code, files, behavior, APIs, or library features must be verified (Read / Grep / Bash / WebFetch / `advisor()`) before stating it. Cite `file:line` for code claims. For external claims (library APIs, docs, current versions), prefer a current source (`WebFetch` the official doc) over training knowledge.
3. **Investigate to definite.** When a claim is uncertain, investigate until you can confirm or refute. Do not leave findings as "might be", "could potentially", or "I'm not sure if". State definite findings or state explicitly what's blocking investigation.
4. **Smallest viable change.** Before adding infrastructure (new types, files, abstractions, API surface), check whether existing call sites, callbacks, return values, or hooks can carry the load. State the requirement first, derive the minimum, then ask "what existing capability can I compose?" before "what new thing should I build?".
5. **Advisor before declaring done.** Call `advisor()` before reporting the task complete. Make the deliverable durable (write the file, save the result, commit the change) BEFORE the call so a session interruption mid-call doesn't lose work.

---

Task: $ARGUMENTS
