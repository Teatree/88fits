'use strict';
// Pass 111 (lane SKINS): the Heroes tab's "Skins (looks players can buy)" section. Every look of the hero is a row: its
// round badge and a still from its strip (lane V's StripPlayer through LookGrid.playerOpts: hover to play), the code, the
// note, its chips (played, NEW, shelved, not painted), then what the players are offered: Purchasable, Name, Price,
// Currency (the registry, GET /api/currencies) and a Goal (a quest content/quests/skin_<hero>_<code>, the same
// condition rows as the hero's Requirement, AFIELDS.QUEST_ROWS, plus beat_stage "Beat Nightfall with May."), with the
// goal's words previewed. Each row saves on its own button through POST /api/content/hero/<id>/skin/<CODE>
// (skins_io.set_skin: the look entry's `skin` written in place, the goal's quest made / edited / moved to the backups,
// both imported). The look the hero is played in is owned by every player and is never offered; a shelved or unpainted
// look cannot be sold. The edits live in a draft per row (doc.ui.skins) until Save: the hero's own Save asset never
// writes them.
const Skins = (() => {
  const { el, clear } = U;
  const M = AssetsModel, F = AFIELDS;
  const S = { currencies: null, loading: false, failed: null };
  // the names the editor suggests for a look players will read (Garry renames them; the game says "Look <CODE>" when empty)
  const SUGGEST = ['Sunday Best', 'Trail Dust', 'High Noon', 'Midnight Rider', 'Gold Rush', 'Desert Rose', 'Dust Devil', 'Outlaw',
    'Rodeo Star', 'Silver Spur', 'Tumbleweed', 'Sheriff', 'Prospector', 'Saloon Night', 'Canyon Red', 'Blood Moon', 'Nightfall', 'Sundown'];

  function ensureCurrencies() {
    if (S.currencies || S.loading || S.failed) return;
    S.loading = true;
    Assets.getJSON('/api/currencies').then((d) => { S.loading = false; S.currencies = Array.isArray(d) ? d : []; App.render('tab'); })
      .catch((e) => { S.loading = false; S.failed = e.message; App.render('tab'); });
  }
  /** The currency options: the registry's records (name, icon), else the vocab's, else the value as it stands. */
  function currencyOptions() {
    if (Array.isArray(S.currencies) && S.currencies.length) return S.currencies.map((c) => ({ v: c.id, label: c.name || c.id, icon: c.icon_url || `/api/currencies/${encodeURIComponent(c.id)}/icon`, help: c.flavour || '', sub: `${c.id}${c.fallback ? ' · stand-in: content/currencies has none' : ''}` }));
    const v = Assets.vocab();
    return Array.isArray(v.currencies) ? v.currencies.map((o) => (M.isObj(o) ? o : { v: o, label: String(o) })) : [];
  }
  const firstCurrency = () => { const o = currencyOptions(); return o.length ? String(o[0].v) : 'gold'; };

  // ------------------------------------------------------------------ the state of a row

  function st(doc) {
    if (!doc.ui.skins) doc.ui.skins = { drafts: {}, players: new Map() };
    return doc.ui.skins;
  }
  /** What is on disk for a look, in the draft's shape. */
  function savedOf(look) {
    const s = M.isObj(look.skin) ? look.skin : {};
    return { purchasable: !!s.purchasable, name: String(s.name || ''), price: Number.isFinite(Number(s.price)) ? Math.trunc(Number(s.price)) : 0,
      currency_type: String(s.currency_type || firstCurrency()), unlock_quest: String(s.unlock_quest || '') };
  }
  function questOf(doc, code) {
    const rec = Assets.listRecord(doc) || {};
    const qs = M.isObj(rec.skin_quests) ? rec.skin_quests : {};
    return qs[code] || null;
  }
  function draftOf(doc, look) {
    const s = st(doc);
    if (!s.drafts[look.code]) s.drafts[look.code] = Object.assign(savedOf(look), { goal: null });
    return s.drafts[look.code];
  }
  const fieldsSame = (a, b) => a.purchasable === b.purchasable && a.name === b.name && a.price === b.price && a.currency_type === b.currency_type;
  function dirtyOf(doc, look) {
    const d = st(doc).drafts[look.code];
    if (!d) return false;
    if (!fieldsSame(d, savedOf(look))) return true;
    if (!d.goal) return false;
    const q = questOf(doc, look.code);
    return !q || JSON.stringify(prune(d.goal.condition)) !== JSON.stringify(prune(q.condition || {})) || String(d.goal.quest_text || '') !== String(q.quest_text || '');
  }
  /** The condition with only its type's keys (vocab quest_types: type -> keys), as the server keeps it. */
  function prune(cond) {
    const c = M.isObj(cond) ? cond : {};
    const types = (Assets.S.vocab && M.isObj(Assets.S.vocab.quest_types)) ? Assets.S.vocab.quest_types : null;
    const keys = types && Array.isArray(types[c.type]) ? types[c.type] : null;
    if (!keys) return Object.assign({}, c);
    const out = { type: c.type };
    for (const k of keys) if (c[k] != null) out[k] = c[k];
    return out;
  }
  function played(doc, look) { return !!look.default || look.code === String(doc.data.variant || doc.data.variant_base || ''); }
  function painted(look) { return look.ready !== false || !!look.base; }

  // ------------------------------------------------------------------ the section

  /** The chips on the section's bar: how many looks are on sale, how many carry a goal. */
  function chips(doc) {
    const looks = Array.isArray(doc.looks) ? doc.looks : [];
    const sale = looks.filter((l) => M.isObj(l.skin) && l.skin.purchasable && !played(doc, l) && !l.shelved).length;
    const goals = looks.filter((l) => questOf(doc, l.code)).length;
    const dirty = looks.filter((l) => dirtyOf(doc, l)).length;
    return [el('span', { class: 'achip' + (sale ? ' purchase' : ''), text: `${sale} on sale` }), goals ? el('span', { class: 'achip locked', text: `${goals} with a goal` }) : null,
      dirty ? el('span', { class: 'achip warn', text: `${dirty} unsaved` }) : null].filter(Boolean);
  }

  function section(doc) {
    ensureCurrencies();
    const wrap = el('div', { class: 'skins' });
    const looks = Array.isArray(doc.looks) ? doc.looks : [];
    wrap.appendChild(el('p', { class: 'muted small', text: `Tick Purchasable to offer a look in the game's shop for ${doc.data.name || doc.id}: give it the name players read, a price and its currency, and, if it should be earned first, a goal (a quest: the look stays locked until it is done; no goal = on sale at once). Each row saves on its own (the hero's Save asset does not write these). The look he is played in is every player's already.` }));
    if (S.failed) wrap.appendChild(el('div', { class: 'ferr warn', text: `No currency list (${S.failed}): restart the editor server (server.py changed in pass 111).` }));
    if (!looks.length) { wrap.appendChild(el('p', { class: 'muted small', text: 'No looks yet: paint one in Looks & previews first.' })); return wrap; }
    const order = looks.slice().sort((a, b) => (played(doc, b) - played(doc, a)) || (!!a.shelved - !!b.shelved) || String(a.code).localeCompare(String(b.code)));
    for (const look of order) wrap.appendChild(row(doc, look));
    // the players of looks that are gone
    const s = st(doc);
    for (const [code, p] of s.players) if (!looks.some((l) => l.code === code)) { if (p && p.destroy) p.destroy(); s.players.delete(code); }
    return wrap;
  }

  function still(doc, look) {
    const box = el('div', { class: 'skin-still' });
    if (!painted(look) || typeof StripPlayer === 'undefined' || typeof LookGrid === 'undefined' || !LookGrid.playerOpts) {
      box.appendChild(el('div', { class: 'placeholder', text: painted(look) ? '' : 'not painted' }));
      return box;
    }
    const rec = Assets.listRecord(doc) || { id: doc.id, name: doc.data.name };
    const s = st(doc);
    const opts = LookGrid.playerOpts('hero', rec, look, { mode: 'hover', zoom: 0.5 });
    let p = s.players.get(look.code);
    if (p && !p.destroyed) { if (p.url.split('?')[0] !== String(opts.url).split('?')[0] || (opts.mtime != null && !p.url.endsWith('v=' + encodeURIComponent(opts.mtime)))) p.setStrip(opts); }
    else { p = StripPlayer.create(opts); s.players.set(look.code, p); }
    box.appendChild(p.el);
    return box;
  }

  function row(doc, look) {
    const isPlayed = played(doc, look);
    const d = draftOf(doc, look);
    const saved = savedOf(look);
    const q = questOf(doc, look.code);
    const dirty = dirtyOf(doc, look);
    const card = el('article', { class: 'skin-row' + (isPlayed ? ' played' : '') + (look.shelved ? ' shelved' : '') + (dirty ? ' dirty' : '') + (d.purchasable && !isPlayed ? ' on' : ''), 'data-code': look.code });
    const badgeUrl = `${look.icon || `/icon/hero/${encodeURIComponent(doc.id)}/${encodeURIComponent(look.code)}`}?v=${doc.baseMtime || 0}`;
    const pics = el('div', { class: 'skin-pics' },
      el('img', { class: 'skin-badge', src: badgeUrl, alt: '', width: 56, height: 56, title: `${look.code}'s badge (its own, else the hero's): the goal's icon too`, onerror: (e) => { e.target.style.visibility = 'hidden'; } }),
      still(doc, look));
    card.appendChild(pics);
    const mid = el('div', { class: 'skin-mid' });
    mid.appendChild(el('div', { class: 'skin-head' }, el('b', { text: look.code }),
      isPlayed ? el('span', { class: 'achip available', text: 'played', title: 'the look he is played in (variant): every player owns it' }) : null,
      look.fresh ? el('span', { class: 'achip warn', text: 'NEW', title: 'not reviewed yet (Approve in Looks & previews)' }) : null,
      look.shelved ? el('span', { class: 'achip hidden', text: 'shelved' }) : null,
      !painted(look) ? el('span', { class: 'achip hidden', text: 'not painted' }) : null,
      !isPlayed && saved.purchasable ? el('span', { class: 'achip purchase', text: `on sale${saved.name ? ' as ' + saved.name : ''} · ${saved.price} ${saved.currency_type}` }) : null,
      q ? el('span', { class: 'achip locked', text: 'goal', title: TypedForms.questWords(q) }) : null,
      dirty ? el('span', { class: 'ccard-dirty', text: '●', title: 'unsaved changes in this row' }) : null));
    if (look.note) mid.appendChild(el('div', { class: 'muted small skin-note', text: look.note, title: look.note }));
    if (isPlayed) {
      mid.appendChild(el('div', { class: 'anote', text: `Always owned: the look ${doc.data.name || doc.id} is played in. Every player has it, so it is never sold.${saved.purchasable ? ' (Its skin still says purchasable: untick it and Save to tidy.)' : ''}` }));
      if (saved.purchasable) mid.appendChild(fields(doc, look, d, { onlyOff: true }));
    } else if (look.shelved || !painted(look)) {
      mid.appendChild(el('div', { class: 'anote warn', text: look.shelved ? 'Shelved: the game never offers a shelved look. Unshelve it in Looks & previews to sell it.' : 'Not painted yet: the game leaves it out, so it cannot be sold.' }));
      if (saved.purchasable || q) mid.appendChild(fields(doc, look, d, { onlyOff: true }));
    } else {
      mid.appendChild(fields(doc, look, d, {}));
    }
    card.appendChild(mid);
    return card;
  }

  /** The controls of one look: Purchasable, Name (+ Suggest), Price, Currency, the goal, the words, Save / Revert. */
  function fields(doc, look, d, o) {
    const box = el('div', { class: 'skin-fields' });
    const set = (fn) => { fn(); redrawRow(doc, look.code); };
    const cb = el('input', { type: 'checkbox', 'data-path': `skin.${look.code}.purchasable` });
    cb.checked = !!d.purchasable;
    cb.addEventListener('change', () => set(() => { d.purchasable = cb.checked; if (d.purchasable && !d.name) d.name = suggest(doc, look); }));
    box.appendChild(Forms.row({ key: 'purchasable', label: 'Purchasable', help: 'offered to the players (bought in the hero sheet, then worn); off = not offered' }, el('span', { class: 'cb-wrap' }, cb, el('span', { class: 'cb-text', text: d.purchasable ? 'yes: offered to the players' : 'no' })), {}));
    if (o.onlyOff) {
      // a look that cannot be sold: only untick it, and take its goal away (Remove goal)
      if (questOf(doc, look.code) && !d.goal) box.appendChild(goal(doc, look, d));
      box.appendChild(actions(doc, look, d, o));
      return box;
    }
    if (!d.purchasable && !M.isObj(look.skin) && !questOf(doc, look.code) && !d.goal) {
      // never offered: the tick alone (ticking it opens the rest, with a suggested name)
      box.appendChild(el('div', { class: 'anote muted', text: 'Not offered: players never see this look. Tick Purchasable to sell it.' }));
      return box;
    }
    const sug = suggest(doc, look);
    const name = Forms.textInput({ key: 'name' }, d.name, (v) => set(() => { d.name = v == null ? '' : String(v); }), { path: `skin.${look.code}.name`, placeholder: `Look ${look.code} (what players read when empty)` });
    box.appendChild(Forms.row({ key: 'name', label: 'Name', help: 'the name players read on the look (empty: the game says "Look <CODE>")' }, el('span', { class: 'skin-name' }, name,
      el('button', { class: 'btn small ghost', type: 'button', text: `Suggest: ${sug}`, title: 'put this name in the box (change it as you like)', onclick: () => set(() => { d.name = sug; }) })), {}));
    const price = Forms.numberInput({ key: 'price', min: 0, int: true, type: 'int' }, d.price, (v) => set(() => { d.price = v == null ? 0 : Math.max(0, Math.trunc(Number(v) || 0)); }), { path: `skin.${look.code}.price`, placeholder: '0' });
    box.appendChild(Forms.row({ key: 'price', label: 'Price', help: 'what buying it costs (0 = free once the goal is done)' }, price, {}));
    const curOpts = currencyOptions();
    const cur = curOpts.length ? Forms.iconSelect(curOpts, d.currency_type, (v) => set(() => { d.currency_type = v || firstCurrency(); }), { path: `skin.${look.code}.currency_type` })
      : el('span', { class: 'muted small', text: S.loading ? 'reading the currencies…' : d.currency_type });
    box.appendChild(Forms.row({ key: 'currency_type', label: 'Currency', help: 'the currency the price is paid in (content/currencies)' }, cur, {}));
    box.appendChild(goal(doc, look, d));
    box.appendChild(el('div', { class: 'anote' + (d.purchasable ? '' : ' muted'), text: words(doc, look, d) }));
    box.appendChild(actions(doc, look, d, o));
    return box;
  }

  /** What the players will see, in words. */
  function words(doc, look, d) {
    const q = questOf(doc, look.code);
    const g = d.goal || (q ? { condition: q.condition, quest_text: q.quest_text } : null);
    if (!d.purchasable) return 'Not offered: players never see this look.';
    const nm = d.name || `Look ${look.code}`;
    const cost = d.price > 0 ? `for ${d.price} ${(currencyOptions().find((c) => String(c.v) === d.currency_type) || {}).label || d.currency_type}` : 'free';
    return g ? `In the game: "${nm}" is locked until "${TypedForms.questWords(g)}", then on sale ${cost}.` : `In the game: "${nm}" is on sale at once, ${cost}.`;
  }

  function suggest(doc, look) {
    const taken = new Set((doc.looks || []).filter((l) => l.code !== look.code && M.isObj(l.skin)).map((l) => String(l.skin.name || '')));
    let h = 0;
    for (const ch of `${doc.id}:${look.code}`) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
    for (let i = 0; i < SUGGEST.length; i++) { const s = SUGGEST[(h + i) % SUGGEST.length]; if (!taken.has(s)) return s; }
    return `Look ${look.code}`;
  }

  /** The goal: its words with Edit / Remove goal, or + Add a goal; the editor is the Requirement's rows (QUEST_ROWS). */
  function goal(doc, look, d) {
    const q = questOf(doc, look.code);
    const wrap = el('div', { class: 'frow wide-ctl', 'data-key': `skin.${look.code}.goal` });
    wrap.appendChild(el('label', { class: 'flabel', text: 'Goal', title: `a quest (content/quests/skin_${doc.id}_${String(look.code).toLowerCase().replace(/-/g, '_')}) whose unlocks is {type skin, id ${doc.id}:${look.code}}: the look stays locked until it is done` }));
    const ctl = el('div', { class: 'fctl' });
    if (!d.goal) {
      if (q) {
        ctl.appendChild(el('div', { class: 'small' }, el('b', { text: `"${TypedForms.questWords(q)}"` }), el('span', { class: 'muted small', text: ` · ${q.id} (${(q.condition && q.condition.type) || '?'})` })));
        ctl.appendChild(el('div', { class: 'alt-actions' },
          el('button', { class: 'btn small', type: 'button', text: 'Edit goal', onclick: () => { d.goal = { condition: JSON.parse(JSON.stringify(q.condition || {})), quest_text: String(q.quest_text || '') }; redrawRow(doc, look.code); } }),
          el('button', { class: 'btn small danger', type: 'button', text: 'Remove goal', title: 'the quest file moves to the backups; the look goes on sale at once (when Purchasable)', onclick: () => { if (confirm(`Remove ${q.id}? ${look.code} needs no goal any more.`)) post(doc, look, { quest: null }); } })));
      } else {
        ctl.appendChild(el('div', { class: 'small muted', text: 'none: on sale at once' }));
        ctl.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: '+ Add a goal', onclick: () => { d.goal = { condition: { type: 'beat_stage', map: 'red_canyon', stage: 1, hero: doc.id }, quest_text: '' }; redrawRow(doc, look.code); } })));
      }
    } else {
      ctl.appendChild(goalEditor(doc, look, d));
    }
    wrap.appendChild(ctl);
    return wrap;
  }

  /** The condition rows of the hero's Requirement (AFIELDS.QUEST_ROWS) over the draft goal; beat_stage shows the stage's
   *  name beside its number and "any hero" for an empty hero; the words below follow every change. */
  function goalEditor(doc, look, d) {
    const box = el('div', { class: 'qdrawer' });
    const draft = d.goal;
    const q = questOf(doc, look.code);
    const qid = q ? q.id : `skin_${doc.id}_${String(look.code).toLowerCase().replace(/-/g, '_')}`;
    box.appendChild(el('div', { class: 'small' }, el('b', { text: qid }), el('span', { class: 'muted small', text: ` · content/quests/${qid}/ · reads: "${TypedForms.questWords(draft)}"` })));
    const localApply = (fn) => {
      const was = String((draft.condition || {}).type || '');
      fn();
      const c = draft.condition || (draft.condition = {});
      // a goal turned into beat_stage starts on this map's first stage with this hero (empty the hero for any hero)
      if (c.type === 'beat_stage' && was !== 'beat_stage') { if (!c.map) c.map = 'red_canyon'; if (!c.stage) c.stage = 1; if (!('hero' in c) || c.hero == null) c.hero = doc.id; }
      redrawRow(doc, look.code);
    };
    const type = String((draft.condition || {}).type || '');
    for (const def of F.QUEST_ROWS) {
      if (def.key === 'name') continue;   // the quest's name follows the look's: "<hero> · <name>"
      if (typeof def.only === 'function' && !def.only(draft)) continue;
      const def2 = Object.assign({}, def);
      if (typeof def.options === 'function') def2.options = F.options(def, Assets.vocab());
      const path = `skin.${look.code}.${def.key}`;
      let rowEl;
      if (def.type === 'enemy') rowEl = Forms.row(def2, Forms.enemyPick(U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, v)), { path, summary: false, emptyLabel: '—' }), {});
      else if (def.type === 'id_select') {
        const anyHero = def.key === 'condition.hero' && type === 'beat_stage';
        rowEl = Forms.row(def2, Forms.iconSelect(((def.kind === 'hero' ? Assets.ensureHeroes() : null), Assets.idOptions(def.kind || 'weapon')) || [], U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, anyHero ? (v || '') : v)), { emptyLabel: anyHero ? 'any hero' : '—', path }), {});
      } else if (def.key === 'condition.map' && Array.isArray(App.S.maps) && App.S.maps.length) {
        rowEl = Forms.row(def2, Forms.select(App.S.maps.map((m) => ({ v: m.id, label: `${m.name || m.id} (${m.id})` })), U.getPath(draft, def.key) || 'red_canyon', (v) => localApply(() => U.setPath(draft, def.key, v || 'red_canyon')), { path }), {});
      } else {
        const after = def.key === 'condition.stage' && type === 'beat_stage' ? el('span', { class: 'muted small skin-hint', text: stageHint(draft.condition) }) : null;
        // (Forms.control's own `after` is a callback; the hint goes to the row's `after`)
        rowEl = Forms.row(def2, Forms.control(def2, draft, { apply: (fn) => localApply(fn), pathPrefix: `skin.${look.code}` }), { after });
      }
      box.appendChild(rowEl);
    }
    // pass 113 (lane TASKS): the picture the game draws for the goal (tasks.js)
    if (typeof TaskPics !== 'undefined') box.appendChild(TaskPics.row(draft));
    box.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small ghost', type: 'button', text: q ? 'Cancel the goal edit' : 'Drop the new goal', onclick: () => { d.goal = null; redrawRow(doc, look.code); } }),
      el('span', { class: 'muted small', text: 'Save (below) writes the goal with the rest of the row.' })));
    return box;
  }

  /** "Nightfall (of 3: Sundown, Nightfall, Blood Moon)" for beat_stage's stage box. */
  function stageHint(c) {
    const tl = Assets.mapTl(String((c && c.map) || 'red_canyon'));
    const sl = tl && Array.isArray(tl.stage_list) ? tl.stage_list.filter(M.isObj) : [];
    if (!sl.length) return tl ? 'this map has no stage list' : 'reading the map…';
    const k = Math.trunc(Number((c && c.stage) || 1));
    const e = sl[k - 1];
    return e ? `${e.name || 'stage ' + k} (of ${sl.length}: ${sl.map((x, i) => x.name || 'stage ' + (i + 1)).join(', ')})` : `no stage ${k}: the map has ${sl.length} (${sl.map((x) => x.name).join(', ')})`;
  }

  function actions(doc, look, d, o) {
    const dirty = dirtyOf(doc, look);
    return el('div', { class: 'alt-actions skin-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: 'Save', disabled: !dirty, title: `writes ${look.code}'s skin into ${doc.id}.json${d.goal ? ' and its goal quest' : ''} and imports them (only this row)`, onclick: () => save(doc, look) }),
      el('button', { class: 'btn small ghost', type: 'button', text: 'Revert', disabled: !dirty, title: 'back to what is on disk', onclick: () => { delete st(doc).drafts[look.code]; redrawRow(doc, look.code); } }),
      o && o.onlyOff ? null : el('span', { class: 'muted small', text: dirty ? 'unsaved' : 'as on disk' }));
  }

  // ------------------------------------------------------------------ writing

  async function save(doc, look) {
    const d = draftOf(doc, look);
    const body = { purchasable: !!d.purchasable, name: d.name || '', price: Math.max(0, Math.trunc(Number(d.price) || 0)), currency_type: d.currency_type || firstCurrency() };
    if (d.goal) body.quest = { condition: prune(d.goal.condition), quest_text: String(d.goal.quest_text || '') };
    await post(doc, look, body);
  }

  async function post(doc, look, body) {
    App.status(`Writing ${doc.id} ${look.code}'s skin…`, 'busy');
    let res;
    try { res = await Assets.postJSON(`/api/content/hero/${encodeURIComponent(doc.id)}/skin/${encodeURIComponent(look.code)}`, body); } catch (e) { App.status(`Could not write the skin: ${e.message}`, 'bad'); return false; }
    const { status, data } = res;
    if (status === 404 && data && /unknown|no such/i.test(String(data.error || ''))) { App.status('The server has no skin route yet: restart the Level Editor server (pass 111 changed server.py)', 'bad'); return false; }
    if (!data || !data.ok) { App.status(`${look.code}: ${(data && data.error) || status}`, 'bad'); return false; }
    delete st(doc).drafts[look.code];
    const imp = data.import_ok === true ? 'imported' : data.import_ok === null ? 'the import was queued (the Godot lock is busy)' : data.unchanged ? '' : `import: ${data.output || 'not run'}`;
    App.toast(`${doc.id} ${look.code}: ${data.unchanged ? 'nothing changed' : (data.wrote || []).join(', ')}${imp ? ' · ' + imp : ''}`);
    if (data.import_ok === false && !data.unchanged) App.status(`${look.code} written, but ${imp}`, 'bad');
    await Assets.refreshRecord('hero', doc.id);
    await Assets.refreshList('heroes');
    App.render('tab');
    return true;
  }

  /** Draw one row again in place (the rest of the pane keeps its DOM, its folds and its scroll). */
  function redrawRow(doc, code) {
    const pane = doc.pane;
    const look = (doc.looks || []).find((l) => l.code === code);
    const old = pane && look ? pane.querySelector(`.skin-row[data-code="${CSS.escape(code)}"]`) : null;
    if (!old) { Assets.redraw(doc, 'editor'); return; }
    old.replaceWith(row(doc, look));
    // the section's chips follow
    const sec = pane.querySelector('details.asection[data-section="Skins"]');
    const sum = sec ? sec.querySelector('summary') : null;
    if (sum) { for (const c of [...sum.querySelectorAll('.achip')]) c.remove(); for (const c of chips(doc)) sum.appendChild(c); }
  }

  // ------------------------------------------------------------------ the hero card's line and the Instructions

  /** "2 skins on sale" for the Heroes list card (the record of /api/heroes). */
  function cardLine(h) {
    const n = Number(h && h.skins_on_sale) || 0;
    const goals = h && M.isObj(h.skin_quests) ? Object.keys(h.skin_quests).length : 0;
    if (!n && !goals) return null;
    return el('span', { class: 'plate', title: 'looks offered to the players (Skins in his editor)' }, el('span', { class: 'achip purchase', text: `${n} skin${n === 1 ? '' : 's'} on sale` }), goals ? el('span', { class: 'muted small', text: `${goals} with a goal` }) : null);
  }

  function instructions(root) {
    const p = (html) => { const n = el('p', {}); n.innerHTML = html; return n; };
    const li = (html) => { const n = el('li', {}); n.innerHTML = html; return n; };
    root.appendChild(el('h2', { text: 'Pass 111: Skins (a hero\'s looks players can buy)' }));
    root.appendChild(p('Any painted look of a hero can be offered to the players as a <b>skin</b>: they buy it (gold today; any currency in <code>content/currencies</code>) and wear it. A skin can also have a <b>goal</b>: a quest that must be done first ("Beat Nightfall with May.").'));
    const ol = el('ol', { class: 'howto' });
    for (const s of [
      'Open the <b>Heroes</b> tab and press <b>Edit</b> on the hero.',
      'Open the section <b>Skins (looks players can buy)</b> (under Looks &amp; previews). Every look is a row with its badge and a still (hover it to play).',
      'Tick <b>Purchasable</b>. Type the <b>Name</b> players will read (or press <i>Suggest</i>), the <b>Price</b> (0 = free once the goal is done) and pick the <b>Currency</b>.',
      'For a goal press <b>+ Add a goal</b>: it starts as <i>beat a stage</i> on Red Canyon, stage 1, with this hero. Change the stage (its name shows beside the number: 1 Sundown, 2 Nightfall, 3 Blood Moon), empty the hero for <i>any hero</i>, or pick any other condition (the same list as a hero\'s Requirement). The words the game will show are under it.',
      'Press the row\'s <b>Save</b>. It writes the look\'s <code>skin</code> in the hero\'s JSON and the goal as <code>content/quests/skin_&lt;hero&gt;_&lt;code&gt;</code>, then imports both. (The hero\'s own <i>Save asset</i> does not write skins.)',
    ]) ol.appendChild(li(s));
    root.appendChild(ol);
    root.appendChild(el('ul', {},
      li('<b>Remove goal</b> moves the quest to the backups; the look is then on sale at once. <b>Revert</b> drops the row\'s unsaved edits.'),
      li('The look the hero is <b>played in</b> is every player\'s already and is never sold. A <b>shelved</b> or <b>not painted</b> look cannot be sold (unshelve it first).'),
      li('The hero card in the list says how many of his skins are on sale. Prices of heroes (Availability) and skins both pick their currency from <code>content/currencies</code>.')));
  }

  return { section, chips, cardLine, instructions, ensureCurrencies, savedOf, prune, suggest, S };
})();
if (typeof module !== 'undefined') module.exports = Skins;
