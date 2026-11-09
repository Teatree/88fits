'use strict';
// Pass 137, lane LOCKIT: the Strings tab (Garry: "a Level Editor tab of strings (name -> text) ... icons beside the rows
// ... sub-tabs by context ... CSV export and import with minimal validation and errors ... ready for my edits without
// breaking anything ... a guide (also a button at the tab's top right)").
// strings_io.py serves the rows (game/content/strings/en.json and the content JSONs' own words) and writes them back where
// they live; strings_model.js renders a text with its sample values and checks it, as the game (Loc.gd) would.
const Strings = (() => {
  const { el, clear } = typeof U !== 'undefined' ? U : {};
  const M = typeof StringsModel !== 'undefined' ? StringsModel : null;
  const PAGE = 150;
  const store = (k, v) => { try { if (v === undefined) return localStorage.getItem('88fits-strings-' + k); localStorage.setItem('88fits-strings-' + k, v); } catch (_) { /* no storage */ } return null; };
  const S = {
    rows: [], byKey: {}, groups: [], edits: {}, group: store('group') || 'weapons', search: '', onlyChanged: false,
    loading: false, failed: null, saving: false, shown: PAGE, importing: null,
  };
  let panelEl = null;

  function load(force) {
    if (S.loading || (S.rows.length && !force)) return;
    S.loading = true;
    fetch('/api/strings', { cache: 'no-store' }).then((r) => { if (!r.ok) throw new Error(r.status === 404 ? 'the server has no /api/strings yet: restart the Level Editor (new in pass 137)' : `HTTP ${r.status}`); return r.json(); }).then((d) => {
      if (!d.ok) throw new Error(d.error || 'the texts could not be read');
      S.rows = d.rows || []; S.groups = d.groups || []; S.byKey = {};
      for (const r of S.rows) S.byKey[r.key] = r;
      for (const k of Object.keys(S.edits)) if (!S.byKey[k] || S.byKey[k].text === S.edits[k]) delete S.edits[k];
      if (!S.groups.some((g) => g.id === S.group)) S.group = (S.groups[0] || {}).id || 'weapons';
      S.failed = null; S.loading = false; redraw();
    }).catch((e) => { S.failed = String(e.message || e); S.loading = false; redraw(); });
  }
  const dirty = () => Object.keys(S.edits).length > 0;
  function redraw() { if (panelEl && panelEl.isConnected) render(panelEl); }
  const btn = (text, cls, on, title) => el('button', { type: 'button', class: 'btn small ' + (cls || ''), text, title: title || '', onclick: on });

  function textOf(r) { return Object.prototype.hasOwnProperty.call(S.edits, r.key) ? S.edits[r.key] : r.text; }
  function visible() {
    const q = S.search.trim().toLowerCase();
    return S.rows.filter((r) => {
      if (q) { if (!(r.key.toLowerCase().includes(q) || textOf(r).toLowerCase().includes(q))) return false; } else if (r.group !== S.group) return false;
      if (S.onlyChanged && !Object.prototype.hasOwnProperty.call(S.edits, r.key)) return false;
      return true;
    });
  }

  // ------------------------------------------------------------------ saving

  async function save() {
    if (S.saving) return;
    const keys = Object.keys(S.edits);
    if (!keys.length) { App.status('No text changed'); return; }
    const bad = keys.filter((k) => M.check(S.byKey[k], S.edits[k]).errors.length);
    if (bad.length) { App.status(`Cannot save: ${bad.length} text${bad.length > 1 ? 's have' : ' has'} a problem (${bad.slice(0, 3).join(', ')}): fix the red lines`, 'bad'); S.onlyChanged = true; redraw(); return; }
    S.saving = true; App.status(`Saving ${keys.length} text${keys.length > 1 ? 's' : ''}…`, 'busy'); redraw();
    const d = await post('/api/strings/save', { changes: S.edits });
    S.saving = false;
    if (!d.ok) { App.status(`Save failed: ${d.error || ''} ${(d.errors || []).map((e) => `${e.key}: ${e.error}`).join('; ')}`, 'bad'); redraw(); return; }
    S.edits = {};
    App.status(d.unchanged ? 'The files already say this' : `Saved ${d.changed} text${d.changed > 1 ? 's' : ''} in ${(d.written || []).length} file${(d.written || []).length > 1 ? 's' : ''} (a backup each)${d.import_ok === false ? '. The import failed: ' + d.output : ''}. The game reads them when it starts.`, d.import_ok === false ? 'bad' : 'good');
    load(true);
  }
  async function post(url, body) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
      try { return await r.json(); } catch (_) { return { ok: false, error: `HTTP ${r.status}` }; }
    } catch (e) { return { ok: false, error: String(e.message || e) }; }
  }

  // ------------------------------------------------------------------ CSV

  function exportCsv(group) { window.location.href = '/api/strings/csv' + (group ? '?group=' + encodeURIComponent(group) : ''); }
  function pickCsv() {
    const f = el('input', { type: 'file', accept: '.csv,text/csv', style: 'display:none' });
    f.addEventListener('change', async () => {
      const file = f.files && f.files[0];
      if (!file) return;
      const text = await file.text();
      const d = await post('/api/strings/import', { csv: text, apply: false });
      S.importing = { name: file.name, csv: text, result: d };
      redraw();
    });
    document.body.appendChild(f); f.click(); setTimeout(() => f.remove(), 60000);
  }
  async function applyImport() {
    const imp = S.importing;
    if (!imp) return;
    App.status('Applying the CSV…', 'busy');
    const d = await post('/api/strings/import', { csv: imp.csv, apply: true });
    if (!d.ok) { imp.result = d; App.status('The CSV was not applied: ' + (d.summary || d.error || ''), 'bad'); redraw(); return; }
    S.importing = null;
    App.status(`Applied ${d.changes.length} text${d.changes.length === 1 ? '' : 's'} from ${imp.name}${d.saved && d.saved.import_ok === false ? '. The import failed: ' + d.saved.output : ''}`, 'good');
    load(true);
  }

  function importPanel() {
    const imp = S.importing;
    const d = imp.result || {};
    const box = el('div', { class: 'str-import' });
    box.append(el('h3', { text: `CSV: ${imp.name}` }), el('p', { class: d.ok ? 'good-text' : 'warn-text', text: d.summary || d.error || 'no answer' }));
    if ((d.errors || []).length) {
      const t = el('table', { class: 'str-tab' }, el('tr', {}, el('th', { text: 'line' }), el('th', { text: 'key' }), el('th', { text: 'error' })));
      for (const e of d.errors.slice(0, 200)) t.append(el('tr', { class: 'bad' }, el('td', { text: String(e.line) }), el('td', { text: e.key || '' }), el('td', { text: e.error })));
      box.append(el('h4', { text: `${d.errors.length} error(s): nothing is written until they are fixed in the file` }), t);
    }
    if ((d.warnings || []).length) {
      const t = el('table', { class: 'str-tab' });
      for (const w of d.warnings.slice(0, 200)) t.append(el('tr', {}, el('td', { text: String(w.line) }), el('td', { text: w.key }), el('td', { text: w.warning })));
      box.append(el('h4', { text: `${d.warnings.length} warning(s)` }), t);
    }
    if ((d.changes || []).length) {
      const t = el('table', { class: 'str-tab' }, el('tr', {}, el('th', { text: 'key' }), el('th', { text: 'now' }), el('th', { text: 'from the CSV' })));
      for (const c of d.changes.slice(0, 300)) t.append(el('tr', {}, el('td', { class: 'str-key', text: c.key }), el('td', { text: c.old }), el('td', { class: 'str-new', text: c.new })));
      box.append(el('h4', { text: `${d.changes.length} change(s)` }), t);
    }
    box.append(el('div', { class: 'str-actions' },
      d.ok && (d.changes || []).length ? btn(`Apply these ${d.changes.length} change${d.changes.length === 1 ? '' : 's'}`, 'primary', applyImport) : null,
      btn(d.ok ? 'Cancel' : 'Close', '', () => { S.importing = null; redraw(); })));
    return box;
  }

  // ------------------------------------------------------------------ rows

  function rowEl(r) {
    const text = textOf(r);
    const changed = Object.prototype.hasOwnProperty.call(S.edits, r.key);
    const chk = M.check(r, text);
    const wrap = el('div', { class: 'str-row' + (changed ? ' changed' : '') + (chk.errors.length ? ' bad' : ''), dataset: { key: r.key } });
    const icon = el('div', { class: 'str-icon' });
    if (r.icon) { const im = el('img', { src: '/api/strings/icon?key=' + encodeURIComponent(r.icon), alt: '', loading: 'lazy' }); im.addEventListener('error', () => im.remove()); icon.append(im); }
    const body = el('div', { class: 'str-body' });
    body.append(el('div', { class: 'str-key', title: r.where, text: r.key }, el('span', { class: 'str-where', text: '  ' + r.where })));
    const ta = el('textarea', { class: 'str-text', rows: Math.min(6, Math.max(1, Math.ceil(text.length / 90) + (text.match(/\n/g) || []).length)), spellcheck: true, readOnly: !!r.readonly });
    ta.value = text;
    ta.addEventListener('input', () => {
      if (ta.value === r.text) delete S.edits[r.key]; else S.edits[r.key] = ta.value;
      const fresh = rowEl(r); wrap.replaceWith(fresh);
      const t2 = fresh.querySelector('textarea'); t2.focus(); t2.setSelectionRange(ta.selectionStart, ta.selectionEnd);
      drawBar();
    });
    body.append(ta);
    if (r.vars.length) {
      const chips = el('div', { class: 'str-vars' });
      for (const v of r.vars) chips.append(el('span', { class: 'str-chip' + (M.variables(text).includes(v) ? '' : ' unused'), title: r.samples[v] !== undefined ? `{${v}}: the value the game last gave it (tools/dl/loc/samples.json)` : `{${v}}: no sample value yet`, text: `{${v}}` + (r.samples[v] !== undefined ? ` = ${r.samples[v]}` : '') }));
      body.append(chips);
      if (Object.keys(r.samples).length) body.append(el('div', { class: 'str-preview', title: 'the text as the game would show it with these sample values', text: M.render(text, r.samples) }));
    }
    for (const e of chk.errors) body.append(el('div', { class: 'str-err', text: '✖ ' + e }));
    for (const w of chk.warnings) body.append(el('div', { class: 'str-warn', text: '⚠ ' + w }));
    const side = el('div', { class: 'str-side' });
    if (changed) side.append(btn('Undo', '', () => { delete S.edits[r.key]; redraw(); }, `back to: ${r.text}`));
    wrap.append(icon, body, side);
    return wrap;
  }

  // ------------------------------------------------------------------ the page

  let R = {};
  function drawBar() {
    if (!R.save) return;
    const n = Object.keys(S.edits).length;
    R.save.textContent = n ? `Save ${n} change${n > 1 ? 's' : ''}` : 'Save';
    R.save.disabled = !n || S.saving;
    R.revert.disabled = !n;
  }

  function render(panel) {
    panelEl = panel;
    if (!M) { clear(panel); panel.append(el('p', { class: 'warn-text', text: 'strings_model.js did not load' })); return; }
    load(false);
    clear(panel);
    if (S.failed) { panel.append(el('h2', { text: 'Texts' }), el('p', { class: 'warn-text', text: S.failed }), btn('Try again', '', () => { S.failed = null; load(true); })); return; }
    if (!S.rows.length) { panel.append(el('p', { class: 'muted', text: 'reading the texts…' })); return; }
    const head = el('div', { class: 'str-head' });
    head.append(el('h2', { text: 'Texts' }), el('span', { class: 'muted', text: `${S.rows.length} texts a player reads · English` }), el('span', { class: 'spacer' }),
      btn('Guide', 'str-guide', () => window.open('/api/strings/guide', '_blank'), 'How this tab works: keys, {variables}, {n?one:many}, CSV in Excel or Google Sheets, what breaks and how the tab stops it'));
    const bar = el('div', { class: 'str-bar' });
    const search = el('input', { type: 'search', class: 'str-search', placeholder: 'Search every key and text…', value: S.search });
    search.addEventListener('input', () => { S.search = search.value; S.shown = PAGE; for (const t of panel.querySelectorAll('.str-group')) t.classList.toggle('on', !S.search && t.title === S.group); drawList(); });
    const only = el('label', { class: 'str-only' }, el('input', { type: 'checkbox', checked: S.onlyChanged, onchange: (e) => { S.onlyChanged = e.target.checked; drawList(); } }), ' changed since the last save');
    R.save = btn('Save', 'primary', save, 'Write every changed text where it lives (Ctrl+S); a backup is kept of each file');
    R.revert = btn('Revert', '', () => { S.edits = {}; redraw(); }, 'Forget every change not saved yet');
    bar.append(search, only, R.save, R.revert,
      btn('Export all (CSV)', '', () => exportCsv(''), 'Every text as a CSV for Excel or Google Sheets: key,group,text,variables,where'),
      btn('Export this tab', '', () => exportCsv(S.group), 'This sub-tab\'s texts as a CSV'),
      btn('Import CSV…', '', pickCsv, 'Read a CSV back: it is checked first and shows what would change; nothing is written until you apply it'));
    const tabs = el('div', { class: 'str-groups' });
    for (const g of S.groups) {
      const n = S.rows.filter((r) => r.group === g.id && Object.prototype.hasOwnProperty.call(S.edits, r.key)).length;
      tabs.append(el('button', { type: 'button', class: 'str-group' + (g.id === S.group && !S.search ? ' on' : ''), title: g.id, onclick: () => { S.group = g.id; store('group', g.id); S.search = ''; S.shown = PAGE; redraw(); } },
        `${g.label} `, el('span', { class: 'muted', text: String(g.count) }), n ? el('span', { class: 'str-dot', text: ` ${n}` }) : null));
    }
    R.list = el('div', { class: 'str-list' });
    panel.append(head, bar, tabs);
    if (S.importing) panel.append(importPanel());
    panel.append(R.list);
    drawBar();
    drawList();
  }

  function drawList() {
    if (!R.list) return;
    clear(R.list);
    const vis = visible();
    if (!vis.length) { R.list.append(el('p', { class: 'muted', text: S.search ? 'Nothing matches.' : 'No texts here yet: wave 2 of pass 137 moves the code\'s words into the table.' })); return; }
    for (const r of vis.slice(0, S.shown)) R.list.append(rowEl(r));
    if (vis.length > S.shown) R.list.append(btn(`Show ${Math.min(PAGE, vis.length - S.shown)} more (${vis.length - S.shown} left)`, '', () => { S.shown += PAGE; drawList(); }));
  }

  function key(e) {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); return true; }
    return false;
  }

  return { render, save, dirty, load, key, S };
})();
if (typeof module !== 'undefined') module.exports = Strings;
