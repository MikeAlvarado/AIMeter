import { useEffect, useRef, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useLanguage } from '../../hooks/useLanguage'
import { useScrolledPast } from '../../hooks/useScrolledPast'
import { cn } from '../../lib/cn'
import { scrollToSection } from '../../lib/scroll'
import { APP_STORE_URL, SECTION_IDS } from '../../lib/site'
import { LanguageToggle } from './LanguageToggle'
import { MobileMenu, type NavLink } from './MobileMenu'

export function Nav() {
  const { t } = useLanguage()
  const scrolled = useScrolledPast()
  const location = useLocation()
  const navigate = useNavigate()
  const [menuOpen, setMenuOpen] = useState(false)
  const navRef = useRef<HTMLElement | null>(null)
  const onHome = location.pathname === '/'

  useEffect(() => {
    if (!menuOpen) return
    const onPointerDown = (event: PointerEvent) => {
      if (event.target instanceof Node && !navRef.current?.contains(event.target)) setMenuOpen(false)
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [menuOpen])

  const labels: Record<(typeof SECTION_IDS)[number], string> = {
    features: t.nav.features,
    widgets: t.nav.widgets,
    privacy: t.nav.privacy,
    'open-source': t.nav.openSource,
  }
  const links: NavLink[] = [
    ...SECTION_IDS.map((id) => ({ id, label: labels[id], href: `/#${id}` })),
    { id: 'support', label: t.nav.support, href: '/support' },
  ]

  const go = (link: NavLink) => {
    setMenuOpen(false)
    if (link.id === 'support') {
      void navigate('/support')
      return
    }
    if (onHome) {
      scrollToSection(link.id)
    } else {
      void navigate(`/#${link.id}`)
    }
  }

  return (
    <header className="inset-x-inset-sm nav:inset-x-inset nav:top-6 fixed top-4 z-50">
      <nav
        ref={navRef}
        aria-label={t.nav.navLabel}
        className={cn(
          'rounded-nav nav:px-6 border-hairline mx-auto flex w-full flex-col border px-4 py-2.5 backdrop-blur-xl transition-[max-width,background-color] duration-500 ease-out',
          scrolled || !onHome ? 'max-w-[62.5rem]' : 'max-w-[120rem]',
          menuOpen ? 'bg-bg/90' : scrolled || !onHome ? 'bg-bg/70' : 'bg-bg/40',
        )}
      >
        <div className="flex items-center">
          <div className="flex flex-1 items-center">
            <Link to="/" aria-label={t.nav.home} onClick={() => setMenuOpen(false)} className="font-display text-ink text-2xl">
              AIMeter<span className="text-accent">.</span>
            </Link>
          </div>
          <ul className="nav:flex hidden items-center gap-8">
            {links.map((link) => (
              <li key={link.id}>
                <a
                  href={link.href}
                  onClick={(event) => {
                    event.preventDefault()
                    go(link)
                  }}
                  className="text-ink/70 hover:text-ink text-sm transition-colors"
                >
                  {link.label}
                </a>
              </li>
            ))}
          </ul>
          <div className="flex flex-1 items-center justify-end gap-3">
            <LanguageToggle className="nav:flex hidden" />
            <a
              href={APP_STORE_URL}
              target="_blank"
              rel="noreferrer"
              className="rounded-cta bg-ink text-bg nav:inline-flex hidden px-4 py-2 text-sm font-medium transition-transform hover:scale-[1.03]"
            >
              {t.nav.cta}
            </a>
            <button
              type="button"
              aria-label={menuOpen ? t.nav.closeMenu : t.nav.openMenu}
              aria-expanded={menuOpen}
              aria-controls="mobile-menu"
              onClick={() => setMenuOpen((wasOpen) => !wasOpen)}
              className="nav:hidden text-ink border-hairline flex size-9 items-center justify-center rounded-full border"
            >
              <svg aria-hidden viewBox="0 0 20 20" className="size-5" fill="currentColor">
                <circle cx="10" cy="4.5" r="1.6" />
                <circle cx="15.5" cy="10" r="1.6" />
                <circle cx="10" cy="15.5" r="1.6" />
                <circle cx="4.5" cy="10" r="1.6" />
              </svg>
            </button>
          </div>
        </div>
        <MobileMenu open={menuOpen} onClose={() => setMenuOpen(false)} onNavigate={go} links={links} />
      </nav>
    </header>
  )
}
