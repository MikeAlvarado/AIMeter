## Data source (Claude) — all isolated in Providers/Claude/

Undocumented endpoints Claude Code uses internally. Treat as unstable; a
server change must only touch these files. Validate against reality with
`Scripts/probe-usage-endpoint.sh` (see `Scripts/sample-response.json` for a
captured response) before changing the model.

- `GET https://api.anthropic.com/api/oauth/usage` — rate-limit windows.
  Modern shape is the `limits` array (kinds: `session`, `weekly_all`,
  `weekly_scoped` + `scope.model.display_name`); top-level `five_hour` /
  `seven_day` objects are a legacy fallback. Also `spend` (amounts in
  `amount_minor` scaled by `exponent`) and `extra_usage` (credits scaled by
  `decimal_places`). `resets_at` is ISO 8601 with fractional seconds, and
  is **null for windows with no usage yet**.
- `GET https://api.anthropic.com/api/oauth/profile` — used once to resolve
  the plan name when credentials lack it: `account.has_claude_pro` /
  `has_claude_max` → "pro"/"max" (max wins). Result is persisted into the
  stored credentials.
- Auth headers on every call: `Authorization: Bearer <token>`,
  `anthropic-beta: oauth-2025-04-20`, and a Claude Code-like
  `User-Agent: claude-code/<version>` — other agents hit an aggressively
  rate-limited bucket (persistent 429s).
- OAuth: PKCE against `https://claude.ai/oauth/authorize` (client ID
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, scope
  `user:profile user:inference`); the user pastes back `<code>#<state>`
  (an empty or malformed paste, e.g. just `"#"`, throws a typed error
  instead of indexing a possibly-empty split result); exchange/refresh at
  `https://console.anthropic.com/v1/oauth/token`.

Credential sources (per account — see "Accounts vs. providers" in the
repo-root CLAUDE.md):
- macOS, the one `.autoDetected` account only: `ClaudeAutoCredentialSource`
  — read-only mirror of Claude Code's own login (Keychain item
  `Claude Code-credentials`, fallback `~/.claude/.credentials.json`); never
  refreshes those tokens (that would log out the CLI). Falls back to the
  app's own Keychain copy if the CLI login isn't found. `UsageModel`
  speculatively tries this account (as accountID `"claude"`) whenever the
  registry is empty, registering it only once a refresh actually confirms
  real credentials — a Mac with no Claude Code login never gets a phantom
  account, and this never adds a second, redundant Keychain-authorization
  probe beyond what that one refresh attempt already does.
- Every `.managed` account (iOS always; macOS for every account past the
  first): `ClaudeKeychainCredentialSource` — the app owns its copy (from
  the in-app OAuth flow, or a pasted credentials JSON) and refreshes it,
  keyed by `ClaudeKeychainCredentialSource.storageKey(for: accountID)`
  (the legacy default key for `"claude"`, `"claude.credentials.<accountID>"`
  for every other account — both the app and the widget extension call
  this same helper so they can never diverge).
- `RefreshService.migrateCredentialsToSharedGroup()` migrates pre-sharing
  credentials into the shared access group once, from `AccountMigration`
  at `UsageModel.init` — unrelated to the per-account keying above, and
  unchanged since before multi-account support.
