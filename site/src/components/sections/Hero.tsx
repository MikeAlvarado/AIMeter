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
 * it, all of it in the first screen: the words take what they need, their
 * size and gaps following the screen's height, and the demo the room left.
 * Full bleed, flush with the window's sides and top.
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
        {/* One screen tall (a height of its own, so the demo's room is known): the words above take what they need, the demo the rest. */}
        <div className="nav:px-14 relative mx-auto flex h-[100svh] min-h-[36rem] w-full max-w-6xl flex-col px-4 pt-[clamp(5.5rem,12svh,8rem)] pb-[clamp(0.75rem,2svh,1.5rem)]">
          <div className="mx-auto flex max-w-3xl flex-col items-center px-2 text-center">
            <motion.ul {...enter(0.1)} className="mb-[clamp(0.75rem,1.8svh,1.25rem)] flex flex-wrap justify-center gap-2">
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
                className="text-ivory text-[clamp(2.4rem,min(1.2rem+3.4vw,7svh),4.25rem)] leading-[1.02] [text-shadow:0_0_40px_rgba(243,217,204,0.25)]"
              />
            </motion.div>
            <motion.p {...enter(0.45)} className="text-blush/85 mt-[clamp(0.75rem,1.6svh,1.25rem)] max-w-[40rem] text-[clamp(1rem,0.9rem+0.3vw,1.125rem)] leading-relaxed">
              {t.hero.sub}
            </motion.p>
            {/* On a phone the source link waits for the page's end, so the opening fits. */}
            <motion.div {...enter(0.65)} className="mt-[clamp(1rem,2.4svh,1.75rem)] flex flex-wrap items-center justify-center gap-3">
              <AppStoreBadge light />
              <MacDownloadBadge />
              <GitHubLink className="text-ivory pad:inline-flex hidden border-white/30 hover:bg-white/10">{t.hero.github}</GitHubLink>
            </motion.div>
          </div>
          <motion.div
            className="mt-[clamp(1rem,2.6svh,2rem)] flex min-h-0 flex-1 flex-col"
            initial={reduced ? false : { opacity: 0, y: 40 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 1.1, delay: 0.6, ease: easeOutExpo }}
          >
            <NotchDemo />
          </motion.div>
        </div>
        <div className="text-blush/70 nav:px-9 relative flex items-center justify-between px-6 pb-6 text-sm">
          <span>
            {t.hero.version} {CURRENT_VERSION}
          </span>
          <span>{t.hero.platforms}</span>
        </div>
      </div>
    </section>
  )
}
