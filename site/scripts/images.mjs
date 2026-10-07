// Turns the demo-mode captures into the WebP files under src/assets. Input is
// a work dir with raw/ and widget-shots/ as produced by Scripts/store-frames.sh
// in the app repo (see Scripts/StoreFrames/CLAUDE.md):
//   node scripts/images.mjs <work-dir>
import { resolve } from 'node:path'
import sharp from 'sharp'

const work = process.argv[2]
if (!work) throw new Error('usage: node scripts/images.mjs <work-dir>')
const out = resolve('src/assets')

const jobs = [
  ['raw/dashboard.png', 'dashboard', 1000],
  ['raw/dashboard-dark.png', 'dashboard-dark', 1000],
  ['raw/detail-week30.png', 'detail-week30', 1000],
  ['raw/detail-smart.png', 'detail-smart', 1000],
  ['raw/detail-top.png', 'detail-top', 1000],
  ['raw/home-widgets.png', 'home-widgets', 1100],
  ['raw/ipad-dashboard.png', 'ipad-dashboard', 1400],
  ['widget-shots/01-two-dark.png', 'widget-two-dark', null],
  ['widget-shots/02-two-light.png', 'widget-two-light', null],
  ['widget-shots/03-three-used-dark.png', 'widget-three-dark', null],
  ['widget-shots/06-small-dark.png', 'widget-small-dark', null],
]
for (const [src, name, height] of jobs) {
  let image = sharp(resolve(work, src))
  if (height) image = image.resize({ height })
  const info = await image.webp({ quality: 84 }).toFile(resolve(out, `${name}.webp`))
  console.log(name, info.width, info.height, info.size)
}
