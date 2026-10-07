import { MotionConfig } from 'motion/react'
import { useEffect } from 'react'
import { BrowserRouter, Route, Routes, useLocation } from 'react-router-dom'
import { Nav } from './components/layout/Nav'
import { LanguageProvider } from './i18n/LanguageProvider'
import { Home } from './pages/Home'
import { NotFound } from './pages/NotFound'
import { PrivacyPage } from './pages/PrivacyPage'
import { SupportPage } from './pages/SupportPage'

function ScrollToTop() {
  const { pathname, hash } = useLocation()
  useEffect(() => {
    if (!hash) window.scrollTo({ top: 0, behavior: 'instant' })
  }, [pathname, hash])
  return null
}

function Site() {
  return (
    <>
      <ScrollToTop />
      <Nav />
      <Routes>
        <Route path="/" element={<Home />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/support" element={<SupportPage />} />
        <Route path="*" element={<NotFound />} />
      </Routes>
    </>
  )
}

export default function App() {
  return (
    <MotionConfig reducedMotion="user">
      <LanguageProvider>
        <BrowserRouter basename={import.meta.env.BASE_URL.replace(/\/$/, '')}>
          <Site />
        </BrowserRouter>
      </LanguageProvider>
    </MotionConfig>
  )
}
