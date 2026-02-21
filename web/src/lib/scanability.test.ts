import { describe, expect, it } from 'vitest'
import { DEFAULT_DESIGN } from '@/types/qr'
import type { DesignOptions } from '@/types/qr'
import { contrastRatio, scoreScanability } from './scanability'
import type { ScanCheck, ScanReport } from './scanability'

const design = (): DesignOptions => structuredClone(DEFAULT_DESIGN)

function check(report: ScanReport, id: string): ScanCheck {
  const found = report.checks.find((c) => c.id === id)
  if (!found) throw new Error(`no check with id ${id}`)
  return found
}

describe('contrastRatio', () => {
  it('is 21:1 for black on white, and 1:1 for a colour against itself', () => {
    expect(contrastRatio('#000000', '#ffffff')).toBeCloseTo(21, 5)
    expect(contrastRatio('#3366ff', '#3366ff')).toBeCloseTo(1, 5)
  })
})

describe('scoreScanability', () => {
  it('grades the default design and a short payload as Excellent', () => {
    const report = scoreScanability('https://example.com', design())
    expect(report.score).toBeGreaterThanOrEqual(90)
    expect(report.grade).toBe('Excellent')
  })

  it('fails the contrast check for pale modules on white', () => {
    const d = design()
    d.fgColor = '#dddddd'
    d.bgColor = '#ffffff'
    expect(check(scoreScanability('https://example.com', d), 'contrast').status).toBe('fail')
  })

  it('flags a dense payload', () => {
    const d = design()
    d.errorLevel = 'H'
    expect(check(scoreScanability('x'.repeat(900), d), 'density').status).not.toBe('pass')
  })

  it('fails an oversized logo on the weakest error correction', () => {
    const d = design()
    d.logoDataUrl = 'data:image/png;base64,AAAA'
    d.logoSize = 0.5
    d.errorLevel = 'L'
    expect(check(scoreScanability('https://example.com', d), 'logo').status).toBe('fail')
  })

  it('warns on a quiet zone below the ISO minimum and on a transparent background', () => {
    const tight = design()
    tight.margin = 2
    expect(check(scoreScanability('https://example.com', tight), 'quiet').status).toBe('warn')

    const transparent = design()
    transparent.transparentBg = true
    expect(check(scoreScanability('https://example.com', transparent), 'bg').status).toBe('warn')
  })
})
