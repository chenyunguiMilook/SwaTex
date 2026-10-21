import Testing

@testable import SwaTex

/// Column gaps of the align family and the width of null delimiters — two places where RaTeX (and
/// SwaTex before) differed from KaTeX. The expectations are KaTeX's rules, stated as relations
/// that hold in KaTeX 0.16.22 (checked glyph by glyph with `scripts/katex_diff`), so they do not
/// depend on any one glyph's metrics:
///
/// - aligned/align: no space inside an `rl` pair, 1em (`pregap`) before every later pair, and the
///   relation keeps its full thick space on both sides (KaTeX environments/array.ts `alignedHandler`).
/// - alignat: no space anywhere between columns.
/// - `\left.` / `\right.` / `\middle.` take `\nulldelimiterspace` (0.12em); `\big.` takes nothing.
@Suite("KaTeXAlignment")
struct KaTeXAlignmentTests {
    private let thickSpace = 5.0 / 18.0

    private func displayList(_ latex: String) throws -> DisplayList {
        try SwaTexEngine.displayList(for: latex)
    }

    private func glyphXs(_ latex: String) throws -> [Double] {
        try displayList(latex).items.compactMap {
            if case let .glyphPath(x, _, _, _, _, _) = $0 { return x }
            return nil
        }
    }

    @Test func alignedRelationKeepsItsSpacingOnBothSides() throws {
        // Regression: "=" sat 0.333em after "a" and 0.167em before "b" (a 3mu column gap plus
        // relation spacing capped at 3mu). In KaTeX the aligned row is spaced exactly like `a=b`.
        let plain = try glyphXs(#"a=b"#)
        let aligned = try glyphXs(#"\begin{aligned}a&=b\end{aligned}"#)
        #expect(plain.count == 3 && aligned.count == 3)
        for (p, a) in zip(plain, aligned) {
            #expect(abs(p - a) < 1e-4, "aligned \(aligned) vs plain \(plain)")
        }
        // …and the gap after "=" is one thick space ("=" is 0.77778em wide in Main-Regular).
        #expect(abs((aligned[2] - aligned[1]) - (0.77778 + thickSpace)) < 1e-4)
    }

    @Test func alignedPairsAreOneEmApart() throws {
        // Regression: pairs were 3mu apart instead of \qquad-ish 1em (`pregap: 1`).
        let first = try displayList(#"a=b"#).width
        let xs = try glyphXs(#"\begin{aligned}a&=b&c&=d\end{aligned}"#)
        #expect(xs.count == 6)
        #expect(abs(xs[3] - (first + 1.0)) < 1e-4, "c at \(xs[3]), first pair is \(first) wide")
    }

    @Test func alignatColumnsTouch() throws {
        let first = try displayList(#"a=b"#).width
        let xs = try glyphXs(#"\begin{alignedat}{2}a&=b&c&=d\end{alignedat}"#)
        #expect(xs.count == 6)
        #expect(abs(xs[3] - first) < 1e-4, "c at \(xs[3]), first pair is \(first) wide")
    }

    @Test func nullDelimitersTakeNullDelimiterSpace() throws {
        let x = try displayList(#"x"#).width
        let bare = try displayList(#"\left. x \right."#)
        #expect(abs(bare.width - (x + 2 * nullDelimiterSpace)) < 1e-4)
        #expect(abs((try glyphXs(#"\left. x \right."#).first ?? -1) - nullDelimiterSpace) < 1e-4)
        let middle = try displayList(#"\left( x \middle. x \right)"#).width
        let noMiddle = try displayList(#"\left( x x \right)"#).width
        #expect(abs(middle - noMiddle - nullDelimiterSpace) < 1e-4)
    }

    @Test func bigNullDelimiterTakesNothing() throws {
        #expect(abs(try displayList(#"\big. x"#).width - displayList(#"x"#).width) < 1e-4)
    }
}
