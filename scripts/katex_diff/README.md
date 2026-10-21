# katex_diff — SwaTex against KaTeX, glyph by glyph

`scripts/diff_layout.py` compares SwaTex with RaTeX, the engine it was ported from. That catches
porting slips, but not a bug the two share. This tool compares with **KaTeX itself**:

1. KaTeX 0.16.22 (pinned in `package.json`) renders every formula to HTML, display mode.
2. Headless Chrome lays the page out with the KaTeX fonts (inlined as data URIs).
3. A script in the page reads, per formula, each character's pen x (DOM `Range` rects) and its
   baseline (a zero-size inline-block probe after each text node), the fraction / over / under /
   `\hline` rules, and the box from the `.strut`s.
4. `LayoutDump --glyphs` prints the same quantities from SwaTex's display list.
5. Glyphs are paired by character (nearest position), and everything is compared in em:
   x from the formula's left edge, y relative to the baseline.

```sh
cd scripts/katex_diff && npm install
swift build -c release --product LayoutDump
node katex_diff.mjs --layoutdump ../../.build/release/LayoutDump --corpus corpus.txt
node katex_diff.mjs --layoutdump ../../.build/release/LayoutDump \
    --golden ../../Tests/SwaTexTests/Resources/golden --show 40 --out /tmp/report.json
```

`--tol` (em, default 0.01), `--only <regex>`, `--show <n>` (worst diffs to print), `--out` (full JSON
report), `--dump-katex` (print KaTeX's own box, glyph and rule positions — where the numbers in
`KaTeXAlignmentTests` / `KaTeXSpacingTests` come from). Exit status 1 when any compared formula is
out of tolerance.

## What it cannot see

- `\tag`, `\url` / `\href` and the numbered environments (`equation`, `align`, `alignat`, `gather`,
  `multline`) are left out: KaTeX draws equation numbers with a CSS counter and pushes tags to the
  page edge, neither of which is a glyph position.
- Ink drawn as SVG on one side and glyphs on the other (KaTeX's surds, stretchy arrows, some stacked
  delimiters) only shows up through the box and the glyphs around it.
- Content that starts left of the origin (`\llap`, negative kerns) is measured from KaTeX's first
  `.base`; a few such formulas show a uniform x offset that is a convention, not a layout error.

## Baseline (golden corpora, 2026-10-21, tol 0.01 em)

| | compared | within tol | out of tol |
|---|---|---|---|
| SwaTex 0.5.0 | 2149 | 1460 | 689 |
| + aligned column gaps + null delimiters (0.5.0-vectorshop.1) | 2149 | 1488 | 661 |
| + operator-limit kerns, `\frac` as Ord, script-style units (0.5.0-vectorshop.2) | 2149 | 1525 | 624 |
| + italic-correction runs, upright `\operatorname*`, `\mathit` / font-group atoms | 2149 | 1580 | 569 |

The hand-picked `corpus.txt` (textbook formulas and every array environment): 12 → 21 → 25 of 27.
No formula got further from KaTeX at any step.

Remaining out-of-tolerance formulas, roughly grouped (not yet triaged; some may be measurement
artifacts): mhchem · rules only (`\hline` / fraction line y, ~0.02 em) · font choice
(symbols KaTeX takes from another face) · CD · `\varinjlim` / `\varprojlim` limits 0.26 em low ·
`\text` with accents / unicode · `\mathop{X}_a^b` and `\mathclap` under limits · stacked
delimiters · `\rule{1ex}` in a superscript 0.0175 em too wide.
