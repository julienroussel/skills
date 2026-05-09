# Shared Secret-Pattern Catalog

**Canonical source** for the regex union and per-pattern demotion criteria used by `/review` Phase 1 Track B step 7, `/audit` Phase 1 step 6.5, and the post-implementation re-scans in `/review` Phase 5.6/6 + Convergence Phase 5.6 + Fresh-eyes. The pre-commit hook installed by `/review` reads `.claude/secret-hook-patterns.txt` (not this file directly) — this file is the human-maintained source of truth that `/review`'s install path materializes.

## Portability and evaluation-time safeguards

Apply these BEFORE invoking the regex on any input:

- **POSIX ERE smoke probe** (run once at first-use site): `printf 'foo\n' | grep -E '^f{1,3}o+$' >/dev/null 2>&1`. On failure, abort with `[ABORT — GREP -E INCOMPATIBLE] Detected grep that lacks POSIX ERE quantifier support. Install GNU grep or set GREP=ggrep before re-running.`
- **Per-line length cap (10000 bytes)**: lines exceeding the cap are flagged in the Phase 7 report under `[OVERSIZED LINE — MANUAL REVIEW]` with file path and line number — they are NOT regex-evaluated. Bounds regex evaluation time and prevents pathological backtracking against adversarial long lines.
- **POSIX ERE constraint on every pattern below**: no Perl-style shorthand (`\s`/`\d`/`\w`/`\b`), no Perl-style grouping (`(?:...)`/`(?=...)`/`(?<!...)`). Use POSIX character classes (`[[:space:]]`/`[[:digit:]]`/`[[:alnum:]]`). Non-boundary checks (e.g., the `dapi` prefix check) MUST be implemented as post-match line inspection in the consuming code, NOT as lookbehinds inside the regex.

## Invocation flag

Invoke with `grep -Ei`. The `-i` is mandatory — the case-insensitivity is annotated on the quoted-credential and env-assignment patterns; omitting `-i` produces false negatives on lowercase keys (e.g., `database_url=postgres://...`). Strict-prefixed patterns like `AKIA`/`ghp_` are unaffected because their literal characters don't appear in real secrets recased.

## Token-prefix patterns (regex union)

```
(AKIA[0-9A-Z]{16}|sk_live_[a-zA-Z0-9]{20,200}|rk_live_[a-zA-Z0-9]{20,200}|sk_test_[a-zA-Z0-9]{20,200}|rk_test_[a-zA-Z0-9]{20,200}|sk-ant-[a-zA-Z0-9_-]{20,200}|sk-[a-zA-Z0-9_-]{20,200}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9]{22,200}|xox[bpas]-[a-zA-Z0-9-]{1,200}|-----BEGIN .{0,50} PRIVATE KEY|SG\.[a-zA-Z0-9_-]{1,200}\.[a-zA-Z0-9_-]{1,200}|AIza[0-9A-Za-z_-]{35}|npm_[a-zA-Z0-9]{36}|eyJ[A-Za-z0-9_-]{10,2000}\.eyJ[A-Za-z0-9_-]{10,2000}\.[A-Za-z0-9_-]{10,2000}|AccountKey=[a-zA-Z0-9+/=]{44,200}|SK[a-fA-F0-9]{32}|pypi-[A-Za-z0-9_-]{16,200}|sbp_[a-zA-Z0-9]{20,200}|hvs\.[a-zA-Z0-9_-]{24,200}|dop_v1_[a-zA-Z0-9]{43}|dp\.st\.[a-zA-Z0-9_-]{1,200}|dapi[a-fA-F0-9]{32}|shpat_[a-fA-F0-9]{32}|GOCSPX-[a-zA-Z0-9_-]{28}|https://hooks\.slack\.com/services/T[A-Z0-9]{8,15}/B[A-Z0-9]{8,15}/[a-zA-Z0-9]{24}|https://(discord|discordapp)\.com/api/webhooks/[0-9]{1,25}/[a-zA-Z0-9_-]{1,200}|"private_key":[[:space:]]*"-----BEGIN|vc_[a-zA-Z0-9]{24,200}|glpat-[a-zA-Z0-9_-]{20,200}|dckr_pat_[a-zA-Z0-9_-]{20,200}|nfp_[a-zA-Z0-9]{20,200})
```

## Connection-string variants (apply after the prefix union)

- **URL-form basic auth** (`scheme://user:pass@host`): `(mongodb\+srv://|postgres://|postgresql://|mysql://|mariadb://|mssql://|redis://|rediss://|amqp://|amqps://)[^[:space:]:/@]{1,500}:[^[:space:]@]{0,500}@`
- **Query-parameter credentials**: `(mongodb\+srv://|postgres://|postgresql://|mysql://|mariadb://|mssql://|redis://|rediss://|amqp://|amqps://)[^[:space:]?#]{0,500}[?&](password|passwd)=[^[:space:]&]{1,500}`
- **JDBC**: `jdbc:(postgresql|mysql|mariadb|sqlserver|oracle|sqlite):[^[:space:]?#]{0,500}[?&](password|passwd)=[^[:space:]&]{1,500}`
- **Generic URL-scheme credentials**: `[a-z]{1,20}://[^[:space:]?#]{0,500}[?&](password|passwd)=[^[:space:]&]{1,500}`

## Quoted-assignment and env-assignment patterns (case-insensitive — `-i` mandatory)

- **Quoted credentials**: `(password|passwd|secret|token|api[_-]?key|apikey|apiKey|client[_-]?secret|clientSecret)[[:space:]]*[:=][[:space:]]*["'][^"']{8,200}`
- **Unquoted env assignments**: `(PASSWORD|PASSWD|SECRET|TOKEN|API[_-]?KEY|APIKEY|CLIENT[_-]?SECRET|CLIENTSECRET|DATABASE_URL|REDIS_URL)[[:space:]]*=[[:space:]]*[^[:space:]"'#]{8,200}` — excludes comments and quoted values already covered by the quoted-credentials pattern.

**Optional left-boundary anchor** (recommended for the env-assignment sub-pattern): prepend `(^|[[:space:]]|[;,])` to avoid matching substrings of longer identifiers. Defaults err on false positives, not false negatives.

## Pre-scan vs post-implementation tier classification

Pre-scan sites (`/review` Phase 1 step 7, `/audit` Phase 1 step 6.5) treat **ALL matches as strict tier** — no advisory demotion. Reasons: (a) the user is reviewing their own changes and false-positive tolerance is lower; (b) in headless mode the user explicitly opted into halt-on-detection.

Post-implementation re-scan sites (`/review` Phase 5.6, Phase 6 regression re-scans, Convergence Phase 5.6, Fresh-eyes) apply the **Advisory-tier classification for re-scans** in `secret-scan-protocols.md`. The deterministic demotion criteria for the high-FP-rate patterns (`SK`, `sk-`, `dapi`) are codified there. Escalation conditions (assignment context, config/env file) take precedence over demotion.

## Pattern-type enum mapping

When writing `secret-warnings.json` (per `secret-warnings-schema.md`), set `patternType` per the matched sub-pattern. Patterns with no dedicated label fall through to `"other"` and are subject to the `"other"` full-scan fallback in `/review` Phase 7 step 3 (see `review/protocols/secret-warnings-lifecycle.md`).

Dedicated labels: `aws-key` (`AKIA`), `stripe-key` (`sk_live_`/`rk_live_`/`sk_test_`/`rk_test_`), `anthropic-key` (`sk-ant-`), `github-token` (`ghp_`/`gho_`/`github_pat_`), `slack-token` (`xox[bpas]-`), `pem-private-key` (`BEGIN PRIVATE KEY`), `sendgrid-key` (`SG.`), `google-api-key` (`AIza`), `jwt`, `connection-string-basic-auth`, `connection-string-query-credentials`, `jdbc-credentials`. All others use `"other"`.

## Updating this file

Adding a new prefix pattern requires updating, in order: (1) this file's regex union, (2) `secret-warnings-schema.md` `patternType` enum if a new label is introduced, (3) the consumers (`/review` Phase 1 step 7, `/audit` Phase 1 step 6.5, the pre-commit hook patterns file via `/review`'s install path) by re-reading this file. The hook template SHA-256 is hardcoded; updating the patterns file does NOT change the template hash, so no template-hash bump is required.
