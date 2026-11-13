/** Mirrors the main process encoder so images and audio load through the custom scheme. */
export function assetUrl(base: string | undefined, ref: string | null | undefined): string | null {
  if (!base || !ref) return null
  return `${base}${ref.split('/').map(encodeURIComponent).join('/')}`
}
