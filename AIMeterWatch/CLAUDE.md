## Apple Watch

The Watch app (`AIMeterWatch`, `com.mikealvarado.aimeter.watchkitapp`,
watchOS 10+) and its complications (`AIMeterWatchWidgetsExtension`,
`…watchkitapp.widgets`) show what the iPhone last fetched, for every
account. They hold no credentials and never fetch: the iPhone is the only
source, so the Watch's freshness is the iPhone's. See "Apple Watch" in
the repo-root CLAUDE.md for why (the token rotation the app and the
widget already race over; one copy of the login fewer).

- **The payload** (`Shared/WatchPayload.swift`, `Codable`, versioned):
  the accounts in the Dashboard's order (`accountID`, `providerID`,
  `displayName`, `icon`, the last `UsageSnapshot`) and the display
  preferences by raw value (display mode, reset style, glance metric,
  third-row fallback, credit amounts, usage colors). One JSON blob under
  `WatchPayload.key` in the WatchConnectivity dictionary, the version
  beside it; always whole, never a delta, since `updateApplicationContext`
  keeps only the last value and the Watch may have missed any number.
- **The iPhone's side** (`AIMeter/Services/WatchBridge.swift`, iOS only):
  `WCSession`, activated from `UsageModel.init` where
  `WCSession.isSupported()` (so never on an iPad). `pushSoon()`
  coalesces a burst (a sweep's accounts land one by one; Settings writes
  several keys) into one `updateApplicationContext`, sent only when the
  payload differs from the last one sent and the session is activated,
  paired and the Watch app installed; a changed snapshot also goes through
  `transferCurrentComplicationUserInfo` while
  `remainingComplicationUserInfoTransfers` allows (about fifty a day), so
  a face updates without the Watch app opening. `UsageModel.notifyWatch`
  is called after every sweep (`refreshAll`, `refreshAllIfStale`,
  `refresh(accountID:)`), `loadAccounts`, a reorder, a rename or icon
  change (`propagateName`), a disconnect, and every widget-visible
  preference change (`PreferencesModel.onWidgetVisibleChange`, set by the
  app's model; the widgets and the Watch never set it). Demo mode sends
  nothing. The Watch's one message, `[WatchPayload.refreshKey: true]`, is
  answered with `refreshAllIfStale()` and a payload; `sendMessage` from
  the Watch launches the iOS app in the background when it isn't running,
  which is what makes the Watch's Refresh work with the iPhone in a
  pocket. `refreshAllInBackground` (the iOS `BGAppRefreshTask`) does not
  push: it has no model; the Watch's own background refresh asks.
- **The Watch's side** (`AIMeterWatch/WatchStore.swift`): the payload is
  written into the Watch's own App Group through the same types the
  phone's widgets read (`AccountRegistryStore.replaceAll`,
  `SnapshotStore`, the `Preferences.Keys` with the raw values, and
  `WatchPayload.receivedAtKey`), so the complications and the app draw
  with the phone's own code and `WidgetCenter.reloadAllTimelines()`
  shows it. "Only the app writes the registry" holds: on the Watch, the
  Watch app is the app of its container, and it writes only what it was
  sent. `requestRefresh()` sends the message while the iPhone is
  reachable, applies the reply, and otherwise notes the iPhone out of
  reach; the app asks on appearing while what it holds is older than
  `AppConfig.staleAfter` (`requestRefreshIfStale`), and Refresh asks
  regardless; `WatchAppDelegate` schedules a `WKApplicationRefreshBackgroundTask`
  every 30 minutes that asks only while what the Watch holds is older
  than `AppConfig.staleAfter`.
- **The app** (`WatchContentView`): a list with a section per account
  (`ProviderIdentityView` header with the plan pill in its compact form,
  `compactPill`, since the phone's read as tall as the row, and 5 pt of
  air under the header, which watchOS otherwise sets on the first card;
  Mike's two notes on the 2026-10-19 capture; the `WindowSlots`
  rows with bars, the grouped reset line as a live countdown under a day
  (`ResetLineText`, the widgets' own), the credits amount), "Updated
  X ago" (`UsageFormatting.updatedLabel`) or "iPhone not reachable" at
  the end, Refresh in the toolbar (its glyph white by name: watchOS
  fills a top-bar button with the app's tint and drew the glyph in it
  too, a solid disc with no arrow, measured on the watchOS 27
  simulator), and with nothing sent yet "Open AIMeter on iPhone". No
  settings of its own: the preferences are the phone's.
- **The complications** (`AIMeterWatchWidgets/UsageComplication.swift`,
  kind `AppConfig.watchWidgetKind`, `AppIntentConfiguration` with the
  phone's `UsageAccountConfigurationIntent`, from `WidgetsShared/`):
  `accessoryCircular` (the glance window's gauge), `accessoryRectangular`
  (the three slots), `accessoryInline` and `accessoryCorner` (the figure
  with a short gauge as its label), the first three the same views iOS's
  Lock Screen draws (`WidgetsShared/AccessoryUsageViews.swift`).
  `recommendations()` offers one per connected account, named after it,
  since the face editor on watchOS lists recommendations instead of
  showing a picker. The timeline re-reads the store at
  `AppConfig.widgetRefreshFloor`; nothing fetches.
- **Project**: both targets use `Config.local.xcconfig` for the team like
  the others, App Group entitlements only (no keychain group), `SDKROOT
  = watchos`. The iOS app embeds the Watch app ("Embed Watch Content",
  `platformFilters = (ios, )` on the file and `platformFilter = ios` on
  the dependency), so a Mac build neither builds nor carries it. The
  Watch app's icon is the Sunset look, written by
  `Scripts/AppIcon/render.mjs` beside the others (watchOS masks it round
  itself). Verify: `xcodebuild build -scheme AIMeterWatch -destination
  'generic/platform=watchOS Simulator'` warning-free; the Watch app also
  builds with the iOS app.
