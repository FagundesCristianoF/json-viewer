import Foundation

enum TextNormalizer {

    private static let vietnameseMappings: [(Character, Character)] = [
        ("đ", "d"), ("Đ", "D"), ("ð", "d"), ("Ð", "D")
    ]

    // Unicode code points that map to space (punctuation / special)
    private static func isPunctuation(_ v: UInt32) -> Bool {
        (v >= 0x2010 && v <= 0x2015) ||  // dashes
        v == 0x2212 ||  // minus sign
        v == 0x00AD ||  // soft hyphen
        v == 0x2018 || v == 0x2019 ||  // curly single
        v == 0x201C || v == 0x201D || v == 0x201E ||  // curly double
        v == 0x2032 || v == 0x2033 ||  // prime
        v == 0x22 || v == 0x27 || v == 0x60 || v == 0xB4 ||  // ASCII quotes
        v == 0x2026 ||  // ellipsis
        v == 0xB7 || v == 0x2022  // middle dot, bullet
    }

    static func normalize(_ value: String) -> String {
        guard !value.isEmpty else { return "" }

        var text = value
        for (from, to) in vietnameseMappings {
            text = text.replacingOccurrences(of: String(from), with: String(to))
        }

        // Decompose accents
        let decomposed = text.decomposedStringWithCompatibilityMapping
        var stripped = ""
        for scalar in decomposed.unicodeScalars {
            let cat = scalar.properties.generalCategory
            if cat == .nonspacingMark || cat == .spacingMark || cat == .enclosingMark {
                continue
            }
            stripped.unicodeScalars.append(scalar)
        }

        // Replace punctuation with space
        var replaced = ""
        for scalar in stripped.unicodeScalars {
            replaced.append(isPunctuation(scalar.value) ? " " : Character(scalar))
        }

        return replaced
            .lowercased()
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func nameLastToken(_ name: String) -> String {
        let norm = normalize(name)
        let tokens = norm.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }
        return tokens.last ?? norm
    }
}
