import { describe, expect, it } from 'vitest'
import { isValidBitcoinAddress, sha256 } from './bitcoin'

const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')

describe('sha256', () => {
  it('matches the published vectors', () => {
    expect(hex(sha256(new Uint8Array()))).toBe(
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    )
    expect(hex(sha256(new TextEncoder().encode('abc')))).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    )
  })
})

describe('isValidBitcoinAddress', () => {
  it('accepts the known-good P2PKH, P2SH and bech32 vectors', () => {
    for (const address of [
      '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', // genesis block
      '1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2',
      '3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy', // P2SH
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4', // BIP173
    ]) {
      expect(isValidBitcoinAddress(address), address).toBe(true)
    }
  })

  it('rejects malformed and corrupted addresses', () => {
    for (const address of [
      '',
      '1',
      '0OIl', // characters outside the base58 alphabet
      '1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb', // one character changed
      'bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t5', // one character changed
      'bitcoin:1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa', // scheme included
    ]) {
      expect(isValidBitcoinAddress(address), address).toBe(false)
    }
  })
})
