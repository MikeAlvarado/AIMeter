import type { ReactNode } from 'react'
import type { PhoneCopy } from '../../../i18n/types'
import { Bar, CountUp, ResetGlyph, SparkleGlyph, BriefcaseGlyph } from '../parts'
import { useTicker } from '../useTicker'
import { APP, ROUNDED_FONT, tint } from '../theme'
import { clock, fill } from './format'

const palette = APP.dark
const WIDGET = '#2A2826'

/**
 * The Home Screen with the widgets as 4.0 draws them, the app's card in
 * every size: Single Limit (one window as the protagonist), Usage Limits
 * small (the most urgent window large, the others one line each) and
 * medium (the windows as columns, like the Mac's menu bar panel), and All
 * Accounts (each account's card). The session keeps running here too.
 */
export function WidgetsScreen({ copy }: { copy: PhoneCopy }) {
  const tick = useTicker(2400)
  const step = tick % 6
  const session = 42 + step
  return (
    <div
      className="absolute inset-0 px-[26px] pt-[72px]"
      style={{ background: 'radial-gradient(120% 70% at 50% 0%, #6b3a28 0%, #2a1a14 45%, #120d0b 100%)' }}
    >
      <div className="grid grid-cols-2 gap-[22px]">
        {/* Single Limit: the window alone. */}
        <Widget className="h-[158px]">
          <Header icon="sparkle" name={copy.personal} />
          <span className="mt-[8px] text-[11px] font-semibold" style={{ color: palette.ink2 }}>
            {copy.windowPills[0]}
          </span>
          <Figure used={session} size={40} suffix={copy.used} />
          <div className="mt-auto flex flex-col gap-[7px]">
            <Bar value={session} color={tint(palette, session)} track={palette.track} height={8} lit />
            <Reset text={fill(copy.resetsIn, clock(177 - step))} />
          </div>
        </Widget>
        {/* Usage Limits, small: the protagonist and the others. */}
        <Widget className="h-[158px]">
          <Header icon="briefcase" name={copy.work} />
          <Hero title={copy.windowPills[0]} used={73} reset={clock(71)} size={28} />
          <Rows rows={[{ title: copy.week, used: 28 }, { title: copy.credits, used: 31 }]} delay={0.2} />
        </Widget>
      </div>
      {/* Usage Limits, medium: the windows as columns. */}
      <Widget className="mt-[22px] h-[158px]">
        <Header icon="sparkle" name={copy.personal} plan={copy.plan} />
        <div className="mt-3 grid flex-1 grid-cols-3 gap-[10px]">
          <Column title={copy.windowPills[0]} used={session} reset={clock(177 - step)} copy={copy} delay={0.05} />
          <Column title={copy.week} used={61} reset="3d 2h" copy={copy} delay={0.13} />
          <Column title={copy.topModel} used={18} reset="3d 2h" copy={copy} delay={0.21} />
        </div>
      </Widget>
      {/* All Accounts: each account's card. */}
      <Widget className="mt-[22px] h-[354px]">
        <Header icon="sparkle" name={copy.personal} plan={copy.plan} />
        <Hero title={copy.week} used={61} reset="3d 3h" size={34} delay={0.3} />
        <Rows rows={[{ title: copy.windowPills[0], used: session }, { title: copy.topModel, used: 18 }]} delay={0.36} />
        <span className="min-h-[14px] flex-1" />
        <Header icon="briefcase" name={copy.work} plan={copy.plan} />
        <Hero title={copy.windowPills[0]} used={73} reset={clock(71)} size={34} delay={0.48} />
        <Rows rows={[{ title: copy.week, used: 28 }, { title: copy.credits, used: 31 }]} delay={0.54} />
      </Widget>
    </div>
  )
}

function Widget({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div className={`flex flex-col rounded-[22px] p-4 ${className}`} style={{ background: WIDGET, boxShadow: '0 10px 30px rgba(0,0,0,0.35)' }}>
      {children}
    </div>
  )
}

function Header({ icon, name, plan }: { icon: 'sparkle' | 'briefcase'; name: string; plan?: string }) {
  return (
    <div className="flex items-center gap-[5px]">
      <span className="grid size-[15px] place-items-center rounded-[3.5px]" style={{ background: `${palette.accent}2E`, color: palette.accent }}>
        {icon === 'sparkle' ? <SparkleGlyph size={9} /> : <BriefcaseGlyph size={9} />}
      </span>
      <span className="text-[12px] font-semibold" style={{ color: palette.ink }}>
        {name}
      </span>
      {plan && (
        <span className="rounded-full px-[6px] text-[10px] font-semibold" style={{ background: palette.track, color: palette.ink2 }}>
          {plan}
        </span>
      )}
    </div>
  )
}

function Figure({ used, size, suffix, delay = 0 }: { used: number; size: number; suffix?: string; delay?: number }) {
  return (
    <span className="flex items-baseline leading-none" style={{ fontFamily: ROUNDED_FONT }}>
      <span className="font-semibold tabular-nums" style={{ color: palette.ink, fontSize: size }}>
        <CountUp to={used} delay={delay} />
      </span>
      <span className="font-semibold" style={{ color: palette.ink2, fontSize: size * 0.43 }}>
        %
      </span>
      {suffix && (
        <span className="ml-[3px] text-[11px] font-medium" style={{ color: palette.ink2 }}>
          {suffix}
        </span>
      )}
    </span>
  )
}

/** A widget's protagonist: the window's name, the figure with its reset beside it, a thicker bar. */
function Hero({ title, used, reset, size, delay = 0 }: { title: string; used: number; reset: string; size: number; delay?: number }) {
  return (
    <div className="mt-[8px] flex flex-col gap-[4px]">
      <span className="text-[11px] font-semibold" style={{ color: palette.ink2 }}>
        {title}
      </span>
      <div className="flex items-baseline justify-between">
        <Figure used={used} size={size} delay={delay} />
        <Reset text={reset} />
      </div>
      <Bar value={used} color={tint(palette, used)} track={palette.track} height={7} delay={delay} lit />
    </div>
  )
}

/** A widget card's other windows: name, a thin bar, the figure, in shared columns. */
function Rows({ rows, delay }: { rows: { title: string; used: number }[]; delay: number }) {
  return (
    <div className="mt-auto grid items-center gap-x-[6px] gap-y-[6px] pt-2" style={{ gridTemplateColumns: 'auto 1fr auto' }}>
      {rows.map((row, index) => (
        <Row key={row.title} {...row} delay={delay + index * 0.06} />
      ))}
    </div>
  )
}

function Row({ title, used, delay }: { title: string; used: number; delay: number }) {
  return (
    <>
      <span className="text-[11px] whitespace-nowrap" style={{ color: palette.ink }}>
        {title}
      </span>
      <Bar value={used} color={tint(palette, used)} track={palette.track} height={4} delay={delay} />
      <span className="text-right text-[11px] font-semibold tabular-nums" style={{ color: palette.ink, fontFamily: ROUNDED_FONT }}>
        <CountUp to={used} delay={delay} suffix="%" />
      </span>
    </>
  )
}

function Column({ title, used, reset, copy, delay }: { title: string; used: number; reset: string; copy: PhoneCopy; delay: number }) {
  return (
    <div className="flex flex-col gap-[5px]">
      <span className="text-[11px]" style={{ color: palette.ink2 }}>
        {title}
      </span>
      <span className="flex items-baseline gap-[3px]" style={{ fontFamily: ROUNDED_FONT }}>
        <span className="text-[22px] font-semibold tabular-nums" style={{ color: palette.ink }}>
          <CountUp to={used} delay={delay} suffix="%" />
        </span>
        <span className="text-[11px]" style={{ color: palette.ink2, fontFamily: 'inherit' }}>
          {copy.used}
        </span>
      </span>
      <Bar value={used} color={tint(palette, used)} track={palette.track} height={6} delay={delay} />
      <Reset text={fill(copy.resetsIn, reset)} />
    </div>
  )
}

function Reset({ text }: { text: string }) {
  return (
    <span className="flex items-center gap-[3px] text-[10px] font-medium whitespace-nowrap tabular-nums" style={{ color: palette.ink2 }}>
      <ResetGlyph />
      {text}
    </span>
  )
}
