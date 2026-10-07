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
  + work) and refresh them all at once. Each gets a nickname (rename it any
  time from the card header's context menu or its detail screen), its own
  card on the dashboard, its own Provider Detail screen, and its own
  notification/Live Activity toggles — nothing is shared between accounts
  except the handful of settings that are genuinely app-wide (appearance,
  refresh cadence). Hold and drag a card to reorder
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
- Widgets: "Usage Limits" shows one account's windows — `systemSmall`
  as rows with grouped reset countdowns, `systemMedium` as side-by-side
  columns with a big "42% left" figure, bar and reset line each — with
  an always-visible manual refresh button (iOS); Lock Screen accessories (circular,
  rectangular, inline) — the circular gauge follows whichever window you
  pick as your glance metric. A `systemLarge` widget shows every connected
  account at once instead of picking one. On iOS widgets refresh
  themselves in the background — you don't need to open the app. On macOS,
  widgets show up automatically in Notification Center / the desktop and
  are fed by the menu bar app, which is why AIMeter can keep running with
  no icons visible (see below) — that's what keeps them from going stale.
- In eight languages: English, Spanish, German, French, Japanese,
  Korean, Brazilian Portuguese and Simplified Chinese, picked from the
  device language.
- Each account gets a name and an icon of your choosing: any SF Symbol,
  or the Claude / Claude Code mark, drawn in the same style, shown on the
  dashboard, in the menu bar, in every widget and in the Live Activity.
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
  reset countdowns, a small 24-hour sparkline per window), and a
  fullscreen landscape mode on iPhone.
- A **History** chart on each account's detail screen: the percent of
  each limit used over the last day, week, or month, with every reset
  marked — drawn from samples the app and widgets already record, kept on
  the device for 30 days.
- macOS menu bar styles: gauge with or without the number, number only, a
  bar, a battery, or two or three windows side by side — plus an optional
  reset countdown, the account's name, and red once a window passes 80 %.
  Settings shows a live preview on a light and a dark menu bar.
- Keyboard shortcuts on the Mac (a "Usage" menu: ⌘R refresh, ⌘N add
  account, ⌘⇧U used/remaining, ⌘⇧A reset-time style) and two
  Shortcuts/Siri actions on both platforms, "Refresh Usage" and "Show
  Usage" — give either a system-wide key in the Shortcuts app; AIMeter
  asks for no Accessibility permission to do it itself.
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
  can't notice by looking. All with honest permission handling, no
  silent failures.
- Service status: when Anthropic's public status page reports an
  incident, the dashboard and the macOS menu bar popover show a banner
  (tap it for the incident page), and an account whose refresh is
  failing at the same time says so under its error — so an outage reads
  as their outage, not as a problem with your account. On a normal day
  nothing is shown; the check can be turned off in Settings.
- **Claude Code on this Mac** (macOS, opt-in, off by default): what your
  Claude Code sessions would have cost at API list prices — tokens per
  model for today, the last 7 days, the last 30 days and all time — read from the
  session logs the CLI keeps in `~/.claude/projects`. Only the usage
  fields are decoded, never your prompts or the replies, and nothing
  leaves the Mac. Not a bill: your subscription already covers it.
- Peak hours: earlier versions showed Anthropic's weekday peak window,
  during which Claude session usage burned faster. Anthropic removed that
  policy in May 2026 and no plan documents one today, so the indicator
  and its alerts are switched off — the mechanism stays in the code (see
  `docs/design/peak-hours-investigation.md`) for the day the policy
  returns.
- macOS menu bar extra: a gauge that fills with whichever window you pick
  to glance at, with the exact percentage spelled out beside it if you
  want (it's always in the tooltip either way), plus your plan badge.
  Hide the Dock icon, hide the menu bar icon, or both, and optionally have
  AIMeter open itself at login (opt-in, visibly toggleable) so it keeps
  refreshing and feeding widgets with no icon on screen at all.
- Background refresh at a configurable cadence (30 min / 1 h / 3 h); widgets
  keep the last known data (with a staleness hint) when a fetch fails.
- English, Spanish, German, French, Japanese, Korean, Brazilian Portuguese
  and Simplified Chinese, following the device language.

## Website

[mikealvarado.github.io/AIMeter](https://mikealvarado.github.io/AIMeter/)
is the product page, with the [privacy policy](https://mikealvarado.github.io/AIMeter/privacy/)
and a [support page](https://mikealvarado.github.io/AIMeter/support/), in
English and Spanish. It lives in [`site/`](site/) (React + Vite +
TypeScript, static, no analytics) and deploys to GitHub Pages from `main`.

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

AIMeter's own sign-in requests a single OAuth scope, `user:profile` — the
one the usage and profile endpoints need — and never `user:inference`, so a
token issued to AIMeter cannot be used to run Claude. Be aware that
Anthropic's published authentication policy (Claude Code docs → Legal and
compliance → "Authentication and credential use") reserves Claude.ai OAuth
for its own applications and disallows third-party apps from collecting or
storing Claude.ai credentials. AIMeter is a read-only meter of your own
account that holds nothing but the token you grant it, on your device — but
it claims no exemption from that policy, and Anthropic may restrict this
endpoint or these tokens at any time.

## Privacy & data transparency

AIMeter is designed so you can verify every claim in this section by
reading the code (it's small) or probing the endpoints yourself.

**What leaves your device** — HTTPS requests to `api.anthropic.com` only
(`/api/oauth/usage` for the windows/spend data, `/api/oauth/profile` to
resolve your plan name, re-checked at most every 6 hours so a plan change
shows up) and, for the iOS sign-in flow, the standard
OAuth exchange with `claude.ai` / `console.anthropic.com` — plus one
anonymous GET of the public status page (`status.claude.com/api/v2/summary.json`,
no parameters, nothing about you in it; off with the "Check service
status" toggle in Settings). Nothing else:
no analytics, no crash reporting, no third-party SDKs, no server of ours.

**What is stored, and where**
- OAuth tokens: device Keychain only (`AfterFirstUnlock`; on iOS in the
  App Group keychain access group so the widget can refresh usage itself).
- The last usage snapshot (percentages, reset dates, spend numbers) and
  your display preferences: the App Group container, so widgets can render
  without fetching.
- Up to 30 days of usage percentages per window (just the numbers, their
  dates, and the reset dates), as a small JSON file per account in the
  same container, for the history chart. Deleted when you disconnect.
- Nothing is ever written to UserDefaults outside the App Group, to disk
  unencrypted, or to the repo.

**Claude Code logs (macOS, opt-in)**: off by default. If you turn on
"Read Claude Code's local usage logs" in Settings, AIMeter reads
`~/.claude/projects` on that Mac to add up tokens per model; it decodes
only the usage fields of each record (never conversation content), keeps
a small index of counts in `~/Library/Application Support/AIMeter/`, and
deletes that index when you turn it off. `Scripts/probe-claude-code-logs.sh`
prints exactly which fields it looks at.

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
`Scripts/probe-status-endpoint.sh` does the same for the status page.

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
  single account never needs a name; either way you can rename it later
  from the dashboard). The app then owns its token copy —
  including automatic refresh — stored only in the device Keychain, shared
  with the widget extension through the App Group keychain access group so
  widgets can update themselves in the background. On macOS only, the same
  field also accepts the full credentials JSON copied from another Mac
  (`~/.claude/.credentials.json`) as a fallback; the iOS build accepts
  nothing but the sign-in code — it never takes in another app's
  credential file.
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
`Scripts/probe-status-endpoint.sh` prints the status page summary the app
reads (no login involved).

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
AIMeterWidgets/         AIMeterUsage (one account's limits), AIMeterSingleUsage (one
                        number), AIMeterAllAccounts (every account at
                        once), and a Live Activity (iOS) — all render App
                        Group snapshots and, on iOS, refresh themselves
                        when stale
Scripts/StoreFrames/    renders the App Store screenshots, header and
                        search-results card from the app's own views
                        (`Scripts/store-frames.sh`; see its CLAUDE.md)
site/                   the website (product page, privacy policy,
                        support page; React + Vite + TypeScript),
                        deployed to GitHub Pages by
                        .github/workflows/site.yml
Shared/                 config + presentation helpers used by app and
                        widgets, including PrivacyInfo.xcprivacy (bundled
                        into both targets) and the shared provider header
                        component
```

Each of `AIMeter/`, `AIMeterWidgets/`, `Packages/UsageKit/Sources/UsageKit/Providers/Claude/`,
`Scripts/StoreFrames/` and `site/` has its own `CLAUDE.md` with the detail specific to that folder — the
repo-root `CLAUDE.md` is the full spec that ties them together.

Adding a provider = implementing `UsageProvider` (one folder under
`Providers/`), returning `UsageWindow`s with an extensible `kind`
(`.session`, `.weekly`, `.modelSpecific("…")`) and their own `duration`,
plus one case each in `Shared/ProviderCatalog.swift` (display name, and
which credential store backs an account of that family). Widgets render
whatever windows a snapshot contains.

Run the package tests:

```sh
cd Packages/UsageKit && swift test
```

(`AIMETER_LIVE_TEST=1 swift test --filter LiveClaudeProviderTests` runs an
opt-in integration test against your real account.)

The app's own unit tests (`AIMeterTests`, hosted in the app) run from
Xcode with ⌘U, or:

```sh
xcodebuild test -project AIMeter.xcodeproj -scheme AIMeter -destination 'platform=macOS'
```

## License

[MIT](LICENSE)
