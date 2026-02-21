import QRCodeStyling, { type Options } from 'qr-code-styling'
import type { DesignOptions } from '@/types/qr'
import { estimateVersion } from './payload'

/** Converts the quiet-zone setting (modules) to canvas px for a given payload density.
 *  Solves: marginPx = quietModules × modulePx, where modulePx = (size − 2·marginPx) / modules. */
function quietZonePx(payload: string, d: DesignOptions, size: number): number {
  if (d.margin <= 0) return 0
  const bytes = new TextEncoder().encode(payload || ' ').length
  const modules = 17 + 4 * Math.min(estimateVersion(bytes, d.errorLevel), 40)
  return Math.round((d.margin * size) / (modules + 2 * d.margin))
}

export function buildQrOptions(payload: string, d: DesignOptions, displaySize: number): Partial<Options> {
  const dotsColor = d.gradient.enabled
    ? {
        gradient: {
          type: 'linear' as const,
          rotation: (d.gradient.rotation * Math.PI) / 180,
          colorStops: [
            { offset: 0, color: d.fgColor },
            { offset: 1, color: d.gradient.color2 },
          ],
        },
      }
    : { color: d.fgColor }
  return {
    width: displaySize,
    height: displaySize,
    type: 'canvas',
    data: payload || ' ',
    image: d.logoDataUrl ?? undefined,
    margin: quietZonePx(payload, d, displaySize),
    qrOptions: { errorCorrectionLevel: d.errorLevel },
    imageOptions: {
      crossOrigin: 'anonymous',
      margin: d.logoMargin,
      imageSize: d.logoSize,
      hideBackgroundDots: true,
    },
    dotsOptions: { ...dotsColor, type: d.dotType },
    cornersSquareOptions: { color: d.fgColor, type: d.cornerSquareType },
    cornersDotOptions: { color: d.fgColor, type: d.cornerDotType },
    backgroundOptions: {
      color: d.transparentBg ? 'rgba(0,0,0,0)' : d.bgColor,
    },
  }
}

/** Renders the standards-compliant square QR into an ImageBitmap at design.size. */
async function renderQrBitmap(payload: string, design: DesignOptions): Promise<ImageBitmap> {
  const opts = buildQrOptions(payload, { ...design, ctaEnabled: false }, design.size)
  const qr = new QRCodeStyling(opts as Options)
  const data = await qr.getRawData('png')
  if (!(data instanceof Blob)) throw new Error('QR render failed')
  return createImageBitmap(data)
}

function destinationLabel(payload: string): string {
  try {
    const u = new URL(payload)
    return u.hostname.replace(/^www\./, '')
  } catch {
    const t = payload.trim().split('\n')[0]
    return t.length > 42 ? `${t.slice(0, 42)}…` : t
  }
}

/** Wraps a rendered code canvas with a Context Band — CTA text + human-readable destination. */
function composeContextBand(
  code: HTMLCanvasElement,
  design: DesignOptions,
  payload: string,
): HTMLCanvasElement {
  const w = code.width
  const band = Math.round(w * 0.24)
  const canvas = document.createElement('canvas')
  canvas.width = w
  canvas.height = code.height + band
  const ctx = canvas.getContext('2d')!

  ctx.fillStyle = design.transparentBg ? '#ffffff' : design.bgColor
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.drawImage(code, 0, 0)

  // band
  ctx.fillStyle = design.fgColor
  ctx.fillRect(0, code.height, w, band)

  const fgOnBand = design.bgColor === design.fgColor ? '#ffffff' : design.bgColor
  const cta = (design.ctaText || 'Scan me').trim()
  ctx.textAlign = 'center'
  ctx.fillStyle = fgOnBand
  ctx.font = `700 ${Math.round(band * 0.34)}px system-ui, -apple-system, sans-serif`
  ctx.fillText(cta, w / 2, code.height + band * 0.48)

  const dest = destinationLabel(payload)
  if (dest) {
    ctx.globalAlpha = 0.75
    ctx.font = `400 ${Math.round(band * 0.2)}px ui-monospace, monospace`
    ctx.fillText(dest, w / 2, code.height + band * 0.8)
    ctx.globalAlpha = 1
  }
  return canvas
}

/** Full render pipeline: square QR → optional Context Band. */
export async function renderFinalCanvas(payload: string, design: DesignOptions): Promise<HTMLCanvasElement> {
  const bitmap = await renderQrBitmap(payload || ' ', design)
  const canvas = document.createElement('canvas')
  canvas.width = bitmap.width
  canvas.height = bitmap.height
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0)
  bitmap.close()
  if (design.ctaEnabled) return composeContextBand(canvas, design, payload)
  return canvas
}

export function canvasToBlob(canvas: HTMLCanvasElement, ext: 'png' | 'jpeg' | 'webp'): Promise<Blob | null> {
  const mime = ext === 'jpeg' ? 'image/jpeg' : ext === 'webp' ? 'image/webp' : 'image/png'
  return new Promise((resolve) => canvas.toBlob((b) => resolve(b), mime, 0.95))
}

/** SVG export — vector path, square code only (Context Band is a raster composition). */
export async function renderSvgBlob(payload: string, design: DesignOptions): Promise<Blob | null> {
  const qr = new QRCodeStyling(
    buildQrOptions(payload || ' ', { ...design, ctaEnabled: false }, design.size) as Options,
  )
  const data = await qr.getRawData('svg')
  if (data instanceof Blob) return data
  if (typeof data === 'string') return new Blob([data], { type: 'image/svg+xml' })
  // ArrayBuffer / BufferSource fallback
  return new Blob([data as BlobPart], { type: 'image/svg+xml' })
}
