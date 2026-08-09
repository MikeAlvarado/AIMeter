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
