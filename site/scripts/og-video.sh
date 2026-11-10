#!/bin/sh
# Writes public/og.mp4, the og:video a shared link plays in iMessage and
# other previews: the hero's Limits scene cut close around the island
# (the notch's middle, from Help's end to the status icons' start, so no
# menu is cut in half), 1280x720, 10.5 s. The cursor comes to the notch,
# the figures peek out, a click opens every account, and once it is open
# the hero's headline rises in under it over a band of the night ground
# and holds on the last frame.
# Run it from anywhere after Scripts/island-video.sh records the scenes
# again; it needs ffmpeg, Google Chrome (to draw the headline in the
# site's own fonts) and `npm ci` done here.
set -eu
cd "$(dirname "$0")/.."
SITE=$(pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FONTS="$SITE/node_modules"

cat > "$WORK/title.html" <<EOF
<!doctype html><meta charset=utf-8>
<style>
@font-face{font-family:IS;src:url(file://$FONTS/@fontsource/instrument-serif/files/instrument-serif-latin-400-normal.woff2)}
@font-face{font-family:IS;font-style:italic;src:url(file://$FONTS/@fontsource/instrument-serif/files/instrument-serif-latin-400-italic.woff2)}
@font-face{font-family:Mona;src:url(file://$FONTS/@fontsource-variable/mona-sans/files/mona-sans-latin-wght-normal.woff2);font-weight:200 900}
html,body{margin:0;width:1280px;height:720px;background:transparent;overflow:hidden}
.shade{position:absolute;inset:0;background:linear-gradient(180deg,rgba(20,17,15,0) 0%,rgba(20,17,15,0) 63%,rgba(20,17,15,.985) 75%,#14110f 100%)}
.t{position:absolute;left:0;right:0;top:548px;text-align:center;font-family:IS;font-size:68px;line-height:1;color:#faf9f5;letter-spacing:-.005em}
.t i{color:#e08b6d}
.s{position:absolute;left:0;right:0;top:636px;text-align:center;font-family:Mona;font-weight:500;font-size:19px;letter-spacing:.02em;color:rgba(250,249,245,.62)}
</style>
<div class=shade></div>
<div class=t>Your AI limits, right in the <i>notch</i>.</div>
<div class=s>AIMeter &nbsp;·&nbsp; Free and open source</div>
EOF
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu \
  --hide-scrollbars --allow-file-access-from-files --default-background-color=00000000 \
  --force-device-scale-factor=1 --window-size=1280,720 --virtual-time-budget=2000 \
  --screenshot="$WORK/title.png" "file://$WORK/title.html" 2>/dev/null

# Limits from 1.0 s (the notch closed, the cursor on its way) to 8.0 s
# (open, before the cursor leaves), then that frame held 3.5 s; the
# headline fades in 1.0 s after the island has opened (5.4 s in).
Z="crop=1200:675:360:0,scale=1280:720:flags=lanczos,setsar=1,fps=30,format=yuv420p"
ffmpeg -loglevel error -y \
  -i src/assets/videos/island-limits-en.mp4 -loop 1 -framerate 30 -i "$WORK/title.png" \
  -filter_complex "\
[0:v]trim=1.0:8.0,setpts=PTS-STARTPTS,${Z},tpad=stop_mode=clone:stop_duration=3.5[bg];\
[1:v]format=rgba,trim=duration=10.5,fade=in:st=5.4:d=0.9:alpha=1[ov];\
[bg][ov]overlay=x=0:y='if(lt(t,5.4),24,max(0,24-(t-5.4)*30))':shortest=1,format=yuv420p[v]" \
  -map "[v]" -c:v libx264 -profile:v high -crf 22 -preset slow -movflags +faststart -an \
  public/og.mp4
echo "public/og.mp4: $(($(stat -f%z public/og.mp4) / 1024)) KB"
