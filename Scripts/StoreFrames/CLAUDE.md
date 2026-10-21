# Store assets (screenshots, header, search-results card)

Everything the App Store shows for AIMeter is rendered here from the
app's own code: no design tool, no mockups. `Scripts/store-frames.sh`
assembles this package with the `Shared/` views and the widget views it
draws, builds it with SwiftPM, and runs it in one of three modes. Keep
this file current: it is the only record of how the assets were made.

## What it produces

- `frames`: the screenshot frames. iPhone at 1206×2622 (the "iPhone with
  Dynamic Island (medium display)" slot, 402×874 pt at 3x) and iPad 13"
  at 2064×2752 (1032×1376 pt at 2x). Specs in `Sources/Frames.swift`
  (`phoneSpecs`, `padSpecs`): headline, subhead, which raw capture, text
  on top or bottom, tilt. The device hangs off one edge by a fixed
  amount and the text sits at the other, so neither can push the other
  out of the canvas (the first attempt let the headline clip).
- `marketing`: the two landscape product-page assets App Store Connect
  added with iOS 26 — the **header** (5244×2950) and the **search
  results** card (3840×2560) — `Sources/Marketing.swift`. Copy on the
  left, the dashboard in a bezel low and right, the three widget views
  floating in front of it. The search card keeps everything inside the
  central two thirds; the header is cropped far more: on an iPhone the
  product page shows its top 63 % and central 54 % only, with the back,
  share and close buttons over its top corners (measured on Mike's
  phone on 2026-10-19, where "All your" and "AI" were cut off the 3.0
  headline), so since 3.2 the header's headline, subhead, widgets and
  phone sit inside x 24–77 %, y 25–63 % (`MarketingFrame.headerBand`),
  with no pills (they would fall under the cut). `sips -c 1858 2857
  --cropOffset 0 1183` on the rendered header shows what the phone
  shows. The widget
  cluster is rendered in `main.swift` on a transparent background and
  passed in (cropping it out of the home-screen render dragged a
  rectangle of backdrop along).
- `shots`: loose renders for review and tweets — the medium widget in
  its variants, the icon tiles, the home-screen composite of all three
  widget kinds, and since 3.2 the two Edit Widget layouts, the single
  limit as a ring and the all-accounts widget condensed to six
  (`ring-widget.png`, `condensed-widget.png`, each with a `-dark`
  twin), all in `main.swift`. `EntryStubs.swift` stands in for the
  widgets' entries and their two Edit Widget enums without AppIntents.

## Inputs: the raw captures

`<work-dir>/raw/` holds simulator captures taken in **demo mode** (two
accounts, "Personal" on the default mark and "Work" on a briefcase):
`dashboard.png`, `dashboard-dark.png`, `detail-top.png`,
`detail-week30.png` (History on Week + 30 days), `detail-smart.png`
(the Smart notifications card), `ipad-dashboard.png`, `ipad-detail.png`,
`ipad-dashboard-dark.png` (the app's Appearance on Dark), plus `appicon.png` (`Sunset.png` from `node Scripts/AppIcon/render.mjs <dir>`, the icon as iOS draws it)
and `home-widgets.png` (from `shots`). Capture with
`xcrun simctl io <udid> screenshot <file>` on a device nobody else is
using (iPhone 17e and iPad Pro 13" M5 for 2.0 and 3.0); the demo build is a
plain `xcodebuild build` for the simulator, installed with
`simctl install` and launched with `simctl launch`. Never place real
accounts on a simulator for this; demo data is the source of every
store image. The 3.0 set (2026-10-14) was taken with a clean status
bar (`xcrun simctl status_bar <udid> override --time 9:41 --batteryState
charged --batteryLevel 100 …`; 2.0's showed the real time) and the
simulator's own appearance for the dark captures (`xcrun simctl ui
<udid> appearance dark`); demo mode came from a temporary DEBUG check
for `-AIMeterDemo` at the end of `UsageModel.init`, never committed,
instead of tapping through Settings. 3.1 (2026-10-16) took no new
capture: the app icon changed to the notch island (Sunset), so only
the closing frame changed, rendered from the 3.0 captures with the new
`appicon.png`; every other frame, the header and the search card came
out pixel for pixel as 3.0's. 4.0 (2026-10-21) took the whole set again for the
redesign (the account card with its protagonist, the widgets, the
layered icon) on the iPhone 17e and the iPad Pro 13" (M5), demo mode
through the DEBUG `-AIMeterDemo YES` launch argument now in the app;
`detail-smart.png` is the account's settings page reached from
Settings → Account settings (demo mode hides Provider Detail's link to
it), and the iPad's detail frame shows the Spend card's first row only,
no amount. The set lives in `roadmap/screenshots-4.0/` (local), and the
README's pictures and the website's `og.png` are cut from it: the
banner from the header's content band, 1600 × 667, the three others
from `iphone-02/03/04` at 600 wide, the social card from the search
card's middle, 1200 × 630. `detail-smart.png` is scrolled so
the footnote under the alerts starts about two thirds down: the frame
shows the top two thirds of the capture, and the footnote's sixth line
names the provider. The website takes no capture from here since 3.0:
its iPhone's screens are drawn in the page (`site/src/components/phone`),
so they move and follow the language.

## Rules (store metadata is reviewed like the app)

- No third-party name anywhere in a frame: headlines, subheads, demo
  nicknames ("Personal", "Work"), window names ("Top model"). The app
  was rejected under 4.1(a) for names in metadata.
- No price, of any kind, anywhere in a frame or the store copy: not
  "free", not "no subscription", not a dollar amount. 1.6.0 was
  rejected under 2.3.7 (Accurate Metadata — "references to free or
  discounted services are considered a price reference") for the
  closing frame's "Free. … No subscription", the "Free" pill on the
  header and search card, and the iPad alerts frame, whose 13" screen
  keeps the Spend and Extra usage cards ($14.27 of $25.00) on screen
  however far it scrolls. That frame is now the dark dashboard
  ("Every account, its own icon"); the closing frame reads "Open
  source. No account."; the pills are "Open source" and "No account"
  (three longer pills truncate on the search card). A capture of
  Provider Detail must stop above the Spend card, and the footnote
  under the alerts names the provider, so it never shows either. From
  3.2 the alerts live on the account's settings page (Settings → the
  account), so the next round's `detail-smart.png` is a capture of that
  page.
- No em dash (—) anywhere in store text: headlines, subheads, What's
  New, promotional text, description, keywords, in every language. A
  comma, colon or period instead.
- No brand mark in a capture: the Claude / Claude Code marks exist in
  the icon picker since 1.6, and demo accounts deliberately never use
  them. A screenshot of the picker itself would show them, so there is
  none.
- Every pixel comes from a real view: the widgets are the real widget
  views, the phone is a real capture. Headlines may claim only what the
  app does.
- Sizes are exact store sizes; the slot lists them under the upload box
  and rejects anything else.

## Style and inspiration

The look follows the category's best listing (Limits: AI Usage Tracker,
reviewed 2026-10-07): dark warm backdrop with a terracotta glow
(`Theme.accent` 0xD97757 over 0x221D19 → 0x3D2B22 → 0x14110F), one bold
headline (SF Pro, 50 pt at 3x on phone), a one-line subhead at 72 %
white, the device tilted 4° in a near-black bezel with a hairline
stroke, and alternating text-top / text-bottom frames so the set has
rhythm. Headlines are short claims, not feature names: "All your AI
limits, one glance." / "Widgets that keep score." / "Every reset,
charted." / "Alerts before you hit the wall." / "Know your pace." /
"Every account, its own icon." / "Free. Open source. No account."
The closing frame is the app icon on the backdrop. The landscape assets
add three pills (Free · Open source · No account).

## How to run

    Scripts/store-frames.sh <work-dir> shots       # widget renders → <work-dir>/widget-shots
    cp <work-dir>/widget-shots/home-widgets.png <work-dir>/raw/
    Scripts/store-frames.sh <work-dir> frames      # → <work-dir>/frames
    Scripts/store-frames.sh <work-dir> marketing   # → <work-dir>/marketing
    Scripts/store-frames.sh <work-dir> notch [es]  # → <work-dir>/notch-frames (see "Not store assets")

The script copies sources rather than symlinking them: SwiftPM did not
notice edits behind a symlink and rendered stale views once. Its list of
`Shared/` files is explicit, so a new file a copied one depends on has
to join it (3.0 added the sessions' model, preferences and pets; 3.2
`ResetLine`, the widgets' countdown). Run it from
a checkout whose `Shared/` matches the build you are shipping, since the
widget views come from the working tree.

## Uploading

App Store Connect, version page → App Previews and Screenshots: remove
the slot's assets, then upload the frames **one at a time** in order
(a bulk upload landed out of order once; drag-reorder did not work).
Header and search-results assets go under "Header and Search Results".
The What's New text and promotional text are not carried over between
versions; screenshots are, until replaced. Save after each section.

## Not store assets

The notch island (2.0) is Mac-only and the Mac app is not in the store,
so its captures are never store assets. Since 3.0 the website shows it
in motion instead: videos of the real app in demo mode, recorded by
`Scripts/island-video.sh` (see `Scripts/IslandVideo/CLAUDE.md`). The
stills below are what the page showed before, and what posts still use;
they were website assets, taken
on a MacBook with a notch in demo mode at 2×: `screencapture -R
0,0,<screen width>,320` of the screen's top edge with the island
collapsed (the bare notch) and again during the peek (the wings open),
and `screencapture -o -l <panel window id>` of the island's panel alone
while it is expanded — the panel on transparency, so whatever the
desktop holds under it stays out of the picture. `site/scripts/island.mjs`
crops the strips, lays the panel over the collapsed strip (mirroring the
desktop below the menu bar so no window shows) and writes the three
`island-*.webp` files into `site/src/assets/` (see `site/CLAUDE.md`).
The 2.0.0 set was taken on 2026-10-09 on a 14" M4 Max (1512 pt wide,
the panel's frame at x 401). The 3.0.0 set (2026-10-14) could not use
the real top edge: it held the working Mac's windows and other apps'
status items beside the notch. So every piece was captured alone, on
transparency: the desktop picture (`screencapture -o -l` of the
WindowManager "Wallpaper" window that is on screen; the menu bar is
transparent, so nothing else belongs in the strip) and the island's
panel collapsed, peeking and expanded, and `site/scripts/island-strips.mjs
<work-dir> 401` lays the first two panels over the wallpaper to make the
two strips `island.mjs` reads. A window capture taken a few seconds after
launch once returned the panel's previous frame (an expanded island while
the screen showed it collapsed): look at each capture before using it. The one thing this pipeline renders for it
is `Scripts/store-frames.sh <work-dir> notch`: two 16:9 frames
(2400×1350, `notch-frames/notch-01-island.png` and `notch-02-peek.png`)
in the style above — backdrop, one claim, the capture in a bezel — from
the `island-*.png` copies `island.mjs` leaves in its work dir, for the
website and posts, never the store. `notch es` renders the same two
frames with the Spanish copy (`notch-01-island-es.png`,
`notch-02-peek-es.png`) for posts in Spanish; the captures inside stay
the demo's, which is English.
