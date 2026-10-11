'use strict';
// Pass 66 (lane P): the Heroes tab. The list pane shows every hero as the game plays him (the records of /api/heroes:
// the round badge, name and order, the availability chip, the trait sentence, the start and favourite plates, how many
// looks, the title cut-out), with an Edit button each and "+ New from template"; the editor pane (assets.js's header,
// sections and field rows over AFIELDS.hero) has the Identity, Trait (with TextGen.hero_trait's sentence previewed and
// "at level 20"), Favourites, Specials, Availability (written and shown, not wired), "His own" (his weapon, hero mutation
// and perks), Art words (pose drivers from /api/drivers, the title and badge words) and Looks & previews (lane V's
// LookGrid, the round badge at 128 / 64, the title cut-out in its 660x888 frame at a quarter).
const Heroes = (() => {
  const { el, clear, fmtN } = U;
  const M = AssetsModel, F = AFIELDS;
  let listEl = null, createHost = null, creating = false;
  const filt = () => Assets.S.filters.heroes;

  function render(panel) {
    Forms.closePop();
    clear(panel);
    Assets.ensureHeroes(); Assets.ensureItems(); Assets.ensureVocab(); Assets.ensureDrivers(); Assets.ensureMethods();
    const doc = Assets.active('heroes');
    const wrap = el('div', { class: 'apanes' + (doc ? ' with-editor' : '') });
    const list = el('div', { class: 'alist' });
    const bar = el('div', { class: 'palette-bar' });
    const box = el('input', { type: 'search', class: 'txt wide', placeholder: 'filter by name, id or trait…', value: filt().q });
    box.addEventListener('input', () => { filt().q = box.value.trim().toLowerCase(); draw(); });
    bar.appendChild(box);
    bar.appendChild(Forms.select([{ v: 'all', label: 'every hero' }, { v: 'available', label: 'playable' }, { v: 'hidden', label: 'hidden' }, { v: 'purchase', label: 'purchase' }], filt().status, (v) => { filt().status = v || 'all'; draw(); }, { path: 'heroes.status' }));
    bar.appendChild(el('button', { class: 'btn small' + (creating ? ' toggle on' : ''), type: 'button', text: '+ New from template ▾', title: 'a new hero folder from another hero\'s JSON (hidden until the tests are re-pinned)', onclick: () => { creating = !creating; drawCreate(); } }));
    list.appendChild(bar);
    createHost = el('div', { class: 'acreate-host' });
    list.appendChild(createHost);
    drawCreate();
    listEl = el('div', { class: 'hlist' });
    list.appendChild(listEl);
    wrap.appendChild(list);
    if (doc) wrap.appendChild(Assets.buildPane(doc, (pane) => editor(pane, doc)));
    panel.appendChild(wrap);
    draw();
  }

  function drawCreate() {
    if (!createHost) return;
    clear(createHost);
    if (!creating) return;
    const hs = Assets.S.lists.heroes || [];
    const templates = hs.map((h) => ({ v: h.id, label: h.name || h.id, icon: h.icon || `/icon/hero/${h.id}`, sub: `${h.id}${h.hidden ? ' · hidden' : ''} · ${h.trait_name || ''}`, dim: !!h.hidden }));
    const taken = new Set(hs.map((h) => h.id).concat((App.S.enemies || []).map((c) => c.id)));
    createHost.appendChild(Assets.createDialog('hero', templates, taken, {
      label: 'hero', docRequired: false, copyArt: true,
      note: 'A new hero starts hidden (hidden: true, availability "hidden", price 0, gold): the tests pin the five heroes on the title (pass334, pass61_hr); turn him available after a re-pin. His numbers and art words come from the template; the looks and PNGs only with "copy the art".',
      onCreate: async (body) => { const d = await Assets.create('hero', body); if (d) creating = false; },
      onCancel: () => { creating = false; drawCreate(); },
    }));
  }

  const avail = (h) => h.availability || (h.hidden ? 'hidden' : 'available');

  function draw() {
    if (!listEl) return;
    clear(listEl);
    const hs = Assets.S.lists.heroes;
    if (!hs) { listEl.appendChild(el('p', { class: 'muted', text: Assets.S.failed.heroes ? `No hero list: ${Assets.S.failed.heroes} (lane S's /api/heroes)` : 'Reading the heroes…' })); return; }
    const f = filt();
    const list = hs.filter((h) => (f.status === 'all' || avail(h) === f.status) && (!f.q || [h.id, h.name, h.trait_name, h.trait_text, h.flavour].some((s) => String(s || '').toLowerCase().includes(f.q))));
    list.sort((a, b) => (!!a.hidden - !!b.hidden) || ((a.order == null ? 100 : a.order) - (b.order == null ? 100 : b.order)) || String(a.id).localeCompare(String(b.id)));
    listEl.appendChild(el('div', { class: 'muted small', text: `${list.length} of ${hs.length} heroes · the title shows the playable ones by order` }));
    for (const h of list) listEl.appendChild(card(h));
  }

  function card(h) {
    const doc = Assets.S.docs[`hero:${h.id}`] || null;
    const editing = !!doc && Assets.S.open.heroes === doc.key;
    const fl = Assets.flatItems();
    const nameOf = (kind, id) => { if (!fl || !id) return id || ''; const list = kind === 'weapon' ? fl.weapons : fl.passives; const x = list.find((w) => w.id === id); return x ? (x.name || id) : id; };
    const art = el('article', { class: 'hcard' + (h.hidden ? ' dim' : '') + (editing ? ' editing' : ''), 'data-id': h.id });
    art.appendChild(el('img', { class: 'hcard-badge', src: h.icon || `/icon/hero/${h.id}`, alt: '', width: 64, height: 64, onerror: (e) => { e.target.style.visibility = 'hidden'; } }));
    const mid = el('div', { class: 'hcard-mid' });
    mid.appendChild(el('h3', {}, el('span', { text: h.name || h.id }), el('span', { class: 'muted small', text: h.order != null ? `#${h.order}` : '' }), Assets.statusChip(avail(h), avail(h) === 'purchase' ? `${h.price || 0} ${h.currency_type || 'gold'}: not wired` : ''), doc && Assets.docDirty(doc) ? el('span', { class: 'ccard-dirty', text: '●', title: 'unsaved changes' }) : null));
    mid.appendChild(el('div', { class: 'muted small', text: `${h.id} · ${h.pronoun || 'they'} · ${h.trait_name || 'no trait name'}` }));
    mid.appendChild(el('div', { class: 'small', text: h.trait_text || M.heroTrait(h) || '' }));
    const plates = el('div', { class: 'plates' });
    if (h.start_weapon) plates.appendChild(el('span', { class: 'plate', title: 'START: the weapon he lands with' }, el('img', { src: `/icon/weapon/${h.start_weapon}`, alt: '' }), el('span', { text: `start ${nameOf('weapon', h.start_weapon)}` })));
    if (h.favourite_weapon) plates.appendChild(el('span', { class: 'plate', title: 'FAVOURITE: arrives with a bonus, carries his hero mutation' }, el('img', { src: `/icon/weapon/${h.favourite_weapon}`, alt: '' }), el('span', { text: `favourite ${nameOf('weapon', h.favourite_weapon)}` })));
    if (h.favourite_passive) plates.appendChild(el('span', { class: 'plate', title: 'FAVOURITE passive' }, el('img', { src: `/icon/passive/${h.favourite_passive}`, alt: '' }), el('span', { text: `favourite ${nameOf('passive', h.favourite_passive)}` })));
    const looks = Array.isArray(h.looks) ? h.looks : [];
    plates.appendChild(el('span', { class: 'plate muted', text: `${looks.length} look${looks.length === 1 ? '' : 's'}${looks.filter((l) => l.fresh).length ? ` · ${looks.filter((l) => l.fresh).length} new` : ''}${looks.filter((l) => l.shelved).length ? ` · ${looks.filter((l) => l.shelved).length} shelved` : ''}` }));
    mid.appendChild(plates);
    mid.appendChild(el('div', { class: 'ccard-actions' }, el('button', { class: 'btn small' + (editing ? ' primary' : ''), type: 'button', text: editing ? 'Editing' : 'Edit', onclick: () => Assets.open('hero', h.id) })));
    art.appendChild(mid);
    art.appendChild(el('img', { class: 'hcard-title', src: h.title || `/art/wanted/hero_${h.id}.png`, alt: '', title: 'the title cut-out (art/ui/wanted/hero_<id>.png); stripes when missing', onerror: (e) => { e.target.removeAttribute('src'); } }));
    return art;
  }

  function redraw(doc, what) {
    if (what === 'all') { App.render('tab'); return; }
    if (!Assets.swapPane(doc, (pane) => editor(pane, doc))) App.render('tab');
    else if (listEl) for (const c of listEl.querySelectorAll('.hcard')) { const d = Assets.S.docs[`hero:${c.dataset.id}`]; c.classList.toggle('editing', !!d && Assets.S.open.heroes === d.key); const dot = c.querySelector('.ccard-dirty'); if (dot) dot.hidden = !(d && Assets.docDirty(d)); }
  }

  // ------------------------------------------------------------------ the editor

  function editor(pane, doc) {
    const iss = Assets.issuesOf(doc);
    const defs = F.hero;
    pane.appendChild(Assets.header(doc, iss));
    const sec = (name, nodes, opts) => Assets.section(doc, name, nodes, Object.assign({ marks: Assets.sectionMarks(iss, (opts && opts.keys) || Assets.sectionKeys(defs, name)) }, opts || {}));
    pane.appendChild(sec('Identity', Assets.rows(doc, defs, 'Identity', iss), { open: true }));
    pane.appendChild(sec('Trait', Assets.rows(doc, defs, 'Trait', iss), { open: true, foot: 'The signature stat grows per level (Run.hero_sheet); the plaque, the hero sheet and the arena read TextGen.hero_trait, which the preview above mirrors.' }));
    pane.appendChild(sec('Favourites', Assets.rows(doc, defs, 'Favourites', iss), { open: true }));
    pane.appendChild(sec('Specials', Assets.rows(doc, defs, 'Specials', iss)));
    pane.appendChild(sec('Availability', Assets.rows(doc, defs, 'Availability', iss).concat([availabilityNote(doc)]), { open: true }));
    pane.appendChild(sec('His own', hisOwn(doc), { open: true, keys: ['perks'], chips: [] }));
    pane.appendChild(sec('Art words', Assets.rows(doc, defs, 'Art words', iss), { foot: 'The words gen_art.py sends for the base look; title_* and badge.* feed gen_title_heroes.py and the badge job. Each look\'s own recipe (in Looks) overrides the clip keys.' }));
    const lookChips = [el('span', { class: 'achip', text: `${doc.looks.length} look${doc.looks.length === 1 ? '' : 's'}` })];
    pane.appendChild(sec('Looks & previews', [Assets.looksSection(doc, iss), previews(doc)].concat(Assets.rows(doc, defs, 'Looks & previews', iss)), { open: true, chips: lookChips, keys: ['looks', 'variant', 'variant_base', 'anims', 'strip_cols', 'frame_px', 'fps'] }));
  }

  /** hidden and availability kept in step: a change of one writes the other (Godot hides when either says so) */
  function availabilityNote(doc) {
    const d = doc.data;
    const av = d.availability || (d.hidden ? 'hidden' : 'available');
    const agree = !!d.hidden === (av !== 'available');
    const wrap = el('div', { class: 'anote' + (agree ? '' : ' warn') });
    wrap.appendChild(el('div', { class: 'small', text: `In play: ${av === 'available' ? 'playable from the title' : av === 'purchase' ? 'hidden until the purchase loop is wired (parked: Garry asked to be reminded when he raises heroes\' cost again)' : 'hidden: not on the title, not in the arena\'s tiles'}. The server keeps hidden = (availability != available).` }));
    if (!agree) wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: `Make hidden agree (${av !== 'available' ? 'hidden: true' : 'hidden off'})`, onclick: () => Assets.apply(doc, (dd) => { if (av !== 'available') dd.hidden = true; else delete dd.hidden; }, 'editor') }));
    else wrap.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: av === 'available' ? 'Hide him' : 'Make him playable', title: av === 'available' ? 'hidden: true and availability hidden' : 'the tests pin the five heroes: re-pin them first', onclick: () => Assets.apply(doc, (dd) => { if (av === 'available') { dd.hidden = true; dd.availability = 'hidden'; } else { delete dd.hidden; dd.availability = 'available'; } }, 'editor') }));
    return wrap;
  }

  /** His weapon(s) (WeaponDef.hero), his hero mutation(s) and his perks, each with Edit where an editor exists. */
  function hisOwn(doc) {
    const rec = Assets.listRecord(doc) || {};
    const fl = Assets.flatItems();
    const weapons = Array.isArray(rec.weapons) && rec.weapons.length ? rec.weapons : (fl ? fl.weapons.filter((w) => w.hero === doc.id).map((w) => w.id) : []);
    const muts = Array.isArray(rec.hero_mutations) && rec.hero_mutations.length ? rec.hero_mutations : (fl ? fl.mutations.filter((m) => m.hero === doc.id).map((m) => m.id) : []);
    const perks = Array.isArray(rec.perks) ? rec.perks : [];
    const nameOf = (list, id) => { const x = (list || []).find((w) => w.id === id); return x ? (x.name || id) : id; };
    const out = el('div', { class: 'hisown' });
    const line = (kind, id, label, extra) => el('div', { class: 'isub' }, el('img', { src: `/icon/${kind}/${id}`, alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }), el('span', { class: 'achip ' + kind, text: label }), el('b', { text: nameOf(fl ? (kind === 'weapon' ? fl.weapons : fl.mutations) : [], id) }), el('span', { class: 'muted small', text: id }), extra || null,
      kind !== 'perk' ? el('button', { class: 'btn small ghost', type: 'button', text: 'Edit', onclick: () => Assets.open(kind, id) }) : null);
    if (!weapons.length) out.appendChild(el('div', { class: 'muted small', text: `No weapon carries hero: "${doc.id}" (WeaponDef.hero). Start weapon: ${doc.data.start_weapon || 'the favourite, else the peashooter'}.` }));
    for (const id of weapons) { const w = fl ? fl.weapons.find((x) => x.id === id) : null; out.appendChild(line('weapon', id, 'his weapon', w && w.evolves_into ? el('span', { class: 'muted small', text: `→ ${w.evolves_into}` }) : null)); }
    if (!muts.length) out.appendChild(el('div', { class: 'muted small', text: 'No hero mutation (kind hero, hero = this id): a playable hero has exactly one, on his favourite weapon (pass26_test).' }));
    for (const id of muts) { const m = fl ? fl.mutations.find((x) => x.id === id) : null; out.appendChild(line('mutation', id, 'hero mutation', m ? el('span', { class: 'muted small', text: `on ${m.weapon}${m.weapon !== doc.data.favourite_weapon ? ' (not his favourite!)' : ''}` }) : null)); }
    if (!perks.length) out.appendChild(el('div', { class: 'muted small', text: 'No perks listed (content/perks with hero = this id; played heroes have 1-2).' }));
    for (const id of perks) out.appendChild(el('div', { class: 'isub' }, el('img', { src: `/icon/perk/${id}`, alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }), el('span', { class: 'achip perk', text: 'perk' }), el('b', { text: id }), el('span', { class: 'muted small', text: 'content/perks/' + id + ' (perks have no editor here: a JSON of text, effects and a special the code knows)' })));
    return out;
  }

  /** The round badge at 128 and 64 and the title cut-out (660x888 at a quarter; the title's stripes when missing). */
  function previews(doc) {
    const wrap = el('div', { class: 'hprev' });
    wrap.appendChild(Assets.iconPreview(doc, { key: 'icon' }));
    const url = `/art/wanted/hero_${encodeURIComponent(doc.id)}.png?v=${doc.baseMtime || 0}`;
    let cut;
    if (typeof CutoutPreview === 'function') { try { cut = CutoutPreview(url); } catch (_) { cut = null; } }
    if (!cut) {
      const img = el('img', { src: url, alt: '', onerror: (e) => { e.target.remove(); } });
      cut = el('div', { class: 'cutout', title: 'the title cut-out (game/art/ui/wanted/hero_<id>.png, 660x888) at a quarter; stripes = the title\'s placeholder' }, img,
        el('button', { class: 'btn small zoom', type: 'button', text: '⤢', title: 'at 1:1', onclick: () => {
          const box = el('div', { class: 'amodal-back' });
          box.appendChild(el('div', { class: 'amodal wide' }, el('h3', { text: `hero_${doc.id}.png at 1:1 (660 × 888)` }), el('img', { src: url, alt: '', style: 'max-width:100%;display:block;background:repeating-linear-gradient(45deg,#3a3429 0 8px,#2a2520 8px 16px)' }), el('div', { class: 'amodal-actions' }, el('button', { class: 'btn', type: 'button', text: 'Close', onclick: () => box.remove() }))));
          box.addEventListener('click', (e) => { if (e.target === box) box.remove(); });
          document.body.appendChild(box);
        } }));
    }
    wrap.appendChild(el('div', { class: 'cutout-wrap' }, el('div', { class: 'muted small', text: 'Title cut-out' }), cut, el('button', { class: 'btn small', type: 'button', text: '+ Title cut-out candidates…', onclick: () => Assets.openJobForm(doc, { method: 'hero_title', mode: 'title' }) })));
    return wrap;
  }

  return { render, redraw, card };
})();
