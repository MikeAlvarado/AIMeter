## Data source (Codex) — all isolated in Providers/Codex/

The second provider family (`CodexProvider.providerID` = `"codex"`,
display name "Codex"): a ChatGPT account's Codex limits, read from the
undocumented endpoint the Codex CLI's `/status` and ChatGPT's own usage
page read. Treat as unstable; a server change must only touch these
files. Validate against reality with `Scripts/probe-codex-usage.sh`
(the CLI's login on this Mac, ids redacted, `-o` saves a fixture) before
changing the model. The CLI itself is open source (openai/codex,
`codex-rs/`), which is where every shape below was read from.

- `GET https://chatgpt.com/backend-api/wham/usage` with
  `Authorization: Bearer <access token>`, `ChatGPT-Account-Id: <account
  id>` (the workspace the usage is read for, the way the CLI asks) and
  `Accept: application/json`. The schema is the CLI's own
  (`codex-backend-openapi-models`, `RateLimitStatusPayload`): `plan_type`
  (`free`, `plus`, `pro`, `team`, `business`, `enterprise`, `edu`, …:
  the pill, capitalized), `account_id`, `rate_limit` (`allowed`,
  `limit_reached`, `primary_window`, `secondary_window`), each window
  `used_percent`, `limit_window_seconds`, `reset_after_seconds` and
  `reset_at` (Unix seconds), `additional_rate_limits[]` (`limit_name`,
  `metered_feature`, its own `rate_limit` with two windows:
  GPT-5.3-Codex-Spark), `credits` (`has_credits`, `unlimited`,
  `balance`), `spend_control.individual_limit` (`limit`, `used`,
  `remaining_percent`, `reset_at`; workspaces only), plus `promo`,
  `model_usage`, `rate_limit_reset_credits`, which are not decoded.
- Mapping (`CodexUsageResponse.usageWindows`): the primary window is the
  session when it is at most 24 h long (5 h on paid plans) and the
  overall period when longer, the secondary the week; **Codex Free
  reports one 30-day primary window and no secondary** (measured
  2026-10-20), so a Free account has one `.weekly` window with
  `duration` 2 592 000 s and no session, which the app titles "Monthly"
  and labels "30d". Each additional limit gives one
  `.modelSpecific(limit_name)` from its weekly window (its primary one by
  fallback). `limit_reached` marks its full windows `.exceeded`. A window
  without `used_percent` is skipped, and a secondary window beside a
  long primary (never seen) is keyed `.quota("secondary_window")` so two
  weeklies never collide. `spend_control.individual_limit` maps to
  `SpendStatus` (USD); the credits balance is not shown (there is no
  percentage to draw, and `ExtraUsageStatus` has no balance field).
  `accountIdentity` is `"codex:<account_id>"` (the response's, else the
  credentials'), what iCloud sync keys the history by.
- Statuses: 401 → one refresh for an app-owned source, then
  `notAuthenticated`; 429 → `rateLimited`; anything else `httpError`
  with its body.
- Auth: the CLI's public PKCE client `app_EMoamEEZ73f0CkXaXp7hrann`
  against `https://auth.openai.com`. Tokens are JWTs; the access token's
  `exp` claim is the only expiry (`auth.json` has none; ten days from a
  fresh login, measured) and its `https://api.openai.com/auth` namespace
  carries `chatgpt_account_id` and `chatgpt_plan_type`; nothing else is
  decoded (`JWTClaims`; the email beside them never is). Refresh:
  `POST /oauth/token`, form-encoded `grant_type=refresh_token`,
  `client_id`, `refresh_token` → `access_token`, `refresh_token`
  (rotated: OpenAI's error codes include `refresh_token_reused`),
  `id_token`, `expires_in`. A 400 or a 401 is a rejected login, a 429
  `rateLimited`, anything else `httpError` (`CodexOAuthClient`). The
  same rotation race as Claude's (`ClaudeProvider.rotate`): a rejected
  refresh re-reads the source and uses a pair another process rotated
  (on iOS the widget shares the Keychain item), one more look after
  `rejectionRecheckDelay`.
- Device-code sign-in (`CodexDeviceAuth`, the CLI's
  `codex login --device-auth`, rebuilt from
  `codex-rs/login/src/device_code_auth.rs`; the one ChatGPT login with
  no localhost callback, so it works from a phone): `POST
  /api/accounts/deviceauth/usercode` with JSON `{"client_id"}` →
  `device_auth_id`, `user_code` (`83O4-A9V7A`), `interval` as a
  **string** (`"5"`; a number is accepted too), `expires_at` (15
  minutes); the user enters the code at `https://auth.openai.com/codex/device`;
  `POST /api/accounts/deviceauth/token` with `{device_auth_id,
  user_code}` answers 403 or 404 until approved, then 200 with
  `authorization_code`, `code_challenge`, `code_verifier` (the server
  mints the PKCE pair), exchanged at `/oauth/token`
  (`grant_type=authorization_code`, `redirect_uri=https://auth.openai.com/deviceauth/callback`,
  the verifier) for the tokens. The user has to allow device code login
  in ChatGPT's security settings first; the code request succeeds
  without it and the approval page refuses the code. The usercode call
  was measured live on 2026-10-20.
- Credential sources (per account, see "Accounts vs. providers" in the
  repo-root CLAUDE.md): `CodexKeychainCredentialSource`, the app's own
  copy from the device-code sign-in, key `codex.credentials.<accountID>`
  (no legacy bare key: this family never had a single-account install),
  refreshed in place, the shared access group on iOS so the widget can
  fetch with it; and, macOS only, `CodexFileCredentialSource`, a
  read-only mirror of `$CODEX_HOME/auth.json` (else `~/.codex/auth.json`:
  `{"OPENAI_API_KEY": null, "tokens": {"id_token", "access_token",
  "refresh_token", "account_id"}, "last_refresh"}`, `CodexCredentials.fromAuthJSON`;
  a keyring-stored login is not found, an API-key login is not a login)
  for an `.autoDetected` account. Unlike Claude Code's login it is never
  guessed at launch: the Connect sheet offers "Use Codex's login on this
  Mac" while the file holds one and no account mirrors it
  (`UsageModel.canConnectCodexCLILogin` / `connectCodexCLILogin`). Never
  written, never refreshed (the CLI rotates its own pair when it runs;
  an expired mirror is `tokenExpired`, the "Sign in again" affordance,
  and signing in makes the account `.managed` through `reconnect`),
  `clear()` a no-op (disconnecting never logs the CLI out), and
  disconnecting it never sets `Preferences.autoDetectDeclined`, which
  is Claude's tombstone alone.
- Status page: OpenAI's is an Atlassian Statuspage
  (`CodexProvider.statusSummaryEndpoint`,
  `https://status.openai.com/api/v2/summary.json`, read by the shared
  `StatuspageSource`) whose summary carries **no `incidents` key at
  all** (measured 2026-10-20), so the shared decoder treats
  `incidents`, `scheduled_maintenances` and `components` as optional.
- Fixtures: `Tests/UsageKitTests/Fixtures/codex-usage-response-free.json`
  is a real capture of a Free account (2026-10-20, the probe's `-o`,
  `user_id`/`account_id`/`email`/`campaign_id` redacted);
  `codex-usage-response-plus-synthetic.json` is hand-built on the CLI's
  schema for a paid plan (session, week, one model limit), since no paid
  account was at hand: re-run the probe on one and replace it.
