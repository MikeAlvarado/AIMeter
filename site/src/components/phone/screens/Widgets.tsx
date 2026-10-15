import type { ReactNode } from 'react'
import type { PhoneCopy } from '../../../i18n/types'
import { Bar, CountUp, ResetGlyph, SparkleGlyph, BriefcaseGlyph } from '../parts'
import { useTicker } from '../useTicker'
import { APP, tint } from '../theme'
import { duration, fill } from './format'

const palette = APP.dark
const WIDGET = '#2A2826'

/**
 * The Home Screen with the three widget kinds, as the store's capture
 * shows them: the single figure, the account's windows in rows and in
 * columns, and every account at once. The session keeps running here too.
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
        <Widget className="h-[158px]">
          <Header icon="sparkle" name={copy.personal} trailing={copy.windowPills[0]} />
          <span className="mt-[6px] text-[32px] font-bold tabular-nums" style={{ color: palette.ink }}>
            <CountUp to={session} suffix="%" />
          </span>
          <span className="text-[12px]" style={{ color: palette.ink2 }}>
            {copy.usedCap}
          </span>
          <div className="mt-auto flex flex-col gap-[6px]">
            <Bar value={session} color={tint(palette, session)} track={palette.track} height={5} />
            <Reset text={fill(copy.resetsIn, duration(177 - step))} />
          </div>
        </Widget>
        <Widget className="h-[158px] gap-[5px]">
          <Header icon="briefcase" name={copy.work} />
          <MiniRow title={copy.windowPills[0]} used={73} delay={0.1} />
          <MiniRow title={copy.week} used={28} delay={0.18} />
          <MiniRow title={copy.credits} used={31} delay={0.26} />
        </Widget>
      </div>
      <Widget className="mt-[22px] h-[158px]">
        <Header icon="sparkle" name={copy.personal} plan={copy.plan} />
        <div className="mt-3 grid flex-1 grid-cols-3 gap-4">
          <Column title={copy.windowPills[0]} used={session} reset={duration(177 - step)} copy={copy} delay={0.05} />
          <Column title={copy.week} used={61} reset="3d 2h" copy={copy} delay={0.13} />
          <Column title={copy.topModel} used={18} reset="3d 2h" copy={copy} delay={0.21} />
        </div>
      </Widget>
      <Widget className="mt-[22px] gap-[7px]">
        <Header icon="sparkle" name={copy.personal} plan={copy.plan} />
        <MiniRow title={copy.windowPills[0]} used={session} delay={0.3} />
        <MiniRow title={copy.week} used={61} delay={0.36} />
        <MiniRow title={copy.topModel} used={18} delay={0.42} />
        <div className="mt-1">
          <Header icon="briefcase" name={copy.work} plan={copy.plan} />
        </div>
        <MiniRow title={copy.windowPills[0]} used={73} delay={0.48} />
        <MiniRow title={copy.week} used={28} delay={0.54} />
      </Widget>
    </div>
  )
}

function Widget({ children, className = '' }: { children: ReactNode; className?: string }) {
  return (
    <div className={`flex flex-col rounded-[22px] p-[14px] ${className}`} style={{ background: WIDGET, boxShadow: '0 10px 30px rgba(0,0,0,0.35)' }}>
      {children}
    </div>
  )
}

function Header({ icon, name, plan, trailing }: { icon: 'sparkle' | 'briefcase'; name: string; plan?: string; trailing?: string }) {
  return (
    <div className="flex items-center gap-[6px]">
      <span className="grid size-[18px] place-items-center rounded-[5px]" style={{ background: `${palette.accent}2E`, color: palette.accent }}>
        {icon === 'sparkle' ? <SparkleGlyph size={10} /> : <BriefcaseGlyph size={10} />}
      </span>
      <span className="text-[13px] font-semibold" style={{ color: palette.ink }}>
        {name}
      </span>
      {plan && (
        <span className="rounded-full px-[6px] text-[10px] font-medium" style={{ background: palette.track, color: palette.ink2 }}>
          {plan}
        </span>
      )}
      {trailing && (
        <span className="ml-auto text-[11px]" style={{ color: palette.ink2 }}>
          {trailing}
        </span>
      )}
    </div>
  )
}

function MiniRow({ title, used, delay }: { title: string; used: number; delay: number }) {
  return (
    <div className="flex flex-col gap-[3px]">
      <div className="flex items-center text-[11px]">
        <span className="flex-1" style={{ color: palette.ink2 }}>
          {title}
        </span>
        <span className="font-semibold tabular-nums" style={{ color: palette.ink }}>
          <CountUp to={used} delay={delay} suffix="%" />
        </span>
      </div>
      <Bar value={used} color={tint(palette, used)} track={palette.track} height={4} delay={delay} />
    </div>
  )
}

function Column({ title, used, reset, copy, delay }: { title: string; used: number; reset: string; copy: PhoneCopy; delay: number }) {
  return (
    <div className="flex flex-col gap-[5px]">
      <span className="text-[11px]" style={{ color: palette.ink2 }}>
        {title}
      </span>
      <span className="text-[22px] font-bold tabular-nums" style={{ color: palette.ink }}>
        <CountUp to={used} delay={delay} suffix="%" />
        <span className="ml-1 text-[11px] font-normal" style={{ color: palette.ink2 }}>
          {copy.used}
        </span>
      </span>
      <Bar value={used} color={tint(palette, used)} track={palette.track} height={4} delay={delay} />
      <Reset text={fill(copy.resetsIn, reset)} />
    </div>
  )
}

function Reset({ text }: { text: string }) {
  return (
    <span className="flex items-center gap-[3px] text-[10px]" style={{ color: palette.ink2 }}>
      <ResetGlyph />
      {text}
    </span>
  )
}
