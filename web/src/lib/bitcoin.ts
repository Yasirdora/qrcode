/**
 * Bitcoin address validation by checksum — the same rules the iOS app applies,
 * so a mistyped address is refused by both before it is ever printed.
 *
 * Two encodings carry an address: Base58Check (P2PKH `1…`, P2SH `3…`) and
 * bech32 / bech32m (segwit `bc1…`). Witness version 0 uses bech32, version 1
 * and above use bech32m — mixing the two is the bug BIP350 fixed, so the
 * constant is chosen by version rather than assumed.
 *
 * This proves the address is internally consistent. It cannot prove the address
 * exists on the chain or belongs to anyone; no offline check can.
 */

const BASE58_ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
const BECH32_ALPHABET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l'
const BECH32_CONST = 1
const BECH32M_CONST = 0x2bc830a3

export function isValidBitcoinAddress(address: string): boolean {
  return address.length > 0 && (isValidBase58Check(address) || isValidSegwit(address))
}

// MARK: - Base58Check

function isValidBase58Check(address: string): boolean {
  const decoded = base58Decode(address)
  // Version byte + 20-byte hash + 4-byte checksum.
  if (!decoded || decoded.length !== 25) return false
  if (decoded[0] !== 0x00 && decoded[0] !== 0x05) return false
  const digest = sha256(sha256(decoded.slice(0, 21)))
  return decoded.slice(21).every((byte, i) => byte === digest[i])
}

/** Big-integer decode: repeated multiply-and-add, least significant byte first. */
function base58Decode(input: string): Uint8Array | null {
  const bytes: number[] = []
  for (const character of input) {
    const digit = BASE58_ALPHABET.indexOf(character)
    if (digit < 0) return null
    let carry = digit
    for (let i = 0; i < bytes.length; i++) {
      carry += 58 * bytes[i]
      bytes[i] = carry & 0xff
      carry >>= 8
    }
    while (carry > 0) {
      bytes.push(carry & 0xff)
      carry >>= 8
    }
  }
  // A leading '1' is a leading zero byte, not a value.
  const leadingZeros = input.match(/^1*/)?.[0].length ?? 0
  return Uint8Array.from([...new Array<number>(leadingZeros).fill(0), ...bytes.reverse()])
}

// MARK: - Segwit (bech32 / bech32m)

function isValidSegwit(address: string): boolean {
  // Mixed case is invalid per BIP173; all-lower or all-upper is fine.
  if (/[A-Z]/.test(address) && /[a-z]/.test(address)) return false
  const lowered = address.toLowerCase()
  const separator = lowered.lastIndexOf('1')
  if (separator < 1) return false
  const hrp = lowered.slice(0, separator)
  const dataPart = lowered.slice(separator + 1)
  if (!['bc', 'tb', 'bcrt'].includes(hrp)) return false
  // Six checksum characters plus at least the witness version.
  if (dataPart.length < 7 || dataPart.length > 90) return false

  const values: number[] = []
  for (const character of dataPart) {
    const value = BECH32_ALPHABET.indexOf(character)
    if (value < 0) return false
    values.push(value)
  }
  const version = values[0]
  if (version > 16) return false
  const data = values.slice(0, -6)
  const checksum = values.slice(-6)
  const constant = version === 0 ? BECH32_CONST : BECH32M_CONST
  if (polymod([...hrpExpand(hrp), ...data, ...checksum]) !== constant) return false

  // Witness program: 2…40 bytes; 20 or 32 for v0, exactly 32 for v1+.
  const program = convertBits(data.slice(1), 5, 8, false)
  if (!program || program.length < 2 || program.length > 40) return false
  return version === 0 ? program.length === 20 || program.length === 32 : program.length === 32
}

function hrpExpand(hrp: string): number[] {
  const high: number[] = []
  const low: number[] = []
  for (const character of hrp) {
    high.push(character.charCodeAt(0) >> 5)
    low.push(character.charCodeAt(0) & 31)
  }
  return [...high, 0, ...low]
}

function polymod(values: number[]): number {
  const generators = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
  let checksum = 1
  for (const value of values) {
    const top = checksum >> 25
    checksum = ((checksum & 0x1ffffff) << 5) ^ value
    for (let i = 0; i < 5; i++) if ((top >> i) & 1) checksum ^= generators[i]
  }
  return checksum >>> 0
}

function convertBits(data: number[], from: number, to: number, pad: boolean): number[] | null {
  let accumulator = 0
  let bits = 0
  const output: number[] = []
  const maxValue = (1 << to) - 1
  for (const value of data) {
    accumulator = (accumulator << from) | value
    bits += from
    while (bits >= to) {
      bits -= to
      output.push((accumulator >> bits) & maxValue)
    }
  }
  if (pad) {
    if (bits > 0) output.push((accumulator << (to - bits)) & maxValue)
  } else if (bits >= from || ((accumulator << (to - bits)) & maxValue) !== 0) {
    return null
  }
  return output
}

// MARK: - SHA-256

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])

function rotr(value: number, shift: number): number {
  return (value >>> shift) | (value << (32 - shift))
}

/**
 * SHA-256, needed for the Base58Check checksum. WebCrypto's `digest` is
 * asynchronous and the payload builder is not, so the compression function
 * lives here; it is pinned by the standard test vectors.
 */
export function sha256(message: Uint8Array): Uint8Array {
  const h = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ])
  const remainder = (message.length + 9) % 64
  const padding = remainder === 0 ? 0 : 64 - remainder
  const padded = new Uint8Array(message.length + 1 + padding + 8)
  padded.set(message)
  padded[message.length] = 0x80
  const view = new DataView(padded.buffer)
  const bitLength = message.length * 8
  view.setUint32(padded.length - 8, Math.floor(bitLength / 0x100000000))
  view.setUint32(padded.length - 4, bitLength >>> 0)

  const w = new Uint32Array(64)
  for (let offset = 0; offset < padded.length; offset += 64) {
    for (let i = 0; i < 16; i++) w[i] = view.getUint32(offset + i * 4)
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3)
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10)
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0
    }
    let [a, b, c, d, e, f, g, hh] = h
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
      const ch = (e & f) ^ (~e & g)
      const t1 = (hh + S1 + ch + K[i] + w[i]) >>> 0
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const t2 = (S0 + maj) >>> 0
      hh = g
      g = f
      f = e
      e = (d + t1) >>> 0
      d = c
      c = b
      b = a
      a = (t1 + t2) >>> 0
    }
    h[0] = (h[0] + a) >>> 0
    h[1] = (h[1] + b) >>> 0
    h[2] = (h[2] + c) >>> 0
    h[3] = (h[3] + d) >>> 0
    h[4] = (h[4] + e) >>> 0
    h[5] = (h[5] + f) >>> 0
    h[6] = (h[6] + g) >>> 0
    h[7] = (h[7] + hh) >>> 0
  }

  const out = new Uint8Array(32)
  const outView = new DataView(out.buffer)
  for (let i = 0; i < 8; i++) outView.setUint32(i * 4, h[i])
  return out
}
