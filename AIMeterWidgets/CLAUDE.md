## Widgets

`AIMeterUsage` and `AIMeterSingleUsage` are `AppIntentConfiguration`, so
every placed instance — Home Screen or Lock Screen — has its own
independent account selection; an empty `AccountRegistryStore` (nothing
connected yet, or the app hasn't run its one-time migration since the
last update) falls back to a single synthetic "claude" option in both
pickers rather than showing an empty list. `AIMeterAllAccounts` (see
below) has no picker at all.
- `AIMeterUsage` (small & medium, `UsageAccountConfigurationIntent`):
  header (logo + the picked account's nickname) + all three bars with
  reset lines; Lock Screen accessories (circular gauge, rectangular
  list, inline) belong to this same widget kind, so they inherit the
  same per-instance account picker. Rectangular and inline show all
  three `WindowSlots` for that account, credits included under the
  third-row fallback; the circular gauge has room for one number, so it
  shows whichever window the shared `glanceMetric` preference points at,
  read against that instance's own picked account. Widget fonts are
  fixed sizes (12/11/9 pt) on purpose — text styles scale with Dynamic
  Type and overflow the fixed widget height on real devices. Rows sit in
  equal flexible slices so the layout fills any family height. The
  header also shows a small peak-hours badge (see "Peak hours" in the
  repo-root CLAUDE.md); Lock Screen accessories don't. On iOS, the header
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
- `AIMeterAllAccounts` (`.systemLarge` only, `StaticConfiguration` — no
  per-instance configuration, since there's nothing to pick, it always
  shows every connected account): one compact row per account —
  `ProviderIdentityView` at the same small size `AIMeterUsage`'s header
  uses, the same always-visible iOS refresh button, and that account's
  `WindowSlots` rendered as full `WindowBarRow`s — the exact same row
  `AIMeterUsage` uses, reset lines included (internal, not `private`, in
  `UsageWidgetViews.swift` specifically so this view can reuse it
  unchanged rather than re-implementing a second row style). That
  full-detail row costs real vertical room, so this is capped at the
  first 2 accounts (registry order, same order Dashboard/menu bar already
  use) with a "+N more" line beyond that — deliberately not a
  `ScrollView`; static content is the safer choice for widgets. One
  peak-hours badge for the whole widget, not repeated per account — same
  rule the macOS menu bar popover already follows. On iOS, self-refreshes
  every shown account's stale snapshot concurrently (`withTaskGroup`, same
  pattern `UsageModel.refreshAll()` uses in the app) during timeline
  generation, same as `AIMeterUsage` does for its one account.
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
  badge, but only when the picked window is `.session` — the only
  window the documented policy actually affects.
- A pre-multi-account widget instance's persisted selection
  (`"claude|kind"`) keeps resolving unchanged after an upgrade — the
  migrated legacy account's literal accountID is `"claude"`, so the
  exact same composite id still parses correctly with zero rewrite.

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
  `UsageHistoryStore.record` happens in both places: "stays continuous
  when only the widget runs." A running activity gets fresher the same
  way the rest of the app does; no new budget to manage.
- **Session only, not Weekly/Credits.** ~5h comfortably fits ActivityKit's
  ~8h hard cap, and "counting down to a deadline" is the Live Activity
  metaphor; a 7-day window doesn't fit either. Not a "later" gap — the
  wrong shape for this mechanism entirely.
- **Opt-in per account, off by default** — a "Live Activity" toggle in
  Provider Detail, same visual/persistence pattern as the Smart
  Notifications toggles (App-Group-backed, keyed by accountID). Matches
  every other visible/persistent thing this app does (peak notifications,
  the login item): a Dynamic Island takeover is prominent enough that it
  should never start on its own the moment a session begins. Per account,
  not global, for the same reason every other per-account setting already
  is — with 2+ connected accounts there's no single unambiguous "the"
  session. `LiveActivityManager` (`Shared/` — not `AIMeter/Services/`,
  since `WidgetRefresher`'s self-fetch in *this* target needs to call it
  too, same reason `SessionActivityAttributes` lives in `Shared/`) is the
  one place
  that starts/updates/ends: while a toggle is on, it starts one whenever
  that account has a session window with a future `resetsAt` and none is
  already running, and ends it (`dismissalPolicy: .immediate`) on
  toggle-off, on disconnect, or once a fresh fetch shows no active session
  (usage back at 0, or no `resetsAt`) — the actual reset-hour transition
  itself is left to `ActivityContent(staleDate: resetsAt)`, ActivityKit's
  own built-in staleness presentation, rather than a hand-rolled grace
  timer: simpler, and the next `sync` call (triggered by the very next
  fetch, same as everything else in this pipeline) settles the activity's
  fate for real. `Activity.request(attributes:content:pushType: nil)` —
  the `nil` is what keeps this entitlement-free. Multiple accounts can
  each run their own concurrent activity if opted in separately; the
  Dynamic Island's own standard behavior (one compact/expanded at a time,
  others collapse to `.minimal`) handles that with no special-casing here.
- `Shared/SessionActivityAttributes.swift` (`ActivityAttributes` +
  `ContentState: usedPct, resetsAt, isPeak`) lives in `Shared/`, synced
  into both targets already like `Theme.swift`/`AppConfig.swift` — both
  the app (start/update/end) and this extension (render) need the type.
- Presentation: chosen from 3 mocked layout concepts (Minimal, Detailed,
  Bold stat) — "Detailed" shipped, since it mirrors the row rhythm this
  app's own usage rows already use elsewhere. Lock Screen banner and the
  Dynamic Island's `.expanded` region share the same content — account
  name via `ProviderIdentityView` (same small icon size this extension's
  other headers use), percentage, `UsageBarView` (already shared), and the
  countdown. The peak badge (bolt icon, `Theme.danger`, shown when
  `isPeak` — see "Peak hours" in the repo-root CLAUDE.md) is grouped with
  the account name on the *leading* side, not with the percentage on the
  trailing side — deliberate: it's a property of the account/window, not
  of the number, so it reads as "this account, right now, is in peak
  hours" rather than looking like it's modifying the percentage. `.compact`
  is icon + percentage, with the same bolt appended when `isPeak`;
  `.minimal` is icon only (no room for the badge at that size).
- `AIMeter/Info.plist` carries `NSSupportsLiveActivities: YES` — the
  physical-file pattern already used for `BGTaskSchedulerPermittedIdentifiers`/
  `UIBackgroundModes`, the keys that can't be expressed as
  `INFOPLIST_KEY_*` build settings.
