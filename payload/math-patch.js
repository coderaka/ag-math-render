/**
 * ag-math-render — LaTeX Math Rendering for Antigravity AI IDE
 *
 * Watches the entire DOM for new text containing LaTeX delimiters
 * and renders them with KaTeX. Zero dependency on Antigravity's
 * internal CSS class names for maximum update resilience.
 *
 * KaTeX is loaded via static <script> tags in the HTML (injected
 * by install.sh), avoiding Trusted Types CSP restrictions entirely.
 *
 * Supported delimiters:
 *   - Inline:  $...$  or \(...\)
 *   - Display: $$...$$ or \[...\]
 *
 * @license MIT
 */

(() => {
    'use strict';

    // ── Configuration ──────────────────────────────────────────────

    const RENDERED_ATTR = 'data-math-rendered';
    const SNAPSHOT_PROP = Symbol('mathTextSnapshot');

    // Quick test: does text likely contain math?
    const MATH_HINT = /\$\$|\\\(|\\\[|\$(?!\s)([^$\n]+?)\$/;

    // Delimiters in priority order (longer match first)
    const DELIMITERS = [
        { left: '$$',   right: '$$',   display: true  },
        { left: '\\[',  right: '\\]',  display: true  },
        { left: '\\(',  right: '\\)',  display: false },
        { left: '$',    right: '$',    display: false },
    ];

    // Elements to skip (code blocks, already-rendered math)
    const SKIP_SELECTOR = 'pre, code, .code-block, .katex, .katex-display, ' +
        'mjx-container, .math-rendered-inline, .math-rendered-display';

    let observer = null;

    // ── Delimiter Parsing ──────────────────────────────────────────

    function isEscaped(text, idx) {
        let count = 0;
        for (let i = idx - 1; i >= 0 && text[i] === '\\'; i--) count++;
        return count % 2 === 1;
    }

    function findOpen(text, pos) {
        let best = null;
        for (const d of DELIMITERS) {
            const idx = text.indexOf(d.left, pos);
            if (idx === -1) continue;
            if (isEscaped(text, idx)) continue;
            // For single $: next char must not be whitespace
            if (d.left === '$' && text[idx + 1] && /\s/.test(text[idx + 1])) continue;
            if (!best || idx < best.index ||
                (idx === best.index && d.left.length > best.delim.left.length)) {
                best = { index: idx, delim: d };
            }
        }
        return best;
    }

    function findClose(text, start, delim) {
        let idx = text.indexOf(delim.right, start);
        while (idx !== -1) {
            if (!isEscaped(text, idx)) {
                if (delim.right === '$') {
                    if (text[idx - 1] && /\s/.test(text[idx - 1])) {
                        idx = text.indexOf(delim.right, idx + 1);
                        continue;
                    }
                    if (text[idx + 1] === '$') {
                        idx = text.indexOf(delim.right, idx + 1);
                        continue;
                    }
                }
                return idx;
            }
            idx = text.indexOf(delim.right, idx + delim.right.length);
        }
        return -1;
    }

    function tokenize(text) {
        const tokens = [];
        let pos = 0;

        while (pos < text.length) {
            const open = findOpen(text, pos);
            if (!open) {
                tokens.push({ type: 'text', data: text.slice(pos) });
                break;
            }
            if (open.index > pos) {
                tokens.push({ type: 'text', data: text.slice(pos, open.index) });
            }
            const mathStart = open.index + open.delim.left.length;
            const closeIdx = findClose(text, mathStart, open.delim);
            if (closeIdx === -1) {
                tokens.push({ type: 'text', data: text.slice(open.index) });
                break;
            }
            tokens.push({
                type: 'math',
                data: text.slice(mathStart, closeIdx),
                display: open.delim.display,
                rawLeft: open.delim.left,
                rawRight: open.delim.right,
            });
            pos = closeIdx + open.delim.right.length;
        }
        return tokens;
    }

    // ── Underscore Restoration ─────────────────────────────────────
    // Markdown renders _x_ as <em>x</em> inside $...$, breaking LaTeX.

    function restoreUnderscores(el) {
        if (!el || shouldSkipElement(el)) return;
        let restored = false;
        let seg = [];

        function flush() {
            if (!seg.length) return;
            const hasFormat = seg.some(u => u.type === 'format');
            if (!hasFormat) { seg = []; return; }

            let merged = '';
            let cursor = 0;
            seg.forEach(u => { u.start = cursor; merged += u.text; cursor += u.text.length; u.end = cursor; });

            if (!merged.includes('$')) { seg = []; return; }

            const ranges = [];
            let p = 0;
            while (p < merged.length) {
                const o = findOpen(merged, p);
                if (!o) break;
                const s = o.index + o.delim.left.length;
                const c = findClose(merged, s, o.delim);
                if (c === -1) { p = s; continue; }
                ranges.push({ start: s, end: c });
                p = c + o.delim.right.length;
            }
            if (!ranges.length) { seg = []; return; }

            seg.forEach(u => {
                if (u.type !== 'format') return;
                const inside = ranges.some(r => u.start >= r.start && u.end <= r.end);
                if (!inside) return;
                u.node.replaceWith(document.createTextNode(`${u.marker}${u.text}${u.marker}`));
                restored = true;
            });
            seg = [];
        }

        for (const child of Array.from(el.childNodes)) {
            if (child.nodeType === Node.TEXT_NODE) {
                if (shouldSkipText(child)) { flush(); continue; }
                const t = child.textContent || '';
                if (!t) { flush(); continue; }
                seg.push({ type: 'text', text: t });
            } else if (child.nodeType === Node.ELEMENT_NODE) {
                if (shouldSkipElement(child)) { flush(); continue; }
                const tag = child.tagName.toLowerCase();
                if (tag === 'em' || tag === 'strong') {
                    const t = child.textContent || '';
                    if (!t) { flush(); continue; }
                    seg.push({ type: 'format', node: child, text: t, marker: tag === 'strong' ? '__' : '_' });
                } else {
                    flush();
                    restoreUnderscores(child);
                }
            } else {
                flush();
            }
        }
        flush();
        if (restored) el.normalize();
    }

    // ── Skip Logic ─────────────────────────────────────────────────

    function shouldSkipText(node) {
        const p = node.parentElement;
        return !p || !!p.closest(SKIP_SELECTOR);
    }

    function shouldSkipElement(node) {
        return !node || !!node.closest(SKIP_SELECTOR);
    }

    // ── Rendering ──────────────────────────────────────────────────

    function renderElement(el) {
        restoreUnderscores(el);

        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        const textNodes = [];
        let n;
        while ((n = walker.nextNode())) {
            if (shouldSkipText(n)) continue;
            if (!n.textContent || !MATH_HINT.test(n.textContent)) continue;
            textNodes.push(n);
        }

        for (const textNode of textNodes) {
            const tokens = tokenize(textNode.textContent || '');
            if (tokens.length === 1 && tokens[0].type === 'text') continue;

            const frag = document.createDocumentFragment();
            for (const tok of tokens) {
                if (tok.type === 'text') {
                    if (tok.data) frag.appendChild(document.createTextNode(tok.data));
                    continue;
                }
                const span = document.createElement('span');
                span.className = tok.display ? 'math-rendered-display' : 'math-rendered-inline';
                try {
                    window.katex.render(tok.data, span, {
                        displayMode: tok.display,
                        throwOnError: false,
                        trust: true,
                    });
                } catch {
                    span.textContent = `${tok.rawLeft}${tok.data}${tok.rawRight}`;
                }
                frag.appendChild(span);
            }
            textNode.replaceWith(frag);
        }
    }

    function processNode(node) {
        if (!node || node.nodeType !== Node.ELEMENT_NODE) return;
        if (shouldSkipElement(node)) return;

        const text = node.textContent || '';
        if (node.hasAttribute(RENDERED_ATTR) && node[SNAPSHOT_PROP] === text) return;
        if (!MATH_HINT.test(text)) return;

        if (!window.katex?.render) {
            // KaTeX not available — should not happen with static loading
            console.warn('[ag-math] KaTeX not found on window.katex');
            return;
        }

        try {
            renderElement(node);
            node.setAttribute(RENDERED_ATTR, '1');
            node[SNAPSHOT_PROP] = node.textContent || '';
        } catch (err) {
            console.warn('[ag-math] Render error:', err);
            node.removeAttribute(RENDERED_ATTR);
        }
    }

    // ── DOM Observation ────────────────────────────────────────────

    let pending = new Set();
    let scheduled = false;

    function flushPending() {
        scheduled = false;
        const nodes = [...pending];
        pending.clear();
        for (const n of nodes) {
            if (n.isConnected) processNode(n);
        }
    }

    function enqueue(node) {
        if (!node) return;
        let target = node;
        if (target.nodeType === Node.TEXT_NODE) target = target.parentElement;
        if (!target) return;

        pending.add(target);
        if (!scheduled) {
            scheduled = true;
            requestAnimationFrame(flushPending);
        }
    }

    function startObserver() {
        observer = new MutationObserver((mutations) => {
            for (const m of mutations) {
                if (m.type === 'characterData' && m.target.parentElement) {
                    enqueue(m.target.parentElement);
                }
                for (const node of m.addedNodes) {
                    enqueue(node);
                }
            }
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true,
            characterData: true,
        });

        console.log('[ag-math] Observer started on document.body');
    }

    // ── Styles ─────────────────────────────────────────────────────

    function injectStyles() {
        const style = document.createElement('style');
        style.textContent = `
            .math-rendered-display {
                display: block;
                text-align: center;
                margin: 0.8em 0;
                overflow-x: auto;
            }
            .math-rendered-inline {
                display: inline;
            }
        `;
        document.head.appendChild(style);
    }

    // ── Init ───────────────────────────────────────────────────────

    function init() {
        if (!window.katex?.render) {
            console.error('[ag-math] KaTeX not loaded! Check that katex.min.js is in the HTML.');
            return;
        }
        injectStyles();
        startObserver();
        console.log('[ag-math] Math rendering patch loaded (v1.1.0)');
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init, { once: true });
    } else {
        init();
    }
})();
