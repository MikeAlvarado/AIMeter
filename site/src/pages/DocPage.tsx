import { ArrowLeft } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useDocumentMeta } from '../hooks/useDocumentMeta'
import { useLanguage } from '../hooks/useLanguage'
import type { DocPage as DocPageData } from '../i18n/types'
import { AUTHOR_URL, COPYRIGHT_YEAR, GITHUB_URL } from '../lib/site'

export function DocPage({ page, children }: { page: DocPageData; children?: ReactNode }) {
  const { t } = useLanguage()
  useDocumentMeta(`${page.title} — AIMeter`, page.description)
  return (
    <main className="px-inset-sm nav:px-inset nav:pt-40 flex flex-col pt-32 pb-16">
      <article className="mx-auto flex w-full max-w-2xl flex-col gap-10">
        <header className="flex flex-col gap-4">
          <Link to="/" className="text-ink-2 hover:text-ink inline-flex items-center gap-1 self-start text-sm transition-colors">
            <ArrowLeft className="size-4" aria-hidden />
            {t.backHome}
          </Link>
          <h1 className="font-display text-section text-ink leading-[1.02]">{page.title}</h1>
          <p className="text-ink-2 text-sm">{page.updated}</p>
          <p className="text-ink/85 text-lg leading-relaxed">{page.intro}</p>
        </header>
        {page.sections.map((section) => (
          <section key={section.heading} className="flex flex-col gap-3">
            <h2 className="font-display text-ink text-3xl leading-tight">{section.heading}</h2>
            {section.paragraphs.map((paragraph) => (
              <p key={paragraph} className="text-ink/85 leading-relaxed">
                {paragraph}
              </p>
            ))}
            {section.bullets && (
              <ul className="text-ink/85 flex flex-col gap-2.5 leading-relaxed">
                {section.bullets.map((bullet) => (
                  <li key={bullet} className="flex gap-2.5">
                    <span aria-hidden className="bg-accent mt-[0.65em] size-1.5 shrink-0 rounded-full" />
                    <span>{bullet}</span>
                  </li>
                ))}
              </ul>
            )}
          </section>
        ))}
        {children}
        <footer className="border-hairline text-ink-2 flex flex-col gap-3 border-t pt-8 text-sm">
          <p>{t.closing.trademark}</p>
          <p>
            © {COPYRIGHT_YEAR}{' '}
            <a href={AUTHOR_URL} target="_blank" rel="noreferrer" className="hover:text-ink underline-offset-4 hover:underline">
              Mike Alvarado
            </a>
            . {t.closing.rights}{' '}
            <a href={GITHUB_URL} target="_blank" rel="noreferrer" className="hover:text-ink underline-offset-4 hover:underline">
              {t.closing.links.source}
            </a>
            {' · '}
            <Link to="/privacy" className="hover:text-ink underline-offset-4 hover:underline">
              {t.closing.links.privacy}
            </Link>
            {' · '}
            <Link to="/support" className="hover:text-ink underline-offset-4 hover:underline">
              {t.closing.links.support}
            </Link>
          </p>
        </footer>
      </article>
    </main>
  )
}
