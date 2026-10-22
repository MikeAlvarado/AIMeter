## Screens

- **Dashboard** (on `AppBackground`, see "Surfaces" in the repo-root
  CLAUDE.md): on iOS, floating gear + refresh buttons on Liquid Glass
  (`RoundIconButton`, `glassControl`; refresh icon spins while busy; soft
  haptic on refresh start) and between them, with no app title since
  4.0, only "Updated X ago", the newest account's refresh
  (`DashboardView.lastUpdatedLabel`); on macOS no in-page header at all,
  that line being the window's subtitle (`navigationSubtitle`) — the window's
  own title bar already says "AIMeter", so Refresh (a small spinner while
  busy) and Settings sit in the window's toolbar at its trailing edge,
  the way a Mac app keeps them, and the window opens 460 × 760 pt
  (`defaultSize`) with a 380 × 560 minimum that a smaller restored frame
  grows to. Either way refresh fans out to every account concurrently
  via `UsageModel.refreshAll()`; on macOS ⌘R comes from the Usage menu —
  see "Conventions" in the repo-root CLAUDE.md — and from the menu bar
  popover's own button, never from the toolbar's. Then — only while the provider reports an incident
  (`UsageModel.activeIncident`, see "Service status" in the repo-root
  CLAUDE.md) — a `ServiceStatusBanner`, then one card per *connected account*
  (`AccountSectionView`, 16 pt apart; see "Account cards" in the repo-root
  CLAUDE.md): inside the card, the identity (mark, nickname, plan pill,
  chevron), the most urgent window large with its 24-hour sparkline once
  three samples exist (see "History" in the repo-root CLAUDE.md), the
  other windows one line each, and only when there is one the error,
  "Sign in again", the incident line or a stale "Updated X ago"; tapping
  the identity pushes that account's Provider Detail
  (`NavigationLink(value: accountID)`). An "Add account" capsule on glass
  follows the list (hidden in demo mode, same as the menu bar's copy:
  `completeConnection` would register a real account underneath the
  fabricated row, invisible until Exit Demo). Disconnected state (no
  accounts at all) shows a Connect card instead; on macOS, once the user
  has disconnected the CLI-mirrored account, that card also offers "Use
  Claude Code's login instead" (`UsageModel.redetectClaudeCodeLogin`, see
  "Disconnect cascades" in the repo-root CLAUDE.md). On macOS, below the
  accounts, the "Claude Code on this Mac" section (`ClaudeCodeSection` —
  see "Claude Code local usage" in the repo-root CLAUDE.md): the
  invitation card while the feature is off, the three-bucket summary
  pushing `ClaudeCodeUsageView` while on; in demo mode, the same summary
  and detail over `DemoUsageData.codingSessions` under the neutral title
  "Coding sessions on this Mac". The header's refresh
  button and pull-to-refresh play a soft haptic, keyed on a
  user-initiated request counter rather than `isRefreshing`, which also
  flips for the foreground auto-refresh.
  - **Reordering** (2+ accounts only, and never while "Order by urgency"
    is on, `UsageModel.ordersByUrgency`, when the order shown is not the
    registry's; see "Order by urgency" in the repo-root CLAUDE.md): hold
    a card to lift it, drag, and
    release over another section to take that section's place, with
    `AccountDropHighlight`'s accent outline marking the target. The order is
    the account registry's own (see "Accounts vs. providers" in the
    repo-root CLAUDE.md), so it carries to the menu bar popover, the
    all-accounts widget, every account picker, and the macOS status item's
    "first account" fallback.
    - Built on a hold-then-drag gesture moving the card with an `offset`
      (SwiftUI's `LongPressGesture.sequenced(before: DragGesture)` on iOS 17
      and macOS, a UIKit long-press recognizer on iOS 18+ — see the last
      bullets below), **not** on `.draggable`/`.dropDestination`.
      That is the entire reason this is hand-rolled: SwiftUI's drag and
      drop carries a *preview* of the view, and UIKit scales that preview
      down to fit its own bounds — a full-width account card lifts at
      roughly half size. Supplying `.draggable(preview:)` with the section
      rendered at its measured on-screen width was tried and gets scaled
      identically; the preview API has no opt-out. With a gesture nothing
      is lifted out of the view tree at all, so the card moves at exactly
      the size it already had. Depth (shadow) marks the lift, deliberately
      not a `scaleEffect` — growing the card is the same complaint again.
    - The long press is also what lets a vertical drag coexist with the
      enclosing `ScrollView`: move immediately and you scroll, hold first
      and you reorder — the bargain the Home Screen makes. Its duration is
      the platform's 0.5 s, deliberately not shorter: at 0.3 s a thumb that
      merely settled before scrolling completed the press and the scroll
      became a reorder (reproduced with a 400 ms dwell on the simulator).
    - The press alone cannot tell a scroll from a hold: `LongPressGesture`
      measures `maximumDistance` in the card's own coordinate space, and a
      card scrolls *with* the finger, so a scrolling finger never "moves"
      and the press completes mid-scroll — the card lifted, shadow and
      haptic included, while the list was still moving (reported from a
      device). `DashboardScrollOffsetKey` publishes the content's offset in
      the ScrollView's own space and `ScrollMovementTracker` (a reference in
      `@State`, so per-frame updates invalidate nothing) records when it
      last changed; a press that completes with movement inside the press
      window (0.6 s) is ignored and the rest of that touch stays a scroll.
    - On iOS 18+ the gesture is not a SwiftUI gesture at all but a UIKit
      `UILongPressGestureRecognizer` (`ReorderPressRecognizer`, a
      `UIGestureRecognizerRepresentable` in `AccountReorder.swift`). Any
      SwiftUI gesture with a drag in it — `.gesture` *and*
      `.simultaneousGesture` were both tried — makes the ScrollView refuse to
      pan for touches that begin on the card (iOS 26 simulator: a flick on a
      card did nothing, the same flick in the gap between cards scrolled,
      and with the gesture removed the flick on the card scrolled), and
      cards are nearly all the content. UIKit's recognizer has the right
      semantics natively: a finger that moves before 0.5 s starts the pan
      and cancels the press; a press that completes first prevents the pan
      for that touch; its `.changed` states are the drag. iOS 17 and macOS
      keep the SwiftUI sequenced gesture (no such regression there). Both
      paths report through `ReorderPhase` into one handler, and
      `.scrollDisabled(draggingID != nil)` on the ScrollView restates the
      "lifted card never scrolls" promise for the SwiftUI path. Verified on
      the iOS 26 simulator with four accounts: flick up/down from a card
      scrolls; 200 ms pause then move scrolls; 800 ms hold then move
      reorders with the list still; a 1.2 s slow drag with the finger down
      scrolls without lifting (the device symptom); header tap and header
      context menu unaffected.
    - `AccountSectionFramesKey` publishes each section's rect in the
      Dashboard's named coordinate space, since a gesture (unlike a drop
      target) only gets a location and has to resolve "what am I over"
      itself. The dragged card's own rect stays in the running so releasing
      where you started is a no-op.
    - Resolving on release rather than reordering live keeps the state down
      to "which card, moved how far, over what", and a gesture always ends
      — there's no cancelled-drag hole to defend against, which a live
      `.dropDestination` version needed a catch-all drop target for.
    - The gesture covers the whole section while the header carries a
      "Move up"/"Move down" context menu — the same long press would
      otherwise have to arbitrate between the two, and the menu is both the
      VoiceOver/Switch Control path and the only part of this that announces
      itself.
  - **Icon**: the header context menu also carries "Change icon…" (only
    where this view may present sheets — the macOS popover routes its
    edits to the Dashboard), opening `AccountIconPicker` for that account;
    the account's settings page has the discoverable "Icon" row to the
    same sheet. The choice (`AccountIcon`: an SF Symbol name, or the
    Claude / Claude Code mark) lands on `UsageModel.setIcon(_:for:)`, in
    place like a rename, and shows wherever `ProviderIdentityView` draws
    the account: dashboard, landscape, menu bar popover, every widget, the
    Live Activity. Hidden in demo mode (demo accounts keep the default
    mark on purpose: screenshots). See "Design system" in the repo-root
    CLAUDE.md for the marks and the review posture behind them.
  - **Renaming**: that same header context menu carries "Rename…" for
    every account — one account is enough to want a name, so unlike Move
    up/down it isn't gated on 2+ — opening `renameAccountAlert`
    (`RenameAccountAlert.swift`): a plain alert with one field seeded with
    the current nickname and Save disabled while it's empty or already
    another account's name (case-insensitive, `UsageModel.isNameTaken` —
    the nickname is all that tells accounts apart in widget pickers and
    notification titles; the message line says which), landing on
    `UsageModel.rename(_:to:)`. Alert buttons don't re-evaluate `.disabled`
    live on every OS version, so `rename` also returns whether it accepted
    the name, and a rejected Save re-presents the alert with the reason
    instead of dismissing silently. Hidden in demo mode. The rename is in place
    (same `accountID`, so nothing keyed by it moves — the mirror image of
    why reconnect is in place too) and nudges every surface that caches
    the name instead of leaving it to drift until the next fetch: the
    account's `RefreshService` (`renamed(to:)`, keeping the provider and
    its plan cache rather than rebuilding), every placed widget
    (`reloadAllTimelines`), a running Live Activity (ended and restarted
    under the new name — see `AIMeterWidgets/CLAUDE.md`), and the pending
    reset/run-out notifications (`RefreshService.rescheduleNotifications`,
    re-issued from the stored snapshot, no fetch) — all three through
    `UsageModel.propagateName`, which `refresh(accountID:)` calls again
    when it finds a rename landed while its fetch was in flight (that
    fetch's `RefreshService` still carried the old name). the account's
    settings page reaches the same alert, for anyone who never discovers
    the context menu.
  - A card whose last refresh failed on credentials shows "Sign-in expired"
    + a **Sign in again** button instead of the raw error, opening the
    Connect sheet in reconnect mode (see "Connect sheet" below and "Losing
    a login" in the repo-root CLAUDE.md). Same row appears in Provider
    Detail, landscape, and the macOS menu bar popover — it lives in the
    shared `UsageStatusFooter`, not per screen.
- **Provider detail** (push, one per account — `ProviderDetailView(accountID:)`):
  what the account shows, and nothing it does: rate-limit rows for that
  account (with the same "Sign in again" recovery row when this
  account's credentials stopped working, and the same incident line
  under a failing refresh), followed by the one always-on
  service-status footnote in the app ("Service status: … · checked X
  ago", `UsageModel.serviceStatusFootnote`, absent until the first check
  of a launch lands or while the check is turned off); a **History**
  card (`HistoryCard`: window pill, 24 h / 7 days / 30 days pill, the
  Swift Charts curve with reset rules and the 85 % line, or "Recording
  since …" until an hour of samples exists — see "History" in the
  repo-root CLAUDE.md); a **Peak hours** card (`PeakHoursCard`, see
  "Peak hours" in the repo-root CLAUDE.md, identical content regardless
  of account since the policy is Claude-wide, not account-specific) with
  a live status line and a "schedule as of" footnote — rendered only
  while `ClaudePeakSchedule.current` is non-nil, which it isn't today
  (the policy is retired); a **Forecast** card (`ForecastCard`) listing
  any of that account's windows projected to run out early or an
  all-clear row; Spend and Extra usage cards (label/value rows, currency
  formatted) for this account; and, in the toolbar, an **Account
  settings** button (`slider.horizontal.3`, a `NavigationLink` to an
  `AccountSettingsRoute`) pushing the account's own settings page (below)
  in the same navigation stack on both platforms, the demo's accounts
  included. Until 4.1 it was a row at the end of the page, which went
  unfound (Mike, 2026-10-22).
  Until 3.2 the per-account toggles (reset and smart notifications, the
  Live Activity, name, icon, disconnect) and three global ones (the Lock
  Screen widget's window, the third usage row, the credit amounts) sat
  here under the data; they moved so that every setting has one place,
  general ones in Settings and an account's on its page (Mike's rule,
  2026-10-19: general settings and per-account settings, and never the
  same thing in both). The store capture that showed the Smart
  notifications card here (`detail-smart.png`, see
  `Scripts/StoreFrames/CLAUDE.md`) is therefore taken on the account's
  page from 3.2 on.
- **Account settings** (`AccountSettingsCards`, `AccountSettingsPage.swift`,
  both platforms): one account's own settings and nothing general. While
  its login doesn't work (`needsReauthentication`), a card first with
  "Sign-in expired" and **Sign in again**, which opens
  `ConnectAccountSheet(reconnecting:)` right there (Settings' row for the
  account says "Sign in again" in red, and this is where it leads); then
  an **Account** card (hidden in demo mode) — a Name row showing the
  current nickname, and tapping it opens the same rename alert the
  Dashboard header's context menu uses (see "Renaming" above), and an
  Icon row opening the icon picker, one card between them (`Card` stacks
  its rows itself: handed them loose, it drew three cards from 1.6 to
  3.0.1); the per-window reset notification toggles
  (`NotificationTogglesCard`) and a **Smart notifications** card
  (`SmartNotificationTogglesCard`, one toggle per `SmartAlert` case in
  declaration order: Near-limit warnings with a threshold slider, Limit
  reached, Run-out warnings, Early-reset alerts, and Sign-in alerts —
  all five scoped to this one account, and Sign-in alerts the only toggle
  in the app that starts **on**, for the reason documented on
  `NotificationPreferences.reauthAlertsEnabled`); on iOS only, a "Live
  Activity" card (`LiveActivityCard` — see `AIMeterWidgets/CLAUDE.md`): a
  toggle for this account's Session countdown on the Lock Screen/Dynamic
  Island, off by default, and while it is on, "Show a pet" (the account's
  pixel pet beside the countdown, drawn next to the words; also off by
  default); and a disconnect button (hidden in demo mode; the demo leaves
  through Settings' Demo card); on the Mac, before it, "Hide in discreet
  mode" (`DiscreetAccountSettings`), whether discreet mode hides this
  account. Disconnecting asks first
  (`DisconnectConfirmation`, a `confirmationDialog` anchored to the
  control that asks, so iPad's popover points at it; the Mac's "−" uses
  the same): "Disconnect Claude?", and that AIMeter forgets its sign-in
  and deletes its usage history (in iCloud too, if sync is on) and its
  alerts, while the account with the service isn't touched.
  `UsageModel.disconnect` returns whether the account is gone, and only
  then does the page move on: a failed cascade leaves the account, its
  error on its card, and the page open. The cascade also clears the
  account's discreet-mode mark (macOS), since the id can come back (the
  Claude Code mirror is always `"claude"`). Reached three ways, all to
  the same cards: pushed from Settings' accounts card on iOS
  (`AccountListSettings`), pushed from Provider Detail's toolbar on both
  platforms (a value, `AccountSettingsRoute`, in
  the Dashboard's stack), and the detail pane of the Mac Settings
  window's Accounts tab (`MacAccountsSettingsPage`), where disconnecting
  selects the first remaining account; `onDisconnect` lets the Settings
  list's page pop. In the Dashboard's stack the page doesn't pop itself:
  whenever an account goes away, from anywhere, `ContentView` resets the
  stack's path to the Dashboard, since the Provider Detail under the page
  has nothing left to show. Until 4.0.1 the page popped onto that empty
  detail, titled with a provider's name (it read as another account),
  and the page was pushed by destination inside a path-bound stack,
  which could leave the stack stuck (Mike, 2026-10-21; measured after
  the fix with a scripted connect, push and disconnect of the Codex CLI
  mirror: the path went from 2 to 0 and the app kept answering).
  Peak-hours alerts are the one exception to "an account's alerts on its
  page": a single toggle in the general Settings, not repeated per
  account, since the policy is Claude-wide, not account-specific — see
  "Peak hours" in the repo-root CLAUDE.md (hidden today: the policy is
  retired).
- **Settings** (reorganized for 4.1, Mike's call on 2026-10-22 after a
  fresh review of the 4.0 layout): the general settings, built from one
  view per section (`SettingsSections.swift`: `DemoModeSettings`,
  `AppearanceSettings` — the appearance / display mode / reset style
  pills and the "Usage colors" switch —, `PeakNotificationsSettings`,
  `ServiceStatusSettings`, `BackgroundRefreshSettings`,
  `PrivacyLinkSettings`, `OpenSourceSettings`; `AccountsSettings.swift`:
  `AccountListSettings`, `AccountListRow`, `UsageRowsSettings` and iOS's
  `GlanceMetricSettings`; `MacAccountsSettings.swift`; and
  `AccountOrderToggle`,
  `DiscreetModeSettings`, `CloudSyncSettings`, `ExportSettings` and
  `FeedbackSettings` in files of their own; each draws its header, card
  and footnote and never the gap around itself), which the two platforms
  arrange in the same groups: the accounts; how the numbers look; the
  widgets (iOS); refreshing and data; AIMeter itself (no notifications
  group: every alert is an account's, on its page, so it only listed the
  accounts again). The
  rules: each setting lives in one place (general ones in Settings, an
  account's on its page, which Settings' rows lead to); only what applies
  shows (the services you have: Privacy & data describes how each family
  connects and what it can reach only for the families connected, all
  three with none or in the demo, `ProviderCatalog.familiesToDescribe`;
  "Usage rows" unless every account is Copilot's, since its fallback
  reaches every account with a session or a week, Claude's and Codex's,
  `UsageRowsSettings.applies`, its Fable example only with a Claude
  account; Claude Code's cards and the Accessibility privacy row only
  where Claude Code has run, `Tour.claudeCodePresent`; order and the
  glance account with two or more accounts); what deletes data asks
  first and says what goes; every menu says what it is for.
  - **iOS** (`SettingsView`, a sheet with Done, a `NavigationStack`):
    one screen. While `isDemoMode` is true, or while nothing is
    connected, the "Demo mode" card leads it. Then the accounts card
    (`AccountListSettings`: one `AccountListRow` per account, its mark,
    its name with the plan pill (`PlanPill`, shared with
    `ProviderIdentityView`), and under them its service, or "Sign in
    again" in red while its login doesn't work, each pushing its page;
    "Add account", which opens `ConnectAccountSheet` over Settings
    (hidden in demo mode); "Order by urgency" as the card's last row with
    2+ accounts, `AccountOrderToggle`, `Preferences.ordersByUrgency`,
    mirrored into the model through `setOrdersByUrgency`); the one
    Peak-hours toggle under it while a schedule is in force (none today);
    then one card of rows, each pushing a screen of its sections
    (`SettingsGroupLink`): **Appearance** (appearance, display mode,
    usage colors, reset style; the "App icon" card, `AppIconSettings`:
    the four looks as pictures with their names, the one in use ringed in
    the accent; "Usage rows", `UsageRowsSettings`: the Auto/Hidden/Credits
    pill for the third-slot fallback, default Auto, and "Show credit
    amounts", off by default, both one shared value for every account),
    **Widgets** (the "Lock Screen widget" pill, `GlanceMetricSettings`:
    which window the circular gauge reads for whichever account a widget
    instance is set to, its options the union of what the accounts
    report; and how to add a widget, since the app can't place one),
    **Refresh & data** (the refresh cadence, "Check service
    status" (`Preferences.checksServiceStatus`, default on, mirrored into
    the model through `setChecksServiceStatus`), iCloud
    (`CloudSyncSettings`: "Sync preferences and history",
    `Preferences.cloudSync`, off by default, mirrored through
    `setCloudSync(enabled:)`; see "iCloud sync" in the repo-root
    CLAUDE.md), Export (`ExportSettings`, only with an account and never
    in demo mode: "Export as CSV" and "Export as JSON", each a
    `ShareLink` whose `Transferable` writes the file only once a
    destination is picked; see "Usage history" in the repo-root CLAUDE.md
    for the file) and the "Privacy & data" link) and **About** ("Show the
    tour", `TourSettings`, see "Tour" below; "Send feedback",
    `FeedbackSettings`: a new issue in the project's GitHub repository
    with the running version and system already in its text, nothing sent
    until the user posts it; "Open Source", the GitHub mark, the
    repository; and, for a connected install, the "Demo mode" card).
  - **macOS** (`MacSettingsView`, the Settings scene): at most six
    toolbar tabs (seven didn't fit in French or German, and "This Mac"
    next to "General" was a distinction nobody makes), at a fixed 540 pt
    width so rows, pills and previews never stretch (the long tabs scroll
    inside 620 pt, the short ones are their content's height), the
    Accounts tab wider. Every toggle in it is a trailing switch
    (`SettingsSwitchToggleStyle`, `.settingsSwitch`, defined there; the
    Dashboard's navigation stack sets it too, so an account page's
    toggles match). **General**: the Demo card first while it leads;
    "Startup" (`StartupSettings`: Open at Login, with a pending-approval
    row and a nudge when the Dock icon is hidden but the login item is
    off), "Updates" (`UpdatesSettings`, `UpdateViews.swift`: "Check for
    updates automatically", the updater's state with "Check Now" or,
    once one is ready, "Restart to Update", and a footnote saying when it
    installs), "Dock" (`DockSettings`, `MacChromeSettings.swift`: Hide
    Dock icon, with `HiddenEverywhereWarning` once both icons are hidden
    and the island is off), Appearance, App icon (a footnote says only
    the Dock changes, see "App icon" in the repo-root CLAUDE.md), Usage
    rows, the refresh cadence, Service status, Peak notifications while
    offered, then Show
    the tour, Send feedback, Open Source and the Demo card. **Accounts**
    (`MacAccountsSettingsPage`, 760 pt wide, as the Mac's own account
    settings are: Mail, Calendar, Internet Accounts): on the left the
    accounts (`AccountListRow`s, the selected one on the accent wash)
    with + and − under them (+ opens `ConnectAccountSheet` over Settings,
    − asks through `DisconnectConfirmation`; both hidden in demo mode),
    and under those what concerns all of them: "Order by urgency" (2+),
    "Menu bar and island" (2+: `PrimaryAccountPicker`, the one home of
    `Preferences.primaryAccountID` since 3.2; the Menu bar and Notch
    island cards carry `MainAccountNote` under their previews instead of
    repeating the menu) and "Discreet mode" (`DiscreetModeSettings`: the
    switch, and under it which accounts it hides, "Hides Work", or, with
    none marked, where to mark them, so turning it on never looks like it
    did nothing; each account is marked on its own settings, Mike's call
    on 2026-10-22, after a version with a checkbox per account in this
    card); on the right the
    selected account (the first while none is), its identity and service
    over `AccountSettingsCards`; each pane scrolls on its own, and the
    detail back to its top for each account, so neither the list nor a
    way back is ever out of sight. The selection lives in
    `MacSettingsView` (`accountSelection`). Until 4.1 the tab was the
    general account settings with one account's cards under a second
    "Account" menu, Disconnect at the bottom (Mike, 2026-10-22: "it makes
    no sense that you can't"), and briefly a list whose row swapped the
    tab's content behind a "‹ Accounts" button that scrolled away.
    **Menu bar** (`MenuBarSettings`: "Show in menu bar" first, the
    `MenuBarVisibilityToggle`, with "Hidden while the notch island is
    on." under it while the island has the icon hidden, and the
    everywhere-hidden warning; then a live preview of the status item
    label on a light and a dark strip, rendered from the very same
    `MenuBarLabelModel.current` the `MenuBarExtra` uses, so the preview
    is the truth, the main-account note with 2+ accounts; the Style menu
    (`MenuBarStyle`); the window pill for single styles or the
    multi-select window chips for `multi` (1–3, options' order kept),
    under a "Window" or "Windows" title; then the "Yellow above 70%, red
    above 85%" (only while usage colors are on), "Reset countdown" (not
    for `multi`) and "Account name" (2+ only) toggles; the footnote also
    points at the Shortcuts-app route to a system-wide key). **Notch
    island** (`NotchIslandSettings`, two cards. The first: a live preview
    of the **peek** — what hovering shows — as this screen draws it (the
    real notch's silhouette, or the drawn notch or pill at the chosen
    height), from the same `NotchIslandModel.current` the panel draws (a
    session's name there is cut short to the card, `previewWing`); "Show
    usage in the notch", whose setter goes through
    `PreferencesModel.setNotchIsland(enabled:)` and
    `AppChrome.setNotchIsland(enabled:)`; the Both sides / Left / Right
    pill, only on a Mac with a notch; the shared `MetricChips` under a
    "Windows" title; "Peek on hover" with its "Hover delay" slider (0–1
    s, only while on); "Hide from screenshots and recordings"; and a
    footnote that states the status-item coupling. The second, "Screens
    without a notch" (shown on every Mac, since a MacBook closed on a
    monitor is one): the Style pill (Notch / Pill, with a one-line
    caption for each), Height (Menu bar / Custom, with a 20–44 pt slider
    while custom), "Hide until hovered" and "Hide in full screen", and a
    footnote saying when they apply. The sliders quantize in their
    binding rather than with `step:`, which draws a tick per step).
    **Claude Code** (only where Claude Code has run on this Mac,
    `Tour.claudeCodePresent`, and never in the demo, which has nothing to
    configure): the "Sessions" card (`ClaudeSessionsSettings`, see
    "Claude Code sessions" in the repo-root CLAUDE.md): "Show sessions in
    the notch", with "The notch island is off." under it while it is;
    "Notify when a session needs you", when a session asks for permission
    (its caption adds "once the hooks below are in" while they aren't),
    which asks for the permission and shows the same denied row as the
    notification cards; and "Permission prompts" with Install or Remove,
    the hooks' failure in red under it; each switch restarts the monitor
    through `AppChrome.updateClaudeSessions`; "A pet for each session",
    under the first while it is on, with "Off, a spinner and a count
    instead." under it, and "Show the session's name" under that, with
    "Beside the notch while the island is closed. Hovering shows it
    either way.", and under that, while it is on, "Avoid covering the
    menu bar", which asks macOS for the Accessibility permission when
    switched on (the system's own prompt), but only while it never worked
    for AIMeter (`AccessibilityState.mayPrompt`), and, while the
    permission is missing, shows what to do with an Open Settings button
    to that pane: "Allow AIMeter in Privacy & Security, Accessibility."
    for a permission never given, or, for one a copy signed another way
    holds (System Settings shows AIMeter on and macOS still doesn't trust
    this copy), "This copy of AIMeter needs Accessibility again. In
    System Settings, remove AIMeter with − if it's in the list, then add
    it with +." (the list may not show it at all once the permission was
    reset); the permission is re-checked whenever the app comes forward);
    then "Claude Code usage" (`ClaudeCodeSettings`: "Read Claude Code's
    local usage logs", off by default, whose `onChange` drives
    `UsageModel.claudeCode?.setEnabled`, and, once on, "Show today's
    total in the menu bar"). Until 4.1 the Sessions card sat in the Notch
    island tab and the usage card in This Mac. **Privacy & data**
    (`PrivacyView(showsDataControls: true)`: the iCloud and Export cards
    over the explanation, which is the same screen iOS links to from
    "Refresh & data"). `DEBUG` only: the `-AIMeterSettingsTab <tab>`
    launch argument (a `MacSettingsView.Tab` raw value: `general`,
    `accounts`, `menuBar`, `notchIsland`, `claudeCode`, `privacy`) opens
    Settings on that tab a second after launch, so each tab can be
    checked or captured without a click.
- **Privacy & data** (`PrivacyView`): private-by-default rows (on-device,
  Keychain, no tracking, the opt-in iCloud sync and what it carries, on
  iOS the Watch, and on macOS the opt-in Claude Code log reading,
  the Claude Code sessions with their optional hooks, the optional
  Accessibility permission and what it reads, the opt-in login item and
  the daily update check against GitHub), how connecting
  works, per family and platform (Claude's page and the code it shows,
  the Mac's read-only mirror of Claude Code's login; Codex's device
  code on ChatGPT's page, the Mac's mirror of `~/.codex`; GitHub
  Copilot's device code on GitHub's page), what each connection can
  access (Claude's `user:profile` scope as a chip + its two read-only
  endpoints; Codex's one usage endpoint with the CLI's own access;
  Copilot's quota endpoint, whose answer carries the user id, with no
  scope asked for) + the anonymous status-page check of each family and
  where to turn it off, and the independence/MIT/trademark footer naming
  all three companies. Only the services connected are described (all
  three with none, or in the demo: `ProviderCatalog.familiesToDescribe`),
  and the Claude Code rows and the Accessibility row only where Claude
  Code has run (`Tour.claudeCodePresent`). On the Mac it is a Settings
  tab, with the iCloud and Export cards above it (`showsDataControls`).
  Every claim must stay true to the code — the
  scope chip in particular must match `ClaudeOAuth.scope`, and the
  Copilot text the empty `CopilotDeviceAuth.scope`.
- The GitHub mark is a bundled PNG (`Shared/Media.xcassets/GitHubIcon`,
  light/dark appearance variants in its imageset) —
  SF Symbols has no third-party brand glyphs. It is pre-colored per
  appearance (light accent `#D97757` / dark accent `#E08B6D`) rather than
  tinted via `.renderingMode(.template)` at runtime: a solid-black source
  PNG gets compiled by `actool` into a monochrome/alpha-mask rendition
  whose `.foregroundStyle` tinting was unreliable in practice, whereas a
  pre-colored RGBA source always compiles to a plain ARGB rendition and
  just displays as-is — no template step to trust. It is the only
  third-party mark in the bundle: the provider itself is drawn by the
  neutral `ProviderMark`, never by Anthropic's logo (see "Design system"
  in the repo-root CLAUDE.md).
- **Connect sheet** (`ConnectAccountSheet`, since 4.0): which service,
  then that service's own sign-in. Adding opens the picker — the app's
  mark, "Add an account", one row per family in `ProviderCatalog.providerIDs`
  order (its SF Symbol from `ProviderCatalog.symbolName`, its name, one
  line on how its sign-in goes), the independence footnote naming
  Anthropic, OpenAI and GitHub, Cancel — and a tap swaps in the family's
  flow: `ConnectClaudeSheet` (below) for Claude, `CodexConnectView` or
  `CopilotConnectView` (both `DeviceCodeConnectView`,
  `DeviceCodeConnectView.swift`) for the other two. Signing in again
  (`ConnectAccountSheet(reconnecting:)`, from every "Sign in again") skips
  the picker: the account's family is known. The device-code flow, the
  shape Codex's and Copilot's share: the family's mark, title and
  explainer, on the Mac Codex's "Use Codex's login on this Mac" button
  (while `UsageModel.canConnectCodexCLILogin`: the CLI's file holds a
  login and no account mirrors it; one click registers an
  `.autoDetected` account, `connectCodexCLILogin`), then the one-time
  code the service minted (large, monospaced, a Copy button; "Waiting
  for your approval…" under it), a button that opens the service's
  device page (`auth.openai.com/codex/device`, `github.com/login/device`),
  Codex's note that device code login must be allowed in ChatGPT's
  security settings, the nickname field under the same rules as Claude's,
  the family's own independence footnote, and Cancel. The view polls at
  the service's interval until the login lands (then
  `UsageModel.completeConnection(_:displayName:)` or
  `reconnect(accountID:login:)` with the `ProviderLogin`, and dismiss),
  the code expires ("Try again" asks for a new one) or the sheet closes
  (the task goes with it). Every flow lands on the same two model
  entry points with a `ProviderLogin`; a login of another family than
  the account being repaired is refused with a message.
  - **Claude's flow** (`ConnectClaudeSheet`): `ProviderMark` header
  (prominent tile), title "Connect your Claude account", explainer,
  "Open Claude Sign-In", a
  nickname field (only shown once at least one account is already
  connected — a first connection needs no name; the placeholder is the
  first free "Claude N", `UsageModel.suggestedNickname`, and a typed name
  another account already uses disables Connect with an inline hint — the
  same `isNameTaken` rule renaming follows), paste field, Connect, then an
  independence footnote (not affiliated with Anthropic, reads only your own limits,
  never sends prompts, token stays on this device — said at the moment of
  connecting, not only in Privacy & data). The paste field accepts the
  OAuth code; **on macOS only** it also accepts a full credentials JSON
  (`~/.claude/.credentials.json`, with its own hint line), a fallback the
  iOS build deliberately lacks — an App Store build never asks for or
  accepts another app's credential file, which is at once what App Review
  guideline 5.2.2 objects to and what Anthropic's credential policy forbids
  ("developers may not collect, store, or intermediate Claude.ai
  credentials"). Surfaces the connection error inline
  (`UsageModel.connectionError`, a transient property distinct from an
  already-connected account's ongoing `lastError`, since a failed
  connection attempt never makes it into `accounts`) instead of dismissing
  on failure. Always goes through the app's own managed OAuth/paste flow,
  on both platforms — the macOS auto-detect path is never something a user
  picks here; it only ever applies automatically to the one CLI-mirrored
  login (see "Accounts vs. providers" in the repo-root CLAUDE.md).
  - **Reconnect mode** (`reconnecting:`, routed by `ConnectAccountSheet`
    by the account's family): the same
    sheet and the same exchange, titled "Sign in again", with no nickname
    field (the account keeps the name it has) and landing on
    `UsageModel.reconnect(accountID:login:)`, so the existing account is repaired
    in place rather than a new one created — see "Losing a login" in the
    repo-root CLAUDE.md for why that distinction is the whole point. Its
    extra footnote (signing in here mints AIMeter's own token, separate
    from Claude Code's) is the honest counterpart to the paste-the-JSON
    hint right above it: pasting the CLI's credentials is exactly what
    leaves two clients fighting over one rotating refresh token.
- **Demo mode**: `UsageModel.enterDemoMode()` loads two fabricated
  accounts (`DemoUsageData.accounts()`): "Personal" on the default mark
  with `DemoUsageData.snapshot()` — one of each window kind, spend, and
  extra usage — and "Work" on a symbol icon (`briefcase.fill`) with
  `secondSnapshot()`, a busier session, a quieter week and no per-model
  window, so its third row is the credits fallback and the dashboard
  reads as two genuinely different accounts (and shows the per-account
  icon without a brand mark). Each gets `DemoUsageData.timeline(for:)`,
  thirty days of samples per window ending on that snapshot's exact
  figures (a 5-hour session sawtooth of varying height, the weekly
  windows resetting where the snapshot says the week began and once a
  week before that, sessions idle at night), and on macOS
  `DemoUsageData.codingSessions` (the Claude Code section under its
  neutral demo title) and `DemoUsageData.claudeSessions` (the notch
  island's sessions, through `DemoSessions`: four with neutral titles,
  their pets picked by id, see "Claude Code sessions" in the repo-root
  CLAUDE.md), so every screen (rate limits, sparklines, history
  chart, pace, forecast, spend/extra cards, coding sessions, the
  island's pets) can be explored without a real Claude account. Its names are deliberately
  neutral — "Personal", "Work", and the per-model window "Top model",
  never a provider or product name —
  because demo mode is where App Store screenshots come from, and
  screenshots are store metadata: the third rejection (4.1(a)) was for
  third-party names in metadata, and "Claude"/"Fable 5" in every card
  header was exactly that. Exists
  mainly so App Store reviewers can evaluate the app without being handed
  credentials to a paid third-party account; also a source of screenshots
  that doesn't expose anyone's real usage. Purely in-memory: never calls
  `RefreshService`, never touches the App Group `SnapshotStore` or
  `WidgetCenter`, so it can't leak into widgets or a real connection, and
  `paceReady` short-circuits true so pace/forecast don't show the
  "learning" state on fabricated data with no history. The one way out
  of memory is iOS's Live Activity card, on purpose (a reviewer can see
  one): its switches start a real activity on the demo's figures, which
  `UsageModel.endDemoLiveActivities` ends, with the switches, when the
  demo ends, or at the next launch if the app was quit in it. Scheduling a
  `reset.`/`runout.` notification while in demo mode is a deliberate no-op
  (`UsageModel` passes `nil` in place of the demo snapshot) so a fake
  reset date can never produce a real notification. Entry and exit both
  live in Settings only — a "Demo mode" section offers "View Demo" or
  "Exit Demo": at the top of the list while disconnected or while demo is
  active, and at the very end once a real account is connected (entering
  the demo is in-memory only and `exitDemoMode` reloads the real accounts
  untouched, so there is no reason to hide it — it is also how the
  App Store screenshots get taken on a Mac that has a login); the
  dashboard's disconnected card stays just Connect, no demo affordance, to
  keep it from looking like a second, competing call to action. Provider
  Detail's bottom button also becomes "Exit Demo" (both platforms) instead
  of "Disconnect Claude" (iOS-only) while active.
- **Landscape (iPhone)**: `verticalSizeClass == .compact` swaps the
  dashboard for a full screen of the same account cards
  (`AccountSectionView(linksToDetail: false)`, no sparkline).
- **macOS menu bar**: one status item regardless of how many accounts are
  connected — `MenuBarExtra` has no per-instance configuration the way
  widgets do. The label (`MenuBarLabel`, drawing a `MenuBarLabelModel`)
  shows the *primary* account (`UsageModel.primaryAccountUsage(preferredID:)`)
  in the user's `menuBarStyle`: the variable-value `gauge.with.needle`
  with or without the number, the number alone, a drawn bar or battery
  that fills with the figure, or 2–3 windows as compact text ("S 42% ·
  W 18%", `menuBarMetrics`). Fill and number always follow the
  **displayed** percentage, so a "Remaining" reading never contradicts
  its own glyph (the battery therefore drains as you use under Remaining
  and fills under Used). Optional: the primary window's reset countdown
  appended ("· 1h 20m", ticking once a minute), the account's nickname in
  front (cut to 8 characters; the full name stays in the accessibility
  label), and a red label once the window would be red on the dashboard.
  Whatever the style, the exact value(s) stay in the `.help` tooltip and
  the accessibility label — icon-only mode must never be the only place
  the number lived. See "macOS chrome prefs" in the repo-root CLAUDE.md
  for the keys, defaults and the migration from the old "Show
  percentage" toggle. The whole status item disappears when `statusItemVisible`
  is off (`MenuBarExtra(isInserted:)`). The popover shows a peak-hours
  badge row at the top only while peak is active (never, while the policy
  is retired; peak is Claude-wide, not per account, so this isn't
  repeated per section), a compact `ServiceStatusBanner` only
  while the provider reports an incident (same rule as the Dashboard's),
  then **every**
  connected account that discreet mode leaves (`UsageModel.glanceAccounts`;
  all of them marked, a "Hidden in discreet mode" line instead), under
  one "Updated X ago" line (the newest account's), each as a card
  (4.0.1, `PopoverAccountRow`; Mike's ask, 2026-10-21: the new iPhone's
  card, one window on the left and the other two on the right): the
  identity on top (mark, nickname, plan pill), then the protagonist
  (`AccountCardLayout.hero`) on the left, 124 pt wide (its short title,
  the figure at 30 pt with "%" and "used"/"left", a 6 pt lit bar,
  "Resets in …" under it), and the others on the right, their first
  line on the protagonist's title line (`.firstTextBaseline`), as
  `PopoverCompactRow`: the Dashboard's compact row (name, a 5 pt bar,
  figure, bare reset) on fixed columns (56, flexible, 34, 46 pt), the
  same in every card, so bars, figures and resets line up from one
  account to the next; every name is the short one ("Session", "Week",
  "Fable", "Premium") on both sides. An account with one window has the
  protagonist across the card. (Mike's review, 2026-10-21: the long
  "5-hour session" beside the short "Session", a right column floating
  at the protagonist's middle, and each card's columns at their own x
  read as unfinished.) The status tail under them only when
  it has something to say. 400 pt wide. The popover is the system's own
  glass, clear on macOS 26 and later, so the app's background lies over
  it at 78 % (solid under Reduce Transparency) and each card is a solid
  `Theme.card`: 4.0.0 drew straight on the clear glass, and with a
  window behind the popover its secondary text could not be read. The
  card under the pointer darkens a little and a click opens that
  account's Provider Detail in the Dashboard window
  (`AppChrome.openAccount`: the window's `NavigationStack` path lives in
  `ContentView`, which registers `AppChrome.presentAccount` on appear,
  the same bridge shape as `presentConnect`, a request made while the
  window is closed waiting in `pendingAccount`). No reorder affordance:
  the popover follows the registry order the Dashboard writes. The list
  sits inside a height-capped `ScrollView` (480 pt) so a handful of
  accounts still fit and more scrolls; while more is below, the list
  fades out along its bottom 44 pt (a mask, so the glass shows through)
  and a chevron there scrolls to the end, both gone once the end is in
  sight (the list's bottom measured with `onGeometryChange` in the
  scroll view's space); then, only with "Show today's
  total in the menu bar" on and something to show, one `Claude Code
  today: …` line (`ClaudeCodeUsageModel.menuBarLine`); then the footer,
  which reads like a menu (`PopoverMenuItems.swift`: one item a line,
  its shortcut at the trailing edge, lit under the pointer like the
  cards, separators between the groups): "Open AIMeter"
  (`AppChrome.revealMainWindow()`), "Refresh All" ⌘R, "Add Account…" ⌘N
  (hidden in demo mode; once an account is connected the only way to
  add another from the menu bar, since the Dashboard window stays
  closed by default while the Dock icon is hidden; see "macOS hiding &
  re-entry" below); "Discreet Mode" ⇧⌘D (with an account connected; the
  same switch as Settings' card and the Usage menu's, see "Discreet
  mode" in the repo-root CLAUDE.md) and "Open at Login" as switches
  (`PopoverMenuToggle`, the whole line flips it; Open at Login reads
  `LoginItemManager` live, re-read each time the popover opens); then
  "Settings…" ⌘, and "Quit AIMeter" ⌘Q. "Open AIMeter" reopens the
  Dashboard window even after `AppDelegate` closed it at launch, because
  the scene registers the reopen hook on first appearance, before that
  close ever runs. Anything the popover opens closes it on the way
  (`AppChrome.closeMenuBarPopover`, called by every `AppChrome` route
  that brings a window of the app forward: the Dashboard, an account,
  Connect, Settings, the update window, the tour): a window of its own
  app coming forward doesn't dismiss a `MenuBarExtra` window, so until
  4.0.1 the popover stayed open in front of the Settings window it had
  just opened, as the notch island once did. It closes through SwiftUI's
  own `dismiss`, which the popover hands to `AppChrome` on appear
  (`dismissMenuBarPopover`; its window, through `WindowReader`, only
  says whether it is open). Measured on macOS 27 with clicks on the real
  status item: `close()` on the window, and `performClick` on the status
  item's button, both left the item thinking the popover was open, so
  the next click did nothing and it took two to open again; with
  `dismiss` one click opens it after Settings, an account or Open
  AIMeter.
  "Refresh All" calls `refreshAll()` (every account, concurrently). The popover
  presents **no sheets of its own**: a sheet attached to a `MenuBarExtra`
  window renders clipped and floating beside it, so "Connect", "Add
  account" and an account's "Sign in again" all go through
  `AppChrome.connect(.add / .reconnect(account))`, which reveals the
  Dashboard window and hands it the request (`AppChrome.presentConnect`,
  the Dashboard's live hook, set on appear and cleared on disappear; a
  request made while the window is closed waits in
  `AppChrome.pendingConnect` for the Dashboard's `onAppear`). The Usage
  menu's "Add Account…" uses the same route, and so does a block's "Sign
  in again". Peak-hours
  state folds into the status item's
  tooltip/accessibility text rather than a second glyph there (see "Peak
  hours" in the repo-root CLAUDE.md); the popover's top badge row is the
  visible one, where there's room.
- **macOS notch island** (`AIMeter/Views/NotchIsland/`, on by default
  on a Mac with a notch since 2.0 — see "Notch island" and "Notch island
  prefs" in the repo-root CLAUDE.md for what it shows, the interaction
  rules and the keys): a borderless, transparent, **non-activating**
  `NSPanel` (`NotchIslandPanel`: on every Space, over full-screen apps,
  never main and **never key** — a key non-activating panel steals the
  keyboard from whatever the user was typing into, which is why there is
  no Esc) hosting the SwiftUI tree (`NotchIslandRoot`) in a forced dark
  `colorScheme`. One `NotchIslandController` (`AppChrome.notchIsland`),
  started from `AIMeterApp`'s dashboard `onAppear` — which also publishes
  the app's `PreferencesModel` to `AppEnvironment.prefs`, the island
  living outside the scene graph (`AIMeterApp.init` publishes it first,
  so a launch that restores some other window and no Dashboard still
  starts the island) — and again, idempotently, from
  `applicationDidFinishLaunching`; `AppChrome.setNotchIsland(enabled:)`
  starts and stops it live from Settings. The tree reads
  `NotchIslandState` (data only: level, mode, bar height, the collapsed
  slab's width, revealing, hovering) and reports through
  `NotchIslandActions` (tap, hover, the slab's frame).
  - **Level**: `mainMenu + 3`, above the menu bar itself — on macOS 26
    the bar draws at the status-item level, and at `.statusBar` its
    titles painted over the island and took its hover — and still below
    pop-up menus.
  - **Screen**: `NotchIslandGeometry.target` over `NSScreen.screens`
    (the first with a notch, else the main screen), described as plain
    rects (`NotchIslandController.describe`: `safeAreaInsets.top` and the
    two auxiliary top areas; without a notch the menu bar's height from
    `visibleFrame` stands in for `safeTop` — `NSStatusBar.thickness` is
    22 even under a 32 pt notch bar, so it is never read as the bar's
    height — and the mode follows `notchIslandForm`: the drawn notch
    (`NotchIslandGeometry.Mode.drawn`: the same silhouette fused to the
    top edge over the menu bar's centre, the bar tall, as wide as its
    row) or the pill (`.pill`: a capsule `topInset` below the edge, inside
    the bar unless a custom height outgrows it). The user's own display
    with the MacBook closed is the common case; the 34" ultrawide this
    was built on reports a 30 pt bar. Re-evaluated on
    `didChangeScreenParameters`, wake, a Space change and any
    preference write (`observePreferences` — `PreferencesModel` keeps
    one stored value, so every write wakes it; everything it calls is
    idempotent), and the panel is re-framed
    only when the screen, the options or the frame actually changed.
    `DEBUG` only: the `-AIMeterForceDrawnNotch YES` launch argument
    tries the drawn forms on a Mac with a real notch, and
    `-AIMeterIslandDirector YES` hands the island to the website's video
    recorder (`IslandDirector`; `NotchIslandController.direct` opens a
    level as if the cursor had, see `Scripts/IslandVideo/CLAUDE.md`).
  - **Interaction**: every cursor and click event is fed to the pure
    `NotchIslandInteraction` (Shared, tested), and the controller only
    arms the one timer it asks for and hands the view the level it lands
    on. Three levels: **collapsed** is the bare notch (a drawn notch or
    pill shows its row, unless concealed — see below; a Claude Code
    session at work adds its pets (or, with "Show the session's name",
    its pet and name) on the left and their count on the right,
    centered on the notch,
    `SessionWings`, the slab growing and shrinking with them on the
    opening spring; a drawn notch's or pill's row puts its pets and
    count at its two ends, or with the name reads like the notch's, the
    lead's pet and name first and the other pets before the count, the
    name in the room the rest of the row and the menu bar leave,
    `NamedRowLayout`);
    staying on it for
    the dwell (`notchIslandHoverDelay`, 250 ms by default) opens the **peek**,
    the wings beside the notch with the chosen windows' figures, on the
    side(s) `notchIslandLayout` says (both, left or right — a one-sided
    peek is an asymmetric slab); only a click opens **expanded**:
    every account, the full lines, the footer (staying on the open
    wings for a second opened it too, until 3.0.1). A drawn notch or
    pill in sight skips the peek — it would only show the row already
    there — so resting on it does nothing and a click opens it
    (`skipsPeek`, set on every event from
    `NotchIslandVisibility.showsRowWhenCollapsed`); a concealed one still
    peeks, which is what brings its row back, and the first-run reveal is
    a peek everywhere. A click on the open island leaves it open, so its
    rows can be clicked. Leaving collapses after
    150 ms whatever opened it (short, like boring.notch's: the slab is
    one contiguous shape, so moving from a wing into the body never
    leaves it). With a real notch, hover is SwiftUI's own `onHover` on
    the slab — it follows the slab's animated frame for free, and a
    transparent window only receives the cursor over painted pixels
    anyway, which is why there is no slack beyond the notch: a hover
    region wider than the slab would have to be painted, and painted
    pixels take clicks from the menu titles beside the notch. On a
    screen without a notch the controller tracks the pointer instead
    (`NotchIslandController+Pointer.swift`): a global and a local
    `mouseMoved` monitor (no permission), plus a 20 Hz poll only while
    AIMeter itself is frontmost (the global monitor is silent then),
    put the pointer against `NotchIslandGeometry.hoverRegion` — the
    collapsed row's place from the top edge down, plus `hoverSlack` —
    and the slab as drawn, through `NotchIslandVisibility.pointerIsInside`,
    and only a change of side reaches the interaction. That is what
    makes a **concealed** island (hidden until hovered, or behind a
    full-screen app) reachable at all — it has no pixels for the window
    server to route the mouse to — and keeps the transparent strip above
    the pill from being a dead band; SwiftUI's hover is ignored there,
    so two sources never race each other's enter and leave. Concealed,
    the slab is offset up past the top edge on the level spring
    (`NotchIslandRoot.concealDistance`) and the mouse shape is resampled
    once it settles, so a hidden island stops catching the menu bar's
    clicks. With "Peek on hover" off, a concealed island shows its row
    while the pointer is on its place — nothing would ever open it
    otherwise. Full screen is checked from the on-screen window list on
    Space changes (and 0.4 s and 1.2 s later), app activations, wake and
    screen changes, plus every 3 s only while it holds the island hidden;
    `relocate()` recomputes concealment too, so a launch with "Hide until
    hovered" starts hidden and a lid opened onto a real notch never
    leaves the island stuck above the edge. The panel's `sharingType` follows
    "Hide from screenshots and recordings". The hosting view's `hitTest`
    is confined to the slab's frame (reported by the view on every
    frame of the animation), so a click beside the wings or in the
    shadow falls through. While open, a global and a local mouse-down
    monitor (`NSEvent.addGlobalMonitorForEvents` — mouse monitors need
    no Accessibility permission, keyboard ones would) close it on a
    click outside the slab; both are removed on collapse, so a collapsed
    island costs nothing. The first user-initiated open calls
    `PreferencesModel.markNotchIslandDiscovered` (the deferred
    status-item coupling). The **reveal**: once, two seconds after the
    first start with the island on, the controller opens the peek
    itself with the caption and closes it six seconds later unless the
    cursor is inside or the user clicked (`notchIslandRevealed` is
    written when the peek actually shows, so a launch that crashed or
    quit before then still owes it). The unit-test host is this same
    app: `AppChrome.startNotchIslandIfEnabled` skips the island when
    `XCTestConfigurationFilePath` is set, so a test run never puts a
    panel on the tester's notch. The wings (`CollapsedRow`, or its
    "Connect" glyph with no accounts) are the peek and stay as the
    expanded island's header. They never show a Claude Code session:
    with one at work the peek is `SessionWings(peeking:)` instead, the
    session's pet and name staying put and what it is doing joining the
    count on the right; with none, the figures. Whatever changes swaps
    over (`AnyTransition.notchSwap`: the old fades out in 0.12 s before
    the new fades in, so the two never show over each other); peeking
    with figures on both
    sides, the two wings come out as wide as each other, each one's
    figures at its outer end (`NotchWings`), so the slab stays centered,
    while a one-sided layout keeps its one wing; heading the expanded
    island (`CollapsedRow.fill`, the body's width) each wing reaches out
    to the body's edge, since every pet is in its session's row there.
  - **Motion** — boring.notch's system, rebuilt (it is GPL-3.0: read for
    the recipe, nothing copied). The window is sized **once** per
    screen, to the largest island it can show plus the shadow
    (`NotchIslandGeometry.windowFrame`: the notch with the widest wings
    on both sides, or a drawn row at its widest, `maxDrawnRow`, a whole
    session name in it; never narrower than `expandedWidth`, the bar plus
    `maxBodyHeight` tall, `shadowPadding` around; centered on the notch
    — on the screen for the drawn one — flush with the top edge), and
    **never resized**. Everything that moves is SwiftUI layout inside
    it: the black slab is the *natural size of its content* — collapsed,
    a clear rect the notch's width plus `closedOverhang` (black on
    black, invisible: the slab *is* the notch); peeking, the wings row;
    expanded, the row with the body (`expandedWidth` wide) under it —
    drawn through `NotchIslandSurface` (for a notch, real or drawn:
    content inset by the ears, `.background(.black)`,
    `.clipShape(NotchShape)`, a 1 pt black line along the top so the
    anti-aliased edge never shows a seam against the bezel; for the
    pill: `IslandPillShape`, a continuous rounded rectangle whose radius
    eases from half the row's height — a capsule — to 24 pt open, with
    the content inset `pillContentInset`; either way a shadow only while
    open or hovered, never while concealed). The pill's gap above it is
    the root's top padding, outside the slab, so it is neither drawn nor
    hit-tested. A taller custom island draws its collapsed row larger
    through the `notchIslandRowScale` environment value; the expanded
    account rows keep their size. A level change
    is therefore one layout change, and one implicit animation carries
    all of it — size, the shape's radii (`animatableData`, from the
    notch's 6/14 to the open 19/24, `NotchIslandGeometry.Radii`), the
    shadow: `.animation(_, value: level)` with boring.notch's pair, a
    spring of `response` 0.42 / `dampingFraction` 0.8 on the way open
    (a touch of overshoot) and 0.45 / 1.0 on the way shut (none). The
    body and the reveal caption come and go with
    `.scale(0.8, anchor: .top)` + opacity on `.smooth(0.35)`, so they
    unfold out of the bar while the slab grows under them; what sits
    beside the notch swaps over 0.3 s, the old out before the new in
    (`AnyTransition.notchSwap`); the hover flap (`hoverFlap`, 10×3 pt, collapsed
    only) and the shadow ride an `interactiveSpring` (0.38 / 0.8).
    Nothing under Reduce Motion. No measurement goes up and no frame
    comes down: the wings' layout (`NotchWings`) reports a custom
    alignment guide (`HorizontalAlignment.notchCenter`, its gap's
    center), every container up to the root inherits it from that one
    child, and the root aligns it with the window's center, which the
    controller put on the notch — so the slab stays fused to the notch,
    one wing or two, and the body is centered under it without the
    window measuring anything.
    Every `SegmentView` text is `lineLimit(1)` + horizontal `fixedSize`,
    so a segment never wraps while the slab animates. The window
    server decides which pixels of a transparent window take the mouse
    by sampling the content's alpha — when the window is shown or
    **resized**, and not reliably otherwise: a panel shown before
    SwiftUI had drawn was sampled empty and stayed deaf (no hover, no
    click, while the reveal still drew fine), and `invalidateShadow`
    alone did not refresh a shadowless window. So the controller
    resamples by resizing (`resampleMouseShape`: one point taller for
    one turn, then back — the content is top-aligned and the extra point
    transparent, nothing visible moves): right away on the view's first
    slab report, and 700 ms after the slab last changed size (past the
    spring), so a closed island stops catching clicks where the wings
    were. The hosting view also answers `acceptsFirstMouse` with true:
    the panel is never key, so every click on it is a "first" click
    AppKit would otherwise spend on activation. The slab's frame is
    reported in a named coordinate space on the root (which fills the
    hosting view) through `onGeometryChange`, and until the first report
    nothing is confined. Not through a preference key read with
    `onPreferenceChange`, which is what it was: on macOS 27 that
    delivered the key's default once and never the slab's frame (the
    `GeometryReader` measured every frame; the controller only ever got
    `.zero`), which went unnoticed while SwiftUI's own hover drove the
    island and surfaced with the pointer tracking — the open island
    closed as soon as the pointer left its top row, on the way to the
    footer. The popover's list height, measured the same old way, was
    checked on macOS 27 and still works.
    Two earlier designs are recorded here so they are not
    retried: resizing the window per level while SwiftUI re-measured
    the content (each resize re-laid the content out, which
    re-reported, which resized again — and the two never agreed on a
    frame mid-animation, which is what read as clunky), and sizing the
    window from content the view measured and reported through
    preference keys (a feedback loop into `@Observable`, 99 % CPU, and
    a backdrop that moved separately from the content it was meant to
    frame). Every write into `NotchIslandState` is still guarded by an
    equality check — `@Observable` notifies on every assignment.
    The panel overrides `constrainFrameRect` to return the frame as
    given: AppKit otherwise pushes every window below the menu bar, and
    the island lives in it. Two AppKit traps, both hit once: setting
    `isFloatingPanel` *after* `level` silently resets the level to
    `.floating` (3), under the menu bar, which then takes every hover and
    click (the panel sets no `isFloatingPanel`; `NotchIslandPanelTests`
    pins the level above `.statusBar`); and an `NSHostingView` that is
    the panel's `contentView` sizes the window from its content inside
    AppKit's own constraints pass and SwiftUI requests another pass from
    within it — "more Update Constraints in Window passes than there are
    views in the window", a crash on the first peek — so the hosting
    view sits inside `NotchIslandContainerView`, a plain autoresizing
    container that forwards `hitTest` to it, with `sizingOptions` empty.
  - **No timers while collapsed**, but for a Claude Code session's (and
    the menu bar clearance's 20 s re-read, which runs only while a
    session's name shows beside the notch with "Avoid covering the menu
    bar" on and the Accessibility permission given):
    its pets step on a shared 8 Hz `TimelineView` inside each
    `PixelPetView` (a leaf, so the slab's identity never changes), only
    while one is shown; with pets off the spinner is the `rays` symbol
    under a repeating variable-color symbol effect, which the system
    animates; and the monitor's task, not the view's, puts the "just
    finished" pet away. While open, one `.task` sleeps to
    each minute boundary and refreshes the relative resets, cancelled on
    collapse — a sleep rather than a `TimelineView`, since swapping the
    slab in and out of one would change its identity at the very moment
    it animates. Footer: Refresh and Open AIMeter grouped left, Settings alone
    right; it activates the app only for Open AIMeter
    (`AppChrome.revealMainWindow`) and Settings (`AppChrome.openSettings`:
    the dashboard scene's captured `openSettings` action, else the
    `showSettingsWindow:` selector), and those two (with the update
    notice, "Sign in again" and "Connect") close the island on the way,
    `NotchIslandActions.close`; Refresh runs `refreshAll()` in place
    and leaves it open; no keyboard shortcut (the panel is never key).
    Like the popover it presents no sheets of its own.
  - **Picking the sneak** (`NotchIslandController+Picks.swift`, see
    "Notch island" in the repo-root CLAUDE.md for the rules): the views
    report through `NotchIslandActions` (`pickSession`, `pickAccount`,
    `rotate`, `close`), handed down as the `notchIslandActions`
    environment value, nil in Settings' preview, where nothing is
    clickable. `PetGroup` makes every pet but the lead's clickable (a
    click on the lead's opens the island, like one anywhere else);
    `SessionRowView` and `AccountGrid` make their rows clickable with two
    or more to choose from, the one in the sneak marked and the one
    under the cursor fainter (`IslandRowHighlight`, drawn past the row's
    frame so nothing moves); a mouse drag is a `DragGesture` on the slab,
    two fingers a local `scrollWheel` monitor (`NotchIslandSwipe`), and
    the click that ends a drag which turned the island neither opens it
    nor picks (`tapsIgnoredUntil`). The session picked lives in
    `NotchIslandState.sessionPick`; the account, in `primaryAccountID`,
    or in demo mode `NotchIslandState.demoPrimaryID`, so a demo pick
    never overwrites the real one. A turn nudges the row 8 pt the
    swipe's way and springs it back (`NotchIslandState.nudge`), not
    under Reduce Motion.
  - **Accessibility**: VoiceOver cannot hover, so the island's open
    layers are unreachable to it by design — nothing lives only in the
    island (the popover, the Dashboard and the tooltip carry every
    figure), and the collapsed element still speaks the primary
    account's figures.
  - More than four accounts scroll inside a height-capped list, its
    height measured with `onGeometryChange` (a preference read with
    `onPreferenceChange`, the way `MenuBarView` measures its own, got
    only its default in this panel on macOS 27). Under them, while any
    Claude Code session is shown, `SessionsSection`: up to five rows
    (`SessionRowView`: the pet at 1.5 pt a pixel, with its "!" while it
    waits, or the mark with pets off; the name with the folder dimmed
    after a title; and the status on the trailing edge, yellow while it
    needs permission), "N more", and while the hooks aren't installed the
    `HooksInvitation` line (Install / Not now). `maxBodyHeight` (620) is
    sized for four accounts, the incident notice, five sessions and the
    footer.
  - The accounts are one set of columns (`AccountGrid`,
    `NotchIslandRows.swift`, laid out by `IslandColumns`,
    `NotchIslandColumns.swift`): per account a divider, the header, a
    line of figures (`SegmentText`, the separators between them) and a
    line of bars (`SegmentBar`), and a status line, each view tagged with
    its line and its cell (`islandCell`: a span across the width, or a
    figure, a separator or a bar in a column). Each column is as wide as
    its widest figure; the layout's ideal width is the columns with 10 pt
    either side of each separator, and offered more, the separators share
    the extra evenly (`IslandColumns.Metrics`), so the first column sits
    on the left edge and the last ends on the right one; offered less, it
    keeps its ideal width and `ViewThatFits` picks a smaller size: 12, 11
    and 10 pt. A custom layout and not a SwiftUI `Grid`, which is what it
    was until 3.2.0: with its separator columns flexible, a `Grid`
    holding an account of two windows beside one of three laid out wider
    than it was offered (measured: 341 pt ideal, 451 pt for the 366
    offered, 705 for 1000) and the island cut both ends of every line;
    before that, flexible cells of its own had split its width into equal
    columns and pushed it 13 pt past the edge. `NotchIslandColumnsTests`
    renders the screenshot's two accounts and checks the width. One inset, `ExpandedContent.horizontalPadding`
    (18 pt), gives the header's wings, the accounts, the sessions and the
    footer the same two edges; the footer draws its outer icons against
    them.
- **What's new** (both platforms, `WhatsNewView`): a release's notes, a
  header and one row per item (its symbol on the accent wash, title,
  detail) over the caller's buttons (`CapsuleActionButton`); an item
  that names a tour feature has that feature's card under its text,
  indented past the symbol (`TourFeatureCard`: the animation at 140 pt
  and the button that turns it on, or "On"), for the features that
  apply here and were off as the notes opened (decided once, so a card
  turned on from there stays to say "On"), or that only explain. iOS
  shows it as a sheet over the Dashboard once after an update
  ("Continue"), as tall as the notes (`WhatsNewSheet`: the content
  measured, one height detent plus the home indicator's inset, the full
  height and a scroll only for notes taller than the screen); the Mac in
  the update window, which is its content's size too: the notes scroll
  once they pass the screen's height less 200 pt, the buttons pinned
  under them in sight. Which notes are
  due, and why the notes are JSON: "Updates (macOS) and What's new" in
  the repo-root CLAUDE.md.
- **Tour** (both platforms, `TourView`; see "Tour" in the repo-root
  CLAUDE.md for who gets it and the steps): "Skip tour" at the top
  right, the step's animation (`TourVisual`, 170 pt, on the accent wash,
  or on a dark desk for the Mac's notch scenes; each loops on a spring
  while shown and holds its last frame under Reduce Motion), its title
  and line, the buttons (the action and "Not now", "Later" on the last
  step; or "On" / "Connected" and "Continue", "Done" on the last), and
  the dots (one VoiceOver element, "Step 2 of 6"). What is on is read
  again after each action and whenever the app comes back to the front
  (from a system prompt or System Settings). The Mac's window
  (`TourWindow`) is 460 pt wide with a hidden title bar, centered;
  closing it counts as skipping. iOS's cover (`TourCover`) centers the
  step and scrolls only when a large text size needs it. Settings'
  "Show the tour" row (`TourSettings`: the sparkles glyph on the wash,
  a chevron, a footnote) sits above "Open Source" on both platforms.
  `DEBUG` only: the `-AIMeterShowTour YES` launch argument opens the
  tour at launch on any install, to check or capture it.
- **macOS update window** (`UpdateWindow`, a `Window` scene,
  `AIMeterApp.updateWindowID`, opened through
  `AppChrome.openUpdateWindow`, the same bridge shape as
  `openDashboard`; a request made before the Dashboard scene appeared
  waits in `pendingUpdateWindow`): with an update ready, "AIMeter 3.0.0
  is ready" over its notes without their cards (or a link to the
  release on GitHub when it has none), a line saying to move the app to
  Applications when it can't be replaced in place, and "Later" /
  "Restart to Update"; after a version installed by hand, this
  version's notes with their cards and "Continue"; after one installed
  from the notice, "Turn on what's new" with the new features still off
  and "Continue"; otherwise the check's state ("Check for Updates…" in the app menu
  opens it while it checks). Closed before the restart, and kept out of
  window restoration altogether (`NonRestorableWindow`, like the tour's):
  a relaunch that restored only this window would open no Dashboard, the
  scene that hands `AppChrome` its window bridges on appear, so nothing
  could open a window afterwards (measured, after the app was killed with
  the notes open: no island either, before `AIMeterApp.init` published the
  preferences). The
  `UpdateReadyNotice` ("AIMeter 3.0.0 is ready", the accent wash, opens
  this window) sits at the top of the menu bar popover and the
  Dashboard while an update waits; the notch island's footer adds an
  icon beside Settings.
- **macOS hiding & re-entry** (`AppDelegate` + `AppChrome`, the project's
  only AppDelegate — SwiftUI has no scene hook for either concern):
  - `hideDockIcon` → `.accessory` activation policy, applied in
    `applicationWillFinishLaunching` so a hidden icon never flashes.
  - `.accessory` does **not** suppress `WindowGroup`'s auto-open (measured —
    the window is up by `applicationDidFinishLaunching`), so the delegate
    closes it explicitly, but *only* while `statusItemVisible` is true
    or the notch island is on (its footer opens the Dashboard, so it is
    an affordance too). With both icons hidden and no island the
    dashboard is the app's sole affordance, so launching has to produce
    it or the app would be unreachable — that combination is the one
    case where a launch legitimately shows a window; Settings'
    `HiddenEverywhereWarning` (the Dock card in General, the Menu bar
    tab) follows the same three-way rule.
  - Re-entry when everything is hidden is **relaunching the app**
    (Finder/Spotlight/`open -a`), which fires
    `applicationShouldHandleReopen` — verified to arrive with no Dock icon
    and no status item, and without spawning a second instance. It reveals
    the dashboard without clearing the hidden prefs: needing to relaunch
    once shouldn't permanently undo the user's chosen chrome. There is no
    global hotkey, deliberately — it would cost an Accessibility/Input
    Monitoring TCC permission to guard a path that already works. The
    permission-free equivalent is the `ShowUsageIntent` App Intent
    (`AIMeter/Intents/`): the user adds "Show Usage" to the Shortcuts app
    and assigns it a key there; it calls `AppChrome.revealMainWindow()`
    the same way a relaunch does.
  - AppKit callbacks can't reach SwiftUI's `openWindow`, so the dashboard
    scene publishes it to `AppChrome.openDashboard` on appear — same
    bridging shape as `AppEnvironment.shared` for the refresh schedule.
    Dashboard windows are matched by the identifier SwiftUI derives from
    `WindowGroup(id:)` (`dashboard-AppWindow-…`) so the Settings window,
    also main-capable, is never mistaken for one.
  - **Quit still means quit.** Hiding changes only what is visible; the menu
    bar Quit button remains an unconditional `NSApp.terminate`.
  - **One instance.** `applicationWillFinishLaunching` terminates any
    other running copy of the bundle ID (`AppChrome.terminateOtherInstances`;
    skipped under `XCTestConfigurationFilePath`, since the unit-test host
    is this same app and a test run must not quit the copy the user has
    running — it did once).
    Launch Services only refuses a second launch of the *same* bundle,
    so the installed copy started by the login item and a build run from
    Xcode (or a copy left in Downloads) ran side by side — two islands
    on the notch, two status items, two dashboards, and two refreshers
    rotating the same tokens against each other. The copy being launched
    wins, since it is the one the user just asked for.
