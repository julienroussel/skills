# Shared Secret-Pattern Catalog

**Canonical source** for the regex union and per-pattern demotion criteria, applied at every secret pre-scan and post-implementation re-scan site of its consumers. The pre-commit hook a consumer installs reads `.claude/secret-hook-patterns.txt` (not this file directly) — this file is the human-maintained source of truth that the install path materializes. Consumers aren't enumerated here (to avoid per-file drift) — the authoritative source is each skill's own Phase 1 read list, summarised in the repo `CLAUDE.md` "shared/ — single source of truth" section.

## Portability and evaluation-time safeguards

Apply these BEFORE invoking the regex on any input:

- **POSIX ERE smoke probe** (run once at first-use site): `printf 'foo\n' | grep -E '^f{1,3}o+$' >/dev/null 2>&1`. On failure, abort with `[ABORT — GREP -E INCOMPATIBLE] Detected grep that lacks POSIX ERE quantifier support. Install GNU grep or set GREP=ggrep before re-running.` This probe proves grep supports ERE quantifiers; it does NOT prove the union below compiles on that grep, and it passes on a host where the real scan errors out (see the repetition-bound rule below). Every scan site MUST therefore treat a grep exit status **above 1** as a scan failure and never as a clean result, using the **Scan-status check** below.
- **Scan-status check (mandatory at every scan site)**: branch on grep's **exit status**, never on its output alone. A grep that rejects the union (repetition-bound rule below) or cannot read a file exits 2 and prints nothing, so an output-only test reads a total scan failure as "no secrets found".

  **Grep must be the sole command whose status you read.** Hand it a file, a here-string, or a temp file you materialised first, never the tail of a pipe:

  ```bash
  out=$(grep -Ei -- "$pattern" "$file"); ec=$?      # a file on disk
  out=$(grep -Ei -- "$pattern" <<< "$body"); ec=$?  # an in-memory body
  case "$ec" in
    0) ;;   # match: the site's detection path
    1) ;;   # no match: the ONLY clean outcome
    *) ;;   # scan failure: the site's halt path, never a clean result
  esac
  ```

  Under `set -e`, wrap each capture in `set +e` / `set -e`, the producer capture below included, or the status check never runs.

  **Why never a pipe** (`git diff | grep …`, `printf … | grep …`): `$?` is the **tail's** status, so a producer that fails hands grep empty input and grep exits 1, which is the one status arm `1` calls clean. `set -o pipefail` does not close this: it yields the *rightmost* non-zero status, and grep's own `1` is the rightmost. When the input is a command's output, capture it first and check the producer's own status before scanning (`blob=$(git diff); pec=$?`, then route any non-zero `pec` to the `*)` halt path), or write it to a temp file and scan that. Do not reach for `PIPESTATUS` as the escape hatch: it is a bash array whose spelling is not portable across the shells these sites run under, and the wrong spelling expands to nothing, reproducing the same silent pass.

  Working exemplar: `jr-review/templates/pre-commit-secret-guard.sh.tmpl`. What makes it safe is not the `case` arms alone: every scan in it is the sole-command shape above (grep reads a file, or a staged blob already materialised by a separately status-checked `git show`), its enumeration pipelines run under `set -e -o pipefail`, and its pattern-validity probe tests `[ "$ec" -gt 1 ]`. A reader who lifts the arms into a pipeline inherits none of that. **Never let grep print its matches**: the matching line *is* the credential, and `grep -nEi` echoes it verbatim into whatever surface the caller is writing to. Keep the `out=` capture, take the locations from its `<lineno>:` prefix (as the exemplar does), and report the line number and pattern type, never the matched text. **Halt route, by site kind** (named here so every consumer cites one dialect instead of inventing its own): a **pre-scan** site aborts with the same `[ABORT — GREP -E INCOMPATIBLE]` marker as the smoke probe, quoting the exit status; a **post-write redaction-verification** site treats the artifact as uncertified rather than clean and takes its own redaction-failure route; a **pre-publication redaction** site, which redacts a body immediately before an irreversible post to a possibly-public forge, treats that body as uncertified rather than redacted, does NOT publish it, and surfaces the exit status through the consumer's own operator-escalation route (a status above 1 makes the redaction a silent no-op, so publishing on it posts the unredacted body).
- **Per-line length cap (10000 bytes)**: lines exceeding the cap are flagged in the Phase 7 report under `[OVERSIZED LINE — MANUAL REVIEW]` with file path and line number — they are NOT regex-evaluated. Bounds regex evaluation time and prevents pathological backtracking against adversarial long lines.
- **No repetition bound above 255 — use an open-ended `{n,}` instead.** 255 is a *floor*, not a ceiling: POSIX only requires a conforming implementation to support bounds up to `RE_DUP_MAX`, whose minimum is 255. GNU grep allows far higher, which is why an oversized bound runs fine on Linux and fails only once it reaches a BSD host. macOS's stock `grep` (BSD grep 2.6.0-FreeBSD) implements exactly the floor: one bound of 256 makes grep print `grep: maximum repetition exceeds 255` and **exit 2**, which rejects the *whole* union, not just the offending alternative. Every scan on that host then returns no matches, and any caller that treats "no output" as "no secrets" reads a total scan failure as a clean bill of health. Open-ended bounds (`{10,}`, `{1,}`, `{0,}`) are accepted by BSD grep and are what the patterns below use. Do NOT "fix" a too-large bound by capping it at 255: that silently converts the error into a false negative, since a 400-character JWT payload matches an open-ended bound but not a capped one (the pattern is anchored at `eyJ` and must reach the following `.`). Input length is already bounded by the per-line cap above, so an open upper bound costs nothing. **This rule is deliberately written without any literal over-255 brace form**, so that `grep -oE '\{[0-9]+,[0-9]+\}' shared/secret-patterns.md` with an "upper bound > 255" filter is a clean regression guard for this file rather than one with a permanent known false positive.
- **POSIX ERE constraint on every pattern below**: no Perl-style shorthand (`\s`/`\d`/`\w`/`\b`), no Perl-style grouping (`(?:...)`/`(?=...)`/`(?<!...)`). Use POSIX character classes (`[[:space:]]`/`[[:digit:]]`/`[[:alnum:]]`). Non-boundary checks (e.g., the `dapi` prefix check) MUST be implemented as post-match line inspection in the consuming code, NOT as lookbehinds inside the regex.

<!-- harness-claim-verified: 2026-08-08 -->
<!-- Live probe 2026-08-08 on macOS (/usr/bin/grep, BSD grep 2.6.0-FreeBSD): an upper bound of 256
     printed "maximum repetition exceeds 255" and exited 2, rejecting the entire union; 255 was
     accepted; open-ended {10,} / {1,} / {0,} were all accepted. A 400-character JWT payload matched
     the open-ended form and did NOT match a 255-capped one, which is why the fix opens the bound
     rather than capping it. Re-verify if the patterns below gain a new bounded quantifier or if the
     supported grep set changes. -->
<!-- Live probe 2026-08-08, same session, on the pipe shape behind the Scan-status check:
     `false | grep -Ei <pattern>` exited 1 both with and without `pipefail`, under bash 3.2.57 AND
     zsh 5.9, so by `$?` alone a failed producer is indistinguishable from a clean no-match. `pipefail`
     returns the RIGHTMOST non-zero status (bash 3.2.57: `exit 42 | exit 7` = 7, `exit 42 | exit 0`
     = 42), so grep's own 1 masks the producer. Under zsh 5.9 `${PIPESTATUS[@]}` expanded EMPTY while
     `${pipestatus[@]}` read `1 1`, which is why the rule above is "do not pipe into grep" rather
     than "read PIPESTATUS". The sole-command shapes were confirmed to propagate all three statuses:
     `grep -nEi -- <pat> <<< "$body"` returned 0 on a hit, 1 when clean, and 2 on a pattern the host
     grep rejects. Re-verify if a consumer moves to a shell not covered here. -->

## Invocation flag

Invoke with `grep -Ei`. The `-i` is mandatory — the case-insensitivity is annotated on the quoted-credential and env-assignment patterns; omitting `-i` produces false negatives on lowercase keys (e.g., `database_url=postgres://...`). Strict-prefixed patterns like `AKIA`/`ghp_` are unaffected because their literal characters don't appear in real secrets recased.

## Token-prefix patterns (regex union)

```
(AKIA[0-9A-Z]{16}|sk_live_[a-zA-Z0-9]{20,200}|rk_live_[a-zA-Z0-9]{20,200}|sk_test_[a-zA-Z0-9]{20,200}|rk_test_[a-zA-Z0-9]{20,200}|sk-ant-[a-zA-Z0-9_-]{20,200}|sk-[a-zA-Z0-9_-]{20,200}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|ghs_[a-zA-Z0-9]{36}|ghu_[a-zA-Z0-9]{36}|ghr_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9]{22,200}|xox[bpaes]-[a-zA-Z0-9-]{1,200}|xoxe\.xox[bp]-[a-zA-Z0-9-]{1,200}|-----BEGIN .{0,50} PRIVATE KEY|SG\.[a-zA-Z0-9_-]{1,200}\.[a-zA-Z0-9_-]{1,200}|AIza[0-9A-Za-z_-]{35}|npm_[a-zA-Z0-9]{36}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|AccountKey=[a-zA-Z0-9+/=]{44,200}|SK[a-fA-F0-9]{32}|pypi-[A-Za-z0-9_-]{16,200}|sbp_[a-zA-Z0-9]{20,200}|hvs\.[a-zA-Z0-9_-]{24,200}|dop_v1_[a-zA-Z0-9]{43}|dp\.st\.[a-zA-Z0-9_-]{1,200}|dapi[a-fA-F0-9]{32}|shpat_[a-fA-F0-9]{32}|GOCSPX-[a-zA-Z0-9_-]{28}|https://hooks\.slack\.com/services/T[A-Z0-9]{8,15}/B[A-Z0-9]{8,15}/[a-zA-Z0-9]{24}|https://(discord|discordapp)\.com/api/webhooks/[0-9]{1,25}/[a-zA-Z0-9_-]{1,200}|"private_key":[[:space:]]*"-----BEGIN|vc_[a-zA-Z0-9]{24,200}|glpat-[a-zA-Z0-9_-]{20,200}|gldt-[a-zA-Z0-9_-]{20,200}|glrt-[a-zA-Z0-9_-]{20,200}|glrtr-[a-zA-Z0-9_-]{20,200}|gloas-[a-zA-Z0-9_-]{20,200}|glptt-[a-zA-Z0-9_-]{20,200}|glagent-[a-zA-Z0-9_-]{20,200}|glimt-[a-zA-Z0-9_-]{20,200}|glsoat-[a-zA-Z0-9_-]{20,200}|glcbt-[a-zA-Z0-9_-]{20,200}|glft-[a-zA-Z0-9_-]{20,200}|glffct-[a-zA-Z0-9_-]{20,200}|glwt-[a-zA-Z0-9_-]{20,200}|dckr_pat_[a-zA-Z0-9_-]{20,200}|nfp_[a-zA-Z0-9]{20,200})
```

## Connection-string variants (apply after the prefix union)

- **URL-form basic auth** (`scheme://user:pass@host`): `(mongodb\+srv://|postgres://|postgresql://|mysql://|mariadb://|mssql://|redis://|rediss://|amqp://|amqps://)[^[:space:]:/@]{1,}:[^[:space:]@]{0,}@`
- **Query-parameter credentials**: `(mongodb\+srv://|postgres://|postgresql://|mysql://|mariadb://|mssql://|redis://|rediss://|amqp://|amqps://)[^[:space:]?#]{0,}[?&](password|passwd)=[^[:space:]&]{1,}`
- **JDBC**: `jdbc:(postgresql|mysql|mariadb|sqlserver|oracle|sqlite):[^[:space:]?#]{0,}[?&](password|passwd)=[^[:space:]&]{1,}`
- **Generic URL-scheme credentials**: `[a-z]{1,20}://[^[:space:]?#]{0,}[?&](password|passwd)=[^[:space:]&]{1,}`

## Quoted-assignment and env-assignment patterns (case-insensitive — `-i` mandatory)

- **Quoted credentials**: `(password|passwd|secret|token|api[_-]?key|apikey|apiKey|client[_-]?secret|clientSecret)[[:space:]]*[:=][[:space:]]*["'][^"']{8,200}`
- **Unquoted env assignments**: `(PASSWORD|PASSWD|SECRET|TOKEN|API[_-]?KEY|APIKEY|CLIENT[_-]?SECRET|CLIENTSECRET|DATABASE_URL|REDIS_URL)[[:space:]]*=[[:space:]]*[^[:space:]"'#]{8,200}` — excludes comments and quoted values already covered by the quoted-credentials pattern.

**Optional left-boundary anchor** (recommended for the env-assignment sub-pattern): prepend `(^|[[:space:]]|[;,])` to avoid matching substrings of longer identifiers. Defaults err on false positives, not false negatives.

## Pre-scan vs post-implementation tier classification

Pre-scan sites (`/jr-review` Phase 1 step 7, `/jr-audit` Phase 1 step 6.5) treat **ALL matches as strict tier** — no advisory demotion. Reasons: (a) the user is reviewing their own changes and false-positive tolerance is lower; (b) in headless mode the user explicitly opted into halt-on-detection.

Post-implementation re-scan sites (`/jr-review` Phase 5.6, Phase 6 regression re-scans, Convergence Phase 5.6, Fresh-eyes) apply the **Advisory-tier classification for re-scans** in `secret-scan-protocols.md`. The deterministic demotion criteria for the high-FP-rate patterns (`SK`, `sk-`, `dapi`) are defined in the next section, **here**. Escalation conditions (assignment context, config/env file) take precedence over demotion.

## Deterministic demotion criteria (`SK`, `sk-`, `dapi`)

**This section is the terminus.** Consumers cite **this section by name**; no consumer defines its own variant. A lead improvising them cannot be deterministic, which is the property the tier depends on.

Applies **only** at post-implementation re-scan sites. Pre-scan sites treat all matches as strict (previous section), so this section never runs there.

A match of `SK[a-fA-F0-9]{32}`, `sk-[a-zA-Z0-9_-]{20,200}` or `dapi[a-fA-F0-9]{32}` demotes to advisory **only when ALL FOUR hold**. Any single failure keeps it strict — the list is conjunctive and fails closed, so an unevaluable criterion is a failure, never a pass.

1. **No assignment context.** Within the 40 characters preceding the match on the same line there is no `=` or `:`, and no identifier containing `key`, `secret`, `token`, `auth`, `pass`, or `cred` (case-insensitive). This is the escalation rule in `secret-scan-protocols.md` ("Escalation overrides demotion") evaluated as a precondition; both spellings must agree, so change them together.
2. **Not a config or environment file.** The containing path does not match `(^|/)\.env` or `\.(env|ini|cfg|conf|toml|properties|yaml|yml)$`, and its basename does not start `config.`, `secrets.` or `credentials.`.
3. **Not a bare quoted literal.** The match is not the entire content of a single- or double-quoted string (`"<match>"` / `'<match>'`), which is the shape a real credential assignment takes.
4. **Positive non-credential signal — at least one of:**
   a. the matched value contains a placeholder token, case-insensitive: `example`, `sample`, `dummy`, `placeholder`, `redacted`, `changeme`, `fake`, `xxxx`, or `test`;
   b. the variable part is a single repeated character, or is strictly ascending or descending hex (`abcdef…`, `fedcba…`);
   c. **`SK`/`dapi` only** — a checksum identifier (`md5`, `hash`, `checksum`, `digest`, `etag`, `sha`) appears within the 40 characters preceding the match, i.e. the 32 hex characters are a digest rather than a credential. Note 32 hex characters is **not** a git object id (SHA-1 is 40, SHA-256 is 64), so do not attempt to resolve one with `git cat-file`.

Criterion 4c is `SK`/`dapi`-only because both are `[a-fA-F0-9]{32}` — exactly MD5 width, which is the entire reason they carry a high false-positive rate. `sk-` is not hex-shaped and has no equivalent benign form, so it demotes only via 4a or 4b.

**Advisory is not dismissal.** A demoted match is still surfaced in the Phase 7 report with file path, line number and pattern type (`secret-scan-protocols.md`, "Never silently dismiss"); demotion changes only whether the run halts.

## Pattern-type enum mapping

When writing `secret-warnings.json` (per `secret-warnings-schema.md`), set `patternType` per the matched sub-pattern. Patterns with no dedicated label fall through to `"other"` and are subject to the `"other"` full-scan fallback in `/jr-review` Phase 7 step 3 (see `jr-review/protocols/secret-warnings-lifecycle.md`).

Dedicated labels: `aws-key` (`AKIA`), `stripe-key` (`sk_live_`/`rk_live_`/`sk_test_`/`rk_test_`), `anthropic-key` (`sk-ant-`), `github-token` (`ghp_`/`gho_`/`ghs_`/`ghu_`/`ghr_`/`github_pat_`), `gitlab-token` (`glpat-`/`gldt-`/`glrt-`/`glrtr-`/`gloas-`/`glptt-`/`glagent-`/`glimt-`/`glsoat-`/`glcbt-`/`glft-`/`glffct-`/`glwt-`), `slack-token` (`xox[bpaes]-`/`xoxe.xox[bp]-`), `private-key-pem` (`BEGIN PRIVATE KEY`), `sendgrid-key` (`SG.`), `google-api-key` (`AIza`), `jwt`, `connection-string-basic-auth`, `connection-string-query-credentials`, `jdbc-credentials`. All others use `"other"`.

## Updating this file

Adding a new prefix pattern requires updating, in order: (1) this file's regex union, (2) this file's "Pattern-type enum mapping" list AND the `"other"`-class list in `jr-review/protocols/secret-warnings-lifecycle.md` ("Pattern-type non-absorption rule"), both of which hand-enumerate prefixes rather than deriving them from the union, (3) `secret-warnings-schema.md` `patternType` enum if a new label is introduced, (4) the consumers (`/jr-review` Phase 1 step 7, `/jr-audit` Phase 1 step 6.5, the pre-commit hook patterns file via `/jr-review`'s install path) by re-reading this file. The hook template SHA-256 is hardcoded; updating the patterns file does NOT change the template hash, so no template-hash bump is required.
