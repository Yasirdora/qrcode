import type { ScanReport } from '@/lib/scanability'
import { CheckCircle2, AlertTriangle, XCircle } from 'lucide-react'

const ICONS = {
  pass: <CheckCircle2 className="h-4 w-4 text-emerald-600 shrink-0" />,
  warn: <AlertTriangle className="h-4 w-4 text-amber-600 shrink-0" />,
  fail: <XCircle className="h-4 w-4 text-rose-600 shrink-0" />,
}

const GRADE_COLOR: Record<string, string> = {
  Excellent: 'text-emerald-600',
  Good: 'text-lime-700',
  Risky: 'text-amber-600',
  'Likely unscannable': 'text-rose-600',
}

function scoreColor(score: number): string {
  if (score >= 90) return '#059669'
  if (score >= 70) return '#65a30d'
  if (score >= 45) return '#d97706'
  return '#e11d48'
}

export default function ScanabilityMeter({ report }: { report: ScanReport }) {
  const r = 34
  const circ = 2 * Math.PI * r
  const color = scoreColor(report.score)

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-center gap-4">
        <svg width="84" height="84" viewBox="0 0 84 84" className="-rotate-90">
          <circle cx="42" cy="42" r={r} fill="none" stroke="currentColor" strokeWidth="7" className="text-muted/40" />
          <circle
            cx="42"
            cy="42"
            r={r}
            fill="none"
            stroke={color}
            strokeWidth="7"
            strokeLinecap="round"
            strokeDasharray={circ}
            strokeDashoffset={circ * (1 - report.score / 100)}
            style={{ transition: 'stroke-dashoffset 0.5s ease, stroke 0.5s ease' }}
          />
        </svg>
        <div>
          <div className="text-3xl font-bold tabular-nums" style={{ color }}>
            {report.score}
          </div>
          <div className={`text-sm font-medium ${GRADE_COLOR[report.grade]}`}>{report.grade}</div>
          <div className="text-xs text-muted-foreground">Scanability score</div>
        </div>
      </div>
      <ul className="space-y-2">
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
    </div>
  )
}
