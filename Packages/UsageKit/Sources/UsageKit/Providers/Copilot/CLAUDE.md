## Data source (GitHub Copilot) — all isolated in Providers/Copilot/

The third provider family (`CopilotProvider.providerID` = `"copilot"`,
display name "GitHub Copilot"): a GitHub account's monthly Copilot
quotas, read from the undocumented endpoint Copilot's editor plug-ins
read. Treat as unstable; a server change must only touch these files.
Validate against reality with `Scripts/probe-copilot-quota.sh` (GitHub's
device flow, which the user completes in the browser; the token never
leaves the shell; ids redacted; `-o` saves a fixture) before changing
the model.

- `GET https://api.github.com/copilot_internal/user` with
  `Authorization: token <GitHub OAuth token>`, `Accept:
  application/json` and a plain `User-Agent`: measured on 2026-10-20,
  the endpoint answers those alone, none of the editor headers the
  plug-ins add (`Editor-Version`, `Copilot-Integration-Id`). Fields read
  (`CopilotQuotaResponse`; everything else is ignored by construction):
  `id` (the GitHub user's numeric id), `copilot_plan`, `access_type_sku`
  (the plan as GitHub bills it: a Free account reports `copilot_plan`
  "individual" beside `access_type_sku` `free_limited_copilot`, so the
  SKU decides the pill: `free` → Free, `pro_plus` → Pro+, `individual`
  → Pro, `business`, `enterprise`; the paid SKUs are community-reported,
  and `copilot_plan` stands in for an unknown SKU), `quota_reset_date`
  (a bare date, midnight UTC on the first of the month; a full
  timestamp is accepted too) and `quota_snapshots`, a dictionary keyed by
  GitHub's quota ids (`premium_interactions`, `chat`, `completions`),
  each with `entitlement`, `remaining`, `percent_remaining`,
  `unlimited`, `has_quota`, `overage_permitted`, `overage_count` (and
  `token_based_billing`, `credits_used`, `quota_reset_at`,
  `timestamp_utc`, not read). The Free capture: chat 200, completions
  2000, and premium requests with `has_quota` false, entitlement 0 and
  `percent_remaining` 0.
- Mapping (`usageWindows`): one `.quota(<id>)` window per snapshot the
  plan meters (`isMetered`: not `unlimited`, `has_quota` not false, an
  entitlement above zero; Free's premium requests fail that and would
  otherwise read "100 % used"), in the order premium requests, chat,
  completions, then any other id by name; its figure from
  `percent_remaining` (else from the counts), its reset the month's, its
  `duration` the length of the calendar month that ends at the reset (so
  the app titles it "Monthly" and labels it "30d"/"31d"), `.exceeded`
  at 100 %. The quota id is what the kind carries, never a display name:
  the app names the three known ids (`UsageWindow.Kind.quotaName`) so
  persistence keys stay the same in every language. Overage is not
  shown. `accountIdentity` is `"copilot:<GitHub user id>"` from the
  answer's `id`, persisted in the credentials (`userID`) once, so it
  outlives a response that ever leaves it out; nothing else is called.
- Statuses: 401 → `notAuthenticated` (a GitHub OAuth token never
  expires on its own; a revoked one is a 401); 429 → `rateLimited`;
  anything else `httpError` with its body (a 403 is an account with no
  Copilot access).
- Auth (`CopilotDeviceAuth`): GitHub's documented OAuth device flow with
  the OAuth App id Copilot's own clients sign in with
  (`Iv1.b507a08c87ecfe98`: VS Code's Copilot, the Copilot CLI, opencode).
  A token minted for a third party's own OAuth App is not accepted by
  the quota endpoint, and there is no public registration for it: the
  same gray zone as Claude Code's client id, taken knowingly. **No scope
  at all** (`CopilotDeviceAuth.scope` is empty; the probe's token came
  back with no scope and the endpoint answered it), so the token reaches
  nothing private on GitHub: `POST https://github.com/login/device/code`
  (form: `client_id`) → `device_code`, `user_code`, `verification_uri`
  (`https://github.com/login/device`), `expires_in` (900), `interval`
  (5); the user enters the code there; `POST https://github.com/login/oauth/access_token`
  (`grant_type=urn:ietf:params:oauth:grant-type:device_code`) answers
  `authorization_pending` (poll again), `slow_down` (with the new
  interval), `expired_token` or `access_denied` (`notAuthenticated`), or
  the `access_token`.
- Credential source: `CopilotKeychainCredentialSource` only, the app's
  own copy, key `copilot.credentials.<accountID>` (the shared access
  group on iOS). No CLI mirror: there is nothing on a Mac to mirror
  that the app could read without a browser's cookies.
- Status page: GitHub's is an Atlassian Statuspage
  (`CopilotProvider.statusSummaryEndpoint`,
  `https://www.githubstatus.com/api/v2/summary.json`, read by the shared
  `StatuspageSource`); its "Copilot" components are the ones that
  matter, and the whole page's indicator is what the banner shows.
- Fixtures: `Tests/UsageKitTests/Fixtures/copilot-quota-response.json`
  is a real capture of a Free account (2026-10-20, the probe's `-o`;
  `login`, `quota_id`s and tracking ids redacted, the numeric `id`
  replaced by 4242). Paid shapes are tested from inline JSON on the
  same schema until a paid account is probed.
