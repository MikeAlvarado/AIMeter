// Turns the notch island captures into the three WebP files the Mac section
// shows (src/assets/island-{collapsed,peek,expanded}.webp). Input is a work
// dir with three PNGs taken on a MacBook with a notch, in demo mode, at 2×
// (see Scripts/StoreFrames/CLAUDE.md → "Not store assets" in the app repo):
//   strip-collapsed.png  screencapture -R 0,0,<screen width>,320 — the real
//                        menu bar, the island collapsed (the bare notch)
//   strip-peek.png       the same strip while the wings are open
//   panel-expanded.png   screencapture -o -l <island panel window id> while
//                        the island is expanded: the panel alone, on
//                        transparency, so whatever sits under it on the
//                        desktop is not in the picture
//   node scripts/island.mjs <work-dir>
// The panel is laid over the collapsed strip at the panel's own frame (it is
// centred on the notch, so on the screen's centre line); below the menu bar
// the strip is mirrored past MIRROR_Y so no window of the desktop shows.
import { resolve } from 'node:path'
import sharp from 'sharp'

const work = process.argv[2]
if (!work) throw new Error('usage: node scripts/island.mjs <work-dir>')
const out = resolve('src/assets')

/** The crop, in 2× pixels: 552 pt centred on a 1512 pt screen. */
const CROP = { left: 960, width: 1104 }
/** Collapsed and peek strips: the menu bar plus a little desktop. */
const STRIP_HEIGHT = 96
/** Below this row the collapsed strip is mirrored upward (rows past it may hold the desktop's windows). */
const MIRROR_Y = 380
const MARGIN_BELOW_ISLAND = 40

const strip = sharp(resolve(work, 'strip-collapsed.png'))
const stripMeta = await strip.metadata()
const panel = sharp(resolve(work, 'panel-expanded.png'))
const panelMeta = await panel.metadata()

// Where the slab ends: the last row of the panel with any opaque pixel.
const { data, info } = await panel.clone().ensureAlpha().raw().toBuffer({ resolveWithObject: true })
let bottom = 0
for (let y = 0; y < info.height; y++) {
  for (let x = 0; x < info.width; x++) {
    if (data[(y * info.width + x) * info.channels + 3] > 0) bottom = y
  }
}
const expandedHeight = bottom + 1 + MARGIN_BELOW_ISLAND

// The backdrop: the collapsed strip, its lower rows replaced by a mirror of
// the rows above MIRROR_Y.
const top = await strip.clone().extract({ left: CROP.left, top: 0, width: CROP.width, height: MIRROR_Y }).toBuffer()
const mirrorHeight = expandedHeight - MIRROR_Y
const mirrored = await strip
  .clone()
  .extract({ left: CROP.left, top: MIRROR_Y - mirrorHeight, width: CROP.width, height: mirrorHeight })
  .flip()
  .toBuffer()
// The panel's frame is wider than the crop: clip it to the crop's columns.
const panelScreenLeft = Math.floor((stripMeta.width - panelMeta.width) / 2)
const panelClip = await panel
  .clone()
  .extract({ left: CROP.left - panelScreenLeft, top: 0, width: CROP.width, height: Math.min(panelMeta.height, expandedHeight) })
  .toBuffer()
const expanded = await sharp({ create: { width: CROP.width, height: expandedHeight, channels: 3, background: '#000' } })
  .composite([
    { input: top, top: 0, left: 0 },
    { input: mirrored, top: MIRROR_Y, left: 0 },
    { input: panelClip, top: 0, left: 0 },
  ])
  .webp({ quality: 84 })
  .toFile(resolve(out, 'island-expanded.webp'))
console.log('island-expanded', expanded.width, expanded.height, expanded.size)

const strips = [
  ['strip-collapsed.png', 'island-collapsed'],
  ['strip-peek.png', 'island-peek'],
]
for (const [src, name] of strips) {
  const info = await sharp(resolve(work, src))
    .extract({ left: CROP.left, top: 0, width: CROP.width, height: STRIP_HEIGHT })
    .webp({ quality: 84 })
    .toFile(resolve(out, `${name}.webp`))
  console.log(name, info.width, info.height, info.size)
}

// PNG copies in the work dir, for `Scripts/store-frames.sh <work-dir> notch`
// (the 16:9 frames for the website and posts).
for (const name of ['island-collapsed', 'island-peek', 'island-expanded']) {
  await sharp(resolve(out, `${name}.webp`)).png().toFile(resolve(work, `${name}.png`))
}
