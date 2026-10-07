export const NAV_OFFSET = 96

export function scrollToSection(id: string) {
  const element = document.getElementById(id)
  if (!element) return
  const top = element.getBoundingClientRect().top + window.scrollY - NAV_OFFSET
  window.scrollTo({ top, behavior: 'smooth' })
}
