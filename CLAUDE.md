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
  providerID, a user-editable `displayName`, and `credentialStrategy`:
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
Code on another machine, a second device the same credentials JSON was
pasted into) leaves AIMeter's copy invalid; a password change or global
sign-out does the same. From then on every refresh fails identically and
the account silently freezes at its last snapshot.

- `UsageError.requiresReauthentication` marks the three failures no retry
  can fix (`notAuthenticated`, `tokenExpired`, `credentialsNotFound`);
  `UsageModel.AccountUsage.needsReauthentication` carries it to the UI,
  which swaps the raw endpoint message for a "Sign in again" prompt
  (`UsageStatusFooter(reauthenticate:)`). Raw bodies are still shown for
  every other error — see the typed-errors rule above; this is the one case
  where the raw text ("The provider rejected the credentials") is faithful
  and useless at the same time.
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
  Code's.
- The `planName` write-back in `ClaudeProvider` re-reads the credential
  source before saving instead of persisting the value the fetch started
  with. It only owns `subscriptionType`; saving the whole stale value could
  put an already-consumed refresh token back over a freshly rotated one —
  one of the ways an account breaks like this in the first place, since the
  iOS widget refreshes against the same shared Keychain item as the app.

## Refresh & notification behavior

- `RefreshService` is scoped to one `ConnectedAccount`
  (`init(account:)`) — `UsageModel` holds one instance per registered
  account (`private var services: [String: RefreshService]`) plus
  `accounts: [AccountUsage]` (account + its own snapshot/error/isRefreshing).
  `RefreshService.refresh()`: fetch → shape → save to store (keyed by that
  account's `accountID`) → record history → `WidgetCenter.reloadAllTimelines()`
  → reschedule that account's notifications (resets + run-outs) → fire any
  of that account's early-reset alerts. `UsageModel.refreshAll()` fans this
  out to every account concurrently via `withTaskGroup` — safe, since each
  account uses a different bearer token (no shared rate-limit bucket) and
  `UsageModel` is `@MainActor`-isolated, so the per-account bookkeeping
  each task does on completion is serialized even though the network
  requests themselves run in parallel. `refresh(accountID:)` refreshes just
  one (Provider Detail's own pull-to-refresh, one account at a time).
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
  "Peak hours" below), which depends only on a fixed weekday schedule and
  never on what a fetch returns, so it's rescheduled once at
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
  Claude-wide policy, not tied to a specific login. All off by default;
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
  exactly as it always has. Permission is a single OS-level toggle, not
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
- Peak hours: Anthropic has repeatedly introduced/reverted a policy where
  Claude session usage burns faster during documented weekday-morning
  windows (currently 5-11 AM PT; the exact hours have changed before and
  will again). `docs/design/peak-hours-investigation.md` confirms
  empirically — by diffing a live response captured inside the window
  against one captured outside it — that neither `/api/oauth/usage` nor
  `/api/oauth/profile` carries any peak-related field in either state, so
  there is nothing server-side to key off. `PeakCalculator` (UsageKit
  core, pure — `isPeak(at:schedule:)` / `nextTransition(after:schedule:)`)
  computes it instead, entirely on-device and with zero network cost,
  since peak state is a deterministic function of the clock. The
  mechanism is provider-agnostic; the concrete PT/weekday/5-11 values are
  Claude's own policy and live in `ClaudePeakSchedule`
  (`Providers/Claude/`) alongside a `lastVerified` date — the honesty
  mechanism for a policy known to change: it's surfaced in the UI
  (Provider Detail's "Peak hours" card) so a schedule that goes stale
  between releases is never presented as live truth. Deliberately
  hardcoded and release-updated rather than remote-fetched (this project
  has no server, by design) or user-editable (most users can't verify a
  schedule they'd hand-edit).
  - The named-timezone rule is load-bearing: `PeakCalculator` evaluates
    weekday/hour through `TimeZone(identifier: "America/Los_Angeles")` —
    never `TimeZone.current` — so the result is identical regardless of
    the device's own timezone, and DST is handled for free (a named zone
    carries its own historical/future transition rules; a fixed UTC
    offset would silently break twice a year). `PeakCalculatorTests`
    checks both DST transition dates and an explicit
    device-timezone-independence case.
  - `ClaudePeakStatus` (Shared/) wraps the calculator with the copy
    ("Peak hours now" / "Off-peak now", next-transition countdown,
    `lastVerified` label) shared by Provider Detail, the menu bar, and
    both widget headers.
  - Glance surfaces, all zero-network since peak is time-derived: Provider
    Detail shows a dedicated card; the macOS menu bar popover header shows
    a bolt badge, while the status item itself (`MenuBarLabel`) folds peak
    into the tooltip/accessibility text only, not a second glyph, to
    avoid disturbing its carefully-tuned single gauge; both widgets
    (`AIMeterUsage` header, `AIMeterSingleUsage` header when the picked
    window is `.session`) show the same badge. Widget timelines add a
    second `TimelineEntry` dated exactly at `nextTransition` (when it
    falls before the next scheduled reload) so WidgetKit flips the badge
    on its own at the right wall-clock moment — no extra refresh, no
    widened refresh budget. Lock Screen accessories deliberately don't
    show it (too cramped, lowest value).
  - Notifications: an off-by-default `peak.` family
    (`NotificationScheduler.reschedulePeakNotifications`) — "Peak hours
    started"/"ended", 10 recurring `UNCalendarNotificationTrigger`s (5
    weekdays × start/end) with `DateComponents.timeZone` pinned to the
    schedule's zone for the same DST-correctness reason as the calculator.
    Deliberately **not** part of the "reschedule every fetch" convention
    the other families follow: this schedule never depends on a fetched
    snapshot, so `UsageModel` reschedules it once at init and whenever the
    toggle changes, not on every refresh.
- Display prefs (App Group, shared with widgets): Remaining/Used,
  Relative/Absolute reset style (tap any reset line to toggle), appearance
  System/Light/Dark, refresh cadence, and `glanceMetric` — the one window
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
