import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { AccountCard, ResetGlyph, RoundButton } from '../parts'
import { useTicker } from '../useTicker'
import { APP, backdrop, tint, type Scheme } from '../theme'
import { duration, fill } from './format'

/** The protagonists' traces: the week's climb over the last day, and a session's sawtooth. */
const WEEK_SPARK = [55, 55, 56, 56, 57, 58, 58, 59, 60, 60, 61, 61]
const SESSION_SPARK = [18, 40, 62, 4, 26, 48, 70, 3, 3, 3, 40, 73]

/**
 * The Dashboard in demo mode, as the app draws it since 4.0: no title, when
 * the accounts last refreshed between the glass buttons, and one card per
 * account, its most urgent window large (Personal's week, Work's session)
 * and the rest one line each. The session keeps running: every few seconds
 * its figure creeps up and its reset counts down, and now and then a
 * refresh spins.
 */
export function DashboardScreen({ copy, scheme = 'light' }: { copy: PhoneCopy; scheme?: Scheme }) {
  const palette = APP[scheme]
  const tick = useTicker(2400)
  const step = tick % 6
  const session = 42 + step
  const refreshing = tick > 0 && tick % 6 === 0
  return (
    <div className="absolute inset-0 px-5 pt-[58px]" style={{ background: backdrop(palette) }}>
      <div className="flex items-center justify-between">
        <RoundButton palette={palette}>
          <GearGlyph />
        </RoundButton>
        <span className="text-[13px]" style={{ color: palette.ink2 }}>
          {copy.updatedNow}
        </span>
        <RoundButton palette={palette}>
          <motion.span animate={{ rotate: refreshing ? 360 : 0 }} transition={{ duration: refreshing ? 0.9 : 0, ease: 'easeInOut' }} className="grid place-items-center">
            <ResetGlyph />
          </motion.span>
        </RoundButton>
      </div>
      <div className="mt-6 flex flex-col gap-4">
        <AccountCard
          palette={palette}
          name={copy.personal}
          icon="sparkle"
          plan={copy.plan}
          hero={{ title: copy.weekly, used: 61, color: tint(palette, 61), reset: fill(copy.resetsIn, '3d 3h'), suffix: copy.used }}
          spark={WEEK_SPARK}
          rows={[
            { title: copy.session, used: session, color: tint(palette, session), reset: duration(178 - step) },
            { title: copy.weeklyTopModel, used: 18, color: tint(palette, 18), reset: '3d 3h' },
          ]}
        />
        <AccountCard
          palette={palette}
          name={copy.work}
          icon="briefcase"
          plan={copy.plan}
          hero={{ title: copy.session, used: 73, color: tint(palette, 73), reset: fill(copy.resetsIn, '1h 11m'), suffix: copy.used }}
          spark={SESSION_SPARK}
          rows={[
            { title: copy.weekly, used: 28, color: tint(palette, 28), reset: '5d 8h' },
            { title: copy.credits, used: 31, color: tint(palette, 31) },
          ]}
          delay={0.2}
        />
      </div>
    </div>
  )
}

function GearGlyph() {
  return (
    <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <circle cx="12" cy="12" r="3.2" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z" />
    </svg>
  )
}
