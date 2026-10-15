import { motion } from 'motion/react'
import { useRef } from 'react'
import { useLanguage } from '../../hooks/useLanguage'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { easeOutExpo, easeOutSoft } from '../../lib/easing'
import { CURRENT_VERSION } from '../../lib/site'
import { AppStoreBadge } from '../ui/AppStoreBadge'
import { GitHubLink } from '../ui/GitHubLink'
import { GrainOverlay } from '../ui/GrainOverlay'
import { MacDownloadBadge } from '../ui/MacDownloadBadge'
import { PlusGrid } from '../ui/PlusGrid'
import { MixedHeading } from '../ui/MixedHeading'
import { NotchDemo } from '../ui/NotchDemo'
import { Pill } from '../ui/Pill'

/**
 * The page opens on the notch: what AIMeter is, the two downloads, and
 * under them the notch island at work (`NotchDemo`), the iPhone app beside
 * it. Full bleed, flush with the window's sides and top.
 */
export function Hero() {
  const { t } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const heroRef = useRef<HTMLDivElement | null>(null)
  const enter = (delay: number) => ({
    initial: reduced ? false : { opacity: 0, y: 14 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.8, delay, ease: easeOutSoft },
  })

  return (
    <section id="top">
      <div ref={heroRef} className="night-ground relative overflow-hidden text-ivory">
        <PlusGrid track={heroRef} />
        <GrainOverlay className="opacity-[0.06]" />
        <div className="nav:pt-36 relative mx-auto flex max-w-3xl flex-col items-center px-6 pt-28 text-center">
          <motion.ul {...enter(0.1)} className="mb-7 flex flex-wrap justify-center gap-2">
            {t.hero.pills.map((pill) => (
              <li key={pill}>
                <Pill className="text-blush/90 border-white/25">{pill}</Pill>
              </li>
            ))}
          </motion.ul>
          <motion.div {...enter(0.2)}>
            <MixedHeading
              as="h1"
              text={`${t.hero.line1}\n${t.hero.line2}`}
              className="text-hero text-ivory leading-[1.02] [text-shadow:0_0_40px_rgba(243,217,204,0.25)]"
            />
          </motion.div>
          <motion.p {...enter(0.45)} className="text-blush/85 mt-6 max-w-[38rem] text-lg leading-relaxed">
            {t.hero.sub}
          </motion.p>
          <motion.div {...enter(0.65)} className="mt-9 flex flex-wrap items-center justify-center gap-3">
            <AppStoreBadge light />
            <MacDownloadBadge />
            <GitHubLink className="text-ivory border-white/30 hover:bg-white/10">{t.hero.github}</GitHubLink>
          </motion.div>
        </div>
        <motion.div
          className="nav:px-14 nav:mt-20 relative mx-auto mt-14 w-full max-w-6xl px-4"
          initial={reduced ? false : { opacity: 0, y: 40 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 1.1, delay: 0.6, ease: easeOutExpo }}
        >
          <NotchDemo />
        </motion.div>
        <div className="text-blush/70 nav:px-9 relative mt-10 flex items-center justify-between px-6 pb-6 text-sm">
          <span>
            {t.hero.version} {CURRENT_VERSION}
          </span>
          <span>{t.hero.platforms}</span>
        </div>
      </div>
    </section>
  )
}
