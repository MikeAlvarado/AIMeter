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
- Widget kinds: `AIMeterUsage` (the three-window widget),
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
  `UsageModel+Notifications.swift` (the per-account toggles) and
  `UsageModel+macOS.swift` (refresh schedule, wake/activation observers,
  `AppEnvironment`); members those extensions share are internal rather
  than private, by necessity, and documented as such. Notifications are
  three files: `NotificationPreferences.swift` (the toggles, plus
  `SmartAlert` — the five per-account families addressed as one enum, so
  the model and the toggles card have one getter/setter pair instead of
  five), `NotificationScheduler.swift` (the fetch-driven families) and
  `NotificationScheduler+Peak.swift`.
- `AIMeter/Views/` — Provider Detail is `ProviderDetailView.swift` plus
  `ProviderDetailCards.swift` (Peak, Forecast, raw detail rows and their
  row builders, `ProviderDetailRows`) and `NotificationTogglesCards.swift`
  (both notification cards). The Dashboard is `DashboardView.swift` plus
  `DashboardView+Reorder.swift` (the hold-and-drag reorder, whose state
  stays on the view — internal `@State`, for the same reason as above) and
  `RoundIconButton.swift`.
- `Shared/` — `PeakBadge.swift` is the one peak glyph every glance surface
  composes (menu bar popover, both widget headers, the all-accounts
  widget, the Live Activity); `PreferencesModel` keeps a single stored
  `Preferences` value behind computed accessors, so the field list exists
  once.

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
  sandboxed widget can't read Claude Code's credential file).
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
- Disconnect cascades (`RefreshService.disconnect()` from
  `UsageModel.disconnect(accountID:)`): credentials, stored snapshot, usage
  history, every notification still pending or delivered for that account
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
- Usage history: `UsageHistoryStore` (App Group, keyed by `accountID`)
  keeps a bounded, reset-aware ring of `(timestamp, usedPct)` samples per
  window — the extra data (beyond the single latest snapshot) the
  recent-rate run-out predictor needs. Recorded wherever a fetch persists
  a snapshot (the app refresh *and* the iOS widget self-fetch, so it stays
  continuous when only the widget runs); a used%-drop discards a kind's
  prior samples so a rate never spans a reset. Cleared on disconnect. Each
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
  "Work — Session limit reset"); a single-account install's copy reads
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

## Presentation rules

- Session and weekly slots are always present (`WindowSlots`); a missing
  window keeps its slot (em dash + empty bar). The third slot shows the
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
  — applies to dashboard, detail, menu bar, widgets, landscape. Credits has
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
  System/Light/Dark, refresh cadence, and `glanceMetric`
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
  Settings → `MacChromeSettings`), picks which account the one status item
  represents (`UsageModel.primaryAccountUsage(preferredID:)`, falling back
  to the first connected account when unset or stale). Both pickers moved
  out of Claude's Provider Detail and into `MacChromeSettings` — with
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
- macOS chrome prefs (same App Group store, macOS-only meaning):
  `menuBarShowsPercentage` (default **true**), `statusItemVisible`
  (default **true**), `hideDockIcon` (default **false**). All three default
  to the behavior that shipped before they existed, so an upgrade never
  changes an existing install. Bools whose default is `true` must load
  through `Preferences.bool(_:_:default:)`, which presence-checks the key —
  `UserDefaults.bool(forKey:)` reports `false` for an unwritten key and
  would silently flip them. Unlike `glanceMetric` (account-dependent, so it
  lives in Claude's Provider Detail) these are provider-agnostic app chrome
  and surface in app-wide Settings via `MacChromeSettings`.
- "Open at Login" has **no preference key**: `SMAppService.mainApp.status`
  is the state, read live by `LoginItemManager`. A mirrored bool would drift
  the moment the user revoked it in System Settings.
- Stale snapshot (>30 min): widgets show a small "last updated" hint in the
  header trailing edge.
- Errors render inside the provider card, below the rows: raw endpoint body
  included, in `Theme.danger`. The one exception is a credential failure,
  which shows an actionable "Sign in again" prompt instead — see "Losing a
  login" above.

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
The icon it draws is `Shared/ProviderMark.swift` — an SF Symbol
(`sparkle`) on the app's own accent wash (or a filled accent tile,
`prominent: true`, for the Connect sheet header), also used directly by
Privacy & data and the Live Activity's compact/minimal islands. It is
deliberately **not** the provider's logo: Anthropic's trademark guidelines
reserve the Claude logo for uses approved in writing, and App Review
(4.1(c)/5.2.1) treats a third party's icon the same way — the app was
rejected once over brand use. The provider is identified by its *name*
alone, plain-text referential use, which is what both permit; no
third-party logo ships in the bundle (the GitHub mark in Settings is the
one exception, used as a link glyph to the app's own repository).
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

Bar/percentage color is one decision, `UsageWindow.tint`
(`Shared/WindowDisplay.swift`) — `Theme.danger` when the provider flags a
window `critical`/`exceeded` *or* `usedPct >= 80`, `Theme.accent`
otherwise. Two colors, nothing else, on purpose. Exposed as a static,
`tint(usedPct:severity:)`, so a caller that only carries those two values
(not a full `UsageWindow`) can still make the same call rather than
re-deriving a simplified copy — the Live Activity's `ContentState` does
exactly this (see `AIMeterWidgets/CLAUDE.md`).

## Localization

English source, Spanish complete; the device language picks automatically.
Three catalogs: `Shared/Localizable.xcstrings` (app + widget UI),
`Packages/UsageKit/Sources/UsageKit/Resources/Localizable.xcstrings`
(errors, via `String(localized:bundle:.module)`). Brand words (Claude,
Pro, Max, AIMeter) are never translated. Dates/currency use system
formatters. To add a language: add translations to both catalogs and the
region to the project's `knownRegions`.

## Conventions

- Swift 5.10+, async/await only (no Combine for new code).
- Keep files under ~300 lines; split by feature, not by type.
- Accessibility: every usage row is one combined VoiceOver element; bars
  are decorative (`accessibilityHidden`); icon-only buttons carry labels.
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
- Tests live in UsageKit (`swift test`); fixture
  `Tests/UsageKitTests/Fixtures/claude-usage-response.json` is a real
  captured response — mapping tests assert against it.
  `AIMETER_LIVE_TEST=1` enables an opt-in live test.

## Open source hygiene

- MIT license. README includes: undocumented-endpoint disclaimer, privacy
  /data-transparency section, build instructions with the user's own team
  ID, no affiliation with Anthropic.
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
  ever introduced.
- App Review posture. Version 1.0 was rejected under 4.1(c) (Copycats —
  the store subtitle named Claude) and 5.2.2 (Legal — "requests, displays,
  or distributes third-party account information"). The code-side answer,
  all of which must hold for every later submission: no third-party logo in
  the bundle (`ProviderMark`, not Anthropic's Claude/Claude Code icons);
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
- Never commit: xcuserdata, local xcconfig, credentials, tokens, or
  anything under `docs/design/reference/` (gitignored).
- App Store notes for the macOS background work: the `SMAppService` login
  item is reviewed, so it stays opt-in, off by default, visibly toggleable,
  and disclosed in `PrivacyView`. It needs no entitlement (unlike the
  deprecated `SMLoginItemSetEnabled`/`SMJobBless`) and works unsandboxed as
  the app is today. Hiding the Dock icon via `.accessory` is routine for
  menu-bar utilities and unproblematic. A global re-entry hotkey was
  rejected precisely because it would add an Accessibility/Input Monitoring
  permission and the review scrutiny that comes with it. Separately,
  `ENABLE_APP_SANDBOX = NO` is pre-existing and would have to change for
  Mac App Store distribution regardless of any of this.

## Workflow

- Data model follows reality: before changing endpoint-related code, run
  `Scripts/probe-usage-endpoint.sh` and check the captured fixtures. Never
  guess wire formats.
- Before large changes, propose the plan and wait for approval.
- Verify on both platforms: `xcodebuild` for macOS and iOS Simulator plus
  `swift test` in `Packages/UsageKit` must pass warning-free.
- Docs follow reality, same as the data model: any change that touches
  behavior, config, file layout, or a new feature's shape is not done
  until every doc that describes it is updated too — this file, the
  nested `AIMeter/CLAUDE.md` / `AIMeterWidgets/CLAUDE.md` /
  `Packages/UsageKit/Sources/UsageKit/Providers/Claude/CLAUDE.md`, and
  `README.md` for anything user-facing (features, setup steps, the
  architecture tree). A stale doc is a bug, not a follow-up — this file's
  own opening claim is that it's enough to rebuild the app from zero, and
  that stops being true the moment one of these drifts from the code.
