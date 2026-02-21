import type { ContentState } from '@/types/qr'
import { isValidBitcoinAddress } from './bitcoin'

function escapeWifi(s: string): string {
  return s.replace(/([\\;,:"'])/g, '\\$1')
}

function escapeVCard(s: string): string {
  return s.replace(/([\\;,])/g, '\\$1').replace(/\n/g, '\\n')
}

function toUtcStamp(datetimeLocal: string): string {
  if (!datetimeLocal) return ''
  const d = new Date(datetimeLocal)
  if (isNaN(d.getTime())) return ''
  return d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
}

/** Builds the raw string encoded into the QR symbol for each content type. */
export function buildPayload(c: ContentState): string {
  switch (c.type) {
    case 'url': {
      const u = c.url.trim()
      if (!u) return ''
      // accept any URI scheme (https:, mailto:, tel:, yourapp:…) — only add https when bare
      return /^[a-z][a-z0-9+.-]*:/i.test(u) ? u : `https://${u}`
    }
    case 'text':
      return c.text
    case 'wifi': {
      const { ssid, password, encryption, hidden } = c.wifi
      if (!ssid) return ''
      return `WIFI:T:${encryption};S:${escapeWifi(ssid)};P:${escapeWifi(password)};${hidden ? 'H:true;' : ''};`
    }
    case 'vcard': {
      const v = c.vcard
      if (!v.firstName && !v.lastName && !v.phone && !v.email) return ''
      const lines = [
        'BEGIN:VCARD',
        'VERSION:3.0',
        `N:${escapeVCard(v.lastName)};${escapeVCard(v.firstName)};;;`,
        `FN:${escapeVCard(`${v.firstName} ${v.lastName}`.trim())}`,
      ]
      if (v.org) lines.push(`ORG:${escapeVCard(v.org)}`)
      if (v.title) lines.push(`TITLE:${escapeVCard(v.title)}`)
      // Every value is escaped, not only the name fields: a phone extension or
      // a URL with a query string contains the separators that delimit vCard
      // fields, so an unescaped one truncates the record.
      if (v.phone) lines.push(`TEL;TYPE=CELL:${escapeVCard(v.phone)}`)
      if (v.email) lines.push(`EMAIL:${escapeVCard(v.email)}`)
      if (v.url) lines.push(`URL:${escapeVCard(v.url)}`)
      lines.push('END:VCARD')
      // vCard 3.0 mandates CRLF; strict parsers reject LF-only records.
      return lines.join('\r\n')
    }
    case 'sms': {
      if (!c.smsNumber) return ''
      return `sms:${c.smsNumber}${c.smsMessage ? `?body=${encodeURIComponent(c.smsMessage)}` : ''}`
    }
    case 'phone':
      return c.phoneNumber ? `tel:${c.phoneNumber}` : ''
    case 'geo': {
      if (!c.geoLat || !c.geoLng) return ''
      return `geo:${c.geoLat},${c.geoLng}`
    }
    case 'event': {
      const e = c.event
      if (!e.title || !e.start) return ''
      // Wrapped in VCALENDAR with a UID and a DTSTAMP: several calendar clients
      // refuse a bare VEVENT. Both values are derived from the event, because
      // the payload is rebuilt on every render and a random UID would change
      // the encoded code between two exports.
      const lines = [
        'BEGIN:VCALENDAR',
        'VERSION:2.0',
        'PRODID:-//Qr.Code//EN',
        'BEGIN:VEVENT',
        `UID:${e.start.replace(/\D/g, '')}-${e.title.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 24)}@qr.code`,
        `DTSTAMP:${toUtcStamp(e.start)}`,
        `SUMMARY:${escapeVCard(e.title)}`,
        `DTSTART:${toUtcStamp(e.start)}`,
      ]
      if (e.end) lines.push(`DTEND:${toUtcStamp(e.end)}`)
      if (e.location) lines.push(`LOCATION:${escapeVCard(e.location)}`)
      if (e.description) lines.push(`DESCRIPTION:${escapeVCard(e.description)}`)
      lines.push('END:VEVENT')
      lines.push('END:VCALENDAR')
      // iCalendar requires CRLF as well.
      return lines.join('\r\n')
    }
    case 'crypto': {
      const address = c.cryptoAddress.trim()
      // A mistyped address is not recoverable, and the code is printed before
      // anyone can check it. Refuse to encode an address whose checksum does
      // not verify; an empty payload shows the "add content" state instead of
      // a code that sends funds nowhere.
      if (!isValidBitcoinAddress(address)) return ''
      return `bitcoin:${address}${c.cryptoAmount ? `?amount=${c.cryptoAmount}` : ''}`
    }
    case 'whatsapp': {
      const digits = c.whatsappNumber.replace(/[^\d]/g, '')
      if (!digits) return ''
      return `https://wa.me/${digits}${c.whatsappMessage ? `?text=${encodeURIComponent(c.whatsappMessage)}` : ''}`
    }
    case 'custom':
      return c.customText
  }
}

/** Human-friendly one-liner for a code's content — used in preview chips and history,
 *  never the raw payload (mailto:/WIFI:/BEGIN:VCARD strings are ugly and meaningless). */
export function summarizeContent(c: ContentState): string {
  switch (c.type) {
    case 'url': {
      try {
        return new URL(buildPayload(c)).hostname.replace(/^www\./, '') || 'Link'
      } catch {
        return c.url.trim() || 'Link'
      }
    }
    case 'text': {
      const t = c.text.trim().split('\n')[0]
      return t ? (t.length > 40 ? `${t.slice(0, 40)}…` : t) : 'Plain text'
    }
    case 'wifi':
      return c.wifi.ssid ? `Wi-Fi · ${c.wifi.ssid}` : 'Wi-Fi network'
    case 'vcard': {
      const name = `${c.vcard.firstName} ${c.vcard.lastName}`.trim()
      return name ? `Contact · ${name}` : 'Contact card'
    }
    case 'sms':
      return c.smsNumber ? `SMS · ${c.smsNumber}` : 'Text message'
    case 'phone':
      return c.phoneNumber ? `Call · ${c.phoneNumber}` : 'Phone call'
    case 'geo':
      return c.geoLat && c.geoLng ? `Location · ${c.geoLat}, ${c.geoLng}` : 'Location'
    case 'event':
      return c.event.title ? `Event · ${c.event.title}` : 'Calendar event'
    case 'crypto':
      return c.cryptoAddress
        ? `Bitcoin · …${c.cryptoAddress.slice(-8)}`
        : 'Bitcoin payment'
    case 'whatsapp':
      return c.whatsappNumber ? `WhatsApp · ${c.whatsappNumber}` : 'WhatsApp chat'
    case 'custom': {
      const t = c.customText.trim().split('\n')[0]
      return t ? `Custom · ${t.length > 30 ? `${t.slice(0, 30)}…` : t}` : 'Custom payload'
    }
  }
}

/** Rough byte-mode capacity (chars) per error-correction level, version 40 upper bound used for scoring. */
export const EC_CAPACITY_V40: Record<string, number> = { L: 2953, M: 2331, Q: 1663, H: 1273 }

/** Approximate smallest QR version (1-40) needed for a byte payload at a given EC level.
 *  Capacity grows ~quadratically; this piecewise model is accurate enough for UX scoring. */
export function estimateVersion(bytes: number, ec: string): number {
  if (bytes <= 0) return 1
  // capacity table sampled from ISO/IEC 18004 byte mode (versions 1,2,4,6,10,14,20,26,32,40)
  const samples: [number, Record<string, number>][] = [
    [1, { L: 17, M: 14, Q: 11, H: 7 }],
    [2, { L: 32, M: 26, Q: 20, H: 14 }],
    [4, { L: 78, M: 62, Q: 46, H: 34 }],
    [6, { L: 136, M: 108, Q: 80, H: 60 }],
    [10, { L: 271, M: 213, Q: 151, H: 119 }],
    [14, { L: 440, M: 348, Q: 251, H: 198 }],
    [20, { L: 861, M: 669, Q: 482, H: 367 }],
    [26, { L: 1274, M: 1000, Q: 711, H: 548 }],
    [32, { L: 1953, M: 1525, Q: 1086, H: 831 }],
    [40, { L: 2953, M: 2331, Q: 1663, H: 1273 }],
  ]
  for (const [v, caps] of samples) {
    if (bytes <= (caps[ec] ?? caps.M)) return v
  }
  return 41 // overflow
}
