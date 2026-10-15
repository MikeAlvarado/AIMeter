import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { AccountHeader, Card, ResetGlyph, RoundButton, UsageRow } from '../parts'
import { useTicker } from '../useTicker'
import { APP, tint, type Scheme } from '../theme'
import { duration, fill } from './format'

/** Sparklines' shapes: the last 24 hours, a session's sawtooth and the week's climb. */
const SESSION_SPARK = [2, 8, 14, 3, 6, 12, 18, 4, 9, 16, 22, 30]
const WEEK_SPARK = [10, 12, 15, 17, 20, 22, 25, 27, 30, 32, 35, 38]

/**
 * The Dashboard in demo mode, as the app draws it: both accounts, their
 * windows' bars filling as the screen appears, and the session still
 * running: every few seconds its figure creeps up and its reset counts
 * down, and now and then a refresh spins.
 */
export function DashboardScreen({ copy, scheme = 'light' }: { copy: PhoneCopy; scheme?: Scheme }) {
  const palette = APP[scheme]
  const tick = useTicker(2400)
  const step = tick % 6
  const session = 42 + step
  const refreshing = tick > 0 && tick % 6 === 0
  return (
    <div className="absolute inset-0 px-4 pt-[60px]" style={{ background: palette.background }}>
      <div className="flex items-center justify-between">
        <RoundButton palette={palette}>
          <GearGlyph />
        </RoundButton>
        <span className="text-[17px] font-semibold" style={{ color: palette.ink, fontFamily: 'ui-serif, "New York", Georgia, serif' }}>
          AIMeter
        </span>
        <RoundButton palette={palette}>
          <motion.span animate={{ rotate: refreshing ? 360 : 0 }} transition={{ duration: refreshing ? 0.9 : 0, ease: 'easeInOut' }} className="grid place-items-center">
            <ResetGlyph />
          </motion.span>
        </RoundButton>
      </div>
      <div className="mt-6 flex flex-col gap-6">
        <section className="flex flex-col gap-2">
          <AccountHeader palette={palette} name={copy.personal} icon="sparkle" plan={copy.plan} />
          <Card palette={palette} className="flex flex-col gap-[14px]">
            <UsageRow palette={palette} title={copy.session} used={session} color={tint(palette, session)} reset={fill(copy.resetsIn, duration(178 - step))} spark={SESSION_SPARK} />
            <UsageRow palette={palette} title={copy.weekly} used={61} color={tint(palette, 61)} spark={WEEK_SPARK} delay={0.08} />
            <UsageRow palette={palette} title={copy.weeklyTopModel} used={18} color={tint(palette, 18)} reset={fill(copy.resetsIn, '3d 3h')} delay={0.16} />
            <Footer palette={palette} text={copy.updatedNow} />
          </Card>
        </section>
        <section className="flex flex-col gap-2">
          <AccountHeader palette={palette} name={copy.work} icon="briefcase" plan={copy.plan} />
          <Card palette={palette} className="flex flex-col gap-[14px]">
            <UsageRow palette={palette} title={copy.session} used={73} color={tint(palette, 73)} reset={fill(copy.resetsIn, '1h 11m')} spark={SESSION_SPARK.slice().reverse()} delay={0.24} />
            <UsageRow palette={palette} title={copy.weekly} used={28} color={tint(palette, 28)} reset={fill(copy.resetsIn, '5d 8h')} delay={0.32} />
            <UsageRow palette={palette} title={copy.credits} used={31} color={tint(palette, 31)} delay={0.4} />
            <Footer palette={palette} text={fill(copy.updatedMinutes, '4')} />
          </Card>
        </section>
      </div>
    </div>
  )
}

function Footer({ palette, text }: { palette: (typeof APP)[Scheme]; text: string }) {
  return (
    <div className="flex flex-col gap-3">
      <div className="h-px w-full" style={{ background: palette.track }} />
      <span className="text-[13px]" style={{ color: palette.ink2 }}>
        {text}
      </span>
    </div>
  )
}

function GearGlyph() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </svg>
  )
}
