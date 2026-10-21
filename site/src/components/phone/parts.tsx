import { animate, motion } from 'motion/react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import { ROUNDED_FONT, surface, type Palette } from './theme'

// The app's pieces as the screens on the page draw them, at the app's own
// sizes in points (the screen is laid out at 390 × 844 and scaled to fit).

/** A figure that counts up to `to` as the screen appears, then follows it. */
export function CountUp({ to, delay = 0, suffix = '' }: { to: number; delay?: number; suffix?: string }) {
  const reduced = usePrefersReducedMotion()
  const [value, setValue] = useState(0)
  // Where it is now, so a new target counts on from there, not from zero.
  const current = useRef(0)
  useEffect(() => {
    if (reduced) return
    const controls = animate(current.current, to, {
      duration: 1.1,
      delay,
      ease: [0.22, 1, 0.36, 1],
      onUpdate: (latest) => {
        current.current = latest
        setValue(latest)
      },
    })
    return () => controls.stop()
  }, [to, delay, reduced])
  return (
    <>
      {Math.round(reduced ? to : value)}
      {suffix}
    </>
  )
}

/** A bar; `lit` is the protagonist's, its fill easing into its color, never glowing. */
export function Bar({ value, color, track, delay = 0, height = 6, lit = false }: { value: number; color: string; track: string; delay?: number; height?: number; lit?: boolean }) {
  return (
    <div className="w-full overflow-hidden rounded-full" style={{ height, background: track }}>
      <motion.div
        className="h-full rounded-full"
        style={{ background: lit ? `linear-gradient(90deg, ${color}D9, ${color})` : color }}
        initial={{ width: 0 }}
        animate={{ width: `${Math.min(100, value)}%` }}
        transition={{ duration: 1.1, delay, ease: [0.22, 1, 0.36, 1] }}
      />
    </div>
  )
}

export function Card({ palette, children, className = '' }: { palette: Palette; children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-[24px] p-4 ${className}`} style={surface(palette)}>
      {children}
    </div>
  )
}

/**
 * An account's card (4.0, `AccountSectionView`): its identity inside, the
 * window closest to its limit large with its trace and its reset, and the
 * others one line each in shared columns. No hairlines.
 */
export function AccountCard({
  palette,
  name,
  icon,
  plan,
  hero,
  rows,
  spark,
  delay = 0,
}: {
  palette: Palette
  name: string
  icon: 'sparkle' | 'briefcase'
  plan?: string
  hero: { title: string; used: number; color: string; reset?: string; suffix: string }
  rows: { title: string; used: number; color: string; reset?: string }[]
  spark?: number[]
  delay?: number
}) {
  return (
    <div className="flex flex-col gap-5 rounded-[24px] p-5" style={surface(palette)}>
      <AccountIdentity palette={palette} name={name} icon={icon} plan={plan} />
      <div className="flex flex-col gap-[14px]">
        <div className="flex items-end gap-3">
          <div className="flex min-w-0 flex-col gap-[2px]">
            <span className="text-[15px] font-semibold" style={{ color: palette.ink2 }}>
              {hero.title}
            </span>
            <span className="flex items-baseline leading-none whitespace-nowrap" style={{ fontFamily: ROUNDED_FONT }}>
              <span className="text-[54px] font-semibold tracking-[-0.02em] tabular-nums" style={{ color: palette.ink }}>
                <CountUp to={hero.used} delay={delay} />
              </span>
              <span className="text-[25px] font-semibold" style={{ color: palette.ink2 }}>
                %
              </span>
              <span className="ml-1 text-[15px] font-medium" style={{ color: palette.ink2, fontFamily: 'inherit' }}>
                {hero.suffix}
              </span>
            </span>
          </div>
          <span className="flex-1" />
          <div className="flex flex-col items-end gap-2 pb-[6px]">
            {spark && <Sparkline points={spark} color={hero.color} width={92} height={30} filled />}
            {hero.reset && (
              <span className="text-[13px] font-medium whitespace-nowrap" style={{ color: palette.ink2 }}>
                {hero.reset}
              </span>
            )}
          </div>
        </div>
        <Bar value={hero.used} color={hero.color} track={palette.track} delay={delay} height={10} lit />
      </div>
      {rows.length > 0 && (
        <div className="grid items-center gap-x-3 gap-y-[13px]" style={{ gridTemplateColumns: 'auto minmax(36px, 1fr) auto auto' }}>
          {rows.map((row, index) => (
            <CompactRow key={row.title} palette={palette} row={row} delay={delay + 0.08 * (index + 1)} />
          ))}
        </div>
      )}
    </div>
  )
}

function CompactRow({ palette, row, delay }: { palette: Palette; row: { title: string; used: number; color: string; reset?: string }; delay: number }) {
  return (
    <>
      <span className="text-[15px] font-medium whitespace-nowrap" style={{ color: palette.ink }}>
        {row.title}
      </span>
      <Bar value={row.used} color={row.color} track={palette.track} delay={delay} height={5} />
      <span className="text-right text-[15px] font-semibold tabular-nums" style={{ color: palette.ink, fontFamily: ROUNDED_FONT }}>
        <CountUp to={row.used} delay={delay} suffix="%" />
      </span>
      <span className="text-right text-[13px] whitespace-nowrap" style={{ color: palette.ink2 }}>
        {row.reset ?? ''}
      </span>
    </>
  )
}

/** The identity at the top of an account's card: the mark, the name, the plan, the chevron. */
export function AccountIdentity({ palette, name, icon, plan }: { palette: Palette; name: string; icon: 'sparkle' | 'briefcase'; plan?: string }) {
  return (
    <div className="flex items-center gap-[10px]">
      <span className="grid size-[26px] place-items-center rounded-[8px]" style={{ background: `${palette.accent}24`, color: palette.accent }}>
        {icon === 'sparkle' ? <SparkleGlyph size={14} /> : <BriefcaseGlyph size={14} />}
      </span>
      <span className="text-[17px] font-semibold" style={{ color: palette.ink }}>
        {name}
      </span>
      {plan && (
        <span className="rounded-full px-[10px] py-[2px] text-[12px] font-semibold" style={{ background: `${palette.track}B3`, color: palette.ink2 }}>
          {plan}
        </span>
      )}
      <span className="flex-1" />
      <ChevronGlyph color={palette.ink2} />
    </div>
  )
}

/** One window: its name, the figure, the bar, and under it the reset and the pace. */
export function UsageRow({
  palette,
  title,
  used,
  color,
  reset,
  pace,
  spark,
  delay = 0,
}: {
  palette: Palette
  title: string
  used: number
  color: string
  reset?: string
  pace?: string
  spark?: number[]
  delay?: number
}) {
  return (
    <div className="flex flex-col gap-[7px]">
      <div className="flex items-center gap-2">
        <span className="flex-1 text-[17px] font-medium" style={{ color: palette.ink }}>
          {title}
        </span>
        {spark && <Sparkline points={spark} color={palette.ink2} />}
        <span className="text-[17px] font-semibold tabular-nums" style={{ color: palette.ink, fontFamily: ROUNDED_FONT }}>
          <CountUp to={used} delay={delay} suffix="%" />
        </span>
      </div>
      <Bar value={used} color={color} track={palette.track} delay={delay} />
      {(reset || pace) && (
        <motion.div
          className="flex items-center gap-1 text-[13px]"
          style={{ color: palette.ink2 }}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: delay + 0.5, duration: 0.5 }}
        >
          {pace && <span className="mr-1">{pace}</span>}
          {reset && (
            <>
              <ResetGlyph />
              <span>{reset}</span>
            </>
          )}
        </motion.div>
      )}
    </div>
  )
}

export function Toggle({ on, palette }: { on: boolean; palette: Palette }) {
  return (
    <motion.span
      className="relative inline-flex h-[31px] w-[51px] shrink-0 rounded-full"
      animate={{ backgroundColor: on ? palette.accent : palette.track }}
      transition={{ duration: 0.25 }}
    >
      <motion.span
        className="absolute top-[2px] size-[27px] rounded-full bg-white shadow-[0_2px_6px_rgba(0,0,0,0.18)]"
        animate={{ left: on ? 22 : 2 }}
        transition={{ type: 'spring', stiffness: 500, damping: 32 }}
      />
    </motion.span>
  )
}

/** The app's segmented pill: the chosen one on the accent's wash. */
export function Segmented({ palette, options, selected, id }: { palette: Palette; options: string[]; selected: number; id: string }) {
  return (
    <div className="flex rounded-full p-[3px]" style={{ background: palette.track }}>
      {options.map((option, index) => (
        <span key={option} className="relative flex-1 py-[7px] text-center text-[14px] font-medium" style={{ color: index === selected ? palette.ink : palette.ink2 }}>
          {index === selected && (
            <motion.span layoutId={id} className="absolute inset-0 rounded-full" style={{ background: `${palette.accent}2E` }} transition={{ type: 'spring', stiffness: 420, damping: 36 }} />
          )}
          <span className="relative">{option}</span>
        </span>
      ))}
    </div>
  )
}

/** A trace of the last 24 hours; `filled` is the protagonist's, in its bar's color with a fade under it and its latest point marked. */
export function Sparkline({ points, color, width = 56, height = 16, filled = false }: { points: number[]; color: string; width?: number; height?: number; filled?: boolean }) {
  const max = filled ? 100 : Math.max(...points, 1)
  const xy = points.map((value, index) => [(index / (points.length - 1)) * width, height - (value / max) * (height - 4) - 2] as const)
  const path = xy.map(([x, y], index) => `${index === 0 ? 'M' : 'L'}${x},${y}`).join(' ')
  const last = xy[xy.length - 1] ?? [0, 0]
  const gid = `spark-${color.replace('#', '')}`
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} className="mr-1 shrink-0 overflow-visible" aria-hidden>
      {filled && (
        <>
          <defs>
            <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor={color} stopOpacity={0.16} />
              <stop offset="1" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <motion.path d={`${path} L${width},${height} L0,${height} Z`} fill={`url(#${gid})`} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 0.6, duration: 0.6 }} />
        </>
      )}
      <motion.path d={path} fill="none" stroke={color} strokeWidth={filled ? 1.8 : 1.2} strokeLinecap="round" strokeLinejoin="round" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.2, ease: 'easeOut' }} />
      {filled && <motion.circle cx={last[0]} cy={last[1]} r={2.6} fill={color} initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ delay: 1.1 }} />}
    </svg>
  )
}

// MARK: Glyphs, drawn after the SF Symbols the app uses.

export function ResetGlyph() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M20 12a8 8 0 1 1-2.34-5.66" />
      <path d="M20 4v5h-5" />
    </svg>
  )
}

export function SparkleGlyph({ size = 12 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M12 1.5c.6 4.9 2.1 8.4 4.2 9.9 1.4 1 3.5 1.4 6.3 1.6-2.8.2-4.9.6-6.3 1.6-2.1 1.5-3.6 5-4.2 9.9-.6-4.9-2.1-8.4-4.2-9.9-1.4-1-3.5-1.4-6.3-1.6 2.8-.2 4.9-.6 6.3-1.6 2.1-1.5 3.6-5 4.2-9.9z" />
    </svg>
  )
}

export function BriefcaseGlyph({ size = 12 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
      <path d="M9 3h6a2 2 0 0 1 2 2v1h3a2 2 0 0 1 2 2v4H2V8a2 2 0 0 1 2-2h3V5a2 2 0 0 1 2-2zm0 3h6V5H9v1zM2 14h9v1.5h2V14h9v5a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-5z" />
    </svg>
  )
}

export function ChevronGlyph({ color, back = false }: { color: string; back?: boolean }) {
  return (
    <svg width="9" height="15" viewBox="0 0 9 15" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden style={back ? { transform: 'scaleX(-1)' } : undefined}>
      <path d="M1.5 1.5l6 6-6 6" />
    </svg>
  )
}

/** A floating round button on Liquid Glass (`glassControl`): translucent, a light rim, a soft shadow. */
export function RoundButton({ palette, children }: { palette: Palette; children: ReactNode }) {
  const dark = palette.background === '#262624'
  return (
    <span
      className="grid size-[44px] place-items-center rounded-full backdrop-blur-xl"
      style={{
        background: dark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.55)',
        color: palette.ink,
        boxShadow: dark
          ? 'inset 0 1px 0 rgba(255,255,255,0.14), inset 0 0 0 0.5px rgba(255,255,255,0.10), 0 6px 16px rgba(0,0,0,0.3)'
          : 'inset 0 1px 0 rgba(255,255,255,0.95), inset 0 0 0 0.5px rgba(31,30,29,0.08), 0 6px 16px rgba(0,0,0,0.07)',
      }}
    >
      {children}
    </span>
  )
}
