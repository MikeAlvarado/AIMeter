import { useLanguage } from '../../hooks/useLanguage'
import { useRevealOnScroll } from '../../hooks/useRevealOnScroll'
import { GitHubLink } from '../ui/GitHubLink'
import { MixedHeading } from '../ui/MixedHeading'

export function OpenSource() {
  const { t } = useLanguage()
  const ref = useRevealOnScroll<HTMLDivElement>()
  return (
    <section id="open-source" className="px-inset-sm nav:px-inset pb-24">
      <div ref={ref} className="border-hairline mx-auto flex max-w-6xl flex-col gap-12 border-t pt-16">
        <div className="nav:flex-row nav:items-end nav:justify-between flex flex-col gap-6">
          <div data-reveal className="flex max-w-2xl flex-col gap-4">
            <MixedHeading text={t.openSource.heading} className="text-section leading-[1.02]" />
            <p className="text-ink-2 max-w-lg text-lg">{t.openSource.sub}</p>
          </div>
          <div data-reveal>
            <GitHubLink className="text-ink">{t.openSource.github}</GitHubLink>
          </div>
        </div>
        <ul className="tab:flex-row flex flex-col gap-8">
          {t.openSource.points.map((point) => (
            <li key={point.title} data-reveal className="flex flex-1 flex-col gap-2">
              <h3 className="text-ink text-lg font-medium">{point.title}</h3>
              <p className="text-ink-2 text-sm leading-relaxed">{point.body}</p>
            </li>
          ))}
        </ul>
        <p data-reveal className="text-ink-2 text-sm">
          <span className="text-ink font-medium">{t.openSource.languagesLabel}:</span> {t.openSource.languages}.
        </p>
      </div>
    </section>
  )
}
