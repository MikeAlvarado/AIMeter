import dashboard from '../../assets/dashboard.webp'
import dashboardDark from '../../assets/dashboard-dark.webp'
import detailSmart from '../../assets/detail-smart.webp'
import detailTop from '../../assets/detail-top.webp'
import detailWeek from '../../assets/detail-week30.webp'
import homeWidgets from '../../assets/home-widgets.webp'
import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import type { Feature } from '../../i18n/types'
import { MixedHeading } from '../ui/MixedHeading'
import { PhoneFrame } from '../ui/PhoneFrame'

const IMAGES: Record<string, string> = {
  limits: dashboard,
  widgets: homeWidgets,
  history: detailWeek,
  alerts: detailSmart,
  pace: detailTop,
  accounts: dashboardDark,
}

function FeatureRow({ feature, index }: { feature: Feature; index: number }) {
  const ref = useRevealOnScroll<HTMLLIElement>()
  const image = IMAGES[feature.id] ?? dashboard
  return (
    <li ref={ref} className="flex flex-col">
      <div className="bg-hairline h-px w-full" />
      <div className="tab:flex-row tab:gap-10 tab:py-14 flex flex-col gap-8 py-10">
        <div data-reveal className="tab:basis-[36%] flex flex-col gap-2">
          <span className="text-ink-2 text-sm tabular">({String(index + 1).padStart(2, '0')})</span>
          <h3 className="text-ink tab:text-4xl text-2xl leading-tight tracking-tight">{feature.title}</h3>
        </div>
        <div className="tab:flex-row tab:gap-10 flex flex-1 flex-col gap-8">
          <div data-reveal className="flex flex-1 flex-col gap-5">
            <p className="text-ink/80 text-base leading-relaxed">{feature.body}</p>
            <ul className="text-ink-2 flex flex-col gap-2 text-sm">
              {feature.points.map((point) => (
                <li key={point} className="flex gap-2.5">
                  <span aria-hidden className="bg-accent mt-[0.55em] size-1.5 shrink-0 rounded-full" />
                  {point}
                </li>
              ))}
            </ul>
          </div>
          <div data-reveal className="tab:w-[13rem] shrink-0 self-center">
            <PhoneFrame src={image} alt={feature.imageAlt} className="w-[12rem]" />
          </div>
        </div>
      </div>
    </li>
  )
}

export function Features() {
  const { t } = useLanguage()
  const headingRef = useRevealOnScroll<HTMLDivElement>()
  return (
    <section id="features" className="px-inset-sm nav:px-inset nav:py-32 py-24">
      <div ref={headingRef} className="mx-auto mb-14 flex max-w-2xl flex-col items-center gap-4 text-center">
        <MixedHeading data-reveal text={t.features.heading} className="text-section leading-[1.02]" />
        <p data-reveal className="text-ink-2 max-w-md text-lg">
          {t.features.sub}
        </p>
      </div>
      <ul aria-label={t.features.listLabel} className="mx-auto flex max-w-6xl flex-col">
        {t.features.items.map((feature, index) => (
          <FeatureRow key={feature.id} feature={feature} index={index} />
        ))}
        <li aria-hidden className="bg-hairline h-px w-full" />
      </ul>
    </section>
  )
}
