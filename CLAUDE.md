# AIMeter

Open source multiplatform app (iOS 17+ / macOS 14+, pure SwiftUI, no
dependencies, no server) that shows AI subscription usage and remaining
limits in the app, in widgets, and in the macOS menu bar. First provider:
Claude Pro/Max. The architecture is provider-agnostic so more AI providers
(Codex, Cursor, …) can be added as new sections later, and multi-account:
several logins of the same provider (e.g. two Claude accounts) can be
connected and refreshed simultaneously — see "Accounts vs. providers" below.

This file is the complete spec: product, data source, architecture, design
system, and behaviors. It should be enough to rebuild the app from zero.

## Identifiers

- Bundle ID: `com.mikealvarado.aimeter`
- Widget extension: `com.mikealvarado.aimeter.widgets`
- App Group: `group.com.mikealvarado.aimeter` — must match exactly in both
  targets' entitlements and `Shared/AppConfig.swift`. On iOS it doubles as
  the **keychain access group** so the widget can read credentials — this
  needs BOTH the `com.apple.security.application-groups` entitlement AND a
  `keychain-access-groups` entitlement (`$(AppIdentifierPrefix)` + the same
  group string) in both targets. The App Group entitlement alone only
  shares `UserDefaults`/files, not Keychain items — a common trap, since it
  builds and even codesigns fine without the Keychain entitlement; it only
  fails at runtime on a real device (the Simulator is lenient about it).
- Background task ID: `com.mikealvarado.aimeter.refresh`
- macOS update check (`NSBackgroundActivityScheduler`):
  `com.mikealvarado.aimeter.updates.activity` (`AppUpdater.activityID`)
- Widget kinds: `AIMeterUsage` ("Usage Limits": the account's windows,
  rows in the small family, columns with a big figure each in the medium),
  `AIMeterSingleUsage` (single-window widget, user-configurable via
  WidgetKit's `AppIntentConfiguration`), and `AIMeterAllAccounts`
  (`.systemLarge`-only, every connected account at once, no per-instance
  configuration — see `AIMeterWidgets/CLAUDE.md`).

## Layout of the repo

Both app targets sync the `Shared/` folder; the widget target also gets its
assets and string catalog from there.

- `AIMeter/Services/` — `UsageModel` is split by feature into
  `UsageModel.swift` (state, loading, the refresh path),
  `UsageModel+Connections.swift` (connect/reconnect/disconnect, demo mode,
  the macOS redetect), `UsageModel+Naming.swift` (order and nicknames),
  `UsageModel+Notifications.swift` (the per-account toggles),
  `UsageModel+ServiceStatus.swift` (the provider's status page check, see
  "Service status" below), `UsageModel+History.swift` (the chart's
  in-memory timeline cache) and
  `UsageModel+macOS.swift` (refresh schedule, wake/activation observers,
  `AppEnvironment`); members those extensions share are internal rather
  than private, by necessity, and documented as such. Notifications are
  three files: `NotificationPreferences.swift` (the toggles, plus
  `SmartAlert` — the five per-account families addressed as one enum, so
  the model and the toggles card have one getter/setter pair instead of
  five), `NotificationScheduler.swift` (the fetch-driven families) and
  `NotificationScheduler+Peak.swift`.
- `AIMeter/Services/ClaudeCodeUsageModel.swift` (macOS) — Claude Code's
  local token usage on this Mac, see "Claude Code local usage" below;
  its views are `AIMeter/Views/ClaudeCodeUsageCard.swift` (the Dashboard
  section: invitation or summary) and `ClaudeCodeUsageView.swift` (the
  detail). The reading itself is UsageKit's
  `Providers/Claude/ClaudeCode/` (pricing table, line parser,
  incremental reader, aggregates).
- `AIMeter/Services/ClaudeSessions/` (macOS): Claude Code's sessions in
  the notch island, see "Claude Code sessions" below.
  `ClaudeSessionMonitor` (the observable state the island reads),
  `DemoSessions` (what it reads instead in demo mode),
  `ClaudeSessionLogWatcher` (FSEvents on `~/.claude/projects`, reading
  only the bytes added), `ClaudeHookListener` (the hooks' Unix socket)
  and `ClaudeCodeHooks` (the one-click install into
  `~/.claude/settings.json`); the rules are UsageKit's
  `Providers/Claude/ClaudeCode/ClaudeCodeSession.swift` (the record and
  hook-event shapes) and `ClaudeCodeSessionTracker.swift`. The views:
  `AIMeter/Views/NotchIsland/NotchIslandSessions.swift` (what sits
  beside the notch), `NotchIslandSessionRows.swift` (the expanded
  island's rows, the hooks invitation), `PixelPetView.swift` (the pets,
  their "!" and their group) and `NotchIslandController+Clearance.swift`
  (where the menu bar's own items are) over
  `Shared/NotchIslandModel+Sessions.swift`,
  `Shared/NotchIslandClearance.swift` and the pets themselves,
  `Shared/SessionPet.swift` (identity, the deal, the clock) and
  `SessionPet+Sprites.swift` (the hand-drawn pixels), all pure and
  tested, and `AIMeter/Views/ClaudeSessionsSettings.swift` (the
  "Sessions" card of Settings' Claude Code tab).
- `AIMeter/Views/` — Provider Detail is `ProviderDetailView.swift` plus
  `ProviderDetailCards.swift` (Peak, Forecast, raw detail rows and their
  row builders, `ProviderDetailRows`), `HistoryCard.swift` (the Swift
  Charts history card and the Dashboard row's `Sparkline`) and
  `NotificationTogglesCards.swift` (both notification cards). The Dashboard is `DashboardView.swift` plus
  `DashboardView+Reorder.swift` (the hold-and-drag reorder, whose state
  stays on the view — internal `@State`, for the same reason as above) and
  `RoundIconButton.swift`. The macOS status item is `MenuBarLabel.swift`
  (the view, the drawn bar/battery glyphs, and `MenuBarLabelModel.current`)
  over `Shared/MenuBarLabelModel.swift` (the pure model: text, fill, tint,
  accessibility — the part that is unit-tested); its Settings tab is
  `MenuBarSettings.swift`. The macOS Settings window is
  `MacSettingsView.swift` (the tabs, and the trailing-switch toggle style)
  over `SettingsSections.swift` (one view per section, shared with the iOS
  sheet's `SettingsView`) and `MacChromeSettings.swift` (the Hiding and
  Startup sections of its General tab). The
  macOS notch island is `AIMeter/Views/NotchIsland/`:
  `NotchIslandController.swift` (lifecycle, the interaction's timers
  and monitors, the reveal), `NotchIslandController+Screen.swift`
  (which display, the fixed panel frame, the observers) and
  `NotchIslandController+Pointer.swift` (a screen without a notch:
  pointer tracking, concealment, the full-screen check, capture
  exclusion, the preferences observation; the controller's members
  these two reach are internal, not private, by necessity),
  `NotchIslandPanel.swift` (the `NSPanel` and the hosting view that
  confines hit-testing to the slab), `NotchShape.swift` (the eared
  silhouette with animatable radii and `NotchIslandSurface`, the black
  stack the content is drawn on), `NotchIslandView.swift` (the root: the
  slab as the natural size of its content, the springs and transitions,
  `NotchIslandModel.current`), `NotchIslandCollapsedRow.swift` (the wings
  and the segment line), `NotchWings.swift` (the `notchCenter` alignment
  guide and `NotchWings`, the layout that keeps the wings centered on the
  notch),
  `NotchIslandRows.swift` (expanded content: account rows, footer),
  `NotchIslandSessions.swift`, `NotchIslandSessionRows.swift` and
  `NotchIslandController+Clearance.swift` (Claude Code's sessions, see
  below) and
  `NotchIslandSettings.swift` (its two Settings cards) — over the four
  pure files in `Shared/`
  (`NotchIslandModel.swift`, `NotchIslandGeometry.swift`,
  `NotchIslandInteraction.swift`, `NotchIslandVisibility.swift`, all
  unit-tested), see "Notch island" under "Presentation rules".
  `AIMeter/Views/PrimaryAccountPicker.swift` is the "Account" menu both
  the Menu bar and the Notch island cards show with two or more
  accounts.
- `AIMeter/Intents/` — the App Intents (`RefreshUsageIntent`,
  `ShowUsageIntent`, `AIMeterShortcuts`), both platforms; see
  "Conventions" for why they exist.
- `Shared/` — `PeakBadge.swift` is the one peak glyph every glance surface
  composes (menu bar popover, both widget headers, the all-accounts
  widget, the Live Activity); `ServiceStatusBanner.swift` is the one
  incident notice (dashboard, menu bar popover); `UsageRecorder.swift` is
  the one call that writes a persisted snapshot into both history stores;
  `HistoryChartData.swift` shapes a timeline into what the chart and the
  sparkline draw (pure, tested); `PreferencesModel.swift` (the
  observable wrapper, split from `PreferencesStore.swift`, the value
  type) keeps a single stored `Preferences` value behind computed
  accessors, so the field list exists once; `MetricChips.swift` is the
  1–3 window chip row the menu bar's
  `multi` style and the notch island's wings both configure with.
- Updates and What's new (see "Updates (macOS) and What's new" below):
  `AIMeter/WhatsNew.json` (each release's notes, eight languages) read
  by `AIMeter/Services/WhatsNew.swift`, drawn by
  `AIMeter/Views/WhatsNewView.swift`; `AIMeter/Services/AppVersion.swift`
  compares versions; the Mac's updater is `AIMeter/Services/Updates/`
  (`AppUpdater`, the state and schedule; `UpdateFeed`, GitHub's release;
  `UpdateInstaller`, download, checks and the swap) with its window,
  Settings section and notices in `AIMeter/Views/UpdateViews.swift`.
- The tour (see "Tour" below): `AIMeter/Services/Tour.swift` (the
  features, the steps, who is due, what an update still offers) over
  `AIMeter/Views/Tour/`: `TourView.swift` (the steps, and the feature
  card the notes reuse), `TourActions.swift` (each feature's button,
  whether it is on, whether it applies here), `TourText.swift` (the
  words), `TourVisuals.swift` and `TourVisuals+Mac.swift` (the
  animations, drawn from the app's own pieces) and
  `TourPresentation.swift` (the Mac's window, the iOS cover, Settings'
  row).

## Architecture rules (non-negotiable)

- `Packages/UsageKit` must NOT import SwiftUI, WidgetKit, UIKit, or Combine.
- Providers implement `UsageProvider`:
  `func fetchUsage() async throws -> UsageSnapshot`.
- `UsageSnapshot` holds `[UsageWindow]` plus optional `spend: SpendStatus`
  and `extraUsage: ExtraUsageStatus`. `UsageWindow.kind` is extensible:
  `.session`, `.weekly`, `.modelSpecific(String)`, and `.credits` — the
  last one is a display-only pseudo-window the Shared presentation layer
  synthesizes from `spend` (`UsageSnapshot.creditsWindow`); provider
  mapping code never produces it and it's never part of a persisted
  snapshot's `windows`. Widgets and views render whatever windows a
  snapshot contains; provider names are never hardcoded in rendering logic.
- **Provider seam** (what a second provider plugs into): every provider
  family is resolved through `Shared/ProviderCatalog.swift` —
  `displayName(for:)` (the plain-text name, never a logo), the
  `legacyAccount` sentinel every widget fallback uses,
  `fallbackAccount(for:)` (what the widget's self-fetch builds for an id
  the registry can't place: that id's own login, never the legacy
  account's — whose figures would otherwise be saved under the wrong
  account), and
  `makeProvider(for:keychain:transport:)`, the one switch on
  `providerID` that builds a `UsageProvider` plus the `CredentialStore`
  to clear on disconnect, and `statusSource(for:)` /
  `statusPageURL(for:)`, which resolve the family's public status page
  (`ServiceStatusSource`, UsageKit core) or nil for a provider without
  one — the app then simply shows no status for it. `RefreshService` holds only those two
  existentials and never names a provider; `WidgetRefresher` builds its
  self-fetch provider through the same catalog. The literal `"claude"`
  lives in `ClaudeProvider.providerID` (with `providerDisplayName`) and
  nowhere else; `ProviderCatalog.defaultProviderID` is what a new
  connection belongs to until there is a picker. `CredentialStore`
  (UsageKit core — `clear()`, `invalidateCache()`) is the
  provider-agnostic half of `ClaudeCredentialSource`, which refines it
  with the typed `load`/`save`; `RefreshService.storeConnection` is the
  one deliberately Claude-typed member (the credentials from the OAuth
  exchange are), and a second provider adds its own connect path beside
  it rather than generalizing it. Window lengths come from the window,
  not the kind: `UsageWindow.duration` is set by the provider's mapping
  (Claude states 5 h / 7 d on every window) and `effectiveDuration` is
  what pace and run-out math read, falling back to `Kind.windowDuration`'s
  Claude-shaped default only for windows saved before the field existed —
  a provider whose week is a month sets `duration` instead of needing a
  new `Kind`. Peak hours stay Claude's: `ClaudePeakStatus.forProvider`
  reports off-peak for any other family, so its bolt never appears on
  another provider's account. Still Claude-shaped, deliberately, until a
  second provider exists to design against: `WindowSlots`' three-slot
  layout and the credits fallback, `ConnectClaudeSheet` as the only
  connect flow (no provider picker on "Add account"), and
  `CredentialStrategy.autoDetected`, which is Claude Code's semantics.
- **Accounts vs. providers**: `providerID` (`UsageProvider.id`,
  `UsageSnapshot.providerID`) identifies a provider *family* — `"claude"` —
  and never changes per login; `accountID` identifies one specific
  connected login of that family and is a storage/orchestration concept
  that lives *outside* UsageKit's `Core/` — `UsageProvider`, `UsageSnapshot`,
  and `ClaudeProvider` carry no account identity and don't need to, since
  the caller (the app, a widget) always already knows which account it
  asked for. `AccountRegistryStore` (`Packages/UsageKit/Storage/`) is the
  App Group-shared, **order-significant** list of connected
  `ConnectedAccount`s — its order *is* display order for every surface
  (dashboard, macOS menu bar popover, all-accounts widget, widget account
  pickers), which is what makes the dashboard's drag-reorder one
  `replaceAll` write rather than a per-surface preference (accountID,
  providerID, a user-editable `displayName` (set in the Connect sheet,
  renamed in place any time later — `UsageModel.rename` — and unique across
  accounts, case-insensitively, since it's all that tells them apart in
  widget pickers and notification titles; see `AIMeter/CLAUDE.md` →
  "Renaming"), and `credentialStrategy`:
  `.managed` for an app-owned Keychain copy from OAuth/paste, or macOS-only
  `.autoDetected` for the one login mirrored from Claude Code's own
  Keychain item — capped at exactly one account, since the CLI itself only
  ever tracks one login per machine; every other account, on either
  platform, is `.managed`). Only the app ever writes to the registry
  (`add`/`rename`/`remove`/`replaceAll`/`setCredentialStrategy`); the widget
  extension only reads
  (`accounts()`/`account(for:)`) — same "only the app writes" invariant
  `SnapshotStore` already had. `credentialStrategy` is mutable after the
  fact for exactly one transition (`setCredentialStrategy`): macOS's
  `.autoDetected` → `.managed`, when a CLI-mirrored login stops working and
  the user signs in through the app instead — see "Losing a login" below. A pre-multi-account
  install's one account is migrated in place as the literal accountID
  `"claude"` (not a fresh UUID) by `AccountMigration`, so its existing
  Keychain item, `SnapshotStore`/`UsageHistoryStore` entries, and any
  already-placed widget survive the upgrade with zero rewrite — new
  accounts (2nd+, or the 1st on a clean post-feature install) get
  `UUID().uuidString`.
- App ↔ widget data flows only through the App Group `SnapshotStore`
  (JSON-encoded snapshot per `accountID`, not `providerID` — two accounts
  of the same provider would otherwise collide on one key). Widgets render
  the last snapshot for whichever account their `AppIntentConfiguration`
  selection points at; on iOS the widget may fetch for itself when that
  account's snapshot is older than the refresh cadence (credentials via
  the shared keychain access group, keyed the same way —
  `ClaudeKeychainCredentialSource.storageKey(for:)`), writing the result
  back to the store. On macOS the menu bar app feeds the widget (a
  sandboxed widget can't read Claude Code's credential file). The widget
  target is sandboxed on macOS (`ENABLE_APP_SANDBOX[sdk=macosx*] = YES`,
  the app itself is not): the plug-in daemon loads no app extension
  without the sandbox entitlement — every Mac build before 2.0.0's
  release was refused with "plug-ins must be sandboxed", so no Mac
  widget ever appeared — and `pluginkit -m -i
  com.mikealvarado.aimeter.widgets` is the check that it registered.
- macOS widget freshness contract: both widgets appear in Notification
  Center / the desktop automatically — WidgetKit discovery, nothing to
  register — but on macOS they only ever render what the app last wrote.
  The timeline still re-runs on schedule with the app closed; it just
  re-serves the same snapshot, indefinitely and with no error state. The
  only signal is the `isStale` (>30 min) "updated X ago" hint in the widget
  header. That is precisely why the app is built to keep running while
  hidden: a quit app doesn't break the widget visibly, it just quietly
  freezes it.
- OAuth tokens live in the Keychain only (shared access group on iOS,
  `kSecAttrAccessibleAfterFirstUnlock`). Never UserDefaults, never in git.
- Typed errors (`UsageError`) carry the raw HTTP body so the UI can show
  exactly what the endpoint said; UI decides presentation.

Undocumented-endpoint specifics (exact URLs, headers, OAuth flow,
credential sources) live in
`Packages/UsageKit/Sources/UsageKit/Providers/Claude/CLAUDE.md` — loaded
automatically when working in that directory.

## Data-shaping rules (applied at fetch time, in this order)

1. Map `limits` → windows; unknown kinds are skipped (forward-compatible).
2. Scoped weekly windows share the weekly window's exact `resetsAt` (the
   endpoint reports microsecond-apart timestamps for what is one boundary).
3. `fillingMissingResets(from: previousSnapshot)` — weekly windows whose
   `resetsAt` came back null inherit the previous date advanced in whole
   7-day periods (weekly boundaries are fixed anchors, so this is truth,
   not a guess). Sessions only carry a still-future date: an idle session
   genuinely has no reset. Reported dates are never overwritten.

## Losing a login (and getting it back)

A stored login can stop working for good — Anthropic rotates the refresh
token on every use, so any other client refreshing the *same* login (Claude
Code on another machine, or — macOS only, the iOS build has no such path —
a second Mac the same credentials JSON was pasted into) leaves AIMeter's
copy invalid; a password change or global sign-out does the same. From then on every refresh fails identically and
the account silently freezes at its last snapshot.

- `UsageError.requiresReauthentication` marks the three failures no retry
  can fix (`notAuthenticated`, `tokenExpired`, `credentialsNotFound`);
  `UsageModel.AccountUsage.needsReauthentication` carries it to the UI,
  which swaps the raw endpoint message for a "Sign in again" prompt
  (`UsageStatusFooter(reauthenticate:)`). Raw bodies are still shown for
  every other error — see the typed-errors rule above; this is the one case
  where the raw text ("The provider rejected the credentials") is faithful
  and useless at the same time.
- A rejected refresh is not taken at face value: `ClaudeProvider.refreshed`
  re-reads the credential source and, if the stored pair differs from the
  one just rejected, uses that instead. The two processes that share a
  Keychain item on iOS (app and widget) both refresh on foreground when
  the snapshot is stale, and Anthropic rotates on every use, so the loser
  of that race would otherwise announce a broken login that the winner
  just rotated fine. Only a rejection of the pair the store still holds
  is a real `notAuthenticated`; a 429 from the token endpoint is
  `rateLimited`, never a dead login.
- Recovery is **reconnect in place** (`UsageModel.reconnect(accountID:credentials:)`),
  never disconnect-then-add: the accountID is the key for the stored
  snapshot, usage history (and its pace warm-up anchor), notification
  preferences, Live Activity toggle, and the account selection baked into
  every already-placed widget. A new UUID orphans all of it, so the
  Connect sheet's `reconnecting:` mode writes fresh credentials to the
  *existing* account's Keychain key and changes nothing else.
- A macOS `.autoDetected` account that reconnects becomes `.managed`: the
  in-app OAuth exchange mints a token pair the app owns, so it both stops
  deferring to a CLI login that just proved unusable and ends the rotation
  standoff — AIMeter can refresh its own pair without invalidating Claude
  Code's. The registry flip is written only *after* the new credentials
  are stored: the other order, with a failed save in between, leaves a
  `.managed` account with nothing at its key — a permanent
  `credentialsNotFound` card.
- The `planName` write-back in `ClaudeProvider` re-reads the credential
  source before saving instead of persisting the value the fetch started
  with. It only owns `subscriptionType` and `planCheckedAt`; saving the
  whole stale value could put an already-consumed refresh token back over a
  freshly rotated one — one of the ways an account breaks like this in the
  first place, since the iOS widget refreshes against the same shared
  Keychain item as the app.
- The plan name is the one part of a snapshot that isn't re-derived from
  the usage response on every fetch — that response carries no subscription
  field, so the name comes from `/api/oauth/profile` and is cached in the
  credentials. It therefore needs an expiry of its own: `planCheckedAt`
  stamps each confirmation and `ClaudeProvider.planRecheckInterval` (6 h)
  bounds how long it's trusted, so a Pro → Max upgrade reaches the plan
  pill (dashboard, menu bar, landscape, all-accounts widget — all of them
  read `UsageSnapshot.planName`) instead of showing the plan the account
  had at sign-in forever. Details in the Claude provider's own CLAUDE.md.

## Refresh & notification behavior

- `RefreshService` is scoped to one `ConnectedAccount`
  (`init(account:)`) — `UsageModel` holds one instance per registered
  account (`private var services: [String: RefreshService]`) plus
  `accounts: [AccountUsage]` (account + its own snapshot/error/isRefreshing).
  `RefreshService.refresh()`: fetch → shape → save to store (keyed by that
  account's `accountID`) → record history → sync the Live Activity →
  reschedule that account's notifications (resets + run-outs) → fire any
  of that account's early-reset alerts. The widget reload is deliberately
  *not* in there: `UsageModel.fetch(accountID:)` (private) wraps one
  account's refresh and reports whether a snapshot landed, and each public
  entry point — `refresh(accountID:)`, `refreshAll()`,
  `refreshAllIfStale()`, `refreshAllInBackground()` — calls
  `WidgetCenter.reloadAllTimelines()` **once** if any did, because every
  reload draws on WidgetKit's per-kind budget (see "Widget timeline"
  below) and N accounts would otherwise spend it N times per sweep.
  `UsageModel.refreshAll()` fans this
  out to every account concurrently via `withTaskGroup` — safe, since each
  account uses a different bearer token (no shared rate-limit bucket) and
  `UsageModel` is `@MainActor`-isolated, so the per-account bookkeeping
  each task does on completion is serialized even though the network
  requests themselves run in parallel. `refresh(accountID:)` refreshes just
  one (Provider Detail's own pull-to-refresh, one account at a time).
- **Service status** (`UsageModel+ServiceStatus.swift`): every sweep
  (`refreshAll`, `refreshAllIfStale`, `refresh(accountID:)`) also asks
  each connected provider *family*'s status page for its health — once per
  family, never per account, concurrently with the fetches and never
  blocking them, and at most every 5 minutes
  (`serviceStatusMinimumInterval`). Claude's is the Atlassian Statuspage
  at status.claude.com (`ClaudeStatusSource`, `summary.json`; shape and
  fixtures in the Claude provider's CLAUDE.md). The result is a
  `ServiceStatus` per `providerID` (`UsageModel.serviceStatus`, persisted
  in the App Group through `ServiceStatusStore` so a relaunch shows the
  last confirmed state until the first check lands). The rule is that
  nothing is ever announced that wasn't confirmed: a failed or
  unparseable check is `unknown`, treated exactly like operational; a
  last-known status outlives failing checks for 30 minutes
  (`serviceStatusMaxAge`) and is then dropped rather than asserted
  stale. `Preferences.checksServiceStatus` (default **on**, presence-
  checked like the other true-default bools; Settings → "Service
  status") turns the check off and clears what's shown immediately —
  Settings mirrors it into `UsageModel.checksServiceStatus` through
  `setChecksServiceStatus`, so the model never reads the App Group
  directly (the tests drive it with an injected `ServiceStatusSource`).
  Demo mode never checks and never shows one. Not in the widget
  extension or the iOS background task: there is no surface for it
  there, and a stale status in a widget would be worse than none.
- Disconnect cascades (`RefreshService.disconnect()` from
  `UsageModel.disconnect(accountID:)`): credentials, stored snapshot, both
  usage histories (`UsageRecorder.clear` — the predictor's series and the
  chart's timeline file), every notification still pending or delivered for that account
  (`NotificationScheduler.removeAll(accountID:)` — a queued `reset.` would
  otherwise fire at its `resetsAt` for an account that no longer exists),
  and its per-account preference keys (`NotificationPreferences.clear()`,
  `LiveActivityPreferences.clear()`), so a UUID's worth of keys doesn't
  leak into the App Group forever. On macOS, disconnecting the
  `.autoDetected` account also sets `Preferences.autoDetectDeclined`:
  disconnecting only clears the app's fallback copy, the CLI's own
  Keychain item is untouched, and without the tombstone `loadAccounts()`
  would speculatively re-mirror it on the next launch — the account the
  user just removed would quietly come back. The disconnected Dashboard
  card offers "Use Claude Code's login instead"
  (`UsageModel.redetectClaudeCodeLogin`) to clear it.
- Migration: `AccountMigration.run(registry:)`, called once from
  `UsageModel.init` before accounts are loaded. Each step gates itself
  independently (not one shared "migrated" flag), so a crash between steps
  can never skip a later step on the next launch: (1) registers the legacy
  account as `ConnectedAccount(accountID: "claude", …)` if the app's own
  Keychain already has credentials at the default key (the `.autoDetected`
  macOS case is handled separately and lazily — see credential sources
  above, to avoid a redundant Keychain-authorization probe); (2) copies
  the pre-multi-account flat notification-preference keys (`notify.session`,
  `notify.runout`, …) to their new `"claude"`-scoped equivalents so an
  upgrading user's toggles aren't silently reset. Old keys are never
  deleted — they're just inert once migrated.
- iOS app: `refreshAll()` on cold launch; on foreground, always reload
  widget timelines (covers WidgetKit's archived-render cache after app
  updates) and `refreshAllIfStale()` (each account whose own snapshot is
  >60 s old, independently); `BGAppRefreshTask` at the user-selected
  cadence (30 min / 1 h / 3 h, `RefreshCadence`) as a best-effort backstop
  — `UsageModel.refreshAllInBackground()` is a standalone static path for
  this (the background task context has no live `UsageModel` instance to
  reuse), reading the registry and fanning out concurrently the same way.
- macOS: `NSBackgroundActivityScheduler` (`UsageModel.rebuildRefreshSchedule`)
  at the cadence, with a 20 % tolerance, for as long as the app runs — which
  now includes running with no visible icons at all. Deliberately *not* a
  run-loop `Timer`: an app with no visible window is a prime App Nap
  target, and Nap throttles timers unpredictably. Nothing fires while the
  Mac sleeps, so `NSWorkspace.didWakeNotification` nudges
  `refreshAllIfStale(maxAge: cadence)` on wake — a no-op for any account
  whose snapshot is still fresh, a catch-up fetch for the rest.
- Widget timeline: single entry, `.after(interval)` where `interval =
  max(displayCadence, AppConfig.widgetRefreshFloor)` (30 min). The widget's
  reload interval is deliberately floored *independent of* the user's
  display cadence: WidgetKit budgets background refreshes (~a few dozen a
  day), so requesting every 15 min exhausts the budget and the system
  stops refreshing that widget — and then ignores even app-initiated
  `reloadAllTimelines()` until the budget replenishes (this is per widget
  *kind*, which is why a heavily-refreshed medium widget can freeze while
  the single-usage widget stays live). Multiple accounts sharpen this: each
  placed widget instance draws from the same per-*kind* budget regardless
  of which account it's configured for, so N accounts × M widgets divides
  one shared allowance — a known tradeoff, not something fixed in code.
  The app's foreground push covers freshness during active use. On iOS
  `getTimeline` self-fetches for that instance's own configured account
  when its stored snapshot is older than that interval, via a short-timeout
  (`timeoutIntervalForRequest = 15`, `waitsForConnectivity = false`)
  URLSession so a slow request fails fast instead of wasting the refresh.
- Usage history: two stores, written together by `UsageRecorder.record`
  wherever a fetch persists a snapshot (the app refresh *and* the iOS
  widget self-fetch, so both stay continuous when only the widget runs)
  and cleared together on disconnect.
  `UsageHistoryStore` (App Group `UserDefaults`, keyed by `accountID`)
  keeps a bounded, reset-aware ring of `(timestamp, usedPct)` samples per
  window — the extra data (beyond the single latest snapshot) the
  recent-rate run-out predictor needs; a used%-drop discards a kind's
  prior samples so a rate never spans a reset. That reset-awareness is
  exactly why it can't feed a chart, so `UsageTimelineStore` (a JSON file
  per account in the App Group container, `usage-timeline/<accountID>.json`)
  keeps the long, reset-*preserving* series of `TimelineSample`s
  (`timestamp`, `usedPct`, `resetsAt`) per window: raw for 48 hours, one
  sample per hour (the hour's highest) before that, nothing past 30 days
  (`UsageTimeline.compacted`, applied on every write — tens of KB per
  account). Resets are derived at read time, never stored:
  `UsageTimeline.isReset` says a sample starts a new window when its
  `resetsAt` moved later by more than a minute (weekly boundaries are
  fixed anchors) or its figure fell by the same 10-point threshold the
  predictor uses. Writes are atomic; the app and the widget may both
  append, and a rarely lost sample is accepted over a lock. Both stores
  keep one sample per refresh: on iOS the app and its widget both fetch
  when the app comes forward and each records what it got, often within
  the same second (which the file's whole-second dates make identical),
  so a sample within `UsageTimeline.sameRefreshWindow` (60 s) of the last
  replaces it (`UsageTimeline.appending`; `UsageHistoryStore.record` does
  the same for the predictor's ring), and `UsageTimeline.deduplicated`
  applies the rule at read time to files written before it. The app reads
  the file once per account into `UsageModel.timelines`
  (`UsageModel+History.swift`), reloaded after each successful fetch and
  on each foreground sweep (the widget may have appended), so the
  Dashboard's sparklines never read a file inside a body evaluation. Each
  account's `observingSince` (the pace warm-up anchor) is independent, so
  an account added later starts its own warm-up clock rather than
  inheriting an existing account's history.
- Notifications are local only, keyed by identifier prefix + `accountID`
  (`NotificationScheduler`, e.g. `reset.<accountID>.<kind>`) so two
  accounts sharing a window kind never clobber each other's pending
  requests — the one deliberate exception is `peak.`, which stays
  account-independent (see below). Five families are rescheduled/
  re-evaluated from scratch after every successful fetch, scoped to just
  that fetch's account; two more sit outside that sweep — `peak.` (see
  "Peak hours" below — retired today, so the family only clears its own
  stale pending requests), which depends only on a fixed weekday schedule
  and never on what a fetch returns, so it's rescheduled once at
  `UsageModel.init` and whenever its toggle changes instead, and `reauth.`,
  which fires from the *failure* path rather than a successful fetch. Two
  of the five fetch-driven families are *scheduled* to a future trigger:
  `reset.` (per-window `UNCalendarNotificationTrigger` at each window's
  `resetsAt`, the free baseline, per-window opt-in toggles) and `runout.`
  (per-window run-out warnings fired a lead time before a projected early
  exhaustion — recent-rate projection when history exists, else
  average-rate). Three are *immediate, detection-based* (nil trigger,
  fired when comparing the previous stored snapshot to the new one, so
  they can't be scheduled — the trigger level/time isn't known ahead):
  `earlyreset.` (`ResetDetector` — a window refilled before its scheduled
  reset), `limitreached.` (`ThresholdDetector.crossedUp` at ~100%, message
  adapts to whether `spend.enabled` — "draws on credits" vs "blocked until
  reset"), and `nearlimit.` (`crossedUp` at the user's threshold, a
  slider; a single big jump that also hits the limit yields only the more
  severe limit-reached, not both). All fire once per upward crossing (not
  on every refresh while above) and re-arm after a reset. `reauth.` is
  immediate too, but fired from the *failure* path rather than from a
  snapshot comparison: `RefreshService.refresh` posts it when the fetch
  throws `notAuthenticated` (see "Losing a login" above) — deliberately
  narrower than `requiresReauthentication`, since `tokenExpired` on macOS
  usually just means Claude Code hasn't rotated its own token yet, and
  `credentialsNotFound` is also what the speculative macOS auto-detect
  candidate throws before being dropped. It dedupes through
  `reauthAlertDelivered` (fires once per breakage, not once per refresh
  cycle forever) and is cleared — pending flag and delivered notification
  alike — by the next successful fetch or a reconnect. Each `smart`
  alert has its own toggle **per account** (near-limit adds a per-account
  threshold) — `NotificationPreferences(accountID:)`, so muting a
  secondary account never touches another's; `peak.` is the one alert
  family with a single toggle shared by every account (`UsageModel`'s
  dedicated `peakPreferences`, constructed with a documented placeholder
  accountID since `peakEnabled` never actually reads it), since it's one
  Claude-wide policy, not tied to a specific login — the toggle is hidden
  while no schedule is in force. All off by default;
  toggles live in the App Group — except `reauthAlertsEnabled`, the one
  family that defaults to **on**: the other five announce usage the user
  can always go look at, while this one announces that AIMeter has stopped
  being able to look at all, and silence there is indistinguishable from
  "nothing changed". (On by default never means a surprise prompt — like
  every family it only delivers if permission was already granted — and a
  `true` default must load through a presence check, same trap as
  `Preferences.bool(_:_:default:)`.) Once more than one account is connected,
  a notification's title is prefixed with that account's nickname (e.g.
  "Work: Session limit reset"); a single-account install's copy reads
  exactly as it always has. A rename re-issues that account's pending
  `reset.`/`runout.` requests from the stored snapshot
  (`RefreshService.rescheduleNotifications`, no fetch) so titles already
  queued don't keep the old nickname until the next refresh; connecting a
  second account or disconnecting back to one does the same for every
  *other* account (`UsageModel.relabelPendingNotifications`), since the
  prefix rule flips at exactly that crossing. Permission is
  a single OS-level toggle, not
  per account: it's handled honestly regardless of which account's card
  changed it — a denied system permission snaps every account's toggle
  back off and shows a warning row with an "Open Settings" shortcut;
  authorization is re-checked on foreground — iOS via `scenePhase == .active`
  (`ContentView`), macOS via `NSApplication.didBecomeActiveNotification`
  (`UsageModel.observeActivation()`, registered once from `init` alongside
  `observeWake()`) — both exist for the same reason: the user may have just
  come back from flipping the OS toggle in Settings. Detection-based alerts share
  the widget-self-fetch gap noted for history — a crossing the widget
  applies before the app refreshes is missed, and the same goes for
  `reauth.`: `WidgetRefresher` swallows its fetch errors (`try?`), so a
  broken login is announced by the app's own next refresh or its
  `BGAppRefreshTask`, not by the widget that hit it first. Cancelled URL tasks are not
  surfaced as errors.

## Updates (macOS) and What's new

- **What's new** (both platforms): each release's notes live in
  `AIMeter/WhatsNew.json`, a resource rather than catalog strings, every
  item (an SF Symbol, a title, a line or two of detail, optionally
  `platforms: ["macOS"]` or `["iOS"]`) written in all eight languages
  and never with an em dash (`WhatsNewTests` holds both;
  `Scripts/release-mac.sh` refuses a version without its entry or whose
  `MARKETING_VERSION` differs). `WhatsNew.dueAtLaunch()` decides, once
  per launch: notes newer than `pref.whatsNewSeenVersion` (App Group) up
  to the running version, newest first, skipped versions' notes added
  up; with no version recorded yet, a fresh install shows nothing and
  an install that already has accounts (an upgrade from before this
  existed) gets this version's notes; nothing to show records the
  version at once. iOS presents them as a sheet on the Dashboard
  (`ContentView`) after the App Store update; the Mac in its update
  window. Text follows the app's own language
  (`Bundle.main.preferredLocalizations`), then the language without its
  region, then English. An item may name a tour feature (`feature`, a
  `TourFeature` raw value, checked by `WhatsNewTests`): it then carries
  that feature's card under its text (`TourFeatureCard`, its animation
  and the button that turns it on, or "On"), for the features that
  apply here and were off when the notes opened, or that only explain
  (the colors). The Mac's notice before an update installs shows no
  cards (the running version can't turn on what only the next one has).
- **Tour** (both platforms, `Tour`): a fresh install (no account in the
  registry and `pref.tourCompleted` unset) opens with the full tour
  instead of any notes: one step at a time, each an animation of the
  feature drawn from the app's own pieces (its bars and colors, a
  widget, a notification, the island, the pets), a title and a line, a
  button that turns it on the way its Settings switch does (asking for
  the permission where one is needed, never anything a switch couldn't
  undo) with "Not now" beside it, or "On" (a login item still waiting
  for approval says so, with the way to the pane) and "Continue"; "Skip
  tour" leaves at any step, and dots count the steps. The Mac's steps
  are the welcome, the notch island, Claude Code's sessions (the
  hooks), the session's name with the menu bar clearance (the
  Accessibility permission), notifications, Open at Login and
  connecting; iOS's the welcome, how to add a widget, notifications and
  connecting. A step that can't show here is passed over as the tour
  runs (`TourActions.applies`): the two Claude Code steps while the
  island is off or where Claude Code has never run (its logs folder
  doesn't exist; installing the hooks there would create its folder).
  Connecting comes last, opening the Dashboard's Connect sheet once the
  tour has closed (the Mac through `AppChrome.connect`, iOS through
  `.tourConnectRequest`); with an account already there (demo mode's
  included, the way "Add account" hides there) the step reads
  "Connected". Finishing, skipping or closing it sets
  `pref.tourCompleted`, counts its features as offered
  (`pref.tourOfferedFeatures`) and this version's notes as read. The
  Mac shows it in its own window (`AIMeterApp.tourWindowID`, opened at
  launch by `AppDelegate` through `AppChrome.openTourWindow`, the
  update window's bridge), iOS as a full-screen cover from
  `ContentView`; Settings → "Show the tour" (General on the Mac) opens
  it again, on iOS once the Settings sheet is gone
  (`Tour.deliverPendingShow`). After an update installed from the Mac's
  notice, whose notes were read before the restart, the update window
  opens once with "Turn on what's new": the features this version's
  notes name that apply here, are still off and were never offered
  (`Tour.pendingOffers`), each with its card.
- **Updates (macOS only; the iOS build has none of it)**: `AppUpdater`
  checks a minute after launch and then once a day
  (`NSBackgroundActivityScheduler`, 2 h tolerance) while
  `Preferences.checksForUpdates` is on (default **on**,
  presence-checked; Settings → General → "Updates", which also has
  "Check Now" and the state; "Check for Updates…" in the app menu does
  the same and opens the update window). The feed is GitHub's
  `releases/latest` for this repository (`UpdateFeed`; no server of
  ours, the same release the site's Download button points at): a
  release is an offer only when it is not a draft or pre-release, its
  tag is a version newer than the running one, and it has
  `AIMeter-macOS.zip`. `UpdateInstaller.prepare` downloads that zip to
  `~/Library/Caches/com.mikealvarado.aimeter/Updates/<version>/`, checks
  its SHA-256 against the asset's `digest`, unpacks it with `ditto`,
  and keeps it only if the app inside is validly signed, Apple-anchored,
  this bundle ID and the same team as the running app (nested code
  included), and carries exactly the offered version. An unsigned build
  has no team to hold a download to, so it never updates
  (`AppUpdater.isAvailable`). A ready update raises one notification
  (`update.<version>`; `NotificationRouter`, the app's only
  `UNUserNotificationCenter` delegate, opens the update window on a
  click and lets just that notification show while the app is in
  front) and the `UpdateReadyNotice` at the top of the menu bar popover
  and the Dashboard, plus an icon beside Settings in the notch island's
  footer. Nothing installs until "Restart to Update" in the update
  window (the new version's notes, from the downloaded app's own
  `WhatsNew.json`): a shell script that outlives the app waits for it to
  quit, sets the running copy aside, moves the new one into its place
  (putting the old one back if that fails), deletes the previous
  version and the download, and opens the new one; the notes are marked
  seen first, so they don't show again after the restart. "Later"
  closes the window; the notices stay, and the notification comes back a
  day later. A copy that can't be replaced where it is (translocated, or
  in a folder this user can't write) opens the release page instead.
  Each launch removes whatever a past update left behind. `DEBUG` only:
  `-AIMeterUpdateFeed <url>` points the check at another feed (a
  `file://` JSON shaped like GitHub's) to try the whole path without a
  release.

## Presentation rules

- Session and weekly slots are always present (`WindowSlots`); a missing
  window keeps its slot (`--` + empty bar). The third slot shows the
  real per-model window when the plan reports one (e.g. Max/Team
  Premium's Fable 5 allowance). When it doesn't — most Claude Pro accounts,
  since Fable moved to usage credits — `ModelSlotFallback` (Provider
  Detail → "Third usage row": Auto/Hidden/Credits, default Auto) decides:
  `.hidden` drops the slot (two rows total), `.credits` keeps three rows
  and fills it with a synthesized `.credits` window from `spend` instead
  of a dead placeholder, `.auto` picks between those two on its own —
  showing the credits row exactly when `spend.enabled` is true, hiding it
  otherwise, no manual choice needed. The credits row's notification
  toggle is always disabled (no reset date to schedule against).
- Reset lines: consecutive windows sharing one reset date show
  "Resets in …" once, under the last of the group (`WindowSlots.showsReset`)
  — applies to dashboard, detail, menu bar, widgets, landscape: every
  surface that stacks the windows. The one surface that doesn't, the
  medium widget's side-by-side columns, shows each column's own line
  (see `AIMeterWidgets/CLAUDE.md`). Credits has
  no reset date, so `showCreditsAmount` (off by default, Provider Detail)
  optionally fills that same line with `SpendStatus.amountLabel`
  ("$14.27 of $25.00") instead of leaving it blank.
- Pace: `PaceCalculator.pace(for:now:)` (UsageKit core, pure, no history)
  compares a window's used% against where a steady burn to `resetsAt`
  would put it — `expectedPct` (0–100) plus on/ahead/behind `status`
  within a ±5 pt tolerance. Needs `resetsAt` and the kind's
  `windowDuration` (session 5h, weekly/model 7d, credits none — distinct
  from `nominalPeriod`), so idle sessions and credits have no pace. It
  renders as a per-row status caption ("On pace"/"Ahead of pace"/"Behind
  pace", `UsagePace.Status.label`) alongside the reset line — only on the
  Claude detail screen (`WindowRowsList(showsPace:)`, true just there; the
  dashboard, menu bar, and landscape leave it off to keep the glance
  clean), and never as a bar marker or in widgets. Pace is per-window
  (each window's own used% vs the same expected line), so — unlike the
  grouped reset line — every row shows its own.
- Pace warm-up: pace and the forecast are withheld until the account has
  been observed long enough to trust them — `PaceCalculator.isReady`
  against `UsageHistoryStore.observingSince` (set on the first fetch, kept
  across resets, cleared on disconnect) vs `warmupDuration` (~4 session
  cycles, 20h). Until ready (`UsageModel.paceReady`), rows drop the pace
  caption and the Forecast card shows a "Learning your pace…" state instead
  of asserting on/ahead/behind from too little history.
- Run-out prediction (the other half of "predictions & pace"):
  `RunOutPredictor` projects when a window hits 100% two ways (the "hybrid"
  model). `averageProjection` uses the average rate since the window began
  — stable, works from a single snapshot, no history — and drives the
  Provider Detail **Forecast** card (per-window "Runs out ~1h early", or an
  all-clear row). `recentProjection` fits the recent slope of the
  `UsageHistoryStore` samples — reactive to a burst — and drives the
  run-out *alert* (falling back to average when history is thin). Both
  suppress under `alertMinimumUsedPct` and when the trend isn't rising.
  `ResetDetector.earlyResets` compares consecutive snapshots for an early
  refill (used% dropped well before the known reset) to fire the
  early-reset alert.
- History (Provider Detail → "History", `HistoryCard`): the % of limit
  used over time for one of the account's reported windows (window and
  24 h / 7 days / 30 days pills), from `HistoryChartData` over the
  timeline above — one Swift Charts area + line per window segment, so
  the curve breaks at a reset instead of drawing a cliff (the areas
  `stacking: .unstacked`, here and in the sparkline: Swift Charts stacks
  areas that share an x by default, so one refresh recorded twice drew a
  thin spike to twice the figure), a dashed rule at
  each reset (only up to `HistoryChartData.maxResetRules`, 12, in range —
  a week of sessions would otherwise hatch the chart), and a faint dashed line at 85 % (the same threshold that
  turns a bar red, `UsageLevel.dangerAbove`; the curve itself stays one color). Y is fixed 0–100 and
  labeled "% of limit" in the footnote — the data is never tokens.
  Until the range holds two samples an hour apart the card shows
  "Recording since …" instead of asserting a shape from one point. The
  chart is one VoiceOver element with a spoken summary
  (`HistoryChartData.summary`: span, peak, resets). The Dashboard's usage
  rows carry a 56×16 pt `Sparkline` of the same 24-hour data before the
  percentage, only once three points exist, decorative and in the
  secondary color — drawn as one continuous line with a faint fill rather
  than one segment per window (a session's sawtooth split at every reset
  rendered as hatch marks at that size) (`WindowRowsList(showsSparklines:)`, true only from the
  Dashboard — the popover, landscape, detail and widget rows don't). Demo
  mode draws from `DemoUsageData.timeline(for:)`, thirty fabricated days
  ending exactly on that demo account's snapshot figures (the demo has
  two accounts, see `AIMeter/CLAUDE.md` → "Demo mode").
- Claude Code local usage (macOS, **opt-in**, off by default —
  `Preferences.claudeCodeUsageEnabled`): what Claude Code's sessions on
  this Mac would have cost at API list prices, from the JSONL logs the
  CLI keeps in `~/.claude/projects` (format and fixtures in the Claude
  provider's CLAUDE.md; `Scripts/probe-claude-code-logs.sh` prints the
  shape, never content). It is a property of the *machine*, not of a
  connected account — the CLI's login may or may not be one of them — so
  it has its own Dashboard section ("Claude Code on this Mac",
  `ClaudeCodeSection`): while off, an invitation card (only if the logs
  folder exists, and until "Not now" sets the
  `claudeCodeUsageDismissed` tombstone); while on, Today / Last 7 days /
  Last 30 days rows ("1.2M tokens · ≈ $4.10" — rolling windows, not
  calendar week/month, so the rows nest and never read smaller going
  down; see `ClaudeCodeUsageAggregate.last(days:)`) pushing `ClaudeCodeUsageView`
  (bucket pill incl. All time, token breakdown, per-model rows, Rescan,
  and the honesty footnote: list prices as of
  `ClaudeModelPricing.lastVerified`, "your subscription already covers
  this — it is not a bill", the folder read, and — when Claude Code's own
  `cost-state` totals exist for fully-priced sessions — how far the table
  is from them, the early warning that the table went stale). Settings →
  "Claude Code" holds the toggle (and "Show today's total in the menu
  bar", one `Claude Code today: 300K · ≈ $2.00` line under the popover's
  accounts); Privacy & data has its row. `UsageModel.claudeCode` owns
  the model and rescans it on every refresh sweep while enabled; off
  clears what's shown *and* deletes the reader's index. In demo mode the
  section shows `DemoUsageData.codingSessions` — fabricated, nesting
  aggregates with neutral model names ("Top model", "Everyday model",
  "Fast model") under the neutral title "Coding sessions on this Mac",
  no Rescan, a "Sample data" footnote — so screenshots can show the
  feature without a third-party product name; the Settings card and the
  popover line stay out of the demo. Rules: only the usage fields are decoded (the `Decodable`s
  declare nothing else — content is never read, by construction); the
  reader is incremental by file **size** and byte offset, never by
  modification date (a required-reason API); duplicates are the norm
  (streaming writes one message as several identical lines — dedupe by
  `message.id` + `requestId`); `cost-state` is cumulative per session
  (last record wins) and carries no time, so the buckets come from
  per-message tokens × the pricing table and `cost-state` is the
  cross-check; an unknown model shows tokens and no cost, and makes the
  bucket's cost a lower bound ("> $…"). The pricing table is hardcoded
  and release-updated like `ClaudePeakSchedule` was — no server, not
  user-editable — and verifying it against the pricing page is part of
  every release. iOS: nothing, deliberately (no logs there, and the iOS
  build never reads another app's files).
- Claude Code sessions (macOS, **on by default** with the island,
  `Preferences.claudeSessionsEnabled`): which of this Mac's Claude Code
  sessions are working, waiting for a permission prompt or just
  finished, shown by the notch island. Every Claude Code client on the
  Mac (the desktop app, a second copy of it, the CLI) writes its
  sessions to the same `~/.claude/projects`, so one watcher sees them
  all, any number at once. Two sources feed UsageKit's pure
  `ClaudeCodeSessionTracker`:
  - **The logs, always** (`ClaudeSessionLogWatcher`): FSEvents says
    which files changed and only the bytes added since the last read
    are parsed, keyed by size and offset like the usage reader, never
    by modification date. A file seen for the first time is read from
    its last 256 KB and, for a session's own log, further back (4× at a
    time, up to 16 MB) until it holds the previous turn's end
    (`ClaudeCodeSessionRecord.endsTurn`): a session already at work when
    AIMeter launched otherwise counted its time from wherever the window
    began (measured: "Working for 3m" on a 189 MB log whose turn had
    started 15 minutes before). A session's own `<id>.jsonl` is read before its
    subagents' (`<id>/subagents/agent-<agent>.jsonl`, workflow agents a
    level deeper; a workflow's `journal.jsonl` is nobody's). Only the
    record's shape is decoded (`ClaudeCodeSessionRecord`: type,
    subtype, time, ids, stop reason, the *types* of the content items,
    whether it has a prompt source, and the title records), so no
    prompt, reply or tool input is ever read; the shapes are in the
    Claude provider's CLAUDE.md. A turn starts with a prompt or tool
    traffic and ends with a reply whose stop reason ends it, the
    `stop_hook_summary` / `turn_duration` record, an API error, or the
    interruption marker. A subagent's records only keep its parent
    working. A record older than the newest one that decided a
    session's state never changes it (another file read late, or the
    log catching up with a hook).
  - **The hooks, once installed** (`ClaudeCodeHooks`; one click in the
    island or in Settings, and "Remove" takes exactly them out again):
    six events (`UserPromptSubmit`, `PermissionRequest`, `Notification`,
    `Stop`, `StopFailure`, `SessionEnd`) each get one `async` command
    (Claude Code never waits for it) that posts the event's JSON with
    `/usr/bin/curl` to `~/Library/Application Support/AIMeter/claude-hooks.sock`,
    only while that socket exists, and always exits 0.
    `ClaudeHookListener`, an `NWListener` on that Unix socket (nothing
    listens on the network, and only this user can connect), decodes
    the event's name, session, folder, agent and notification kind and
    nothing else. The hooks add what the log can't say: a permission
    prompt (`PermissionRequest`, open until the agent that asked writes
    its log again, so another subagent's work never clears it) and a
    turn's start and end the moment they happen. Hooks never see a user
    interrupt (`Stop` doesn't fire for one), so the log's marker stays
    the authority there. The install keeps every other key and hook in
    `~/.claude/settings.json`, backs the file up first
    (`settings.json.aimeter-backup`), refuses a file that isn't valid
    JSON, replaces an older AIMeter entry instead of doubling it, and
    writes through a file created with the original's permissions that
    then takes its name (Claude Code keeps it `600`, and it may hold
    secrets; a plain atomic write recreated it world-readable). Remove,
    when nothing else changed since the install, puts the backed-up
    file back byte for byte and deletes the backup; otherwise it takes
    out just AIMeter's entries. Running sessions pick either change up
    without a restart (Claude Code watches its settings); with AIMeter
    gone the entries do nothing.
  What shows: collapsed on a real notch, the island reads the way Vibe
  Island's compact island does (`SessionWings`): the lead session (the
  one waiting for a permission prompt if any, so it is never left in the
  count, else the newest at work) on the notch's left, with the second
  of three beside it, and on its right the other pets (three in all at
  most, `PetGroup`) and a small badge counting every session they stand
  for: a short island. "Show the session's name"
  (`claudeSessionsShowsName`, off by default) puts the lead's whole name
  beside its pet instead, the other pets moving to the right; it makes
  the island far wider, since both sides keep one width. The name is cut
  short past 170 pt and the peek's "Working for 3m" past 150 pt: the
  panel is sized once for wings up to `NotchIslandGeometry.maxWing`
  (240 pt), and a wider slab is clipped at the window's edge and loses
  its rounded corners (it did, with a long title and a 220 pt cap).
  A drawn notch or the pill has no notch to keep clear and a panel sized
  for its widest row (`NotchIslandGeometry.maxDrawnRow`), so there the
  name runs to `drawnNameWidth` (320 pt, about fifty characters, larger
  with a taller island): on a wide screen a session's whole title shows.
  Collapsed, the name also takes only the room the menu bar leaves
  (`NotchIslandClearance`, `NotchIslandState.availableWing`) with "Avoid
  covering the menu bar" on (`claudeSessionsAvoidsMenus`, off by
  default), which asks for the Accessibility permission: the open app's
  menu titles on the left and the status items on the right, both from
  the Accessibility API (the app's menu bar, and every app's "extras"
  bar), since macOS shows another app's menus to nothing else and, on
  macOS 27, `MenuBarAgent` draws every status item, so the public window
  list carries none of them (measured: only the agent's bar at level 24
  and a zero-size window per app). Level-25 windows in that list, where
  status items lived before, still count with no permission. Only those
  frames are ever read, on a queue of their own (the first read of an
  app takes tens of milliseconds, 1.5 s for every app running here,
  later ones a few for all of them), on every relocation, after an app
  switch, launch or quit, and every 20 s while the permission path runs,
  then asking only the apps found with status items, since an item that
  changes width (a temperature, a battery's percentage) moves every item
  left of it (`NotchIslandController+Clearance.swift`). On a screen
  without a notch that room is measured from the line down its centre,
  which the drawn row is centred on (`NotchIslandClearance.anchor`), and
  the name gets what the rest of the row leaves of it (`NamedRowLayout`).
  With less than 48 pt left for it, the island
  drops the name and is the short one. The peek is not limited: the
  pointer is on it. Both sides are as wide as each other, each
  one's content at its outer end (`NotchWings`), so the island stays
  centered on the notch. Nothing at all shows when no session is
  active. A pet (`SessionPet`) is one of six creatures drawn by hand on
  a 12 × 10 grid (drop, ghost, cat, bunny, frog, fox), in one of six
  colors (no yellow and no red, which already mean a permission prompt
  and a limit in the island), with one of six accessories fitted to it
  (none, sunglasses, top hat, beanie, bow, headphones): 216
  combinations, the one a session's id points at through FNV-1a (the
  same on every launch, unlike `hashValue`), dealt so no two sessions on
  screen share one. It walks in place while its session works, shakes
  beside a yellow "!" while it waits for permission (beside it, never
  above its head, so it stays inside the bar) and sleeps under a
  blinking "z" for 8 s after the turn ends
  (`ClaudeSessionMonitor.finishedMarkDuration`). `PixelPetView` paints
  `SessionPet.pixels` on a shared 8 Hz clock (a `TimelineView`, so it
  runs only while a pet is shown; still under Reduce Motion), its
  canvas in two thirds of the bar on whole device pixels
  (`SessionPet.pixelSize(beside:)`: 1.5 pt on a MacBook's 32 pt notch,
  the body half the bar's height, as on the mockup the pets were
  approved on), the body rather than the canvas centered on its row
  (`SessionPet.bodyLift`: the hat's headroom is all above the body),
  with air on both sides (12 pt from the slab's ear, 10 from the notch)
  and a soft glow in its own color, like Vibe Island's pets. With "A
  pet for each session" off (`claudeSessionsPets`, on by default) the
  pets' place holds a spinner (the `rays` symbol under a repeating
  variable-color effect in the labels' white, since the system's
  progress indicator reads a dim gray on black), a yellow alert or a
  check. On a real notch the peek is dynamic, one thing or the other
  and never both: with a session at work it shows that session in full
  (its pet and name stay where they were, name shown or not, and what
  it is doing, "Working for 3m" or "Needs permission" in yellow, joins
  the count on the right), and only with none does it show the usage
  figures. Whatever changes fades out before the new fades in
  (`AnyTransition.notchSwap`). The drawn notch and the pill, which have
  no hover swap, keep the pets and the count at the two ends of their
  row; with the session's name, the row reads like the notch's: the
  lead's pet and name first, the figures where the notch would be, the
  other pets and the count last. Expanded, the header carries the
  figures alone: each pet shows once, in its session's row.
  Expanded, under the accounts, a "Claude Code" section lists up to
  five sessions, each with its pet (the title, else the folder; the
  folder after a title) and "Working for 3m", "Needs permission" or
  "Done 2m ago": active
  ones first by the start of their turn, then those that finished in
  the last ten minutes. A "working" session silent for 30 minutes is
  dropped as a crash. While the hooks aren't installed the section ends
  with a one-line invitation (Install, or "Not now":
  `claudeSessionsHooksDismissed`). An optional "needs you" notification
  (`claudeSessionsNotify`, off by default, `claudesession.`
  identifiers, "Notify when a session needs you") asks for the
  permission when switched on and fires once each time a session starts
  waiting for a permission prompt, which only the hooks can tell (its
  caption says so while they aren't installed); a turn ending is never
  announced, since a notification for every turn was noise (Mike's call,
  2026-10-15: notify only when a session needs something). The notice is
  taken back once the prompt is answered or the session ends
  (`ClaudeSessionMonitor.newlyAsking` / `noLongerAsking`, tested), and a
  starting monitor clears what a previous run left delivered. The monitor
  runs while the island shows sessions or that notification is on
  (`AppChrome.updateClaudeSessions`), never under XCTest. Demo mode
  never shows a real session (its captures come from the demo): the
  island shows the demo's own instead (`DemoSessions`, dealt from
  `DemoUsageData.claudeSessions` each time the demo starts), four with
  neutral titles and folders whose ids are picked for their pets (a fox
  in sunglasses waiting for a permission prompt, a cat in headphones and
  a bunny with a bow at work, a ghost in a beanie done), under the
  neutral title "Coding sessions on this Mac" and with no hooks
  invitation.
  iOS: nothing, impossible by construction (no Claude Code there, and an
  iOS app can't read another app's files).
- Peak hours — **retired** (`ClaudePeakSchedule.current` is nil since
  2026-09-22). Anthropic introduced a policy in March 2026 where Claude
  Code session usage on Pro and Max burned faster 5-11 AM PT on weekdays,
  and announced its removal on 2026-05-06 ("removing the peak hours limit
  reduction on Claude Code for Pro and Max accounts",
  anthropic.com/news/higher-limits-spacex). No Anthropic help page — Pro,
  Max, Team, or "Usage limit best practices" — has described a peak window
  for any plan since, and Team/Enterprise never had one documented. The
  schedule's 2026-08-03 re-verification rested on a scheduler warning, not
  documentation, and that day's captures found no server-side signal
  either. That absence of a signal is the crux: `docs/design/peak-hours-investigation.md`
  confirms empirically — by diffing a live response captured inside the
  window against one captured outside it — that neither `/api/oauth/usage`
  nor `/api/oauth/profile` carries any peak-related field, so the app can
  never notice on its own that the policy stopped applying, and a
  hardcoded schedule silently keeps announcing "Peak hours now" every
  weekday morning to users whose limits no longer change. Showing nothing
  beats that, so the schedule is nil rather than re-dated.
  - What stays, so a return is a one-line change (assign a re-verified
    `ClaudePeakSchedule.lastKnown` to `current`): `PeakCalculator`
    (UsageKit core, pure — `isPeak(at:schedule:)` /
    `nextTransition(after:schedule:)`, provider-agnostic; the concrete
    PT/weekday/5-11 values are Claude's own policy and live in
    `ClaudePeakSchedule` alongside a `lastVerified` date, the honesty
    mechanism for a policy known to change, surfaced in the UI so a stale
    schedule is never presented as live truth), `ClaudePeakStatus`
    (Shared/, wraps the calculator with the copy shared by every surface —
    with a nil schedule it reports off-peak with no next transition, which
    is what hides every badge without each surface checking the schedule
    itself), the badge views in the menu bar popover, both widget headers,
    and the Live Activity, the widget timelines' extra `TimelineEntry` at
    `nextTransition` (skipped while nil), and the off-by-default `peak.`
    notification family (`NotificationScheduler.reschedulePeakNotifications`,
    10 recurring `UNCalendarNotificationTrigger`s pinned to the schedule's
    zone; while nil it only removes pending `peak.` requests, so an install
    upgrading with the toggle on stops getting alerts — and both its
    Settings toggle and Provider Detail's "Peak hours" card are gated on a
    non-nil schedule, so neither renders today). Deliberately hardcoded
    and release-updated rather than remote-fetched (this project has no
    server, by design) or user-editable (most users can't verify a schedule
    they'd hand-edit).
  - The named-timezone rule is load-bearing: `PeakCalculator` evaluates
    weekday/hour through `TimeZone(identifier: "America/Los_Angeles")` —
    never `TimeZone.current` — so the result is identical regardless of
    the device's own timezone, and DST is handled for free (a named zone
    carries its own historical/future transition rules; a fixed UTC
    offset would silently break twice a year). `PeakCalculatorTests`
    checks both DST transition dates and an explicit
    device-timezone-independence case.
  - Surface rules, for when it returns: Provider Detail shows a dedicated
    card; the macOS menu bar popover header shows a bolt badge, while the
    status item itself (`MenuBarLabel`) folds peak into the
    tooltip/accessibility text only, not a second glyph; both widgets
    (`AIMeterUsage` header, `AIMeterSingleUsage` header when the picked
    window is `.session`) show the same badge, flipped by WidgetKit at the
    transition entry with no extra refresh; Lock Screen accessories don't
    (too cramped). `peak.` is deliberately **not** part of the "reschedule
    every fetch" convention: the schedule never depends on a fetched
    snapshot, so `UsageModel` reschedules it once at init and whenever the
    toggle changes.
- Display prefs (App Group, shared with widgets): Remaining/Used,
  Relative/Absolute reset style (tap any reset line to toggle), appearance
  System/Light/Dark, usage colors (`usageColors`, see "Design system"),
  refresh cadence, and `glanceMetric`
  (widgets read all of these straight from the App Group when they
  render, but nothing re-renders them until their next timeline reload,
  so `PreferencesModel` reloads timelines once per burst of changes to a
  widget-visible pref — `widgetsChanged()`, coalesced over 0.5 s — rather
  than leaving a Remaining/Used flip to wait for the next fetch) — the one window
  shown by the two single-number surfaces with no room for a fixed
  three-slot layout: the macOS menu bar label and iOS's Lock Screen
  circular gauge. One shared preference still drives both, unchanged by
  multi-account — each surface separately supplies *which account* to
  read it against: on iOS every Lock Screen accessory is its own
  `AppIntentConfiguration` instance (`AIMeterUsage`, same as the Home
  Screen widgets), so it already carries its own account selection and
  just applies the shared `glanceMetric` to that account's snapshot; macOS
  has no per-instance mechanism (`MenuBarExtra` is a single scene), so a
  new paired preference, `primaryAccountID` (`Shared/PreferencesStore.swift`,
  Settings → the "Account" menu, `PrimaryAccountPicker`, in both the Menu
  bar and the Notch island cards), picks which account the one status
  item — and the notch island's wings — represent
  (`UsageModel.primaryAccountUsage(preferredID:)`, falling back
  to the first connected account when unset or stale). It is a labeled
  menu, like "Style", because the unlabeled row of account segments it
  replaced sat above the equally unlabeled window segments and read as
  one more window picker. Both pickers moved
  out of Claude's Provider Detail and into Settings' Menu bar and Notch
  island tabs — with
  several accounts there's no longer one unambiguous account whose detail
  screen could own "which window does the menu bar read"; iOS keeps its
  equivalent "Lock Screen widget" pill in Provider Detail, since that one
  is still meaningfully per-account (which window *of this account* the
  gauge reads). `glanceMetric` is stored as a plain `UsageWindow.Kind` (not
  a fixed enum) so its option list scales with whichever account it's
  being read against: Session and Weekly always, the per-model window
  (e.g. Fable on Max) whenever that account reports one, and Credits
  whenever it has that enabled *and* `modelSlotFallback` isn't Hidden
  (`UsageSnapshot.glanceOptions`) — 2 to 4 choices, same live-options
  principle `UsageWindowOptionQuery` uses for the single-window widget.
  `modelSlotFallback` and `showCreditsAmount` themselves stay **global**
  (one shared value for every account, not re-keyed per account) — a
  deliberate scope simplification, not an oversight: re-scoping them would
  also mean threading an account identity through every widget rendering
  path that reads them, for a cosmetic edge case (two accounts wanting
  different third-row fallback behavior) that hasn't come up.
- Claude Code prefs (App Group, macOS-only meaning): `claudeCodeUsageEnabled`
  (default **false**), `claudeCodeUsageDismissed` (default false),
  `menuBarShowsClaudeCodeLine` (default false) — see "Claude Code local
  usage" above; and `claudeSessionsEnabled` (default **true**,
  presence-checked), `claudeSessionsPets` (default **true**,
  presence-checked), `claudeSessionsShowsName` (default false),
  `claudeSessionsAvoidsMenus` (default false),
  `claudeSessionsNotify` (default false) and
  `claudeSessionsHooksDismissed` (default false), whose keys and loading
  live in `Shared/PreferencesStore+ClaudeSessions.swift` — see "Claude
  Code sessions" above.
- Notch island prefs (same App Group store, macOS-only meaning):
  `notchIslandEnabled` (the struct's default is **false**; the real
  default is written once, at the first launch of 2.0, by
  `AccountMigration.migrateNotchIslandIfNeeded(defaults:hasNotch:)`,
  gated on `notchIslandMigrated`: **true on a Mac with a notch, false on
  one without** — a drawn notch replacing a quiet status item on an
  iMac is not an upgrade anyone asked for, so it stays opt-in there),
  `notchIslandLayout` (`NotchIslandLayout`: `bothSides` default,
  `leftOnly`, `rightOnly` — which wings open beside the notch on the
  peek and head the expanded island; collapsed is always the bare notch;
  a drawn notch or pill has no sides and shows its one row whenever it
  is not concealed), `notchIslandMetrics` (`[UsageWindow.Kind]`,
  default session + weekly, stored by storage key like `menuBarMetrics`),
  `notchIslandExpandsOnHover` ("Peek on hover", default **true**,
  presence-checked; off, only a click opens it — the collapsed island
  is invisible on a real notch, so turning this off means knowing where
  to click; a *concealed* drawn island instead shows its row while the
  pointer is on its place, since it has nothing to click otherwise),
  `notchIslandMigrated` (the gate above), `notchIslandRevealed` (the
  first-run reveal has been shown) and `notchIslandDiscovered` (the user
  has opened the island once); `notchIslandHoverDelay` (the peek's
  dwell in seconds, default 0.25, clamped to 0–1 —
  `NotchIslandInteraction.dwellRange`) and `notchIslandHiddenFromCapture`
  (default false: `NSWindow.sharingType = .none`, verified on macOS 27
  against both `screencapture` and a ScreenCaptureKit frame, with a
  control capture showing the island when off), on every screen; and,
  for a screen **without** a notch only, `notchIslandForm`
  (`NotchIslandForm`: `notch` default — drawn, fused to the top edge —
  or `pill`), `notchIslandHeightMode` (`menuBar` default, or `custom`)
  with `notchIslandCustomHeight` (default 36 pt, clamped to
  `NotchIslandGeometry.heightRange`, 20–44, on load and on write; kept
  when the mode goes back to the menu bar), `notchIslandHidesUntilHover`
  (default false) and `notchIslandHidesInFullScreen` (default **true**,
  presence-checked). Their keys and loading live in
  `Shared/PreferencesStore+NotchIsland.swift`; corrupt values (an unknown
  raw value, NaN, out of range) fall back or clamp, tested. Which of
  boring.notch's and Atoll's options were taken and which were not: the
  height on non-notch displays, the hover delay, the external-display
  style (Atoll's "Dynamic Island"), hide-until-hovered (Atoll) and
  hide-from-capture (Atoll) were; full-screen hiding was, rebuilt on the
  public window list (theirs goes through a third-party package,
  MacroVisionKit, watching Spaces); show
  on all displays / preferred display (one panel per display — a
  larger change), show on the lock screen (private SkyLight API), the
  shadow and corner-radius-scaling toggles (cosmetic), haptics (Force
  Touch trackpads only), the closed and open widths (AIMeter's island is
  the natural size of its content) and "extend hover area" (declared in
  boring.notch but read nowhere — no effect) were not. The island and the status item are
  **coupled**, in two steps: on the upgrade the icon *stays* until the
  user opens the island for the first time
  (`PreferencesModel.markNotchIslandDiscovered`, called by the controller
  on the first user-initiated open, hides it then — never before the
  user has found its replacement); the Settings toggle couples them
  immediately (`setNotchIsland(enabled:)`: on hides the icon and counts
  as discovered, off brings it back; "Hide menu bar icon" still works on
  its own afterwards, so both can be shown together by hand). This is
  the one deliberate exception to "defaults never change an existing
  install". `appearance` defaults to **`.dark`
  on macOS** since 2.0 (`.system` on iOS, `#if os(macOS)` on the struct's
  default) — an install that ever chose a theme has the key written and
  keeps it; one that never did falls into dark, the one other
  upgrade-visible change, so the app matches the black island beside it.
  On macOS the appearance is applied to the whole app through
  `NSApp.appearance` (`AppChrome.applyAppearance`, at launch and when
  Settings changes it): `.preferredColorScheme` on the scenes never
  reached the `MenuBarExtra` window, so a dark AIMeter opened a light
  popover.
- macOS chrome prefs (same App Group store, macOS-only meaning):
  `statusItemVisible` (default **true**, but see the island coupling
  above), `hideDockIcon` (default **false**), and the status item's own: `menuBarStyle` (`MenuBarStyle` —
  `gaugeWithPercent` (the default and what shipped first), `gaugeOnly`,
  `percentOnly`, `bar`, `battery`, `multi`), `menuBarMetrics` (the 1–3
  windows `multi` lists, default session + weekly, filtered at render
  time to what the primary account reports — the same live-options rule
  as `glanceMetric`), `menuBarTintsAtDanger` (the bars' `UsageLevel`
  color — yellow above 70 %, red above 85 % used or a critical severity —
  default off, offered only while `usageColors` is on; the key keeps its
  first name), `menuBarShowsResetCountdown` (default
  off; while on, the label reads `MinuteClock.now`, an observable date a
  main-actor task advances at each minute boundary — **never** a
  `TimelineView` in the `MenuBarExtra` label: on macOS 27 that re-renders
  the status item from inside its own render and the app never finishes
  launching, 100 % CPU; 1.6.0 shipped with that bug, fixed in 2.0) and `menuBarShowsAccountName` (default off, offered only with 2+
  accounts), and `checksForUpdates` (the daily update check, default
  **on**, presence-checked; see "Updates (macOS) and What's new"). All default to the behavior that shipped before they
  existed, so an upgrade never changes an existing install — including
  the one migration: `menuBarShowsPercentage`, the pre-style bool, is
  only read at load now, to derive `menuBarStyle` for an install that
  never chose one (`false` → `gaugeOnly`); a stored style wins over it,
  and the old key is left inert, never deleted (the same rule as the
  migrated notification keys). Bools whose default is `true` must load
  through `Preferences.bool(_:_:default:)`, which presence-checks the key —
  `UserDefaults.bool(forKey:)` reports `false` for an unwritten key and
  would silently flip them. Unlike `glanceMetric` (account-dependent, so it
  lives in Claude's Provider Detail on iOS) these are provider-agnostic app
  chrome and surface in app-wide Settings (`MacSettingsView`'s General
  and Menu bar tabs: `HidingSettings`, `MenuBarSettings`). The label itself is computed once per state change
  by `MenuBarLabelModel` (Shared, pure) and only drawn by `MenuBarLabel`:
  the gauge styles are the variable-value SF Symbol as always, `bar` and
  `battery` are rendered to an `NSImage` with `ImageRenderer` (a status
  item flattens arbitrary SwiftUI shapes but draws an `Image(nsImage:)`
  faithfully) — a *template* image, so it follows a light or dark menu
  bar, except under a tint, where it carries the real `Theme.warning` or
  `Theme.danger` and is marked non-template. Whatever the style, the exact
  value(s) stay in the tooltip and the accessibility label.
- Notch island (macOS, 2.0): a pure-black panel fused to the MacBook's
  notch — or, on a screen without one (an external display, an iMac, a
  MacBook Air, a closed MacBook feeding a monitor), an island it draws
  itself in the form the user picks (`notchIslandForm`): by default a
  notch fused to the top edge over the menu bar's centre, boring.notch's
  answer — the same silhouette, as wide as its row and the menu bar
  tall, growing exactly like the real one — or a **pill** like the
  iPhone's island (Atoll's "Dynamic Island" style): a capsule floating
  inside the menu bar, `pillInset` (3 pt) below the top edge, that opens
  into a rounded card (`IslandPillShape`, continuous corners, 24 pt
  radius) — never a capsule around a body, which is what made 2.0.0's
  floating pill unreadable (it hung *under* the bar and a 300-pt-tall
  capsule clipped its content at the ends). A custom height
  (`notchIslandHeightMode`) makes either taller; the pill then hangs
  below the bar keeping a 2 pt gap, and the row's figures grow with it
  (`NotchIslandGeometry.rowScale`, up to 1.35×). The island shows
  every account's windows in Vibe Island's line format,
  `✦ 5h 42% 2h 58m | 7d 61% 3d 3h`. The pure part is
  `Shared/NotchIslandModel.swift` (what it shows, computed once from the
  accounts' snapshots and the prefs, sibling of `MenuBarLabelModel`) and
  `Shared/NotchIslandGeometry.swift` (where and how big, from plain
  rects in AppKit coordinates); everything that touches `NSPanel` is
  `AIMeter/Views/NotchIsland/` (see "macOS notch island" in
  `AIMeter/CLAUDE.md` for the panel, hover, click, Esc and screen rules).
  Data rules, the same as every other surface's: a segment's **label is
  the window's real length**, not its kind — under 48 h in hours ("5h"),
  from there on in days ("7d", "30d", so a provider whose week is a
  month needs no new `Kind`), a per-model window is the model's name
  (cut to 6 characters in the wings), credits is "Cr" (localized like the
  menu bar's "S/W/C"); percentage and bar fraction follow `DisplayMode`;
  the reset is the bare countdown or clock time per `ResetStyle` (the
  full "Resets in …" sentence stays in the accessibility label), and a
  credits slot shows `SpendStatus.amountLabel` there when
  `showCreditsAmount` is on; tint is the bars' rule
  (`UsageWindow.level(usageColors:)`) with no switch of its own (the
  island is a colored surface, unlike the monochrome status item) —
  terracotta where Vibe uses green, yellow and red as everywhere else
  (`UsageLevel`), terracotta alone while usage colors are off; the third slot
  is `WindowSlots`/`ModelSlotFallback` exactly as on the Dashboard, and
  an empty slot keeps its place with `--`. **Collapsed, the
  island is the notch and shows nothing** — so no menu title or status
  item is ever covered (Xcode's menu runs up to the notch on a 14"),
  with one exception: while a Claude Code session works, waits for a
  permission prompt or has just finished, its pets and their count sit
  either side of the notch, centered on it (see "Claude Code
  sessions"); a
  drawn island, having no real notch to hide in, shows its one row —
  unless it is **concealed** (`NotchIslandVisibility.isConcealed`):
  always with "Hide until hovered", or while a full-screen app has its
  screen with "Hide in full screen" (on by default — there is no menu
  bar to sit in then, and it would cover the app's top centre). It
  slides up past the top edge on the level spring and comes back with
  the peek. Full screen is recognized from the public on-screen window
  list (`CGWindowListCopyWindowInfo`; bounds and levels need no Screen
  Recording permission): a level-0 window that starts at the display's
  top edge and runs its full height, over the menu bar's strip — a
  full-screen app, either half of a Split View, a game's borderless
  full screen — measured on macOS 27, where
  `currentSystemPresentationOptions`, `NSMenu.menuBarVisible()` and
  `visibleFrame` all report another app's full screen as nothing;
  checked on Space changes (again 0.4 s and 1.2 s later, as the switch
  settles), app activations, wake and screen changes, and every 3 s
  only while it holds the island hidden (an app can leave its own
  borderless full screen without a Space change). On a screen without a notch the island tracks
  the pointer itself (a global `mouseMoved` monitor, no permission;
  polled at 20 Hz only while AIMeter itself is frontmost, when the
  global monitor is silent): the pointer is on the island when it is
  on its collapsed place from the top edge down
  (`NotchIslandGeometry.hoverRegion`, live while hidden, the pill's gap
  included) or on the slab as drawn, the top edge itself counting —
  pushed against the top, the pointer reads exactly the screen's
  `maxY`, which `CGRect.contains` would leave out — and SwiftUI's hover
  cannot see a hidden island or the transparent strip above the pill.
  The
  interaction is the pure, tested `NotchIslandInteraction` (Shared): the
  cursor has to **stay** on the notch for the hover delay
  (`notchIslandHoverDelay`, 250 ms by default) before the island
  **peeks** — passing over the notch on the way to a menu does nothing —
  and the peek is the wings (with no Claude Code session at work; with
  one, the peek shows that session, see "Claude Code sessions"): the
  *primary* account's `notchIslandMetrics` (1–3, filtered to what it reports like
  `menuBarMetrics`, falling back to `glanceMetric`) as compact
  `label percent` figures beside the notch, on the side(s)
  `NotchIslandLayout` says (`bothSides`: first left, rest right, the
  two wings as wide as each other so the slab stays centered;
  `leftOnly`; `rightOnly`), no resets; with nothing connected the wing
  carries a "Connect" affordance routed through `AppChrome.connect(.add)`.
  Staying on the open wings 1 s more, or a **click** at any time, opens
  the expanded island. On a screen without a notch, a drawn notch or
  pill in sight already shows its row, so there the dwell opens the
  expanded island at once (`NotchIslandInteraction.skipsPeek`, from
  `NotchIslandVisibility.showsRowWhenCollapsed`); a hidden one still
  peeks first, since the peek is what brings its row back. In every
  case, a click on an expanded island, leaving it (after
  150 ms, whatever opened it) or a click anywhere else closes it (mouse
  monitors, which need no permission). The motion is boring.notch's
  system, rebuilt (it is GPL, read for the recipe, nothing copied): a
  fixed window, the slab as the natural size of its content, one spring
  — see "macOS notch island" in `AIMeter/CLAUDE.md`. Nothing is pinned and the island
  never takes keyboard focus, so there is no Esc. Once, on the first
  launch with the island on, it peeks by itself for a few seconds with a
  one-line caption saying what it is (`notchIslandRevealed`). Expanded,
  the wings stay as the header, reaching out to the body's edges, and
  every account gets a row — identity header, the full line (label, percent, `↻` reset) with a 2 pt
  bar under each segment, and a status line only when there is one —
  all accounts in one grid (`AccountGrid`) spanning the island edge to
  edge, so their windows share columns, the gaps between them are
  spread evenly and every bar in a column has that column's width; the
  header, the accounts, the sessions and the footer share one left and
  one right edge (`ExpandedContent.horizontalPadding`). The figures
  step down from 12 to 11, then 10 pt when the grid would not fit. The status line:
  "Updated 31 min ago" past `AppConfig.staleAfter`, the offline line, the
  "Sign in again" prompt (`AppChrome.connect(.reconnect)`), or the raw
  error — plus the incident notice while the provider reports one, and a
  Refresh / Open AIMeter / Settings footer. Nothing lives only in the
  island: the popover, the Dashboard and the tooltip carry every figure.
  Demo mode shows the demo accounts (it is where the site's capture comes
  from).
- "Open at Login" has **no preference key**: `SMAppService.mainApp.status`
  is the state, read live by `LoginItemManager`. A mirrored bool would drift
  the moment the user revoked it in System Settings.
- Stale snapshot (>30 min): widgets show a small "last updated" hint in the
  header trailing edge.
- Errors render inside the provider card, below the rows: raw endpoint body
  included, in `Theme.danger`. Two exceptions: a credential failure shows
  an actionable "Sign in again" prompt instead (see "Losing a login"
  above), and a lost network (`UsageModel.offlineCodes`, the `URLError`s
  that mean no route rather than a provider answer) shows a quiet
  "Offline. Showing the last update." line in the secondary color
  (`AccountUsage.isOffline` → `UsageStatusFooter(offline:)`) — nothing is
  wrong with the account, the last snapshot still stands, and the next
  successful fetch clears it.
- Service incidents (see "Service status" above) render in three places,
  and only while the provider reports one (`ServiceStatus.isDegraded`) —
  on a normal day nothing is added anywhere: a `ServiceStatusBanner`
  above the account list on the Dashboard and at the top of the macOS
  menu bar popover (provider name + the page's own description, the
  incident title or the affected components under it, tap opens the
  incident's page or the status page; `Theme.danger` tint for
  major/critical, the accent for minor/maintenance — still two colors);
  and one quiet secondary-color line under a failing account's raw error
  (`UsageStatusFooter(serviceIncident:)` ← `UsageModel.incidentNote(for:)`,
  "Claude reports an incident: …") — only when that account's refresh is
  actually failing, not offline (the device's network, not their outage)
  and not a dead login (an incident doesn't invalidate credentials). The
  raw body stays underneath it, per the typed-errors rule. Provider
  Detail alone shows the status even when fine: a footnote under the
  rate-limit card, "Service status: All Systems Operational · checked
  3 min ago" (`serviceStatusFootnote`), so the user can see the check
  exists and how fresh it is. The status item (`MenuBarLabel`) never
  gains a glyph for it.

## Screens

Screen-by-screen behavior lives in `AIMeter/CLAUDE.md` (Dashboard, Provider
detail, Settings, Privacy & data, Connect sheet, Demo mode, Landscape,
macOS menu bar, macOS hiding & re-entry) and `AIMeterWidgets/CLAUDE.md`
(both widget kinds) — loaded automatically when working under those
directories.

## Design system (Shared/Theme.swift)

`Shared/ProviderIdentityView.swift` is the one place that draws "icon +
name + optional plan pill" — parametrized by icon size/corner radius,
font, and name color so it fits the dashboard, landscape header, menu bar,
and both widgets without re-typing the composition per surface; each
caller still wraps it in its own `HStack` for whatever trailing content
(chevron, "Updated X ago", a staleness hint, or nothing) that surface needs.
The icon it draws is `Shared/ProviderMark.swift`: by default an SF
Symbol (`sparkle`) on the app's own accent wash (or a filled accent tile,
`prominent: true`, for the Connect sheet header), also used directly by
Privacy & data and the Live Activity's compact/minimal islands. Since
1.6 the user can pick a glyph **per account** (`ConnectedAccount.icon`,
an `AccountIcon`: any SF Symbol by name, or one of two bundled marks —
`ClaudeMark` and `ClaudeCodeMark` in `Shared/Media.xcassets`, the
Claude and Claude Code logos as single-path template SVGs). Every choice
is drawn the same way, a template glyph in the accent on the wash at the
same size, so headers keep one shape and weight whatever the pick. The
picker is `AIMeter/Views/AccountIconPicker.swift` (Dashboard header
context menu "Change icon…", Provider Detail → Account → Icon): the
three marks, a curated SF Symbols grid, and a free-text field validated
against the OS's symbol set, applying immediately through
`UsageModel.setIcon`, which writes the registry and nudges the same
cached surfaces a rename does (widgets reload; a running Live Activity
restarts, since its `attributes` carry the icon like the name). The
default stays the sparkle, so nothing changes for an account that never
picks one. Bundling the two marks was a deliberate product decision on
2026-10-07, taken knowing the history below: Anthropic's trademark
guidelines reserve the Claude logo for uses approved in writing, App
Review (4.1(c)/5.2.1) treats a third party's icon the same way, and the
app was rejected once over brand use. The provider is still identified
by its *name* in every header the user hasn't customized; the GitHub
mark in Settings is a link glyph to the app's own repository.
Two more `Shared/ThemeComponents.swift` views follow the same rule for
other repeated pieces: `UsageStatusFooter` (the error label + "Updated X
ago" caption under the rate-limit rows — dashboard, provider detail, menu
bar popover; `showsDividers` defaults on for the two card surfaces, off
for the menu bar which already brackets the section with its own, and
`reauthenticate` swaps the error label for the "Sign in again" prompt, see
"Losing a login" above) and
`DisconnectedPrompt` (the "Sign in to see your usage" text + Connect
button — dashboard and menu bar, `buttonLabel`/`verticalPadding`
parametrized per surface, caller still owns the wrapping container).

Bar/percentage color is one decision, `UsageLevel`
(`Shared/WindowDisplay.swift`, read as `UsageWindow.level` /
`.tint(usageColors:)`) —
`Theme.accent` (terracotta) up to 70 % used, `Theme.warning` (a warm
yellow that sits with the terracotta on ivory and charcoal — a cold, pure
yellow glared on a light widget) from 71 % or when the provider flags `warning`, `Theme.danger` (a pure
red, no orange in it, so it never reads as a darker terracotta) from
86 % or when it flags `critical`/`exceeded` (`warningAbove` 70,
`dangerAbove` 85, both strict, compared on the whole percent every
surface prints — they all truncate — so a bar reading "70%" is never
yellow even when the endpoint reports 70.6). Three colors, nothing else, on purpose: a
glance tells room, heads-up and nearly out apart, the way Claude's own
usage menu does. The thresholds are on *used* whatever `DisplayMode`
shows. The yellow and red are the user's to turn off, once for every
surface (`Preferences.usageColors`, Settings → "Usage colors", on by
default and presence-checked): off, every bar, widget, Live Activity and
island segment draws at `.normal`, terracotta whatever the figure or the
provider's flag — the level itself is still computed, only its color is
withheld (`UsageWindow.level(usageColors:)`). Exposed as a static,
`tint(usedPct:severity:usageColors:)`, so a caller that only carries those two values
(not a full `UsageWindow`) can still make the same call rather than
re-deriving a simplified copy — the Live Activity's `ContentState` does
exactly this (see `AIMeterWidgets/CLAUDE.md`). The menu bar applies the
same levels only when asked (`menuBarTintsAtDanger`, the most urgent of
its listed windows, and only while usage colors are on — Settings
doesn't offer the switch otherwise); otherwise the status item stays
monochrome. The
Lock Screen accessories stay system-tinted. The notch island keeps
the same three colors (their dark variants, drawn in a forced dark
`colorScheme`), except a brighter yellow, `Theme.islandWarning` — the
cards' warm yellow reads dull on black — on a surface that is pure black whatever the appearance —
the color of the hardware, not of the theme — with white at fixed
opacities for labels (82 %), resets (50 %) and separators (22 %)
(`NotchIslandStyle`).

## Localization

English source (plus each release's notes in `AIMeter/WhatsNew.json`,
which carries its own eight languages, see "Updates (macOS) and What's
new"); complete translations in Spanish, German, French,
Japanese, Korean, Brazilian Portuguese and Simplified Chinese (the six
added for 1.6.1 were written in-house on 2026-10-07 against the English
key, its comment and the Spanish, and are open to native review); the
device language picks automatically. Two catalogs:
`Shared/Localizable.xcstrings` (app + widget UI) and
`Packages/UsageKit/Sources/UsageKit/Resources/Localizable.xcstrings`
(errors, via `String(localized:bundle:.module)`); `AIMeter` links
Swift Charts for the history chart (a system framework, still no
third-party dependency). Brand words (Claude, Claude Code, Pro, Max,
AIMeter, SF Symbols) are never translated; Apple's own terms follow
Apple's glossary per language (Keychain, Lock Screen, Live Activity,
Dynamic Island, Shortcuts, menu bar). A handful of keys are left
untranslated in every language on purpose — the Shortcuts action titles
("Refresh Usage", "Show Usage"), which the Settings footnote quotes
verbatim — and the compact menu-bar letters ("S", "W", "C") and
countdown units ("%lldh %lldm") are localized as short as each script
allows. Dates/currency use system formatters. No em dash (—) in any copy, in
any language, nor the en dash some languages use for the same pause:
a comma, colon, period or parentheses instead, and `--` for a figure
there is none of (Mike's rule, 2026-10-14; code comments and these
docs are not copy). To add a language: add
translations to both catalogs (every key that has a Spanish value) and
the region to the project's `knownRegions`; placeholders must match the
key exactly (`%@`, `%lld`, `%%`, positional `%1$@` when reordered).

## Conventions

- Swift 5.10+, async/await only (no Combine for new code).
- Keep files under ~300 lines; split by feature, not by type.
- Accessibility: every usage row is one combined VoiceOver element; bars
  are decorative (`accessibilityHidden`); icon-only buttons carry labels.
- Keyboard shortcuts (macOS): a "Usage" menu in the main menu bar
  (`AIMeterApp.commands`) carries them so they are discoverable — ⌘R
  Refresh All, ⌘N Add Account…, ⌘⇧U Used/Remaining, ⌘⇧A relative/absolute
  reset times. ⌘R is declared there and on the popover's Refresh button
  (the popover is its own window with no main menu), never on the
  Dashboard's own button as well: both firing was the bug. The popover
  also declares ⌘, and ⌘Q on its Settings…/Quit buttons for the same
  reason. "Add Account…" reaches the Dashboard's Connect sheet through
  `AppChrome.connect(.add)` (see "macOS menu bar" in `AIMeter/CLAUDE.md`),
  the same bridge shape as `AppChrome.openDashboard`. There is no global hotkey of the app's own
  (see "macOS hiding & re-entry" in `AIMeter/CLAUDE.md`); the sanctioned
  route is the App Intents: `RefreshUsageIntent` (refreshes every account
  and speaks a one-line summary per account, `UsageSummary.spoken`) and
  `ShowUsageIntent` (`openAppWhenRun`, reveals the dashboard), registered
  by `AIMeterShortcuts` with phrases, so the user can give either a
  system-wide key in the Shortcuts app with no extra permission. They
  reach the live model through `AppEnvironment.shared`, which
  `UsageModel.init` now sets on both platforms (iOS gets the same two
  Shortcuts/Siri actions for free). Their `perform()` is `@MainActor`:
  AppIntents calls it from an arbitrary executor and everything they
  touch is main-actor state.
- Hit areas: a `.plain`-style `Button` hit-tests its *label*, and a
  transparent frame, padding, or `Spacer` is not opaque content — so any
  button whose background is drawn outside the label (the capsule buttons,
  `SegmentedPill`'s unselected segments, the Settings rows inside a `Card`,
  the account header) claims its full shape with `.contentShape(...)` on
  the label. Without it only the word or glyph responds, which is how the
  Connect sheet's button shipped once: tappable on the text, dead on the
  rest of the capsule.
  `accessibilityReduceMotion` gates the three animated transitions in the
  app (`RoundIconButton`'s refresh spin, `SegmentedPill`'s selection
  change, and the Dashboard account reorder's drop-target highlight and
  settle) — when on, the state still updates, just without
  `withAnimation`. Anything reachable only by dragging needs a
  non-drag equivalent: the dashboard's reorder pairs its drag with
  "Move up"/"Move down" in the account header's context menu, which
  VoiceOver and Switch Control surface as actions.
- Tests: UsageKit's (`swift test`; fixture
  `Tests/UsageKitTests/Fixtures/claude-usage-response.json` is a real
  captured response — mapping tests assert against it;
  `AIMETER_LIVE_TEST=1` enables an opt-in live test;
  `ClaudeCodeSessionTests` pins the session rules on the measured record
  shapes) and the app's own
  `AIMeterTests` target (`xcodebuild test -scheme AIMeter`, hosted in
  `AIMeter.app` on either platform, `@testable import AIMeter`), which
  covers the Shared/app logic UsageKit can't see: `WindowSlots` and the
  grouped reset line, `UsageFormatting`, `UsageSnapshot.glanceOptions`,
  `NotificationPreferences` (incl. `SmartAlert` and `clear()` scoping),
  `ProviderCatalog`, `UsageModel`'s naming/ordering/demo paths, the
  usage levels and the usage-colors switch with its presence-checked
  default (`UsageLevelTests`), versions and the bundled What's New notes
  (every language, no em dash, every named feature one the tour knows)
  with the rules for which are due (`WhatsNewTests`), the tour's
  audience, steps and the offers after an update (`TourTests`), on macOS the update feed against a captured GitHub
  response (`AIMeterTests/Fixtures/github-release-latest.json`), the
  offer rules and the install script (`UpdateFeedTests`), the
  service-status throttle, aging, banner and footer-line rules
  (`ServiceStatusTests`, with a stub `ServiceStatusSource` injected
  through `UsageModel.serviceStatusSources`), the menu bar label's
  text/fill/tint rules plus the style migration
  (`MenuBarLabelModelTests`), the notch island's label/figure/tint/reset,
  third-slot, wing-split and status rules (`NotchIslandModelTests`), its
  frames from this Mac's measured screen rects
  (`NotchIslandGeometryTests`), its hover/dwell/leave/click state machine
  (`NotchIslandInteractionTests`, the hover delay's clamping included),
  the drawn notch and the pill on a screen without one — heights, the
  pill's gap, radii, row scale, hover region, and their invariants swept
  over every menu bar height, custom height and form
  (`NotchIslandFormGeometryTests`), concealment's truth table, the
  full-screen check against window lists measured on macOS 27, and the
  pointer rule (`NotchIslandVisibilityTests`), its preference keys,
  clamping of corrupt values, the status-item
  coupling and discovery, the hardware-decided upgrade step and the
  per-platform appearance default (`NotchIslandPreferencesTests`),
  `HistoryChartData` (readiness, clipping,
  segments, resets, the spoken summary, and that the demo timeline ends
  on the demo snapshot), and on macOS `ClaudeCodeUsageModel` over a
  scratch logs folder (scan, buckets, the popover line, off deletes the
  index) plus the token/USD formatters, and Claude Code's sessions: the
  preferences, the mark, count and rows, the hooks' edits to Claude
  Code's settings, whose log a path is, and a hook request's body
  (`ClaudeSessionsTests`, with the demo's sessions and the pets their ids
  deal, which the website's videos show, the room a drawn row's name
  gets, and which changes the "needs you" notification announces or
  takes back; nothing there opens the socket or
  touches `~/.claude`), and the pets: every combination reachable and distinct,
  an id's pet pinned, the deal's uniqueness and order independence,
  every creature, accessory and pose inside its canvas on every tick,
  and the pixel size (`SessionPetTests`), and how far the wings beside
  the notch may reach: the status items found in a window list or
  placed by the Accessibility API (this Mac's, measured on macOS 27), the
  menus' edge, the narrower side for both, and on a screen without a
  notch the room either side of its centre (`NotchIslandClearanceTests`). Two
  seams exist for it and nothing else: `UsageModel(registry:platformServices:)`
  with `platformServices: false` (no migration — it probes the real
  Keychain — no scheduler/observers, no notification sweep) and
  `NotificationPreferences(accountID:defaults:)`; every test writes only to
  a throwaway `UserDefaults` suite (`ScratchDefaults`), never the App
  Group the host app opens. Not covered on purpose: anything that fetches
  (`RefreshService`, `WidgetRefresher`) or touches the Keychain
  (disconnect, connect, `AccountMigration`).

## Open source hygiene

- MIT license. README includes: undocumented-endpoint disclaimer, privacy
  /data-transparency section (which lists every host the app talks to —
  the usage/profile endpoints, the OAuth page on iOS, the public
  status page, and on the Mac GitHub's release API and download), build
  instructions with the user's own team ID, no
  affiliation with Anthropic.
- The App Store Connect app record's **Name** is `AIMeter: Usage Tracker`,
  not the bare `AIMeter` — that exact string is already registered to
  another app (`Name` must be globally unique across every developer in
  the store, unlike the Bundle ID or SKU, which are only scoped to this
  account). This is store-listing metadata only: the in-app title, Bundle
  ID (`com.mikealvarado.aimeter`), App Group, and every other reference in
  this project and codebase stay `AIMeter`.
- `DEVELOPMENT_TEAM` is not hardcoded in `project.pbxproj`: both targets'
  build configs read it from a `baseConfigurationReference` to
  `Config.local.xcconfig` (gitignored, matches the `*.local.xcconfig`
  pattern). `Config.local.xcconfig.example` is the tracked template new
  clones copy and fill in with their own Team ID.
- `Shared/PrivacyInfo.xcprivacy` (bundled into both targets via the
  file-system-synchronized `Shared/` group) declares no tracking and the
  one required-reason API category actually used — `UserDefaults`, reason
  `1C8F.1` (App Group only). Update it if a new required-reason API is
  ever introduced — which is why the Claude Code log reader keys files
  by size and byte offset and never reads a modification date (file
  timestamps are a required-reason category).
- App Review posture. Version 1.0 was rejected under 4.1(c) (Copycats —
  the store subtitle named Claude) and 5.2.2 (Legal — "requests, displays,
  or distributes third-party account information"). The code-side answer,
  all of which must hold for every later submission: no third-party logo
  on any *default* surface (`ProviderMark` draws the sparkle unless the
  user picks otherwise — the two Anthropic marks bundled since 1.6 for
  the per-account icon picker are opt-in and never appear in demo data or
  screenshots; a knowing exception, see "Design system");
  "Claude" only as plain-text nominative use *inside* the app, never in
  the App Store name, subtitle, icon, or keywords, with the store
  description carrying the not-affiliated/trademark line the Privacy
  screen already shows; the in-app OAuth requests `user:profile` only; the
  iOS build never accepts another app's credential file; the Connect
  sheet states independence and read-only scope at the moment of
  connecting; and demo data — the source of App Store screenshots, which
  are metadata too — names no provider or product ("Personal", "Top
  model"). Store metadata itself (name, subtitle, promotional text,
  keywords, description, screenshots, in every localization) carries no
  third-party name at all after the third rejection under 4.1(a): even the
  descriptive "supports Claude Pro/Max" sentence was pulled from the
  description. Anthropic's own published rule (Claude Code docs → Legal and
  compliance → "Authentication and credential use") reserves Claude.ai
  OAuth for its own applications and disallows third parties collecting or
  storing Claude.ai credentials, so none of this amounts to permission —
  it is the honest minimum, and any change that adds a brand asset or a
  credential path reopens both findings.
- Store assets (screenshots, the product-page header, the search-results
  card) are rendered from the app's own views by `Scripts/store-frames.sh`
  over demo-mode simulator captures; `Scripts/StoreFrames/CLAUDE.md` is
  the record of sizes, rules, style and the upload procedure, and is kept
  current like every other doc here.
- The website (`site/`: product page, privacy policy, support page, in
  English and Spanish) is a static React + Vite app deployed to GitHub
  Pages by `.github/workflows/site.yml`; its `CLAUDE.md` holds the
  structure, the content rules (the landing page follows the store's
  no-third-party-names posture; the privacy and support pages name the
  hosts, factually) and the three URLs App Store Connect points at
  (marketing, support, privacy policy). Its images come from the store
  pipeline above (`site/scripts/images.mjs`), plus the notch island's
  three captures (`site/scripts/island.mjs`, see "Not store assets" in
  `Scripts/StoreFrames/CLAUDE.md`).
- Never commit: xcuserdata, local xcconfig, credentials, tokens, or
  anything under `docs/design/reference/` (gitignored).
- Credit where it is due, and only that. The notch island's motion
  system follows boring.notch (GPL-3.0), its line format and the way it
  shows a Claude Code session while collapsed (its pets at one end, the
  count at the other) follow Vibe Island, and its options for screens without a notch — the pill, the
  height, hide until hovered, hide from captures — follow Atoll
  (GPL-3.0, a boring.notch descendant); all three are named in the
  README's Acknowledgments, the website's support page and the relevant
  doc sections here, always with the same two facts: the approach was
  studied, no code was copied, and the tree stays MIT. Naming an open-source project as inspiration carries no
  license obligation; a copied file would (GPL is viral, MIT is not),
  which is why the island was written from scratch and why a reference
  clone never lives inside the repository. Neither name appears on the
  landing page or in store metadata, under the same no-third-party-names
  posture as the provider's.
- App Store notes for the macOS background work: the `SMAppService` login
  item is reviewed, so it stays opt-in, off by default, visibly toggleable,
  and disclosed in `PrivacyView`. It needs no entitlement (unlike the
  deprecated `SMLoginItemSetEnabled`/`SMJobBless`) and works unsandboxed as
  the app is today. Hiding the Dock icon via `.accessory` is routine for
  menu-bar utilities and unproblematic. A global re-entry hotkey was
  rejected precisely because it would add an Accessibility/Input Monitoring
  permission and the review scrutiny that comes with it. The one
  Accessibility use there is, since 2.1, is opt-in and narrow: "Avoid
  covering the menu bar" asks for it only when switched on and reads only
  where the open app's menu titles and the menu bar's status items are
  (see "Claude Code sessions"), disclosed
  in `PrivacyView` and the website's privacy page. Separately,
  `ENABLE_APP_SANDBOX = NO` is pre-existing and would have to change for
  Mac App Store distribution regardless of any of this, and so would the
  updater: a Mac App Store build must not update itself.

## Workflow

- Data model follows reality: before changing endpoint-related code, run
  `Scripts/probe-usage-endpoint.sh` (usage) or
  `Scripts/probe-status-endpoint.sh` (the status page) and check the
  captured fixtures; before touching the Claude Code log reader, run
  `Scripts/probe-claude-code-logs.sh` (shape only). Never guess wire
  formats.
- Before large changes, propose the plan and wait for approval.
- **Git history is linear: rebase and merge, always.** One feature or
  fix per branch, branched from its base (`papa` while an integration
  branch is open, else `main`), with plain commit messages and no
  Co-Authored-By line. To land it, rebase the branch onto its base and
  fast-forward (`git rebase <base>` then `git merge --ff-only`, or
  GitHub's "Rebase and merge"); never `git merge --no-ff`, never a
  "merge:" commit, never a squash that loses the per-feature commits.
  Conflicts are resolved during the rebase, commit by commit, so every
  commit still builds. Branches whose commits are all on the base get
  deleted on the remote once landed — a stale branch with no PR only
  invites GitHub's "Compare & pull request" noise. `rerere` is on for
  this clone so a conflict resolved once is replayed automatically.
- Releasing: iOS through App Store Connect; the Mac app as a Developer
  ID-signed, notarized zip on a GitHub Release, built by
  `Scripts/release-mac.sh` (hardened runtime is on for both macOS
  targets). The script needs only the Apple account Xcode is signed in
  to: the Developer ID signature is a cloud-managed certificate and the
  export uploads straight to the notary service with that account
  (`destination` `upload`, then `xcodebuild -exportNotarizedApp` once
  Apple is done) — no local certificate, no `notarytool` profile. See
  README → "Releasing". Every release, both platforms: bump
  `MARKETING_VERSION`, add its notes to `AIMeter/WhatsNew.json` in all
  eight languages (the script checks), tag it with exactly that version
  and keep the asset's name `AIMeter-macOS.zip`, which is what the Mac's
  updater looks for.
- Verify on both platforms: `xcodebuild` for macOS and iOS Simulator plus
  `swift test` in `Packages/UsageKit` must pass warning-free, and
  `xcodebuild test -scheme AIMeter` (the app's own unit tests) on at
  least one of them.
- Docs follow reality, same as the data model: any change that touches
  behavior, config, file layout, or a new feature's shape is not done
  until every doc that describes it is updated too — this file, the
  nested `AIMeter/CLAUDE.md` / `AIMeterWidgets/CLAUDE.md` /
  `Packages/UsageKit/Sources/UsageKit/Providers/Claude/CLAUDE.md`, and
  `README.md` for anything user-facing (features, setup steps, the
  architecture tree). A stale doc is a bug, not a follow-up — this file's
  own opening claim is that it's enough to rebuild the app from zero, and
  that stops being true the moment one of these drifts from the code.
