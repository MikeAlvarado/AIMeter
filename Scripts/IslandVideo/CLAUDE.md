# Island videos (`Scripts/IslandVideo/`)

The website's notch island videos: the real app's island, recorded while
it plays a scripted scene, composed over a drawn desktop. Not store
assets (the Mac app is not in the store); the hero's `NotchDemo` plays
them (see `site/CLAUDE.md`).

    Scripts/island-video.sh <a DEBUG AIMeter.app> [work dir]

writes `site/src/assets/videos/island-<scene>-<lang>.mp4` and its poster
(`.webp`, the first frame) for every scene and language. Run it on a
MacBook with its built-in display on: the island then sits in the real
notch and is captured at 2×. A screen without a notch draws the island
in its own form (the pill or the drawn notch, as Settings says), at the
display's scale, which on an external 1× display is half the sharpness;
that is fine for trying the pipeline, not for the site.

## How it works

- **The app is directed, not driven.** The script relaunches the DEBUG
  build with `-AIMeterIslandDirector YES` (and `-AppleLanguages (<lang>)`,
  and `-pref.claudeSessionsShowsName NO` so the island is the short one
  whatever the user chose: a launch argument overrides the App Group's
  read without writing it). `IslandDirector`
  (`AIMeter/Services/IslandDirector.swift`, DEBUG only) then takes
  distributed notifications (`com.mikealvarado.aimeter.director`, a
  `command` and a `value`): `demo` (demo mode on), `level` (`collapsed`,
  `peek`, `expanded`, through `NotchIslandController.direct`, as if the
  cursor had opened it), `sessions` (a JSON list replacing the demo's
  sessions, `DemoSessions`, each with its turn's `steps` (an action,
  how many, seconds from the turn's start), `edits`, `plan` (statuses)
  and `ask` (the tool and what it asks), for the island's card) and
  `approve` (a session's id: the card's Approve, on the demo). No
  cursor moves and no real session shows.
- **The recorder** (`swift build -c release` here) captures the island's
  panel alone with ScreenCaptureKit (`Capture.swift`: AIMeter's window at
  `mainMenu + 3`, transparent where nothing is drawn, at its display's
  scale). It captures the panel's rectangle on its display with only
  that window in it, never the window by itself: a single-window capture
  is cropped to what is drawn and put in the frame's top left corner, so
  the island lost its place (the first take on a MacBook had the
  collapsed notch 260 pt left of the real one, and the open island
  growing rightward from its left edge). On its own 30 fps clock it
  composes each frame
  (`Compose.swift`): the drawn desktop (`Backdrop.swift`: a wallpaper in
  the app's colors, the menu bar with Terminal's menus, a few status
  icons and the clock, each left out wherever the island reaches at its
  widest in that language's scenes, `islandReach`, so it never covers
  one, and Help always the last menu (the ones before it go first), two
  terminals at work, in the scene's language), the panel with the
  notch's centre (or the screen's middle) at the canvas's middle, and a
  drawn arrow cursor with a ring on its clicks. 960×540 pt at 2×, H.264
  at a high bitrate; the script re-encodes it (`ffmpeg`, CRF 24,
  `+faststart`) and takes the poster.
- **The scenes** (`Scenes.swift`), each a timeline of what the app is
  told and where the cursor is: `limits` (no session: the cursor rests
  on the notch, the figures peek out, a click opens every account),
  `sessions` (three sessions at work walk beside the notch; resting
  shows the newest in full, and the island stays closed: the card is
  the permission scene's, Mike's call on 2026-10-25) and `permission` (a
  session asks: its pet comes forward and shakes beside the "!", the
  peek says so, a click opens its card, which says what it asks; the
  cursor presses Approve on the card, measured at 127 pt left of the
  middle and 409 pt down on a MacBook's island, and it works on; then
  the other finishes and falls asleep). Two sessions there, not more:
  the open island with the card and two accounts is just short of the
  540 pt canvas, and a third row ran it past the bottom edge. Session titles and the terminals follow
  the language; folder names do not. The ids are the demo's
  (`DemoUsageData.claudeSessions`), picked for their pets (a fox in
  sunglasses, a cat in headphones, a bunny with a bow, a ghost in a
  beanie, and `demo-425`, a green frog), which `ClaudeSessionsTests`
  pins.

The Screen Recording permission the recorder needs is the terminal's
(the same one `screencapture` uses). The script relaunches the app
normally at the end, even after a failure, so the user's own accounts
come back (the script reopens the build it recorded with; quit it and
open the installed copy, and note that a test build rewrites AIMeter's
hooks in `~/.claude/settings.json` to its own format: copy the file
before and put it back after). Recorded on 2026-10-15, again on
2026-10-21 for 4.0 (the expanded island's account rows on their own
layout, `IslandColumns`), and on 2026-10-25 for 4.2 (the session card).
