# AIMeter

Open source iOS & macOS app that shows your AI subscription usage and
remaining limits in widgets — home screen, Lock Screen, Notification Center,
and the macOS menu bar.

First supported provider: **Claude Pro/Max** (session, weekly, and top-model
weekly windows). The architecture is provider-agnostic, so more AI providers
can be added later.

- **iOS 17+ / macOS 14+**, pure SwiftUI, no dependencies, no server, no
  analytics.
- Widgets: `systemSmall` and `systemMedium` show all three Claude windows
  with grouped reset countdowns; Lock Screen accessories (circular,
  rectangular, inline). On iOS the widget refreshes itself in the
  background — you don't need to open the app.
- A second, single-window widget ("Single Limit") for when you only care
  about one number — pick the provider/window (session, weekly, or a
  per-model limit) from the widget's own Edit Widget configuration.
- Dashboard with your plan badge (Pro/Max), per-window reset countdowns,
  and a fullscreen landscape mode on iPhone.
- Detail screen with the raw provider data: spend cap and extra-usage
  credits, exactly as the endpoint reports them. When a plan bills a model
  via usage credits instead of its own weekly limit (e.g. Fable 5 on
  Claude Pro), the third usage row can be hidden or repurposed to show
  that spend/credit status instead of a dead placeholder — your choice.
- macOS menu bar extra with session usage and your plan badge at a glance.
- Optional local notifications when a usage window resets (with honest
  permission handling — no silent failures).
- Background refresh at a configurable cadence (15/30/60 min); widgets
  keep the last known data (with a staleness hint) when a fetch fails.
- English and Spanish, following the device language.

## ⚠️ Disclaimer

AIMeter reads usage from an **undocumented endpoint**
(`https://api.anthropic.com/api/oauth/usage`) that Claude Code uses
internally, authenticated with your own Claude Code OAuth token. This
endpoint may change or disappear at any time and its use is not officially
supported.

This project is **not affiliated with, endorsed by, or sponsored by
Anthropic**. "Claude" is a trademark of Anthropic, PBC. Use at your own risk
and in accordance with Anthropic's terms of service.

Your token never leaves your device: it is read from (macOS) or stored in
(iOS) the Keychain, and requests go directly to Anthropic's API.

## Privacy & data transparency

AIMeter is designed so you can verify every claim in this section by
reading the code (it's small) or probing the endpoints yourself.

**What leaves your device** — HTTPS requests to `api.anthropic.com` only
(`/api/oauth/usage` for the windows/spend data, `/api/oauth/profile` once
to resolve your plan name) and, for the iOS sign-in flow, the standard
OAuth exchange with `claude.ai` / `console.anthropic.com`. Nothing else:
no analytics, no crash reporting, no third-party SDKs, no server of ours.

**What is stored, and where**
- OAuth tokens: device Keychain only (`AfterFirstUnlock`; on iOS in the
  App Group keychain access group so the widget can refresh usage itself).
- The last usage snapshot (percentages, reset dates, spend numbers) and
  your display preferences: the App Group container, so widgets can render
  without fetching.
- Nothing is ever written to UserDefaults outside the App Group, to disk
  unencrypted, or to the repo.

**Notifications** are generated locally on the device
(`UNUserNotificationCenter`) from the reset dates already in the snapshot
— no push service involved.

**Disconnecting** (iOS button, or macOS just uses Claude Code's login)
deletes the stored token and the cached snapshot.

**Audit it**: `Scripts/probe-usage-endpoint.sh` prints the exact raw JSON
the app consumes, using your own local login; the token is never printed
or written to disk. `Scripts/sample-response.json` is a captured example.

## How it gets your usage

- **macOS** — zero setup. The app reads the credentials Claude Code already
  maintains on your Mac (Keychain item `Claude Code-credentials`, falling
  back to `~/.claude/.credentials.json`). It never modifies them: Claude
  Code keeps owning the token refresh cycle. Requires Claude Code installed
  and logged in.
- **iOS** — sign in once, in the app. Tap **Connect**: AIMeter opens
  Claude's sign-in page in your browser (same PKCE flow Claude Code uses,
  any sign-in method works), you copy the code it shows and paste it back.
  The app then owns its token copy — including automatic refresh — stored
  only in the device Keychain, shared with the widget through the App Group
  keychain access group so widgets can update themselves in the background.
  As a fallback, the same field also accepts the full credentials JSON
  copied from another device (`~/.claude/.credentials.json`).

## Building

You need Xcode 16+ and an Apple Developer account (a free one works for
running on your own devices).

1. Clone the repo and open `AIMeter.xcodeproj`.
2. Copy `Config.local.xcconfig.example` to `Config.local.xcconfig` (already
   gitignored — never committed) and set `DEVELOPMENT_TEAM` to your own
   Apple Developer Team ID. Both targets read it from there, so you don't
   need to touch Signing & Capabilities for this.
3. If your team can't use the bundle identifiers as-is, change
   `com.mikealvarado.aimeter` / `com.mikealvarado.aimeter.widgets` and the
   App Group `group.com.mikealvarado.aimeter` to your own — the App Group
   must match in **both** targets' entitlements and in
   `Shared/AppConfig.swift`.
4. Build & run the `AIMeter` scheme.

Note: the macOS app is intentionally **not sandboxed** — it needs to read
Claude Code's credentials. Signing (any team) is required for the App Group
(app ↔ widget data sharing) to work at runtime.

### Validating the endpoint

Before trusting the app, you can see exactly what it reads:

```sh
Scripts/probe-usage-endpoint.sh
```

prints the raw JSON response for your account using your local Claude Code
login. The token is never printed or written to disk.

## Architecture

```
Packages/UsageKit     provider-agnostic Swift Package (no UI imports)
  Core/               UsageProvider protocol, UsageSnapshot, UsageWindow
  Providers/Claude/   all endpoint- and OAuth-specific code, isolated
  Storage/            Keychain wrapper + App Group snapshot store
AIMeter/              multiplatform SwiftUI app (iOS + macOS)
AIMeterWidgets/       both widgets (the 3-window widget and Single Limit);
                      renders App Group snapshots and, on iOS, refreshes
                      them itself when they go stale
Shared/               config + presentation helpers used by app and widgets,
                      including PrivacyInfo.xcprivacy (bundled into both
                      targets) and the shared provider header component
```

Adding a provider = implementing `UsageProvider` (one folder under
`Providers/`), returning `UsageWindow`s with an extensible `kind`
(`.session`, `.weekly`, `.modelSpecific("…")`). Widgets render whatever
windows a snapshot contains.

Run the package tests:

```sh
cd Packages/UsageKit && swift test
```

(`AIMETER_LIVE_TEST=1 swift test --filter LiveClaudeProviderTests` runs an
opt-in integration test against your real account.)

## License

[MIT](LICENSE)
