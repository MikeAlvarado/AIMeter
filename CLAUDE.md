# AIMeter

Open source multiplatform app (iOS 17+ / macOS 14+, SwiftUI) that displays
AI subscription usage and remaining limits in widgets. First provider:
Claude Pro/Max. Architecture must support adding other AI providers later.

## Identifiers

- Bundle ID: com.mikealvarado.aimeter
- Widget extension: com.mikealvarado.aimeter.widgets
- App Group: group.com.mikealvarado.aimeter (must match exactly in both targets)

## Architecture rules (non-negotiable)

- `Packages/UsageKit/` is a local Swift Package, provider-agnostic, pure logic.
  It must NOT import SwiftUI, WidgetKit, or anything UI-related.
- All providers implement `UsageProvider` protocol:
  `func fetchUsage() async throws -> UsageSnapshot`.
- `UsageSnapshot` holds `[UsageWindow]`. `UsageWindow.kind` is an extensible
  enum: `.session`, `.weekly`, `.modelSpecific(String)`. Widgets render any
  combination of windows; they never hardcode provider or window names.
- App and Widget extension share data only through the App Group store.
  Widgets render the last snapshot + timestamp. On iOS the widget may fetch
  for itself when the snapshot is older than the refresh cadence (it reads
  credentials via the shared keychain access group — the App Group — and
  writes the result back to the store). On macOS the menu bar app feeds it.
- OAuth tokens live in Keychain only. Never in UserDefaults, never in the repo.

## Data source (Claude)

- Claude Code's OAuth token: auto-detected from ~/.claude/.credentials.json
  on macOS, manual paste on iOS.
- Usage comes from the undocumented endpoint Claude Code uses internally
  (rolling windows: 5h session, weekly, top-model weekly if available).
  Treat it as unstable: isolate all endpoint specifics inside ClaudeProvider
  so a breaking change touches one file.

## Conventions

- Swift 5.10+, async/await only (no Combine for new code).
- Errors surface as typed errors from UsageKit; UI decides presentation.
- Widget refresh: timeline entries every 15–30 min; call
  `WidgetCenter.shared.reloadAllTimelines()` after every successful fetch.
- Local notifications (UNUserNotificationCenter) scheduled at each window's
  `resetsAt`; per-window toggle in settings. No server, no push.
- Keep files under ~300 lines; split by feature, not by type.

## Open source hygiene

- MIT license. README includes: undocumented-endpoint disclaimer,
  build instructions with user's own team ID, no affiliation with Anthropic.
- Never commit: xcuserdata, local .xcconfig, credentials, tokens.

## Workflow

- Phase discipline: do not start UI work until the Phase 1 data-validation
  script confirms which usage windows the endpoint returns (session, weekly,
  Fable) and their format. The data model follows reality, not assumptions.
- Before large changes, propose the plan and wait for approval.

- docs/design/reference/ is local-only (gitignored); never commit its contents.
