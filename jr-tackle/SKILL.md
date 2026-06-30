---
name: jr-tackle
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
  --permission-mode plan). The body declares an explicit scope split: tackle
  makes file edits; /jr-ship owns all git mutations (add/commit/push/PR/MR/merge).
  No upfront AskUserQuestion gate — bin/tackle launches fresh sessions where
  "Enabled plan mode" never appears in context, so an auto-detect-and-nudge
  gate would fire on every PR/issue invocation. The "Ask clarifications early"
  step in the rigor protocol naturally surfaces intent before substantive work.
- Symmetric with bin/tackle's prompt prefill (bin/tackle:19-21). Out-of-session
  bootstrap = bin/tackle. In-session rigor wrap = /jr-tackle.
-->

ultrathink

You have been invoked via `/jr-tackle`. The task is at the end after `Task:`. Apply the rigor protocol below to that task.

## Scope: edits only — /jr-ship owns git

This skill cannot engage Claude Code's harness plan mode from its body — that's a user action (Shift+Tab or `--permission-mode plan` at startup). Whether or not the harness is actually in plan mode:

- **File edits are the deliverable.** Use Edit/Write freely on the task at hand.
- **Git mutations are OUT OF SCOPE.** Never run `git add`, `git commit`, `git push`, `git merge`, `git reset`, `git checkout -- <path>`, `git clean`, `git stash drop`, `git rebase`, `gh pr create` / `glab mr create`, `gh pr merge` / `glab mr merge`, or any other git/forge (gh/glab) command that mutates state — including destructive resets that discard working-tree changes (your edits are the deliverable; do not destroy them). The companion `/jr-ship` skill is the dedicated commit/push/PR/merge path — stop at the working-tree-modified state and report `git diff --stat` to the user.
- **Other irreversible actions** (external sends, destructive shell, dropping tables) require explicit user confirmation per scope.
- **Read-only operations** (file reads, grep, web fetches, `advisor()`, `git status`/`log`/`diff`) are always fine.

## Rigor protocol

1. **Ask clarifications early.** Before substantive work, surface task ambiguities via `AskUserQuestion`. Do not assume — ask.
2. **Verify everything.** Any claim about code, files, behavior, APIs, or library features must be verified (Read / Grep / Bash / WebFetch / `advisor()`) before stating it. Cite `file:line` for code claims. For external claims (library APIs, docs, current versions), prefer a current authoritative source over training knowledge — fetch raw markdown (`gh api …/contents/<path>`, or the doc's raw `.md`) rather than a rendered page, and cross-check any load-bearing or verbatim claim against a second fetch or `advisor()`. A single `WebFetch` summarization can fabricate text (it has reported a non-existent `ultra` effort value as real), so never rest a load-bearing claim on one WebFetch.
3. **Investigate to definite.** When a claim is uncertain, investigate until you can confirm or refute. Do not leave findings as "might be", "could potentially", or "I'm not sure if". State definite findings or state explicitly what's blocking investigation.
4. **Smallest viable change.** Before adding infrastructure (new types, files, abstractions, API surface), check whether existing call sites, callbacks, return values, or hooks can carry the load. State the requirement first, derive the minimum, then ask "what existing capability can I compose?" before "what new thing should I build?". And don't pad what you *do* write: no speculative abstraction, placeholder stubs, defensive guards for states that can't occur, comments that restate the code, or emoji/marketing language.
5. **Advisor before declaring done.** Call `advisor()` before reporting the task complete. Make the deliverable durable (write the file or save the result) BEFORE the call so a session interruption mid-call doesn't lose work. **The file write is the durability — do NOT commit.** Per the scope rules above, `/jr-ship` owns all git mutations.

---

Task: $ARGUMENTS
