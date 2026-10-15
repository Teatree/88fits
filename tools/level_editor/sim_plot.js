// The Sim's charts on a page (pass 78, lane DASH; Garry: "Add those charts to our Local Run Analytics dashboard so their
// formats match"). The drawing the Sim tab had in sim.js (pass 77), moved here unchanged so the Level Editor's Sim tab
// and analytics/dashboard.html draw the same charts the same way: the sections and their cards (title, what it shows,
// the per-second DPS switch, Table, CSV), each plot as SVG (the axis from 0 to a round tick, the boss fights shaded with
// a crown, the stage starts, a stack bottom to top, the bands, the compared run dashed grey, the lines), one hover cursor
// shared by every chart and the readout under each. The charts' definitions and maths stay in sim_model.js; the styles
// in sim.css. A page hands a `view`:
//   {current: a result (sim_batch / SimAvg.aggregate), compare: one or null, hover, raw, tables (Set), drawn ([]),
//    csvName(c), download(name, text), toggleRaw(), toggleTable(id), whenText(t, end) (optional)}
'use strict';

const SimPlot = (() => {
  const M = SimModel;
  const SVG_NS = 'http://www.w3.org/2000/svg';
  // the crown over a boss fight (the editor's #g-crown symbol, drawn inline so a page without the symbol has it too)
  const CROWN = 'M1.5 5.5l3.3 2.6L8 3l3.2 5.1 3.3-2.6-1.3 7H2.8zM2.8 13.5h10.4V15H2.8z';

  // ------------------------------------------------------------------ the DOM (the editor's U.el / U.svg rules)

  function applyAttrs(e, attrs, isSvg) {
    if (!attrs) return;
    for (const k of Object.keys(attrs)) {
      const v = attrs[k];
      if (v == null || v === false) continue;
      if (k === 'class') e.setAttribute('class', v);
      else if (k === 'text') e.textContent = v;
      else if (k === 'style' && typeof v === 'string') e.setAttribute('style', v);
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

  function el(tag, attrs, ...children) { const e = document.createElement(tag); applyAttrs(e, attrs, false); appendAll(e, children); return e; }
  function svg(tag, attrs, ...children) { const e = document.createElementNS(SVG_NS, tag); applyAttrs(e, attrs, true); appendAll(e, children); return e; }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); return e; }

  function keyLine(color, dash) {
    return svg('svg', { class: 'sim-key', width: 18, height: 8, viewBox: '0 0 18 8' }, svg('line', { x1: 1, y1: 4, x2: 17, y2: 4, stroke: color, 'stroke-width': 2, 'stroke-dasharray': dash || null, 'stroke-linecap': 'round' }));
  }

  function keyBox(color, alpha) {
    return svg('svg', { class: 'sim-key', width: 12, height: 12, viewBox: '0 0 12 12' }, svg('rect', { x: 1, y: 1, width: 10, height: 10, rx: 2, fill: color, 'fill-opacity': alpha == null ? 0.75 : alpha }));
  }

  // ------------------------------------------------------------------ the sections and the cards

  /** The charts in their sections (Garry's order), each section a heading, its one line and a grid of cards.
   *  `opts.lacking`: a line under the difficulty section naming what the runs did not report. */
  function drawCharts(container, view, opts) {
    const o = opts || {};
    const r = view.current;
    const defs = M.charts(r, view.compare, { raw: view.raw });
    const lacking = o.lacking === undefined ? M.missing(r) : o.lacking;
    view.drawn = [];
    for (const sec of M.SECTIONS) {
      const mine = defs.filter((c) => c.section === sec.id);
      if (!mine.length) continue;
      const box = el('section', { class: 'sim-section', 'data-id': sec.id },
        el('div', { class: 'sim-section-head' }, el('h2', { text: sec.title }), el('span', { class: 'muted small', text: sec.words })));
      const grid = el('div', { class: 'sim-grid' });
      for (const c of mine) grid.appendChild(chartCard(c, r, view));
      box.appendChild(grid);
      if (sec.id === 'difficulty' && lacking && lacking.length) box.appendChild(el('p', { class: 'muted small sim-lacking', text: `${o.lackingWords || 'Not in these runs (the runner did not report them)'}: ${lacking.join('; ')}.` }));
      container.appendChild(box);
    }
    requestAnimationFrame(() => { for (const d of view.drawn) plotChart(d, view); updateReadouts(view); observePlots(view); });
    return defs;
  }

  // a plot drawn at one width and shown at another (a scrollbar appearing, a resize, a fold above it) is drawn again
  // at its new width; until then it stretches with its card, so it is never cut off
  function observePlots(view) {
    if (typeof ResizeObserver === 'undefined') return;
    if (view._plotObserver) view._plotObserver.disconnect();
    view._plotObserver = new ResizeObserver(() => {
      clearTimeout(view._reflowT);
      view._reflowT = setTimeout(() => {
        let any = false;
        for (const d of view.drawn) {
          const w = Math.floor(d.plot.clientWidth || 0);
          if (d.geo && w > 0 && Math.abs(w - d.geo.W) > 8) { plotChart(d, view); any = true; }
        }
        if (any) updateReadouts(view);
      }, 120);
    });
    for (const d of view.drawn) view._plotObserver.observe(d.plot);
  }

  function chartCard(c, r, view) {
    const card = el('section', { class: 'card sim-chart', 'data-id': c.id });
    const tools = el('div', { class: 'sim-chart-tools' });
    if (c.id === 'dps' && view.toggleRaw) tools.appendChild(el('button', { type: 'button', class: 'btn small' + (view.raw ? ' on' : ''), text: view.raw ? 'per second' : `smoothed ${(r.rules || {}).dps_window || 5} s`, title: 'switch between each run smoothed over 5 s (with the band) and the raw per-second average', onclick: () => view.toggleRaw() }));
    tools.appendChild(el('button', { type: 'button', class: 'btn small ghost' + (view.tables.has(c.id) ? ' on' : ''), text: 'Table', title: 'the numbers every minute', onclick: () => view.toggleTable(c.id) }));
    tools.appendChild(el('button', { type: 'button', class: 'btn small ghost', text: 'CSV', title: 'every second of this chart as a spreadsheet file', onclick: () => view.download(view.csvName(c), M.csv(c, r.t.length - 1)) }));
    card.appendChild(el('div', { class: 'sim-chart-head' }, el('h3', { text: c.title }), tools));
    card.appendChild(el('p', { class: 'sim-how', text: c.how }));
    const plot = el('div', { class: 'sim-plot' });
    card.appendChild(plot);
    const read = el('div', { class: 'sim-read' });
    card.appendChild(read);
    if (view.tables.has(c.id)) card.appendChild(tableView(c, r.t.length - 1));
    view.drawn.push({ c, plot, read, card });
    return card;
  }

  function tableView(c, T) {
    const tb = M.table(c, 60, T);
    const t = el('table', { class: 'sim-table small' });
    t.appendChild(el('thead', {}, el('tr', {}, ...tb.head.map((h) => el('th', { text: h })))));
    const body = el('tbody');
    for (const row of tb.rows) body.appendChild(el('tr', {}, el('td', { text: M.fmtT(row[0]) }), ...row.slice(1).map((v) => el('td', { text: M.fmtVal(v, c.fmt) }))));
    t.appendChild(body);
    return el('div', { class: 'sim-table-wrap' }, t);
  }

  /** The x axis's last second: the longer of the shown and the compared result. */
  function axisT(view) {
    const a = view.current ? view.current.t.length - 1 : 0;
    const b = view.compare ? view.compare.t.length - 1 : 0;
    return Math.max(1, a, b);
  }

  // ------------------------------------------------------------------ the plot

  /** A path through `values` (null breaks it), averaged per pixel when there are more seconds than pixels. */
  function pathD(values, x, y, T, pw) {
    const n = Math.min(values.length, T + 1);
    const per = n > pw * 1.5 ? Math.ceil(n / pw) : 1;
    let d = '', open = false;
    for (let i = 0; i < n; i += per) {
      let s = 0, k = 0;
      for (let j = i; j < Math.min(n, i + per); j++) if (values[j] != null) { s += values[j]; k++; }
      if (!k) { open = false; continue; }
      const t = per > 1 ? i + (Math.min(n, i + per) - i - 1) / 2 : i;
      d += `${open ? 'L' : 'M'}${x(t).toFixed(1)},${y(s / k).toFixed(1)}`;
      open = true;
    }
    return d;
  }

  /** A filled area between lo and hi (null breaks it). */
  function areaD(lo, hi, x, y, T, pw) {
    const n = Math.min(lo.length, hi.length, T + 1);
    const per = n > pw * 1.5 ? Math.ceil(n / pw) : 1;
    const segs = [];
    let cur = [];
    for (let i = 0; i < n; i += per) {
      let a = 0, b = 0, k = 0;
      for (let j = i; j < Math.min(n, i + per); j++) if (lo[j] != null && hi[j] != null) { a += lo[j]; b += hi[j]; k++; }
      if (!k) { if (cur.length) segs.push(cur); cur = []; continue; }
      cur.push([per > 1 ? i + (Math.min(n, i + per) - i - 1) / 2 : i, a / k, b / k]);
    }
    if (cur.length) segs.push(cur);
    let d = '';
    for (const sg of segs) {
      d += sg.map((p, i) => `${i ? 'L' : 'M'}${x(p[0]).toFixed(1)},${y(p[2]).toFixed(1)}`).join('');
      d += sg.slice().reverse().map((p) => `L${x(p[0]).toFixed(1)},${y(p[1]).toFixed(1)}`).join('') + 'Z';
    }
    return d;
  }

  function plotChart(d, view) {
    const { c, plot } = d;
    clear(plot);
    const W = Math.max(280, Math.floor(plot.clientWidth || 560));
    const H = 200, L = 52, R = 10, TOP = 18, B = 22;
    const pw = W - L - R, ph = H - TOP - B;
    const T = axisT(view);
    const rg = M.chartRange(c);
    const ymin = rg.lo, ymax = rg.hi;
    const x = (t) => L + (pw * t) / T;
    const y = (v) => TOP + ph * (1 - (Math.max(ymin, Math.min(ymax * 1.2, v)) - ymin) / (ymax - ymin || 1));
    const s = svg('svg', { class: 'sim-svg', viewBox: `0 0 ${W} ${H}`, width: '100%', height: H, preserveAspectRatio: 'none', role: 'img', 'aria-label': `${c.title} against play time` });
    // the grid and the y axis (0 the base line, also when the axis goes below it)
    for (const v of M.yTicksRange(ymin, ymax, ymin < 0 ? 5 : 4)) {
      s.appendChild(svg('line', { x1: L, y1: y(v), x2: W - R, y2: y(v), class: v === 0 ? 'sim-base' : 'sim-gl' }));
      s.appendChild(svg('text', { x: L - 6, y: y(v) + 3.5, class: 'sim-tick end', text: M.tickLabel(v, Math.max(ymax, -ymin), c.fmt) }));
    }
    for (const t of M.timeTicks(T, pw)) {
      s.appendChild(svg('line', { x1: x(t), y1: H - B, x2: x(t), y2: H - B + 4, class: 'sim-base' }));
      s.appendChild(svg('text', { x: x(t), y: H - 6, class: 'sim-tick mid', text: M.fmtT(t) }));
    }
    // the boss fights and the stage starts (medians of the runs that reached them)
    const mk = (view.current && view.current.markers) || {};
    const names = (view.current && view.current.names) || {};
    for (const b of mk.bosses || []) {
      if (b.start == null) continue;
      const x0 = x(b.start), x1 = x(b.end != null ? b.end : Math.min(T, b.start + 30));
      s.appendChild(svg('rect', { x: x0, y: TOP, width: Math.max(2, x1 - x0), height: ph, class: 'sim-boss' },
        svg('title', { text: `${names[b.id] || b.id}: the fight from ${M.fmtT(b.start)} to ${b.end != null ? M.fmtT(b.end) : '?'} (medians of the ${b.n} runs that met it; ${b.beaten} beat it)` })));
      s.appendChild(svg('path', { d: CROWN, transform: `translate(${(x0 + 1).toFixed(1)},2) scale(0.75)`, class: 'sim-crown' }));
      // its name right of the crown, or left of it near the right edge (never cut by the plot's edge)
      const nearB = x0 > W - R - 70;
      if (pw > 420) s.appendChild(svg('text', { x: nearB ? x0 - 3 : x0 + 15, y: 12, class: 'sim-mark-text' + (nearB ? ' end' : ''), text: M.shortName(names[b.id] || b.id) }));
    }
    for (const st of mk.stages || []) {
      if (st.t == null) continue;
      s.appendChild(svg('line', { x1: x(st.t), y1: TOP, x2: x(st.t), y2: H - B, class: 'sim-stage' },
        svg('title', { text: `stage ${st.stage} starts at ${M.fmtT(st.t)} (the median of the ${st.n} runs that got there)` })));
      // the label right of its line, or left of it near the right edge
      const near = x(st.t) > W - R - 52;
      s.appendChild(svg('text', { x: x(st.t) + (near ? -3 : 3), y: TOP + 10, class: 'sim-mark-text' + (near ? ' end' : ''), text: st.stage > 3 ? 'endless' : `stage ${st.stage}` }));
    }
    // the stack (bottom to top), the bands, the compared run, the lines
    if (c.stack) {
      const parts = c.stack.items.concat(c.stack.other ? [c.stack.other] : []);
      let base = new Array(T + 1).fill(0);
      for (const p of parts) {
        const top = base.map((b, i) => (p.values[i] == null ? (i < p.values.length ? b : null) : b + p.values[i]));
        const lo = base.map((b, i) => (top[i] == null ? null : b));
        s.appendChild(svg('path', { d: areaD(lo, top, x, y, T, pw), fill: p.color, 'fill-opacity': 0.55, stroke: 'none' }));
        s.appendChild(svg('path', { d: pathD(top, x, y, T, pw), fill: 'none', stroke: p.color, 'stroke-width': 1.25, 'stroke-linejoin': 'round' }));
        base = top.map((v, i) => (v == null ? base[i] : v));
      }
    }
    for (const b of c.bands) s.appendChild(svg('path', { d: areaD(b.lo, b.hi, x, y, T, pw), fill: b.color, 'fill-opacity': 0.16, stroke: 'none' }));
    for (const l of c.overlay) s.appendChild(svg('path', { d: pathD(l.values, x, y, T, pw), fill: 'none', stroke: M.COMPARE, 'stroke-width': 1.75, 'stroke-dasharray': M.COMPARE_DASH, 'stroke-linejoin': 'round' }));
    for (const l of c.lines) s.appendChild(svg('path', { d: pathD(l.values, x, y, T, pw), fill: 'none', stroke: l.color, 'stroke-width': l.width || 2, 'stroke-dasharray': l.dash || null, 'stroke-linejoin': 'round', 'stroke-linecap': 'round' }));
    // the cursor and the hover layer
    const cursor = svg('g', { class: 'sim-cursor', visibility: 'hidden' });
    cursor.appendChild(svg('line', { x1: 0, y1: TOP, x2: 0, y2: H - B, class: 'sim-cursor-line' }));
    const dots = [];
    const dotSeries = c.lines.filter((l) => !l.dash).map((l) => ({ values: l.values, color: l.color }));
    if (c.stack) dotSeries.push({ values: M.totalOf(c.stack), color: '#c3c2b7' });
    for (const ds of dotSeries) { const dot = svg('circle', { r: 4, fill: ds.color, class: 'sim-dot' }); cursor.appendChild(dot); dots.push({ dot, values: ds.values }); }
    s.appendChild(cursor);
    const hit = svg('rect', { x: L, y: TOP, width: pw, height: ph, class: 'sim-hit' });
    const toT = (ev) => { const rc = s.getBoundingClientRect(); const px = ((ev.clientX - rc.left) * W) / rc.width; return Math.max(0, Math.min(T, Math.round(((px - L) / pw) * T))); };
    hit.addEventListener('pointermove', (ev) => setHover(view, toT(ev)));
    hit.addEventListener('pointerleave', () => setHover(view, null));
    s.appendChild(hit);
    plot.appendChild(s);
    d.geo = { x, y, cursor, dots, T, W };
  }

  function setHover(view, t) {
    if (view.hover === t) return;
    view.hover = t;
    if (view._hoverRaf) return;
    view._hoverRaf = requestAnimationFrame(() => { view._hoverRaf = 0; updateReadouts(view); });
  }

  /** "at 3:20 · stage 1 · clock 3:20 · 8 of 10 runs playing" (one run: no count). */
  function whenText(view, t, end) {
    const r = view.current;
    const clock = r.series && r.series.clock ? r.series.clock.median[Math.min(t, end)] : null;
    const stage = r.series && r.series.stage ? r.series.stage.median[Math.min(t, end)] : null;
    const playing = r.playing ? r.playing[Math.min(t, end)] : null;
    const n = M.runsIn(r);
    return `${view.hover == null ? 'at the end' : 'at'} ${M.fmtT(t)}` + (stage != null && t <= end ? ` · stage ${Math.round(stage) > 3 ? 'endless' : Math.round(stage)}` : '') +
      (clock != null && t <= end ? ` · clock ${M.fmtT(clock)}` : '') + (playing != null && t <= end && n > 1 ? ` · ${playing} of ${n} runs playing` : '');
  }

  function updateReadouts(view) {
    const r = view.current;
    if (!r) return;
    const end = r.t.length - 1;
    const t = view.hover == null ? end : view.hover;
    const when = view.whenText ? view.whenText(t, end) : whenText(view, t, end);
    for (const d of view.drawn) {
      const { c, read, geo } = d;
      if (geo) {
        if (view.hover == null) geo.cursor.setAttribute('visibility', 'hidden');
        else {
          geo.cursor.setAttribute('visibility', 'visible');
          const line = geo.cursor.firstChild;
          line.setAttribute('x1', geo.x(t)); line.setAttribute('x2', geo.x(t));
          for (const dt of geo.dots) {
            const v = t < dt.values.length ? dt.values[t] : null;
            if (v == null) dt.dot.setAttribute('visibility', 'hidden');
            else { dt.dot.setAttribute('visibility', 'visible'); dt.dot.setAttribute('cx', geo.x(t)); dt.dot.setAttribute('cy', geo.y(v)); }
          }
        }
      }
      clear(read);
      read.appendChild(el('span', { class: 'sim-read-when', text: when }));
      for (const row of M.readout(c, t)) {
        const key = row.kind === 'stack' ? keyBox(row.color) : row.kind === 'total' ? keyLine('#c3c2b7') : keyLine(row.color, row.dash);
        read.appendChild(el('span', { class: 'sim-read-item' + (row.kind === 'overlay' ? ' cmp' : '') + (row.kind === 'stack' && !row.value ? ' zero' : '') }, key,
          el('b', { text: M.fmtVal(row.value, c.fmt) }), el('span', { class: 'muted', text: ' ' + row.label }),
          row.sub ? el('span', { class: 'muted small', text: row.kind === 'stack' ? ` (${row.sub})` : ` (middle 80%: ${row.sub})` }) : null));
      }
      for (const b of c.bands) if (!c.lines.some((l) => l.color === b.color)) read.appendChild(el('span', { class: 'sim-read-item' }, keyBox(b.color, 0.3), el('span', { class: 'muted', text: b.label })));
    }
  }

  /** Every plot again at its card's width (a page's resize handler calls it). */
  function replot(view) {
    for (const d of view.drawn) plotChart(d, view);
    updateReadouts(view);
  }

  return { el, svg, clear, keyLine, keyBox, drawCharts, chartCard, tableView, axisT, pathD, areaD, plotChart, setHover, updateReadouts, replot, whenText, CROWN };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = SimPlot;
