import { Bell, Gauge, PawPrint, type LucideIcon } from 'lucide-react'
import { useEffect, useId, useRef, useState } from 'react'
import limitsEn from '../../assets/videos/island-limits-en.mp4'
import limitsEnPoster from '../../assets/videos/island-limits-en.webp'
import limitsEs from '../../assets/videos/island-limits-es.mp4'
import limitsEsPoster from '../../assets/videos/island-limits-es.webp'
import permissionEn from '../../assets/videos/island-permission-en.mp4'
import permissionEnPoster from '../../assets/videos/island-permission-en.webp'
import permissionEs from '../../assets/videos/island-permission-es.mp4'
import permissionEsPoster from '../../assets/videos/island-permission-es.webp'
import sessionsEn from '../../assets/videos/island-sessions-en.mp4'
import sessionsEnPoster from '../../assets/videos/island-sessions-en.webp'
import sessionsEs from '../../assets/videos/island-sessions-es.mp4'
import sessionsEsPoster from '../../assets/videos/island-sessions-es.webp'
import { useLanguage } from '../../hooks/useLanguage'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import type { Locale } from '../../i18n/types'
import { cn } from '../../lib/cn'
import { Device } from '../phone/Device'
import { DashboardScreen } from '../phone/screens/Dashboard'
import { APP } from '../phone/theme'

/** The recordings `Scripts/island-video.sh` makes from the real app, one per scene and language. */
interface Recording {
  icon: LucideIcon
  video: Record<Locale, string>
  poster: Record<Locale, string>
}

const SCENES: Recording[] = [
  { icon: Gauge, video: { en: limitsEn, es: limitsEs }, poster: { en: limitsEnPoster, es: limitsEsPoster } },
  { icon: PawPrint, video: { en: sessionsEn, es: sessionsEs }, poster: { en: sessionsEnPoster, es: sessionsEsPoster } },
  { icon: Bell, video: { en: permissionEn, es: permissionEs }, poster: { en: permissionEnPoster, es: permissionEsPoster } },
]

/**
 * The notch island at work: a MacBook playing one scene's recording at a
 * time, the iPhone app beside it, and the scenes to pick from under it.
 * It takes the room the opening leaves it: the MacBook is as wide as the
 * column or as tall as that room allows, whichever is less. Each scene
 * plays to its end and hands over to the next; off screen the video
 * pauses, and with reduced motion nothing plays by itself (the poster
 * shows, with the controls).
 */
export function NotchDemo() {
  const { t, lang } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const [active, setActive] = useState(0)
  const [progress, setProgress] = useState(0)
  const [inView, setInView] = useState(false)
  const rootRef = useRef<HTMLDivElement | null>(null)
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const panelId = useId()
  const scene = SCENES[active] as Recording
  const copy = t.demo.scenes[active] ?? t.demo.scenes[0]

  useEffect(() => {
    const root = rootRef.current
    if (!root) return
    const observer = new IntersectionObserver(([entry]) => setInView(entry?.isIntersecting ?? false), { threshold: 0.2 })
    observer.observe(root)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    const video = videoRef.current
    if (!video || reduced) return
    if (inView) {
      void video.play().catch(() => {})
    } else {
      video.pause()
    }
  }, [inView, reduced, active, lang])

  const choose = (index: number) => {
    setProgress(0)
    setActive(index)
  }

  return (
    // `--frame` is the MacBook's height over its width: the screen (4:3, cut
    // round the notch on a phone, else 16:9) and its bezel, 0.8% a side. The
    // MacBook is as wide as the column, or as wide as the room's height
    // allows once the hinge (0.75rem), the tabs (2.5rem) and the gap are out.
    <div ref={rootRef} className="tab:[--frame:0.5785] flex min-h-0 w-full flex-1 [--frame:0.766] [container-type:size]">
      <div className="flex h-full w-full flex-col items-center justify-center gap-[clamp(0.6rem,1.6svh,1rem)]">
        <div className="relative" style={{ width: 'min(100cqw, calc((100cqh - 3.25rem - clamp(0.6rem, 1.6svh, 1rem)) / var(--frame)))' }}>
          <div className="rounded-[1.4rem] bg-[#0b0908] p-[0.8%] shadow-[0_60px_120px_-30px_rgba(0,0,0,0.7)] ring-1 ring-white/15">
            {/* On a phone the screen is cut taller around the notch, so the island reads at a useful size. */}
            <div id={panelId} role="tabpanel" className="bg-night tab:aspect-video relative aspect-[4/3] overflow-hidden rounded-[0.8rem]">
              <video
                key={`${active}-${lang}`}
                ref={videoRef}
                src={scene.video[lang]}
                poster={scene.poster[lang]}
                aria-label={copy.title}
                muted
                playsInline
                preload="auto"
                autoPlay={!reduced && inView}
                controls={reduced}
                onTimeUpdate={(event) => {
                  const { currentTime, duration } = event.currentTarget
                  if (duration) setProgress(currentTime / duration)
                }}
                onEnded={() => {
                  if (!reduced) choose((active + 1) % SCENES.length)
                }}
                className="block h-full w-full object-cover object-top"
              />
            </div>
          </div>
          {/* The hinge and the base, with the opening's groove. */}
          <div aria-hidden className="relative left-1/2 h-3 w-[106%] -translate-x-1/2 rounded-b-[1.1rem] bg-gradient-to-b from-[#45403d] to-[#1a1715]">
            <div className="absolute top-0 left-1/2 h-1.5 w-[13%] -translate-x-1/2 rounded-b-md bg-black/45" />
          </div>
          <div className="nav:block absolute -right-[2%] -bottom-[3%] hidden w-[19%]">
            <Device background={APP.light.background} label={t.hero.phoneAlt} className="shadow-[0_40px_80px_rgba(0,0,0,0.55)]">
              <DashboardScreen copy={t.phone} />
            </Device>
          </div>
        </div>

        <div role="tablist" aria-label={t.demo.label} className="flex h-10 flex-wrap justify-center gap-2">
          {t.demo.scenes.map((label, index) => {
            const Icon = SCENES[index]?.icon ?? Gauge
            const selected = index === active
            return (
              <button
                key={label.pill}
                type="button"
                role="tab"
                aria-selected={selected}
                aria-controls={panelId}
                onClick={() => choose(index)}
                className={cn(
                  'tab:px-4 tab:text-sm relative inline-flex items-center gap-2 overflow-hidden rounded-full border px-3 py-2 text-[13px] font-medium transition-colors',
                  selected ? 'text-ivory border-white/30 bg-white/12' : 'text-blush/70 border-white/12 hover:bg-white/8',
                )}
              >
                <Icon className="size-4" aria-hidden />
                {label.pill}
                {selected && !reduced && (
                  <span aria-hidden className="bg-ember-2 absolute bottom-0 left-0 h-[2px]" style={{ width: `${progress * 100}%` }} />
                )}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}
