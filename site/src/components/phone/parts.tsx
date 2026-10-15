import { animate, motion } from 'motion/react'
import { useEffect, useRef, useState, type ReactNode } from 'react'
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion'
import type { Palette } from './theme'

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

export function Bar({ value, color, track, delay = 0, height = 6 }: { value: number; color: string; track: string; delay?: number; height?: number }) {
  return (
    <div className="w-full overflow-hidden rounded-full" style={{ height, background: track }}>
      <motion.div
        className="h-full rounded-full"
        style={{ background: color }}
        initial={{ width: 0 }}
        animate={{ width: `${Math.min(100, value)}%`, backgroundColor: color }}
        transition={{ duration: 1.1, delay, ease: [0.22, 1, 0.36, 1] }}
      />
    </div>
  )
}

export function Card({ palette, children, className = '' }: { palette: Palette; children: ReactNode; className?: string }) {
  return (
    <div className={`rounded-[20px] p-4 ${className}`} style={{ background: palette.card, boxShadow: '0 1px 2px rgba(0,0,0,0.04), 0 6px 18px rgba(0,0,0,0.05)' }}>
      {children}
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
        <span className="text-[17px] font-semibold tabular-nums" style={{ color: palette.ink }}>
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

export function AccountHeader({ palette, name, icon, plan, chevron = true }: { palette: Palette; name: string; icon: 'sparkle' | 'briefcase'; plan?: string; chevron?: boolean }) {
  return (
    <div className="flex items-center gap-2 px-1">
      <span className="grid size-[22px] place-items-center rounded-[6px]" style={{ background: `${palette.accent}24`, color: palette.accent }}>
        {icon === 'sparkle' ? <SparkleGlyph /> : <BriefcaseGlyph />}
      </span>
      <span className="text-[15px] font-medium" style={{ color: palette.ink2 }}>
        {name}
      </span>
      {plan && (
        <span className="rounded-full px-2 py-[1px] text-[12px] font-medium" style={{ background: palette.track, color: palette.ink2 }}>
          {plan}
        </span>
      )}
      <span className="flex-1" />
      {chevron && <ChevronGlyph color={palette.ink2} />}
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

export function Sparkline({ points, color }: { points: number[]; color: string }) {
  const width = 56
  const height = 16
  const max = Math.max(...points, 1)
  const path = points.map((value, index) => `${index === 0 ? 'M' : 'L'}${(index / (points.length - 1)) * width},${height - (value / max) * (height - 2) - 1}`).join(' ')
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} className="mr-1 shrink-0" aria-hidden>
      <motion.path d={path} fill="none" stroke={color} strokeWidth={1.2} strokeLinejoin="round" initial={{ pathLength: 0 }} animate={{ pathLength: 1 }} transition={{ duration: 1.2, ease: 'easeOut' }} />
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

export function RoundButton({ palette, children }: { palette: Palette; children: ReactNode }) {
  return (
    <span className="grid size-[36px] place-items-center rounded-full" style={{ background: palette.card, color: palette.ink, boxShadow: '0 1px 3px rgba(0,0,0,0.08)' }}>
      {children}
    </span>
  )
}
