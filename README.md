# AIMeter

Open source iOS & macOS app that shows your AI subscription usage and
remaining limits in widgets — home screen, Lock Screen, Notification Center,
and the macOS menu bar.

First supported provider: **Claude Pro/Max** (session, weekly, and top-model
weekly windows). The architecture is provider-agnostic, so more AI providers
can be added later.

- **iOS 17+ / macOS 14+**, pure SwiftUI, no dependencies, no server.
- Widgets: `systemSmall`, `systemMedium`, and Lock Screen accessories
  (circular, rectangular, inline) always showing the three Claude windows.
- macOS menu bar extra with session usage at a glance.
- Optional local notifications when a usage window resets.
- Background refresh every ~15 minutes; widgets keep the last known data
  (with a staleness indicator) when a fetch fails.

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

## How it gets your usage

- **macOS** — zero setup. The app reads the credentials Claude Code already
  maintains on your Mac (Keychain item `Claude Code-credentials`, falling
  back to `~/.claude/.credentials.json`). It never modifies them: Claude
  Code keeps owning the token refresh cycle. Requires Claude Code installed
  and logged in.
- **iOS** — paste once. Copy your credentials on your computer and paste
  them into the app:

  ```sh
  # Linux, or macOS installs that use the file:
  cat ~/.claude/.credentials.json | pbcopy

  # macOS installs that use the Keychain:
  security find-generic-password -s "Claude Code-credentials" -w | pbcopy
  ```

  Pasting the full JSON (including the refresh token) lets the app renew the
  access token on its own. A bare access token also works but expires within
  hours. Credentials are stored only in the device Keychain.

## Building

You need Xcode 16+ and an Apple Developer account (a free one works for
running on your own devices).

1. Clone the repo and open `AIMeter.xcodeproj`.
2. Select the **AIMeter** target → Signing & Capabilities → set your own
   **Team**. Repeat for **AIMeterWidgetsExtension**.
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
AIMeterWidgets/       widget extension; reads snapshots from the App Group,
                      never fetches
Shared/               config + presentation helpers used by app and widgets
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
