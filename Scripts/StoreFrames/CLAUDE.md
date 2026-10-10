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
  floating in front of it. Everything stays inside the central two
  thirds: the store crops the edges on smaller screens. The widget
  cluster is rendered in `main.swift` on a transparent background and
  passed in (cropping it out of the home-screen render dragged a
  rectangle of backdrop along).
- `shots`: loose renders for review and tweets — the medium widget in
  its variants, the icon tiles, the home-screen composite of all three
  widget kinds (`main.swift`).

## Inputs: the raw captures

`<work-dir>/raw/` holds simulator captures taken in **demo mode** (two
accounts, "Personal" on the default mark and "Work" on a briefcase):
`dashboard.png`, `dashboard-dark.png`, `detail-top.png`,
`detail-week30.png` (History on Week + 30 days), `detail-smart.png`
(the Smart notifications card), `ipad-dashboard.png`, `ipad-detail.png`,
`ipad-alerts.png`, plus `appicon.png` (`AIMeter/Assets.xcassets/AppIcon.appiconset/ios-light.png`)
and `home-widgets.png` (from `shots`). Capture with
`xcrun simctl io <udid> screenshot <file>` on a device nobody else is
using (iPhone 17e and iPad Pro 13" M5 last time); the demo build is a
plain `xcodebuild build` for the simulator, installed with
`simctl install` and launched with `simctl launch`. Never place real
accounts on a simulator for this; demo data is the source of every
store image.

## Rules (store metadata is reviewed like the app)

- No third-party name anywhere in a frame: headlines, subheads, demo
  nicknames ("Personal", "Work"), window names ("Top model"). The app
  was rejected under 4.1(a) for names in metadata.
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

The script copies sources rather than symlinking them: SwiftPM did not
notice edits behind a symlink and rendered stale views once. Run it from
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
so its captures are never store assets. They are website assets: in demo
mode, `screencapture -R` of the screen's top edge at 2× with the island
collapsed and expanded, converted to WebP into `site/src/assets/` (see
`site/CLAUDE.md`). Nothing in this pipeline renders it.
