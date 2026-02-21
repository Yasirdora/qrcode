import type { ContentState, ContentType } from '@/types/qr'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Link2,
  Type,
  Wifi,
  Contact,
  MessageSquare,
  Phone,
  MapPin,
  CalendarDays,
  Bitcoin,
  MessageCircle,
  Braces,
} from 'lucide-react'

const TYPES: { id: ContentType; label: string; icon: typeof Link2 }[] = [
  { id: 'url', label: 'URL', icon: Link2 },
  { id: 'text', label: 'Text', icon: Type },
  { id: 'wifi', label: 'Wi-Fi', icon: Wifi },
  { id: 'vcard', label: 'vCard', icon: Contact },
  { id: 'sms', label: 'SMS', icon: MessageSquare },
  { id: 'phone', label: 'Phone', icon: Phone },
  { id: 'geo', label: 'Geo', icon: MapPin },
  { id: 'event', label: 'Event', icon: CalendarDays },
  { id: 'crypto', label: 'Crypto', icon: Bitcoin },
  { id: 'whatsapp', label: 'WhatsApp', icon: MessageCircle },
  { id: 'custom', label: 'Custom', icon: Braces },
]

interface Props {
  content: ContentState
  onChange: (c: ContentState) => void
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs text-muted-foreground">{label}</Label>
      {children}
    </div>
  )
}

export default function ContentPanel({ content, onChange }: Props) {
  const set = <K extends keyof ContentState>(key: K, value: ContentState[K]) =>
    onChange({ ...content, [key]: value })

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-4 gap-1.5 sm:grid-cols-6">
        {TYPES.map(({ id, label, icon: Icon }) => (
          <button
            key={id}
            onClick={() => set('type', id)}
            className={`flex flex-col items-center gap-1 rounded-lg border px-1 py-2.5 text-[11px] font-medium transition-colors ${
              content.type === id
                ? 'border-foreground bg-foreground text-background'
                : 'border-border bg-background text-muted-foreground hover:border-foreground/40 hover:text-foreground'
            }`}
          >
            <Icon className="h-4 w-4" />
            {label}
          </button>
        ))}
      </div>

      {content.type === 'url' && (
        <Field label="Destination URL">
          <Input
            value={content.url}
            onChange={(e) => set('url', e.target.value)}
            placeholder="https://your-site.com"
          />
        </Field>
      )}

      {content.type === 'text' && (
        <Field label="Plain text">
          <Textarea
            value={content.text}
            onChange={(e) => set('text', e.target.value)}
            placeholder="Any text — serial numbers, coupons, notes…"
            rows={4}
          />
        </Field>
      )}

      {content.type === 'wifi' && (
        <div className="space-y-3">
          <Field label="Network name (SSID)">
            <Input
              value={content.wifi.ssid}
              onChange={(e) => set('wifi', { ...content.wifi, ssid: e.target.value })}
              placeholder="MyHomeWifi"
            />
          </Field>
          <Field label="Password">
            <Input
              value={content.wifi.password}
              onChange={(e) => set('wifi', { ...content.wifi, password: e.target.value })}
            />
          </Field>
          <div className="flex items-center gap-4">
            <div className="flex-1">
              <Field label="Security">
                <Select
                  value={content.wifi.encryption}
                  onValueChange={(v) =>
                    set('wifi', { ...content.wifi, encryption: v as 'WPA' | 'WEP' | 'nopass' })
                  }
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="WPA">WPA / WPA2 / WPA3</SelectItem>
                    <SelectItem value="WEP">WEP</SelectItem>
                    <SelectItem value="nopass">Open</SelectItem>
                  </SelectContent>
                </Select>
              </Field>
            </div>
            <div className="flex items-center gap-2 pt-5">
              <Switch
                checked={content.wifi.hidden}
                onCheckedChange={(v) => set('wifi', { ...content.wifi, hidden: v })}
              />
              <Label className="text-xs">Hidden</Label>
            </div>
          </div>
        </div>
      )}

      {content.type === 'vcard' && (
        <div className="grid grid-cols-2 gap-3">
          <Field label="First name">
            <Input
              value={content.vcard.firstName}
              onChange={(e) => set('vcard', { ...content.vcard, firstName: e.target.value })}
            />
          </Field>
          <Field label="Last name">
            <Input
              value={content.vcard.lastName}
              onChange={(e) => set('vcard', { ...content.vcard, lastName: e.target.value })}
            />
          </Field>
          <Field label="Phone">
            <Input
              value={content.vcard.phone}
              onChange={(e) => set('vcard', { ...content.vcard, phone: e.target.value })}
            />
          </Field>
          <Field label="Email">
            <Input
              value={content.vcard.email}
              onChange={(e) => set('vcard', { ...content.vcard, email: e.target.value })}
            />
          </Field>
          <Field label="Company">
            <Input
              value={content.vcard.org}
              onChange={(e) => set('vcard', { ...content.vcard, org: e.target.value })}
            />
          </Field>
          <Field label="Job title">
            <Input
              value={content.vcard.title}
              onChange={(e) => set('vcard', { ...content.vcard, title: e.target.value })}
            />
          </Field>
          <div className="col-span-2">
            <Field label="Website">
              <Input
                value={content.vcard.url}
                onChange={(e) => set('vcard', { ...content.vcard, url: e.target.value })}
              />
            </Field>
          </div>
        </div>
      )}

      {content.type === 'sms' && (
        <div className="space-y-3">
          <Field label="Phone number">
            <Input value={content.smsNumber} onChange={(e) => set('smsNumber', e.target.value)} placeholder="+1 555 123 4567" />
          </Field>
          <Field label="Message">
            <Textarea value={content.smsMessage} onChange={(e) => set('smsMessage', e.target.value)} rows={3} />
          </Field>
        </div>
      )}

      {content.type === 'phone' && (
        <Field label="Phone number">
          <Input value={content.phoneNumber} onChange={(e) => set('phoneNumber', e.target.value)} placeholder="+1 555 123 4567" />
        </Field>
      )}

      {content.type === 'geo' && (
        <div className="grid grid-cols-2 gap-3">
          <Field label="Latitude">
            <Input value={content.geoLat} onChange={(e) => set('geoLat', e.target.value)} placeholder="37.7749" />
          </Field>
          <Field label="Longitude">
            <Input value={content.geoLng} onChange={(e) => set('geoLng', e.target.value)} placeholder="-122.4194" />
          </Field>
        </div>
      )}

      {content.type === 'event' && (
        <div className="space-y-3">
          <Field label="Event title">
            <Input value={content.event.title} onChange={(e) => set('event', { ...content.event, title: e.target.value })} />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Starts">
              <Input type="datetime-local" value={content.event.start} onChange={(e) => set('event', { ...content.event, start: e.target.value })} />
            </Field>
            <Field label="Ends">
              <Input type="datetime-local" value={content.event.end} onChange={(e) => set('event', { ...content.event, end: e.target.value })} />
            </Field>
          </div>
          <Field label="Location">
            <Input value={content.event.location} onChange={(e) => set('event', { ...content.event, location: e.target.value })} />
          </Field>
        </div>
      )}

      {content.type === 'crypto' && (
        <div className="space-y-3">
          <Field label="Bitcoin address">
            <Input value={content.cryptoAddress} onChange={(e) => set('cryptoAddress', e.target.value)} placeholder="bc1q…" />
          </Field>
          <Field label="Amount (BTC, optional)">
            <Input value={content.cryptoAmount} onChange={(e) => set('cryptoAmount', e.target.value)} placeholder="0.001" />
          </Field>
        </div>
      )}

      {content.type === 'whatsapp' && (
        <div className="space-y-3">
          <Field label="Phone number (with country code)">
            <Input value={content.whatsappNumber} onChange={(e) => set('whatsappNumber', e.target.value)} placeholder="+1 555 123 4567" />
          </Field>
          <Field label="Pre-filled message (optional)">
            <Textarea value={content.whatsappMessage} onChange={(e) => set('whatsappMessage', e.target.value)} rows={3} placeholder="Hi! I scanned your code…" />
          </Field>
        </div>
      )}

      {content.type === 'custom' && (
        <div className="space-y-3">
          <Field label="Raw payload — full control">
            <Textarea
              value={content.customText}
              onChange={(e) => set('customText', e.target.value)}
              rows={5}
              className="font-mono text-xs"
              placeholder={'Any QR payload, e.g.\nBCD\\n002\\n1\\nSCT  (SEPA EPC credit transfer)\nor yourapp://deep/link'}
            />
          </Field>
          <p className="text-[11px] text-muted-foreground">
            Power-user mode: the exact string encoded, byte for byte. SEPA/EPC bank transfers, app
            deep links, proprietary schemes — if a scanner understands it, you can encode it.
          </p>
        </div>
      )}
    </div>
  )
}
