/** The app's own colors (`Shared/Theme.swift`), for the screens drawn on the page. */
export const APP = {
  light: {
    background: '#FAF9F5',
    card: '#FFFFFF',
    track: '#EDEAE1',
    ink: '#1F1E1D',
    ink2: '#87867F',
    accent: '#D97757',
    warning: '#DDA712',
    danger: '#D70015',
  },
  dark: {
    background: '#262624',
    card: '#30302E',
    track: '#3E3D3A',
    ink: '#FAF9F5',
    ink2: '#9B9A93',
    accent: '#E08B6D',
    warning: '#F0BF3A',
    danger: '#FF3B30',
  },
} as const

export type Scheme = keyof typeof APP
export type Palette = (typeof APP)[Scheme]

/** The bars' color rule (`UsageLevel`): yellow above 70 % used, red above 85 %. */
export function tint(palette: Palette, used: number): string {
  if (used > 85) return palette.danger
  if (used > 70) return palette.warning
  return palette.accent
}

/** The phone's own font: the system's, as in the app. */
export const SYSTEM_FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Helvetica Neue", sans-serif'

/** The screen's size in points, an iPhone's, which every screen is laid out at. */
export const SCREEN = { width: 390, height: 844 }
