// Differential-testing CLI: reads LaTeX formulas from stdin (one per line) and
// prints layout metrics as JSON — the exact counterpart of RaTeX's
// `cargo run --bin layout`, used to diff the two engines.
//
// `--glyphs` additionally prints every glyph and rule of the display list
// (em units, x from the left edge, y relative to the baseline, positive down),
// for `scripts/katex_diff` — a position-level diff against KaTeX itself.

import Foundation
import SwaTex

func round5(_ v: Double) -> Double {
    (v * 100000).rounded() / 100000
}

func jsonString(_ s: String) -> String {
    var out = "\""
    for ch in s.unicodeScalars {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if ch.value < 0x20 {
                out += String(format: "\\u%04x", ch.value)
            } else {
                out.unicodeScalars.append(ch)
            }
        }
    }
    return out + "\""
}

func glyphsJSON(_ list: DisplayList) -> String {
    var glyphs: [String] = []
    var rules: [String] = []
    for item in list.items {
        switch item {
        case let .glyphPath(x, y, scale, font, charCode, _):
            let fontId = FontId(rawValue: font) ?? .mainRegular
            let ttf = fontId.ttfGlyphScalar(forDisplayCharCode: charCode).value
            glyphs.append(
                "{\"c\":\(charCode),\"t\":\(ttf),\"f\":\(jsonString(font)),"
                    + "\"x\":\(round5(x)),\"y\":\(round5(y - list.height)),\"s\":\(round5(scale))}")
        case let .line(x, y, width, thickness, _, _):
            rules.append(
                "{\"x\":\(round5(x)),\"y\":\(round5(y - list.height)),\"w\":\(round5(width)),\"t\":\(round5(thickness))}"
            )
        case .rect, .path:
            break
        }
    }
    return
        ",\"glyphs\":[\(glyphs.joined(separator: ","))],\"rules\":[\(rules.joined(separator: ","))]"
}

let dumpGlyphs = CommandLine.arguments.contains("--glyphs")

while let line = readLine(strippingNewline: true) {
    let expr = line.trimmingCharacters(in: .whitespaces)
    if expr.isEmpty { continue }

    do {
        let ast = try parseLaTeX(expr)
        let options = LayoutOptions()
        let lbox = layout(ast, options: options)
        let displayList = toDisplayList(lbox)

        print(
            "{\"input\":\(jsonString(expr)),"
                + "\"box\":{\"width\":\(round5(lbox.width)),\"height\":\(round5(lbox.height)),\"depth\":\(round5(lbox.depth))},"
                + "\"displayList\":{\"width\":\(round5(displayList.width)),\"height\":\(round5(displayList.height)),\"depth\":\(round5(displayList.depth)),\"itemCount\":\(displayList.items.count)}"
                + (dumpGlyphs ? glyphsJSON(displayList) : "") + "}"
        )
    } catch {
        print(
            "{\"error\":true,\"message\":\(jsonString("\(error)")),\"input\":\(jsonString(expr))}")
    }
}
