# Phase 1 Track B — Locale discovery — `/jr-i18n`

**Canonical source** for `/jr-i18n`'s catalog/locale discovery. `jr-i18n/SKILL.md`
reads this file into lead context at Phase 1 Track A (under the hard-fail +
non-empty + smoke-parse guard, alongside the `shared/*.md` files) and applies it at
the `## Phase 1 Track B` step. Update here to change discovery behavior.

## Framework detection matrix

Detect which i18n framework(s) the project uses by probing for catalog files within
`path` (the positional scope, or repo root if omitted). A project may use more than
one; collect all. For each match, record `framework`, the `catalogGlob`, the
`format` (json/yaml/php/po/arb), and how a locale code is derived from the path.

| Framework / convention | Catalog signal (glob) | Locale code from |
|---|---|---|
| i18next / react-intl / vue-i18n (JSON) | `**/locales/<code>/*.json`, `**/lang/<code>.json`, `**/i18n/<code>.json` | directory or filename stem |
| vue-i18n (SFC `<i18n>` or `src/locales/*.json`) | `src/locales/<code>.json`, `<sfc>.vue` `<i18n>` block | filename stem / block `locale` |
| Laravel | `lang/<code>/*.php` (assoc-array returns) + `lang/<code>.json` | directory / filename stem |
| Symfony | `translations/*.<code>.{yaml,xlf,php}` | the `.<code>.` segment |
| Rails / Ruby | `config/locales/**/*.<code>.yml` or top YAML key = code | filename segment / top key |
| Django / Python (gettext) | `**/locale/<code>/LC_MESSAGES/*.po` | directory `<code>` |
| Generic gettext | `**/*.po`, `**/*.pot` (`.pot` = template, no locale) | `Language:` header or filename |
| Flutter / ARB | `**/*_<code>.arb` or `**/<code>.arb` | filename segment |
| ICU MessageFormat | any of the above containing `{n, plural, …}` / `{n, select, …}` | host catalog's code |

If no catalog is found, abort Phase 1 with the plain-text message:
`/jr-i18n found no translation catalogs under <path>. Nothing to review.` (exit
non-zero). Do NOT invent a framework.

## Resolve source locale

The **source locale** is the reference the targets are translated *from*.
- If `--source-locale=<code>` is set, use it (validate it exists among discovered
  locales; abort if not).
- Else auto-detect: prefer `en` / `en-US` / `en-GB` if present; otherwise the locale
  with the most keys (the most-complete catalog is almost always the source); break
  ties by lexical order and record the assumption in the Phase 7 report.

The source-locale strings are the **ground truth meaning**; translator subagents
judge each target against them, never the reverse.

## Enumerate and filter target locales

- Target locales = all discovered locales minus the source.
- If `--locale=<codes>` is set, intersect targets with that list; abort if the
  intersection is empty (`No discovered locale matches --locale=<codes>.`).
- For each target, build a `(key → source string, target string|MISSING)` table by
  joining the target catalog against the source on key path. Missing-in-target and
  extra-in-target keys are recorded here (these become mechanical findings in
  Phase 3, classified `certain`).
- Record per target: `locale`, human language name (for the translator persona —
  e.g. `fr` → "French", `pt-BR` → "Brazilian Portuguese"), `catalogPath(s)`,
  `keyCount`, `missingCount`, `format`.

## Parameter sanitization

Apply before any value reaches a Bash command (reuse the other skills' allowlist
posture — `--scope` in `jr-review/SKILL.md` is the reference):
- `path` (positional): reject control chars; allowlist `^[a-zA-Z0-9][a-zA-Z0-9/_.-]*$`
  (leading char alphanumeric — NOT underscore, matching the `--scope` reference which drops it
  to fail-closed against `_..foo` before the `..` guard runs);
  reject absolute paths, `..` traversal, dot-prefixed and hyphen-prefixed segments;
  always double-quote in Bash.
- `--locale=<codes>` / `--source-locale=<code>`: each code must match
  `^[a-zA-Z]{2,3}([-_][a-zA-Z0-9]{2,8})*$` (BCP-47-ish); reject anything else. Trim
  whitespace; ignore empty entries from consecutive commas.

Discovery is read-only: use `find`/`ls`/`grep`/`jq`/`cat` only — never write.
