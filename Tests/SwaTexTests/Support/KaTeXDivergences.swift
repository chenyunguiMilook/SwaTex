import Foundation

/// Formulas where SwaTex deliberately lays out differently from RaTeX because RaTeX differs from
/// KaTeX (`Resources/golden/katex_divergences.jsonl`). The golden corpora stay RaTeX's output, byte
/// for byte, so they can be regenerated; for an input listed here the golden tests expect this
/// display-list summary instead.
///
/// Every entry was checked against KaTeX 0.16.22 with `scripts/katex_diff` (glyph positions, not
/// just the box). The KaTeX numbers themselves are pinned by `KaTeXAlignmentTests`.
enum KaTeXDivergences {
    struct Entry: Decodable {
        struct DL: Decodable, Equatable {
            var width: Double
            var height: Double
            var depth: Double
            var itemCount: Int
        }
        var input: String
        var reason: String
        var displayList: DL
    }

    static let entries: [Entry] = {
        guard
            let url = Bundle.module.url(
                forResource: "katex_divergences", withExtension: "jsonl", subdirectory: "golden"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap {
            try? decoder.decode(Entry.self, from: Data($0.utf8))
        }
    }()

    static let byInput: [String: Entry.DL] = Dictionary(
        entries.map { ($0.input, $0.displayList) }, uniquingKeysWith: { first, _ in first })
}
