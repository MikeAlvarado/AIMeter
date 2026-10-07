import homeWidgets from '../../assets/home-widgets.webp'
import widgetSmall from '../../assets/widget-small-dark.webp'
import widgetThree from '../../assets/widget-three-dark.webp'
import widgetTwoLight from '../../assets/widget-two-light.webp'
import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { GrainOverlay } from '../ui/GrainOverlay'
import { MixedHeading } from '../ui/MixedHeading'

export function Widgets() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>({ stagger: 120 })
  return (
    <section id="widgets" className="px-inset-sm nav:px-inset pb-24">
      <div ref={ref} className="rounded-shell night-gradient nav:p-14 relative mx-auto flex max-w-6xl flex-col gap-12 overflow-hidden p-7 text-ivory">
        <GrainOverlay className="opacity-[0.08]" />
        <div className="nav:flex-row nav:items-start relative flex flex-col gap-10">
          <div className="flex flex-1 flex-col gap-8">
            <div data-reveal className="flex flex-col gap-4">
              <MixedHeading text={t.widgets.heading} className="text-section text-ivory leading-[1.02]" />
              <p className="text-blush/80 max-w-md text-lg">{t.widgets.sub}</p>
            </div>
            <ul className="flex flex-col divide-y divide-white/10">
              {t.widgets.kinds.map((kind) => (
                <li key={kind.title} data-reveal className="flex flex-col gap-1 py-4">
                  <h3 className="text-lg font-medium">{kind.title}</h3>
                  <p className="text-blush/70 text-sm leading-relaxed">{kind.body}</p>
                </li>
              ))}
              <li data-reveal className="flex flex-col gap-1 py-4">
                <h3 className="text-lg font-medium">
                  {t.widgets.lockScreen} · {t.widgets.liveActivity}
                </h3>
                <p className="text-blush/70 text-sm leading-relaxed">{t.widgets.liveActivityBody}</p>
              </li>
            </ul>
            <div data-reveal className="flex flex-col gap-3">
              <img src={widgetThree} alt="" width={1059} height={537} loading="lazy" decoding="async" className="w-full max-w-[22rem] drop-shadow-[0_20px_40px_rgba(0,0,0,0.45)]" />
              <div className="flex items-end gap-3">
                <img src={widgetTwoLight} alt="" width={1059} height={537} loading="lazy" decoding="async" className="w-full max-w-[16rem] drop-shadow-[0_20px_40px_rgba(0,0,0,0.45)]" />
                <img src={widgetSmall} alt="" width={546} height={546} loading="lazy" decoding="async" className="w-[7.5rem] drop-shadow-[0_20px_40px_rgba(0,0,0,0.45)]" />
              </div>
            </div>
          </div>
          <div data-reveal className="nav:w-[22rem] mx-auto w-full max-w-[20rem] shrink-0">
            <img src={homeWidgets} alt={t.widgets.homeAlt} width={506} height={1100} loading="lazy" decoding="async" className="w-full rounded-[2rem] ring-1 ring-white/15" />
          </div>
        </div>
      </div>
    </section>
  )
}
