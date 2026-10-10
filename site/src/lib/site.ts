export const APP_STORE_ID = '6797946742'
export const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}`
export const GITHUB_URL = 'https://github.com/MikeAlvarado/AIMeter'
export const GITHUB_ISSUES_URL = `${GITHUB_URL}/issues`
export const GITHUB_BUILD_URL = `${GITHUB_URL}#building`
export const AUTHOR_URL = 'https://mikealvaradol.web.app/'
export const SUPPORT_EMAIL = 'miguel_l06@hotmail.com'
export const CURRENT_VERSION = '2.0'

export const SECTION_IDS = ['features', 'widgets', 'privacy', 'open-source'] as const
export type SectionId = (typeof SECTION_IDS)[number]

export const COPYRIGHT_YEAR = new Date().getFullYear()
