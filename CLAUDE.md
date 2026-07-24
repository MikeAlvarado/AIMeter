# AIMeter

Open source multiplatform app (iOS 17+ / macOS 14+, pure SwiftUI, no
dependencies, no server) that shows AI subscription usage and remaining
limits in the app, in widgets, and in the macOS menu bar. First provider:
Claude Pro/Max. The architecture is provider-agnostic so more AI providers
(Codex, Cursor, …) can be added as new sections later.

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
- Widget kinds: `AIMeterUsage` (the three-window widget) and
  `AIMeterSingleUsage` (single-window widget, user-configurable via
  WidgetKit's `AppIntentConfiguration`).

## Layout of the repo

```
Packages/UsageKit     local Swift Package, provider-agnostic, pure logic
  Core/               UsageProvider, UsageSnapshot, UsageWindow, SpendStatus,
                      UsagePace/PaceCalculator, UsageSample/RunOutPredictor/
                      ResetDetector/ThresholdDetector, UsageError (localized
                      via bundle: .module)
  Providers/Claude/   ALL Claude endpoint/OAuth specifics, isolated here
  Storage/            KeychainStore (accessGroup-aware) + SnapshotStore +
                      UsageHistoryStore (bounded per-window sample ring)
  Sources/UsageKit/Resources/Localizable.xcstrings   (package strings)
AIMeter/              multiplatform SwiftUI app (views + services)
  Services/           RefreshService, UsageModel, NotificationScheduler,
                      BackgroundRefresh (iOS) + macOS-only AppDelegate/
                      AppChrome (activation policy, hiding, reopen) and
                      LoginItemManager (SMAppService)
  Views/              dashboard/detail/settings/menu bar + macOS-only
                      MacChromeSettings (menu bar, hiding, startup)
AIMeterWidgets/       both widgets — AIMeterUsage (3-window) and
                      AIMeterSingleUsage (single window, AppIntents
                      configuration); renders snapshots; iOS: self-fetch
Shared/               AppConfig, Theme, components, formatting, preferences,
                      ProviderIdentityView (shared header), PrivacyInfo.xcprivacy,
                      Media.xcassets (Claude logos), Localizable.xcstrings
Scripts/              probe-usage-endpoint.sh + sample-response.json
docs/design/reference/  local-only reference screenshots (gitignored)
```

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
- App ↔ widget data flows only through the App Group `SnapshotStore`
  (JSON-encoded snapshot per provider ID). Widgets render the last
  snapshot; on iOS the widget may fetch for itself when the snapshot is
  older than the refresh cadence (credentials via the shared keychain
  access group), writing the result back to the store. On macOS the menu
  bar app feeds the widget (a sandboxed widget can't read Claude Code's
  credential file).
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

Credential sources:
- macOS: `ClaudeAutoCredentialSource` — read-only mirror of Claude Code's
  own login (Keychain item `Claude Code-credentials`, fallback
  `~/.claude/.credentials.json`); never refreshes those tokens (that would
  log out the CLI). Falls back to the app's own Keychain copy.
- iOS: `ClaudeKeychainCredentialSource` — the app owns its copy (from the
  in-app OAuth flow, or a pasted credentials JSON) and refreshes it.
  `RefreshService` migrates pre-sharing credentials into the shared access
  group once at init.

## Data-shaping rules (applied at fetch time, in this order)

1. Map `limits` → windows; unknown kinds are skipped (forward-compatible).
2. Scoped weekly windows share the weekly window's exact `resetsAt` (the
   endpoint reports microsecond-apart timestamps for what is one boundary).
3. `fillingMissingResets(from: previousSnapshot)` — weekly windows whose
   `resetsAt` came back null inherit the previous date advanced in whole
   7-day periods (weekly boundaries are fixed anchors, so this is truth,
   not a guess). Sessions only carry a still-future date: an idle session
   genuinely has no reset. Reported dates are never overwritten.

## Refresh & notification behavior

- `RefreshService.refresh()`: fetch → shape → save to store → record
  history → `WidgetCenter.reloadAllTimelines()` → reschedule notifications
  (resets + run-outs) → fire any early-reset alerts.
- iOS app: refresh on cold launch; on foreground, always reload widget
  timelines (covers WidgetKit's archived-render cache after app updates)
  and refresh if the snapshot is >60 s old; `BGAppRefreshTask` at the
  user-selected cadence (30 min / 1 h / 3 h, `RefreshCadence`) as
  best-effort backstop.
- macOS: `NSBackgroundActivityScheduler` (`UsageModel.rebuildRefreshSchedule`)
  at the cadence, with a 20 % tolerance, for as long as the app runs — which
  now includes running with no visible icons at all. Deliberately *not* a
  run-loop `Timer`: an app with no visible window is a prime App Nap
  target, and Nap throttles timers unpredictably. Nothing fires while the
  Mac sleeps, so `NSWorkspace.didWakeNotification` nudges
  `refreshIfStale(maxAge: cadence)` on wake — a no-op when the snapshot is
  still fresh, a catch-up fetch when it isn't.
- Widget timeline: single entry, `.after(interval)` where `interval =
  max(displayCadence, AppConfig.widgetRefreshFloor)` (30 min). The widget's
  reload interval is deliberately floored *independent of* the user's
  display cadence: WidgetKit budgets background refreshes (~a few dozen a
  day), so requesting every 15 min exhausts the budget and the system
  stops refreshing that widget — and then ignores even app-initiated
  `reloadAllTimelines()` until the budget replenishes (this is per widget
  *kind*, which is why a heavily-refreshed medium widget can freeze while
  the single-usage widget stays live). The app's foreground push covers
  freshness during active use. On iOS `getTimeline` self-fetches when the
  stored snapshot is older than that interval, via a short-timeout
  (`timeoutIntervalForRequest = 15`, `waitsForConnectivity = false`)
  URLSession so a slow request fails fast instead of wasting the refresh.
- Usage history: `UsageHistoryStore` (App Group) keeps a bounded,
  reset-aware ring of `(timestamp, usedPct)` samples per window — the
  extra data (beyond the single latest snapshot) the recent-rate run-out
  predictor needs. Recorded wherever a fetch persists a snapshot (the app
  refresh *and* the iOS widget self-fetch, so it stays continuous when
  only the widget runs); a used%-drop discards a kind's prior samples so a
  rate never spans a reset. Cleared on disconnect.
- Notifications are local only, all rescheduled/re-evaluated from scratch
  after every successful fetch, keyed by identifier prefix
  (`NotificationScheduler`). Two are *scheduled* to a future trigger:
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
  on every refresh while above) and re-arm after a reset. Each `smart`
  alert has one global toggle (near-limit adds a threshold); all off by
  default; toggles live in the App Group. Permission is handled honestly:
  a denied system permission snaps the toggle back off and shows a warning
  row with an "Open Settings" shortcut; authorization is re-checked on
  foreground. Detection-based alerts share the widget-self-fetch gap noted
  for history — a crossing the widget applies before the app refreshes is
  missed. Cancelled URL tasks are not surfaced as errors.

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
- Display prefs (App Group, shared with widgets): Remaining/Used,
  Relative/Absolute reset style (tap any reset line to toggle), appearance
  System/Light/Dark, refresh cadence, and `glanceMetric` — the one window
  shown by the two single-number surfaces with no room for a fixed
  three-slot layout: the macOS menu bar label and iOS's Lock Screen
  circular gauge. One shared preference drives both. Stored as a plain
  `UsageWindow.Kind` (not a fixed enum) so its option list scales with the
  account: Session and Weekly always, the per-model window (e.g. Fable on
  Max) whenever the account reports one, and Credits whenever the account
  has it enabled *and* `modelSlotFallback` isn't Hidden
  (`UsageSnapshot.glanceOptions`) — 2 to 4 choices, same live-options
  principle `UsageWindowOptionQuery` uses for the single-window widget.
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
  included, in `Theme.danger`.

## Screens

- **Dashboard**: floating gear + refresh buttons (refresh icon spins while
  busy; soft haptic on refresh start), small centered serif "AIMeter"
  title, then a section per provider: logo + name + Pro/Max pill (trailing)
  → card with the three windows, error, "Updated X ago". Disconnected state
  shows a Connect card.
- **Provider detail** (push): rate-limit rows; a **Forecast** card
  (`ForecastCard`) listing any window projected to run out early or an
  all-clear row; a "Third usage row" card with the Auto/Hidden/Credits
  pill (governs the third-slot fallback above, defaults to Auto) plus a
  "Show credit amounts" toggle (off by default) for the Credits row's
  money subtitle; a "Menu bar" pill on macOS / "Lock Screen widget" pill
  on iOS for `glanceMetric`, options read live from the snapshot; Spend
  and Extra usage cards (label/value rows, currency formatted); per-window
  reset notification toggles plus a **Smart notifications** card
  (`SmartNotificationTogglesCard`: global Near-limit warnings with a
  threshold slider, Limit reached, Run-out warnings, Early-reset alerts);
  iOS disconnect button. All of these are Claude-specific display
  prefs, so they live here rather than in the app-wide Settings screen — a
  future provider's own detail view would carry its own equivalents
  instead of sharing these.
- **Settings**: appearance / display mode / reset style pills, refresh
  cadence menu, per-window reset notification toggles + the Smart
  notifications card, a "Privacy & data" link, and an "Open Source" row
  (GitHub mark, opens the repo URL). iOS: sheet with Done; macOS: Settings
  scene (wrapped in a NavigationStack so the link can push), plus the
  macOS-only `MacChromeSettings` block — "Menu bar" (Show percentage),
  "Hiding AIMeter" (Hide Dock icon / Hide menu bar icon, with a warning row
  once both are hidden), and "Startup" (Open at Login, with a pending-approval
  row and a nudge when the Dock icon is hidden but the login item is off).
- **Privacy & data** (`PrivacyView`): private-by-default rows (on-device,
  Keychain, no tracking, and on macOS the opt-in login item), how connecting
  works (per platform), the exact OAuth scopes as chips + the two read-only
  endpoints called, and the independence/MIT footer. Every claim must stay
  true to the code.
- The GitHub mark is a bundled PNG (`Shared/Media.xcassets/GitHubIcon`,
  light/dark appearance variants — same mechanism as the app icon) —
  SF Symbols has no third-party brand glyphs. It is pre-colored per
  appearance (light accent `#D97757` / dark accent `#E08B6D`) rather than
  tinted via `.renderingMode(.template)` at runtime: a solid-black source
  PNG gets compiled by `actool` into a monochrome/alpha-mask rendition
  whose `.foregroundStyle` tinting was unreliable in practice, whereas a
  pre-colored RGBA source always compiles to a plain ARGB rendition (same
  as `ClaudeIcon`) and just displays as-is — no template step to trust.
- **Connect sheet**: pixel-Claude icon, explainer, "Open Claude Sign-In",
  paste field (accepts OAuth code or full credentials JSON), Connect —
  surfaces the connection error inline instead of dismissing on failure.
- **Landscape (iPhone)**: `verticalSizeClass == .compact` swaps the
  dashboard for a fullscreen card with the same stacked rows.
- **Widgets**:
  - `AIMeterUsage` (small & medium): header (logo + "Claude") + all three
    bars with reset lines; Lock Screen accessories (circular gauge,
    rectangular list, inline). Rectangular and inline show all three
    `WindowSlots`, credits included under the third-row fallback; the
    circular gauge has room for one number, so it shows whichever window
    `glanceMetric` points at (Provider Detail). Widget fonts are fixed
    sizes (12/11/9 pt) on purpose — text styles scale with Dynamic Type
    and overflow the fixed widget height on real devices. Rows sit in
    equal flexible slices so the layout fills any family height.
  - `AIMeterSingleUsage` (small only): shows exactly one window the user
    picks from the widget's own Edit Widget UI
    (`SingleUsageConfigurationIntent`, `AppIntentConfiguration`) —
    provider/window options are read live from the last stored snapshot
    (`UsageWindowOptionQuery`), including "Credits" when the fallback
    above is on and there's no real model window, so the list always
    matches what the account actually has instead of a name baked in at
    build time.
- **macOS menu bar**: header (logo + "Claude" + plan pill, via
  `ProviderIdentityView`) + divider, popover with the same rows,
  refresh/settings/quit. The label (`MenuBarLabel`) is a variable-value
  `gauge.with.needle` whose fill tracks the `glanceMetric` window's
  *displayed* percentage (so a "Remaining" reading never contradicts its own
  gauge), with the number spelled out beside it only when
  `menuBarShowsPercentage` is on. Either way the exact value stays in the
  `.help` tooltip and the accessibility label — icon-only mode must never be
  the only place the number lived. The whole status item disappears when
  `statusItemVisible` is off (`MenuBarExtra(isInserted:)`).
- **macOS hiding & re-entry** (`AppDelegate` + `AppChrome`, the project's
  only AppDelegate — SwiftUI has no scene hook for either concern):
  - `hideDockIcon` → `.accessory` activation policy, applied in
    `applicationWillFinishLaunching` so a hidden icon never flashes.
  - `.accessory` does **not** suppress `WindowGroup`'s auto-open (measured —
    the window is up by `applicationDidFinishLaunching`), so the delegate
    closes it explicitly, but *only* while `statusItemVisible` is true.
    With both icons hidden the dashboard is the app's sole affordance, so
    launching has to produce it or the app would be unreachable — that
    combination is the one case where a launch legitimately shows a window.
  - Re-entry when everything is hidden is **relaunching the app**
    (Finder/Spotlight/`open -a`), which fires
    `applicationShouldHandleReopen` — verified to arrive with no Dock icon
    and no status item, and without spawning a second instance. It reveals
    the dashboard without clearing the hidden prefs: needing to relaunch
    once shouldn't permanently undo the user's chosen chrome. There is no
    global hotkey, deliberately — it would cost an Accessibility/Input
    Monitoring TCC permission to guard a path that already works.
  - AppKit callbacks can't reach SwiftUI's `openWindow`, so the dashboard
    scene publishes it to `AppChrome.openDashboard` on appear — same
    bridging shape as `AppEnvironment.shared` for the refresh schedule.
    Dashboard windows are matched by the identifier SwiftUI derives from
    `WindowGroup(id:)` (`dashboard-AppWindow-…`) so the Settings window,
    also main-capable, is never mistaken for one.
  - **Quit still means quit.** Hiding changes only what is visible; the menu
    bar Quit button remains an unconditional `NSApp.terminate`.

## Design system (Shared/Theme.swift)

Warm, editorial, Claude-inspired. Terracotta accent `#D97757` (dark
`#E08B6D`), danger `#B3261E`/`#E5695E`, ivory background `#FAF9F5` (dark
`#262624`), card white/`#30302E`, track `#EDEAE1`/`#3E3D3A`, ink
`#1F1E1D`/`#FAF9F5`, secondary `#87867F`/`#9B9A93`. Serif is reserved for
the app title; monospaced digits for all percentages. Cards: 20 pt
continuous radius, 16 pt padding, capsule bars 6 pt tall. Elevation: soft
wide shadow (black 7 %, r16 y8) + tight contact shadow (4 %, r2 y1) on
cards and floating buttons. Assets: `ClaudeIcon` (starburst) for headers,
`ClaudeCodeIcon` (pixel creature) for the connect sheet; app icon has
light/dark/tinted iOS variants + rounded-rect macOS sizes.

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
for the menu bar which already brackets the section with its own) and
`DisconnectedPrompt` (the "Sign in to see your usage" text + Connect
button — dashboard and menu bar, `buttonLabel`/`verticalPadding`
parametrized per surface, caller still owns the wrapping container).

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
- Tests live in UsageKit (`swift test`); fixture
  `Tests/UsageKitTests/Fixtures/claude-usage-response.json` is a real
  captured response — mapping tests assert against it.
  `AIMETER_LIVE_TEST=1` enables an opt-in live test.

## Open source hygiene

- MIT license. README includes: undocumented-endpoint disclaimer, privacy
  /data-transparency section, build instructions with the user's own team
  ID, no affiliation with Anthropic.
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
