import Foundation

/// Hand-rolled GS1 EAN-13 / EAN-8 encoder — the Tier-2 symbologies CoreImage
/// doesn't ship. Pure Foundation so the bit tables and check-digit math are
/// pinned by unit tests without a simulator.
enum EANEncoder {

    // 7-module digit patterns, per GS1 General Specifications.
    static let lPatterns = ["0001101", "0011001", "0010011", "0111101", "0100011",
                            "0110001", "0101111", "0111011", "0110111", "0001011"]
    static let gPatterns = ["0100111", "0110011", "0011011", "0100001", "0011101",
                            "0111001", "0000101", "0010001", "0001001", "0010111"]
    static let rPatterns = ["1110010", "1100110", "1101100", "1000010", "1011100",
                            "1001110", "1010000", "1000100", "1001000", "1110100"]

    /// First-digit parity map for EAN-13's left half (L = odd, G = even).
    static let firstDigitParity = ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
                                   "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"]

    /// GS1 mod-10 check digit over the body (without the check digit itself).
    /// EAN-13 weights 1,3,1,3… from the left of the 12-digit body;
    /// EAN-8 weights 3,1,3,1… from the left of the 7-digit body.
    static func checkDigit(body: [Int], kind: Symbology) -> Int {
        let heavyFirst = kind == .ean8
        let sum = body.enumerated().reduce(0) { acc, pair in
            let weight = (pair.offset % 2 == 0) == heavyFirst ? 3 : 1
            return acc + pair.element * weight
        }
        return (10 - sum % 10) % 10
    }

    /// Validates and normalizes user input to the full digit string (13 or 8).
    /// Accepts a body without its check digit and appends it; rejects
    /// non-digits, wrong lengths and bad check digits.
    static func normalized(_ input: String, kind: Symbology) -> String? {
        guard kind == .ean13 || kind == .ean8,
              !input.isEmpty,
              input.allSatisfy(\.isNumber) else { return nil }
        var digits = input.compactMap(\.wholeNumberValue)
        let bodyLength = kind == .ean13 ? 12 : 7
        if digits.count == bodyLength {
            digits.append(checkDigit(body: digits, kind: kind))
        }
        guard digits.count == bodyLength + 1,
              digits.last == checkDigit(body: Array(digits.dropLast()), kind: kind) else { return nil }
        return digits.map(String.init).joined()
    }

    /// Full module row including guard patterns, without quiet zones:
    /// 95 modules for EAN-13, 67 for EAN-8. '1' = bar, '0' = space.
    static func modules(_ input: String, kind: Symbology) -> String? {
        guard let digits = normalized(input, kind: kind) else { return nil }
        let d = digits.compactMap(\.wholeNumberValue)
        var row = "101" // left guard
        switch kind {
        case .ean13:
            let parity = firstDigitParity[d[0]]
            for (i, digit) in d[1...6].enumerated() {
                let p = parity[parity.index(parity.startIndex, offsetBy: i)]
                row += p == "L" ? lPatterns[digit] : gPatterns[digit]
            }
            row += "01010" // center guard
            for digit in d[7...12] { row += rPatterns[digit] }
        case .ean8:
            for digit in d[0...3] { row += lPatterns[digit] }
            row += "01010"
            for digit in d[4...7] { row += rPatterns[digit] }
        default:
            return nil
        }
        row += "101" // right guard
        return row
    }
}
