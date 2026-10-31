// Form controls shared by the inspector and the Settings tab (pass 53, pass 54). Every control writes through App.apply,
// so each change is one undo step and the lanes redraw; a value cleared deletes its key (U.setKey / U.setPath), so the
// JSON only ever holds what Garry set. Pass 54: the creature, art variant, elite modifier and power-up picks are one
// combobox with pictures (iconSelect); colours have swatches; a roster row's presence points, the HP x / ATK x curves and
// the spawn sides have blocks of their own. Pass 58: the art variant's empty choice reads "Default (CODE)", the
// creature's default look from the Creatures tab, which a row that names none follows. Pass 66: `opts.apply` lets the
// asset editors' documents use the same controls (Assets.apply instead of App.apply), a textarea type, and shelved looks
// in a dim group at the end of the art variant list.
'use strict';

const Forms = (() => {
  const { el, fmtT, fmtN, parseT, parseNum, clear } = U;

  /** A labelled row: the label (with the help as a tooltip and a "?" that unfolds it), then the control. `opts.note` (a
   *  node, a string or a list of both; pass 57) is a line always shown under the control across the row: the Pattern
   *  field's ring hint. */
  function row(def, control, opts) {
    const o = opts || {};
    const lab = el('label', { class: 'flabel', title: def.help || '' }, def.label, def.required ? el('span', { class: 'req', text: ' *' }) : null);
    const r = el('div', { class: 'frow' + (o.cls ? ' ' + o.cls : '') }, lab, el('div', { class: 'fctl' }, control, o.after || null));
    if (o.note) r.appendChild(el('div', { class: 'fhelp fnote', 'data-note': def.key || '', style: 'border-left: 3px solid var(--sel); color: var(--ink);' }, o.note));
    if (def.help) {
      const help = el('div', { class: 'fhelp', text: def.help, hidden: true });
      lab.appendChild(el('button', { class: 'qmark', text: '?', type: 'button', title: 'what this does', onclick: (e) => { e.preventDefault(); help.hidden = !help.hidden; } }));
      r.appendChild(help);
    }
    return r;
  }

  /** pass 70 (Garry: "Every 'inherited' text or value should just already be there while still being marked as
   *  inherited, so it can be edited more easily"): a box whose own value is empty shows the inherited one IN the box,
   *  greyed and italic (class `inherited`), editable in place. An edit that leaves it different makes it the box's own;
   *  emptying it, or typing the inherited text back, goes back to inheriting (null: the key is left out, sparse records
   *  stay sparse); a box nobody typed in writes nothing (no change event). `o.inherit` = {value, from}; the caller marks
   *  the row ("inherited from <from>") and listens to the box's `inheritchange` event ({detail: {own}}) to flip its mark.
   *  Returns the commit function the box's change handler calls with its text. */
  function inheritable(inp, value, o, onChange, parse, same) {
    const inh = o && o.inherit && o.inherit.value != null && o.inherit.value !== '' && typeof o.inherit.value !== 'object' ? String(o.inherit.value) : null;
    if (inh == null) return null;
    const own0 = !(value == null || value === '');
    if (!own0) { inp.value = inh; inp.classList.add('inherited'); }
    inp.dataset.inherited = inh;
    inp.title = (inp.title ? inp.title + ' · ' : '') + `inherited from ${o.inherit.from || 'its parent'}: ${inh.length > 200 ? inh.slice(0, 200) + '…' : inh} (edit it here to make it its own; empty it to inherit again)`;
    const isInh = (t) => t === '' || (same ? same(t, inh) : t.trim() === inh.trim());
    const flip = () => {
      const now = isInh(inp.value);
      inp.classList.toggle('inherited', now && inp.value !== '');
      inp.dispatchEvent(new CustomEvent('inheritchange', { detail: { own: !now }, bubbles: true }));
    };
    inp.addEventListener('input', flip);
    return (raw) => {
      if (isInh(String(raw))) {
        if (String(raw).trim() === '') inp.value = inh;
        flip();
        onChange(null);
        return;
      }
      onChange(parse ? parse(raw) : raw);
    };
  }

  function numberInput(def, value, onChange, opts) {
    const o = opts || {};
    const inp = el('input', { type: 'number', class: 'num' + (o.cls ? ' ' + o.cls : ''), value: value == null ? '' : value, placeholder: o.placeholder != null ? String(o.placeholder) : (def.def != null ? String(def.def) : ''), 'data-path': o.path || def.key });
    if (def.min != null) inp.min = def.min;
    if (def.max != null) inp.max = def.max;
    inp.step = def.int ? 1 : (def.step != null ? def.step : 'any');
    const commit = inheritable(inp, value, o, onChange, (t) => parseNum(t, def.int || def.type === 'int'), (t, inh) => t.trim() !== '' && Number(t) === Number(inh));
    inp.addEventListener('change', () => (commit ? commit(inp.value) : onChange(parseNum(inp.value, def.int || def.type === 'int'))));
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }

  /** A run-clock time: seconds in the box, "mm:ss" accepted, the clock shown beside it. */
  function secondsInput(def, value, onChange, opts) {
    const o = opts || {};
    const hint = el('span', { class: 'hint', text: value == null || value === '' ? (o.emptyText || '') : fmtT(value) });
    const inp = el('input', { type: 'text', class: 'num secs', value: value == null ? '' : value, placeholder: o.placeholder != null ? String(o.placeholder) : (def.def != null ? String(def.def) : 'seconds'), 'data-path': o.path || def.key, title: 'seconds, or mm:ss' });
    inp.addEventListener('input', () => { const v = parseT(inp.value); hint.textContent = v == null ? (o.emptyText || '') : fmtT(v); });
    inp.addEventListener('change', () => { const v = parseT(inp.value); onChange(v == null ? null : (def.int === false ? v : Math.round(v))); });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return el('span', { class: 'with-hint' }, inp, hint);
  }

  function textInput(def, value, onChange, opts) {
    const o = opts || {};
    const inp = el('input', { type: 'text', class: 'txt', value: value == null ? '' : value, placeholder: o.placeholder || '', 'data-path': o.path || def.key });
    const commit = inheritable(inp, value, o, onChange, (t) => t.trim());
    inp.addEventListener('change', () => (commit ? commit(inp.value) : onChange(inp.value.trim() === '' ? null : inp.value.trim())));
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }

  /** A multi-line text (pass 66: an asset's doc, prompts and hints): commits on change; Ctrl+Enter blurs; grows with its text. */
  function textareaInput(def, value, onChange, opts) {
    const o = opts || {};
    const ta = el('textarea', { class: 'txt area' + (o.cls ? ' ' + o.cls : ''), rows: o.rows || 2, placeholder: o.placeholder || '', 'data-path': o.path || def.key, spellcheck: false });
    ta.value = value == null ? '' : String(value);
    const grow = () => { ta.style.height = 'auto'; ta.style.height = Math.min(360, Math.max(34, ta.scrollHeight + 2)) + 'px'; };
    ta.addEventListener('input', grow);
    const commit = inheritable(ta, value, o, onChange, null);
    ta.addEventListener('change', () => (commit ? commit(ta.value) : onChange(ta.value.trim() === '' ? null : ta.value)));
    ta.addEventListener('keydown', (e) => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) ta.blur(); });
    requestAnimationFrame(grow);
    return ta;
  }

  function select(options, value, onChange, opts) {
    const o = opts || {};
    const sel = el('select', { 'data-path': o.path || '' });
    if (o.emptyLabel != null) sel.appendChild(el('option', { value: '', text: o.emptyLabel }));
    let found = value == null || value === '' && o.emptyLabel != null;
    for (const opt of options) {
      if (opt.group) {
        const g = el('optgroup', { label: opt.group });
        for (const x of opt.options) { g.appendChild(el('option', { value: x.v, text: x.label, title: x.help || '' })); if (String(x.v) === String(value)) found = true; }
        sel.appendChild(g);
      } else {
        sel.appendChild(el('option', { value: opt.v, text: opt.label, title: opt.help || '' }));
        if (String(opt.v) === String(value)) found = true;
      }
    }
    if (!found && value != null && value !== '') sel.appendChild(el('option', { value: value, text: `(unknown: ${value})`, class: 'unknown' }));
    sel.value = value == null ? '' : String(value);
    sel.addEventListener('change', () => onChange(sel.value === '' ? null : sel.value));
    return sel;
  }

  function boolInput(def, value, onChange, opts) {
    const o = opts || {};
    const cb = el('input', { type: 'checkbox', 'data-path': o.path || def.key });
    cb.checked = value == null ? !!def.def : !!value;
    cb.addEventListener('change', () => onChange(cb.checked));
    return el('span', { class: 'cb-wrap' }, cb, el('span', { class: 'cb-text', text: cb.checked ? 'yes' : 'no' }));
  }

  function bool3Input(def, value, onChange, opts) {
    const o = opts || {};
    return select([{ v: 'yes', label: 'yes' }, { v: 'no', label: 'no' }], value == null ? '' : (value ? 'yes' : 'no'), (v) => onChange(v == null ? null : v === 'yes'), { emptyLabel: o.placeholder ? `— (${o.placeholder})` : '—', path: o.path || def.key });
  }

  /** Stored as a fraction 0..1, shown as a percent. */
  function percentInput(def, value, onChange, opts) {
    const o = opts || {};
    const ph = o.placeholder != null && o.placeholder !== '' ? String(U.roundTo(Number(o.placeholder) * 100, 3)) : (def.def != null ? String(U.roundTo(def.def * 100, 3)) : '');
    const inp = el('input', { type: 'number', class: 'num pct', min: 0, max: 100, step: 'any', value: value == null ? '' : U.roundTo(Number(value) * 100, 3), placeholder: ph, 'data-path': o.path || def.key });
    inp.addEventListener('change', () => { const v = parseNum(inp.value); onChange(v == null ? null : U.roundTo(v / 100, 6)); });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return el('span', { class: 'with-hint' }, inp, el('span', { class: 'hint', text: '%' }));
  }

  // ------------------------------------------------------------------ the picture combobox (pass 54)

  let pop = null;             // the one open list: {box, anchor, close}

  function closePop() { if (pop) { const p = pop; pop = null; p.close(); } }

  /** The face of an option: its picture (or a colour swatch, or a blank) and its name. */
  function optFace(it, size, cls) {
    const pic = it.icon
      ? el('img', { class: 'isel-ico', src: it.icon, alt: '', width: size, height: size, loading: 'lazy' })
      : el('span', { class: 'isel-ico blank', style: `width:${size}px;height:${size}px` });
    const sw = it.swatch ? el('span', { class: 'isel-sw', style: `background:${it.swatch}`, title: it.swatch }) : null;
    return el('span', { class: 'isel-face' + (cls ? ' ' + cls : '') }, pic, el('span', { class: 'isel-name', text: it.label }), sw);
  }

  /** A select with pictures: a button showing the chosen option's icon and name; a click (or Enter / Space / an arrow,
   *  or typing) opens the list under it with 28 px icons, group headings and a filter box; up / down move, Enter picks,
   *  Escape closes. `options` as for select(): [{v, label, icon, swatch, help, sub, dim}] or [{group, options: [...]}]. */
  function iconSelect(options, value, onChange, opts) {
    const o = opts || {};
    const items = [];
    if (o.emptyLabel != null) items.push({ v: '', label: o.emptyLabel, icon: o.emptyIcon || '', help: o.emptyHelp || '', sub: o.emptySub || '', empty: true });
    for (const opt of options) {
      if (opt.group) for (const x of opt.options) items.push(Object.assign({ group: opt.group }, x));
      else items.push(opt);
    }
    const val = value == null ? '' : String(value);
    let cur = items.find((x) => String(x.v) === val);
    if (!cur && val !== '') cur = { v: val, label: `(unknown: ${val})`, unknown: true };
    if (!cur) cur = { v: '', label: o.placeholder || '—' };
    const btn = el('button', { type: 'button', class: 'isel' + (o.cls ? ' ' + o.cls : '') + (cur.unknown ? ' unknown' : ''), 'data-path': o.path || '', title: cur.help || cur.label || '' },
      optFace(cur, o.size || 24), el('span', { class: 'isel-caret', text: '▾' }));
    if (o.disabled) btn.disabled = true;
    const open = (initial) => openPop(btn, items, val, (v) => onChange(v === '' ? null : v), initial, o);
    btn.addEventListener('click', () => { if (pop && pop.anchor === btn) closePop(); else open(''); });
    btn.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(''); }
      else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) { e.preventDefault(); open(e.key); }
    });
    return btn;
  }

  function openPop(anchor, items, value, pick, initial, o) {
    closePop();
    const filter = el('input', { type: 'search', class: 'isel-filter', placeholder: 'type to filter…', value: initial || '', autocomplete: 'off' });
    const list = el('div', { class: 'isel-list', role: 'listbox' });
    const box = el('div', { class: 'isel-pop' }, filter, list);
    document.body.appendChild(box);
    let shown = [], hi = 0, first = true;
    const choose = (k) => {
      const s = shown[k];
      if (!s || s.it.disabled) return;
      closePop();
      anchor.focus({ preventScroll: true });
      if (String(s.it.v) !== value) pick(s.it.v);
    };
    const mark = () => {
      shown.forEach((s, k) => s.row.classList.toggle('hi', k === hi));
      const r = shown[hi];
      if (r) r.row.scrollIntoView({ block: 'nearest' });
    };
    const draw = () => {
      clear(list); shown = [];
      const q = filter.value.trim().toLowerCase();
      let group = null;
      for (const it of items) {
        if (q && !`${it.label} ${it.v} ${it.group || ''} ${it.sub || ''}`.toLowerCase().includes(q)) continue;
        if (it.group && it.group !== group) { list.appendChild(el('div', { class: 'isel-group', text: it.group })); group = it.group; }
        const k = shown.length;
        const r = el('div', { class: 'isel-opt' + (String(it.v) === value ? ' cur' : '') + (it.dim ? ' dim' : ''), role: 'option', title: it.help || '' },
          optFace(it, 28), it.sub ? el('small', { class: 'isel-sub', text: it.sub }) : null);
        r.addEventListener('pointerdown', (e) => { e.preventDefault(); choose(k); });
        r.addEventListener('pointermove', () => { if (hi !== k) { hi = k; mark(); } });
        list.appendChild(r);
        shown.push({ it, row: r });
      }
      if (!shown.length) list.appendChild(el('div', { class: 'isel-none', text: 'nothing matches' }));
      hi = first ? Math.max(0, shown.findIndex((s) => String(s.it.v) === value)) : 0;
      first = false;
      mark();
    };
    const place = () => {
      const r = anchor.getBoundingClientRect();
      const w = Math.max(r.width, o.popWidth || 280);
      box.style.width = `${w}px`;
      box.style.left = `${Math.max(6, Math.min(r.left, window.innerWidth - w - 8))}px`;
      const h = box.offsetHeight;
      const below = window.innerHeight - r.bottom - 8;
      box.style.top = `${below >= Math.min(h, 240) || below >= r.top ? r.bottom + 3 : Math.max(6, r.top - 3 - h)}px`;
      box.style.maxHeight = `${Math.max(160, Math.min(420, below >= r.top ? below - 6 : r.top - 12))}px`;
    };
    filter.addEventListener('input', () => { draw(); });
    filter.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowDown') { e.preventDefault(); hi = Math.min(shown.length - 1, hi + 1); mark(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); hi = Math.max(0, hi - 1); mark(); }
      else if (e.key === 'PageDown') { e.preventDefault(); hi = Math.min(shown.length - 1, hi + 8); mark(); }
      else if (e.key === 'PageUp') { e.preventDefault(); hi = Math.max(0, hi - 8); mark(); }
      else if (e.key === 'Enter') { e.preventDefault(); choose(hi); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closePop(); anchor.focus({ preventScroll: true }); }
      else if (e.key === 'Tab') closePop();
    });
    const outside = (e) => { if (!box.contains(e.target) && e.target !== anchor && !anchor.contains(e.target)) closePop(); };
    const onScroll = (e) => { if (!box.contains(e.target)) closePop(); };
    document.addEventListener('pointerdown', outside, true);
    window.addEventListener('scroll', onScroll, true);
    window.addEventListener('resize', closePop);
    pop = {
      box, anchor,
      close: () => {
        document.removeEventListener('pointerdown', outside, true);
        window.removeEventListener('scroll', onScroll, true);
        window.removeEventListener('resize', closePop);
        box.remove();
        anchor.classList.remove('open');
      },
    };
    anchor.classList.add('open');
    draw();
    place();
    filter.focus({ preventScroll: true });
    if (initial) filter.setSelectionRange(initial.length, initial.length);
  }

  // ------------------------------------------------------------------ creatures

  function creatureGroups(prefer) {
    const S = App.S;
    const by = { boss: [], elite: [], creature: [], special: [], retired: [], hidden: [] };
    for (const c of S.enemies) {
      const opt = { v: c.id, label: c.name, icon: c.icon_play || c.icon, sub: `HP ${fmtN(c.hp)} · bite ${fmtN(c.damage)} · ${fmtN(c.speed)} m/s${c.play ? ' · ' + c.play : ''}`, help: `${c.id}: HP ${c.hp}, bite ${c.damage}, speed ${c.speed}` };
      if (c.hidden) by.hidden.push(opt);
      else if (c.retired) by.retired.push(opt);
      else if (c.kind === 'boss') by.boss.push(opt);
      else if (c.archetype === 'elite') by.elite.push(opt);
      else if (c.max_alive === 1) by.special.push(opt);
      else by.creature.push(opt);
    }
    const groups = [
      { key: 'creature', group: 'Creatures', options: by.creature },
      { key: 'elite', group: 'Elites', options: by.elite },
      { key: 'boss', group: 'Bosses', options: by.boss },
      { key: 'special', group: 'Specials', options: by.special },
      { key: 'retired', group: 'Retired', options: by.retired },
      { key: 'hidden', group: 'Hidden', options: by.hidden },
    ].filter((g) => g.options.length);
    if (prefer) groups.sort((a, b) => (a.key === prefer ? -1 : b.key === prefer ? 1 : 0));
    return groups;
  }

  /** The creature's defaults in one line (what an override replaces). */
  function creatureSummary(id) {
    const c = App.creature(id);
    if (!c) return el('div', { class: 'cdefaults bad', text: id ? `unknown creature "${id}"` : 'no creature' });
    const parts = [`HP ${fmtN(c.hp)}`, `bite ${fmtN(c.damage)}`, `${fmtN(c.speed)} m/s`, `${fmtN(c.size)} m`, `pack ${c.pack_size}`, `knock ${fmtN(App.knockbackOf(c, null), 2)}`];
    if (Number(c.cap_share) !== 1) parts.push(`${fmtN(c.cap_share)} slot`);
    if (c.max_alive) parts.push(`max ${c.max_alive} alive`);
    if (c.damage_reduction) parts.push(`DR ${Math.round(c.damage_reduction * 100)}%`);
    if (c.knockback_resist) parts.push(`KB resist ${Math.round(c.knockback_resist * 100)}%`);
    if (c.ranged) parts.push('ranged');
    if (c.charge) parts.push('charger');
    if (c.boss) parts.push(`attacks: ${[...new Set(c.boss.attacks)].join(', ')}`);
    const tags = [];
    if (c.kind === 'boss') tags.push('boss');
    if (c.archetype === 'elite') tags.push('elite');
    if (c.retired) tags.push('retired');
    if (c.hidden) tags.push('hidden');
    if (!c.can_be_elite) tags.push('never coloured');
    return el('div', { class: 'cdefaults' }, el('span', { text: parts.join(' · ') }), tags.map((t) => el('span', { class: 'tag ' + t.replace(/ /g, '-'), text: t })));
  }

  /** The creature combobox (pictures of the looks in play) and the creature's defaults under it. */
  function enemyPick(value, onChange, opts) {
    const o = opts || {};
    const sel = iconSelect(creatureGroups(o.prefer), value || '', onChange, { emptyLabel: o.emptyLabel, path: o.path || 'enemy', size: 28, cls: 'wide', popWidth: 330 });
    return el('div', { class: 'enemy-pick' }, sel, o.summary === false ? null : creatureSummary(value));
  }

  /** The creature's art variants with their pictures; the empty choice is the creature's default look (pass 58: "Default
   *  (SK-A)", the look its JSON plays, set on the Creatures tab; a row that names none follows it when it changes). A code
   *  picked here pins the row to that look. */
  function variantSelect(enemyId, value, onChange, opts) {
    const o = opts || {};
    const c = App.creature(enemyId);
    const vs = c ? c.variants : [];
    const codeOpt = (v) => ({
      v: v.code,
      label: v.code + (v.code === c.play ? ' · the default' : '') + (v.base ? ' · base strip' : '') + (v.ready ? '' : ' · not painted yet') + (v.shelved ? ' · shelved' : ''),
      icon: v.icon, help: `${v.note || ''}${v.note ? ' · ' : ''}this row plays ${v.code} whatever the default${v.shelved ? ' (shelved: out of the arena and the default lists, a row naming it still plays it)' : ''}`, sub: v.note || '', dim: !v.ready || !!v.shelved,
    });
    // pass 66: shelved looks sit in a dim group at the end
    const live = vs.filter((v) => !v.shelved).map(codeOpt), shelved = vs.filter((v) => !!v.shelved).map(codeOpt);
    const codes = shelved.length ? [{ group: 'Looks', options: live }, { group: 'Shelved', options: shelved }] : live;
    const inPlay = c ? (c.play || c.variant || '') : '';
    const sel = iconSelect(codes, value || '', onChange, {
      emptyLabel: c ? (inPlay ? `Default (${inPlay})` : 'Default (its one painting)') : '—', emptyIcon: c ? c.icon_play || c.icon : '',
      emptyHelp: 'the creature\'s default look (the Creatures tab sets it): this row follows it when it changes', emptySub: 'follows the Creatures tab', path: o.path || 'variant', popWidth: 300,
    });
    if (!codes.length && !value) { sel.disabled = true; sel.title = 'this creature has one painting'; }
    if (value && c) sel.title = `this row plays ${value} (pinned); the default is ${inPlay || 'its one painting'}: pick "Default" to follow it`;
    return sel;
  }

  function eliteSelect(value, onChange, opts) {
    const o = opts || {};
    const options = App.S.elites.map((e) => ({ v: e.id, label: e.name, icon: e.icon, swatch: e.outline || '', help: e.id }));
    if (o.allowRandom) options.unshift({ v: 'random', label: 'random modifier', help: 'one of the modifiers at random' });
    return iconSelect(options, value || '', onChange, { emptyLabel: o.emptyLabel || 'none', path: o.path || 'elite' });
  }

  function pickupSelect(value, onChange, opts) {
    const o = opts || {};
    const list = App.S.pickups.filter((p) => o.all || !p.small);
    return iconSelect(list.map((p) => ({ v: p.id, label: p.name + (p.small ? ' (small)' : ''), icon: p.icon, help: p.id })), value || '', onChange, { emptyLabel: o.emptyLabel == null ? '—' : o.emptyLabel, emptyIcon: o.emptyIcon || '', path: o.path || 'pickup' });
  }

  /** A number, or [min, max]: two boxes; equal or empty max writes one number (unless the file had a list). */
  function intervalInput(def, value, onChange, opts) {
    const o = opts || {};
    const isList = Array.isArray(value);
    const lo = isList ? value[0] : value, hi = isList ? value[value.length - 1] : null;
    const a = el('input', { type: 'number', class: 'num short', min: 0, step: 'any', value: lo == null ? '' : lo, placeholder: def.def != null ? String(def.def) : 'min', 'data-path': (o.path || def.key) + '.0' });
    const b = el('input', { type: 'number', class: 'num short', min: 0, step: 'any', value: hi == null ? '' : hi, placeholder: 'max', 'data-path': (o.path || def.key) + '.1' });
    const fire = () => {
      const x = parseNum(a.value), y = parseNum(b.value);
      if (x == null && y == null) return onChange(null);
      if (y == null || (!isList && y === x)) return onChange(x == null ? y : x);
      onChange([x == null ? y : x, y]);
    };
    a.addEventListener('change', fire); b.addEventListener('change', fire);
    // pass 111 (lane CHEST): a range in another unit (a chest's throw distance in metres) names it in `def.unit`
    return el('span', { class: 'interval' }, a, el('span', { class: 'hint', text: 'to' }), b, el('span', { class: 'hint', text: def.unit != null ? def.unit : 's' }));
  }

  /** A short list of numbers, one box each, with add / remove (stage_mults, hell_cap, weapon_cap...). */
  function numberList(def, arr, onChange, opts) {
    const o = opts || {};
    const list = Array.isArray(arr) ? arr.slice() : [];
    const wrap = el('div', { class: 'numlist' });
    list.forEach((v, k) => {
      const inp = el('input', { type: 'number', class: 'num short', step: def.int || o.int ? 1 : 'any', value: v, 'data-path': `${o.path || def.key}.${k}`, title: o.labels ? o.labels(k) : `#${k + 1}` });
      inp.addEventListener('change', () => { const n = parseNum(inp.value, def.int || o.int); if (n == null) return; const c = list.slice(); c[k] = n; onChange(c); });
      inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
      wrap.appendChild(el('span', { class: 'numlist-item' }, o.labels ? el('small', { text: o.labels(k) }) : null, inp,
        el('button', { class: 'x', type: 'button', title: 'remove', text: '×', onclick: () => { const c = list.slice(); c.splice(k, 1); onChange(c); } })));
    });
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+', title: 'add one', onclick: () => onChange(list.concat([list.length ? list[list.length - 1] : (def.int || o.int ? 1 : 1.0)])) }));
    return wrap;
  }

  /** "79, 140, 200" -> [79, 140, 200]: a stage's path offers as one line of numbers. */
  function numbersLine(values, onChange, opts) {
    const o = opts || {};
    const inp = el('input', { type: 'text', class: 'txt', value: (values || []).join(', '), placeholder: o.placeholder || 'seconds into the stage, comma-separated', 'data-path': o.path || '' });
    inp.addEventListener('change', () => {
      const out = [];
      for (const part of inp.value.split(/[,\s;]+/)) { if (part.trim() === '') continue; const v = parseT(part); if (v != null) out.push(Math.round(v)); }
      onChange(out);
    });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }

  // ------------------------------------------------------------------ colours (pass 54: the variance block)

  const HEX_RE = /^#?([0-9a-f]{6})$/i;
  /** "#8a1428" / "8A1428" -> "#8A1428" (the creature files spell their tints in capitals); null when it is not a colour. */
  const normHex = (s) => { const m = String(s == null ? '' : s).trim().match(HEX_RE); return m ? '#' + m[1].toUpperCase() : null; };

  /** One colour: a swatch that opens the colour picker, the hex in a box, × back to the creature's own (the placeholder,
   *  shown faded when nothing is set). */
  function swatchInput(value, onChange, opts) {
    const o = opts || {};
    const ph = normHex(o.placeholder);
    const cur = normHex(value);
    // pass 79 (lane WORLD): `own` names whose default an empty box plays (a map's colour: "the game's")
    const own = o.own || 'the creature\'s own';
    const color = el('input', { type: 'color', class: 'sw-color' + (cur ? '' : ' ph'), value: (cur || ph || '#ffffff').toLowerCase(), 'data-path': (o.path || '') + '#', title: cur ? cur : (ph ? `${own} ${ph}: pick to override` : 'pick a colour') });
    const txt = el('input', { type: 'text', class: 'txt hex', value: cur || '', placeholder: ph || '#RRGGBB', 'data-path': o.path || '', maxlength: 7, spellcheck: false });
    color.addEventListener('change', () => onChange(color.value.toUpperCase()));
    txt.addEventListener('change', () => {
      const v = txt.value.trim();
      if (v === '') { onChange(null); return; }
      const h = normHex(v);
      if (h) onChange(h); else { txt.value = cur || ''; App.toast(`"${v}" is not a colour: #RRGGBB`); }
    });
    txt.addEventListener('keydown', (e) => { if (e.key === 'Enter') txt.blur(); });
    return el('span', { class: 'swatch' }, color, txt, cur ? el('button', { class: 'x', type: 'button', text: '×', title: `back to ${own}`, onclick: () => onChange(null) }) : null);
  }

  /** A list of colours (variance.tints): unset shows the creature's own list faded with "Edit a copy"; set, a swatch per
   *  tint with ×, "+" to add one and "creature's own" to drop the list. A list here replaces the creature's whole list. */
  function swatchesInput(list, onChange, opts) {
    const o = opts || {};
    const ph = Array.isArray(o.placeholder) ? o.placeholder.map(normHex).filter(Boolean) : [];
    const wrap = el('div', { class: 'swatches' + (Array.isArray(list) ? '' : ' unset') });
    if (!Array.isArray(list)) {
      wrap.appendChild(el('span', { class: 'sw-own', title: 'the creature\'s own tints' }, ph.length ? ph.map((h) => el('span', { class: 'sw-chip', style: `background:${h}`, title: h })) : el('span', { class: 'muted small', text: 'none of its own' })));
      wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: ph.length ? 'Edit a copy' : '+ tint', 'data-path': o.path || '', title: 'start this row\'s own list from the creature\'s', onclick: () => onChange(ph.length ? ph.slice() : ['#FFFFFF']) }));
      return wrap;
    }
    list.forEach((h, k) => {
      const color = el('input', { type: 'color', class: 'sw-color', value: (normHex(h) || '#ffffff').toLowerCase(), title: String(h), 'data-path': `${o.path || ''}.${k}` });
      color.addEventListener('change', () => { const c = list.slice(); c[k] = color.value.toUpperCase(); onChange(c); });
      wrap.appendChild(el('span', { class: 'sw-item' }, color, el('button', { class: 'x', type: 'button', text: '×', title: `remove ${h}`, onclick: () => { const c = list.slice(); c.splice(k, 1); onChange(c); } })));
    });
    if (!list.length) wrap.appendChild(el('span', { class: 'muted small', text: 'no tints: every one plain' }));
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+', title: 'add a tint', onclick: () => onChange(list.concat([list.length ? normHex(list[list.length - 1]) || '#FFFFFF' : '#FFFFFF'])) }));
    wrap.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: 'creature\'s own', title: 'drop this list: the creature\'s own tints again', onclick: () => onChange(null) }));
    return wrap;
  }

  // ------------------------------------------------------------------ one field by its type (the scalar-ish kinds)

  /** A control for `def` bound to `obj[def.key]` (dotted keys allowed); composite types live in the inspector. */
  function control(def, obj, opts) {
    const o = opts || {};
    const value = U.getPath(obj, def.key);
    // pass 113 (lane TASKS): `limits(obj)` {min, max, hint} narrows a number to what applies now (an item_level quest's
    // Level to that item's own levels); a value past them is brought inside on the next change
    const lim = typeof def.limits === 'function' ? (def.limits(obj) || {}) : {};
    if (lim.min != null || lim.max != null) def = Object.assign({}, def, lim.min != null ? { min: lim.min } : {}, lim.max != null ? { max: lim.max } : {});
    // pass 66: an asset document hands its own apply (Assets.apply bound to the document); the map's is App.apply
    const applyFn = typeof o.apply === 'function' ? o.apply : App.apply;
    const write = (v0) => applyFn(() => {
      let v = v0;
      if (typeof v === 'number' && lim.max != null) v = Math.min(v, lim.max);
      if (typeof v === 'number' && lim.min != null) v = Math.max(v, lim.min);
      if (def.key.includes('.')) U.setPath(obj, def.key, v);
      else U.setKey(obj, def.key, v, def.def);
      if (o.after) o.after(v);
    }, o.what || 'all');
    const ctl = { path: o.pathPrefix ? `${o.pathPrefix}.${def.key}` : def.key, placeholder: o.placeholder, cls: o.cls, inherit: o.inherit, own: o.own };
    switch (def.type) {
      case 'int': case 'number': {
        const box = numberInput(def, value, write, ctl);
        if (!lim.hint) return box;
        const over = typeof value === 'number' && ((lim.max != null && value > lim.max) || (lim.min != null && value < lim.min));
        return el('span', { class: 'with-hint' }, box, el('span', { class: 'hint' + (over ? ' bad' : ''), text: over ? `${lim.hint}: ${value} is out of range` : lim.hint, 'data-limits': def.key }));
      }
      case 'seconds': {
        // pass 116 (lane EDITOR): a run-clock second (def.clock) on a stage tab reads and writes from the stage's start
        const off = def.clock && o.stageClock !== false && typeof App !== 'undefined' && typeof App.stageOffset === 'function' ? App.stageOffset() : null;
        if (off == null || typeof StageModel === 'undefined') return secondsInput(def, value, write, ctl);
        const box = secondsInput(def, StageModel.toStageClock(value, off), (v) => write(v == null ? v : Math.round(StageModel.fromStageClock(v, off))), Object.assign({}, ctl, { placeholder: ctl.placeholder }));
        return el('span', { class: 'with-hint', title: `stage clock: 0:00 = this stage's start (${fmtT(off)} on the map clock); saved as the map clock` }, box,
          el('span', { class: 'hint muted', text: value == null || value === '' ? '' : `map ${fmtT(value)}` }));
      }
      case 'text': return textInput(def, value, write, ctl);
      case 'textarea': return textareaInput(def, value, write, Object.assign({ rows: o.rows }, ctl));
      case 'select': return select(def.options, value == null ? (def.def == null ? '' : def.def) : value, (v) => write(v == null ? def.def : v), { path: ctl.path });
      case 'bool': return boolInput(def, value, write, ctl);
      case 'bool3': return bool3Input(def, value, write, ctl);
      case 'percent': return percentInput(def, value, write, ctl);
      case 'elite': return eliteSelect(value, (v) => write(v == null ? null : v), { allowRandom: o.allowRandom, path: ctl.path, emptyLabel: o.emptyLabel });
      case 'interval': return intervalInput(def, value, write, ctl);
      case 'list': return numberList(def, value, write, { path: ctl.path, labels: o.labels, int: def.int });
      case 'pickup': return pickupSelect(value, write, { path: ctl.path, all: o.allPickups });
      case 'swatch': return swatchInput(value, write, ctl);
      case 'swatches': return swatchesInput(value, write, ctl);
      // pass 84 (lane TIMELINE): the density floor's points (Settings -> Cap, the Floor lane's inspector)
      case 'floor_points': return floorBlock(obj);
      default: return el('span', { class: 'muted', text: `(${def.type})` });
    }
  }

  /** A full row for a scalar-ish field of `obj`. */
  function fieldRow(def, obj, opts) {
    return row(def, control(def, obj, opts), opts);
  }

  // ------------------------------------------------------------------ the blocks Settings and the inspector share

  /** A point list as numbers: time (seconds or mm:ss) and a value per point, × to remove, "+ point" (the cap curve, a
   *  curve's manual points, a roster row's presence). `get()` returns the live list inside App.S; `spec` names the value
   *  column and its limits. */
  function pointsTable(get, spec) {
    const sp = spec || {};
    const pts = get() || [];
    const wrap = el('div', { class: 'points' + (sp.extra ? ' with-extra' : '') + (sp.dim ? ' dim' : '') });
    wrap.appendChild(el('div', { class: 'points-head' }, el('span', { text: 'time' }), el('span', { text: sp.valueLabel || 'value' }), sp.extra ? el('span', { text: sp.extraLabel || '' }) : null, el('span')));
    const rows = [];
    pts.forEach((p, k) => {
      const t = el('input', { type: 'text', class: 'num secs', value: p[0], 'data-path': `${sp.path}.${k}.0`, title: 'seconds or mm:ss' });
      const v = el('input', { type: 'number', class: 'num short', value: p[1], min: sp.min == null ? 0 : sp.min, step: sp.step == null ? 'any' : sp.step, 'data-path': `${sp.path}.${k}.1` });
      t.addEventListener('change', () => { const n = parseT(t.value); if (n == null) return; App.apply(() => { const L = get(); L[k][0] = Math.max(0, Math.round(n)); App.sortPoints(L); }); });
      v.addEventListener('change', () => { const n = parseNum(v.value, sp.int); if (n == null) return; App.apply(() => { get()[k][1] = Math.max(sp.min == null ? 0 : sp.min, n); }); });
      for (const i of [t, v]) i.addEventListener('keydown', (e) => { if (e.key === 'Enter') i.blur(); });
      const canRemove = pts.length > (sp.minPoints || 0);
      const hintT = el('span', { class: 'hint', text: fmtT(p[0]) });
      const extraEl = sp.extra ? el('span', { class: 'hint', text: sp.extra(p, k) }) : null;
      rows.push({ t, v, hintT, extraEl });
      wrap.appendChild(el('div', { class: 'points-row' }, el('span', { class: 'with-hint' }, t, hintT), v, extraEl,
        el('button', { class: 'x', type: 'button', text: '×', title: canRemove ? 'remove the point' : `at least ${sp.minPoints} points`, disabled: !canRemove, onclick: () => App.apply(() => { get().splice(k, 1); }) })));
    });
    // the boxes brought up to date in place (pass 58 review: a roster row's Presence times stayed put while its bar was
    // dragged; Inspector.live calls this on every move)
    wrap.refresh = () => {
      const L = get() || [];
      rows.forEach((row, k) => {
        const p = L[k];
        if (!Array.isArray(p)) return;
        if (document.activeElement !== row.t) row.t.value = p[0];
        row.hintT.textContent = fmtT(p[0]);
        if (document.activeElement !== row.v) row.v.value = p[1];
        if (row.extraEl) row.extraEl.textContent = sp.extra(p, k);
      });
    };
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ point', onclick: () => App.apply(() => {
      const L = sp.ensure ? sp.ensure() : get();
      const last = L[L.length - 1] || sp.first || [0, 1];
      L.push([Number(last[0]) + (sp.gap || 60), Number(last[1])]);
    }) }));
    return wrap;
  }

  /** The cap curve's points as numbers. */
  function pointsBlock(tl) {
    return pointsTable(() => (Array.isArray(tl.cap_curve) ? tl.cap_curve : []), {
      path: 'cap_curve', valueLabel: 'cap', int: true, step: 1, first: [0, Number(tl.cap_start) || 10],
      ensure: () => { if (!Array.isArray(tl.cap_curve)) tl.cap_curve = []; return tl.cap_curve; },
    });
  }

  /** The floor curve's points (pass 84, lane TIMELINE): [seconds, creatures alive at the least]; "+ point" starts the
   *  curve at 0:00 with 20 when the map has none. */
  function floorBlock(tl) {
    return pointsTable(() => (Array.isArray(tl.floor_curve) ? tl.floor_curve : []), {
      path: 'floor_curve', valueLabel: 'alive at least', int: true, step: 1, first: [0, 20],
      ensure: () => { if (!Array.isArray(tl.floor_curve)) tl.floor_curve = []; return tl.floor_curve; },
    });
  }

  /** A roster row's presence keyframes (pass 54): time, weight, the row's share of its channel at that time, at least two
   *  points to remove one. */
  function weightsBlock(r, opts) {
    // pass 110 (lane BOSS): a boss fight window's row reads its shares from the window's open rows (opts.rosterAt)
    const rosterAt = opts && typeof opts.rosterAt === 'function' ? opts.rosterAt : App.rosterAt;
    return pointsTable(() => (Array.isArray(r.weights) ? r.weights : []), {
      path: 'weights', valueLabel: 'weight', step: 0.5, minPoints: 2, first: [Number(r.t) || 0, 5],
      ensure: () => { if (!Array.isArray(r.weights)) r.weights = Model.keyframesOf(r, App.tl().weight_late_t); return r.weights; },
      extra: (p) => {
        const t = Number(p[0]) || 0;
        const open = rosterAt(t).find((o) => o.row === r);
        // pass 81 (lane PACE): a row paced as waves is not in the draw; its weight only holds its waves at 0
        if (open && !open.drawn) return open.w > 0 ? 'waves' : 'held';
        return open ? `${Math.round(open.norm * 100)}%` : 'closed';
      },
      extraLabel: 'share',
    });
  }

  /** The HP x / ATK x curve (pass 54): manual points or a formula, both kept in the file; the samples at the stage marks.
   *  Switching to manual seeds the points from the formula at the stage marks, so the line does not jump. */
  function curveBlock(tl, key) {
    const isHp = key === 'hp_curve';
    const wrap = el('div', { class: 'block-form curve-form' });
    const c = U.isObj(tl[key]) && Object.keys(tl[key]).length ? tl[key] : null;
    const SL = App.stageLength(), marks = [];
    for (let k = 0; k <= App.stages(); k++) marks.push(k * SL);
    const samples = (f) => marks.map((t) => `${fmtT(t)} ×${fmtN(f(t), 2)}`).join(' · ');
    const g = tl.hp_growth == null ? Model.DEF.hp_growth : Number(tl.hp_growth), p = tl.hp_power == null ? Model.DEF.hp_power : Number(tl.hp_power);
    const legacy = { kind: 'power', a: g, b: p };
    if (!c) {
      wrap.appendChild(el('p', { class: 'muted small', text: isHp
        ? `No HP curve: the legacy formula (1 + hp_growth × minutes)^hp_power = (1 + ${fmtN(g, 4)} × m)^${fmtN(p, 3)}: ${samples((t) => Model.formulaAt(legacy, t))}.`
        : 'No damage curve: creature damage ×1 over the run clock (the stage multiplier, the hero\'s level and creature_damage_mult still apply).' }));
      const acts = el('div', { class: 'alt-actions' });
      if (isHp) {
        acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Start from the legacy formula', title: 'an hp_curve in formula mode with hp_growth / hp_power as a and b (the same numbers in play)', onclick: () => App.apply((d) => { d.hp_curve = { mode: 'formula', formula: { kind: 'power', a: g, b: p }, points: Model.seedPoints(d, legacy) }; }) }));
        acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Start with manual points', title: 'points at the stage marks on the legacy line, to drag', onclick: () => App.apply((d) => { d.hp_curve = { mode: 'points', points: Model.seedPoints(d, legacy), formula: { kind: 'power', a: g, b: p } }; }) }));
      } else {
        acts.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Add a damage curve (×1 flat)', onclick: () => App.apply((d) => { d.damage_curve = { mode: 'points', points: [[0, 1], [App.runEnd(), 1]], formula: { kind: 'linear', a: 0 } }; }) }));
      }
      wrap.appendChild(acts);
      return wrap;
    }
    const mode = Model.curveMode(c);
    const modeDef = FIELDS.CURVE.find((d) => d.key === 'mode');
    wrap.appendChild(row(modeDef, select(modeDef.options, mode, (v) => App.apply(() => {
      if (v === 'points') {
        c.points = Model.seedPoints(App.tl(), U.isObj(c.formula) ? c.formula : (isHp ? legacy : { kind: 'linear', a: 0 }));
        c.mode = 'points';
        App.toast('Manual points: seeded from the formula at the stage marks');
      } else c.mode = 'formula';
    }), { path: `${key}.mode` })));
    const f = U.isObj(c.formula) ? c.formula : {};
    const fdim = mode !== 'formula';
    const kindDef = FIELDS.CURVE.find((d) => d.key === 'formula.kind');
    const writeF = (k, v) => App.apply(() => { if (!U.isObj(c.formula)) c.formula = {}; U.setPath(c.formula, k, v); });
    const fbox = el('div', { class: 'formula' + (fdim ? ' dim' : '') });
    fbox.appendChild(row(kindDef, select(kindDef.options, f.kind == null ? 'power' : f.kind, (v) => writeF('kind', v), { path: `${key}.formula.kind` })));
    for (const k of ['a', 'b']) {
      if (k === 'b' && (f.kind || 'power') !== 'power') continue;
      const d = FIELDS.CURVE.find((x) => x.key === 'formula.' + k);
      fbox.appendChild(row(d, numberInput(d, f[k], (v) => writeF(k, v), { path: `${key}.formula.${k}`, placeholder: k === 'a' ? Model.FORMULA_DEF.a : Model.FORMULA_DEF.b })));
    }
    if (fdim) fbox.appendChild(el('p', { class: 'muted small', text: 'The formula is kept in the file and used when the mode is "formula".' }));
    else fbox.appendChild(el('p', { class: 'muted small', text: `The line is this formula: ${samples((t) => Model.formulaAt(f, t))}.` }));
    wrap.appendChild(fbox);
    const pbox = el('div', { class: 'curve-points' + (mode === 'points' ? '' : ' dim') });
    pbox.appendChild(el('div', { class: 'fsection' }, el('h3', { text: mode === 'points' ? 'Points (drag them on the lane)' : 'Points (a saved copy: the formula draws the line)' })));
    pbox.appendChild(pointsTable(() => (Array.isArray(c.points) ? c.points : []), {
      path: `${key}.points`, valueLabel: '× multiplier', step: 0.05, minPoints: 1, first: [0, 1],
      ensure: () => { if (!Array.isArray(c.points)) c.points = []; return c.points; },
    }));
    if (mode !== 'points') pbox.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Re-seed from the formula', title: 'overwrite the saved points with the formula at the stage marks', onclick: () => App.apply(() => { c.points = Model.seedPoints(App.tl(), f); }) }));
    wrap.appendChild(pbox);
    wrap.appendChild(el('p', { class: 'muted small', text: `In play: ${samples((t) => Model.curveMult(c, t))}.` }));
    wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small danger', type: 'button', text: 'Remove the curve', title: isHp ? 'back to the legacy hp_growth / hp_power' : 'back to ×1', onclick: () => App.apply((d) => { delete d[key]; }) })));
    return wrap;
  }

  /** Where the roster's bursts and the waves come from (pass 54): the mode, the four sides' weights as a compass round a
   *  little screen, the facing rule's share and spread. Absent = the facing rule. */
  function spawnSidesBlock(tl) {
    const ss = U.isObj(tl.spawn_sides) ? tl.spawn_sides : null;
    const mode = ss && ss.mode ? ss.mode : 'facing';
    const def = (k) => FIELDS.SCALARS.find((d) => d.key === 'spawn_sides.' + k);
    const write = (k, v) => App.apply((d) => {
      if (!U.isObj(d.spawn_sides)) d.spawn_sides = {};
      U.setPath(d.spawn_sides, k, v);
      if (!Object.keys(d.spawn_sides).length) delete d.spawn_sides;
    });
    const wrap = el('div', { class: 'block-form sides-form' });
    const md = def('mode');
    wrap.appendChild(row(md, select(md.options, mode, (v) => App.apply((d) => {
      if (!U.isObj(d.spawn_sides)) d.spawn_sides = {};
      d.spawn_sides.mode = v;
      // screen sides with no weights yet start from Garry's 55 / 15 / 15 / 15 (pass 54)
      if (v === 'sides' && !['top', 'bottom', 'left', 'right'].some((s) => Number(d.spawn_sides[s]) > 0)) Object.assign(d.spawn_sides, { top: 55, bottom: 15, left: 15, right: 15 });
    }), { path: 'spawn_sides.mode' })));
    const sides = ['top', 'bottom', 'left', 'right'];
    const w = {};
    for (const s of sides) w[s] = ss && ss[s] != null ? Math.max(0, Number(ss[s]) || 0) : 0;
    const total = sides.reduce((a, s) => a + w[s], 0);
    const cell = (s) => {
      const d = def(s);
      const inp = numberInput(d, ss ? ss[s] : null, (v) => write(s, v), { path: `spawn_sides.${s}`, placeholder: 0, cls: 'short' });
      return el('div', { class: 'compass-cell c-' + s, title: d.help }, el('div', { class: 'compass-label', text: d.label }), inp,
        el('div', { class: 'hint', text: total > 0 ? `${Math.round(w[s] / total * 100)}%` : '—' }));
    };
    // a portrait screen with the hero in the middle and a band on each edge as thick as its share
    const pic = U.svg('svg', { class: 'compass-pic', viewBox: '0 0 70 110', width: 70, height: 110 });
    pic.appendChild(U.svg('rect', { x: 8, y: 8, width: 54, height: 94, rx: 7, class: 'cp-screen' }));
    const band = (s) => (total > 0 ? 2 + 12 * (w[s] / total) : 2);
    pic.appendChild(U.svg('rect', { x: 14, y: 2, width: 42, height: band('top'), rx: 2, class: 'cp-band' }));
    pic.appendChild(U.svg('rect', { x: 14, y: 108 - band('bottom'), width: 42, height: band('bottom'), rx: 2, class: 'cp-band' }));
    pic.appendChild(U.svg('rect', { x: 2, y: 24, width: band('left'), height: 62, rx: 2, class: 'cp-band' }));
    pic.appendChild(U.svg('rect', { x: 68 - band('right'), y: 24, width: band('right'), height: 62, rx: 2, class: 'cp-band' }));
    pic.appendChild(U.svg('circle', { cx: 35, cy: 55, r: 4.5, class: 'cp-hero' }));
    const compass = el('div', { class: 'compass' + (mode === 'sides' ? '' : ' dim') }, cell('top'), cell('left'), el('div', { class: 'compass-cell c-mid' }, pic), cell('right'), cell('bottom'));
    wrap.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Side weights', title: 'top / bottom / left / right of the screen (north is up under the fixed camera)' }), el('div', { class: 'fctl' }, compass)));
    const fbox = el('div', { class: mode === 'facing' ? '' : 'dim' });
    for (const k of ['facing_share', 'facing_spread_deg']) {
      const d = def(k);
      const ctl = d.type === 'percent' ? percentInput(d, ss ? ss[k] : null, (v) => write(k, v), { path: `spawn_sides.${k}` }) : numberInput(d, ss ? ss[k] : null, (v) => write(k, v), { path: `spawn_sides.${k}` });
      fbox.appendChild(row(d, ctl));
    }
    wrap.appendChild(fbox);
    wrap.appendChild(el('p', { class: 'muted small', text: mode === 'sides'
      ? (total > 0 ? 'Each roster burst and wave picks a side by these weights, then a point 19–24 m out within ±45° of it. Rings, swarms, the portal wave, bosses and Elite bosses come as before.' : 'Every side weighs 0: the game plays the facing rule instead.')
      : `The old rule: ${Math.round((ss && ss.facing_share != null ? Number(ss.facing_share) : 0.7) * 100)}% of the spawns ahead of the hero within ±${ss && ss.facing_spread_deg != null ? ss.facing_spread_deg : 60}°, the rest anywhere round him.` }));
    if (ss) wrap.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small danger', type: 'button', text: 'Remove the block', title: 'no spawn_sides: the facing rule', onclick: () => App.apply((d) => { delete d.spawn_sides; }) })));
    return wrap;
  }

  function specialsBlock(tl) {
    const wrap = el('div', { class: 'block-form' });
    if (!U.isObj(tl.specials) || !Object.keys(tl.specials).length) {
      wrap.appendChild(el('p', { class: 'muted', text: 'This map has no specials block.' }));
      wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Add specials', onclick: () => App.apply((d) => { d.specials = { from: Math.round(App.stageLength() / 2), interval: [60, 90], max_alive: 1, pool: [] }; }) }));
      return wrap;
    }
    const sp = tl.specials;
    for (const def of FIELDS.SPECIALS) wrap.appendChild(fieldRow(def, sp, { pathPrefix: 'specials' }));
    const pool = Array.isArray(sp.pool) ? sp.pool : (sp.pool = []);
    const tbl = el('div', { class: 'mini-table' }, el('div', { class: 'mini-head' }, el('span', { text: 'creature' }), el('span', { text: 'from stage' }), el('span')));
    pool.forEach((rowv, k) => {
      const isStr = typeof rowv === 'string';
      const id = isStr ? rowv : rowv.enemy;
      const sel = iconSelect(creatureGroups('special'), id || '', (v) => App.apply(() => { if (isStr) pool[k] = v; else pool[k].enemy = v; }), { path: `specials.pool.${k}.enemy`, popWidth: 330 });
      const st = el('input', { type: 'number', class: 'num short', min: 1, max: 9, step: 1, value: isStr ? '' : (rowv.stage == null ? '' : rowv.stage), placeholder: '1', 'data-path': `specials.pool.${k}.stage` });
      st.addEventListener('change', () => App.apply(() => { const n = parseNum(st.value, true); if (isStr) pool[k] = { enemy: id }; U.setKey(pool[k], 'stage', n, 1); }));
      tbl.appendChild(el('div', { class: 'mini-row' }, el('span', { class: 'cell-ico' }, sel), st,
        el('button', { class: 'x', type: 'button', text: '×', title: 'remove', onclick: () => App.apply(() => { pool.splice(k, 1); }) })));
    });
    tbl.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ special', onclick: () => App.apply(() => { const c = App.S.enemies.find((x) => x.max_alive === 1 && !x.hidden) || App.S.enemies[0]; pool.push({ enemy: c ? c.id : '' }); }) }));
    wrap.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Pool', title: 'the specials that may come; a row with a stage waits for it' }), el('div', { class: 'fctl' }, tbl)));
    return wrap;
  }

  function pathTimesBlock(tl) {
    const wrap = el('div', { class: 'block-form' });
    const pt = Array.isArray(tl.path_times) ? tl.path_times : [];
    // pass 87: each stage's own length (stage_list)
    const SL = App.stageLength();
    pt.forEach((list, s) => {
      const line = numbersLine(list, (vals) => App.apply((d) => { d.path_times[s] = vals; }), { path: `path_times.${s}`, placeholder: `seconds into stage ${s + 1}` });
      wrap.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: s === pt.length - 1 && s < App.stages() - 1 ? `Stage ${s + 1}+` : `Stage ${s + 1}`, title: `seconds into the stage (0–${App.stageLen(Math.min(s, App.stages() - 1))}); the last list holds for later stages` }),
        el('div', { class: 'fctl' }, line, el('button', { class: 'x', type: 'button', text: '×', title: 'remove this stage\'s list', onclick: () => App.apply((d) => { d.path_times.splice(s, 1); }) }))));
    });
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ stage list', onclick: () => App.apply((d) => { if (!Array.isArray(d.path_times)) d.path_times = []; d.path_times.push(d.path_times.length ? d.path_times[d.path_times.length - 1].slice() : [60, 120, 180]); }) }));
    wrap.appendChild(el('p', { class: 'muted small', text: `Seconds into each stage (${App.stageList().map((w) => fmtT(w.length)).join(' / ')}${SL ? '' : ''}); "mm:ss" works too. The last list holds for every later stage.` }));
    return wrap;
  }

  function pickupsBlock(tl) {
    const wrap = el('div', { class: 'block-form' });
    if (!U.isObj(tl.pickups)) {
      wrap.appendChild(el('p', { class: 'muted', text: 'No power-ups drop on this map.' }));
      wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: 'Add power-up drops', onclick: () => App.apply((d) => { d.pickups = { per_kill: 0.004, roster: [{ id: 'heart', weight: 6, hard_bias: 0.0 }] }; }) }));
      return wrap;
    }
    const pk = tl.pickups;
    wrap.appendChild(fieldRow({ key: 'per_kill', label: 'Chance per kill', type: 'number', min: 0, max: 1, step: 0.0005, def: 0, help: 'the chance a kill drops a power-up, times the creature\'s xp_mult (Elites double)' }, pk, { pathPrefix: 'pickups' }));
    const roster = Array.isArray(pk.roster) ? pk.roster : (pk.roster = []);
    const tbl = el('div', { class: 'mini-table pk' }, el('div', { class: 'mini-head' }, el('span', { text: 'power-up' }), el('span', { text: 'weight' }), el('span', { text: 'hard bias' }), el('span')));
    const total = roster.reduce((a, r) => a + (Number(r.weight) || 0), 0) || 1;
    roster.forEach((r, k) => {
      tbl.appendChild(el('div', { class: 'mini-row' },
        el('span', { class: 'cell-ico' }, control(FIELDS.PICKUP_ROW[0], r, { pathPrefix: `pickups.roster.${k}` })),
        el('span', { class: 'with-hint' }, control(FIELDS.PICKUP_ROW[1], r, { pathPrefix: `pickups.roster.${k}`, cls: 'short' }), el('span', { class: 'hint', text: `${Math.round((Number(r.weight) || 0) / total * 100)}%` })),
        control(FIELDS.PICKUP_ROW[2], r, { pathPrefix: `pickups.roster.${k}`, cls: 'short' }),
        el('button', { class: 'x', type: 'button', text: '×', title: 'remove', onclick: () => App.apply(() => { roster.splice(k, 1); }) })));
    });
    tbl.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ power-up', onclick: () => App.apply(() => { const used = new Set(roster.map((r) => r.id)); const p = App.S.pickups.find((x) => !x.small && !used.has(x.id)) || App.S.pickups[0]; roster.push({ id: p ? p.id : 'heart', weight: 1, hard_bias: 0.0 }); }) }));
    wrap.appendChild(el('div', { class: 'frow' }, el('label', { class: 'flabel', text: 'Roster', title: 'which power-ups drop and how often' }), el('div', { class: 'fctl' }, tbl)));
    return wrap;
  }

  return {
    row, numberInput, secondsInput, textInput, textareaInput, select, boolInput, bool3Input, percentInput, iconSelect, closePop, creatureGroups, inheritable,
    creatureSummary, enemyPick, variantSelect, eliteSelect, pickupSelect, intervalInput, numberList, numbersLine, normHex,
    swatchInput, swatchesInput, control, fieldRow, pointsTable, pointsBlock, floorBlock, weightsBlock, curveBlock, spawnSidesBlock,
    specialsBlock, pathTimesBlock, pickupsBlock,
  };
})();
