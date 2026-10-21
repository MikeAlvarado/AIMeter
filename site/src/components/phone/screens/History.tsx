import { motion } from 'motion/react'
import type { PhoneCopy } from '../../../i18n/types'
import { Card, ChevronGlyph, RoundButton, Segmented } from '../parts'
import { useTicker } from '../useTicker'
import { APP, backdrop } from '../theme'

const palette = APP.light
const WIDTH = 296
const HEIGHT = 190

/** Each range's samples, as the timeline keeps them: segments that break at a reset. */
const RANGES: { window: number; segments: [number, number][][] }[] = [
  // 24 hours: idle overnight, then three five-hour sessions, the last still running.
  {
    window: 0,
    segments: [
      [[0, 0], [0.32, 0], [0.33, 4], [0.52, 58]],
      [[0.53, 2], [0.72, 74]],
      [[0.73, 3], [1, 42]],
    ],
  },
  // 7 days: one week's climb, steeper on working days.
  {
    window: 1,
    segments: [[[0, 1], [0.14, 9], [0.28, 20], [0.42, 33], [0.56, 41], [0.7, 44], [0.84, 52], [1, 61]]],
  },
  // 30 days: four weeks, each reset where the week begins.
  {
    window: 1,
    segments: [
      [[0, 30], [0.12, 66], [0.2, 81]],
      [[0.21, 2], [0.44, 74]],
      [[0.45, 4], [0.68, 88]],
      [[0.69, 1], [1, 61]],
    ],
  },
]

/**
 * Provider Detail's History card: the window and range pills, and the
 * curve of the limit used, breaking at each reset with a dashed rule, under
 * the faint 85 % line. It steps through the three ranges, drawing each.
 */
export function HistoryScreen({ copy }: { copy: PhoneCopy }) {
  const range = useTicker(3200) % RANGES.length
  const data = RANGES[range] ?? RANGES[0]!
  return (
    <div className="absolute inset-0 px-4 pt-[60px]" style={{ background: backdrop(palette) }}>
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
        {copy.history}
      </span>
      <Card palette={palette} className="flex flex-col gap-3">
        <Segmented palette={palette} options={copy.windowPills} selected={data.window} id="history-window" />
        <Segmented palette={palette} options={copy.ranges} selected={range} id="history-range" />
        <Chart key={range} segments={data.segments} labels={copy.chartLabels[range] ?? []} />
      </Card>
      <p className="mt-2 px-1 text-[13px] leading-snug" style={{ color: palette.ink2 }}>
        {copy.historyNote}
      </p>
    </div>
  )
}

function Chart({ segments, labels }: { segments: [number, number][][]; labels: string[] }) {
  const x = (value: number) => value * WIDTH
  const y = (value: number) => HEIGHT - (value / 100) * HEIGHT
  const resets = segments.slice(1).map((segment) => segment[0]?.[0] ?? 0)
  return (
    <div className="flex flex-col gap-1">
      <div className="flex gap-2">
        <svg width={WIDTH} height={HEIGHT} viewBox={`0 0 ${WIDTH} ${HEIGHT}`} className="overflow-visible" aria-hidden>
          <line x1={0} x2={WIDTH} y1={y(85)} y2={y(85)} stroke={palette.danger} strokeOpacity={0.45} strokeDasharray="3 4" />
          {resets.map((at) => (
            <line key={at} x1={x(at)} x2={x(at)} y1={0} y2={HEIGHT} stroke={palette.ink2} strokeOpacity={0.5} strokeDasharray="3 4" />
          ))}
          {segments.map((segment, index) => {
            const line = segment.map(([sx, sy], point) => `${point === 0 ? 'M' : 'L'}${x(sx)},${y(sy)}`).join(' ')
            const first = segment[0] ?? [0, 0]
            const last = segment[segment.length - 1] ?? [0, 0]
            const area = `${line} L${x(last[0])},${HEIGHT} L${x(first[0])},${HEIGHT} Z`
            const delay = index * 0.25
            return (
              <g key={index}>
                <motion.path d={area} fill={palette.accent} initial={{ opacity: 0 }} animate={{ opacity: 0.18 }} transition={{ delay: delay + 0.3, duration: 0.6 }} />
                <motion.path
                  d={line}
                  fill="none"
                  stroke={palette.accent}
                  strokeWidth={2}
                  strokeLinejoin="round"
                  initial={{ pathLength: 0 }}
                  animate={{ pathLength: 1 }}
                  transition={{ delay, duration: 0.7, ease: 'easeOut' }}
                />
              </g>
            )
          })}
        </svg>
        <div className="flex flex-col justify-between py-[2px] text-[11px]" style={{ color: palette.ink2 }}>
          <span>100%</span>
          <span>50%</span>
          <span>0%</span>
        </div>
      </div>
      <div className="flex justify-around pr-8 text-[11px]" style={{ color: palette.ink2 }}>
        {labels.map((label) => (
          <span key={label}>{label}</span>
        ))}
      </div>
    </div>
  )
}
