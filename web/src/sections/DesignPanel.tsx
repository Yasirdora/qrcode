import { useRef } from 'react'
import type { DesignOptions, DotType, CornerSquareType, CornerDotType, ErrorLevel } from '@/types/qr'
import { PRESETS } from '@/types/qr'
import { Label } from '@/components/ui/label'
import { Slider } from '@/components/ui/slider'
import { Switch } from '@/components/ui/switch'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Upload, X } from 'lucide-react'

interface Props {
  design: DesignOptions
  onChange: (d: DesignOptions) => void
}

const DOT_TYPES: { id: DotType; label: string }[] = [
  { id: 'square', label: 'Square' },
  { id: 'rounded', label: 'Rounded' },
  { id: 'extra-rounded', label: 'Smooth' },
  { id: 'dots', label: 'Dots' },
  { id: 'classy', label: 'Classy' },
  { id: 'classy-rounded', label: 'Leaf' },
]

function ColorInput({
  label,
  value,
  onChange,
}: {
  label: string
  value: string
  onChange: (v: string) => void
}) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs text-muted-foreground">{label}</Label>
      <div className="flex items-center gap-2">
        <input
          type="color"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="h-9 w-12 cursor-pointer rounded-md border border-border bg-transparent p-0.5"
        />
        <code className="text-xs text-muted-foreground">{value}</code>
      </div>
    </div>
  )
}

export default function DesignPanel({ design, onChange }: Props) {
  const fileRef = useRef<HTMLInputElement>(null)
  const set = <K extends keyof DesignOptions>(key: K, value: DesignOptions[K]) =>
    onChange({ ...design, [key]: value })

  const onLogoFile = (file: File | undefined) => {
    if (!file) return
    const reader = new FileReader()
    reader.onload = () => set('logoDataUrl', reader.result as string)
    reader.readAsDataURL(file)
  }

  return (
    <div className="space-y-5">
      <div>
        <Label className="text-xs text-muted-foreground">Presets</Label>
        <div className="mt-1.5 flex flex-wrap gap-1.5">
          {PRESETS.map((p) => (
            <button
              key={p.name}
              onClick={() => onChange({ ...design, ...p.design, logoDataUrl: design.logoDataUrl })}
              className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground transition-colors hover:border-foreground/50 hover:text-foreground"
            >
              {p.name}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <ColorInput label="Module color" value={design.fgColor} onChange={(v) => set('fgColor', v)} />
        <ColorInput label="Background" value={design.bgColor} onChange={(v) => set('bgColor', v)} />
      </div>

      <div className="flex items-center justify-between">
        <Label className="text-xs">Gradient modules</Label>
        <Switch
          checked={design.gradient.enabled}
          onCheckedChange={(v) => set('gradient', { ...design.gradient, enabled: v })}
        />
      </div>
      {design.gradient.enabled && (
        <div className="grid grid-cols-2 items-end gap-4">
          <ColorInput
            label="Gradient end"
            value={design.gradient.color2}
            onChange={(v) => set('gradient', { ...design.gradient, color2: v })}
          />
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">
              Angle {design.gradient.rotation}°
            </Label>
            <Slider
              value={[design.gradient.rotation]}
              min={0}
              max={360}
              step={5}
              onValueChange={([v]) => set('gradient', { ...design.gradient, rotation: v })}
            />
          </div>
        </div>
      )}

      <div>
        <Label className="text-xs text-muted-foreground">Module style</Label>
        <div className="mt-1.5 grid grid-cols-3 gap-1.5">
          {DOT_TYPES.map((t) => (
            <button
              key={t.id}
              onClick={() => set('dotType', t.id)}
              className={`rounded-lg border px-2 py-1.5 text-xs transition-colors ${
                design.dotType === t.id
                  ? 'border-foreground bg-foreground text-background'
                  : 'border-border text-muted-foreground hover:text-foreground'
              }`}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-1.5">
          <Label className="text-xs text-muted-foreground">Corner frame</Label>
          <Select
            value={design.cornerSquareType}
            onValueChange={(v) => set('cornerSquareType', v as CornerSquareType)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="square">Square</SelectItem>
              <SelectItem value="extra-rounded">Rounded</SelectItem>
              <SelectItem value="dot">Circle</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs text-muted-foreground">Corner dot</Label>
          <Select
            value={design.cornerDotType}
            onValueChange={(v) => set('cornerDotType', v as CornerDotType)}
          >
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="square">Square</SelectItem>
              <SelectItem value="dot">Circle</SelectItem>
            </SelectContent>
          </Select>
        </div>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs text-muted-foreground">Error correction</Label>
        <Select value={design.errorLevel} onValueChange={(v) => set('errorLevel', v as ErrorLevel)}>
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="L">L — 7% recovery</SelectItem>
            <SelectItem value="M">M — 15% recovery</SelectItem>
            <SelectItem value="Q">Q — 25% recovery</SelectItem>
            <SelectItem value="H">H — 30% recovery (best with logos)</SelectItem>
          </SelectContent>
        </Select>
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs text-muted-foreground">Export size — {design.size}px</Label>
        <Slider
          value={[design.size]}
          min={256}
          max={4096}
          step={128}
          onValueChange={([v]) => set('size', v)}
        />
      </div>

      <div className="space-y-1.5">
        <Label className="text-xs text-muted-foreground">
          Quiet zone — {design.margin} modules {design.margin < 4 && '⚠ ISO minimum is 4'}
        </Label>
        <Slider
          value={[design.margin]}
          min={0}
          max={10}
          step={1}
          onValueChange={([v]) => set('margin', v)}
        />
      </div>

      <div className="space-y-2 rounded-lg border border-border p-3">
        <div className="flex items-center justify-between">
          <div>
            <Label className="text-xs">Context Band</Label>
            <p className="text-[10px] text-muted-foreground">
              A printed strip under the code: your call-to-action + the destination, so people know
              what they're scanning before they scan it.
            </p>
          </div>
          <Switch checked={design.ctaEnabled} onCheckedChange={(v) => set('ctaEnabled', v)} />
        </div>
        {design.ctaEnabled && (
          <input
            value={design.ctaText}
            onChange={(e) => set('ctaText', e.target.value)}
            maxLength={28}
            placeholder="Scan to view menu"
            className="w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm"
          />
        )}
      </div>

      <div className="flex items-center justify-between">
        <Label className="text-xs">Transparent background</Label>
        <Switch checked={design.transparentBg} onCheckedChange={(v) => set('transparentBg', v)} />
      </div>

      <div className="space-y-2">
        <Label className="text-xs text-muted-foreground">Center logo</Label>
        {design.logoDataUrl ? (
          <div className="flex items-center gap-3">
            <img src={design.logoDataUrl} alt="logo" className="h-12 w-12 rounded-md border border-border object-contain" />
            <Button variant="outline" size="sm" onClick={() => set('logoDataUrl', null)}>
              <X className="mr-1 h-3 w-3" /> Remove
            </Button>
          </div>
        ) : (
          <Button variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
            <Upload className="mr-1.5 h-3.5 w-3.5" /> Upload logo
          </Button>
        )}
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => onLogoFile(e.target.files?.[0])}
        />
        {design.logoDataUrl && (
          <>
            <div className="space-y-1.5 pt-2">
              <Label className="text-xs text-muted-foreground">
                Logo scale — {Math.round(design.logoSize * 100)}%
              </Label>
              <Slider
                value={[design.logoSize * 100]}
                min={10}
                max={50}
                step={1}
                onValueChange={([v]) => set('logoSize', v / 100)}
              />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Logo padding — {design.logoMargin}px</Label>
              <Slider
                value={[design.logoMargin]}
                min={0}
                max={24}
                step={1}
                onValueChange={([v]) => set('logoMargin', v)}
              />
            </div>
          </>
        )}
      </div>
    </div>
  )
}
