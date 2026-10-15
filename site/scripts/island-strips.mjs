// Builds the two top-edge strips `island.mjs` reads from clean pieces, for a
// Mac whose real top edge holds windows and other apps' status items: the
// desktop picture alone (`screencapture -o -l <wallpaper window id>`, the
// WindowManager "Wallpaper" window on screen) with the island's panel
// captured alone (`screencapture -o -l <panel window id>`) laid over it at
// the panel's own frame. Input, in the work dir: wallpaper.png,
// panel-collapsed.png, panel-peek.png (all at 2×); output: strip-collapsed.png
// and strip-peek.png next to them.
//   node scripts/island-strips.mjs <work-dir> <panel x in points>
import { resolve } from 'node:path'
import sharp from 'sharp'

const work = process.argv[2]
const panelX = Number(process.argv[3])
if (!work || !Number.isFinite(panelX)) throw new Error('usage: node scripts/island-strips.mjs <work-dir> <panel x in points>')

/** The strip `island.mjs` expects: 320 pt of the screen's top edge at 2×. */
const HEIGHT = 640
const wallpaper = sharp(resolve(work, 'wallpaper.png'))
const { width } = await wallpaper.metadata()
const base = await wallpaper.extract({ left: 0, top: 0, width, height: HEIGHT }).png().toBuffer()
for (const state of ['collapsed', 'peek']) {
  const panel = sharp(resolve(work, `panel-${state}.png`))
  const meta = await panel.metadata()
  const clip = await panel.extract({ left: 0, top: 0, width: meta.width, height: Math.min(meta.height, HEIGHT) }).toBuffer()
  await sharp(base).composite([{ input: clip, left: panelX * 2, top: 0 }]).png().toFile(resolve(work, `strip-${state}.png`))
}
console.log('strips written to', work)
