# Qr.Code — web studio

The browser edition of Qr.Code: an offline, client-side QR code design studio.
No server, no account, no per-code fee — and no network request after the page
loads, which is verifiable in DevTools.

This is the app the iOS edition at the repository root is a port of. The two
share the payload vocabulary, the scanability model and the design language, so
a design built in one can be rebuilt in the other.

## What it does

- **12 payload types** — URL, text, Wi-Fi, contact card, email, SMS, phone,
  geo, calendar event, Bitcoin payment, WhatsApp, and a raw mode that encodes
  anything a scanner understands (SEPA/EPC transfers, deep links, proprietary
  schemes).
- **Styling** — six module shapes, corner frames and dots, gradients,
  transparent backgrounds, centre logos with occlusion feedback, and presets.
- **Scanability score** — contrast by WCAG luminance, symbol density against
  ISO/IEC 18004 capacity, logo occlusion against the error-correction
  allowance, and quiet-zone compliance, with the failing checks named.
- **Export** — SVG for print, plus PNG, JPEG and WebP up to 4096px.
- **Bulk generation** — paste a list or import a CSV, render each entry, and
  download a ZIP with a manifest.
- **Scanner** — camera and image decoding, on device.
- **History** — downloaded designs persist locally and restore in one click.
- **Installable PWA** — offline after the first visit.

## Stack

React 19 · TypeScript · Vite · Tailwind CSS · shadcn/ui (Radix) ·
qr-code-styling · jsQR · JSZip · PapaParse · vite-plugin-pwa.

## Run it

```bash
npm install
npm run dev      # development server
npm run verify   # lint, tests and a production build
```

## Tests

```bash
npm test
```

17 tests cover the pure logic: the payload builders (escaping, CRLF records,
iCalendar wrapping, address validation) and the scanability engine (contrast,
density, occlusion, quiet zone). The rendering and camera paths are not
covered — they need a browser and a camera, and the gap is stated rather than
hidden.

## Architecture

| Path | Responsibility |
| --- | --- |
| `src/lib/payload.ts` | Payload construction for the 12 types, plus the QR version estimator |
| `src/lib/bitcoin.ts` | Bitcoin address checksums — Base58Check, bech32 and bech32m — and the SHA-256 they need |
| `src/lib/scanability.ts` | The scoring engine |
| `src/lib/render.ts` | Canvas, SVG and ZIP rendering, shared by export and batch |
| `src/sections/` | The panels: content, design, scanability, scanner, history, batch |
| `src/components/ui/` | Vendored shadcn/ui primitives |

## Licence

MIT — see the [repository licence](../LICENSE).
