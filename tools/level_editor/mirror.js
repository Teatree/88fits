'use strict';
// Pass 116, lane EDITOR: the Mirror tab. Garry: "Put the Mirror upgrades into a separate tab. With visuals for Mirrors."
// The Upgrade board's talents (game/content/talents/<id>/<id>.json, "the Mirror" in code) in the board's order
// (Registry.talents_list: the first rank's price, then `order`, then the id), each with its painted icons (the talent's
// mirror and each form's), its two forms with their words and effects, and the six ranks: the price of each, the total,
// and what the form holds at that rank (the effects times the rank, a talent's base_stats as its whole value). Editing
// a number marks the talent; Save (or Ctrl+S on this tab) writes only the changed keys of each changed talent in its own
// layout (a backup first) and imports its .tres (talents_io.py).
const Mirror = (() => {
  const { el, clear } = typeof U !== 'undefined' ? U : {};   // Node (the selftest) runs only the pure helpers
  const S = { data: null, failed: null, loading: false, drafts: {}, bases: {}, mtimes: {}, saving: false, open: {} };

  // ------------------------------------------------------------------ pure helpers (selftest_EDITOR116.py runs them)

  /** TalentDef.board_before: the first rank's price, then `order`, then the id. */
  function boardSort(list) {
    const fp = (d) => (Array.isArray(d.cost) && d.cost.length ? Number(d.cost[0]) || 0 : 0);
    return list.slice().sort((a, b) => fp(a) - fp(b) || (Number(a.order) || 0) - (Number(b.order) || 0) || String(a.id).localeCompare(String(b.id)));
  }
  const PCT = new Set(['max_hp', 'might', 'cooldown', 'area', 'speed', 'move_speed', 'xp_gain', 'gold_gain', 'luck', 'damage_reduction', 'crit_chance', 'crit_damage', 'evade', 'magnet']);
  /** One effect at rank k, in plain words (mul: +k x value as a percent; add: + k x value, a percent for the stats the
   *  game shows as one; set: the value). `base` = the talent's base_stats (pass 115: the stat's whole value). */
  function effectAt(e, k, base) {
    const v = Number(e.value) || 0;
    const name = String(e.stat || '?').replace(/_/g, ' ');
    if (e.op === 'set') return `${name} = ${fmt(v)}`;
    if (e.op === 'mul') return `${sign(v * k * 100)}% ${name}`;
    if (base && Object.prototype.hasOwnProperty.call(base, e.stat)) return `${name} ${fmt100(Number(base[e.stat]) + v * k, e.stat)}`;
    return PCT.has(e.stat) && Math.abs(v) < 1 ? `${sign(v * k * 100)}% ${name}` : `${sign(v * k)} ${name}`;
  }
  function fmt(x) { return String(Math.round(x * 1000) / 1000); }
  function sign(x) { const r = Math.round(x * 100) / 100; return (r >= 0 ? '+' : '') + r; }
  function fmt100(x, stat) { return Math.abs(x) <= 1 ? `${Math.round(x * 100)}%` : fmt(x); }
  function rankLine(form, k, base) {
    if (Array.isArray(form.rank_effects) && form.rank_effects.length) {
      const list = form.rank_effects[Math.min(k, form.rank_effects.length) - 1] || [];
      return (Array.isArray(list) ? list : []).map((e) => effectAt(e, 1, base)).join(', ');
    }
    return (form.effects || []).map((e) => effectAt(e, k, base)).join(', ');
  }
  function totalCost(cost, ranks) { return (cost || []).slice(0, ranks).reduce((a, b) => a + (Number(b) || 0), 0); }

  // ------------------------------------------------------------------ data

  function load(force) {
    if (S.loading || (S.data && !force)) return;
    S.loading = true;
    fetch('/api/talents', { cache: 'no-store' }).then((r) => { if (!r.ok) throw new Error(r.status === 404 ? 'the server has no /api/talents yet: restart the Level Editor (new in pass 116)' : `HTTP ${r.status}`); return r.json(); }).then((d) => {
      S.data = d; S.failed = null; S.loading = false; S.drafts = {}; S.bases = {}; S.mtimes = {};
      for (const t of d.talents || []) if (t.json) { S.bases[t.id] = JSON.stringify(t.json); S.drafts[t.id] = JSON.parse(S.bases[t.id]); S.mtimes[t.id] = t.mtime; }
      redraw();
    }).catch((e) => { S.failed = String(e.message || e); S.loading = false; redraw(); });
  }
  function dirtyIds() { return Object.keys(S.drafts).filter((id) => JSON.stringify(S.drafts[id]) !== S.bases[id]); }
  function dirty() { return dirtyIds().length > 0; }

  async function save() {
    if (S.saving) return;
    const ids = dirtyIds();
    if (!ids.length) { App.status('Nothing to save'); return; }
    S.saving = true; redraw();
    const done = [];
    for (const id of ids) {
      App.status(`Saving ${id}…`, 'busy');
      const r = await fetch('/api/talents/save', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, json: S.drafts[id], base_mtime: S.mtimes[id] }) });
      let data; try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
      if (r.status === 409) { App.status(`${id}.json changed on disk since this page read it: Reload`, 'bad'); break; }
      if (!data.ok) { App.status(`Save of ${id} failed: ${data.error}`, 'bad'); break; }
      S.bases[id] = JSON.stringify(S.drafts[id]); S.mtimes[id] = data.mtime;
      done.push(`${id}${data.imported === true ? ' (imported)' : data.imported === null ? ' (import queued)' : data.imported === false ? ' (import failed)' : ''}`);
    }
    S.saving = false;
    if (done.length) App.status(`Saved ${done.join(', ')}`, 'good');
    redraw();
  }

  // ------------------------------------------------------------------ the page

  let panelEl = null;
  function redraw() { if (panelEl && panelEl.isConnected) render(panelEl); }

  function num(value, onSet, o) {
    const inp = el('input', { type: 'number', class: 'num', step: (o && o.step) || 'any', value: value == null ? '' : String(value), style: `width:${(o && o.w) || 70}px` });
    inp.addEventListener('change', () => { const v = Number(inp.value); if (Number.isFinite(v)) onSet(v); });
    return inp;
  }
  function txt(value, onSet, w) {
    const inp = el('input', { type: 'text', class: 'txt', value: value || '', style: `width:${w || 220}px` });
    inp.addEventListener('change', () => onSet(inp.value));
    return inp;
  }
  function img(url, px, round) {
    return url ? el('img', { src: url, alt: '', width: px, height: px, class: 'mir-img' + (round ? ' round' : ''), onerror: (e) => { e.target.style.visibility = 'hidden'; } })
      : el('div', { class: 'mir-img none', style: `width:${px}px;height:${px}px`, text: 'no icon' });
  }

  function talentCard(t, idx) {
    const d = S.drafts[t.id];
    const mark = () => { redraw(); };
    const changed = JSON.stringify(d) !== S.bases[t.id];
    const ranks = Number(d.ranks) || 6;
    const cost = Array.isArray(d.cost) ? d.cost : [];
    const base = d.base_stats && typeof d.base_stats === 'object' ? d.base_stats : null;
    const card = el('section', { class: 'mir-card' + (changed ? ' changed' : '') });
    card.appendChild(el('div', { class: 'mir-head' },
      el('div', { class: 'mir-idx', text: `#${idx + 1}`, title: 'place on the board (the first rank\'s price, then order)' }),
      img(t.icons && t.icons.talent, 96),
      el('div', { class: 'mir-title' },
        el('h3', {}, el('span', { text: d.name || t.id }), el('small', { class: 'muted', text: ` ${t.id} · ${t.file}` }), changed ? el('span', { class: 'achip', text: 'unsaved' }) : null),
        el('div', { class: 'mir-row' }, el('label', { text: 'Name ' }), txt(d.name, (v) => { d.name = v; mark(); }, 160),
          el('label', { text: ' Order ' }), num(d.order, (v) => { d.order = Math.round(v); mark(); }, { step: 1, w: 56 }),
          el('label', { text: ' Ranks ' }), num(ranks, (v) => { d.ranks = Math.max(1, Math.round(v)); mark(); }, { step: 1, w: 50 })),
        el('div', { class: 'mir-row' }, el('label', { text: 'Flavour ' }), txt(d.flavour, (v) => { d.flavour = v; mark(); }, 380)),
        base ? el('div', { class: 'muted small', text: `Starting values the talent owns (base_stats): ${Object.entries(base).map(([k, v]) => `${k} ${v}`).join(', ')}` }) : null)));
    // the prices
    const pr = el('table', { class: 'mir-ranks' });
    const hr = el('tr', {}, el('th', { text: 'Rank' }));
    const cr = el('tr', {}, el('th', { text: `Price (${d.currency_type || 'gold'})` }));
    const tr = el('tr', {}, el('th', { class: 'muted', text: 'Total so far' }));
    let run = 0;
    for (let k = 0; k < ranks; k++) {
      hr.appendChild(el('th', { text: String(k + 1) }));
      cr.appendChild(el('td', {}, num(cost[k], (v) => { const c = cost.slice(); while (c.length <= k) c.push(0); c[k] = Math.max(0, Math.round(v)); d.cost = c; mark(); }, { step: 1, w: 72 })));
      run += Number(cost[k]) || 0;
      tr.appendChild(el('td', { class: 'muted', text: cost[k] == null ? '—' : String(run) }));
    }
    pr.appendChild(hr); pr.appendChild(cr); pr.appendChild(tr);
    // the forms: each with its icon, words, effects and what it holds at each rank
    (d.forms || []).forEach((f, fi) => {
      const fr = el('tr', {}, el('th', {}, el('div', { class: 'mir-form' }, img(t.icons && t.icons.forms ? t.icons.forms[fi] : null, 40), el('b', { text: f.name || `form ${fi + 1}` }))));
      for (let k = 1; k <= ranks; k++) fr.appendChild(el('td', { class: 'small', text: rankLine(f, k, base) }));
      pr.appendChild(fr);
    });
    if (cost.length !== ranks) card.appendChild(el('p', { class: 'warn-text small', text: `${cost.length} prices for ${ranks} ranks: the board stops at whichever ends first (import_json warns)` }));
    card.appendChild(pr);
    card.appendChild(el('div', { class: 'muted small', text: `All ${ranks} ranks: ${totalCost(cost, ranks)} ${d.currency_type || 'gold'}` }));
    const forms = el('div', { class: 'mir-forms' });
    (d.forms || []).forEach((f, fi) => {
      const box = el('div', { class: 'mir-formbox' });
      box.appendChild(el('div', { class: 'mir-form' }, img(t.icons && t.icons.forms ? t.icons.forms[fi] : null, 72), el('div', {},
        el('div', { class: 'mir-row' }, el('label', { text: `Form ${String.fromCharCode(65 + fi)} ` }), txt(f.name, (v) => { f.name = v; mark(); }, 150)),
        el('div', { class: 'mir-row' }, txt(f.text, (v) => { f.text = v; mark(); }, 330)))));
      (f.effects || []).forEach((e, ei) => {
        box.appendChild(el('div', { class: 'mir-row small' }, el('span', { class: 'muted', text: 'each rank: ' }),
          txt(e.stat, (v) => { e.stat = v.trim(); mark(); }, 140),
          (() => { const s = el('select', {}); for (const o of ['add', 'mul', 'set']) s.appendChild(el('option', { value: o, text: o, selected: e.op === o })); s.addEventListener('change', () => { e.op = s.value; mark(); }); return s; })(),
          num(e.value, (v) => { e.value = v; mark(); }, { w: 70 }),
          el('span', { class: 'muted', text: ` · rank 1: ${effectAt(e, 1, base)}` })));
      });
      if (Array.isArray(f.rank_effects) && f.rank_effects.length) box.appendChild(el('div', { class: 'muted small', text: 'this form has one effect list a rank (rank_effects): edit those in the JSON' }));
      forms.appendChild(box);
    });
    card.appendChild(forms);
    if (d.art_prompt) card.appendChild(el('div', { class: 'muted small', text: `Painted from: ${d.art_prompt}` }));
    return card;
  }

  function render(panel) {
    panelEl = panel;
    clear(panel);
    load(false);
    const bar = el('div', { class: 'mir-bar' },
      el('h2', { text: 'The Mirror (Upgrade board)' }),
      el('button', { class: 'btn primary', type: 'button', text: S.saving ? 'Saving…' : `Save${dirty() ? ` (${dirtyIds().length})` : ''}`, disabled: S.saving || !dirty(), onclick: save }),
      el('button', { class: 'btn ghost', type: 'button', text: 'Revert', disabled: !dirty(), onclick: () => { for (const id of Object.keys(S.bases)) S.drafts[id] = JSON.parse(S.bases[id]); redraw(); } }),
      el('button', { class: 'btn ghost', type: 'button', text: 'Reload', onclick: () => { S.data = null; load(true); } }),
      el('span', { class: 'muted small', text: 'In the board\'s order (the first rank\'s price, then order). Every rank is bought in one form and keeps it. Save writes each changed talent (a backup first) and imports it.' }));
    panel.appendChild(bar);
    if (S.failed) { panel.appendChild(el('p', { class: 'warn-text', text: S.failed })); return; }
    if (!S.data) { panel.appendChild(el('p', { class: 'muted', text: 'reading the talents…' })); return; }
    const list = boardSort((S.data.talents || []).filter((t) => S.drafts[t.id]).map((t) => Object.assign({ _t: t }, S.drafts[t.id], { id: t.id })));
    const strip = el('div', { class: 'mir-strip' });
    list.forEach((x, i) => strip.appendChild(el('a', { href: `#mir-${x.id}`, class: 'mir-chip', title: `${x.name}: first rank ${(x.cost || [])[0]}` }, img(x._t.icons && x._t.icons.talent, 48), el('span', { text: `${i + 1}. ${x.name || x.id}` }))));
    panel.appendChild(strip);
    list.forEach((x, i) => { const c = talentCard(x._t, i); c.id = `mir-${x.id}`; panel.appendChild(c); });
  }

  return { render, save, dirty, load, boardSort, effectAt, rankLine, totalCost, S };
})();
if (typeof module !== 'undefined') module.exports = Mirror;
