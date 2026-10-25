export const APP_STORE_ID = '6797946742'
export const APP_STORE_URL = `https://apps.apple.com/app/id${APP_STORE_ID}`
export const GITHUB_URL = 'https://github.com/MikeAlvarado/AIMeter'
export const GITHUB_ISSUES_URL = `${GITHUB_URL}/issues`
export const GITHUB_BUILD_URL = `${GITHUB_URL}#building`
/**
 * The Mac app's zip in the newest release. Every release attaches it under
 * this same name (`Scripts/release-mac.sh`), so the link never needs a bump.
 */
export const MAC_DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/AIMeter-macOS.zip`
export const AUTHOR_URL = 'https://mikealvaradol.web.app/'
export const SUPPORT_EMAIL = 'miguel_l06@hotmail.com'
export const CURRENT_VERSION = '4.2'

export const SECTION_IDS = ['features', 'mac', 'privacy', 'open-source'] as const
export type SectionId = (typeof SECTION_IDS)[number]

export const COPYRIGHT_YEAR = new Date().getFullYear()
