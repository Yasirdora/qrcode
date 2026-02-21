import { describe, expect, it } from 'vitest'
import { DEFAULT_CONTENT } from '@/types/qr'
import type { ContentState } from '@/types/qr'
import { buildPayload, estimateVersion, summarizeContent } from './payload'

/** A mutable copy of the defaults, so a test states only what it changes. */
const content = (): ContentState => structuredClone(DEFAULT_CONTENT)

describe('buildPayload', () => {
  it('escapes the reserved characters in Wi-Fi credentials', () => {
    const c = content()
    c.type = 'wifi'
    c.wifi.ssid = 'My;Home'
    c.wifi.password = 'p:a\\ss'
    c.wifi.encryption = 'WPA'
    c.wifi.hidden = false
    expect(buildPayload(c)).toBe('WIFI:T:WPA;S:My\\;Home;P:p\\:a\\\\ss;;')
  })

  it('adds a scheme only when the URL has none', () => {
    const c = content()
    c.type = 'url'
    c.url = 'example.com'
    expect(buildPayload(c)).toBe('https://example.com')
    c.url = 'mailto:a@b.com'
    expect(buildPayload(c)).toBe('mailto:a@b.com')
    c.url = 'yourapp://deep/link'
    expect(buildPayload(c)).toBe('yourapp://deep/link')
  })

  it('reduces a WhatsApp number to digits and encodes the message', () => {
    const c = content()
    c.type = 'whatsapp'
    c.whatsappNumber = '+1 (555) 123-4567'
    c.whatsappMessage = 'Hi there'
    expect(buildPayload(c)).toBe('https://wa.me/15551234567?text=Hi%20there')
  })

  it('writes vCard 3.0 with CRLF and escapes every value', () => {
    const c = content()
    c.type = 'vcard'
    c.vcard.firstName = 'Ada'
    c.vcard.lastName = 'Lovelace'
    c.vcard.phone = '+49;123'
    const payload = buildPayload(c)
    expect(payload).toContain('TEL;TYPE=CELL:+49\\;123')
    expect(payload).toContain('\r\n')
    expect(payload.replace(/\r\n/g, '')).not.toContain('\n')
  })

  it('wraps a calendar event in VCALENDAR and stays deterministic', () => {
    const c = content()
    c.type = 'event'
    c.event.title = 'Launch party'
    c.event.start = '2027-01-15T10:00'
    const payload = buildPayload(c)
    for (const expected of [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'BEGIN:VEVENT',
      'UID:',
      'DTSTAMP:',
      'SUMMARY:Launch party',
      'DTSTART:',
      'END:VEVENT',
      'END:VCALENDAR',
    ]) {
      expect(payload, expected).toContain(expected)
    }
    expect(payload).toContain('\r\n')
    // The payload is rebuilt on every render, so a generated UID would change
    // the encoded code between two exports.
    expect(buildPayload(c)).toBe(payload)
  })

  it('refuses a Bitcoin address that fails its checksum', () => {
    const c = content()
    c.type = 'crypto'
    c.cryptoAddress = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa'
    expect(buildPayload(c)).toBe('bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa')
    // One character changed: the address is no longer recoverable once printed.
    c.cryptoAddress = '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb'
    expect(buildPayload(c)).toBe('')
  })
})

describe('estimateVersion', () => {
  it('stays inside the ISO capacity bounds', () => {
    expect(estimateVersion(0, 'H')).toBe(1)
    expect(estimateVersion(10, 'H')).toBe(2)
    expect(estimateVersion(5000, 'L')).toBe(41)
  })
})

describe('summarizeContent', () => {
  it('never exposes a Wi-Fi password', () => {
    const c = content()
    c.type = 'wifi'
    c.wifi.ssid = 'CafeNet'
    c.wifi.password = 'hunter2'
    const summary = summarizeContent(c)
    expect(summary).toContain('CafeNet')
    expect(summary).not.toContain('hunter2')
  })
})
