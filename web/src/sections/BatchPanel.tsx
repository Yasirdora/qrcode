import { useRef, useState } from 'react'
import Papa from 'papaparse'
import JSZip from 'jszip'
import { saveAs } from 'file-saver'
import { renderFinalCanvas, renderSvgBlob, canvasToBlob } from '@/lib/render'
import { buildPayload } from '@/lib/payload'
import type { DesignOptions } from '@/types/qr'
import { DEFAULT_CONTENT } from '@/types/qr'
import { Button } from '@/components/ui/button'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Progress } from '@/components/ui/progress'
import { Upload, Package, Loader2 } from 'lucide-react'
import { toast } from 'sonner'

interface Props {
  design: DesignOptions
}

type BatchFormat = 'png' | 'svg'

export default function BatchPanel({ design }: Props) {
  const [raw, setRaw] = useState('')
  const [format, setFormat] = useState<BatchFormat>('png')
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState(0)
  const fileRef = useRef<HTMLInputElement>(null)

  const lines = raw
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)

  const onCsv = (file: File | undefined) => {
    if (!file) return
    Papa.parse<string[]>(file, {
      skipEmptyLines: true,
      complete: (res) => {
        // first column of every row is treated as the payload
        const values = res.data.map((row) => row[0]).filter(Boolean)
        setRaw((prev) => [prev, ...values].filter(Boolean).join('\n'))
        toast.success(`Imported ${values.length} rows from ${file.name}`)
      },
      error: () => toast.error('Could not parse that CSV file.'),
    })
  }

  const generate = async () => {
    if (lines.length === 0) {
      toast.error('Add at least one payload line first.')
      return
    }
    setBusy(true)
    setProgress(0)
    try {
      const zip = new JSZip()
      const usedNames = new Map<string, number>()
      for (let i = 0; i < lines.length; i++) {
        const value = lines[i]
        const payload = buildPayload({ ...DEFAULT_CONTENT, type: 'url', url: value })
        const blob =
          format === 'svg'
            ? await renderSvgBlob(payload, design)
            : await canvasToBlob(await renderFinalCanvas(payload, design), format)
        if (blob) {
          // derive a readable, unique filename from the payload
          let base =
            value
              .replace(/^https?:\/\//i, '')
              .replace(/[^a-z0-9-_]+/gi, '-')
              .replace(/^-+|-+$/g, '')
              .slice(0, 48) || `code-${i + 1}`
          const n = usedNames.get(base) ?? 0
          usedNames.set(base, n + 1)
          if (n > 0) base = `${base}-${n + 1}`
          zip.file(`${String(i + 1).padStart(3, '0')}-${base}.${format}`, blob)
        }
        setProgress(Math.round(((i + 1) / lines.length) * 100))
      }
      zip.file('manifest.txt', lines.map((l, i) => `${String(i + 1).padStart(3, '0')}\t${l}`).join('\n'))
      const out = await zip.generateAsync({ type: 'blob' })
      saveAs(out, `qrflow-batch-${lines.length}-codes.zip`)
      toast.success(`Generated ${lines.length} QR codes as ${format.toUpperCase()}.`)
    } catch (e) {
      console.error(e)
      toast.error('Batch generation failed — see console for details.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-border bg-muted/60 p-3 text-xs text-muted-foreground">
        Paste one URL or text payload per line — or import a CSV (first column is used). Every code
        is rendered locally with your current design settings and packaged into a single ZIP with a
        manifest. No upload, no per-code fees.
      </div>

      <div className="space-y-1.5">
        <div className="flex items-center justify-between">
          <Label className="text-xs text-muted-foreground">Payloads ({lines.length} detected)</Label>
          <Button variant="outline" size="sm" onClick={() => fileRef.current?.click()}>
            <Upload className="mr-1.5 h-3.5 w-3.5" /> Import CSV
          </Button>
          <input
            ref={fileRef}
            type="file"
            accept=".csv,text/csv"
            className="hidden"
            onChange={(e) => onCsv(e.target.files?.[0])}
          />
        </div>
        <Textarea
          value={raw}
          onChange={(e) => setRaw(e.target.value)}
          rows={8}
          placeholder={'https://example.com/product/1\nhttps://example.com/product/2\nWIFI voucher: GUEST-2026'}
          className="font-mono text-xs"
        />
      </div>

      <div className="flex items-end gap-3">
        <div className="space-y-1.5 w-40">
          <Label className="text-xs text-muted-foreground">Format</Label>
          <Select value={format} onValueChange={(v) => setFormat(v as BatchFormat)}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="png">PNG (raster)</SelectItem>
              <SelectItem value="svg">SVG (vector)</SelectItem>
            </SelectContent>
          </Select>
        </div>
        <Button onClick={generate} disabled={busy || lines.length === 0} className="flex-1">
          {busy ? (
            <>
              <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Generating… {progress}%
            </>
          ) : (
            <>
              <Package className="mr-2 h-4 w-4" /> Generate {lines.length || ''} codes → ZIP
            </>
          )}
        </Button>
      </div>
      {busy && <Progress value={progress} />}
    </div>
  )
}
