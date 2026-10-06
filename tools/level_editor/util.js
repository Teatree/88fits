// Small helpers shared by every part of the Level Editor (pass 53): element builders, time formatting, JSON helpers.
'use strict';

const U = (() => {
  const SVG_NS = 'http://www.w3.org/2000/svg';

  /** An HTML element. attrs: class, text, html, title, style (string), on<event> handlers, dataset (object), anything else
   *  as an attribute; children may be nodes, strings or arrays (null skipped). */
  function el(tag, attrs, ...children) {
    const e = document.createElement(tag);
    applyAttrs(e, attrs, false);
    appendAll(e, children);
    return e;
  }

  /** An SVG element (same attribute rules; `href` works on <use> and <image>). */
  function svg(tag, attrs, ...children) {
    const e = document.createElementNS(SVG_NS, tag);
    applyAttrs(e, attrs, true);
    appendAll(e, children);
    return e;
  }

  function applyAttrs(e, attrs, isSvg) {
    if (!attrs) return;
    for (const k of Object.keys(attrs)) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') e.setAttribute('class', v);
      else if (k === 'text') e.textContent = v;
      else if (k === 'html') e.innerHTML = v;
      else if (k === 'style' && typeof v === 'string') e.setAttribute('style', v);
      else if (k === 'dataset') Object.assign(e.dataset, v);
      else if (k.startsWith('on') && typeof v === 'function') e.addEventListener(k.slice(2).toLowerCase(), v);
      else if (!isSvg && k in e && typeof e[k] !== 'object' && k !== 'list' && k !== 'form') {
        try { e[k] = v; } catch (_) { e.setAttribute(k, v); }
      } else e.setAttribute(k, v === true ? '' : v);
    }
  }

  function appendAll(e, children) {
    for (const c of children) {
      if (c == null || c === false) continue;
      if (Array.isArray(c)) appendAll(e, c);
      else if (typeof c === 'string' || typeof c === 'number') e.appendChild(document.createTextNode(String(c)));
      else e.appendChild(c);
    }
  }

  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); return e; }

  /** mm:ss (h:mm:ss past an hour); negative shows a minus. */
  function fmtT(s) {
    if (s == null || isNaN(s)) return '–';
    const neg = s < 0; s = Math.abs(Math.round(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    const core = h > 0 ? `${h}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}` : `${m}:${String(sec).padStart(2, '0')}`;
    return (neg ? '-' : '') + core;
  }

  /** "mm:ss", "m:ss", "430", "7m10s" -> seconds; null when it is not a time. */
  function parseT(str) {
    if (str == null) return null;
    const s = String(str).trim();
    if (s === '') return null;
    let m = s.match(/^(-?)(\d+):(\d{1,2})(?::(\d{1,2}))?$/);
    if (m) {
      const sign = m[1] ? -1 : 1;
      if (m[4] != null) return sign * (Number(m[2]) * 3600 + Number(m[3]) * 60 + Number(m[4]));
      return sign * (Number(m[2]) * 60 + Number(m[3]));
    }
    m = s.match(/^(\d+)m\s*(\d+)?s?$/i);
    if (m) return Number(m[1]) * 60 + Number(m[2] || 0);
    const n = Number(s);
    return isFinite(n) ? n : null;
  }

  /** A number from an input's text, or null for empty / not a number. `int` rounds. */
  function parseNum(str, int) {
    if (str == null) return null;
    const s = String(str).trim().replace(',', '.');
    if (s === '') return null;
    const n = Number(s);
    if (!isFinite(n)) return null;
    return int ? Math.round(n) : roundTo(n, 6);
  }

  function roundTo(n, digits) { const p = Math.pow(10, digits); return Math.round(n * p) / p; }

  function fmtN(n, digits) {
    if (n == null || isNaN(n)) return '–';
    if (Number.isInteger(n)) return String(n);
    return String(roundTo(n, digits == null ? 3 : digits));
  }

  function pct(frac) { return fmtN((frac || 0) * 100, 1) + '%'; }

  const clone = (x) => (x === undefined ? undefined : JSON.parse(JSON.stringify(x)));
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);

  /** Set or delete a key: an empty value deletes it; a value equal to the default is written only when the key already
   *  exists (so a file that spelt out a default keeps it and one that did not stays short: a one-line diff). */
  function setKey(obj, key, value, def) {
    const empty = value == null || value === '' || (typeof value === 'number' && isNaN(value));
    if (empty) { delete obj[key]; return; }
    if (key in obj || def === undefined || !same(value, def)) obj[key] = value;
  }

  /** The value at a dotted path, or undefined. */
  function getPath(obj, path) {
    let cur = obj;
    for (const p of path.split('.')) { if (!isObj(cur) || !(p in cur)) return undefined; cur = cur[p]; }
    return cur;
  }

  /** Set a dotted path, creating objects on the way; an empty value deletes the key and any object left empty. */
  function setPath(obj, path, value) {
    const parts = path.split('.');
    const empty = value == null || value === '' || (typeof value === 'number' && isNaN(value));
    if (empty) {
      const stack = [obj];
      let cur = obj;
      for (let i = 0; i < parts.length - 1; i++) { if (!isObj(cur[parts[i]])) return; cur = cur[parts[i]]; stack.push(cur); }
      delete cur[parts[parts.length - 1]];
      for (let i = stack.length - 1; i > 0; i--) { if (Object.keys(stack[i]).length === 0) delete stack[i - 1][parts[i - 1]]; }
      return;
    }
    let cur = obj;
    for (let i = 0; i < parts.length - 1; i++) { if (!isObj(cur[parts[i]])) cur[parts[i]] = {}; cur = cur[parts[i]]; }
    cur[parts[parts.length - 1]] = value;
  }

  /** The enemy ids of an event's `enemy` (a string or a list). */
  function idList(v) {
    if (v == null || v === '') return [];
    return Array.isArray(v) ? v.map(String) : [String(v)];
  }

  function debounce(fn, ms) { let h = 0; return (...a) => { clearTimeout(h); h = setTimeout(() => fn(...a), ms); }; }

  /** "the Skeleton", but "The Tumbleweed King" keeps its own article. */
  const theName = (name) => (/^the\s/i.test(String(name)) ? String(name) : 'the ' + name);

  /** A tiny Markdown renderer for the schema doc: headings, fenced code, lists, paragraphs, inline code, bold, links. */
  function markdown(src) {
    const out = [];
    const lines = String(src).replace(/\r\n/g, '\n').split('\n');
    let i = 0, para = [], list = null;
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const inline = (s) => esc(s)
      .replace(/`([^`]+)`/g, '<code>$1</code>')
      .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
    const flushPara = () => { if (para.length) { out.push(`<p>${inline(para.join(' '))}</p>`); para = []; } };
    const flushList = () => { if (list) { out.push(`<ul>${list.map((x) => `<li>${inline(x)}</li>`).join('')}</ul>`); list = null; } };
    while (i < lines.length) {
      const l = lines[i];
      if (l.startsWith('```')) {
        flushPara(); flushList();
        const buf = []; i++;
        while (i < lines.length && !lines[i].startsWith('```')) buf.push(lines[i++]);
        out.push(`<pre><code>${esc(buf.join('\n'))}</code></pre>`); i++; continue;
      }
      const h = l.match(/^(#{1,4})\s+(.*)$/);
      if (h) { flushPara(); flushList(); out.push(`<h${h[1].length + 1}>${inline(h[2])}</h${h[1].length + 1}>`); i++; continue; }
      const li = l.match(/^\s*[-*]\s+(.*)$/);
      if (li) { flushPara(); (list = list || []).push(li[1]); i++; continue; }
      if (list && /^\s{2,}\S/.test(l)) { list[list.length - 1] += ' ' + l.trim(); i++; continue; }
      if (l.trim() === '') { flushPara(); flushList(); i++; continue; }
      flushList(); para.push(l.trim()); i++;
    }
    flushPara(); flushList();
    return out.join('\n');
  }

  function download(name, text) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
    a.download = name;
    document.body.appendChild(a); a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }

  /** <svg><use href="#g-name"/></svg> as an inline glyph (the symbols live in index.html). */
  function glyph(name, cls) {
    return svg('svg', { class: 'glyph ' + (cls || ''), viewBox: '0 0 16 16', width: 14, height: 14 }, svg('use', { href: '#g-' + name }));
  }

  return { el, svg, clear, fmtT, parseT, parseNum, roundTo, fmtN, pct, clone, same, clamp, isObj, setKey, getPath, setPath, idList, debounce, theName, markdown, download, glyph, SVG_NS };
})();
