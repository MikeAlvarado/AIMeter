import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { Card, ChevronGlyph, RoundButton, UsageRow } from '../parts'
import { useTicker } from '../useTicker'
import { APP, tint } from '../theme'
import { duration, fill } from './format'

const palette = APP.light

/**
 * The top of Provider Detail: each window's pace beside its reset, and the
 * Forecast card naming the one that will run out early, its estimate
 * firming up as the screen stays.
 */
export function PaceScreen({ copy }: { copy: PhoneCopy }) {
  const tick = useTicker(2600)
  const early = 1019 - (tick % 5) * 7
  return (
    <div className="absolute inset-0 px-4 pt-[60px]" style={{ background: palette.background }}>
      <div className="relative flex items-center justify-center">
        <span className="absolute left-0">
          <RoundButton palette={palette}>
            <ChevronGlyph color={palette.ink} back />
          </RoundButton>
        </span>
        <span className="text-[17px] font-semibold" style={{ color: palette.ink }}>
          {copy.personal}
        </span>
      </div>
      <span className="mt-7 mb-2 block px-1 text-[15px] font-medium" style={{ color: palette.ink2 }}>
        {copy.rateLimits}
      </span>
      <Card palette={palette} className="flex flex-col gap-[14px]">
        <UsageRow palette={palette} title={copy.session} used={42} color={tint(palette, 42)} pace={copy.onPace} reset={fill(copy.resetsIn, '2h 58m')} />
        <UsageRow palette={palette} title={copy.weekly} used={61} color={tint(palette, 61)} pace={copy.ahead} delay={0.15} />
        <UsageRow palette={palette} title={copy.weeklyTopModel} used={18} color={tint(palette, 18)} pace={copy.behind} reset={fill(copy.resetsIn, '3d 3h')} delay={0.3} />
        <div className="h-px w-full" style={{ background: palette.track }} />
        <span className="text-[13px]" style={{ color: palette.ink2 }}>
          {copy.updatedNow}
        </span>
      </Card>
      <span className="mt-6 mb-2 block px-1 text-[15px] font-medium" style={{ color: palette.ink2 }}>
        {copy.forecast}
      </span>
      <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.9, duration: 0.5 }}>
        <Card palette={palette} className="flex items-center justify-between">
          <span className="text-[17px] font-medium" style={{ color: palette.ink }}>
            {copy.weekly}
          </span>
          <span className="text-[15px] font-medium tabular-nums" style={{ color: palette.danger }}>
            {fill(copy.runsOutEarly, duration(early))}
          </span>
        </Card>
        <p className="mt-2 px-1 text-[13px] leading-snug" style={{ color: palette.ink2 }}>
          {copy.forecastNote}
        </p>
      </motion.div>
    </div>
  )
}
