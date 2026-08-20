# AIMeter

Open source iOS & macOS app that shows your AI subscription usage and
remaining limits in widgets — home screen, Lock Screen, Notification Center,
and the macOS menu bar.

First supported provider: **Claude Pro/Max** (session, weekly, and top-model
weekly windows). The architecture is provider-agnostic, so more AI providers
can be added later.

- **iOS 17+ / macOS 14+**, pure SwiftUI, no dependencies, no server, no
  analytics.
- **Multiple accounts**: connect more than one Claude login (e.g. personal
  + work) and refresh them all at once. Each gets a nickname, its own card
  on the dashboard, its own Provider Detail screen, and its own
  notification/Live Activity toggles — nothing is shared between accounts
  except the handful of settings that are genuinely app-wide (appearance,
  refresh cadence, peak-hours alerts). Hold and drag a card to reorder
  them (or use Move up/Move down from the card header's context menu); the
  order carries over to the menu bar, the widgets, and every account
  picker.
- **Sign-in recovery**: Claude rotates its OAuth refresh token on every
  use, so a login shared with another client can stop working — after
  which usage would just quietly freeze at its last reading. AIMeter says
  so on the card, notifies you once when it happens (the one alert that's
  on by default), and offers **Sign in again** right there. That repairs
  the account in place: history, alerts, and already-placed widgets keep
  working, unlike disconnecting and adding it back. Signing in through the
  app also gets AIMeter a token of its own, so it stops competing with
  Claude Code's.
- Widgets: `systemSmall` and `systemMedium` show all three Claude windows
  for one account, with grouped reset countdowns and an always-visible
  manual refresh button (iOS); Lock Screen accessories (circular,
  rectangular, inline) — the circular gauge follows whichever window you
  pick as your glance metric. A `systemLarge` widget shows every connected
  account at once instead of picking one. On iOS widgets refresh
  themselves in the background — you don't need to open the app. On macOS,
  widgets show up automatically in Notification Center / the desktop and
  are fed by the menu bar app, which is why AIMeter can keep running with
  no icons visible (see below) — that's what keeps them from going stale.
- A second, single-window widget ("Single Limit") for when you only care
  about one number — pick the account and window (session, weekly, a
  per-model limit, or usage credits) from the widget's own Edit Widget
  configuration.
- **Live Activity** (iOS): opt in per account from Provider Detail to put
  that account's session countdown on the Lock Screen and Dynamic Island
  while it's running — off by default. The countdown ticks live on-device
  with no network involved; since AIMeter has no server to push updates
  from, the percentage itself refreshes opportunistically whenever the app
  or a widget happens to fetch next, not instantly.
- Dashboard with one card per connected account (plan badge, per-window
  reset countdowns), and a fullscreen landscape mode on iPhone.
- Detail screen with the raw provider data: spend cap and extra-usage
  credits, exactly as the endpoint reports them; a **Forecast** card
  projecting which windows are on track to run out early, plus a per-row
  pace caption (on / ahead / behind a steady burn to the next reset). When
  a plan bills a model via usage credits instead of its own weekly limit
  (e.g. Fable 5 on Claude Pro), the third usage row can be hidden or
  repurposed to show that spend/credit status instead of a dead
  placeholder — your choice.
- Smart notifications, off by default and toggled individually per
  account: a reset reminder per window, a near-limit warning at a
  threshold you set, a limit-reached alert, run-out warnings when your
  recent pace projects an early exhaustion, and early-reset alerts if a
  window refills before its scheduled date. Sign-in alerts (above) are the
  single exception that starts on — a broken login is the one thing you
  can't notice by looking. Peak-hours alerts are the one
  exception — a single app-wide toggle in Settings, since Claude's peak
  policy applies the same way to every account, not something to repeat
  per login. All with honest permission handling, no silent failures.
- Peak-hours awareness: Anthropic has documented weekday morning windows
  (5-11 AM PT) where Claude session usage burns faster. There's no API
  signal for this — confirmed by capturing live responses inside and
  outside the window (see `docs/design/peak-hours-investigation.md`) — so
  AIMeter computes it on-device from the published schedule, correctly
  across timezones and DST. Because Anthropic has changed this policy more
  than once, the in-app indicator always shows the date the schedule was
  last verified.
- macOS menu bar extra: a gauge that fills with whichever window you pick
  to glance at, with the exact percentage spelled out beside it if you
  want (it's always in the tooltip either way), plus your plan badge.
  Hide the Dock icon, hide the menu bar icon, or both, and optionally have
  AIMeter open itself at login (opt-in, visibly toggleable) so it keeps
  refreshing and feeding widgets with no icon on screen at all.
- Background refresh at a configurable cadence (30 min / 1 h / 3 h); widgets
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

**Disconnecting** is per account, on both platforms — a button on that
account's Provider Detail screen deletes its stored token, cached
snapshot, and history. The one exception is a Mac's auto-detected
Claude Code login: there's nothing of AIMeter's own to delete there,
since it only ever reads Claude Code's existing credentials.

**Login item (macOS, opt-in)**: AIMeter never adds itself to your login
items. Turning on "Open at Login" in Settings registers it with macOS
(`SMAppService`) — which asks you to approve it — and turning it back off
removes the registration. All it does when it starts is read your usage.

**Audit it**: `Scripts/probe-usage-endpoint.sh` prints the exact raw JSON
the app consumes, using your own local login; the token is never printed
or written to disk. `Scripts/sample-response.json` is a captured example.

## How it gets your usage

- **macOS** — zero setup for your first account. AIMeter reads the
  credentials Claude Code already maintains on your Mac (Keychain item
  `Claude Code-credentials`, falling back to `~/.claude/.credentials.json`).
  It never modifies them: Claude Code keeps owning the token refresh cycle.
  Requires Claude Code installed and logged in.
- **iOS, and every account after the first on macOS** — sign in in the
  app. Tap **Connect**: AIMeter opens Claude's sign-in page in your
  browser (same PKCE flow Claude Code uses, any sign-in method works), you
  copy the code it shows and paste it back, and optionally give the
  account a nickname (only asked once you already have one connected — a
  single account never needs a name). The app then owns its token copy —
  including automatic refresh — stored only in the device Keychain, shared
  with the widget extension through the App Group keychain access group so
  widgets can update themselves in the background. As a fallback, the same
  field also accepts the full credentials JSON copied from another device
  (`~/.claude/.credentials.json`).
- **Adding more accounts**: tap **Add account** on the dashboard any time
  — the same Connect flow above, repeated per login. There's no limit
  beyond what's practical to keep track of.

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
Packages/UsageKit      provider-agnostic Swift Package (no UI imports)
  Core/                UsageProvider protocol, UsageSnapshot, UsageWindow
  Providers/Claude/    all endpoint- and OAuth-specific code, isolated
  Storage/             Keychain wrapper + App Group snapshot store +
                       AccountRegistryStore (the list of connected logins)
AIMeter/                multiplatform SwiftUI app (iOS + macOS);
                        AccountMigration upgrades a pre-multi-account
                        install in place
AIMeterWidgets/         AIMeterUsage (3-window), AIMeterSingleUsage (one
                        number), AIMeterAllAccounts (every account at
                        once), and a Live Activity (iOS) — all render App
                        Group snapshots and, on iOS, refresh themselves
                        when stale
Shared/                 config + presentation helpers used by app and
                        widgets, including PrivacyInfo.xcprivacy (bundled
                        into both targets) and the shared provider header
                        component
```

Each of `AIMeter/`, `AIMeterWidgets/`, and `Packages/UsageKit/Sources/UsageKit/Providers/Claude/`
has its own `CLAUDE.md` with the detail specific to that folder — the
repo-root `CLAUDE.md` is the full spec that ties them together.

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
