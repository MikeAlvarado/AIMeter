## Widgets

Both kinds are `AppIntentConfiguration`, so every placed
instance — Home Screen or Lock Screen — has its own independent account
selection; an empty `AccountRegistryStore` (nothing connected yet, or
the app hasn't run its one-time migration since the last update) falls
back to a single synthetic "claude" option in both pickers rather than
showing an empty list.
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
  repo-root CLAUDE.md); Lock Screen accessories don't.
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
