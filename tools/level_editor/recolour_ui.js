/* Pass 131 (lane RECUI): fields that explain themselves, for any method in methods.json, and the widgets of
 * "Recolour an existing look".
 *
 * A recipe field may carry, beside key / type / default / help:
 *   label      the plain name beside the box (else the key)
 *   example    one value and what it does, shown under the box
 *   guide      the sensible range and when to change it, shown under the box
 *   show_if    {key, in: [...]}: the field shows only while the field `key` holds one of those values (its default counts)
 *   options_guide  a select's {option: one line saying when to pick it}
 *   widget     a named control from FieldUI.widgets instead of the plain box
 *   form_only  a control that writes no recipe key of its own (a preset list, a preview)
 * A method may carry `guide` {title, steps[], sheet, faults[{see, do, example}]}: FieldUI.guideBox draws it.
 * jobs.js calls shown / line / notes / guideBox; no other method's form changes while its fields carry none of these.
 */
'use strict';

const FieldUI = (() => {
  const el = (...a) => U.el(...a);
  const HUE_NAMES = [[0, 'red'], [30, 'orange'], [60, 'yellow'], [120, 'green'], [180, 'cyan'], [240, 'blue'], [280, 'purple'], [320, 'pink'], [360, 'red']];
  const blank = (v) => v == null || v === '' || (Array.isArray(v) && !v.length);

  // ---- pure helpers (selftest_RECUI131 runs them under Node) ----------------------------------------------------------
  /** Does the field show? `get(key)` reads another field's value; `fields` gives that field's default. */
  function shown(f, get, fields) {
    const c = f && f.show_if;
    if (!c || !c.key) return true;
    let v = get(c.key);
    if (blank(v)) { const d = (fields || []).find((x) => x.key === c.key && x.default != null); v = d ? d.default : ''; }
    return (Array.isArray(c.in) ? c.in : [c.in]).map(String).includes(String(v));
  }
  /** Is some other field's show_if tied to this one (a change must redraw the form)? */
  const drives = (f, fields) => (fields || []).some((x) => x.show_if && x.show_if.key === f.key);
  /** "340-360, 0-20" or [[340,360],[0,20]] -> {ranges, error}. A range runs low to high inside 0-360. */
  function parseRanges(v) {
    if (blank(v)) return { ranges: [], error: '' };
    let list = v;
    if (typeof v === 'string') list = v.split(/[,;]/).map((p) => p.trim()).filter(Boolean).map((p) => p.split(/\s*(?:-|–|to)\s*/));
    else if (Array.isArray(v) && v.length === 2 && !Array.isArray(v[0])) list = [v];
    const out = [];
    for (const r of Array.isArray(list) ? list : []) {
      const a = Number(r && r[0]); const b = Number(r && r[1]);
      if (!Array.isArray(r) || r.length !== 2 || r[0] === '' || r[1] === '' || !Number.isFinite(a) || !Number.isFinite(b)) return { ranges: out, error: 'each range is two numbers, from-to, such as 55-135' };
      if (a < 0 || b > 360) return { ranges: out, error: 'hues run from 0 to 360' };
      if (a >= b) return { ranges: out, error: `${a}-${b} runs backwards: to go through red give two ranges, ${a}-360, 0-${b}` };
      out.push([a, b]);
    }
    return { ranges: out, error: '' };
  }
  const rangesText = (v) => parseRanges(v).ranges.map((r) => `${r[0]}-${r[1]}`).join(', ');
  /** The colour word nearest a hue. */
  function hueName(h) {
    const x = ((Number(h) % 360) + 360) % 360;
    let best = HUE_NAMES[0];
    for (const n of HUE_NAMES) if (Math.abs(n[0] - x) < Math.abs(best[0] - x)) best = n;
    return best[1];
  }
  /** Frame numbers of each animation's first frame along a strip, in the anims' own order: {idle: 0, run: 4, ..., hit: 18}. */
  function animStarts(anims) {
    const out = {}; let k = 0;
    for (const [name, n] of Object.entries(anims && typeof anims === 'object' ? anims : {})) { out[name] = k; k += Number(n) || 0; }
    return out;
  }
  /** A preset laid over a recolour block: the source look stays, every other box is the preset's. */
  function applyPreset(block, preset) {
    const out = { from: block && block.from ? block.from : undefined };
    Object.assign(out, JSON.parse(JSON.stringify((preset && preset.values) || {})));
    if (out.from === undefined) delete out.from;
    return out;
  }
  /** The block's own pass fields, copied as the start of an extra pass. */
  function passFrom(block, extra) {
    const out = {};
    for (const [k, v] of Object.entries(block || {})) if (!['from', 'passes', 'keep_edge'].includes(k) && !k.startsWith('_')) out[k] = JSON.parse(JSON.stringify(v));
    return Object.assign(out, extra || {});
  }

  /** The looks of a creature or outlaw for the pick list: the page's record ([{code, note, sprite, ready, base, anims}]),
   *  else read off its content JSON (variants; the base look and every entry with a sprite are finished). */
  function looksOf(record, json) {
    const rec = record && (record.looks || record.variants);
    if (Array.isArray(rec) && rec.length) return rec;
    const vs = json && json.variants && typeof json.variants === 'object' ? json.variants : {};
    const base = json ? String(json.variant_base || '') : '';
    return Object.entries(vs).map(([code, e]) => ({ code, note: (e && e.note) || '', sprite: (e && e.sprite) || '', base: code === base, ready: !!(e && e.sprite) || code === base, anims: (e && e.anims) || (json && json.anims) || null }));
  }

  // ---- drawing -------------------------------------------------------------------------------------------------------
  /** The example and the guide under a field's box (and a select's "when to pick it" lines). */
  function notes(line, f, value) {
    if (!line || !f) return line;
    if (f.options_guide && typeof f.options_guide === 'object') {
      const cur = blank(value) ? f.default : value;
      const box = el('div', { class: 'fopts' });
      for (const [k, t] of Object.entries(f.options_guide)) box.appendChild(el('div', { class: 'fopt' + (String(k) === String(cur) ? ' on' : ''), text: t }));
      line.appendChild(box);
    }
    if (f.example) line.appendChild(el('div', { class: 'fex' }, el('b', { text: 'Example: ' }), document.createTextNode(f.example)));
    if (f.guide) line.appendChild(el('div', { class: 'fgd' }, el('b', { text: 'Sensible values: ' }), document.createTextNode(f.guide)));
    return line;
  }

  function hueStrip(marks) {
    const bar = el('div', { class: 'huebar' });
    const strip = el('div', { class: 'huestrip' });
    const lay = el('div', { class: 'huemarks' });
    const names = el('div', { class: 'huenames' });
    for (const [deg, name] of HUE_NAMES) names.appendChild(el('span', { style: `left:${(deg / 360) * 100}%`, text: `${name} ${deg}` }));
    bar.appendChild(strip); bar.appendChild(lay); bar.appendChild(names);
    const set = (m) => {
      U.clear(lay);
      for (const r of (m && m.ranges) || []) lay.appendChild(el('div', { class: 'huemark', style: `left:${(r[0] / 360) * 100}%;width:${Math.max(((r[1] - r[0]) / 360) * 100, 0.6)}%`, title: `${r[0]}-${r[1]}` }));
      if (m && m.point != null && Number.isFinite(Number(m.point))) lay.appendChild(el('div', { class: 'huepoint', style: `left:${(Math.min(Math.max(Number(m.point), 0), 360) / 360) * 100}%` }));
    };
    set(marks);
    return { node: bar, set };
  }

  const widgets = {
    /** A look's code: typeable, with the creature's own finished looks as the pick list, and a line saying what was found. */
    look_code(f, value, set, ctx) {
      const looks = (ctx.looks || []).filter((l) => l && l.code && l.code !== ctx.code);
      const done = looks.filter((l) => l.ready || l.sprite || l.base);
      const id = 'fui-looks-' + Math.random().toString(36).slice(2, 8);
      const inp = el('input', { type: 'text', class: 'txt', value: value || '', placeholder: done.length ? `e.g. ${done[0].code}` : 'e.g. CC-B', list: id, spellcheck: false, autocomplete: 'off' });
      const dl = el('datalist', { id });
      for (const l of done) dl.appendChild(el('option', { value: l.code, label: [l.name, l.note].filter(Boolean).join(' · ').slice(0, 80) }));
      const msg = el('div', { class: 'fmsg' });
      const say = () => {
        const v = inp.value.trim();
        const hit = looks.find((l) => l.code === v);
        msg.className = 'fmsg' + (v && !hit && looks.length ? ' bad' : '');
        if (!v) msg.textContent = done.length ? `This creature's finished looks: ${done.map((l) => l.code).join(', ')}.` : '';
        else if (hit) msg.textContent = `Found ${v}${hit.note ? ': ' + String(hit.note).slice(0, 90) : ''}`;
        else if (looks.length) msg.textContent = `No look "${v}" here. Type the code alone; this creature's looks: ${looks.map((l) => l.code).join(', ')}.`;
        else msg.textContent = '';
      };
      inp.addEventListener('input', say);
      inp.addEventListener('change', () => { set(inp.value.trim() || null); if (ctx.draw) ctx.draw(); });
      say();
      return el('div', { class: 'fwid' }, inp, dl, msg);
    },
    /** Hue ranges as words ("340-360, 0-20") over a strip of the colour wheel with the ranges marked. */
    hue_ranges(f, value, set) {
      const inp = el('input', { type: 'text', class: 'txt', value: rangesText(value), placeholder: f.default != null ? rangesText(f.default) : '55-135', spellcheck: false });
      const strip = hueStrip({ ranges: parseRanges(blank(value) ? f.default : value).ranges });
      const msg = el('div', { class: 'fmsg bad' });
      const read = () => {
        const p = parseRanges(inp.value);
        msg.textContent = p.error;
        inp.style.borderColor = p.error ? 'var(--s8, #e66767)' : '';
        strip.set({ ranges: inp.value.trim() ? p.ranges : parseRanges(f.default).ranges });
        return p;
      };
      inp.addEventListener('input', read);
      inp.addEventListener('change', () => { const p = read(); if (!p.error) set(p.ranges.length ? p.ranges : null); });
      return el('div', { class: 'fwid' }, inp, strip.node, msg);
    },
    /** One hue: the number, a swatch and its colour word, on the same strip. */
    hue(f, value, set) {
      const inp = el('input', { type: 'number', class: 'num', value: blank(value) ? '' : value, placeholder: f.default != null ? String(f.default) : '', min: 0, max: 360, step: 1 });
      const sw = el('span', { class: 'hueswatch' });
      const word = el('span', { class: 'muted small' });
      const strip = hueStrip({});
      const read = () => {
        const v = inp.value === '' ? f.default : Number(inp.value);
        const ok = v != null && Number.isFinite(Number(v));
        sw.style.background = ok ? `hsl(${v}, 85%, 50%)` : 'transparent';
        word.textContent = ok ? `${hueName(v)}${inp.value === '' ? ' (the default)' : ''}` : '';
        strip.set({ point: ok ? v : null });
      };
      inp.addEventListener('input', read);
      inp.addEventListener('change', () => set(inp.value === '' ? null : Number(inp.value)));
      read();
      return el('div', { class: 'fwid' }, el('div', { class: 'fwrow' }, inp, sw, word), strip.node);
    },
    /** A pick list that fills the boxes from a look that exists. */
    presets(f, value, set, ctx) {
      const list = Array.isArray(f.presets) ? f.presets : [];
      const sel = el('select');
      sel.appendChild(el('option', { value: '', text: '(pick a preset to fill the boxes)' }));
      list.forEach((p, k) => sel.appendChild(el('option', { value: String(k), text: p.name, selected: ctx.memo && ctx.memo.preset === p.name })));
      const cur = list.find((p) => ctx.memo && ctx.memo.preset === p.name);
      const msg = el('div', { class: 'fmsg', text: cur ? `Filled from ${cur.line}.` : '' });
      sel.addEventListener('change', () => {
        const p = list[Number(sel.value)];
        if (sel.value === '' || !p) return;
        const head = String(f.key).split('.').slice(0, -1).join('.');
        const block = head ? U.getPath(ctx.root, head) : ctx.root;
        if (head) U.setPath(ctx.root, head, applyPreset(block, p));
        if (ctx.memo) ctx.memo.preset = p.name;
        if (ctx.draw) ctx.draw();
      });
      return el('div', { class: 'fwid' }, sel, msg);
    },
    /** Extra passes: each a card with the same boxes as the form (those its own mode reads) plus the frames it runs on. */
    passes(f, value, set, ctx) {
      const list = Array.isArray(value) ? JSON.parse(JSON.stringify(value)) : [];
      const box = el('div', { class: 'fwid fpasses' });
      const head = String(f.key).split('.').slice(0, -1).join('.');
      const block = () => (head ? U.getPath(ctx.root, head) : ctx.root) || {};
      const passFields = (ctx.fields || []).filter((x) => x.key.startsWith(head + '.') && !x.form_only && !['from', 'passes', 'keep_edge'].includes(x.key.slice(head.length + 1)));
      const src = (ctx.looks || []).find((l) => l.code === block().from);
      const starts = animStarts(src && src.anims);
      const commit = () => set(list.length ? list : null);
      const draw = () => {
        U.clear(box);
        list.forEach((p, k) => {
          const card = el('div', { class: 'fpass' });
          const rm = el('button', { type: 'button', class: 'btn', text: 'Remove' });
          rm.addEventListener('click', () => { list.splice(k, 1); commit(); draw(); });
          card.appendChild(el('div', { class: 'fpasshead' }, el('b', { text: `Pass ${k + 2}` }), el('span', { class: 'muted small', text: 'runs on the result of the pass before it' }), rm));
          const cells = el('input', { type: 'text', class: 'txt', value: (p.cells || []).join(', '), placeholder: 'empty = the whole strip and the icon', spellcheck: false });
          cells.addEventListener('change', () => {
            const v = cells.value.split(/[,; ]+/).filter((x) => x !== '').map(Number).filter((n) => Number.isInteger(n) && n >= 0);
            if (v.length) p.cells = v; else delete p.cells;
            cells.value = v.join(', '); commit();
          });
          const cl = ctx.fieldLine('Only these frames', cells, 'The pass runs on these frames of the strip alone; every other frame is left as the pass before made it.');
          const chips = el('div', { class: 'fex' }, el('b', { text: src ? `${src.code}'s frames start at: ` : 'Frames count from 0: ' }));
          if (src && Object.keys(starts).length) {
            for (const [name, n] of Object.entries(starts)) {
              const b = el('button', { type: 'button', class: 'btn', text: `${name} ${n}`, title: `put frame ${n} (the first ${name} frame) in the box` });
              b.addEventListener('click', () => { p.cells = Array.from(new Set([...(p.cells || []), n])); cells.value = p.cells.join(', '); commit(); });
              chips.appendChild(b);
            }
          } else chips.appendChild(document.createTextNode('with 4 idle, 12 run and 2 attack frames the hit frame is 18. Several: 18, 61.'));
          cl.appendChild(chips);
          card.appendChild(cl);
          const get = (key) => p[key.slice(head.length + 1)];
          for (const pf of passFields) {
            if (!shown(pf, get, passFields)) continue;
            const local = pf.key.slice(head.length + 1);
            const setP = (v) => { if (blank(v)) delete p[local]; else p[local] = v; commit(); if (drives(pf, passFields)) draw(); };
            const ctl = pf.widget && widgets[pf.widget] ? widgets[pf.widget](pf, p[local], setP, ctx) : ctx.recipeControl(Object.assign({}, pf, local === 'mode' ? { required: false } : null), p[local], setP, {});
            // the examples and the sensible values stand under the same boxes above: a pass's card stays short
            card.appendChild(ctx.fieldLine(pf.label || local, ctl, pf.help));
          }
          box.appendChild(card);
        });
        const add = el('button', { type: 'button', class: 'btn', text: '+ Add a pass', title: 'a copy of the boxes above, to change' });
        add.addEventListener('click', () => { list.push(passFrom(block())); commit(); draw(); });
        const row = el('div', { class: 'fwrow' }, add);
        if (starts.hit != null) {
          const hit = el('button', { type: 'button', class: 'btn', text: `+ Add a pass for the hit frame (${starts.hit})`, title: 'a copy of the boxes above on that frame alone, with "at least this colourful" lowered to 0.05' });
          hit.addEventListener('click', () => {
            const p = passFrom(block(), { cells: [starts.hit] });
            if (!(Number(p.min_sat) <= 0.05)) p.min_sat = 0.05;
            list.push(p); commit(); draw();
          });
          row.appendChild(hit);
        }
        if (!list.length) row.appendChild(el('span', { class: 'muted small', text: 'none: most recolours need only the boxes above' }));
        box.appendChild(row);
      };
      draw();
      return box;
    },
    /** Before / after on a few frames and the icon, asked of the server; nothing is written. */
    recolour_preview(f, value, set, ctx) {
      const box = el('div', { class: 'fwid fprev' });
      const head = String(f.key).split('.').slice(0, -1).join('.');
      const block = () => (head ? U.getPath(ctx.root, head) : ctx.root) || {};
      const btn = el('button', { type: 'button', class: 'btn primary', text: 'Show before / after' });
      const msg = el('span', { class: 'muted small' });
      const out = el('div', { class: 'fprevshots' });
      const memo = ctx.memo || {};
      const show = (res, stale) => {
        U.clear(out);
        if (!res) return;
        if (!res.ok) { msg.textContent = ''; out.appendChild(el('div', { class: 'fmsg bad', text: res.error || 'the preview failed' })); return; }
        msg.textContent = stale ? 'the boxes changed since this was made: press again' : `made in ${res.seconds} s; nothing was written`;
        for (const s of res.shots || []) {
          out.appendChild(el('div', { class: 'fshot' }, el('div', { class: 'fshotpair' }, el('img', { src: s.before, alt: 'before', title: 'before' }), el('span', { class: 'muted', text: '→' }), el('img', { src: s.after, alt: 'after', title: 'after' })), el('div', { class: 'muted small', text: s.label })));
        }
        for (const n of res.notes || []) out.appendChild(el('div', { class: 'fmsg bad', text: n }));
      };
      const body = () => JSON.stringify({ kind: ctx.kind === 'boss' ? 'boss' : ctx.kind, id: ctx.id, recolour: block() });
      btn.addEventListener('click', async () => {
        if (!block().from) { show({ ok: false, error: 'Fill "Look to recolour" first.' }); return; }
        const b = body();
        btn.disabled = true; msg.textContent = 'working…';
        let res;
        try {
          const r = await fetch('/api/recolour/preview', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: b });
          try { res = await r.json(); } catch (_) { res = { ok: false, error: r.status === 404 ? 'this Level Editor server is older than the preview: restart it (tools\\level_editor.cmd)' : `HTTP ${r.status}` }; }
          if (!r.ok && res.ok !== false) res = { ok: false, error: res.error || `HTTP ${r.status}` };
        } catch (e) { res = { ok: false, error: String(e && e.message ? e.message : e) }; }
        btn.disabled = false;
        memo.preview = { body: b, res };
        show(res, false);
      });
      box.appendChild(el('div', { class: 'fwrow' }, btn, msg));
      box.appendChild(out);
      if (memo.preview) show(memo.preview.res, memo.preview.body !== body());
      return box;
    },
  };

  /** One whole line of the form for a field with a widget. ctx: {root, fields, draw, fieldLine, recipeControl, looks, kind, id, code, memo}. */
  function line(f, ctx) {
    const value = f.form_only ? undefined : U.getPath(ctx.root, f.key);
    const set = (v) => { if (!f.form_only) U.setPath(ctx.root, f.key, v); };
    const ctl = widgets[f.widget](f, value, set, ctx);
    return notes(ctx.fieldLine(f.label || f.key, ctl, f.help), f, value);
  }

  /** A method's guide: the steps, how to read the preview sheet, the usual faults and the box that fixes each. */
  function guideBox(method) {
    const g = method && method.guide;
    if (!g || typeof g !== 'object') return null;
    const key = 'le_guide_' + (method.id || '');
    let open = true;
    try { open = localStorage.getItem(key) !== 'closed'; } catch (_) { /* no storage */ }
    const d = el('details', { class: 'fguide' }, el('summary', { text: g.title || 'How to use this method' }));
    d.open = open;
    d.addEventListener('toggle', () => { try { localStorage.setItem(key, d.open ? 'open' : 'closed'); } catch (_) { /* no storage */ } });
    for (const s of g.steps || []) d.appendChild(el('p', { text: s }));
    if (g.sheet) d.appendChild(el('p', {}, el('b', { text: 'Reading the preview sheet. ' }), document.createTextNode(g.sheet)));
    if (Array.isArray(g.faults) && g.faults.length) {
      const t = el('table', { class: 'fgfaults' }, el('tr', {}, el('th', { text: 'What you see' }), el('th', { text: 'What to change' }), el('th', { text: 'For example' })));
      for (const x of g.faults) t.appendChild(el('tr', {}, el('td', { text: x.see || '' }), el('td', { text: x.do || '' }), el('td', { text: x.example || '' })));
      d.appendChild(t);
    }
    return d;
  }

  return { shown, drives, looksOf, parseRanges, rangesText, hueName, animStarts, applyPreset, passFrom, notes, line, guideBox, widgets, HUE_NAMES };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = FieldUI;
