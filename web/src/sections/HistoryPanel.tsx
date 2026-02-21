import type { HistoryEntry } from '@/types/qr'
import { buildPayload, summarizeContent } from '@/lib/payload'
import QrPreview from '@/components/QrPreview'
import { Button } from '@/components/ui/button'
import { Trash2, RotateCcw } from 'lucide-react'

interface Props {
  entries: HistoryEntry[]
  onRestore: (e: HistoryEntry) => void
  onDelete: (id: string) => void
}

const TYPE_LABEL: Record<string, string> = {
  url: 'URL', text: 'Text', wifi: 'Wi-Fi', vcard: 'vCard',
  sms: 'SMS', phone: 'Phone', geo: 'Geo', event: 'Event', crypto: 'Crypto',
  whatsapp: 'WhatsApp', custom: 'Custom',
}

export default function HistoryPanel({ entries, onRestore, onDelete }: Props) {
  if (entries.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-border p-10 text-center text-sm text-muted-foreground">
        Nothing here yet — designs you download are saved to local history automatically.
      </div>
    )
  }
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      {entries.map((e) => {
        const payload = buildPayload(e.content)
        return (
          <div key={e.id} className="rounded-xl border border-border bg-card p-3 space-y-2">
            <div className="flex justify-center">
              <QrPreview payload={payload} design={e.design} displaySize={140} checkerBg={false} />
            </div>
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span className="rounded-full border border-border px-2 py-0.5">
                {TYPE_LABEL[e.content.type]}
              </span>
              <span>{new Date(e.createdAt).toLocaleString()}</span>
            </div>
            <p className="truncate text-xs text-muted-foreground" title={payload}>
              {summarizeContent(e.content)}
            </p>
            <div className="flex gap-2">
              <Button variant="outline" size="sm" className="flex-1" onClick={() => onRestore(e)}>
                <RotateCcw className="mr-1.5 h-3.5 w-3.5" /> Re-edit
              </Button>
              <Button variant="ghost" size="sm" onClick={() => onDelete(e.id)}>
                <Trash2 className="h-3.5 w-3.5 text-muted-foreground" />
              </Button>
            </div>
          </div>
        )
      })}
    </div>
  )
}
