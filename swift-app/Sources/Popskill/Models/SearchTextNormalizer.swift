import Foundation

struct SearchTextKey: Equatable {
    let separated: String
    let compact: String

    var isEmpty: Bool {
        separated.isEmpty && compact.isEmpty
    }

    func equals(_ query: SearchTextKey) -> Bool {
        separated == query.separated || (!compact.isEmpty && compact == query.compact)
    }

    func hasPrefix(_ query: SearchTextKey) -> Bool {
        (!query.separated.isEmpty && separated.hasPrefix(query.separated))
            || (!query.compact.isEmpty && compact.hasPrefix(query.compact))
    }

    func contains(_ query: SearchTextKey) -> Bool {
        (!query.separated.isEmpty && separated.contains(query.separated))
            || (!query.compact.isEmpty && compact.contains(query.compact))
    }
}

enum SearchTextNormalizer {
    static func key(_ value: String) -> SearchTextKey {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()

        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(folded.unicodeScalars.count)

        var previousWasSeparator = true
        for scalar in folded.unicodeScalars {
            if isSearchScalar(scalar) {
                scalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator {
                scalars.append(" ")
                previousWasSeparator = true
            }
        }

        if scalars.last == " " {
            scalars.removeLast()
        }

        let separated = String(String.UnicodeScalarView(scalars))
        return SearchTextKey(
            separated: separated,
            compact: separated.replacingOccurrences(of: " ", with: "")
        )
    }

    static func matches(_ text: String, query: SearchTextKey) -> Bool {
        key(text).contains(query)
    }

    private static func isSearchScalar(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }
}
