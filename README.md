# ag-math-render

> [!IMPORTANT]
> **📦 Archived — May 2026**
>
> Antigravity 2.0 shipped native LaTeX math rendering, making this project unnecessary.
> The code remains here as a reference for anyone interested in Electron app patching,
> KaTeX integration under Trusted Types CSP, or Markdown↔LaTeX conflict resolution.
>
> It was a good run. Zero stars, one happy user. 🫡

---

Render LaTeX math formulas in [Antigravity AI IDE](https://antigravity.google/) chat — with just **2 files** and zero bloat.

<p align="center">
  <strong>Before</strong>: <code>$x^2 + y^2 = z^2$</code> shown as plain text<br/>
  <strong>After</strong>: Beautifully rendered math formulas ✨
</p>

## What This Project Solved

Antigravity 1.x had no math rendering. Worse, its Markdown parser actively **destroyed** LaTeX syntax:

| Problem | Example | How We Fixed It |
|---------|---------|-----------------|
| `_` parsed as emphasis | `$x_{ij}$` → `$x<em>ij</em>$` | `restoreUnderscores`: unwrap `<em>` inside math regions |
| `*` paired across `$` boundaries | `$f^*$ text $V^*$` → cross-boundary `<em>` | 3-rule heuristic (^, {, *) to distinguish `*` from `_` |
| `|` splits table cells | `$|\Omega|^2$` in table → 3 cells | `repairBrokenTableMath`: $-parity greedy merge |
| `**"text"**` not bold | Unicode punctuation breaks CommonMark flanking | `fixLiteralBold`: regex scan + `<strong>` wrap |
| `$)` false positive | `($ \tau < t $)` → stray `$)` opens math | `findOpen` rejects `$` followed by `)`, `]`, `}` |
| `{}` set vs grouping | `$\{x\}$` → `${x}$` | `recoverBraces`: context-aware classifier with 30+ LaTeX commands |

## Features

- **Inline math**: `$e^{i\pi} + 1 = 0$` → rendered inline
- **Display math**: `$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$` → centered block
- **Streaming-aware**: Renders correctly as AI types in real-time
- **Update-resilient**: Zero dependency on Antigravity's CSS class names
- **Offline**: KaTeX bundled locally, no CDN needed
- **Tiny**: ~1.5MB total (mostly KaTeX fonts)

## How It Worked

1. `install.sh` copies KaTeX + our script into the Antigravity app bundle
2. Static `<script>` tags are injected into `workbench.html` (bypassing Trusted Types CSP)
3. A `MutationObserver` watches the entire DOM for new text containing `$...$` or `$$...$$`
4. Matched text is rendered in-place with [KaTeX](https://katex.org/)

> **Note**: Antigravity 2.0 replaced the VS Code-based architecture with a web SPA served
> from a local HTTPS server. The `workbench.html` injection target no longer exists.

## Project Structure

```
ag-math-render/
├── install.sh          # One-command installer (v1.x only)
├── uninstall.sh        # One-command uninstaller
├── payload/
│   ├── math-patch.js   # Core rendering logic (~780 lines)
│   └── katex/          # KaTeX v0.16.21 (local bundle)
│       ├── katex.min.js
│       ├── katex.min.css
│       └── fonts/
├── README.md
└── LICENSE
```

## Technical Details

### Why static `<script>` tags instead of dynamic loading?

Antigravity enforces [Trusted Types](https://developer.mozilla.org/en-US/docs/Web/API/Trusted_Types_API) via CSP. Setting `script.src` dynamically requires a `TrustedScriptURL`, which we can't create without hijacking an existing policy name. Static `<script>` tags in HTML are parsed by the browser's HTML parser, which is exempt from Trusted Types. Problem eliminated.

### Why bundle KaTeX locally?

Antigravity's CSP restricts `script-src` to `'self'`. By placing KaTeX inside the app bundle, it counts as `'self'` — zero CSP changes needed.

### Why wrap KaTeX with AMD suspension?

Antigravity uses an AMD module loader (`define`/`require`). KaTeX's UMD wrapper detects `define.amd` and registers as an AMD module instead of setting `window.katex`. Our install script wraps `katex.min.js` to temporarily hide `define.amd` during load.

### Why `document.body` instead of a specific selector?

Projects like [anti-power](https://github.com/daoif/anti-power) target specific CSS classes like `.antigravity-agent-side-panel`. These break every time Antigravity updates its UI. We observe the entire `document.body` subtree, making us immune to class name changes.

### The Emphasis Restoration Problem

The hardest problem was distinguishing Markdown emphasis from LaTeX operators. When Markdown sees `$f^*$ text **bold $V^*$**`, it pairs the `*` characters as emphasis across `$` boundaries, destroying the math. Our final solution (after 10+ iterations) was a 3-rule heuristic:

```
isAsterisk = beforeChar ∈ {'^', '{', '*'}
```

This covers `x^*` (superscript star), `\xrightarrow{*}` (brace star), and `p^{**}` (double star) — the only positions where `*` unambiguously appears in LaTeX math.

## Acknowledgments

This project was inspired by [anti-power](https://github.com/daoif/anti-power), which first solved the math rendering problem for Antigravity. We learned several key lessons from studying their implementation:

- **Trusted Types are the real barrier** — not CSP `script-src`. Anti-power discovered that `require-trusted-types-for 'script'` blocks dynamic script injection, and built an elaborate policy-hijacking mechanism to work around it. We found a simpler path: static `<script>` tags bypass Trusted Types entirely.
- **AMD loader conflicts with KaTeX** — anti-power's `suspendAmd()` pattern taught us that `window.define.amd` must be hidden during KaTeX load. We adopted the same idea but applied it at install time (wrapping the JS file) rather than at runtime.
- **`katex.render()` is Trusted Types-safe** — anti-power's `math.js` showed that KaTeX's `render()` method uses DOM APIs directly, so it works under Trusted Types without any workaround.
- **`product.json` checksum clearing** — anti-power identified the exact checksum keys that must be removed to prevent Antigravity from reporting file corruption.

Thank you to the anti-power contributors for mapping the terrain. 🙏

## Timeline

- **2026-04-13** — Project created. First working prototype: KaTeX injection via static `<script>` tags.
- **2026-04-24** — Fixed `$f^*$` rendering as `f^_` (asterisk vs underscore disambiguation).
- **2026-04-25** — Fixed `$\xrightarrow{*}$` (extended heuristic to `{` context).
- **2026-05-05** — Fixed cross-boundary emphasis, table `|` splitting, CommonMark bold edge cases. Major brace recovery engine added.
- **2026-05-13** — First-principles redesign: 8-rule heuristic → 3-rule heuristic.
- **2026-05-14** — Fixed `findOpen` false positive for `$)` patterns.
- **2026-05-20** — Antigravity 2.0 ships native math rendering. Project archived. 🫡

## License

MIT

---

<p align="center">
  <em>Built by Forge 🔨 from Bamboo Grove 🎋<br/>
  Powered by Antigravity + Claude Opus 4.6<br/><br/>
  Zero stars. One user. No regrets.</em>
</p>
