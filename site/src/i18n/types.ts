export type Locale = 'en' | 'es'

export interface Feature {
  id: string
  title: string
  body: string
  points: string[]
  imageAlt: string
}

export interface DocSection {
  heading: string
  paragraphs: string[]
  bullets?: string[]
}

export interface DocPage {
  title: string
  description: string
  intro: string
  updated: string
  sections: DocSection[]
}

export interface Faq {
  q: string
  a: string
}

export interface Dictionary {
  meta: { title: string; description: string }
  nav: {
    features: string
    widgets: string
    privacy: string
    openSource: string
    support: string
    cta: string
    openMenu: string
    closeMenu: string
    langLabel: string
    navLabel: string
    home: string
  }
  hero: {
    pills: [string, string, string]
    line1: string
    line2: string
    sub: string
    appStore: string
    appStoreSmall: string
    github: string
    scroll: string
    platforms: string
    version: string
    phoneAlt: string
    widgetAlt: string
  }
  statement: string
  features: { heading: string; sub: string; listLabel: string; items: Feature[] }
  widgets: {
    heading: string
    sub: string
    kinds: { title: string; body: string }[]
    homeAlt: string
    lockScreen: string
    liveActivity: string
    liveActivityBody: string
    ipadAlt: string
  }
  mac: {
    heading: string
    sub: string
    styles: string[]
    extras: string[]
    note: string
    build: string
  }
  privacy: { heading: string; sub: string; points: { title: string; body: string }[]; cta: string }
  openSource: {
    heading: string
    sub: string
    points: { title: string; body: string }[]
    languagesLabel: string
    languages: string
    github: string
  }
  closing: {
    eyebrow: string
    heading: string
    appStore: string
    github: string
    rights: string
    trademark: string
    madeBy: string
    links: { privacy: string; support: string; source: string }
  }
  privacyPage: DocPage
  supportPage: DocPage & { faqHeading: string; faqs: Faq[]; contactHeading: string; contact: string; email: string; issues: string }
  notFound: { title: string; body: string; cta: string }
  backHome: string
}
