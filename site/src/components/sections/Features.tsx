import { AnimatePresence, motion } from 'motion/react'
import { useEffect, useId, useRef, useState, type ReactNode } from 'react'
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
 * What the app does, in one place: the six features as a list, and one
 * iPhone beside it whose screen is drawn live (`components/phone`), the
 * chosen feature's: the Dashboard's bars filling, the widgets, the history
 * drawing itself, the alerts arriving, the pace, the accounts trading
 * places. The phone stays put; only its screen changes, the new one fading
 * in over the old. It moves on by itself every few seconds, the active
 * item's line filling meanwhile (written straight to the line, so the phone
 * is not drawn again every frame); pointing at it, focusing it or scrolling
 * it away pauses it, a click picks a feature, and with reduced motion only
 * a click does.
 */
export function Features() {
  const { t } = useLanguage()
  const reduced = usePrefersReducedMotion()
  const items = t.features.items
  const [active, setActive] = useState(0)
  const progressRef = useRef(0)
  const lineRef = useRef<HTMLSpanElement | null>(null)
  const [held, setHeld] = useState(false)
  const [inView, setInView] = useState(false)
  const sectionRef = useRef<HTMLElement | null>(null)
  const panelId = useId()
  const feature = items[active] ?? items[0]
  const screen = SCREENS[feature?.id ?? 'limits'] ?? SCREENS.limits!

  useEffect(() => {
    const section = sectionRef.current
    if (!section) return
    const observer = new IntersectionObserver(([entry]) => setInView(entry?.isIntersecting ?? false), { threshold: 0.35 })
    observer.observe(section)
    return () => observer.disconnect()
  }, [])

  useEffect(() => {
    if (reduced || held || !inView) return
    let frame = 0
    let last = performance.now()
    const step = (now: number) => {
      progressRef.current += (now - last) / DWELL_MS
      last = now
      if (progressRef.current >= 1) {
        progressRef.current = 0
        setActive((index) => (index + 1) % items.length)
      }
      if (lineRef.current) lineRef.current.style.transform = `scaleX(${progressRef.current})`
      frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [reduced, held, inView, items.length])

  const choose = (index: number) => {
    progressRef.current = 0
    if (lineRef.current) lineRef.current.style.transform = 'scaleX(0)'
    setActive(index)
  }

  return (
    <section ref={sectionRef} id="features" className="px-inset-sm nav:px-inset nav:py-32 py-24">
      <div className="mx-auto mb-14 flex max-w-2xl flex-col items-center gap-4 text-center">
        <MixedHeading text={t.features.heading} className="text-section leading-[1.02]" />
        <p className="text-ink-2 max-w-md text-lg">{t.features.sub}</p>
      </div>
      <div
        className="tab:flex-row tab:items-center tab:gap-16 mx-auto flex max-w-6xl flex-col gap-10"
        onMouseEnter={() => setHeld(true)}
        onMouseLeave={() => setHeld(false)}
        onFocus={() => setHeld(true)}
        onBlur={(event) => {
          if (!event.currentTarget.contains(event.relatedTarget)) setHeld(false)
        }}
      >
        <ul role="tablist" aria-orientation="vertical" aria-label={t.features.listLabel} className="flex flex-1 flex-col">
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
                        <ul className="text-ink-2 flex flex-col gap-2 text-sm">
                          {item.points.map((point) => (
                            <li key={point} className="flex gap-2.5">
                              <span aria-hidden className="bg-accent mt-[0.55em] size-1.5 shrink-0 rounded-full" />
                              {point}
                            </li>
                          ))}
                        </ul>
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </li>
            )
          })}
        </ul>
        <div id={panelId} role="tabpanel" className="tab:order-none tab:w-[19rem] order-first mx-auto w-[15.5rem] shrink-0">
          <Device background={screen.background} dark={screen.dark} label={feature?.imageAlt ?? ''}>
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
      </div>
    </section>
  )
}
