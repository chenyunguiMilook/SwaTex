import Foundation

/// Formulas where SwaTex deliberately lays out differently from RaTeX because RaTeX differs from
/// KaTeX (`Resources/golden/katex_divergences.jsonl`). The golden corpora stay RaTeX's output, byte
/// for byte, so they can be regenerated; for an input listed here the golden tests expect this
/// display-list summary instead.
///
/// `reason` names the fix that moved it (align-column-gaps, null-delimiter, limit-kerns,
/// fraction-class, relative-units). Each was checked with `scripts/katex_diff`: none is further
/// from KaTeX 0.16.22 than RaTeX's value, and most now match it to 0.01em (the rest differ for
/// unrelated reasons listed in that script's README). KaTeX's numbers themselves are pinned by
/// `KaTeXAlignmentTests` and `KaTeXSpacingTests`.
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
