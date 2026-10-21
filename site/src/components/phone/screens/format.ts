/** Fills `{key}` placeholders in a dictionary string: `{t}` alone, or by name. */
export function fill(template: string, value: string | Record<string, string>): string {
  if (typeof value === 'string') return template.replace(/\{\w+\}/, value)
  return template.replace(/\{(\w+)\}/g, (match, key: string) => value[key] ?? match)
}

/** A countdown the way the app writes it: "2h 58m", "45m". */
export function duration(minutes: number): string {
  const hours = Math.floor(minutes / 60)
  const rest = minutes % 60
  return hours > 0 ? `${hours}h ${rest}m` : `${rest}m`
}

/** A live widget countdown the way WidgetKit writes it: "2:57:00", "45:00". */
export function clock(minutes: number): string {
  const hours = Math.floor(minutes / 60)
  const rest = String(minutes % 60).padStart(2, '0')
  return hours > 0 ? `${hours}:${rest}:00` : `${rest}:00`
}
