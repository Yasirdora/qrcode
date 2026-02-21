# QRFlow Studio

A privacy-first, offline-capable **QR code design studio** built as a Progressive Web App.
Every byte of processing happens in the browser — no server, no tracking, no per-code fees.

![Stack](https://img.shields.io/badge/React-19-61dafb) ![TS](https://img.shields.io/badge/TypeScript-strict-3178c6) ![PWA](https://img.shields.io/badge/PWA-offline-8b5cf6)

## Why this exists (the gap)

Mainstream QR tools either (a) charge $7–40/month for bulk generation, dynamic codes and vector
export, (b) silently cap scans or expire codes on free tiers, or (c) process your content on their
servers. QRFlow Studio demonstrates that **everything a static-QR workflow needs can run entirely
client-side** — including features the paid tools don't have, like a live scanability engine.

## Features

- **12 content types** — URL, text, Wi-Fi, vCard, email, SMS, phone, geo, calendar event, Bitcoin,
  WhatsApp (wa.me with pre-filled message), and a power-user **Custom** mode that encodes any raw
  payload byte-for-byte (SEPA/EPC bank transfers, app deep links, proprietary schemes)
- **Context Bands** — optional printed strip under the code with a call-to-action + the
  human-readable destination, so people know what they're scanning *before* they scan (a trust
  layer against QR phishing)
- **Settings, not steps** — design controls live in a slide-over panel available everywhere, so
  the flow is always just Content → Export; SVG is the primary download (print-perfect), raster
  formats one click away
- **Thumb-first mobile wizard** — on phones the Create flow becomes a 3-step Content → Design →
  Export wizard with a sticky live-preview chip, bottom action bar and safe-area insets
- **Live design studio** — module styles, gradients, corner frames, center logo with occlusion
  control, transparent backgrounds, presets
- **Scanability Score** — a real-time reliability engine (0–100) that grades contrast ratio (WCAG
  luminance), symbol density vs. ISO/IEC 18004 capacity tables, logo occlusion vs. error-correction
  allowance, and quiet-zone compliance
- **Bulk generation** — paste a list or import CSV → hundreds of styled PNG/SVG codes zipped with a
  manifest, all rendered locally
- **Built-in scanner** — camera decoding and image decoding via jsQR, fully on-device
- **History & re-edit** — downloaded designs persist locally and can be restored in one click
- **PWA** — installable, works offline (Workbox service worker), maskable icons
- **High-res export** — PNG/JPEG/WebP up to 4096px + infinitely scalable SVG for print

## Tech stack

React 19 · TypeScript · Vite 7 · Tailwind CSS · shadcn/ui (Radix) · qr-code-styling · jsQR ·
JSZip · PapaParse · vite-plugin-pwa (Workbox)

## Architecture notes

- `src/lib/payload.ts` — standards-compliant payload builders (WIFI: URI scheme, vCard 3.0,
  iCalendar VEVENT, mailto/sms/tel/geo/bitcoin URIs) plus a piecewise QR version estimator based on
  ISO/IEC 18004 byte-mode capacity tables
- `src/lib/scanability.ts` — the scoring engine: WCAG relative-luminance contrast, density,
  occlusion vs. EC allowance (L/M/Q/H ≈ 7/15/25/30%), quiet-zone math
- `src/components/QrPreview.tsx` — memoized qr-code-styling wrapper shared by preview, export and
  the batch renderer
- Zero network calls after load — verifiable in DevTools → Network

## Run it

```bash
npm install
npm run dev      # dev server
npm run build    # production build → dist/ (static, deploys anywhere)
```

## Roadmap

- [ ] Animated QR (APNG/GIF) export
- [ ] Batch mode with per-row design overrides from CSV columns
- [ ] Camera overlay guidance using the scanability model in reverse
