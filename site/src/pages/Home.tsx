import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'
import { Closing } from '../components/sections/Closing'
import { Features } from '../components/sections/Features'
import { Hero } from '../components/sections/Hero'
import { Mac } from '../components/sections/Mac'
import { OpenSource } from '../components/sections/OpenSource'
import { Privacy } from '../components/sections/Privacy'
import { Statement } from '../components/sections/Statement'
import { Widgets } from '../components/sections/Widgets'
import { useDocumentMeta } from '../hooks/useDocumentMeta'
import { useLanguage } from '../hooks/useLanguage'
import { scrollToSection } from '../lib/scroll'

export function Home() {
  const { t } = useLanguage()
  const { hash } = useLocation()
  useDocumentMeta(t.meta.title, t.meta.description)

  useEffect(() => {
    if (!hash) return
    const id = hash.slice(1)
    const frame = window.requestAnimationFrame(() => scrollToSection(id))
    return () => window.cancelAnimationFrame(frame)
  }, [hash])

  return (
    <main className="flex flex-col">
      <div className="sticky top-0 z-0">
        <Hero />
      </div>
      <div className="bg-bg relative z-10">
        <Statement />
        <Features />
        <Widgets />
        <Mac />
        <Privacy />
        <OpenSource />
        <Closing />
      </div>
    </main>
  )
}
