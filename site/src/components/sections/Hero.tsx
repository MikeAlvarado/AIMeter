import { motion } from 'motion/react'
import { useRef } from 'react'
import dashboard from '../../assets/dashboard.webp'
import widgetTwo from '../../assets/widget-two-dark.webp'
import { useHeroRecede } from '../../hooks/useHeroRecede'
import { useLanguage } from '../../hooks/useLanguage'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { easeOutExpo, easeOutSoft } from '../../lib/easing'
import { CURRENT_VERSION } from '../../lib/site'
import { AppStoreBadge } from '../ui/AppStoreBadge'
import { GitHubLink } from '../ui/GitHubLink'
import { GrainOverlay } from '../ui/GrainOverlay'
import { MixedHeading } from '../ui/MixedHeading'
import { PhoneFrame } from '../ui/PhoneFrame'
import { Pill } from '../ui/Pill'

export function Hero() {
  const { t } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const cardRef = useRef<HTMLDivElement | null>(null)
  useHeroRecede(cardRef)
  const enter = (delay: number) => ({
    initial: reduced ? false : { opacity: 0, y: 14 },
    animate: { opacity: 1, y: 0 },
    transition: { duration: 0.8, delay, ease: easeOutSoft },
  })

  return (
    <section id="top" className="p-inset-sm nav:p-inset">
      <div
        ref={cardRef}
        className="rounded-shell night-gradient nav:min-h-[calc(100svh-4.5rem)] relative flex min-h-[calc(100svh-2rem)] flex-col overflow-hidden text-ivory [transform-origin:50%_0%]"
      >
        <motion.div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-[radial-gradient(60%_50%_at_70%_30%,rgba(224,139,109,0.35)_0%,transparent_70%)]"
          initial={reduced ? false : { scale: 1.08, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ duration: 1.6, ease: easeOutExpo }}
        />
        <GrainOverlay className="opacity-[0.08]" />
        <div className="nav:flex-row nav:items-center nav:gap-10 nav:px-14 nav:pt-28 relative flex flex-1 flex-col gap-12 px-6 pt-28 pb-8">
          <div className="nav:max-w-[34rem] flex flex-1 flex-col items-start">
            <motion.ul {...enter(0.1)} className="mb-7 flex flex-wrap gap-2">
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
            <motion.p {...enter(0.45)} className="text-blush/85 mt-6 max-w-[30rem] text-lg leading-relaxed">
              {t.hero.sub}
            </motion.p>
            <motion.div {...enter(0.65)} className="mt-9 flex flex-wrap items-center gap-3">
              <AppStoreBadge light />
              <GitHubLink className="text-ivory border-white/30 hover:bg-white/10">{t.hero.github}</GitHubLink>
            </motion.div>
          </div>
          <motion.div
            className="nav:w-[26rem] relative mx-auto w-full max-w-[22rem] shrink-0"
            initial={reduced ? false : { opacity: 0, y: 40 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 1.1, delay: 0.5, ease: easeOutExpo }}
          >
            <PhoneFrame src={dashboard} alt={t.hero.phoneAlt} priority className="nav:w-[17rem] mx-auto w-[15rem] rotate-[3deg]" />
            <motion.img
              src={widgetTwo}
              alt={t.hero.widgetAlt}
              width={1059}
              height={537}
              decoding="async"
              className="nav:-left-6 nav:w-[17rem] absolute bottom-10 -left-2 w-[14rem] drop-shadow-[0_30px_50px_rgba(0,0,0,0.5)]"
              initial={reduced ? false : { opacity: 0, x: -24 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ duration: 1, delay: 0.95, ease: easeOutExpo }}
            />
          </motion.div>
        </div>
        <div className="text-blush/70 nav:px-9 relative flex items-center justify-between px-6 pb-6 text-sm">
          <span>
            {t.hero.version} {CURRENT_VERSION}
          </span>
          <motion.span initial={reduced ? false : { opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.8, delay: 1.4 }}>
            {t.hero.scroll}
          </motion.span>
          <span>{t.hero.platforms}</span>
        </div>
      </div>
    </section>
  )
}
