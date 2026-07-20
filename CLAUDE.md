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
  the **keychain access group** so the widget can read credentials.
- Background task ID: `com.mikealvarado.aimeter.refresh`
- Widget kind: `AIMeterUsage`

## Layout of the repo

```
Packages/UsageKit     local Swift Package, provider-agnostic, pure logic
  Core/               UsageProvider, UsageSnapshot, UsageWindow, SpendStatus,
                      UsageError (localized via bundle: .module)
  Providers/Claude/   ALL Claude endpoint/OAuth specifics, isolated here
  Storage/            KeychainStore (accessGroup-aware) + SnapshotStore
  Sources/UsageKit/Resources/Localizable.xcstrings   (package strings)
AIMeter/              multiplatform SwiftUI app (views + services)
AIMeterWidgets/       widget extension (renders snapshots; iOS: self-fetch)
Shared/               AppConfig, Theme, components, formatting, preferences,
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
  `.session`, `.weekly`, `.modelSpecific(String)`. Widgets and views render
  whatever windows a snapshot contains; provider names are never hardcoded
  in rendering logic.
- App ↔ widget data flows only through the App Group `SnapshotStore`
  (JSON-encoded snapshot per provider ID). Widgets render the last
  snapshot; on iOS the widget may fetch for itself when the snapshot is
  older than the refresh cadence (credentials via the shared keychain
  access group), writing the result back to the store. On macOS the menu
  bar app feeds the widget (a sandboxed widget can't read Claude Code's
  credential file).
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
  `user:profile user:inference`); the user pastes back `<code>#<state>`;
  exchange/refresh at `https://console.anthropic.com/v1/oauth/token`.

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

- `RefreshService.refresh()`: fetch → shape → save to store → 
  `WidgetCenter.reloadAllTimelines()` → reschedule notifications.
- iOS app: refresh on cold launch; on foreground, always reload widget
  timelines (covers WidgetKit's archived-render cache after app updates)
  and refresh if the snapshot is >60 s old; `BGAppRefreshTask` at the
  user-selected cadence (15/30/60 min) as best-effort backstop.
- macOS: repeating timer at the cadence while the menu bar app runs.
- Widget timeline: single entry, `.after(cadence)`; on iOS `getTimeline`
  self-fetches when the stored snapshot is older than the cadence.
- Notifications are local only (`UNCalendarNotificationTrigger` at each
  window's `resetsAt`), rescheduled from scratch after every successful
  fetch, per-window opt-in toggles stored in the App Group. Permission is
  handled honestly: a denied system permission snaps the toggle back off
  and shows a warning row with an "Open Settings" shortcut; authorization
  is re-checked on foreground. Cancelled URL tasks are not surfaced as
  errors.

## Presentation rules

- Three fixed slots everywhere (`WindowSlots`): session, weekly, top model
  — a missing window keeps its slot (em dash + empty bar).
- Reset lines: consecutive windows sharing one reset date show
  "Resets in …" once, under the last of the group (`WindowSlots.showsReset`)
  — applies to dashboard, detail, menu bar, widgets, landscape.
- Display prefs (App Group, shared with widgets): Remaining/Used,
  Relative/Absolute reset style (tap any reset line to toggle), appearance
  System/Light/Dark, refresh cadence.
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
- **Provider detail** (push): rate-limit rows, Spend and Extra usage cards
  (label/value rows, currency formatted), notification toggles, iOS
  disconnect button.
- **Settings**: appearance / display mode / reset style pills, refresh
  cadence menu, notification toggles, a "Privacy & data" link, and an
  "Open Source" row (GitHub mark, opens the repo URL). iOS: sheet with
  Done; macOS: Settings scene (wrapped in a NavigationStack so the link
  can push).
- **Privacy & data** (`PrivacyView`): private-by-default rows (on-device,
  Keychain, no tracking), how connecting works (per platform), the exact
  OAuth scopes as chips + the two read-only endpoints called, and the
  independence/MIT footer. Every claim must stay true to the code.
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
  paste field (accepts OAuth code or full credentials JSON), Connect.
- **Landscape (iPhone)**: `verticalSizeClass == .compact` swaps the
  dashboard for a fullscreen card with the same stacked rows.
- **Widgets**: small & medium show header (logo + "Claude") + all three
  bars with reset lines; Lock Screen accessories (circular gauge,
  rectangular list, inline). Widget fonts are fixed sizes (12/11/9 pt) on
  purpose — text styles scale with Dynamic Type and overflow the fixed
  widget height on real devices. Rows sit in equal flexible slices so the
  layout fills any family height.
- **macOS menu bar**: session % as the label; popover with the same rows,
  refresh/settings/quit.

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
- Never commit: xcuserdata, local xcconfig, credentials, tokens, or
  anything under `docs/design/reference/` (gitignored).

## Workflow

- Data model follows reality: before changing endpoint-related code, run
  `Scripts/probe-usage-endpoint.sh` and check the captured fixtures. Never
  guess wire formats.
- Before large changes, propose the plan and wait for approval.
- Verify on both platforms: `xcodebuild` for macOS and iOS Simulator plus
  `swift test` in `Packages/UsageKit` must pass warning-free.
