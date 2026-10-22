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

/** The app's own words for the screens drawn on the page, as its string catalog has them. */
export interface PhoneCopy {
  personal: string
  work: string
  plan: string
  session: string
  weekly: string
  weeklyTopModel: string
  credits: string
  /** `{t}`: a countdown such as "2h 58m". */
  resetsIn: string
  updatedNow: string
  /** `{n}`: minutes. */
  updatedMinutes: string
  onPace: string
  ahead: string
  behind: string
  rateLimits: string
  history: string
  forecast: string
  windowPills: [string, string, string]
  ranges: [string, string, string]
  /** The history chart's x labels, one list per range. */
  chartLabels: [string[], string[], string[]]
  runsOutEarly: string
  forecastNote: string
  historyNote: string
  used: string
  usedCap: string
  week: string
  topModel: string
  /** `{w}`: the window's name. */
  nearing: string
  /** `{n}`: the percentage. */
  nearingBody: string
  refilled: string
  refilledBody: string
  now: string
  date: string
}

export interface DemoScene {
  /** The scene's tab under the MacBook. */
  pill: string
  /** What the recording shows, its label for assistive tech. */
  title: string
}

export interface Faq {
  q: string
  a: string
}

export interface Dictionary {
  meta: { title: string; description: string }
  nav: {
    features: string
    mac: string
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
    /** The Mac badge: the full label (VoiceOver) and its small first line. */
    macDownload: string
    macDownloadSmall: string
    platforms: string
    version: string
    phoneAlt: string
  }
  /** The notch island at work under the hero (`NotchDemo`): one entry per recorded scene, in its order. */
  demo: {
    label: string
    scenes: [DemoScene, DemoScene, DemoScene]
  }
  features: {
    heading: string
    sub: string
    listLabel: string
    /** On a phone the features are cards swiped under the iPhone, with dots to jump between them (`FeatureCarousel`). */
    carousel: {
      /** What assistive tech calls the cards' region (`aria-roledescription`). */
      role: string
      /** What it calls one card. */
      slide: string
      /** A card's place: `{n}` of `{total}`. */
      position: string
      /** The dots' label. */
      dots: string
      /** The arrows' labels, either side of the dots with a mouse or on a tablet (never on a phone). */
      previous: string
      next: string
    }
    items: Feature[]
  }
  phone: PhoneCopy
  mac: {
    heading: string
    sub: string
    styles: string[]
    extras: string[]
    note: string
    /** The Mac download link: the latest GitHub Release. */
    download: string
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
