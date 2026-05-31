import { useEffect, useMemo, useState } from 'react'
import type { ContentState, DesignOptions, HistoryEntry } from '@/types/qr'
import { DEFAULT_CONTENT, DEFAULT_DESIGN } from '@/types/qr'
import { buildPayload, summarizeContent } from '@/lib/payload'
import { scoreScanability } from '@/lib/scanability'
import { loadHistory, saveEntry, removeEntry } from '@/lib/history'
import { renderFinalCanvas, renderSvgBlob, canvasToBlob } from '@/lib/render'
import QrPreview from '@/components/QrPreview'
import ContentPanel from '@/sections/ContentPanel'
import DesignPanel from '@/sections/DesignPanel'
import ScanabilityMeter from '@/sections/ScanabilityMeter'
import BatchPanel from '@/sections/BatchPanel'
import ScannerPanel from '@/sections/ScannerPanel'
import HistoryPanel from '@/sections/HistoryPanel'
import { Button } from '@/components/ui/button'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet'
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu'
import { useIsMobile } from '@/hooks/use-mobile'
import { saveAs } from 'file-saver'
import { Toaster, toast } from 'sonner'
import {
  QrCode,
  Download,
  ShieldCheck,
  WifiOff,
  Layers,
  ScanLine,
  DownloadCloud,
  ChevronDown,
  Settings2,
} from 'lucide-react'

type Ext = 'png' | 'svg' | 'jpeg' | 'webp'

export default function Home() {
  const [content, setContent] = useState<ContentState>(DEFAULT_CONTENT)
  const [design, setDesign] = useState<DesignOptions>(DEFAULT_DESIGN)
  // Restored lazily rather than in an effect: setting state synchronously inside
  // an effect triggers a second render pass on every mount for no reason.
  const [history, setHistory] = useState<HistoryEntry[]>(() => loadHistory())
  const [tab, setTab] = useState('create')
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [installEvt, setInstallEvt] = useState<Event | null>(null)
  const isMobile = useIsMobile()

  useEffect(() => {
    const onPrompt = (e: Event) => {
      e.preventDefault()
      setInstallEvt(e)
    }
    window.addEventListener('beforeinstallprompt', onPrompt)
    return () => window.removeEventListener('beforeinstallprompt', onPrompt)
  }, [])

  const payload = useMemo(() => buildPayload(content), [content])
  const report = useMemo(
    () => (payload.trim() ? scoreScanability(payload, design) : null),
    [payload, design],
  )

  const persist = () => {
    const entry: HistoryEntry = {
      id: crypto.randomUUID(),
      createdAt: Date.now(),
      content,
      design,
    }
    setHistory(saveEntry(entry))
  }

  const download = async (ext: Ext) => {
    if (!payload.trim()) {
      toast.error('Add some content first — the code is empty.')
      return
    }
    let blob: Blob | null = null
    if (ext === 'svg') {
      blob = await renderSvgBlob(payload, design)
      if (design.ctaEnabled) {
        toast.info('SVG is vector-code only — the Context Band exports with PNG/WebP/JPEG.')
      }
    } else {
      blob = await canvasToBlob(await renderFinalCanvas(payload, design), ext)
    }
    if (!blob) {
      toast.error('Export failed.')
      return
    }
    saveAs(blob, `qrflow-${content.type}-${Date.now()}.${ext}`)
    persist()
    toast.success(`${ext.toUpperCase()} downloaded — saved to history.`)
  }

  const restore = (e: HistoryEntry) => {
    setContent({ ...DEFAULT_CONTENT, ...e.content })
    // clamp legacy px-based margins (≤10 modules) from entries saved before the units fix
    setDesign({ ...DEFAULT_DESIGN, ...e.design, margin: Math.min(e.design.margin ?? 4, 10) })
    setTab('create')
    toast.success('Design restored — keep editing.')
  }

  /** Primary action: SVG (print-perfect vector). Other formats live in the dropdown. */
  const exportButtons = (
    <div className="mt-4 space-y-2">
      <div className="flex">
        <Button className="flex-1 rounded-r-none" onClick={() => download('svg')}>
          <Download className="mr-1.5 h-4 w-4" /> Download SVG
        </Button>
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button className="rounded-l-none border-l border-primary-foreground/20 px-2.5">
              <ChevronDown className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onClick={() => download('png')}>PNG — raster, {design.size}px</DropdownMenuItem>
            <DropdownMenuItem onClick={() => download('jpeg')}>JPEG — photos & slides</DropdownMenuItem>
            <DropdownMenuItem onClick={() => download('webp')}>WebP — small web files</DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      <p className="text-center text-[11px] text-muted-foreground">
        SVG is infinitely scalable — the right default for print. Raster exports at {design.size}px.
      </p>
    </div>
  )

  const exportSection = (
    <div className="space-y-4">
      <div className="rounded-xl border border-border bg-card p-5">
        <div className="flex justify-center py-2">
          <QrPreview payload={payload || ' '} design={design} displaySize={isMobile ? 260 : 300} />
        </div>
        {!payload.trim() && (
          <p className="mt-2 text-center text-xs text-amber-600">
            Enter content to activate this code.
          </p>
        )}
        {exportButtons}
      </div>
      <ScanabilityMeter report={report} />
    </div>
  )

  return (
    <div className="min-h-screen bg-background text-foreground">
      <Toaster position="bottom-right" theme="light" />

      <header className="sticky top-0 z-20 border-b border-border bg-background/80 backdrop-blur">
        <div className="mx-auto flex max-w-7xl items-center gap-3 px-4 py-3">
          <img src="./mark-192.png" alt="" className="h-9 w-9" />
          <h1 className="text-sm font-bold">Qr.Code</h1>
          <div className="ml-auto flex items-center gap-2">
            <span className="hidden items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1 text-[11px] text-muted-foreground sm:flex">
              <ShieldCheck className="h-3.5 w-3.5" /> Client-side only
            </span>
            <span className="hidden items-center gap-1.5 rounded-full border border-border bg-card px-3 py-1 text-[11px] text-muted-foreground md:flex">
              <WifiOff className="h-3.5 w-3.5" /> Works offline
            </span>
            {installEvt && (
              <Button
                size="sm"
                variant="outline"
                onClick={async () => {
                  ;(installEvt as { prompt?: () => Promise<void> }).prompt?.()
                  setInstallEvt(null)
                }}
              >
                <DownloadCloud className="mr-1.5 h-4 w-4" /> Install app
              </Button>
            )}
            <Button size="sm" variant="outline" onClick={() => setSettingsOpen(true)}>
              <Settings2 className="mr-1.5 h-4 w-4" /> Design
            </Button>
          </div>
        </div>
      </header>

      {/* Design lives in settings — not a step. Available everywhere, never in the way. */}
      <Sheet open={settingsOpen} onOpenChange={setSettingsOpen}>
        <SheetContent side="right" className="w-full overflow-y-auto sm:max-w-md">
          <SheetHeader>
            <SheetTitle>Design settings</SheetTitle>
          </SheetHeader>
          <div className="mt-4 px-4 pb-8">
            <DesignPanel design={design} onChange={setDesign} />
          </div>
        </SheetContent>
      </Sheet>

      <main className={`mx-auto max-w-7xl px-4 py-6 ${isMobile ? 'pb-32' : ''}`}>
        <Tabs value={tab} onValueChange={setTab}>
          <TabsList className="mb-6">
            <TabsTrigger value="create">
              <QrCode className="mr-1.5 h-4 w-4" /> Create
            </TabsTrigger>
            <TabsTrigger value="batch">
              <Layers className="mr-1.5 h-4 w-4" /> Batch
            </TabsTrigger>
            <TabsTrigger value="scan">
              <ScanLine className="mr-1.5 h-4 w-4" /> Scan
            </TabsTrigger>
            <TabsTrigger value="history">History ({history.length})</TabsTrigger>
          </TabsList>

          <TabsContent value="create">
            {isMobile ? (
              <>
                {/* sticky live-preview chip — informational, not an action */}
                <div className="sticky top-[61px] z-10 -mx-4 mb-4 flex items-center gap-3 border-b border-border bg-background/90 px-4 py-2 backdrop-blur">
                  <QrPreview payload={payload || ' '} design={design} displaySize={52} checkerBg={false} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-xs font-medium">
                      {payload.trim() ? summarizeContent(content) : 'Empty code'}
                    </p>
                    {report && (
                      <p className="text-[11px] text-muted-foreground">
                        Scanability {report.score}/100 · {report.grade}
                      </p>
                    )}
                  </div>
                </div>

                {/* one page: content, then preview & export below */}
                <div className="space-y-4">
                  <section className="rounded-xl border border-border bg-card p-5">
                    <ContentPanel content={content} onChange={setContent} />
                  </section>
                  {exportSection}
                </div>

                {/* thumb zone: exactly one action */}
                <div
                  className="fixed inset-x-0 bottom-0 z-20 border-t border-border bg-background/95 backdrop-blur"
                  style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
                >
                  <div className="px-4 py-3">
                    <Button className="w-full" onClick={() => download('svg')}>
                      <Download className="mr-1.5 h-4 w-4" /> Download SVG
                    </Button>
                  </div>
                </div>
              </>
            ) : (
              <div className="grid gap-6 lg:grid-cols-[1fr_400px]">
                <section className="rounded-xl border border-border bg-card p-5">
                  <div className="mb-4 flex items-center justify-between">
                    <h2 className="text-sm font-semibold">Content</h2>
                    <Button size="sm" variant="ghost" onClick={() => setSettingsOpen(true)}>
                      <Settings2 className="mr-1.5 h-4 w-4" /> Design settings
                    </Button>
                  </div>
                  <ContentPanel content={content} onChange={setContent} />
                </section>
                <section>{exportSection}</section>
              </div>
            )}
          </TabsContent>

          <TabsContent value="batch">
            <div className="mx-auto max-w-3xl rounded-xl border border-border bg-card p-5">
              <h2 className="mb-4 text-sm font-semibold">Bulk generation — CSV or paste list</h2>
              <BatchPanel design={design} />
            </div>
          </TabsContent>

          <TabsContent value="scan">
            <div className="mx-auto max-w-4xl rounded-xl border border-border bg-card p-5">
              <h2 className="mb-4 text-sm font-semibold">Decode a QR code</h2>
              <ScannerPanel />
            </div>
          </TabsContent>

          <TabsContent value="history">
            <HistoryPanel
              entries={history}
              onRestore={restore}
              onDelete={(id) => setHistory(removeEntry(id))}
            />
          </TabsContent>
        </Tabs>
      </main>

      <footer className="border-t border-border py-6 text-center text-xs text-muted-foreground">
        Qr.Code — every byte stays in your browser. Built with React, TypeScript, qr-code-styling
        and jsQR.{' '}
        <a
          href="https://github.com/Yasirdora/qrcode"
          className="underline underline-offset-2 transition-colors hover:text-foreground"
        >
          Open source on GitHub
        </a>
        .
      </footer>
    </div>
  )
}
