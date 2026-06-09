# Code-edit discipline

You have been assigned specific findings to fix or specific simplifications to make. Your changes must be **surgical**: every line you modify should trace directly to your assignment.

## Do NOT

- Reformat unrelated lines (quote style, whitespace, brace placement, import ordering).
- Add type hints, docstrings, JSDoc, or comments where none existed unless the assignment requires them.
- Refactor adjacent code that "could be cleaner" — leave it.
- Fix unrelated bugs you notice — surface them by marking your finding `contested` with a one-line pointer, or leave them; do NOT silently fix.
- Add error handling, fallbacks, retries, or input validation for scenarios outside the assignment.
- Delete imports, variables, or branches unless your changes orphaned them, or removing them *is* your explicit assignment. Pre-existing dead code stays unless its removal is the assigned finding.
- Rename anything (variables, functions, files) unless the assignment requires it.
- Add emoji, decorative banners, or marketing/hype language ("blazingly fast", "robust", "🚀") to code or comments.
- Add comments that restate what the code does — comment only the non-obvious *why*, and only when the assignment needs it.
- Pad the change with speculative abstraction, placeholder/stub code, or defensive guards for states that cannot occur. When new code is unavoidable (a from-scratch addition, a CI-failure fix), write the minimal version that satisfies the assignment — every line still has to pass the test below.

## Do

- Match the file's existing style, even if you would write it differently.
- If the fix requires touching code outside the assignment's scope, or would introduce a worse problem, mark the finding `contested` with a one-line reason instead of expanding scope.
- Keep the diff as small as possible — fewer lines changed is better, all else equal.

## Worked example — "Fix the bug where empty emails crash the validator"

The assignment is one bug. One bug, one fix.

### ❌ Drive-by refactor (changes 9 lines, fixes 1 issue, adds 2 unsolicited concerns)

```diff
-function validate(email) {
-  if (email.includes("@")) return true
-  return false
+/**
+ * Validate an email address.
+ * @param {string} email
+ * @returns {boolean}
+ */
+function validate(email: string): boolean {
+  if (!email || typeof email !== "string") return false;
+  if (email.trim().length === 0) return false;
+  return email.includes("@");
 }
```

Problems: added a docstring nobody asked for; added a TypeScript annotation that drifts from the file's JS style; added a `typeof` guard for a scenario outside the assignment; changed quote style and added semicolons.

### ✅ Surgical (changes 2 lines, fixes 1 issue)

```diff
 function validate(email) {
-  if (email.includes("@")) return true
+  if (email && email.includes("@")) return true
   return false
 }
```

Only the empty-email crash is fixed. Style, types, and unrelated concerns are left as-is.

## The test

Could you defend every changed line to the reviewer as "this was necessary to fix the assigned finding"? If not, revert that line.
