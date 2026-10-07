import { Link } from 'react-router-dom'
import { useDocumentMeta } from '../hooks/useDocumentMeta'
import { useLanguage } from '../hooks/useLanguage'

export function NotFound() {
  const { t } = useLanguage()
  useDocumentMeta(`${t.notFound.title} — AIMeter`, t.notFound.body)
  return (
    <main className="flex min-h-svh flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="font-display text-section text-ink">{t.notFound.title}</h1>
      <p className="text-ink-2">{t.notFound.body}</p>
      <Link to="/" className="rounded-cta bg-ink text-bg mt-2 px-4 py-2 text-sm font-medium">
        {t.notFound.cta}
      </Link>
    </main>
  )
}
