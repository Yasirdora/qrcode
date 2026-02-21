import { useEffect, useRef, useState, useCallback } from 'react'
import jsQR from 'jsqr'
import { Button } from '@/components/ui/button'
import { Camera, CameraOff, Upload, Copy, ExternalLink } from 'lucide-react'
import { toast } from 'sonner'

interface ScanResult {
  text: string
  at: number
}

export default function ScannerPanel() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const rafRef = useRef<number>(0)
  const fileRef = useRef<HTMLInputElement>(null)
  const [cameraOn, setCameraOn] = useState(false)
  const [result, setResult] = useState<ScanResult | null>(null)
  const [dragOver, setDragOver] = useState(false)
  const lastSeenRef = useRef<string>('')

  const stopCamera = useCallback(() => {
    cancelAnimationFrame(rafRef.current)
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    setCameraOn(false)
  }, [])

  useEffect(() => stopCamera, [stopCamera])

  const tick = useCallback(() => {
    const video = videoRef.current
    const canvas = canvasRef.current
    if (!video || !canvas || video.readyState !== video.HAVE_ENOUGH_DATA) {
      rafRef.current = requestAnimationFrame(tick)
      return
    }
    const ctx = canvas.getContext('2d', { willReadFrequently: true })
    if (!ctx) return
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    ctx.drawImage(video, 0, 0)
    const img = ctx.getImageData(0, 0, canvas.width, canvas.height)
    const code = jsQR(img.data, img.width, img.height, { inversionAttempts: 'attemptBoth' })
    if (code?.data && code.data !== lastSeenRef.current) {
      lastSeenRef.current = code.data
      setResult({ text: code.data, at: Date.now() })
      toast.success('QR code decoded')
    }
    rafRef.current = requestAnimationFrame(tick)
  }, [])

  const startCamera = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
      })
      streamRef.current = stream
      if (videoRef.current) {
        videoRef.current.srcObject = stream
        await videoRef.current.play()
      }
      setCameraOn(true)
      rafRef.current = requestAnimationFrame(tick)
    } catch {
      toast.error('Camera unavailable — check permissions, or decode an image instead.')
    }
  }

  const decodeImage = (file: Blob | undefined) => {
    if (!file) return
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      const canvas = document.createElement('canvas')
      const scale = Math.min(1, 1600 / Math.max(img.width, img.height))
      canvas.width = img.width * scale
      canvas.height = img.height * scale
      const ctx = canvas.getContext('2d', { willReadFrequently: true })!
      ctx.drawImage(img, 0, 0, canvas.width, canvas.height)
      const data = ctx.getImageData(0, 0, canvas.width, canvas.height)
      const code = jsQR(data.data, data.width, data.height, { inversionAttempts: 'attemptBoth' })
      URL.revokeObjectURL(url)
      if (code?.data) {
        setResult({ text: code.data, at: Date.now() })
        toast.success('QR code decoded')
      } else {
        toast.error('No QR code found in that image.')
      }
    }
    img.onerror = () => toast.error('Could not read that image file.')
    img.src = url
  }

  // paste from clipboard (⌘V / Ctrl+V) anywhere while the Scan tab is open
  useEffect(() => {
    const onPaste = (e: ClipboardEvent) => {
      const item = Array.from(e.clipboardData?.items ?? []).find((i) => i.type.startsWith('image/'))
      if (!item) return
      e.preventDefault()
      decodeImage(item.getAsFile() ?? undefined)
    }
    window.addEventListener('paste', onPaste)
    return () => window.removeEventListener('paste', onPaste)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const onDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setDragOver(false)
    const file = Array.from(e.dataTransfer.files).find((f) => f.type.startsWith('image/'))
    if (file) decodeImage(file)
    else toast.error('Drop an image file (PNG, JPG, WebP…).')
  }

  const isLink = result ? /^https?:\/\//i.test(result.text) : false

  return (
    <div className="space-y-4">
      <div className="grid gap-4 md:grid-cols-2">
        <div
          className={`space-y-3 rounded-xl border-2 border-dashed p-3 transition-colors ${
            dragOver ? 'border-foreground bg-muted/50' : 'border-transparent'
          }`}
          onDragOver={(e) => {
            e.preventDefault()
            setDragOver(true)
          }}
          onDragLeave={() => setDragOver(false)}
          onDrop={onDrop}
        >
          <div className="relative aspect-video overflow-hidden rounded-xl border border-border bg-black/40">
            <video ref={videoRef} className="h-full w-full object-cover" muted playsInline />
            {!cameraOn && (
              <div className="absolute inset-0 flex flex-col items-center justify-center gap-2 text-white/70">
                {dragOver ? (
                  <>
                    <Upload className="h-8 w-8" />
                    <span className="text-xs font-medium">Drop to decode</span>
                  </>
                ) : (
                  <>
                    <CameraOff className="h-8 w-8" />
                    <span className="text-xs">Camera is off</span>
                  </>
                )}
              </div>
            )}
          </div>
          <canvas ref={canvasRef} className="hidden" />
          <div className="flex gap-2">
            <Button
              variant={cameraOn ? 'destructive' : 'default'}
              className="flex-1"
              onClick={cameraOn ? stopCamera : startCamera}
            >
              {cameraOn ? (
                <>
                  <CameraOff className="mr-2 h-4 w-4" /> Stop camera
                </>
              ) : (
                <>
                  <Camera className="mr-2 h-4 w-4" /> Start camera
                </>
              )}
            </Button>
            <Button variant="outline" className="flex-1" onClick={() => fileRef.current?.click()}>
              <Upload className="mr-2 h-4 w-4" /> Decode image
            </Button>
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={(e) => decodeImage(e.target.files?.[0])}
            />
          </div>
          <p className="text-center text-[11px] text-muted-foreground">
            Drag &amp; drop an image here, or paste one from your clipboard (⌘V / Ctrl+V)
          </p>
        </div>

        <div className="rounded-xl border border-border bg-card p-4">
          <h3 className="text-sm font-medium mb-2">Decoded content</h3>
          {result ? (
            <div className="space-y-3">
              <pre className="max-h-64 overflow-auto whitespace-pre-wrap break-all rounded-lg bg-muted/50 p-3 text-xs">
                {result.text}
              </pre>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    navigator.clipboard.writeText(result.text)
                    toast.success('Copied to clipboard')
                  }}
                >
                  <Copy className="mr-1.5 h-3.5 w-3.5" /> Copy
                </Button>
                {isLink && (
                  <Button size="sm" asChild>
                    <a href={result.text} target="_blank" rel="noreferrer">
                      <ExternalLink className="mr-1.5 h-3.5 w-3.5" /> Open link
                    </a>
                  </Button>
                )}
              </div>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground">
              Point the camera at a QR code or upload an image — decoding happens entirely on this
              device. Nothing is uploaded.
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
