# AIMeter

Open source iOS & macOS app that shows your AI subscription usage and
remaining limits in widgets — home screen, Lock Screen, Notification Center,
the macOS menu bar and, on a MacBook, the notch.

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
  an always-visible manual refresh button (iOS); a reset under a day
  away counts down live ("Resets in 2:23:05"), and on iOS the widget
  fetches again a minute after a window resets; Lock Screen accessories (circular,
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
- Four app icons to pick from in Settings, all of them the notch island:
  Sunset (the default), Ivory, Night, and one with a pet standing on it.
  On the Mac, macOS only lets an app change its Dock icon while it runs,
  so Finder keeps Sunset.
- A second, single-window widget ("Single Limit") for when you only care
  about one number — pick the account and window (session, weekly, a
  per-model limit, or usage credits) from the widget's own Edit Widget
  configuration.
- **Live Activity** (iOS): opt in per account from Provider Detail to put
  that account's session countdown on the Lock Screen and Dynamic Island
  while it's running — off by default. The countdown ticks live on-device
  with no network involved; since AIMeter has no server to push updates
  from, the percentage itself refreshes opportunistically whenever the app
  or a widget happens to fetch next, not instantly. "Show a pet" (also off
  by default) puts the account's own pixel pet beside the countdown: calm
  with room to spare, a yellow "!" near the limit, a red one when nearly
  out.
- Dashboard with one card per connected account (plan badge, per-window
  reset countdowns, a small 24-hour sparkline per window), and a
  fullscreen landscape mode on iPhone. Every bar reads at a glance:
  terracotta up to 70 % used, yellow up to 85 %, red past it — the same on iPhone, iPad, Mac, widgets and the Live Activity,
  and one switch in Settings to keep every bar terracotta instead.
- A **History** chart on each account's detail screen: the percent of
  each limit used over the last day, week, or month, with every reset
  marked — drawn from samples the app and widgets already record, kept on
  the device for 30 days. **Export** them from Settings as a CSV (for
  Numbers or Excel) or a JSON (for a script): every account, every
  window, the share sheet on iOS and a save panel on the Mac.
- A **notch island** on the Mac: a black panel fused to the MacBook's
  notch. On a screen without one — an external display, an iMac, a
  closed MacBook on a monitor — it draws its own at the top edge: a
  notch fused to the edge, or a pill floating in the menu bar like the
  iPhone's island, at the menu bar's height or your own, shown always,
  only when the cursor comes to it, and out of the way of full-screen
  apps. Shown, it already carries your figures, so a click on it opens
  every account straight away.
  Invisible until the cursor rests on the notch; then the figures you
  chose peek out beside it (`5h 42% | 7d 61%`, on either side or both),
  and a click opens every account in full —
  `5h 42% ↻2h 58m | 7d 61% ↻3d 3h` with bars, status and Refresh / Open
  / Settings — never taking focus or the keyboard. A click inside keeps
  it open; click an account, a pet or a session there and the peek shows
  it, or swipe across the island (two fingers, or a drag) to turn
  through your sessions while one works, else your accounts. On by default on a
  MacBook with a notch, where the menu bar icon stays until you open the
  island the first time and then gives way to it; opt-in elsewhere.
  Settings previews the peek and picks which account and windows the
  wings show, which side(s) of the notch they use, the hover delay, and
  whether screenshots and recordings leave the island out.
- macOS menu bar styles: gauge with or without the number, number only, a
  bar, a battery, or two or three windows side by side — plus an optional
  reset countdown, the account's name, and yellow past 70 % / red past 85 %.
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
- **A tour, and what's new**: the first launch walks through each part
  of AIMeter, one at a time, with a short animation and a button that
  turns it on (notifications, the notch island, Claude Code's hooks, the
  login item), and ends by connecting your account; Settings opens it
  again. After an update, a short sheet lists what changed, in your
  language, and a new feature that is still off comes with the same
  animation and button. The Mac app updates itself from
  the project's GitHub releases: a daily check, a background download
  whose signature must match the developer's, and an install only when
  you restart from its notice ("Later" leaves it waiting). Off with
  "Check for updates automatically" in Settings.
- **Claude Code on this Mac** (macOS, opt-in, off by default): what your
  Claude Code sessions would have cost at API list prices — tokens per
  model for today, the last 7 days, the last 30 days and all time — read from the
  session logs the CLI keeps in `~/.claude/projects`. Only the usage
  fields are decoded, never your prompts or the replies, and nothing
  leaves the Mac. Not a bill: your subscription already covers it.
- **Claude Code sessions in the notch** (macOS, on with the island):
  each Claude Code session at work gets a little pixel pet beside the
  notch (one of seven creatures, six colors and six accessories, its own
  for as long as the session lasts) that walks while the session works,
  shakes beside a yellow "!" when it waits for your permission, and
  falls asleep when it finishes. The one that needs you leads, and a
  count sits on the other side of the notch (Settings can add the
  session's name); hover to see its name and what it is doing, swipe to
  the next one or click another to put it in front, or open the island
  for every session and your usage. Settings can
  swap the pets for a plain spinner. Any number of
  sessions, from the desktop app or the CLI. It reads only the shape of
  the session logs in `~/.claude/projects`; one click (in Settings or in
  the island) adds AIMeter to Claude Code's hooks, so it also knows the
  moment a session asks for permission. An optional notification says
  when a session needs you: when it asks for permission, never just
  because a turn ended.
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

## Install

- **iPhone and iPad**: [the App Store](https://apps.apple.com/app/id6797946742).
- **Mac**: [download AIMeter-macOS.zip](https://github.com/MikeAlvarado/AIMeter/releases/latest/download/AIMeter-macOS.zip)
  from the latest release — signed with Developer ID and notarized by
  Apple — unzip it and move AIMeter to Applications. macOS 14 or later.
  From then on it updates itself: once a day it checks the latest
  release, downloads a newer one in the background, checks its
  signature, and installs it when you restart from its notice.
  Or build it yourself (see [Building](#building)).

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
status" toggle in Settings). On the Mac only, once a day, a request to
`api.github.com` asking whether a newer release exists, and the
download of `AIMeter-macOS.zip` from the project's GitHub release when
there is one (off with "Check for updates automatically" in Settings).
Nothing else:
no analytics, no crash reporting, no third-party SDKs, no server of ours.

**The one optional permission on the Mac** — "Avoid covering the menu
bar" (Settings, Claude Code) asks macOS for Accessibility, and AIMeter
uses it for one thing: reading where the open app's menu titles and the
menu bar's icons are, so the notch island shrinks before it covers them.
It reads nothing else and changes nothing.

**What is stored, and where**
- OAuth tokens: device Keychain only (`AfterFirstUnlock`; on iOS in the
  App Group keychain access group so the widget can refresh usage itself).
- The last usage snapshot (percentages, reset dates, spend numbers) and
  your display preferences: the App Group container, so widgets can render
  without fetching.
- Up to 30 days of usage percentages per window (just the numbers, their
  dates, and the reset dates), as a small JSON file per account in the
  same container, for the history chart. Deleted when you disconnect.
  "Export" in Settings writes that same history to a CSV or JSON file
  you choose where to send; nothing is uploaded by the app.
- Nothing is ever written to UserDefaults outside the App Group, to disk
  unencrypted, or to the repo.

**Claude Code logs (macOS, opt-in)**: off by default. If you turn on
"Read Claude Code's local usage logs" in Settings, AIMeter reads
`~/.claude/projects` on that Mac to add up tokens per model; it decodes
only the usage fields of each record (never conversation content), keeps
a small index of counts in `~/Library/Application Support/AIMeter/`, and
deletes that index when you turn it off. `Scripts/probe-claude-code-logs.sh`
prints exactly which fields it looks at.

**Claude Code sessions (macOS)**: on while the notch island is (Settings →
Claude Code turns it off). AIMeter follows `~/.claude/projects` to tell
which sessions are working, waiting or done, decoding only each record's
type, time, ids and stop reason, the types of its content items, and the
session's title and folder: never prompts, replies or tool input. Nothing
is stored or sent. The optional hooks (Install, in Settings → Claude Code
or in the island) add one entry per event to `~/.claude/settings.json`,
backed up first to `settings.json.aimeter-backup`, everything else kept.
Each entry posts the event to a Unix socket in
`~/Library/Application Support/AIMeter/`, only while AIMeter is running,
in the background and always successfully, so Claude Code never waits on
it; AIMeter reads the event's name, session, folder and agent from it and
discards the rest. The file keeps its permissions (readable by you
alone). Remove puts the file back exactly as it was, or, if you changed
it since, takes out just AIMeter's entries; if you delete AIMeter without
removing them they simply do nothing.

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
Claude Code's credentials. Its widget extension is (macOS loads no app
extension that isn't), and it only reads what the app writes to the App
Group. Signing (any team) is required for the App Group (app ↔ widget data
sharing) to work at runtime.

### Releasing

iOS ships through App Store Connect (archive the `AIMeter` scheme for
iOS in Release, export with the `app-store-connect` method, submit).
The app's `Info.plist` declares `ITSAppUsesNonExemptEncryption` false —
its only encryption is the system's HTTPS — so a build needs no export
compliance answer in App Store Connect.
The Mac app ships as a Developer ID-signed, notarized zip attached to a
GitHub Release: `Scripts/release-mac.sh <version>` archives, exports
with the `developer-id` method straight to Apple's notary service,
waits for the notarized app (`xcodebuild -exportNotarizedApp`),
verifies its signature, Gatekeeper assessment, stapled ticket and that
the widget extension is sandboxed, and zips it as `AIMeter-macOS.zip` —
the same name in every release, which is what lets the website and the
Install section above link to `releases/latest/download/AIMeter-macOS.zip`. It needs nothing but the Apple account Xcode is signed in to,
as the team's Account Holder or an Admin: the Developer ID signature is
a cloud-managed certificate and the upload uses that account, so there
is no certificate to create and no `notarytool` profile. Run it from a
Terminal, since the archive's signing reads the login keychain.
Notarization usually takes minutes but can take over an hour; the
script waits up to three, and rerunning it with the same work folder
resumes the wait instead of uploading again. Both macOS targets build
with the hardened runtime, which notarization requires. Tag the commit (`git tag <version>`), then
`gh release create <version> <zip>` with the release notes.

Before either: bump `MARKETING_VERSION`, and add the version's notes to
`AIMeter/WhatsNew.json` in all eight languages. The iPhone shows them
once after the App Store update, and the Mac's update notice shows them
before installing. The script refuses a version whose notes are missing
or whose `MARKETING_VERSION` differs. The tag must be that same version
and the asset must keep the name `AIMeter-macOS.zip`: the Mac's updater
compares the tag with its own version and downloads that asset.

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
                        install in place; Views/NotchIsland/ is the
                        macOS notch island (panel, controller, views);
                        Services/Updates/ is the Mac's own updater,
                        WhatsNew.json each release's notes (8 languages),
                        and Views/Tour/ the first launch's tour
AIMeterWidgets/         AIMeterUsage (one account's limits), AIMeterSingleUsage (one
                        number), AIMeterAllAccounts (every account at
                        once), and a Live Activity (iOS) — all render App
                        Group snapshots and, on iOS, refresh themselves
                        when stale
Scripts/AppIcon/        draws the app icons (Sunset, Ivory, Night, Pet),
                        their Mac sizes and the website's favicons from
                        code (`node Scripts/AppIcon/render.mjs`)
Scripts/IslandVideo/    records the website's notch island videos from the
                        running app in demo mode (`Scripts/island-video.sh`)
Scripts/PetsPreview/    draws every session pet into one PNG from the
                        app's sprite code (`Scripts/pets-preview.sh`)
Scripts/StoreFrames/    renders the App Store screenshots, header and
                        search-results card from the app's own views
                        (`Scripts/store-frames.sh`; see its CLAUDE.md)
site/                   the website (product page, privacy policy,
                        support page; React + Vite + TypeScript),
                        deployed to GitHub Pages by
                        .github/workflows/site.yml
Shared/                 config + presentation helpers used by app and
                        widgets, including PrivacyInfo.xcprivacy (bundled
                        into both targets), the shared provider header
                        component and the notch island's pure model and
                        geometry (unit-tested)
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

## Acknowledgments

The notch island owes its feel to three projects that got there first.
[boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0)
was the reference for *how* a notch panel should move — a fixed window
that never resizes, the black slab sized by its own content, one spring
carrying size, corners and shadow together. It was read, not copied:
AIMeter's island is its own implementation, written from scratch under
this repository's MIT license, and no boring.notch code is in this tree.
Vibe Island set the one-line format the island shows
(`5h 42% 2h 58m | 7d 61% 3d 3h`) and the way it shows a Claude Code
session while collapsed: its pets at one end, the count at the other.
[Atoll](https://github.com/Ebullioscopic/Atoll) (GPL-3.0) showed which
options a screen without a notch needs — the pill like the iPhone's
island, its height, hiding until the cursor comes, staying out of
screen captures — and was studied the same way: read, never copied.
Thanks to all three.

## License

[MIT](LICENSE)
