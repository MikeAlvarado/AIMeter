import { Bell, Gauge, PawPrint, type LucideIcon } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
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
import { easeOutSoft } from '../../lib/easing'
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
 * time, the iPhone app beside it, and the scenes to pick from under it with
 * their title and line. Each scene plays to its end and hands over to the
 * next; off screen the video pauses, and with reduced motion nothing plays
 * by itself (the poster shows, with the controls).
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
    <div ref={rootRef} className="flex flex-col items-center gap-8">
      <div className="relative w-full">
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
        <div className="nav:block absolute -right-[2%] -bottom-[9%] hidden w-[19%]">
          <Device background={APP.light.background} label={t.hero.phoneAlt} className="shadow-[0_40px_80px_rgba(0,0,0,0.55)]">
            <DashboardScreen copy={t.phone} />
          </Device>
        </div>
      </div>

      <div role="tablist" aria-label={t.demo.label} className="flex flex-wrap justify-center gap-2">
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

      <div className="min-h-[7.5rem] max-w-xl text-center" aria-live="polite">
        <AnimatePresence mode="wait">
          <motion.div
            key={`${active}-${lang}`}
            initial={reduced ? false : { opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reduced ? undefined : { opacity: 0, y: -6 }}
            transition={{ duration: 0.35, ease: easeOutSoft }}
          >
            <h2 className="text-ivory font-display text-[clamp(1.8rem,1.2rem+1.6vw,2.6rem)] leading-tight">{copy.title}</h2>
            <p className="text-blush/80 mt-3 text-base leading-relaxed">{copy.body}</p>
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  )
}
