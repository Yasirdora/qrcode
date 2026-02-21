export type ContentType =
  | 'url'
  | 'text'
  | 'wifi'
  | 'vcard'
  | 'sms'
  | 'phone'
  | 'geo'
  | 'event'
  | 'crypto'
  | 'whatsapp'
  | 'custom'

export type DotType = 'square' | 'rounded' | 'dots' | 'classy' | 'classy-rounded' | 'extra-rounded'
export type CornerSquareType = 'square' | 'dot' | 'extra-rounded'
export type CornerDotType = 'square' | 'dot'
export type ErrorLevel = 'L' | 'M' | 'Q' | 'H'

export interface GradientOptions {
  enabled: boolean
  color2: string
  rotation: number
}

export interface DesignOptions {
  fgColor: string
  bgColor: string
  transparentBg: boolean
  gradient: GradientOptions
  dotType: DotType
  cornerSquareType: CornerSquareType
  cornerDotType: CornerDotType
  errorLevel: ErrorLevel
  size: number
  /** Quiet zone in modules — ISO/IEC 18004 requires ≥ 4. Converted to px at render time
   *  based on the estimated symbol density. */
  margin: number
  logoDataUrl: string | null
  logoSize: number // 0.1 - 0.5 fraction of code area
  logoMargin: number
  ctaEnabled: boolean
  ctaText: string
}

export interface WifiFields {
  ssid: string
  password: string
  encryption: 'WPA' | 'WEP' | 'nopass'
  hidden: boolean
}

export interface VCardFields {
  firstName: string
  lastName: string
  org: string
  title: string
  phone: string
  email: string
  url: string
}

export interface EventFields {
  title: string
  location: string
  start: string // datetime-local
  end: string
  description: string
}

export interface ContentState {
  type: ContentType
  url: string
  text: string
  wifi: WifiFields
  vcard: VCardFields
  smsNumber: string
  smsMessage: string
  phoneNumber: string
  geoLat: string
  geoLng: string
  event: EventFields
  cryptoAddress: string
  cryptoAmount: string
  whatsappNumber: string
  whatsappMessage: string
  customText: string
}

export interface HistoryEntry {
  id: string
  createdAt: number
  content: ContentState
  design: DesignOptions
}

export const DEFAULT_CONTENT: ContentState = {
  type: 'url',
  url: 'https://github.com',
  text: '',
  wifi: { ssid: '', password: '', encryption: 'WPA', hidden: false },
  vcard: { firstName: '', lastName: '', org: '', title: '', phone: '', email: '', url: '' },
  smsNumber: '',
  smsMessage: '',
  phoneNumber: '',
  geoLat: '',
  geoLng: '',
  event: { title: '', location: '', start: '', end: '', description: '' },
  cryptoAddress: '',
  cryptoAmount: '',
  whatsappNumber: '',
  whatsappMessage: '',
  customText: '',
}

export const DEFAULT_DESIGN: DesignOptions = {
  fgColor: '#111827',
  bgColor: '#ffffff',
  transparentBg: false,
  gradient: { enabled: false, color2: '#7c3aed', rotation: 45 },
  dotType: 'rounded',
  cornerSquareType: 'extra-rounded',
  cornerDotType: 'dot',
  errorLevel: 'Q',
  size: 1024,
  margin: 4,
  logoDataUrl: null,
  logoSize: 0.28,
  logoMargin: 6,
  ctaEnabled: false,
  ctaText: 'Scan me',
}

export interface DesignPreset {
  name: string
  design: Partial<DesignOptions>
}

export const PRESETS: DesignPreset[] = [
  {
    name: 'Classic',
    design: {
      fgColor: '#111827', bgColor: '#ffffff', transparentBg: false,
      gradient: { enabled: false, color2: '#7c3aed', rotation: 45 },
      dotType: 'square', cornerSquareType: 'square', cornerDotType: 'square', errorLevel: 'Q',
    },
  },
  {
    name: 'Midnight',
    design: {
      fgColor: '#a5b4fc', bgColor: '#0f172a', transparentBg: false,
      gradient: { enabled: true, color2: '#22d3ee', rotation: 45 },
      dotType: 'rounded', cornerSquareType: 'extra-rounded', cornerDotType: 'dot', errorLevel: 'Q',
    },
  },
  {
    name: 'Ember',
    design: {
      fgColor: '#b45309', bgColor: '#fffbeb', transparentBg: false,
      gradient: { enabled: true, color2: '#dc2626', rotation: 30 },
      dotType: 'classy-rounded', cornerSquareType: 'extra-rounded', cornerDotType: 'dot', errorLevel: 'Q',
    },
  },
  {
    name: 'Forest',
    design: {
      fgColor: '#065f46', bgColor: '#ecfdf5', transparentBg: false,
      gradient: { enabled: false, color2: '#10b981', rotation: 45 },
      dotType: 'dots', cornerSquareType: 'dot', cornerDotType: 'dot', errorLevel: 'Q',
    },
  },
  {
    name: 'Mono Ink',
    design: {
      fgColor: '#18181b', bgColor: '#ffffff', transparentBg: true,
      gradient: { enabled: false, color2: '#7c3aed', rotation: 45 },
      dotType: 'extra-rounded', cornerSquareType: 'extra-rounded', cornerDotType: 'dot', errorLevel: 'H',
    },
  },
  {
    name: 'Candy',
    design: {
      fgColor: '#db2777', bgColor: '#fdf2f8', transparentBg: false,
      gradient: { enabled: true, color2: '#8b5cf6', rotation: 60 },
      dotType: 'dots', cornerSquareType: 'extra-rounded', cornerDotType: 'dot', errorLevel: 'H',
    },
  },
]
