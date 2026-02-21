import { useEffect, useRef } from 'react'
import type { DesignOptions } from '@/types/qr'
import { renderFinalCanvas } from '@/lib/render'

interface Props {
  payload: string
  design: DesignOptions
  displaySize?: number
  checkerBg?: boolean
}

export default function QrPreview({ payload, design, displaySize = 320, checkerBg = true }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    let cancelled = false
    renderFinalCanvas(payload || ' ', design)
      .then((canvas) => {
        if (cancelled || !canvasRef.current) return
        const el = canvasRef.current
        el.width = canvas.width
        el.height = canvas.height
        el.getContext('2d')!.drawImage(canvas, 0, 0)
      })
      .catch(() => {})
    return () => {
      cancelled = true
    }
  }, [payload, design])

  return (
    <div
      className="rounded-xl overflow-hidden shadow-lg inline-block"
      style={
        design.transparentBg && checkerBg
          ? {
              backgroundImage: 'repeating-conic-gradient(#d4d4d8 0% 25%, #fafafa 0% 50%)',
              backgroundSize: '20px 20px',
            }
          : { background: design.transparentBg ? 'transparent' : design.bgColor }
      }
    >
      <canvas ref={canvasRef} style={{ width: displaySize, height: 'auto', display: 'block' }} />
    </div>
  )
}
