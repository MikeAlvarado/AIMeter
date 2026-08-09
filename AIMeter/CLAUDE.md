## Screens

- **Dashboard**: floating gear + refresh buttons (refresh icon spins while
  busy; soft haptic on refresh start; refresh fans out to every account
  concurrently via `UsageModel.refreshAll()`), small centered serif
  "AIMeter" title, then one section per *connected account*
  (`AccountSectionView`, shared with the macOS menu bar popover): logo +
  nickname + Pro/Max pill (trailing) → card with the three windows, error,
  "Updated X ago"; tapping a section's header pushes that account's
  Provider Detail (`NavigationLink(value: accountID)`). An "Add account"
  row follows the list. Disconnected state (no accounts at all) shows a
  Connect card instead.
- **Provider detail** (push, one per account — `ProviderDetailView(accountID:)`):
  rate-limit rows for that account; a **Peak hours** card
  (`PeakHoursCard`, see "Peak hours" in the repo-root CLAUDE.md, identical
  content regardless of account since the policy is Claude-wide, not
  account-specific) with a live status line and a "schedule as of"
  footnote; a **Forecast** card
  (`ForecastCard`) listing any of that account's windows projected to run
  out early or an all-clear row; a "Third usage row" card with the
  Auto/Hidden/Credits pill (governs the third-slot fallback above,
  defaults to Auto, shared across accounts) plus a "Show credit amounts"
  toggle (off by default, also shared) for the Credits row's money
  subtitle; on iOS only, a "Lock Screen widget" pill for `glanceMetric`
  (macOS's equivalent lives in Settings now — see "Display prefs" in the
  repo-root CLAUDE.md), options read live from this account's snapshot,
  and a "Live Activity" toggle (also iOS only — see
  `AIMeterWidgets/CLAUDE.md`) for this account's Session countdown on the
  Lock Screen/Dynamic Island, off by default; Spend and Extra usage
  cards (label/value rows, currency formatted) for this account; per-window
  reset notification toggles plus a **Smart notifications** card
  (`SmartNotificationTogglesCard`: Near-limit warnings with a threshold
  slider, Limit reached, Run-out warnings, and Early-reset alerts — all
  four scoped to this one account); a disconnect button, on both
  platforms (macOS previously had none — a gap multi-account made
  untenable, since it's now the only way to remove a non-primary account).
  All of these are Claude-specific display prefs, so they live here rather
  than in the app-wide Settings screen — a future provider's own detail
  view would carry its own equivalents instead of sharing these. Peak-hours
  alerts are the one exception: a single toggle in the app-wide Settings
  screen, not repeated per account, since the policy is Claude-wide, not
  account-specific — see "Settings" below and "Peak hours" in the
  repo-root CLAUDE.md.
- **Settings**: while `isDemoMode` is true, a "Demo mode" section (Exit
  Demo action + explanatory footnote) leads the list, above everything
  else, then appearance / display mode / reset style pills, a
  "Notifications" card with the one Peak-hours alerts toggle (the single
  exception to "no notification toggles here" — every other toggle moved
  fully into each account's own Provider Detail once there could be more
  than one "the" account to apply them to, but peak-hours is one
  Claude-wide policy with nothing account-specific to scope it to; see
  "Peak hours" in the repo-root CLAUDE.md), and refresh
  cadence menu (all app-wide, not per account), a "Privacy & data" link,
  and an "Open Source" row (GitHub mark, opens the repo URL). iOS: sheet
  with Done; macOS: Settings scene
  (wrapped in a NavigationStack so the link can push), plus the macOS-only
  `MacChromeSettings` block — "Menu bar" (which account and window the
  status item reads, only shown/relevant once >1 account is connected for
  the account picker, plus Show percentage), "Hiding AIMeter" (Hide Dock
  icon / Hide menu bar icon, with a warning row once both are hidden), and
  "Startup" (Open at Login, with a pending-approval row and a nudge when
  the Dock icon is hidden but the login item is off).
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
- **Connect sheet**: pixel-Claude icon, explainer, "Open Claude Sign-In", a
  nickname field (only shown once at least one account is already
  connected — a first connection needs no name; suggests "Claude 2" etc.
  based on how many exist), paste field (accepts OAuth code or full
  credentials JSON), Connect — surfaces the connection error inline
  (`UsageModel.connectionError`, a transient property distinct from an
  already-connected account's ongoing `lastError`, since a failed
  connection attempt never makes it into `accounts`) instead of dismissing
  on failure. Always goes through the app's own managed OAuth/paste flow,
  on both platforms — the macOS auto-detect path is never something a user
  picks here; it only ever applies automatically to the one CLI-mirrored
  login (see "Accounts vs. providers" in the repo-root CLAUDE.md).
- **Demo mode**: `UsageModel.enterDemoMode()` loads a fabricated
  `DemoUsageData.snapshot()` — one of each window kind, spend, and extra
  usage — so every screen (rate limits, pace, peak hours, forecast,
  spend/extra cards) can be explored without a real Claude account. Exists
  mainly so App Store reviewers can evaluate the app without being handed
  credentials to a paid third-party account; also a source of screenshots
  that doesn't expose anyone's real usage. Purely in-memory: never calls
  `RefreshService`, never touches the App Group `SnapshotStore` or
  `WidgetCenter`, so it can't leak into widgets or a real connection, and
  `paceReady` short-circuits true so pace/forecast don't show the
  "learning" state on fabricated data with no history. Scheduling a
  `reset.`/`runout.` notification while in demo mode is a deliberate no-op
  (`UsageModel` passes `nil` in place of the demo snapshot) so a fake
  reset date can never produce a real notification. Entry and exit both
  live in Settings only — a "Demo mode" section at the top of the list
  (shown while disconnected or while demo is active, hidden once a real
  account is connected) offers "View Demo" or "Exit Demo" accordingly; the
  dashboard's disconnected card stays just Connect, no demo affordance, to
  keep it from looking like a second, competing call to action. Provider
  Detail's bottom button also becomes "Exit Demo" (both platforms) instead
  of "Disconnect Claude" (iOS-only) while active.
- **Landscape (iPhone)**: `verticalSizeClass == .compact` swaps the
  dashboard for a fullscreen card with the same stacked rows.
- **macOS menu bar**: one status item regardless of how many accounts are
  connected — `MenuBarExtra` has no per-instance configuration the way
  widgets do. The label (`MenuBarLabel`) is a variable-value
  `gauge.with.needle` whose fill tracks the *primary* account's
  `glanceMetric` window's **displayed** percentage (`UsageModel.primaryAccountUsage(preferredID:)`,
  so a "Remaining" reading never contradicts its own gauge), with the
  number spelled out beside it only when `menuBarShowsPercentage` is on.
  Either way the exact value stays in the `.help` tooltip and the
  accessibility label — icon-only mode must never be the only place the
  number lived. The whole status item disappears when `statusItemVisible`
  is off (`MenuBarExtra(isInserted:)`). The popover shows a peak-hours
  badge row at the top only while peak is active (peak is Claude-wide, not
  per account, so this isn't repeated per section) + divider, then **every**
  connected account as its own `AccountSectionView` (shared with the
  Dashboard, `linksToDetail: false` here since the popover has no
  navigation stack to push into — tapping a section header does nothing,
  unlike the Dashboard's chevron-and-push) inside a height-capped
  `ScrollView` so a handful of accounts still fit and more scrolls, then
  divider + refresh/settings/quit. "Refresh" calls `refreshAll()` (every
  account, concurrently). Peak-hours state folds into the status item's
  tooltip/accessibility text rather than a second glyph there (see "Peak
  hours" in the repo-root CLAUDE.md); the popover's top badge row is the
  visible one, where there's room.
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
