# ag-math-render

Render LaTeX math formulas in [Antigravity AI IDE](https://antigravity.dev) chat — with just **2 files** and zero bloat.

<p align="center">
  <strong>Before</strong>: <code>$x^2 + y^2 = z^2$</code> shown as plain text<br/>
  <strong>After</strong>: Beautifully rendered math formulas ✨
</p>

## Features

- **Inline math**: `$e^{i\pi} + 1 = 0$` → rendered inline
- **Display math**: `$$\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}$$` → centered block
- **Streaming-aware**: Renders correctly as AI types in real-time
- **Update-resilient**: Zero dependency on Antigravity's CSS class names
- **Offline**: KaTeX bundled locally, no CDN needed
- **Tiny**: ~1.5MB total (mostly KaTeX fonts)

## How It Works

1. `install.sh` copies KaTeX + our script into the Antigravity app bundle
2. Static `<script>` tags are injected into `workbench.html` (bypassing Trusted Types CSP)
3. A `MutationObserver` watches the entire DOM for new text containing `$...$` or `$$...$$`
4. Matched text is rendered in-place with [KaTeX](https://katex.org/)

No Antigravity-internal CSS classes are referenced, so class name changes in updates won't break it.

## Install

```bash
git clone https://github.com/chihao-zhang/ag-math-render.git
cd ag-math-render
bash install.sh
```

Then **restart Antigravity** (Cmd+Q → reopen).

### Custom Install Path

```bash
bash install.sh /path/to/Antigravity.app
```

### After Antigravity Updates

Antigravity updates replace the patched files. Simply re-run:

```bash
bash install.sh
```

## Uninstall

```bash
bash uninstall.sh
```

Then restart Antigravity.

## Supported Syntax

| Syntax | Type | Status |
|--------|------|--------|
| `$...$` | Inline | ✅ Works |
| `$$...$$` | Display (block) | ✅ Works |
| `\(...\)` | Inline | ⚠️ Unreliable* |
| `\[...\]` | Display | ⚠️ Unreliable* |

\* *Antigravity's Markdown renderer treats `\(` and `\[` as escape sequences and strips the backslash before our script sees the DOM. This is a fundamental limitation of any DOM-based approach. Use `$` / `$$` instead.*

## Project Structure

```
ag-math-render/
├── install.sh          # One-command installer
├── uninstall.sh        # One-command uninstaller
├── payload/
│   ├── math-patch.js   # Core rendering logic (~240 lines)
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

## Comparison with anti-power

| | anti-power | ag-math-render |
|---|---|---|
| Features | 6 (math + mermaid + copy + font + width + table) | 1 (math) |
| Install tool | Tauri desktop app (Rust + frontend) | Shell script |
| Code size | ~3500 lines | ~240 lines |
| DOM targeting | 3 hardcoded CSS classes | Zero class dependencies |
| KaTeX loading | Dynamic (Trusted Types workaround) | Static (no workaround needed) |
| Update resilience | Low (3 fragility points) | High (1 fragility point) |

## Requirements

- macOS (Linux/Windows: adjust paths in `install.sh`)
- Antigravity AI IDE
- Python 3 (for checksum removal — pre-installed on macOS)

## License

MIT
