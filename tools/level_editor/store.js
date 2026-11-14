'use strict';
// Pass 149 (lane EDITOR): the Store tab (game/content/store/store.json version 2, docs/store_schema.md; store_io.py serves
// and saves it, store_model.js holds the bonus tags, the coin offer rule and the checks). Garry (2026-11-14): "In the Shop
// there will now be 2 sections: Gems section at the top, Coins section underneath: Gems are bought with $ ... Coins are
// bought with Gems. As the Player progresses the amount of Coins they get from each offers changes as they progress ...
// in rounded steps rather than continuously."
//
// The page edits the gem packs (amount, price in cents and the words on the button, ribbon, picture) with each one's bonus
// tag, the coin offers (their gem price and coins at the start, ribbon, picture) and how they grow (stage_mult a stage,
// trail_step and trail_per_step, round_sig), the paid revive (price 0 = none, its currency, how many a run). The preview
// shows every offer at every stage x Trail level by the game's rule (StorePacks.coins_for), and "a player at" picks one
// stage and Trail Level and shows the COINS section as he would read it. Save (or Ctrl+S on this tab) writes the file with
// a backup; the game reads it when it starts.
const Store = (() => {
  const { el, clear } = U;
  const M = StoreModel;
  const S = {
    loaded: null, failed: null, loading: false, doc: null, base: null, mtime: null, history: [], saving: false, msg: null,
    stage: 0, level: 0,   // "a player at"
  };

  // ------------------------------------------------------------------ data

  function load(force) {
    if (S.loading || (S.loaded && !force)) return;
    S.loading = true;
    fetch('/api/store', { cache: 'no-store' }).then((r) => { if (r.status === 404) throw new Error('the server has no /api/store yet: restart the Level Editor (new in pass 149)'); return r.json(); }).then((d) => {
      S.loading = false;
      if (!d.ok) { S.failed = d.error || 'the Store could not be read'; redraw(); return; }
      S.loaded = d; S.failed = null; S.msg = null;
      S.doc = d.json && M.isV2(d.json) ? M.normalise(d.json) : null;
      S.base = S.doc ? JSON.stringify(S.doc) : null;
      S.mtime = d.mtime; S.history = [];
      redraw();
    }).catch((e) => { S.loading = false; S.failed = String(e.message || e); redraw(); });
  }
  const dirty = () => !!S.doc && JSON.stringify(S.doc) !== S.base;
  const redraw = () => { if (typeof App !== 'undefined' && App.S.tab === 'store') App.render('tab'); };
  const ctx = () => ({ currencies: ((S.loaded && S.loaded.currencies) || []).map((c) => c.id), stages: ((S.loaded && S.loaded.stages) || []).length || null, pictures: (S.loaded && S.loaded.pictures) || null });
  const issues = () => (S.doc ? M.check(S.doc, ctx()) : []);

  function edit(fn) {
    const before = JSON.stringify(S.doc);
    fn(S.doc);
    if (JSON.stringify(S.doc) === before) return;
    S.history.push(before);
    if (S.history.length > 200) S.history.shift();
    redraw();
  }
  function undo() { if (!S.history.length) return; S.doc = JSON.parse(S.history.pop()); redraw(); }
  function revert() { if (S.base) { S.doc = JSON.parse(S.base); S.history = []; redraw(); } }

  async function save() {
    if (!S.doc || S.saving) return;
    const errs = M.errorsOf(issues());
    if (errs.length) { App.status(`Cannot save the Store: ${errs.map((x) => x.text).join(' · ')}`, 'bad'); return; }
    if (!dirty()) { App.status('Nothing to save'); return; }
    S.saving = true; redraw();
    App.status('Saving the Store…', 'busy');
    let r, data;
    try {
      r = await fetch('/api/store/save', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ json: S.doc, base_mtime: S.mtime }) });
      try { data = await r.json(); } catch (_) { data = { ok: false, error: `HTTP ${r.status}` }; }
    } catch (e) { r = { status: 0 }; data = { ok: false, error: String(e.message || e) }; }
    S.saving = false;
    if (r.status === 409) { S.msg = 'store.json changed on disk since this page read it: Reload to take the file (your edits here would be lost), or Save again to keep yours'; S.mtime = data.mtime; App.status(S.msg, 'bad'); redraw(); return; }
    if (!data.ok) { App.status(`Save of the Store failed: ${data.error}${r.status === 404 ? ' (restart the editor: the route is new in pass 149)' : ''}`, 'bad'); redraw(); return; }
    S.base = JSON.stringify(S.doc); S.mtime = data.mtime; S.msg = null;
    App.status(data.unchanged ? 'The Store on disk is already this' : `Saved ${data.file}${data.backup ? ' (a backup was kept)' : ''}. ${data.note || ''}`, 'good');
    redraw();
  }
  function reload() { S.loaded = null; S.doc = null; load(true); redraw(); }

  // ------------------------------------------------------------------ small pieces

  const fmt = (x) => Math.round(Number(x) || 0).toLocaleString('en-US');
  const curRecs = () => (S.loaded && S.loaded.currencies) || [];
  const curRec = (id) => curRecs().find((c) => c.id === id) || { id, name: id, word: id, icon_url: `/api/currencies/${encodeURIComponent(id)}/icon` };
  const curImg = (id, px) => el('img', { class: 'sto-cur', src: curRec(id).icon_url, alt: '', width: px || 18, height: px || 18, title: curRec(id).name, onerror: (e) => { e.target.style.visibility = 'hidden'; } });
  const picUrl = (res) => `/api/store/picture?path=${encodeURIComponent(res || '')}`;
  const stageNames = () => { const st = (S.loaded && S.loaded.stages) || []; return st.length ? st : [0, 1, 2, 3].map((i) => ({ name: `Stage ${i + 1}` })); };
  const priceWords = (cents) => `$${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`;

  function numBox(value, set, o) {
    const opt = o || {};
    const inp = el('input', { type: 'number', class: 'num ' + (opt.cls || 'short'), value: value == null ? '' : value, step: opt.step || 'any', min: opt.min != null ? opt.min : null, title: opt.title || '', 'data-path': opt.path || '' });
    inp.addEventListener('change', () => { const v = inp.value === '' ? null : Number(inp.value); if (v == null || Number.isFinite(v)) set(v); });
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }
  function txtBox(value, set, o) {
    const opt = o || {};
    const inp = el('input', { type: 'text', class: 'txt ' + (opt.cls || ''), value: value == null ? '' : value, placeholder: opt.ph || '', title: opt.title || '', 'data-path': opt.path || '', spellcheck: false });
    if (opt.list) inp.setAttribute('list', opt.list);
    inp.addEventListener('change', () => set(inp.value.trim()));
    inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') inp.blur(); });
    return inp;
  }
  function selBox(value, options, set, o) {
    const opt = o || {};
    const s = el('select', { 'data-path': opt.path || '', title: opt.title || '' });
    let hit = false;
    for (const [v, t] of options) { if (v === value) hit = true; s.appendChild(el('option', { value: v, text: t, selected: v === value })); }
    if (!hit && value != null) s.appendChild(el('option', { value, text: `${value} (unknown)`, selected: true }));
    s.addEventListener('change', () => set(s.value));
    return s;
  }
  function check(value, set, label, path) {
    const cb = el('input', { type: 'checkbox', checked: !!value, 'data-path': path || '' });
    cb.addEventListener('change', () => set(cb.checked));
    return el('label', { class: 'cb' }, cb, el('span', { text: label }));
  }
  const curOptions = () => curRecs().map((c) => [c.id, c.name && c.name !== c.id ? `${c.name} (${c.id})` : c.id]);
  const curSel = (value, set, path, title) => selBox(value, curOptions().length ? curOptions() : [['gold', 'gold'], ['gems', 'gems']], set, { path, title });
  function row(label, help, ...ctl) {
    return el('div', { class: 'frow' }, el('label', { class: 'flabel', text: label, title: help || '' }), el('div', { class: 'fctl' }, ...ctl, help ? el('span', { class: 'hint sto-hint', text: help }) : null));
  }
  function card(title, sub, ...body) {
    return el('div', { class: 'sto-card' }, el('div', { class: 'sto-card-head' }, el('h3', { text: title }), sub ? el('span', { class: 'muted small', text: sub }) : null), ...body);
  }
  function btn(text, title, onClick, cls, disabled) { return el('button', { type: 'button', class: 'btn small ' + (cls || ''), text, title: title || '', onclick: onClick, disabled: !!disabled }); }
  function thumb(res, cur) {
    const box = el('span', { class: 'sto-thumb', title: res || 'no picture' });
    const fall = () => { clear(box); box.classList.add('none'); box.appendChild(curImg(cur, 26)); };
    if (!res) { fall(); return box; }
    box.appendChild(el('img', { src: picUrl(res), alt: '', onerror: fall }));
    return box;
  }
  const flagged = (path) => issues().filter((x) => x.path === path || x.path.startsWith(path + '.'));
  function flagCls(path) { const f = flagged(path); return f.some((x) => x.sev === 'error') ? ' err' : f.length ? ' warn' : ''; }

  // ------------------------------------------------------------------ the page

  function render(panel) {
    const scroll = panel.scrollTop;
    const active = panel.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    clear(panel);
    load();
    const page = el('div', { class: 'sto' });
    panel.appendChild(page);
    if (S.failed && !S.loaded) { page.appendChild(el('p', { class: 'ferr bad', text: `Could not read the Store: ${S.failed}` })); return; }
    if (!S.loaded) { page.appendChild(el('p', { class: 'muted', text: 'Loading the Store…' })); return; }
    page.appendChild(head());
    page.appendChild(el('p', { class: 'lead sto-lead', html: 'The Store has two sections. <b>GEMS</b> on top: packs of the hard currency bought with dollars (no billing yet: a price tap says "Coming soon"). <b>COINS</b> underneath: offers bought with gems, a real exchange, whose coins <b>grow in rounded steps</b> with the latest stage the player has unlocked (the big step) and every few Trail levels (the small one). Nothing in a run gives gems; a price or a poster may still name them. The player sees the Store and the gem wallet only while the debug Settings\' <b>Store</b> switch is on. The game reads this file when it starts.' }));
    if (!S.doc) {
      const v = S.loaded.json ? S.loaded.json.version : null;
      page.appendChild(el('div', { class: 'ferr warn' },
        el('span', { text: S.loaded.exists ? `${S.loaded.file} is version ${v == null ? '?' : v} (pass 147's coin packs bought with dollars), not version 2: the game of pass 149 reads version 2 (lane STORE writes it). ` : `${S.loaded.file} is not there yet. ` }),
        btn('Start version 2 from the defaults', 'the six gem packs, the three coin offers and the scaling of COMMON.md decision 1; nothing is written until Save', () => { S.doc = M.fromV1(S.loaded.json); S.base = S.loaded.exists ? JSON.stringify(S.loaded.json) : null; redraw(); }, 'primary')));
      return;
    }
    if (S.msg) page.appendChild(el('div', { class: 'ferr warn' }, el('span', { text: S.msg + ' ' }), btn('Reload', 'read the file again (your edits here are lost)', reload)));
    const iss = issues();
    if (iss.length) {
      const box = el('div', { class: 'sto-issues' });
      for (const x of iss.slice().sort((a, b) => (a.sev === 'error' ? 0 : 1) - (b.sev === 'error' ? 0 : 1))) box.appendChild(el('div', { class: 'ferr ' + (x.sev === 'error' ? 'bad' : 'warn'), text: `${x.sev === 'error' ? 'Error' : 'Warning'} · ${x.path}: ${x.text}` }));
      page.appendChild(box);
    }
    const grid = el('div', { class: 'sto-grid' });
    const left = el('section', { class: 'sto-col' }, gemsCard(), coinsCard(), reviveCard());
    const right = el('section', { class: 'sto-col' }, playerCard(), previewCard());
    grid.append(left, right);
    page.appendChild(grid);
    page.appendChild(el('datalist', { id: 'sto-pics' }, ...((S.loaded.pictures || []).map((p) => el('option', { value: p })))));
    panel.scrollTop = scroll;
    if (active) { const again = panel.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  function head() {
    const d = dirty();
    const errs = M.errorsOf(issues()).length;
    return el('div', { class: 'sto-head' },
      el('h2', { text: 'Store' }),
      el('code', { class: 'sto-file', text: S.loaded.file || 'game/content/store/store.json' }),
      d ? el('span', { class: 'dirty-dot', text: '●', title: 'unsaved changes' }) : null,
      el('span', { class: 'spacer' }),
      btn('Undo', 'undo the last edit on this tab', undo, '', !S.history.length),
      btn('Revert', 'back to the file as it was read', revert, '', !d),
      btn('Reload', 'read the file again from disk', () => { if (!d || confirm('Drop the unsaved edits and read store.json again?')) reload(); }),
      btn(S.saving ? 'Saving…' : 'Save store', errs ? `${errs} error(s) block the save` : 'write store.json (a backup first; Ctrl+S on this tab). The game reads it when it starts.', save, 'primary' + (errs ? ' blocked' : ''), !d || S.saving));
  }

  // ---- the gems

  const packs = () => S.doc.gems.packs;
  const offers = () => S.doc.coins.offers;
  function moveIn(list, i, by) { const j = i + by; if (j < 0 || j >= list.length) return; const [x] = list.splice(i, 1); list.splice(j, 0, x); }
  function freeId(prefix) { const used = new Set(packs().concat(offers()).map((x) => x && x.id)); let n = 1; while (used.has(`${prefix}_${n}`)) n++; return `${prefix}_${n}`; }

  function gemsCard() {
    const g = S.doc.gems;
    const bonus = M.gemBonus(S.doc);
    const cur = g.currency;
    const tbl = el('div', { class: 'sto-table sto-packs' });
    tbl.appendChild(el('div', { class: 'sto-tr sto-th' }, ...['', 'id', 'gems', 'price (cents)', 'on the button', 'ribbon', 'picture', 'bonus', ''].map((t) => el('span', { text: t }))));
    packs().forEach((p, i) => {
      const at = `gems.packs.${i}`;
      const set = (fn) => edit((d) => fn(d.gems.packs[i]));
      tbl.appendChild(el('div', { class: 'sto-tr' + flagCls(at), title: flagged(at).map((x) => x.text).join('\n') },
        thumb(p.picture, cur),
        txtBox(p.id, (v) => set((x) => { x.id = v; }), { cls: 'mono id', path: `${at}.id`, title: 'the pack\'s id (the screen names its node Pack_<id>)' }),
        el('span', { class: 'sto-amt' }, curImg(cur, 16), numBox(p.amount, (v) => set((x) => { x.amount = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 10, path: `${at}.amount`, title: 'gems the pack gives' })),
        numBox(p.price_cents, (v) => set((x) => {
          const c = Math.max(0, Math.round(v || 0));
          // the words on the button follow the cents while they still read the old price ("$4.99")
          if (!x.price_text || x.price_text === priceWords(Number(x.price_cents) || 0)) x.price_text = priceWords(c);
          x.price_cents = c;
        }), { min: 0, step: 100, path: `${at}.price_cents`, title: 'the price in cents (499 = $4.99); the words follow while they read the old price' }),
        txtBox(p.price_text, (v) => set((x) => { x.price_text = v; }), { cls: 'short', path: `${at}.price_text`, title: 'the words on the button (must name the price: $4.99)' }),
        selBox(p.ribbon || '', M.RIBBONS.map((r) => [r, M.RIBBON_WORDS[r]]), (v) => set((x) => { x.ribbon = v; }), { path: `${at}.ribbon` }),
        txtBox(p.picture, (v) => set((x) => { x.picture = v; }), { cls: 'pic', list: 'sto-pics', path: `${at}.picture`, title: 'res://art/ui/store/<file>.png (a missing file shows the currency icon)' }),
        el('span', { class: 'sto-bonus', title: `gems per whole dollar against the cheapest pack's (${M.dollars(p.price_cents)} dollar${M.dollars(p.price_cents) === 1 ? '' : 's'})` }, bonus[p.id] ? `+${bonus[p.id]}% BONUS` : '—'),
        el('span', { class: 'sto-acts' },
          btn('▲', 'one place up (the screen lays the packs in file order)', () => edit((d) => moveIn(d.gems.packs, i, -1)), 'ghost', i === 0),
          btn('▼', 'one place down', () => edit((d) => moveIn(d.gems.packs, i, 1)), 'ghost', i === packs().length - 1),
          btn('✕', 'remove this pack', () => edit((d) => { d.gems.packs.splice(i, 1); }), 'ghost'))));
    });
    return card('Gems (the top section)', 'bought with dollars; 3 × 2 on the screen, in this order',
      row('Gives', 'the currency the packs give (the hard currency)', curSel(cur, (v) => edit((d) => { d.gems.currency = v; }), 'gems.currency'), curImg(cur, 20)),
      row('Bonus tags', 'a pack shows "+N% BONUS" when its gems per whole dollar beat the cheapest pack\'s ($4.99 counts as $5): N = round(100 × (its rate ÷ the cheapest rate − 1)); nothing under 1%', check(g.show_bonus !== false, (v) => edit((d) => { d.gems.show_bonus = v; }), 'show them', 'gems.show_bonus')),
      tbl,
      el('div', { class: 'sto-line' }, btn('+ gem pack', 'one more pack, after the last', () => edit((d) => { const last = d.gems.packs[d.gems.packs.length - 1] || {}; d.gems.packs.push({ id: freeId('gems'), amount: last.amount ? last.amount * 2 : 100, price_cents: 999, price_text: '$9.99', ribbon: '', picture: '' }); })),
        el('span', { class: 'muted small', text: 'Survivor.io\'s tiers as the lead remembers them (80 for $0.99 … 14,000 for $99.99): edit them freely.' })));
  }

  // ---- the coins

  function coinsCard() {
    const c = S.doc.coins;
    const sc = c.scaling;
    const bonus = M.offerBonus(S.doc);
    const tbl = el('div', { class: 'sto-table sto-offers' });
    tbl.appendChild(el('div', { class: 'sto-tr sto-th' }, ...['', 'id', 'price (gems)', 'coins at the start', 'ribbon', 'picture', 'bonus', ''].map((t) => el('span', { text: t }))));
    offers().forEach((o, i) => {
      const at = `coins.offers.${i}`;
      const set = (fn) => edit((d) => fn(d.coins.offers[i]));
      tbl.appendChild(el('div', { class: 'sto-tr' + flagCls(at), title: flagged(at).map((x) => x.text).join('\n') },
        thumb(o.picture, c.currency),
        txtBox(o.id, (v) => set((x) => { x.id = v; }), { cls: 'mono id', path: `${at}.id`, title: 'the offer\'s id (the screen names its node Offer_<id>)' }),
        el('span', { class: 'sto-amt' }, curImg(c.pay, 16), numBox(o.gems, (v) => set((x) => { x.gems = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 10, path: `${at}.gems`, title: 'what the offer costs, in gems' })),
        el('span', { class: 'sto-amt' }, curImg(c.currency, 16), numBox(o.coins, (v) => set((x) => { x.coins = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 100, path: `${at}.coins`, title: 'the coins at stage 1 and Trail Level 0, before the growth and the rounding' })),
        selBox(o.ribbon || '', M.RIBBONS.map((r) => [r, M.RIBBON_WORDS[r]]), (v) => set((x) => { x.ribbon = v; }), { path: `${at}.ribbon` }),
        txtBox(o.picture, (v) => set((x) => { x.picture = v; }), { cls: 'pic', list: 'sto-pics', path: `${at}.picture`, title: 'res://art/ui/store/<file>.png' }),
        el('span', { class: 'sto-bonus', title: 'coins per gem against the offer with the fewest gems, at the amounts a new player reads (stage 1, Trail Level 0); each grown amount is rounded, so the tag moves a little with progress (see A player at…)' }, bonus[o.id] ? `+${bonus[o.id]}% BONUS` : '—'),
        el('span', { class: 'sto-acts' },
          btn('▲', 'one place up (the screen lays the offers left to right in file order)', () => edit((d) => moveIn(d.coins.offers, i, -1)), 'ghost', i === 0),
          btn('▼', 'one place down', () => edit((d) => moveIn(d.coins.offers, i, 1)), 'ghost', i === offers().length - 1),
          btn('✕', 'remove this offer', () => edit((d) => { d.coins.offers.splice(i, 1); }), 'ghost'))));
    });
    // the growth: stage_mult one box a stage (the map's stage names), the Trail's step
    const sm = Array.isArray(sc.stage_mult) ? sc.stage_mult : [];
    const names = stageNames();
    const smBoxes = sm.map((v, i) => el('span', { class: 'sto-sm' + flagCls('coins.scaling.stage_mult') }, el('small', { text: names[i] ? names[i].name : `stage ${i + 1} (none)` }),
      numBox(v, (x) => edit((d) => { d.coins.scaling.stage_mult[i] = x == null ? 1 : Math.max(0, x); }), { min: 0, step: 0.5, path: `coins.scaling.stage_mult.${i}`, cls: 'tiny', title: `× at ${names[i] ? names[i].name : 'stage ' + (i + 1)}` })));
    return card('Coins (under it)', 'bought with gems: a real exchange, a confirm first',
      row('Gives', 'the currency an offer gives (gold: the player reads coins)', curSel(c.currency, (v) => edit((d) => { d.coins.currency = v; }), 'coins.currency'), curImg(c.currency, 20)),
      row('Paid with', 'the currency an offer costs (the gems)', curSel(c.pay, (v) => edit((d) => { d.coins.pay = v; }), 'coins.pay'), curImg(c.pay, 20)),
      row('Bonus tags', 'an offer shows "+N% BONUS" when its coins per gem beat the smallest offer\'s', check(c.show_bonus !== false, (v) => edit((d) => { d.coins.show_bonus = v; }), 'show them', 'coins.show_bonus')),
      tbl,
      el('div', { class: 'sto-line' }, btn('+ coin offer', 'one more offer, after the last', () => edit((d) => { const last = d.coins.offers[d.coins.offers.length - 1] || {}; d.coins.offers.push({ id: freeId('coins'), gems: last.gems ? last.gems * 2 : 100, coins: last.coins ? last.coins * 2 : 1000, ribbon: '', picture: '' }); }))),
      el('h4', { class: 'sto-sub', text: 'How the coins grow' }),
      el('p', { class: 'sto-formula', html: 'coins = <b>coins at the start</b> × <b>stage ×</b>[the latest stage unlocked] × (1 + <b>per step</b> × ⌊Trail Level ÷ <b>Trail step</b>⌋), rounded to <b>figures</b> significant figures' }),
      row('Stage ×', 'the big step: a stage newly unlocked multiplies every offer (the latest one the player has unlocked counts; past the list\'s end its last value holds)', ...smBoxes,
        btn('+', 'one more value (a stage the map may add)', () => edit((d) => { const a = d.coins.scaling.stage_mult; a.push(a.length ? a[a.length - 1] : 1); }), 'ghost'),
        btn('−', 'remove the last value', () => edit((d) => { if (d.coins.scaling.stage_mult.length > 1) d.coins.scaling.stage_mult.pop(); }), 'ghost', sm.length <= 1)),
      row('Trail step', 'the small step comes every this many Trail levels (0 = the Trail never grows the offers)', numBox(sc.trail_step, (v) => edit((d) => { d.coins.scaling.trail_step = Math.max(0, Math.round(v == null ? 10 : v)); }), { min: 0, step: 1, path: 'coins.scaling.trail_step' }), el('span', { class: 'muted small', text: 'levels' })),
      row('Per step', 'what each small step adds: 0.05 = +5% a step', numBox(sc.trail_per_step, (v) => edit((d) => { d.coins.scaling.trail_per_step = Math.max(0, v == null ? 0 : v); }), { min: 0, step: 0.01, path: 'coins.scaling.trail_per_step' }),
        el('span', { class: 'muted small', text: `+${Math.round((Number(sc.trail_per_step) || 0) * 1000) / 10}% every ${sc.trail_step || '?'} levels · at Trail Level ${(S.loaded && S.loaded.trail_top) || 83}: ×${(1 + (Number(sc.trail_per_step) || 0) * M.trailSteps(sc, (S.loaded && S.loaded.trail_top) || 83)).toFixed(2)}` })),
      row('Figures', 'the amounts are rounded to this many significant figures, so they move in steps (2: 17,325 → 17,000)', numBox(sc.round_sig, (v) => edit((d) => { d.coins.scaling.round_sig = Math.max(1, Math.round(v || 1)); }), { min: 1, step: 1, path: 'coins.scaling.round_sig' })));
  }

  // ---- the paid revive

  function reviveCard() {
    const r = S.doc.revive;
    const on = Number(r.price) > 0;
    return card('Paid revive', on ? `GET UP for ${fmt(r.price)} ${curRec(r.currency).word || r.currency}, ${r.per_run} a run` : 'off: the Down! screen is as before',
      el('p', { class: 'muted small', text: 'With a price above 0: when the Outlaw falls with no free chance left and fewer paid revives used this run than "a run", the Down! screen still opens and offers GET UP for the price (its currency\'s icon) or STAY DOWN. Paying is a revive like the ad\'s. With a free chance left the screen is as before. 0 = no paid revive.' }),
      row('Price', '0 = no paid revive', numBox(r.price, (v) => edit((d) => { d.revive.price = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 10, path: 'revive.price' }), curImg(r.currency, 18)),
      row('Paid in', 'the currency GET UP costs', curSel(r.currency, (v) => edit((d) => { d.revive.currency = v; }), 'revive.currency')),
      row('A run', 'how many paid revives a run may have', numBox(r.per_run, (v) => edit((d) => { d.revive.per_run = Math.max(0, Math.round(v || 0)); }), { min: 0, step: 1, path: 'revive.per_run' })));
  }

  // ---- the previews

  /** "A player at": one stage and Trail Level, the COINS section as he reads it. */
  function playerCard() {
    const names = stageNames();
    const c = S.doc.coins;
    const top = (S.loaded && S.loaded.trail_top) || 83;
    S.stage = Math.min(S.stage, names.length - 1);
    const stSel = selBox(String(S.stage), names.map((s, i) => [String(i), `${i + 1} · ${s.name}`]), (v) => { S.stage = Number(v); redraw(); }, { path: 'pv.stage', title: 'the latest stage the player has unlocked' });
    const lv = el('input', { type: 'range', min: 0, max: top, step: 1, value: Math.min(S.level, top), class: 'sto-range', 'data-path': 'pv.level' });
    const lvOut = el('b', { text: String(Math.min(S.level, top)) });
    lv.addEventListener('input', () => { lvOut.textContent = lv.value; });
    lv.addEventListener('change', () => { S.level = Number(lv.value); redraw(); });
    const f = M.factor(c.scaling, S.stage, S.level);
    const tiles = el('div', { class: 'sto-tiles' });
    const bonus = M.offerBonus(S.doc, S.stage, S.level);   // the tag at the amounts he reads
    for (const o of offers()) {
      if (!o || typeof o !== 'object') continue;
      const coins = M.coinsFor(o, S.stage, S.level, c.scaling);
      tiles.appendChild(el('div', { class: 'sto-tile' + (o.ribbon ? ' rb' : '') },
        o.ribbon ? el('span', { class: 'sto-ribbon', text: M.RIBBON_WORDS[o.ribbon] || o.ribbon }) : null,
        thumb(o.picture, c.currency),
        el('div', { class: 'sto-tile-amt' }, curImg(c.currency, 20), el('b', { text: fmt(coins) })),
        bonus[o.id] && c.show_bonus !== false ? el('div', { class: 'sto-tile-bonus', text: `+${bonus[o.id]}% BONUS` }) : null,
        el('div', { class: 'sto-tile-buy' }, curImg(c.pay, 18), el('span', { text: fmt(o.gems) }))));
    }
    return card('A player at…', 'the COINS section as he reads it',
      el('div', { class: 'sto-line' }, el('label', { class: 'sto-l' }, el('span', { text: 'Latest stage unlocked' }), stSel),
        el('label', { class: 'sto-l sto-lv' }, el('span', {}, 'Trail Level ', lvOut), lv)),
      el('p', { class: 'muted small', text: `× ${M.stageMult(c.scaling, S.stage)} for the stage, × ${(1 + (Number(c.scaling.trail_per_step) || 0) * M.trailSteps(c.scaling, S.level)).toFixed(2)} for ${M.trailSteps(c.scaling, S.level)} Trail step${M.trailSteps(c.scaling, S.level) === 1 ? '' : 's'}: × ${Math.round(f * 1000) / 1000} in all, then rounded to ${c.scaling.round_sig} figures. Coins ×25 never touches the Store.` }),
      tiles);
  }

  /** Every offer at every stage x Trail level 0, 10, 20, 40, 60 and the Trail's top (store_model.preview). */
  function previewCard() {
    const top = (S.loaded && S.loaded.trail_top) || 83;
    const levels = M.previewLevels(top);
    const names = stageNames();
    const pv = M.preview(S.doc, names, levels);
    const c = S.doc.coins;
    const tbl = el('table', { class: 'sto-pv' });
    tbl.appendChild(el('tr', {}, el('th', { text: 'offer · stage' }), ...levels.map((T) => el('th', { text: `Trail ${T}` }))));
    for (const b of pv) {
      tbl.appendChild(el('tr', { class: 'sto-pv-offer' }, el('th', { colspan: levels.length + 1 }, curImg(c.pay, 14), ` ${b.offer.id} · ${fmt(b.gems)} ${curRec(c.pay).word || c.pay}`)));
      for (const r of b.rows) {
        tbl.appendChild(el('tr', {}, el('td', { class: 'sto-pv-st', text: `${r.stage + 1} · ${r.name} ×${r.mult}` }),
          ...r.cells.map((x, j) => el('td', { class: 'sto-pv-c' + (j > 0 && x.coins !== r.cells[j - 1].coins ? ' up' : ''), title: `${fmt(x.coins)} coins for ${fmt(b.gems)} gems: ${Math.round(x.per_gem * 10) / 10} coins a gem`, text: fmt(x.coins) }))));
      }
    }
    return card('Coin offers by progress', `the game's rule (StorePacks.coins_for) at every stage × Trail Level 0, 10, 20, 40, 60 and the Trail's top (${top}); a lit cell moved from the one before it`, tbl);
  }

  return { render, save, dirty, load, reload, undo, S };
})();
