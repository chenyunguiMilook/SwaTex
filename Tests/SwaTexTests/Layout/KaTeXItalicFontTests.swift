import Testing

@testable import SwaTex

/// Italic corrections and fonts of runs of letters — where RaTeX (and SwaTex before) differed from
/// KaTeX. Numbers are KaTeX 0.16.22's own (`scripts/katex_diff --dump-katex`).
///
/// - KaTeX `tryCombineChars` merges adjacent symbols of the same classes / skew / size / color and
///   keeps only the last one's italic correction: `PV`, `ff`, `\mathrm{inf}` have none between
///   their letters; `fx` (different skew) keeps the f's.
/// - `\operatorname*{…}` (and `\limsup`, `\operatornamewithlimits`) is upright like
///   `\operatorname`; operator names (`\inf`, `\operatorname{inf}`) end with their last letter's
///   correction.
/// - `\mathit` is Main-Italic with no italic correction.
/// - A font command changes ords, not atoms: `\mathbf{a+b}` keeps a Main-Regular `+` and its
///   spacing; `\boldsymbol` sets atoms in Main-Bold.
/// - Only a single-symbol base shifts its subscript left by its correction (`\mathrm{inf}_n` does not).
@Suite("KaTeXItalicFont")
struct KaTeXItalicFontTests {
    private let tol = 0.002

    private func glyphs(_ latex: String) throws -> [(char: Character, x: Double, font: String)] {
        try SwaTexEngine.displayList(for: latex).items.compactMap {
            if case let .glyphPath(x, _, _, font, charCode, _) = $0 {
                return (Character(Unicode.Scalar(charCode)!), x, font)
            }
            return nil
        }
    }

    private func x(_ c: Character, _ nth: Int = 0, in latex: String) throws -> Double {
        let matches = try glyphs(latex).filter { $0.char == c }
        return try #require(nth < matches.count ? matches[nth] : nil, "no \(c) #\(nth) in \(latex)")
            .x
    }

    @Test func adjacentLettersShareOneCorrection() throws {
        #expect(abs(try x("V", in: "PV") - 0.7809) < tol)
        #expect(abs(try x("f", 1, in: #"\operatorname{ff} x"#) - 0.3057) < tol)
        #expect(abs(try x("x", in: #"\mathrm{ff} x"#) - 0.6896) < tol)
        // different skew: no combining, the f keeps its correction
        #expect(abs(try x("x", in: "fx") - 0.5976) < tol)
    }

    @Test func operatorNamesAreUprightAndEndWithTheirCorrection() throws {
        let limsup = try glyphs(#"\limsup_n x"#)
        for letter in limsup where "limsup".contains(letter.char) {
            #expect(letter.font == "Main-Regular", "\(letter.char) is \(letter.font)")
        }
        #expect(abs(try x("p", in: #"\limsup_n x"#) - 2.5055) < tol)
        #expect(abs(try x("x", in: #"\limsup_n x"#) - 3.2283) < tol)
        #expect(abs(try x("x", in: #"\inf x"#) - 1.3843) < tol)
        #expect(abs(try x("n", 1, in: #"\mathrm{inf}_n"#) - 1.2177) < tol)
    }

    @Test func mathitIsMainItalicWithoutCorrection() throws {
        let g = try glyphs(#"\mathit{ff} x"#)
        #expect(g.prefix(2).allSatisfy { $0.font == "Main-Italic" })
        #expect(abs(try x("f", 1, in: #"\mathit{ff} x"#) - 0.3067) < tol)
        #expect(abs(try x("x", in: #"\mathit{ff} x"#) - 0.614) < tol)
    }

    @Test func fontCommandsKeepAtomsAndTheirSpacing() throws {
        let bf = try glyphs(#"\mathbf{a+b}"#)
        #expect(bf.first { $0.char == "+" }?.font == "Main-Regular")
        #expect(abs(try x("+", in: #"\mathbf{a+b}"#) - 0.7813) < tol)
        #expect(abs(try x("b", in: #"\mathbf{a+b}"#) - 1.7814) < tol)
        let bold = try glyphs(#"\boldsymbol{x+\mu}"#)
        #expect(bold.first { $0.char == "+" }?.font == "Main-Bold")
        #expect(abs(try x("μ", in: #"\boldsymbol{x+\mu}"#) - 1.9977) < tol)
    }
}
