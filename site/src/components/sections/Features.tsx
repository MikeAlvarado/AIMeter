import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useId, useRef, useState, type PointerEvent, type ReactNode } from 'react'
import { useLanguage } from '../../hooks/useLanguage'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import type { PhoneCopy } from '../../i18n/types'
import { easeOutSoft } from '../../lib/easing'
import { Device } from '../phone/Device'
import { AccountsScreen } from '../phone/screens/Accounts'
import { AlertsScreen } from '../phone/screens/Alerts'
import { DashboardScreen } from '../phone/screens/Dashboard'
import { HistoryScreen } from '../phone/screens/History'
import { PaceScreen } from '../phone/screens/Pace'
import { WidgetsScreen } from '../phone/screens/Widgets'
import { APP } from '../phone/theme'
import { MixedHeading } from '../ui/MixedHeading'
import { FeatureCarousel, FeaturePoints } from './FeatureCarousel'

/** How long each feature holds the phone before the next. */
const DWELL_MS = 7000
/** How long a new screen takes to come in over the one it replaces. */
const SWAP_S = 0.45

/** Each feature's live screen, and the color its screen is drawn on. */
const SCREENS: Record<string, { background: string; dark: boolean; render: (copy: PhoneCopy) => ReactNode }> = {
  limits: { background: APP.light.background, dark: false, render: (copy) => <DashboardScreen copy={copy} /> },
  widgets: { background: '#120d0b', dark: true, render: (copy) => <WidgetsScreen copy={copy} /> },
  history: { background: APP.light.background, dark: false, render: (copy) => <HistoryScreen copy={copy} /> },
  alerts: { background: '#120d0b', dark: true, render: (copy) => <AlertsScreen copy={copy} /> },
  pace: { background: APP.light.background, dark: false, render: (copy) => <PaceScreen copy={copy} /> },
  accounts: { background: APP.dark.background, dark: true, render: (copy) => <AccountsScreen copy={copy} /> },
}

/**
 * What the app does, in one place: the six features, and one iPhone whose
 * screen is drawn live (`components/phone`), the chosen feature's: the
 * Dashboard's bars filling, the widgets, the history drawing itself, the
 * alerts arriving, the pace, the accounts trading places. The phone stays
 * put; only its screen changes, the new one fading in over the old.
 *
 * From the `tab` breakpoint up the features are a list beside the phone;
 * below it, cards swiped under the phone (`FeatureCarousel`), and on a
 * phone only the phone's top shows, drawn larger. It moves on by itself
 * every few seconds, the active row's line (or dot) filling meanwhile,
 * written straight to the element so the phone is not drawn again every
 * frame. Pointing at it or focusing it pauses it, a touch pauses it until
 * it has left the screen, scrolling it away pauses it, and with reduced
 * motion only a click, a tap or a swipe changes it.
 */
export function Features() {
  const { t } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const items = t.features.items
  const [active, setActive] = useState(0)
  const progressRef = useRef(0)
  const lineRef = useRef<HTMLSpanElement | null>(null)
  const dotRef = useRef<HTMLSpanElement | null>(null)
  const [held, setHeld] = useState(false)
  const [touched, setTouched] = useState(false)
  const [inView, setInView] = useState(false)
  const sectionRef = useRef<HTMLElement | null>(null)
  const panelId = useId()
  const feature = items[active] ?? items[0]
  const screen = SCREENS[feature?.id ?? 'limits'] ?? SCREENS.limits!

  useEffect(() => {
    const section = sectionRef.current
    if (!section) return
    const observer = new IntersectionObserver(
      ([entry]) => {
        const visible = entry?.isIntersecting ?? false
        setInView(visible)
        // A finger has no hover to leave: a touch holds the features until they have left the screen.
        if (!visible) setTouched(false)
      },
      { threshold: 0.35 },
    )
    observer.observe(section)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (reduced || held || touched || !inView) return
    let frame = 0
    let last = performance.now()
    const step = (now: number) => {
      progressRef.current += (now - last) / DWELL_MS
      last = now
      if (progressRef.current >= 1) {
        progressRef.current = 0
        setActive((index) => (index + 1) % items.length)
      }
      const scale = `scaleX(${progressRef.current})`
      if (lineRef.current) lineRef.current.style.transform = scale
      if (dotRef.current) dotRef.current.style.transform = scale
      frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [reduced, held, touched, inView, items.length])

  const choose = (index: number) => {
    progressRef.current = 0
    if (lineRef.current) lineRef.current.style.transform = 'scaleX(0)'
    if (dotRef.current && !reduced) dotRef.current.style.transform = 'scaleX(0)'
    setActive(index)
  }

  /** A mouse or a pen holds the features while over them; a finger has no hover to leave, so a touch is `touched` instead. */
  const hover = (event: PointerEvent<HTMLDivElement>, over: boolean) => {
    if (event.pointerType !== 'touch') setHeld(over)
  }

  return (
    <section ref={sectionRef} id="features" className="px-inset-sm nav:px-inset nav:py-32 py-24">
      <div className="mx-auto mb-14 flex max-w-2xl flex-col items-center gap-4 text-center">
        <MixedHeading text={t.features.heading} className="text-section leading-[1.02]" />
        <p className="text-ink-2 max-w-md text-lg">{t.features.sub}</p>
      </div>
      <div
        className="tab:flex-row tab:items-center tab:gap-16 max-pad:gap-1 mx-auto flex max-w-6xl flex-col gap-4"
        onPointerEnter={(event) => hover(event, true)}
        onPointerLeave={(event) => hover(event, false)}
        onTouchStart={() => setTouched(true)}
        onFocus={() => setHeld(true)}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget)) setHeld(false)
        }}
      >
        <ul role="tablist" aria-orientation="vertical" aria-label={t.features.listLabel} className="tab:flex hidden flex-1 flex-col">
          {items.map((item, index) => {
            const selected = index === active
            return (
              <li key={item.id} className="border-hairline border-t last:border-b">
                <button
                  type="button"
                  role="tab"
                  aria-selected={selected}
                  aria-controls={panelId}
                  onClick={() => choose(index)}
                  className="group relative flex w-full items-baseline gap-4 py-4 text-left"
                >
                  <span className="text-ink-2 text-sm tabular">({String(index + 1).padStart(2, '0')})</span>
                  <span className={selected ? 'text-ink tab:text-3xl text-2xl leading-tight tracking-tight' : 'text-ink-2 group-hover:text-ink tab:text-3xl text-2xl leading-tight tracking-tight transition-colors'}>
                    {item.title}
                  </span>
                  {selected && !reduced && (
                    <span ref={lineRef} aria-hidden className="bg-accent absolute -top-px left-0 h-px w-full origin-left" style={{ transform: 'scaleX(0)' }} />
                  )}
                </button>
                <AnimatePresence initial={false}>
                  {selected && (
                    <motion.div
                      initial={{ height: 0, opacity: 0 }}
                      animate={{ height: 'auto', opacity: 1 }}
                      exit={{ height: 0, opacity: 0 }}
                      transition={{ duration: 0.4, ease: easeOutSoft }}
                      className="overflow-hidden"
                    >
                      <div className="flex flex-col gap-4 pb-6 pl-12">
                        <p className="text-ink/80 max-w-xl text-base leading-relaxed">{item.body}</p>
                        <FeaturePoints points={item.points} />
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </li>
            )
          })}
        </ul>
        {/* Under the `tab` breakpoint it also yields to a short screen (a
            width 390/844 of its height, 0.462), so the dots and a card's
            title fit under it. On a phone only its top shows, drawn larger:
            the bezel is cut 650 pt down its 844 pt screen (an aspect of
            390/621, so it yields at 0.628 of the room left) and fades out
            from 545 pt (84 % of the way down), below every screen's point;
            the lowest, Pace's Forecast card, ends at 560 pt. */}
        <div
          id={panelId}
          role="tabpanel"
          className="tab:order-none tab:w-[19rem] tab:max-w-none max-pad:w-[min(78vw,22rem)] max-pad:max-w-[max(13.5rem,calc((100svh-17rem)*0.628))] max-pad:aspect-[390/621] max-pad:overflow-hidden max-pad:edge-fade-b max-pad:[--fade-from:84%] order-first mx-auto w-[clamp(13.5rem,56vw,15.5rem)] max-w-[max(10rem,calc((100svh-16rem)*0.462))] shrink-0"
        >
          {/* Cut, it keeps no shadow (the cut would show) and draws its hairline inside. */}
          <Device background={screen.background} dark={screen.dark} label={feature?.imageAlt ?? ''} className="max-pad:shadow-none max-pad:ring-inset">
            {/* The leaving screen stays whole under the arriving one until
                it is covered, so nothing else shows through the fade. */}
            <AnimatePresence initial={false}>
              <motion.div
                key={`${feature?.id}-${t.phone.session}`}
                className="absolute inset-0"
                initial={reduced ? false : { opacity: 0, scale: 1.03 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, transition: { delay: SWAP_S, duration: 0 } }}
                transition={{ duration: SWAP_S, ease: easeOutSoft }}
              >
                {screen.render(t.phone)}
              </motion.div>
            </AnimatePresence>
          </Device>
        </div>
        <div className="tab:hidden">
          <FeatureCarousel items={items} active={active} reduced={reduced} panelId={panelId} fillRef={dotRef} onSelect={choose} />
        </div>
      </div>
    </section>
  )
}
