#!/usr/bin/env node
// Position-level differential test: SwaTex vs KaTeX itself.
//
// `scripts/diff_layout.py` compares SwaTex against RaTeX, which SwaTex is a port of — a bug the
// two share (or one RaTeX introduced on purpose) passes it. This script compares against the
// reference implementation instead: KaTeX renders every formula to HTML, headless Chrome lays it
// out with the KaTeX fonts, and each glyph's pen position and baseline is read back with DOM
// ranges. SwaTex's `LayoutDump --glyphs` prints the same quantities from its display list.
// Both sides are in em, x from the formula's left edge, y relative to its baseline (down = +).
//
// Usage:
//   node katex_diff.mjs --layoutdump <LayoutDump binary> (--corpus <file> | --golden <dir>)
//                       [--tol 0.01] [--only <regex>] [--show 30] [--out report.json]
//                       [--chrome <path>]
//
//   --corpus  one formula per line            --golden  the *.jsonl golden files ("input" keys)
//   --tol     em; a formula passes when every glyph/rule and the box are within it
//   --only    keep formulas matching this regex
//   --dump-katex  also print KaTeX's own measurements (box, glyphs, rules) for every formula
//
// Left out: formulas with \tag (KaTeX pushes the tag to the far edge of the page, SwaTex sets it a
// quad after the body — a layout convention, not a metric) and \url / \href (KaTeX renders link
// text in its own way), and the numbered environments (equation / align / alignat / gather /
// multline): KaTeX draws their "(1)" with a CSS counter, which no DOM range can see. \html* is
// rendered with trust so KaTeX draws the content like SwaTex does.
//
// Exit status: 0 when every formula both engines accept is within tolerance, 1 otherwise.

import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, readdirSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import katex from "katex";
import "katex/contrib/mhchem"; // \ce / \pu, which SwaTex has built in

const here = dirname(fileURLToPath(import.meta.url));

// ── Arguments ──────────────────────────────────────────────────────────────

const args = process.argv.slice(2);
function opt(name, fallback) {
    const i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}
const layoutDump = opt("--layoutdump");
const corpusPath = opt("--corpus");
const goldenDir = opt("--golden");
const tol = Number(opt("--tol", "0.01"));
const only = opt("--only") ? new RegExp(opt("--only")) : null;
const show = Number(opt("--show", "30"));
const outPath = opt("--out");
const dumpKaTeX = args.includes("--dump-katex");
const chrome = opt("--chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
if (!layoutDump || (!corpusPath && !goldenDir)) {
    console.error("usage: katex_diff.mjs --layoutdump <bin> (--corpus <file> | --golden <dir>) [--tol 0.01] [--only re] [--show 30] [--out report.json]");
    process.exit(2);
}

// ── Corpus ─────────────────────────────────────────────────────────────────

let formulas = [];
if (corpusPath) {
    formulas = readFileSync(corpusPath, "utf8").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("%"));
} else {
    for (const f of readdirSync(goldenDir).filter((f) => f.endsWith(".jsonl")).sort()) {
        for (const line of readFileSync(join(goldenDir, f), "utf8").split("\n")) {
            if (line.trim()) formulas.push(JSON.parse(line).input);
        }
    }
}
// LayoutDump reads one formula per line.
const skipped = /\\tag\*?\{|\\url\{|\\href\{|\\begin\{(equation|align|alignat|gather|multline)\}/;
formulas = [...new Set(formulas.filter((t) => !t.includes("\n") && !skipped.test(t) && (!only || only.test(t))))];
console.log(`${formulas.length} formulas`);

// ── SwaTex side ────────────────────────────────────────────────────────────

const dump = spawnSync(layoutDump, ["--glyphs"], {
    input: formulas.join("\n") + "\n",
    maxBuffer: 1 << 30,
    encoding: "utf8",
});
if (dump.status !== 0) {
    console.error(dump.stderr);
    process.exit(2);
}
const swatex = new Map();
for (const line of dump.stdout.split("\n")) {
    if (line.trim()) {
        const r = JSON.parse(line);
        swatex.set(r.input, r);
    }
}

// ── KaTeX side ─────────────────────────────────────────────────────────────

const katexDist = join(here, "node_modules", "katex", "dist");
// Fonts go in as data URIs: a file:// page may not load file:// fonts (they need CORS).
const css = readFileSync(join(katexDist, "katex.min.css"), "utf8").replace(
    /src:url\(fonts\/([^)]+)\.woff2\) format\("woff2"\)[^;}]*/g,
    (_, name) => {
        const b64 = readFileSync(join(katexDist, "fonts", `${name}.woff2`)).toString("base64");
        return `src:url(data:font/woff2;base64,${b64}) format("woff2")`;
    },
);

const warn = console.warn;
console.warn = () => {}; // KaTeX's "No character metrics" chatter for strict: "ignore"
const rendered = formulas.map((tex) => {
    try {
        return {
            html: katex.renderToString(tex, {
                displayMode: true,
                output: "html",
                throwOnError: true,
                strict: "ignore",
                trust: true,
                macros: {},
            }),
        };
    } catch (e) {
        return { error: String(e.message ?? e) };
    }
});

console.warn = warn;

// Runs in the page. Reads, per formula: em size, box, every glyph's pen x and baseline y, rules.
function measure() {
    const probe = () => {
        const p = document.createElement("span");
        p.style.cssText = "display:inline-block;width:0;height:0;margin:0;padding:0;border:0";
        return p;
    };
    const out = [];
    for (const div of document.querySelectorAll("div.f")) {
        const i = Number(div.dataset.i);
        const k = div.querySelector(".katex");
        const html = k && k.querySelector(".katex-html");
        if (!html) continue;
        const em = parseFloat(getComputedStyle(k).fontSize);
        const origin = probe();
        html.insertBefore(origin, html.firstChild);

        // Pass 1: pen x of every character, before any probe can shift a layout.
        const walker = document.createTreeWalker(html, NodeFilter.SHOW_TEXT);
        const nodes = [];
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
            if (n.parentElement.closest("svg") || !n.data.length) continue;
            const cs = getComputedStyle(n.parentElement);
            const family = cs.fontFamily.split(",")[0].replace(/["']/g, "").trim();
            const range = document.createRange();
            const chars = [];
            let off = 0;
            for (const ch of n.data) {
                range.setStart(n, off);
                range.setEnd(n, off + ch.length);
                const r = range.getClientRects()[0] || range.getBoundingClientRect();
                chars.push({ ch: ch.codePointAt(0), left: r.left });
                off += ch.length;
            }
            nodes.push({
                n, chars, family,
                italic: cs.fontStyle === "italic",
                bold: Number(cs.fontWeight) >= 600 || cs.fontWeight === "bold",
                size: parseFloat(cs.fontSize),
            });
        }
        // Pass 2: one zero-size probe after each text node sits on its baseline.
        for (const t of nodes) {
            t.probe = probe();
            t.n.parentNode.insertBefore(t.probe, t.n.nextSibling);
        }
        const o = origin.getBoundingClientRect();
        const glyphs = [];
        for (const t of nodes) {
            const base = t.probe.getBoundingClientRect().top;
            for (const c of t.chars) {
                glyphs.push({
                    ch: c.ch, family: t.family, italic: t.italic, bold: t.bold,
                    x: (c.left - o.left) / em, y: (base - o.top) / em, s: t.size / em,
                });
            }
        }
        const rules = [];
        for (const r of html.querySelectorAll(".frac-line, .overline-line, .underline-line, .hline, .hdashline")) {
            const b = r.getBoundingClientRect();
            if (b.width === 0) continue;
            rules.push({ x: (b.left - o.left) / em, y: (b.top + b.height / 2 - o.top) / em, w: b.width / em, t: b.height / em });
        }
        let height = 0, depth = 0, right = o.left;
        for (const base of html.querySelectorAll(":scope > .base")) {
            const strut = base.querySelector(":scope > .strut");
            if (strut) {
                const total = parseFloat(strut.style.height) || 0;
                const d = -(parseFloat(strut.style.verticalAlign) || 0);
                height = Math.max(height, total - d);
                depth = Math.max(depth, d);
            }
            right = Math.max(right, base.getBoundingClientRect().right);
        }
        out.push({ i, width: (right - o.left) / em, height, depth, glyphs, rules });
        for (const t of nodes) t.probe.remove();
        origin.remove();
    }
    return out;
}

const page = `<!doctype html><meta charset="utf-8"><style>${css}
body{margin:0;width:100000px} div.f{font-size:40px;margin:0}</style>
<body>${rendered.map((r, i) => (r.html ? `<div class="f" data-i="${i}">${r.html}</div>` : "")).join("\n")}
<pre id="out"></pre>
<script>
${measure.toString()}
(async () => {
  document.body.offsetHeight;          // lay out once so every face is requested
  await document.fonts.ready;
  const json = JSON.stringify(measure());
  document.getElementById("out").textContent = btoa(unescape(encodeURIComponent(json)));
})();
</script>`;

const work = mkdtempSync(join(tmpdir(), "katex-diff-"));
writeFileSync(join(work, "page.html"), page);
const run = spawnSync(chrome, [
    "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
    `--user-data-dir=${join(work, "profile")}`, "--virtual-time-budget=600000",
    "--dump-dom", pathToFileURL(join(work, "page.html")).href,
], { maxBuffer: 1 << 30, encoding: "utf8", timeout: 900_000 });
const m = /<pre id="out">([^<]*)<\/pre>/.exec(run.stdout ?? "");
rmSync(work, { recursive: true, force: true });
if (!m || !m[1]) {
    console.error("headless Chrome produced no measurements", run.stderr?.slice(-2000));
    process.exit(2);
}
const katexById = new Map(JSON.parse(Buffer.from(m[1], "base64").toString("utf8")).map((r) => [r.i, r]));

if (dumpKaTeX) {
    for (const [i, tex] of formulas.entries()) {
        const k = katexById.get(i);
        if (!k) continue;
        const r4 = (v) => Math.round(v * 1e4) / 1e4;
        console.log(`KaTeX ${tex}\n  box w ${r4(k.width)} h ${r4(k.height)} d ${r4(k.depth)}`);
        for (const g of k.glyphs.filter((g) => ![0x20, 0xa0, 0x200b].includes(g.ch))) {
            console.log(`  ${String.fromCodePoint(g.ch)} x ${r4(g.x)} y ${r4(g.y)} size ${r4(g.s)}`);
        }
        for (const r of k.rules) console.log(`  rule x ${r4(r.x)} y ${r4(r.y)} w ${r4(r.w)}`);
    }
}

// ── Compare ────────────────────────────────────────────────────────────────

// Characters KaTeX's DOM carries that draw nothing: spaces (\text, \ ), the U+200B it puts in every
// vlist for Safari, and NBSP.
const invisible = new Set([0x20, 0xa0, 0x200b]);
// Glyphs SwaTex draws as font glyphs where KaTeX draws an SVG (surds): not missing on KaTeX's side.
const svgInKaTeX = new Set([0x221a]);

// KaTeX CSS family + style → SwaTex FontId raw value.
function fontId(g) {
    const f = g.family.replace(/^KaTeX_/, "");
    if (f === g.family) return "other";
    switch (f) {
        case "Main": return `Main-${g.bold && g.italic ? "BoldItalic" : g.bold ? "Bold" : g.italic ? "Italic" : "Regular"}`;
        case "Math": return g.bold ? "Math-BoldItalic" : "Math-Italic";
        case "SansSerif": return `SansSerif-${g.bold ? "Bold" : g.italic ? "Italic" : "Regular"}`;
        case "Caligraphic": case "Fraktur": return `${f}-${g.bold ? "Bold" : "Regular"}`;
        default: return `${f}-Regular`; // AMS, Script, Size1-4, Typewriter
    }
}

const round = (v) => Math.round(v * 1e4) / 1e4;
const results = [];
for (const [i, tex] of formulas.entries()) {
    const s = swatex.get(tex);
    const k = katexById.get(i);
    const kErr = rendered[i].error;
    const sErr = !s || s.error;
    if (kErr || sErr || !k) {
        const status = kErr && sErr ? "both-error" : kErr ? "katex-error" : sErr ? "swatex-error" : "unmeasured";
        results.push({ tex, status, katexError: kErr, swatexError: s?.message });
        continue;
    }
    const issues = [];
    let worst = 0;
    const note = (what, d) => {
        worst = Math.max(worst, Math.abs(d));
        if (Math.abs(d) > tol) issues.push(`${what} ${d > 0 ? "+" : ""}${round(d)}`);
    };
    note("width", s.displayList.width - k.width);
    note("height", s.displayList.height - k.height);
    note("depth", s.displayList.depth - k.depth);

    const unused = s.glyphs.map((g) => ({ ...g, used: false }));
    let unmatched = 0, fontMismatch = 0;
    for (const g of k.glyphs.filter((g) => !invisible.has(g.ch)).sort((a, b) => a.x - b.x || a.y - b.y)) {
        let best = null, bestD = Infinity;
        for (const c of unused) {
            if (c.used || (c.t !== g.ch && c.c !== g.ch)) continue;
            const d = Math.hypot(c.x - g.x, c.y - g.y);
            if (d < bestD) { best = c; bestD = d; }
        }
        const label = String.fromCodePoint(g.ch);
        if (!best) { unmatched++; issues.push(`glyph ${label} missing in SwaTex`); continue; }
        best.used = true;
        note(`glyph ${label} x`, best.x - g.x);
        note(`glyph ${label} y`, best.y - g.y);
        note(`glyph ${label} size`, best.s - g.s);
        const kf = fontId(g);
        if (kf !== "other" && kf !== best.f) { fontMismatch++; issues.push(`glyph ${label} font ${best.f} vs KaTeX ${kf}`); }
    }
    for (const c of unused.filter((c) => !c.used && !svgInKaTeX.has(c.c) && !invisible.has(c.c))) {
        unmatched++;
        issues.push(`glyph ${String.fromCodePoint(c.c)} only in SwaTex`);
    }
    const ruleLeft = [...s.rules];
    for (const r of k.rules) {
        let bi = -1, bd = Infinity;
        ruleLeft.forEach((c, j) => { const d = Math.hypot(c.x - r.x, c.y - r.y); if (d < bd) { bd = d; bi = j; } });
        if (bi < 0) { unmatched++; issues.push("rule missing in SwaTex"); continue; }
        const c = ruleLeft.splice(bi, 1)[0];
        note("rule x", c.x - r.x);
        note("rule y", c.y - r.y);
        note("rule width", c.w - r.w);
    }
    // SwaTex draws some KaTeX borders/SVG pieces as lines; only missing rules count against it.
    const ok = issues.length === 0;
    results.push({ tex, status: ok ? "ok" : "diff", worst: round(worst), unmatched, fontMismatch, issues });
}

// ── Report ─────────────────────────────────────────────────────────────────

const count = (st) => results.filter((r) => r.status === st).length;
const compared = results.filter((r) => r.status === "ok" || r.status === "diff");
console.log(
    `compared ${compared.length}: ok ${count("ok")} · diff ${count("diff")}` +
    ` | both-error ${count("both-error")} · katex-only-error ${count("katex-error")}` +
    ` · swatex-only-error ${count("swatex-error")} · unmeasured ${count("unmeasured")}  (tol ${tol} em)`,
);
const diffs = results.filter((r) => r.status === "diff").sort((a, b) => b.worst - a.worst);
for (const r of diffs.slice(0, show)) {
    console.log(`  ${String(r.worst).padStart(7)}  ${r.tex}\n           ${r.issues.slice(0, 6).join(" · ")}${r.issues.length > 6 ? ` · …(${r.issues.length})` : ""}`);
}
for (const r of results.filter((r) => r.status === "swatex-error").slice(0, show)) {
    console.log(`  swatex-only error: ${r.tex}  — ${r.swatexError}`);
}
if (outPath) writeFileSync(outPath, JSON.stringify({ tol, results }, null, 1));
process.exit(diffs.length === 0 ? 0 : 1);
