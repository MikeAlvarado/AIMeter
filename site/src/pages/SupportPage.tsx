import { Mail } from 'lucide-react'
import { useLanguage } from '../hooks/useLanguage'
import { GITHUB_ISSUES_URL, SUPPORT_EMAIL } from '../lib/site'
import { GitHubLink } from '../components/ui/GitHubLink'
import { DocPage } from './DocPage'

export function SupportPage() {
  const { t } = useLanguage()
  const page = t.supportPage
  return (
    <DocPage page={page}>
      <section className="flex flex-col gap-4">
        <h2 className="font-display text-ink text-3xl leading-tight">{page.faqHeading}</h2>
        <div className="border-hairline flex flex-col divide-y divide-(--hairline) border-y">
          {page.faqs.map((faq) => (
            <details key={faq.q} className="group py-4">
              <summary className="text-ink flex cursor-pointer list-none items-start justify-between gap-4 font-medium [&::-webkit-details-marker]:hidden">
                {faq.q}
                <span aria-hidden className="text-ink-2 mt-0.5 shrink-0 transition-transform group-open:rotate-45">
                  +
                </span>
              </summary>
              <p className="text-ink/85 mt-3 leading-relaxed">{faq.a}</p>
            </details>
          ))}
        </div>
      </section>
      <section className="flex flex-col gap-4">
        <h2 className="font-display text-ink text-3xl leading-tight">{page.contactHeading}</h2>
        <p className="text-ink/85 leading-relaxed">{page.contact}</p>
        <div className="flex flex-wrap gap-3">
          <GitHubLink href={GITHUB_ISSUES_URL} className="text-ink">
            {page.issues}
          </GitHubLink>
          <a
            href={`mailto:${SUPPORT_EMAIL}?subject=AIMeter`}
            className="rounded-cta text-ink inline-flex h-12 items-center gap-2.5 border border-current/25 px-4 text-sm font-medium transition-colors hover:bg-current/10"
          >
            <Mail className="size-5" aria-hidden />
            {page.email}
          </a>
        </div>
      </section>
    </DocPage>
  )
}
