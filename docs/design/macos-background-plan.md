# macOS background & widget plan — analysis

> **Status update — implemented.** All five phases are built, both platforms
> build warning-free, and `swift test` passes (68 tests, 1 skipped — the
> opt-in live test). The two open empirical questions were resolved by
> measurement before the design was finalized; one of them **overturned the
> assumption in the analysis below**, which is recorded in "Verification
> results" at the end of this document. Read that section alongside §3 —
> where the two disagree, the measured behavior is what shipped.

Status of the original analysis: **analysis pass, no code written**. Branch `feature/macos-background-and-widget`
created off `main`. This document covers the three related requests as one
system: the Notification Center widget's freshness depends on the menu bar
app staying alive (#3), and the menu bar app staying alive with its icon
hidden is only usable day-to-day if the status item can still show useful
information at a glance (#2).

**Decisions confirmed (2026-07-24):** full Dock icon + status item hiding
is in scope for v1 (not deferred to a stretch phase); login item
(`SMAppService`) ships as part of this feature; the menu bar
percentage toggle surfaces in app-wide Settings, not Provider Detail; the
connected-state menu bar icon is an SF Symbol gauge with variable fill;
re-entry when both icons are hidden relies on relaunch-reopen only, no
global hotkey. These are folded into the sections below — see "Decisions
made" at the end for the full record and what still needs verifying
empirically during implementation.

## Baseline: what's actually there today

Read in full: `AIMeterApp.swift`, `Services/RefreshService.swift`,
`Services/UsageModel.swift`, `Services/BackgroundRefresh.swift`,
`Views/MenuBarView.swift`, `Views/SettingsView.swift`,
`Views/ProviderDetailView.swift`, `Views/ContentView.swift`,
`Shared/AppConfig.swift`, `Shared/PreferencesStore.swift`,
`Shared/WindowDisplay.swift`, `AIMeterWidgets/*.swift`, both
`.entitlements` files, both `Info.plist` files, and the relevant
`project.pbxproj` build settings.

Confirmed facts that shape everything below:

- **No `NSApplicationDelegateAdaptor` exists anywhere.** The macOS app is
  pure SwiftUI scenes (`WindowGroup` + `MenuBarExtra` + `Settings`) with no
  `AppDelegate`. Any activation-policy or reopen-handling code needs one
  added from scratch.
- **No `LSUIElement`, no activation-policy code, no sandbox.**
  `project.pbxproj` has `ENABLE_APP_SANDBOX = NO` for the `AIMeter` target
  (both Debug and Release) and nothing sets `LSUIElement`. Today the app
  launches with a regular Dock icon, appears in Cmd-Tab, and — because
  `WindowGroup` + regular activation policy auto-opens a window at launch —
  the dashboard window opens automatically every launch, in addition to
  the menu bar item.
- **The macOS refresh loop is a plain `Timer`.** `UsageModel.rebuildTimer`
  (`Services/UsageModel.swift:237-247`) creates a repeating `Timer` on
  `RunLoop.main` in `.common` mode. No `ProcessInfo.beginActivity`, no
  `NSBackgroundActivityScheduler`, no sleep/wake observers anywhere in the
  repo (`grep` for `NSWorkspace`, `willSleep`, `didWake`, `SMAppService` —
  zero hits).
- **The menu bar label has no icon today.** `MenuBarLabel`
  (`Views/MenuBarView.swift:10-22`) is `Text("\(pct)%")` when a window is
  available, and only falls back to `Image(systemName: "gauge.with.needle")`
  when there's *no* data. So "icon + percentage" as a mode doesn't
  currently exist — normal operation is percentage-only text. Building the
  requested toggle means deciding what the icon actually is (see §2).
- **`AIMeterWidgets` is one multiplatform `app-extension` target**
  (`project.pbxproj:145-151`), no `ENABLE_APP_SANDBOX` override (extensions
  are OS-enforced sandboxed regardless), sharing the same App Group +
  keychain-group entitlements as the app. `AIMeterWidgetsBundle` registers
  both `UsageWidget` (`.systemSmall`/`.systemMedium` on macOS) and
  `SingleUsageWidget` (`.systemSmall`, `AppIntentConfiguration`). Nothing
  iOS-only is required for macOS widget registration.
- **`RefreshService.refresh()` is shared, platform-agnostic** — it's what
  the menu bar timer, the iOS cold launch, and the iOS `BGAppRefreshTask`
  all call. `UsageModel.refreshIfStale(maxAge:)` (`UsageModel.swift:67-73`)
  is also already unconditional (no `#if os(iOS)`), so it's directly
  reusable for a macOS wake-triggered catch-up (§3) with no new plumbing.
- Minor aside, unrelated to this feature but noticed while reading: CLAUDE.md's
  "Refresh & notification behavior" section says the iOS background cadence
  is "15/30/60 min," but `RefreshCadence` in `PreferencesStore.swift:65-79`
  only defines 30 min / 1 hr / 3 hr. Worth a quick fix to CLAUDE.md
  independent of this feature — flagging, not fixing here.

---

## 1. Notification Center widget

**Already works — nothing to build for placement itself.** Once a
WidgetKit extension ships embedded in a macOS 11+ app (this one targets
14.0) and is code-signed, the system automatically offers it in the widget
gallery (Notification Center panel, and macOS 14+ desktop widgets) — this
is OS-level `pluginkit` discovery, not something the app registers via API
or entitlement. `AIMeterWidgetsBundle` + `UsageWidget`'s
`.systemSmall/.systemMedium` families on macOS (`UsageWidget.swift:67-73`)
is already sufficient. The only real-world gotcha is local-dev: a freshly
built widget sometimes doesn't appear in the gallery until the containing
app has been launched at least once post-install, which is an environment
quirk, not a product gap.

**Action for this item: verify once by running the app, then document.**
No code change. I'd fold this into Phase 1 below as a manual check.

### What feeds it, and the freshness contract

Per `AppConfig.swift` and `UsageWidget.swift`, on macOS:

- `UsageTimelineProvider.getTimeline` reads `SnapshotStore` and does
  **not** self-fetch (`WidgetRefresher.fetchIfStale` is behind `#if
  os(iOS)` in both `UsageWidget.swift:35-42` and `SingleUsageWidget.swift`).
  The `#if os(macOS)` comment in `AppConfig.swift:8-11` ("the menu bar app
  feeds the widget instead") is accurate and enforced by the code, not just
  documented intent.
- The widget's own timeline re-run interval is `max(refreshCadence,
  widgetRefreshFloor)` — 30 min to 3 hr. Each re-run just re-reads
  whatever is currently in `SnapshotStore`; if the menu bar app hasn't
  refreshed, the widget re-serves the same stale data under a new
  `.after(interval)` policy. There is no upper bound — it can be stale for
  days.
- `UsageSnapshot.isStale` (`WindowDisplay.swift:50-52`, 30 min threshold)
  drives a small "updated Xh ago" hint rendered by `WidgetHeader`
  (`UsageWidgetViews.swift:44-69`), shared code so it applies to the
  macOS widget too. This is the *only* signal the user gets that the
  numbers are frozen — there's no error state, no "app not running"
  indicator, just a growing relative-time label.

**Stated freshness contract:** on macOS, the widget shows exactly what the
menu bar app last fetched, plus an increasingly stale-looking timestamp
hint past 30 minutes. If the menu bar app is quit, the widget freezes at
its last snapshot indefinitely — it will keep re-rendering on schedule
(so it's not "broken" from WidgetKit's perspective) but the data never
changes. This is precisely why item 3 matters: today, quitting the menu
bar app silently breaks the widget's usefulness with only a subtle
timestamp as a clue.

---

## 2. Optional percentage in the menu bar

### Where the preference lives

Same place as every other display preference: `Preferences` /
`PreferencesModel` in `Shared/PreferencesStore.swift`, App Group-backed,
next to `glanceMetric`. New field, e.g.:

```swift
var menuBarShowsPercentage: Bool = true   // default true — preserves current look
```

Storage key `pref.menuBarShowsPercentage`. **Migration detail that
matters:** `showCreditsAmount` (the one existing plain `Bool` pref) uses
`defaults.bool(forKey:)` directly, which defaults to `false` when the key
is absent. That's wrong for this pref — we want existing installs to keep
today's behavior (percentage shown) by default, so `Preferences.load`
needs the presence-check pattern already used for the enum prefs:

```swift
if defaults.object(forKey: Keys.menuBarShowsPercentage) != nil {
    prefs.menuBarShowsPercentage = defaults.bool(forKey: Keys.menuBarShowsPercentage)
}
```

(struct default `true` covers first-run and pre-upgrade installs alike).

### Where it surfaces in UI — resolved: app-wide Settings

`glanceMetric` (which window the label shows) lives in Provider Detail's
"Menu bar" card because it's account-dependent (its option list comes
from `UsageSnapshot.glanceOptions`). "Show percentage or just an icon" has
no such dependency — it's pure menu bar chrome — so it surfaces in a new
macOS-only section of `SettingsView.swift`, alongside the future
Dock-icon/status-item/login-item toggles from §3 (all of these are the
same category of thing: "how does this app's chrome behave," not
"what does this provider report"). This does mean menu bar configuration
is now split across two screens (glanceMetric in Provider Detail, display
mode in Settings) — accepted tradeoff, matches the architectural
boundary CLAUDE.md already draws between provider-specific and app-wide prefs.

### What the label becomes in each mode

Today there is no real "icon" — connected state is percentage-only text.
To make "icon-only vs. icon+percentage" a real toggle, an icon needs to
exist in the connected state too. Options:

- **SF Symbol `gauge.with.needle` with `variableValue:`** —
  `Image(systemName: "gauge.with.needle", variableValue: pct / 100)`
  renders the gauge partially filled to match usage, so icon-only mode
  still conveys *something* at a glance instead of being a static glyph.
  Zero new assets, matches system menu-bar icon conventions (monochrome,
  template-rendered automatically).
  - Update: `MenuBarLabel` gains `HStack { icon; if showsPercentage { Text(...) } }`.
- **Claude mark as a template asset** — would need a new monochrome PNG
  in `Shared/Media.xcassets` (menu bar icons must be template/monochrome,
  unlike the colored `ClaudeIcon` used elsewhere) and doesn't convey usage
  level the way a variable gauge does.

**Resolved: SF Symbol option.** No new assets, and the variable fill is a
genuinely nice touch consistent with "at a glance" — it also reads
sensibly as the icon shown when the status item itself would otherwise be
invisible in icon-only mode.

### Narrow menu bars / tooltip / accessibility

- `MenuBarLabel`'s text isn't currently `.monospacedDigit()` despite
  CLAUDE.md's design-system rule ("monospaced digits for all
  percentages") — small pre-existing gap, worth fixing alongside this
  change since the file's being touched anyway.
- Icon-only mode should still carry the number somewhere non-visual:
  `.help("Claude session: 42% used")` on the label view (SwiftUI's
  tooltip modifier, should propagate through `MenuBarExtra`'s label —
  needs empirical confirmation, first thing to check when implementing)
  and an explicit `.accessibilityLabel` so VoiceOver announces the value
  instead of just "gauge with needle."

### Files/symbols touched

- `Shared/PreferencesStore.swift` — new field, key, migration, `PreferencesModel` property.
- `AIMeter/Views/MenuBarView.swift` — `MenuBarLabel` redesign (icon + conditional text, tooltip, a11y label, monospacedDigit fix).
- `AIMeter/Views/SettingsView.swift` — new toggle UI (new macOS-only section).
- CLAUDE.md — "macOS menu bar" bullet in Screens, "Display prefs" bullet in Presentation rules.

No entitlement changes, no new system permissions. Independently
shippable and low-risk.

---

## 3. Keep running with the icon hidden

### Disambiguating "icon"

Two independent things called "the icon," confirmed via `grep` that
neither is currently touched anywhere in the app:

- **(A) The menu bar status item** — the `MenuBarExtra` content itself
  (icon/percentage from §2). This is the app's *only* current UI entry
  point besides the Dock icon.
- **(B) The Dock icon / activation policy** — `NSApplication.ActivationPolicy`,
  today implicitly `.regular` (Dock icon, Cmd-Tab entry, auto-opens the
  dashboard window at launch). Controlled via `LSUIElement` in Info.plist
  or `NSApp.setActivationPolicy(_:)` at runtime.

**Resolved: both (A) and (B) are hideable, independently, in v1.** Two
separate prefs, `statusItemVisible: Bool = true` and
`hideDockIcon: Bool = false` — both default to today's behavior for
existing installs. This is the harder version of the feature: with both
hidden (e.g. after a login-item auto-launch where the user previously set
both to hidden), there is genuinely no visible UI at all until something
brings it back.

### The lockout trap — resolved to relaunch-only

Concrete re-entry paths considered:

1. **Relaunch the `.app` bundle** (Finder/Spotlight/Dock recents). Free,
   standard macOS pattern. **Chosen as the sole mitigation.**
2. **Global hotkey.** Rejected for v1 — needs Accessibility/Input
   Monitoring TCC permission, a materially heavier privacy prompt with
   real App Review scrutiny, to guard against a scenario (relaunch not
   working) that hasn't been confirmed to actually occur.
3. **Opening from the widget.** Free secondary path (WidgetKit's default
   tap already activates the containing app) — worth wiring but not a
   substitute for (1) since it requires a widget to be placed at all.

**This makes path (1) load-bearing, not just a nice-to-have**, and it
rests on one thing I flagged as uncertain and could not verify by reading
code: whether `applicationShouldHandleReopen(_:hasVisibleWindows:)` (or an
equivalent reopen signal) reliably fires when an already-running
`.accessory`-policy app with no Dock icon is relaunched via
Spotlight/Finder. **This needs to be the first thing built and manually
tested in Xcode in phase 4**, before anything else in that phase, because
if it doesn't fire reliably, relaunch-only isn't a safe sole mitigation
and the hotkey option would need to be revisited before shipping — cheaper
to find out on day one of phase 4 than after it's built out.

**Design decision for the reopen handler itself:** relaunching should
reveal the UI (open the dashboard window, bring it to front) as a
one-time action, **without** silently flipping the persisted
`statusItemVisible`/`hideDockIcon` preferences — the user's chosen chrome
state should survive a relaunch; "I had to relaunch once" shouldn't
permanently undo "hide everything." The window opened by reopen can be
closed again afterward and the icons stay however the user last set them.

**Implementation note (not a decision, just a heads-up for phase 4):** the
reopen handler lives in `AppDelegate`, which has no direct access to
SwiftUI's `\.openWindow`/`\.openSettings` environment actions. This
codebase already has exactly this bridging problem solved once —
`AppEnvironment.shared` (`UsageModel.swift:251-256`) is a weak static
reference that lets the non-SwiftUI `Timer` closure reach the live
`UsageModel`. The same pattern (a small static holder populated from a
scene's `.onAppear`/environment, read from `AppDelegate`) is the
straightforward way to let reopen trigger `openWindow`. Flagging so it
isn't rediscovered as a surprise mid-implementation.

### Persistence across reboot — login item

Without a login item, hiding the Dock icon actively makes the app *harder*
to start after a reboot (no Dock icon to click, nothing auto-launches, and
until it's running there's no status item either) — this genuinely needs
`SMAppService` to be part of the same feature, not a follow-up, or the
Dock-hiding toggle is close to a trap in its own right. Confirmed
available: `ServiceManagement` framework, macOS 13+ (`SMAppService`),
no special entitlement required (unlike the deprecated
`SMLoginItemSetEnabled`/`SMJobBless`), works unsandboxed exactly as this
app is today.

- Opt-in only, off by default (`pref.launchAtLogin`, `false`) — never
  auto-register silently, matches App Review expectations and just good
  practice.
- `SMAppService.mainApp.register()`/`.unregister()`, called from a
  Settings toggle.
- No modal permission prompt exists for this API — instead macOS silently
  adds the entry to System Settings → General → Login Items & Extensions
  and shows a one-time, non-blocking notification banner the first time.
  The thing to actually handle is `SMAppService.mainApp.status`:
  `.requiresApproval` means the entry exists but is pending user approval —
  the app should detect this and show an in-app hint with a settings-pane
  deep link, exactly the existing pattern in `NotificationTogglesCard`
  (`ProviderDetailView.swift:386-405`, `notificationSettingsURL`) for
  denied notification permission. Same shape, different pane identifier
  (`x-apple.systempreferences:com.apple.LoginItems-Settings.extension`).
- `PrivacyView` should disclose the login item once it exists — CLAUDE.md's
  rule that "every claim must stay true to the code" applies here.

### Refresh behavior while headless

- **App Nap:** an `.accessory`-policy app with no visible/key window is a
  prime App Nap target. A `Timer` firing every 30–3600 s under Nap can be
  throttled/coalesced by the system in ways that undermine the "keep
  refreshing reliably" promise this whole feature is for. Recommend
  swapping the raw `Timer` in `UsageModel.rebuildTimer` for
  **`NSBackgroundActivityScheduler`** — Apple's purpose-built API for
  exactly this (periodic maintenance work, App Nap-aware, power-state
  aware, coalesced with other system activity, tolerant of a scheduling
  window rather than an exact instant). This is a self-contained swap
  independent of the Dock-icon/login-item work and improves reliability
  even if those never ship — recommend doing it regardless (see
  "Decisions made" at the end).
- **Sleep:** a `Timer` (or `NSBackgroundActivityScheduler`) simply doesn't
  fire while asleep. On wake, a repeating `Timer` whose fire date has
  passed fires once immediately, then reschedules from "now" — so a
  6-hour sleep across a 30-min cadence produces one catch-up fire on wake,
  not 12 queued ones. This is already correct, not broken, today.
- **Explicit wake catch-up recommended anyway**, for snappiness rather
  than correctness: observe `NSWorkspace.shared.notificationCenter` for
  `NSWorkspace.didWakeNotification` and call the *already existing*
  `UsageModel.refreshIfStale()` (`UsageModel.swift:67-73`, already
  platform-agnostic, already used by iOS's foreground handler in
  `ContentView.swift:36-43`). Zero new plumbing needed — just wiring the
  observer.

### Quit vs. hide — explicit invariant

`MenuBarView`'s "Quit" button (`NSApp.terminate(nil)`,
`MenuBarView.swift:60-62`) is a real, unconditional quit today and **must
stay that way** — hiding the Dock icon changes only what's visible, never
what "Quit" does. No hide-to-tray reinterpretation, no scope creep here;
stating this explicitly so it's not accidentally blurred during
implementation.

### Files/symbols touched

- `AIMeter/AIMeterApp.swift` — needs a `NSApplicationDelegateAdaptor`
  (none exists today) to set activation policy before first paint (avoids
  an icon flash) and to implement `applicationShouldHandleReopen`; the
  `MenuBarExtra` scene's initializer changes to
  `MenuBarExtra(isInserted: $prefs.statusItemVisible) { ... } label: { ... }`
  (macOS 13+ API) so `statusItemVisible` actually controls presence, not
  just content.
- New `AppDelegate` (new file, e.g. `AIMeter/Services/AppDelegate.swift`),
  macOS-only — activation policy at launch, `applicationShouldHandleReopen`,
  and the `AppEnvironment`-style bridge noted above to trigger `openWindow`
  from a non-SwiftUI context.
- New `AIMeter/Services/LoginItemManager.swift` (or similar) wrapping
  `SMAppService`.
- `Shared/PreferencesStore.swift` — `hideDockIcon: Bool = false`,
  `statusItemVisible: Bool = true`, `launchAtLogin: Bool = false`, keys +
  migration (presence-check pattern again, all defaulting to today's
  behavior so existing installs are unaffected).
- `AIMeter/Services/UsageModel.swift` — swap `Timer` for
  `NSBackgroundActivityScheduler` in `rebuildTimer`; add
  `NSWorkspace.didWakeNotification` observer calling `refreshIfStale()`.
- `AIMeter/Views/SettingsView.swift` — new macOS-only section: "Show
  percentage" (§2), "Hide Dock icon," "Hide menu bar icon," "Open at
  Login" toggles, with a `.requiresApproval` hint row for the login item
  and an inline nudge ("you'll need to relaunch AIMeter manually after
  restarting" or similar) when Dock/status-item hiding is on but the
  login item is off.
- `AIMeter/Views/PrivacyView.swift` — disclose the login item once it exists.
- Open question to resolve first in Xcode, not resolvable by reading code
  alone: whether `WindowGroup`'s auto-open-at-launch is suppressed simply
  by `.accessory` policy (common claim in menu-bar-app patterns, matches
  my understanding of `.accessory` semantics) or needs an explicit
  "close the auto-opened window" step in the delegate. Same category of
  risk as the reopen-event question above — both get resolved by the same
  round of manual testing at the start of phase 4.

### App Store submission concerns (explicitly asked for)

- `ENABLE_APP_SANDBOX = NO` today is **pre-existing and unrelated to this
  feature** — sandboxing would be mandatory for Mac App Store distribution
  regardless of anything here. Flagging so it isn't mistaken for something
  this feature introduces or should fix.
- `SMAppService` login items are explicitly reviewed by App Review —
  mitigated by being opt-in, off by default, visibly toggleable, and
  disclosed in `PrivacyView`. No known blocker under those conditions.
- A global hotkey (if ever pursued for full status-item hiding) needs
  Accessibility/Input Monitoring TCC permission — a materially heavier
  privacy surface and review scrutiny. This is the concrete reason to
  deprioritize it.
- Hiding the Dock icon via `.accessory` policy by itself is common and
  unproblematic for App Store apps (menu-bar-only utilities ship
  routinely).

---

## Phased plan

Each phase is independently shippable and testable; later phases build on
earlier ones but don't require them to have shipped to be individually
valuable.

1. **Verify Notification Center placement (no code).** Build, run,
   confirm both widgets appear in the macOS widget gallery. Document the
   freshness contract from §1 in CLAUDE.md. Zero risk.
2. **Menu bar percentage toggle (§2).** New pref + migration, `MenuBarLabel`
   redesign (icon + conditional text + tooltip + a11y), toggle UI. No
   entitlements, no new permissions. Fully independent of phases 3–5.
3. **Background-reliable refresh (§3, reliability half only).** Swap
   `Timer` → `NSBackgroundActivityScheduler`; add
   `NSWorkspace.didWakeNotification` → `refreshIfStale()`. No UI, no new
   prefs, no user-visible change except better reliability. This is a
   prerequisite for phase 4 to actually deliver on "keep refreshing" once
   the Dock icon (and its implicit "is this thing still running"
   affordance) goes away — do this before phase 4, not after.
4. **Hide Dock icon + status item, and re-entry (§3, activation-policy
   half — full scope, both icons).** Start with the two empirical
   questions (reopen-event delivery for an already-running accessory app,
   and whether `.accessory` policy alone suppresses `WindowGroup`'s
   auto-open) *before* building the rest of the phase — both get answered
   by the same short round of manual testing in Xcode, and the outcome
   (especially of the first) determines whether relaunch-only is actually
   safe as the sole re-entry path or whether the hotkey option needs to
   come back on the table. Then: new `AppDelegate`, `hideDockIcon` +
   `statusItemVisible` prefs + Settings toggles,
   `MenuBarExtra(isInserted:)` wiring, `applicationShouldHandleReopen` +
   the environment-action bridge. Ship after phase 3 so refresh
   reliability is already solid before removing every visible reassurance
   that the app is still running.
5. **Login item (§3, `SMAppService`).** `launchAtLogin` pref + toggle +
   `.requiresApproval` hint row + `PrivacyView` disclosure, plus the
   inline "you'll need to relaunch manually after a restart" nudge when
   icons are hidden and this is off. Closely coupled to phase 4 (hiding
   both icons without a login item is close to a trap across reboots) —
   kept as its own commit for isolated testing/rollback, but the two
   should land together in practice.

---

## Decisions made (2026-07-24)

1. **§2 placement:** app-wide Settings, new macOS-only section — not
   Provider Detail.
2. **§2 icon:** SF Symbol `gauge.with.needle` with `variableValue:` fill.
3. **§3 scope:** both the Dock icon and the status item are independently
   hideable in v1 (`hideDockIcon`, `statusItemVisible`), not deferred.
4. **§3 login item:** `SMAppService` support ships as part of this
   feature, not deferred.
5. **§3 re-entry mitigation:** relaunch-only, no global hotkey. This is
   now the single point of failure for getting back into a fully-hidden
   app, so phase 4 starts by empirically verifying the reopen-event
   behavior in Xcode before building anything else — see the
   "Implementation note" and phase 4 description above. If that
   verification comes back negative, this decision needs revisiting
   before shipping phase 4, not after.

**Carried over without a question, since it's a pure internal
improvement with no visible behavior change or apparent downside:** phase
3 (`NSBackgroundActivityScheduler` swap + wake-triggered
`refreshIfStale()`) proceeds regardless of anything else, per the
original recommendation. Flag now if that's not wanted.

---

## Verification results (measured, not assumed)

Both phase-4 unknowns were tested against a real build before the design
was finalized. Method: the built `.app` copied aside with a distinct bundle
identifier and ad-hoc re-signed, so LaunchServices treated it as its own
app and the test couldn't be confounded by another running instance (the
first attempt *was* — an unrelated Xcode debug session held the real bundle
ID and swallowed the reopen event). Preferences were injected per-run via
`NSArgumentDomain` (`-pref.hideDockIcon YES`), which a suite-backed
`UserDefaults` reads, so no persistent preference of the user's was
touched.

**1. Does `applicationShouldHandleReopen` reach a hidden accessory app?
YES.** Relaunching an already-running `.accessory` app with no Dock icon
via `open -a` fired the delegate, in the same process — no second instance
spawned. Relaunch-only re-entry is sound, and the global hotkey stays
unnecessary (decision 5 holds).

**2. Does `.accessory` suppress `WindowGroup`'s auto-open? NO — the
analysis above guessed wrong.** The dashboard window is present and visible
by `applicationDidFinishLaunching` even under `.accessory`. (An initial run
appeared to show the opposite; that was the confounded run from the same
bundle-ID collision, and it did not reproduce once isolated.) The app
therefore closes the window explicitly rather than relying on the policy.

That correction forced a design decision the original plan didn't
anticipate: **suppressing the launch window is conditional on the status
item being visible.** With both icons hidden the dashboard is the app's only
affordance, so a launch has to produce it — otherwise launching a
fully-hidden AIMeter would do nothing observable, which is the very lockout
the whole re-entry design exists to prevent. Measured behavior, all three
cases confirmed:

| `hideDockIcon` | `statusItemVisible` | Window at launch |
| --- | --- | --- |
| on | on | closed (menu-bar-only app) |
| on | off | **kept** — the only way to reach the app |
| off | either | unchanged from today |

The cost is that "hide everything + open at login" shows a window each
login. That is the deliberate trade: annoying beats unreachable, and it's
deterministic rather than resting on a heuristic for "was this launched by
launchd or by a person."

### Deviations from the plan as written

- **No `launchAtLogin` preference key.** The plan listed one; the
  implementation has none. `SMAppService.mainApp.status` *is* the state, and
  a mirrored bool in the App Group would go stale the moment the user
  revoked the item in System Settings. `LoginItemManager` reads the live
  status instead, and distinguishes `.enabled` from `.requiresApproval` so a
  pending item doesn't read as a working one.
- **Menu bar gauge follows the *displayed* percentage**, not raw usage, so a
  "Remaining" reading of 58 % shows a 58 %-full gauge instead of
  contradicting its own label.
- **A shared `Preferences.bool(_:_:default:)` helper** was added rather than
  open-coding the presence check per pref — the plan called out the
  `UserDefaults.bool(forKey:)`-returns-false trap for one preference, and
  three of them needed it.

### Not verified automatically

- **The `.help` tooltip on the menu bar label.** Asserting it renders
  through `MenuBarExtra`'s label needs a pointer hovering a real status
  item; `osascript` lacks Accessibility permission in this environment. The
  `.accessibilityLabel` carries the same string regardless, so the value is
  never *only* in the tooltip — but if the tooltip turns out not to appear,
  that's a cosmetic gap to close, not a data-loss one.
- **Actual `SMAppService` registration.** Exercising it would have added a
  real login item to this machine, so the code path is compiled and
  reviewed but not run. Worth a manual pass: toggle Open at Login, confirm
  the entry appears in System Settings → General → Login Items, confirm the
  pending-approval row behaves, then toggle it back off.
