// KaTeX's `tryCombineChars` (buildCommon.js): adjacent symbol nodes that would render as one span
// — same classes (and not a bare "mord" / "mbin"), skew, size and color — are merged, and the
// merged span keeps only the *last* character's italic correction. So `ff`, `PV`, `\mathrm{inf}`
// carry no correction between their letters, while `fx` (different skew) or `f^2` (a supsub) do.
// SwaTex adds the correction to every math glyph's width; these helpers take it back off where
// KaTeX would have combined. Kept out of the recursive layout functions on purpose: their frames
// are paid per nesting level (StackGuardTests).

/// What two adjacent glyphs must share to combine.
struct ItalicCombineKey: Equatable {
    var font: FontId
    var skew: Double
    var color: Color
}

/// The key of a glyph box whose width includes its italic correction, nil otherwise (text mode
/// and `\mathit` glyphs never carry one, so there is nothing to take back).
@inline(never)
func italicCombineKey(_ box: LayoutBox) -> ItalicCombineKey? {
    // A zero correction still links the run (`sgn`: the g's correction goes, though n has none).
    guard case let .glyph(fontId, charCode) = box.content, let m = glyphMetrics(fontId, charCode),
        abs(box.width - (m.width + m.italic)) < 1e-9
    else { return nil }
    return ItalicCombineKey(font: fontId, skew: m.skew, color: box.color)
}

/// The italic correction of a box that is a single glyph; 0 for anything else.
@inline(never)
func directGlyphItalic(_ box: LayoutBox) -> Double {
    guard case let .glyph(fontId, charCode) = box.content else { return 0 }
    return glyphMetrics(fontId, charCode)?.italic ?? 0
}

/// A letter in the default math font (KaTeX classes `mord mathnormal`). Digits and other
/// Main-Regular ords are a bare `mord` in KaTeX and never combine.
@inline(never)
func mathnormalCombineKey(_ node: ParseNode, _ box: LayoutBox) -> ItalicCombineKey? {
    guard node.mode == .math, case .mathOrd = node.kind, let key = italicCombineKey(box),
        key.font == .mathItalic
    else { return nil }
    return key
}

/// Run state for `appendCombiningItalics`.
struct ItalicCombineState {
    var index = -1
    var key: ItalicCombineKey?
}

/// `children.append(box)` for `layoutExpression`, taking back the previous child's italic
/// correction when it and `box` are mathnormal glyphs KaTeX would combine. One call instead of
/// inline code: `layoutExpression` is on the recursion path and its frame is paid per level.
@inline(never)
func appendCombiningItalics(
    _ box: LayoutBox, _ node: ParseNode, to children: inout [LayoutBox],
    _ state: inout ItalicCombineState
) {
    let key = mathnormalCombineKey(node, box)
    if let key, state.index == children.count - 1, state.key == key {
        dropItalicCorrection(&children[state.index])
    }
    state = ItalicCombineState(index: key == nil ? -1 : children.count, key: key)
    children.append(box)
}

/// Remove the italic correction a combined (non-final) glyph would not get in KaTeX.
@inline(never)
func dropItalicCorrection(_ box: inout LayoutBox) {
    if case let .glyph(fontId, charCode) = box.content, let m = glyphMetrics(fontId, charCode) {
        box.width -= m.italic
    }
}

/// Combine runs in a flat list: `keys[i]` is the key of `boxes[i]` or nil for anything that breaks
/// a run (kerns, non-symbol boxes, uncombinable classes).
@inline(never)
func dropCombinedItalicCorrections(_ boxes: inout [LayoutBox], keys: [ItalicCombineKey?]) {
    guard boxes.count > 1 else { return }
    for i in 0..<(boxes.count - 1) {
        if let k = keys[i], keys[i + 1] == k {
            dropItalicCorrection(&boxes[i])
        }
    }
}

private func glyphMetrics(_ fontId: FontId, _ charCode: UInt32) -> CharMetrics? {
    fontId.metrics(forChar: FontId.mathAlphanumeric(charCode)?.metric ?? charCode)
}
