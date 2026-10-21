import type { CSSProperties } from 'react'

/** The app's own colors (`Shared/Theme.swift`), for the screens drawn on the page. */
export const APP = {
  light: {
    background: '#FAF9F5',
    backgroundTop: '#FCFBF8',
    backgroundBottom: '#F3F1EA',
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
    backgroundTop: '#2A2927',
    backgroundBottom: '#1F1E1C',
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

/**
 * The app's backdrop (`AppBackground`, 4.0): its ivory or charcoal eased a
 * shade lighter at the top and deeper at the bottom, with a terracotta
 * warmth past the top-right corner, never a visible spot.
 */
export function backdrop(palette: Palette): string {
  return `radial-gradient(75% 45% at 80% -5%, ${palette.accent}12 0%, transparent 100%), linear-gradient(180deg, ${palette.backgroundTop} 0%, ${palette.background} 50%, ${palette.backgroundBottom} 100%)`
}

/** Every usage figure's face: SF Rounded, as `Theme.figure` draws it. */
export const ROUNDED_FONT = 'ui-rounded, "SF Pro Rounded", -apple-system, BlinkMacSystemFont, system-ui, sans-serif'

/** A card's surface (`cardSurface`): 24 pt corners, a light along the top edge, one soft shadow. */
export function surface(palette: Palette): CSSProperties {
  const dark = palette.background === '#262624'
  return {
    background: palette.card,
    boxShadow: dark
      ? 'inset 0 1px 0 rgba(255,255,255,0.09), 0 0 0 0.5px rgba(255,255,255,0.05), 0 10px 26px rgba(0,0,0,0.28)'
      : 'inset 0 1px 0 rgba(255,255,255,0.95), 0 0 0 0.5px rgba(31,30,29,0.05), 0 10px 26px rgba(0,0,0,0.06)',
  }
}
