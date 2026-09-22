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
- `GET https://api.anthropic.com/api/oauth/profile` — the only source of
  the plan name (the usage response carries no subscription field):
  `account.has_claude_pro` / `has_claude_max` → "pro"/"max" (max wins).
  The result is cached in the stored credentials (`subscriptionType`) with
  the date it was confirmed (`planCheckedAt`), and re-confirmed once the
  cache is older than `ClaudeProvider.planRecheckInterval` (6 h) — a
  subscription changes whenever the user upgrades, and a cache with no
  expiry kept showing "Pro" forever after a move to Max. A failed profile
  call (or one reporting no subscription at all, which is also what a wire
  shape change would look like) keeps the last known plan rather than
  blanking it. Read-only sources have nowhere to persist `planCheckedAt`,
  so `ClaudeProvider`'s in-memory `PlanCache` holds the resolved plan for
  the life of the provider instance and takes precedence over the CLI
  item's own `subscriptionType`.
- Auth headers on every call: `Authorization: Bearer <token>`,
  `anthropic-beta: oauth-2025-04-20`, and a Claude Code-like
  `User-Agent: claude-code/<version>` — other agents hit an aggressively
  rate-limited bucket (persistent 429s).
- OAuth: PKCE against `https://claude.ai/oauth/authorize` (client ID
  `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, scope `user:profile` **only** —
  the scope `/api/oauth/usage` and `/api/oauth/profile` gate on.
  `user:inference` is deliberately never requested, so a token AIMeter
  mints cannot run inference at all: least privilege for a read-only
  meter, and the line Anthropic's authentication policy draws for
  third-party tools. `ClaudeOAuthTests` pins the scope; the Privacy screen's
  scope chip must match it); the user pastes back `<code>#<state>`
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
  the in-app OAuth flow, or — macOS only — a pasted credentials JSON; the
  iOS build accepts nothing but the OAuth code, see the Connect sheet in
  `AIMeter/CLAUDE.md`) and refreshes it,
  keyed by `ClaudeKeychainCredentialSource.storageKey(for: accountID)`
  (the legacy default key for `"claude"`, `"claude.credentials.<accountID>"`
  for every other account — both the app and the widget extension call
  this same helper so they can never diverge).
- `RefreshService.migrateCredentialsToSharedGroup()` migrates pre-sharing
  credentials into the shared access group once, from `AccountMigration`
  at `UsageModel.init` — unrelated to the per-account keying above, and
  unchanged since before multi-account support.
- Token rotation races: `ClaudeProvider.refreshed` treats a rejected
  refresh as "someone else may have rotated this first" — it re-reads the
  source and, if the stored refresh token differs from the one it sent,
  uses the stored pair (refreshing it in turn if already expired) instead
  of throwing `notAuthenticated`; an unchanged pair is a real rejection.
  The token endpoint's 429 maps to `rateLimited` (refresh and exchange
  alike), never to `notAuthenticated`, which would otherwise trip the
  sign-in-expired alert on a throttle.
- `ClaudeCredentialSource.invalidateCache()` (default no-op) is called by
  the provider on a 401 from a source that can't refresh — i.e. the
  macOS CLI mirror, whose `cachedLocal` copy would otherwise keep serving
  a token Claude Code has since replaced (logout, account switch) until
  it expired on its own.
