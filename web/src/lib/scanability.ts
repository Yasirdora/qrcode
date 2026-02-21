import type { DesignOptions } from '@/types/qr'
import { estimateVersion } from './payload'

export interface ScanCheck {
  id: string
  label: string
  status: 'pass' | 'warn' | 'fail'
  detail: string
  weight: number
}

export interface ScanReport {
  score: number // 0-100
  grade: 'Excellent' | 'Good' | 'Risky' | 'Likely unscannable'
  checks: ScanCheck[]
}

function hexToRgb(hex: string): [number, number, number] {
  const h = hex.replace('#', '')
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

function luminance([r, g, b]: [number, number, number]): number {
  const f = (c: number) => {
    const s = c / 255
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
  }
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}

export function contrastRatio(fg: string, bg: string): number {
  const l1 = luminance(hexToRgb(fg))
  const l2 = luminance(hexToRgb(bg))
  const [hi, lo] = l1 >= l2 ? [l1, l2] : [l2, l1]
  return (hi + 0.05) / (lo + 0.05)
}

export function scoreScanability(payload: string, d: DesignOptions): ScanReport {
  const checks: ScanCheck[] = []
  const bytes = new TextEncoder().encode(payload).length

  // 1. Contrast — the #1 cause of unscannable styled codes
  const bg = d.transparentBg ? '#ffffff' : d.bgColor
  const ratio = contrastRatio(d.fgColor, bg)
  checks.push({
    id: 'contrast',
    label: 'Foreground / background contrast',
    status: ratio >= 4 ? 'pass' : ratio >= 2.5 ? 'warn' : 'fail',
    detail:
      ratio >= 4
        ? `Contrast ratio ${ratio.toFixed(1)}:1 — scans fast in all lighting.`
        : ratio >= 2.5
          ? `Contrast ratio ${ratio.toFixed(1)}:1 — marginal. Darken the modules for reliable scanning.`
          : `Contrast ratio ${ratio.toFixed(1)}:1 — most cameras will fail. Make modules darker than background.`,
    weight: 35,
  })

  // 2. Payload density — dense symbols need print size and steady hands
  const version = estimateVersion(bytes, d.errorLevel)
  const modules = version <= 40 ? 17 + version * 4 : 177
  checks.push({
    id: 'density',
    label: 'Symbol density',
    status: version <= 6 ? 'pass' : version <= 20 ? 'warn' : 'fail',
    detail:
      version <= 6
        ? `~Version ${version} (${modules}×${modules} modules). Crisp even at small print sizes.`
        : version <= 20
          ? `~Version ${version} (${modules}×${modules} modules). Shorten the payload or print larger (≥ 3 cm).`
          : version <= 40
            ? `~Version ${version} (${modules}×${modules} modules). Very dense — reduce payload size.`
            : `Payload exceeds QR capacity at EC level ${d.errorLevel}. Shorten it or lower error correction.`,
    weight: 25,
  })

  // 3. Logo occlusion vs error correction
  if (d.logoDataUrl) {
    const occlusion = d.logoSize * d.logoSize
    const ecAllowance: Record<string, number> = { L: 0.07, M: 0.15, Q: 0.25, H: 0.30 }
    const allowance = ecAllowance[d.errorLevel]
    checks.push({
      id: 'logo',
      label: 'Logo occlusion vs error correction',
      status: occlusion <= allowance * 0.7 ? 'pass' : occlusion <= allowance ? 'warn' : 'fail',
      detail:
        occlusion <= allowance
          ? `Logo covers ~${Math.round(occlusion * 100)}% of the symbol; EC ${d.errorLevel} tolerates ~${Math.round(allowance * 100)}%.`
          : `Logo covers ~${Math.round(occlusion * 100)}% but EC ${d.errorLevel} only recovers ~${Math.round(allowance * 100)}%. Shrink the logo or raise EC to H.`,
      weight: 20,
    })
  } else {
    checks.push({
      id: 'logo',
      label: 'Logo occlusion',
      status: 'pass',
      detail: 'No logo embedded — full symbol area is machine-readable.',
      weight: 20,
    })
  }

  // 4. Quiet zone (margin) — d.margin is in modules; ISO/IEC 18004 requires ≥ 4
  const quietModules = d.margin
  checks.push({
    id: 'quiet',
    label: 'Quiet zone',
    status: quietModules >= 4 ? 'pass' : quietModules >= 2 ? 'warn' : 'fail',
    detail:
      quietModules >= 4
        ? `${quietModules}-module quiet zone — meets the ISO 4-module minimum.`
        : `${quietModules}-module quiet zone — ISO requires 4. Raise it in Design settings to avoid edge clipping.`,
    weight: 12,
  })

  // 5. Transparent background
  checks.push({
    id: 'bg',
    label: 'Background',
    status: d.transparentBg ? 'warn' : 'pass',
    detail: d.transparentBg
      ? 'Transparent PNG/SVG: the final surface must stay light and uniform behind the code.'
      : 'Solid background ships inside the file — safe on any surface.',
    weight: 8,
  })

  const statusScore = { pass: 1, warn: 0.5, fail: 0 }
  const totalWeight = checks.reduce((s, c) => s + c.weight, 0)
  const score = Math.round(
    (checks.reduce((s, c) => s + statusScore[c.status] * c.weight, 0) / totalWeight) * 100,
  )
  const grade =
    score >= 90 ? 'Excellent' : score >= 70 ? 'Good' : score >= 45 ? 'Risky' : 'Likely unscannable'

  return { score, grade, checks }
}
