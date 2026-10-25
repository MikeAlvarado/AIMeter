## Widgets

The gallery lists them in `AIMeterWidgetsBundle` order: `AIMeterUsage`
first (the account's limits, the one most people place), then
`AIMeterSingleUsage`, then `AIMeterAllAccounts`. Display names are
feature names ("Usage Limits", "Single Limit", "All Accounts"), never a
provider's — the gallery is a screenshot-able surface like any other.

Every header draws the account's chosen glyph (`ConnectedAccount.icon`,
see "Design system" in the repo-root CLAUDE.md): `AIMeterAllAccounts`
has the `ConnectedAccount` in its rows, and the two configured widgets
read it into their entries (`accountIcon`) through
`WidgetAccountFallback.icon(for:)` — the registry lookup next to the name
— so a change in the app shows on the next reload the app triggers.

What this extension shares with the Watch's complications lives in
`WidgetsShared/`, synced into both: `UsageAccountConfigurationIntent`
(the account picker and its `UsageAccountOption` entity),
`WidgetAccountFallback` (the registry lookups: the first account, the
configured one, a name, an icon), `AccessoryUsageViews.swift` (the
circular, rectangular and inline accessory views, `#if !os(macOS)`, and
the Watch's corner one) and `WidgetPlaceholders.swift`
(`UsageSnapshot.sample`). See `AIMeterWatch/CLAUDE.md`.

`AIMeterUsage` and `AIMeterSingleUsage` are `AppIntentConfiguration`, so
every placed instance — Home Screen or Lock Screen — has its own
independent account selection; an empty `AccountRegistryStore` (nothing
connected yet, or the app hasn't run its one-time migration since the
last update) falls back to a single synthetic "claude" option in both
pickers rather than showing an empty list. That option is never the
*default*, though (`defaultResult()` is nil while nothing is
connected): a first connection on a clean install gets a UUID, so a
widget placed before it that kept "claude" would stay empty until
edited. A widget whose selection is that sentinel with no account of
that id (one placed before this rule) shows the first connected account
instead (`WidgetAccountFallback.resolve(configured:name:)`). `AIMeterAllAccounts` (see
below) has no account picker; its one choice is its layout. Both configured widgets share the same
nil-configuration fallback (the timing edge case right after a widget is
first placed, before the intent's default has resolved) through
`WidgetAccountFallback.resolve()` — the first connected account, or the
legacy sentinel if none — rather than each re-deriving it.
- `AIMeterUsage` ("Usage Limits" in the gallery; small & medium,
  `UsageAccountConfigurationIntent`): header (mark + the picked
  account's nickname) over the account's `WindowSlots`. The small family
  is the app's account card in a small square (`SystemUsageView`, 4.0;
  see "Account cards" in the repo-root CLAUDE.md): the window
  `AccountCardLayout` puts first as the protagonist (`WidgetHero`: its
  short name, the figure at 28 pt with "%", its reset beside it as a bare
  value with the reset glyph, the live countdown under a day, and a 7 pt
  bar) and up to two others as one line each in shared columns
  (`WidgetCompactRows`: name, a 4 pt bar, the figure); the medium
  family (`MediumUsageView`, its own file) lays them out as columns —
  window name, a big figure with the display mode as a one-word suffix
  ("42% left" / "42% used", `DisplayMode.suffix`), the bar, and under it
  the reset line, the optional credits amount, or "Not available" for a
  slot the account doesn't report (`--` where the figure would be).
  One to three columns, whatever the slots yield (a Codex Free account
  has one, its month; Copilot's quotas make three); the figure drops from
  28 pt to 22 pt for three so "100% left" still fits. Column and row
  names are the window's own (`UsageWindow.shortTitle`: "Month" for a
  30-day week, "Premium" for a quota). Each column shows
  its own reset line — the grouped-reset rule (`WindowSlots.showsReset`)
  is for stacked rows, where one line can sit under a group; side by
  side, a column with nothing under its bar reads as unfinished. The
  value row has a fixed height so the bars align across columns whatever
  the glyphs above them. The medium header also carries the plan pill
  (`WidgetHeader(planName:)`); the small one leaves it out for room.
  Lock Screen accessories (circular gauge, rectangular list, inline;
  the views in `WidgetsShared/AccessoryUsageViews.swift`, which the
  Watch's complications draw too)
  belong to this same widget kind, so they inherit the same per-instance
  account picker. Rectangular and inline show all
  three `WindowSlots` for that account, credits included under the
  third-row fallback; the circular gauge has room for one number, so it
  shows whichever window the shared `glanceMetric` preference points at,
  read against that instance's own picked account. Widget fonts are
  fixed sizes (12/11/9 pt) on purpose — text styles scale with Dynamic
  Type and overflow the fixed widget height on real devices; every figure
  is `Theme.figure(size:)`, the app's rounded face. The
  header also shows a small peak-hours badge (see "Peak hours" in the
  repo-root CLAUDE.md — never while the policy is retired, as it is
  today); Lock Screen accessories don't. Every reset line (the
  protagonist's, the medium columns, the single widget) is a `ResetLineText` (Shared):
  a live `Text(timerInterval:)` countdown, "Resets in 2:23:05", while
  the reset is under a day away in the relative style, else the fixed
  "Resets in 2d 22h" / "Resets at 7:59 PM" / "Resets Oct 31, 7:59 PM"
  label (see "Reset lines" in the repo-root CLAUDE.md), decided by the pure
  `ResetLine.line(for:style:now:)` from the *entry's* date, never
  `Date()` (an entry is drawn ahead of its time). The timer ticks on
  WidgetKit's side with no entry of its own; what the reset itself
  changes is the data, so each timeline's policy comes forward to a
  minute after the soonest reset (`WidgetSchedule.nextReload`, iOS
  only) and the self-fetch treats a snapshot overtaken by a reset as
  stale whatever its age (`WidgetSchedule.isStale`), see "Widget
  timeline" in the repo-root CLAUDE.md. On iOS, the header
  also carries an always-visible manual refresh button (`RefreshAccountIntent`,
  `Button(intent:)`) — deliberately not conditioned on staleness, same
  "predictable, always-available" philosophy as the app's own Dashboard
  refresh button. iOS only: a sandboxed macOS widget has no credentials to
  fetch with (the menu bar app feeds it instead — see "App ↔ widget data
  flows" in the repo-root CLAUDE.md), so there's nothing for a macOS tap
  to do. The intent reuses `WidgetRefresher`'s fetch/save/record path
  (its `refreshNow(accountID:)`, gated only by a 5s anti-spam floor, not
  a real staleness check — a direct user tap is high-priority and isn't
  subject to the same background-refresh budget throttling
  `AppConfig.widgetRefreshFloor` protects), then calls
  `WidgetCenter.shared.reloadTimelines(ofKind:)` so the tap shows fresh
  data within a couple seconds. `isDiscoverable = false`: internal to the
  widget's own button, not a standalone Shortcuts/Siri action. No live
  loading state — WidgetKit can't show a spinner mid-tap, so the widget
  just re-renders once the intent completes, same limitation every
  interactive widget has.
- `AIMeterAllAccounts` (`.systemLarge` only; `AppIntentConfiguration`
  since 3.2 with one Edit Widget choice, Layout
  (`AllAccountsConfigurationIntent`, `AllAccountsLayout`: Standard, the
  default and what a widget placed before the choice existed keeps, or
  Condensed); no account picker, it always shows every connected
  account). **Standard**: one card's worth per account, with no divider
  between them —
  `ProviderIdentityView` at the same small size `AIMeterUsage`'s header
  uses, the same always-visible iOS refresh button, and that account's
  windows as the small widget draws them (`WidgetHero` for the
  protagonist `AccountCardLayout` picks, its figure at 34 pt here, `WidgetCompactRows` for the
  rest; internal, not `private`, in `UsageWidgetViews.swift` so both
  widgets render an account identically, and as the app's card does).
  The two accounts share the height, the first at the top and the last
  at the bottom, the room left over between them. That costs real
  vertical room, so this is capped at the
  first 2 accounts (registry order — the same order the Dashboard/menu bar
  use, and the one a Dashboard drag-reorder rewrites, which is why a
  reorder reloads timelines; or by urgency with "Order by urgency" on,
  `AllAccountsEntry.ordered` over `AccountOrder`, applied again after
  the self-fetch) with a "+N more" line beyond that — deliberately not a
  `ScrollView`; static content is the safer choice for widgets. One
  peak-hours badge for the whole widget (hidden while the policy is
  retired), not repeated per account — same rule the macOS menu bar
  popover already follows. On iOS, self-refreshes
  every shown account's stale snapshot concurrently (`withTaskGroup`, same
  pattern `UsageModel.refreshAll()` uses in the app) during timeline
  generation, same as `AIMeterUsage` does for its one account. Every
  placed instance of every kind runs its own timeline in the same reload
  burst, so `WidgetRefresher.fetchIfStale` dedupes across them: it
  re-reads the store right before fetching (another instance may have just
  saved) and claims the fetch with an in-flight stamp in the App Group
  (`widget.fetchInFlight.<accountID>`, 60 s), so three widgets for one
  account are one fetch — and one refresh-token rotation — per reload.
  **Condensed** (`CondensedAccountsView`, its own file; 4.0, variant C
  of three Mike reviewed on 2026-10-21, the vertical-bars one rejected)
  fits six: a header (the app's mark, "All Accounts", the peak badge),
  then one line per account sharing the height, its name, its
  protagonist's thick bar (`AccountCardLayout`, as the cards pick it)
  and figure, and under the name every window with its figure in small
  text, the protagonist first ("Week 61% · Session 42% · Top model 18%",
  each window's own short name, so a Claude and a Copilot account never
  need shared columns), and under them the soonest session reset of all the
  accounts as a bare live countdown ("Next session reset: 1:02:40",
  `ResetLineText(bare:)`). No reset under each bar and no per-account
  refresh button there: that is what a line gives up for the room. Both
  layouts order the rows the same way (`AllAccountsEntry.ordered`).
- `AIMeterSingleUsage` (small only): shows exactly one (account, window)
  pair the user picks from the widget's own Edit Widget UI
  (`SingleUsageConfigurationIntent`) — `UsageWindowOption`'s composite id
  is `"<accountID>|<kind.storageKey>"`; options are read live by
  enumerating every connected account's last stored snapshot
  (`UsageWindowOptionQuery`), including "Credits" per account when the
  fallback above is on and that account has no real model window, so the
  list always matches what each account actually has instead of a name
  baked in at build time. The displayed label includes the account's
  nickname ("Personal · Weekly") so same-provider accounts are
  distinguishable in the picker. Its header shows the same peak-hours
  badge (hidden while the policy is retired), but only when the picked
  window is `.session` — the only window the documented policy actually
  affects. The bar style (4.0) is the app card's protagonist alone: the
  window's name over its figure at 40 pt with "%" and "used"/"left", an
  8 pt bar and the reset line under it. A second Edit Widget choice,
  Style (`SingleUsageStyle`: Bar, the default, or Ring), draws the window
  as a ring instead (`RingUsageView`): the header naming the window on
  its trailing edge, 12 pt of air, a 9 pt ring in the window's level
  color on the bars' track, and in its centre only the figure ("42%",
  no "used": Mike's review, 2026-10-21) over its reset as a bare value
  with the reset glyph, the live countdown under a day
  (`ResetLineText(bare:)` over `UsageFormatting.resetValue`, the value
  the notch island's segments show too), kept 20 pt from the stroke on
  either side. Of the mockup's three ring widgets only this one
  was kept (a small one with a ring per account and a medium one with
  three rings were not; Mike's call, 2026-10-19).
- A pre-multi-account widget instance's persisted selection
  (`"claude|kind"`) keeps resolving unchanged after an upgrade — the
  migrated legacy account's literal accountID is `"claude"`, so the
  exact same composite id still parses correctly with zero rewrite. Every
  empty-registry fallback in this target (`WidgetAccountFallback`, both
  intents' option queries, the placeholders) reads that sentinel from
  `ProviderCatalog.legacyAccount` rather than spelling it out, and the
  self-fetch builds its provider through `ProviderCatalog.makeProvider`
  from the registry's `providerID` for that account — or, when the
  registry can't place the id (a read that came back empty),
  `ProviderCatalog.fallbackAccount(for:)`: the same id as a managed
  login of the default provider. It used to fall back to the legacy
  account itself, which fetched that account's usage with its login and
  saved it under the requested id.

## StandBy (iOS)

A small widget in StandBy (the iPhone charging on its side) loses its
background and is shown large across the room; an iPad's Lock Screen
does the same. Both small widgets read
`showsWidgetContainerBackground` and, without one, draw
`StandByUsageView` instead of the card: the account's name small, the
figure at 66 pt (the protagonist `AccountCardLayout` picks for Usage
Limits, the picked window for Single Limit, whatever its style), the
window's short name and its reset beside it, and its bar. No header and
no refresh button: nothing there is read up close. At night the system
tints it red itself; the colors are the usual levels.

## The control (iOS 18 and later)

`UsageControl` (`AIMeterControl`, registered in the bundle behind
`#available(iOS 18)`): a `ControlWidgetButton` for Control Center, the
Lock Screen's two buttons and the Action button, showing one account's
nickname and its glance figure ("Session 42%",
`Shared/ControlFigure.swift`: the window `glanceMetric` points at, with
the Lock Screen gauge's fallback, in the display mode Settings picks)
over the gauge glyph filled to it (`variableValue`). The account is the
control's own choice (`UsageControlConfigurationIntent`, the widgets'
`UsageAccountOption` entity; unset, the first connected account,
`WidgetAccountFallback`). A tap runs the widgets' `RefreshAccountIntent`,
which reloads the control too (`ControlCenter.reloadControls(ofKind:)`);
everything else that redraws the widgets reloads it through
`WidgetReload.all()`. It reads the App Group's snapshot and never fetches
on its own.

## Live Activity (Session window, iOS only)

`SessionLiveActivity` puts the Session window's countdown on the Lock
Screen and Dynamic Island — the two glance surfaces widgets can't reach.
Renders from this same widget extension target (`ActivityConfiguration`
registered in `AIMeterWidgetsBundle.swift` alongside the three widgets
above); no new target, no push entitlement.

- **No server means no push updates — this is the constraint that shapes
  everything below.** ActivityKit has exactly two update paths: local
  (`Activity.update()` from an on-device process) and remote (APNs push,
  which needs a backend AIMeter deliberately doesn't have). Push is
  entirely off the table, which splits the activity's content into two
  very different update stories:
  - **The countdown is free.** `Text(timerInterval:countsDown:)` against
    the already-known `resetsAt` ticks on-device, rendered by the system,
    with zero app/extension involvement after the activity is started.
    This one fact is what makes the feature viable with no server at all.
  - **The percentage is eventually-consistent, not real-time.** It only
    changes when something already running happens to call `.update()` —
    there is no way to push a fresh number the moment usage actually
    changes server-side. Stated limitation, not a bug to chase.
- **No new update machinery — reuses the two fetch paths that already
  exist and already persist fresh snapshots**, instead of polling or a
  new background task: `RefreshService.refresh()` (`AIMeter/Services/`,
  the app's own pipeline — already ends with reschedule-notification
  calls, this is one more step there) and `WidgetRefresher.fetch()`
  (this target's shared iOS self-fetch helper, behind both `fetchIfStale`
  and `refreshNow`) — same reasoning already documented for why
  `UsageRecorder.record` (both history stores — the predictor's and the chart's timeline) happens in both places: "stays continuous
  when only the widget runs." A running activity gets fresher the same
  way the rest of the app does; no new budget to manage.
- **Session only, not Weekly/Credits.** ~5h comfortably fits ActivityKit's
  ~8h hard cap, and "counting down to a deadline" is the Live Activity
  metaphor; a 7-day window doesn't fit either. Not a "later" gap — the
  wrong shape for this mechanism entirely.
- **Opt-in per account, off by default** — a "Live Activity" toggle on
  the account's settings page (`AccountSettingsCards`; in Provider
  Detail until 3.2), same visual/persistence pattern as the Smart
  Notifications toggles (App-Group-backed, keyed by accountID). Matches
  every other visible/persistent thing this app does (peak notifications,
  the login item): a Dynamic Island takeover is prominent enough that it
  should never start on its own the moment a session begins. Per account,
  not global, for the same reason every other per-account setting already
  is — with 2+ connected accounts there's no single unambiguous "the"
  session. `LiveActivityManager` (`Shared/`, next to
  `SessionActivityAttributes`, which both targets need) is the one place
  that starts/updates/ends — and only the app process ever calls it:
  ActivityKit exposes `Activity.activities` to the app alone, so the
  widget extension can neither start nor update one, which is why
  `WidgetRefresher`'s self-fetch deliberately doesn't try (a running
  activity is refreshed by the app's own next fetch, not the widget's).
  `Activity.request` is honoured only from the foreground app, so
  `RefreshService.allowsLiveActivityStart` is false on the
  `BGAppRefreshTask` path (updates still flow there), and `start` checks
  `ActivityAuthorizationInfo().areActivitiesEnabled` first. While a toggle
  is on, it starts one whenever
  that account has a session window with a future `resetsAt` and none is
  already running, and ends it (`dismissalPolicy: .immediate`) on
  toggle-off, on disconnect, or once a fresh fetch shows no active session
  (usage back at 0, or no `resetsAt`), and a demo account's when the demo
  ends (or at the next launch, if the app was quit in it), its switches
  with it (`UsageModel.endDemoLiveActivities`) — the actual reset-hour transition
  itself is left to `ActivityContent(staleDate: resetsAt)`, ActivityKit's
  own built-in staleness presentation, rather than a hand-rolled grace
  timer: simpler, and the next `sync` call (triggered by the very next
  fetch, same as everything else in this pipeline) settles the activity's
  fate for real. `Activity.request(attributes:content:pushType: nil)` —
  the `nil` is what keeps this entitlement-free. Multiple accounts can
  each run their own concurrent activity if opted in separately; the
  Dynamic Island's own standard behavior (one compact/expanded at a time,
  others collapse to `.minimal`) handles that with no special-casing here.
  A rename can't reach a running activity through `update` — `attributes`
  (the account name, its icon and its pet among them) are fixed for an
  activity's lifetime — so `LiveActivityManager.restart` starts a fresh
  one under the new name, icon or pet and then ends the old one: the new
  one first, synchronously, so a second restart or an `end` arriving
  before the old one is gone already sees it, and a request that fails
  (in the background, where `Activity.request` refuses) keeps the old one
  rather than none. With none running, the next `sync` simply uses the
  new ones. A `sync` allowed to start one (`mayStart`) that finds a
  running activity whose pet no longer matches the switch (or one started
  before pets existed) restarts it the same way, and any second activity
  for one account (a restart's old one, a duplicate) is ended by the next
  `sync`, which keeps the one whose pet matches.
- `Shared/SessionActivityAttributes.swift` (`ActivityAttributes` +
  `ContentState: usedPct, resetsAt, isPeak, severity`) lives in `Shared/`,
  synced into both targets already like `Theme.swift`/`AppConfig.swift` —
  both the app (start/update/end) and this extension (render) need the
  type. `severity` rides along so the bar can call the same
  `UsageWindow.tint(usedPct:severity:usageColors:)` (terracotta / yellow /
  red, `UsageLevel`) every other surface uses (see
  "Design system" in the repo-root CLAUDE.md) instead of a simplified
  percentage-only copy that would miss a provider-flagged critical window
  under the raw threshold. The switch is read from the App Group at
  render (`Preferences.load().usageColors`) rather than carried in the
  `ContentState`: a new field there would not decode from an activity an
  older build started.
- Presentation: chosen from 3 mocked layout concepts (Minimal, Detailed,
  Bold stat) — "Detailed" shipped, since it mirrors the row rhythm this
  app's own usage rows already use elsewhere. Lock Screen banner and the
  Dynamic Island's `.expanded` region share the same content — account
  name via `ProviderIdentityView` (same small icon size this extension's
  other headers use), percentage, `UsageBarView` (already shared), and the
  countdown. The peak badge (bolt icon, `Theme.danger`, shown when
  `isPeak` — see "Peak hours" in the repo-root CLAUDE.md; never while the
  policy is retired) is grouped with
  the account name on the *leading* side, not with the percentage on the
  trailing side — deliberate: it's a property of the account/window, not
  of the number, so it reads as "this account, right now, is in peak
  hours" rather than looking like it's modifying the percentage. `.compact`
  is icon + percentage, with the same bolt appended when `isPeak`;
  `.minimal` is icon only (no room for the badge at that size).
- **The pet** (opt-in per account, off by default; "Show a pet" under the
  Live Activity switch on the account's settings page, `LiveActivityCard`, shown only
  while that switch is on, with the account's pet drawn beside the words):
  the account's own pixel pet, the same creatures as the Mac's session
  pets, from its accountID through FNV-1a (`SessionPet(accountID:)`, so
  the legacy `"claude"` account is a pink axolotl), takes the icon's place
  in `.compactLeading`, `.minimal`, the expanded leading region (beside
  the name) and the Lock Screen header. It rides in the attributes by
  its three parts' raw values (`SessionActivityAttributes.Pet`: creature,
  palette, accessory, which only ever grow at the end; never the index,
  which a new creature remaps), nil when off and nil for an activity an
  older build started, which decodes without it, so the switch restarts a
  running activity (`LiveActivityPreferences.showsPet`,
  `liveActivity.pet.<accountID>`, cleared on disconnect with the other
  key). A Live Activity is an archived snapshot drawn at each update,
  with no clock (`TimelineView` doesn't advance there) and no animation
  API of its own (WWDC26 223: the system times every change), so the pet
  holds one still frame (`PetPixelsView`, a path per tone over
  `SessionPet.paintedPixels`, `Shared/`) and its mood is read at render
  from what the activity already carries (`SessionPetMood`, from
  `usedPct` and `severity`), with no new `ContentState` field: standing
  with room to spare, fidgeting beside a yellow "!" past the bar's yellow
  line, beside a red one past its red line or a critical flag. The
  levels are `UsageLevel`'s, so the mood changes where the bar's color
  does; with usage colors off the mood still changes and the "!" takes
  the text's color. It never sleeps: a pet asleep at the reset needs an
  update at the reset, which nothing sends with no server. The system
  doesn't redraw an activity when its stale date passes (measured on the
  iOS 27 simulator: still awake a minute after `staleDate`, and an
  update carrying a past `staleDate` took the activity off screen
  altogether; Apple documents only the `activityState` change), and the
  next refresh after the reset ends the activity anyway. A change of mood pushes the new pose up from below
  (`.id(mood)` + `.transition(.push(from: .bottom))`), the one motion the
  system plays between two updates. On the island's black the pet glows
  in its color, as on the Mac; on the Lock Screen's card it sits on a
  black tile of its own, since its white accessories vanish on a light
  card (`ActivityPetView`). With two of AIMeter's activities running,
  the island shows one and the Lock Screen stacks both. Showing the Mac's Claude
  Code sessions here instead was looked at and left out: with no server,
  the only path would be CloudKit silent pushes, which Apple throttles to
  a few an hour and drops once the app is force-quit.
- `AIMeter/Info.plist` carries `NSSupportsLiveActivities: YES` — the
  physical-file pattern already used for `BGTaskSchedulerPermittedIdentifiers`/
  `UIBackgroundModes` (and `LSApplicationCategoryType`, Utilities, which
  the macOS archive warns about when missing), the keys that can't be
  expressed as `INFOPLIST_KEY_*` build settings.
