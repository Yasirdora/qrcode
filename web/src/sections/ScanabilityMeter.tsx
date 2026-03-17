import type { ScanReport } from '@/lib/scanability'
import { CheckCircle2, AlertTriangle, XCircle } from 'lucide-react'

const ICONS = {
  pass: <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />,
  warn: <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0" />,
  fail: <XCircle className="h-4 w-4 text-rose-600 shrink-0" />,
}

function scoreColor(score: number): string {
  if (score >= 90) return '#059669'
  if (score >= 70) return '#65a30d'
  if (score >= 45) return '#d97706'
  return '#e11d48'
}

/**
 * The code is the subject of this page; the score is a footnote to it, not a
 * headline — the same call as on iOS. A null report means there is nothing to
 * score yet, and saying so beats scoring an empty code 100.
 */
export default function ScanabilityMeter({ report }: { report: ScanReport | null }) {
  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-sm font-medium">Scanability</span>
        {report ? (
          <span className="text-sm tabular-nums">
            <span className="font-semibold" style={{ color: scoreColor(report.score) }}>
              {report.score}
            </span>
            <span className="ml-1.5 text-muted-foreground">{report.grade}</span>
          </span>
        ) : (
          <span className="text-sm text-muted-foreground">Empty code</span>
        )}
      </div>
      {report && (
        <ul className="space-y-2 border-t border-border pt-3">
          {report.checks.map((c) => (
            <li key={c.id} className="flex items-start gap-2 text-xs">
              {ICONS[c.status]}
              <div>
                <span className="font-medium text-foreground">{c.label}: </span>
                <span className="text-muted-foreground">{c.detail}</span>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
