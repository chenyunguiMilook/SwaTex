import Testing

@testable import SwaTex

/// Operator limits, the class of a fraction, and relative units in script styles — three places
/// where RaTeX (and SwaTex before) differed from KaTeX. Numbers are KaTeX 0.16.22's own, read with
/// `scripts/katex_diff --dump-katex` (browser layout, so good to a few 1e-4 em).
///
/// - Limits: KaTeX `assembleSupSub` kerns, no extra 0.08em (RaTeX's padding put `\sum` / `\lim`
///   limits 0.08em too far out).
/// - `\frac` is an Ord (KaTeX wraps every genfrac in `mord`); RaTeX made it Inner, adding a thin
///   space next to an Ord in display style.
/// - `em` / `ex` in script styles are text-style units, absolute units are absolute (KaTeX
///   units.js); RaTeX measured both in the script font, 0.7× too small.
@Suite("KaTeXSpacing")
struct KaTeXSpacingTests {
    private let tol = 0.002

    private func glyphs(_ latex: String) throws -> [(char: Character, x: Double, y: Double)] {
        let dl = try SwaTexEngine.displayList(for: latex)
        return dl.items.compactMap {
            if case let .glyphPath(x, y, _, _, charCode, _) = $0 {
                return (Character(Unicode.Scalar(charCode)!), x, y - dl.height)
            }
            return nil
        }
    }

    private func glyph(_ c: Character, in latex: String) throws -> (x: Double, y: Double) {
        let g = try #require(try glyphs(latex).first { $0.char == c }, "no \(c) in \(latex)")
        return (g.x, g.y)
    }

    @Test func sumLimitsSitAtKaTeXsKerns() throws {
        let tex = #"\sum_{n=1}^{\infty} x"#
        #expect(abs(try glyph("n", in: tex).y - 1.167) < tol)
        #expect(abs(try glyph("∞", in: tex).y - -1.25) < tol)
        let dl = try SwaTexEngine.displayList(for: tex)
        #expect(abs(dl.height - 1.6514) < tol)
        #expect(abs(dl.depth - 1.2671) < tol)
    }

    @Test func limSubscriptSitsAtKaTeXsKern() throws {
        let tex = #"\lim_{x \to 0} f"#
        #expect(abs(try glyph("→", in: tex).y - 0.6169) < tol)
        #expect(abs(try SwaTexEngine.displayList(for: tex).depth - 0.7171) < tol)
    }

    @Test func undersetUsesTheLimitsHeightInThisStylesEm() throws {
        // Regression: \overset / \underset took the script box's height unscaled (0.129em off).
        #expect(abs(try glyph("a", in: #"\underset{a}{X}"#).y - 0.5998) < tol)
    }

    @Test func dddotDotsStayWhereKaTeXPutsThem() throws {
        // \dddot = \overset{\raisebox{-0.1ex}{\normalsize ...}}: limits and script-style units at
        // once. RaTeX's 0.08em padding had been tuned against exactly this.
        for dot in try glyphs(#"\dddot{x}"#).filter({ $0.char == "." }) {
            #expect(abs(dot.y - -0.5879) < tol)
        }
    }

    @Test func fractionIsAnOrd() throws {
        // A braced group is an Ord, so with \frac an Ord too both rows are spaced the same.
        for (bare, braced) in [
            (#"-\frac{a}{b}"#, #"-{\frac{a}{b}}"#),
            (#"a\frac{b}{c}"#, #"a{\frac{b}{c}}"#),
            (#"x=-\frac{\partial B}{\partial t}"#, #"x=-{\frac{\partial B}{\partial t}}"#),
        ] {
            let a = try SwaTexEngine.displayList(for: bare).width
            let b = try SwaTexEngine.displayList(for: braced).width
            #expect(abs(a - b) < 1e-6, "\(bare) is \(a) wide, \(braced) is \(b)")
        }
    }

    @Test func scriptStyleRelativeUnitsAreTextUnits() throws {
        // KaTeX: 1em in a superscript is one text em, the same as 10pt.
        #expect(abs(try glyph("a", in: #"x^{\kern1em a}"#).x - 1.5719) < tol)
        #expect(abs(try glyph("a", in: #"x^{\kern10pt a}"#).x - 1.5719) < tol)
    }
}
