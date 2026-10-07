import { Link } from 'react-router-dom'
import { useLanguage } from '../../hooks/useLanguage'
import { AUTHOR_URL, COPYRIGHT_YEAR, GITHUB_URL } from '../../lib/site'

export function Footer() {
  const { t } = useLanguage()
  const links = [
    { key: 'privacy', label: t.closing.links.privacy, to: '/privacy' },
    { key: 'support', label: t.closing.links.support, to: '/support' },
  ]
  return (
    <footer className="nav:px-10 nav:pb-8 relative px-7 pb-7 text-sm">
      <div className="mb-6 h-px w-full bg-white/15" />
      <p className="text-blush/60 mx-auto mb-6 max-w-2xl text-center text-xs leading-relaxed">{t.closing.trademark}</p>
      <div className="mb-6 h-px w-full bg-white/10" />
      <div className="text-blush/80 nav:flex-row nav:justify-between flex flex-col-reverse items-center gap-3">
        <p>
          © {COPYRIGHT_YEAR}{' '}
          <a href={AUTHOR_URL} target="_blank" rel="noreferrer" className="hover:text-ivory underline-offset-4 hover:underline">
            Mike Alvarado
          </a>
          . {t.closing.rights}
        </p>
        <ul className="flex items-center gap-6">
          {links.map((link) => (
            <li key={link.key}>
              <Link to={link.to} className="text-blush/70 hover:text-ivory transition-colors">
                {link.label}
              </Link>
            </li>
          ))}
          <li>
            <a href={GITHUB_URL} target="_blank" rel="noreferrer" className="text-blush/70 hover:text-ivory transition-colors">
              {t.closing.links.source}
            </a>
          </li>
        </ul>
      </div>
    </footer>
  )
}
