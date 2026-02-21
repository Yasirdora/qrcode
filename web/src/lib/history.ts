import type { HistoryEntry } from '@/types/qr'

const KEY = 'qrflow:history'
const MAX = 30

export function loadHistory(): HistoryEntry[] {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as HistoryEntry[]) : []
  } catch {
    return []
  }
}

export function saveEntry(entry: HistoryEntry): HistoryEntry[] {
  const list = [entry, ...loadHistory().filter((e) => e.id !== entry.id)].slice(0, MAX)
  localStorage.setItem(KEY, JSON.stringify(list))
  return list
}

export function removeEntry(id: string): HistoryEntry[] {
  const list = loadHistory().filter((e) => e.id !== id)
  localStorage.setItem(KEY, JSON.stringify(list))
  return list
}

export function clearHistory(): void {
  localStorage.removeItem(KEY)
}
