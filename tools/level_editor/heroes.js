'use strict';
// Pass 66 (lane P): the Heroes tab. The list pane shows every hero as the game plays him (the records of /api/heroes:
// the round badge, name and order, the availability chip, the trait sentence, the start and favourite plates, how many
// looks, the title cut-out), with an Edit button each and "+ New from template"; the editor pane (assets.js's header,
// sections and field rows over AFIELDS.hero) has the Identity, Trait (with TextGen.hero_trait's sentence previewed and
// "at level 20"), Favourites, Specials, Availability, "His own" (his weapon, hero mutation and perks), Art words (pose
// drivers from /api/drivers, the title and badge words) and Looks & previews (lane V's LookGrid, the round badge at 128 /
// 64, the title cut-out in its 660x888 frame at a quarter). Pass 69 (lane LE): Availability is wired (free / to buy /
// hidden, `hidden` kept in step) with his Requirement (typed_forms.js: his unlock quest), and every perk opens the perk
// form (Edit, + New perk…); a perk document shows on this tab.
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
    bar.appendChild(Forms.select([{ v: 'all', label: 'every hero' }, { v: 'available', label: 'free' }, { v: 'purchase', label: 'to buy' }, { v: 'hidden', label: 'hidden' }], filt().status, (v) => { filt().status = v || 'all'; draw(); }, { path: 'heroes.status' }));
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
    const templates = hs.map((h) => ({ v: h.id, label: h.name || h.id, icon: h.icon_play || h.icon || `/icon/hero/${h.id}`, sub: `${h.id}${h.hidden ? ' · hidden' : ''} · ${h.trait_name || ''}`, dim: !!h.hidden }));
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
    // pass 70: the badge of the look he is played in (the JSON's variant), as the game draws him (Registry.played_look)
    art.appendChild(el('img', { class: 'hcard-badge', src: h.icon_play || h.icon || `/icon/hero/${h.id}`, alt: '', width: 64, height: 64, title: h.variant ? `the badge of ${h.variant}, the look he is played in` : '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }));
    const mid = el('div', { class: 'hcard-mid' });
    mid.appendChild(el('h3', {}, el('span', { text: h.name || h.id }), el('span', { class: 'muted small', text: h.order != null ? `#${h.order}` : '' }), Assets.statusChip(avail(h), avail(h) === 'purchase' ? `${h.price || 0} ${h.currency_type || 'gold'}${h.quest ? ' once "' + TypedForms.questWords(h.quest) + '"' : ', on sale at once'}` : (h.quest && avail(h) === 'available' ? `free once "${TypedForms.questWords(h.quest)}"` : '')), avail(h) === 'purchase' ? el('span', { class: 'achip', text: `${h.price || 0} ${h.currency_type || 'gold'}`, title: 'the BUY price (pass 69)' }) : null, h.quest && avail(h) !== 'hidden' ? el('span', { class: 'achip locked', text: 'requirement', title: TypedForms.questWords(h.quest) }) : null, doc && Assets.docDirty(doc) ? el('span', { class: 'ccard-dirty', text: '●', title: 'unsaved changes' }) : null));
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
    art.appendChild(el('img', { class: 'hcard-title', src: h.title_play || h.title || `/art/wanted/hero_${h.id}.png`, alt: '', title: 'the title cut-out of the look he is played in (its own, else art/ui/wanted/hero_<id>.png); stripes when missing', onerror: (e) => { e.target.removeAttribute('src'); } }));
    return art;
  }

  function redraw(doc, what) {
    if (what === 'all') { App.render('tab'); return; }
    if (!Assets.swapPane(doc, (pane) => editor(pane, doc))) App.render('tab');
    else if (listEl) for (const c of listEl.querySelectorAll('.hcard')) { const d = Assets.S.docs[`hero:${c.dataset.id}`]; c.classList.toggle('editing', !!d && Assets.S.open.heroes === d.key); const dot = c.querySelector('.ccard-dirty'); if (dot) dot.hidden = !(d && Assets.docDirty(d)); }
  }

  // ------------------------------------------------------------------ the editor

  function editor(pane, doc) {
    // pass 69 (lane LE): a perk opened from His own is edited on this tab (typed_forms.js)
    if (doc.kind === 'perk') { TypedForms.perkEditor(pane, doc); return; }
    const iss = Assets.issuesOf(doc);
    const defs = F.hero;
    pane.appendChild(Assets.header(doc, iss));
    const sec = (name, nodes, opts) => Assets.section(doc, name, nodes, Object.assign({ marks: Assets.sectionMarks(iss, (opts && opts.keys) || Assets.sectionKeys(defs, name)) }, opts || {}));
    pane.appendChild(sec('Identity', Assets.rows(doc, defs, 'Identity', iss), { open: true }));
    pane.appendChild(sec('Trait', Assets.rows(doc, defs, 'Trait', iss), { open: true, foot: 'The signature stat grows per level (Run.hero_sheet); the plaque, the hero sheet and the arena read TextGen.hero_trait, which the preview above mirrors.' }));
    pane.appendChild(sec('Favourites', Assets.rows(doc, defs, 'Favourites', iss), { open: true }));
    pane.appendChild(sec('Specials', Assets.rows(doc, defs, 'Specials', iss)));
    // pass 69: the requirement (his unlock quest) and what the title shows; availabilityNote keeps hidden in step
    pane.appendChild(sec('Availability', Assets.rows(doc, defs, 'Availability', iss).concat([TypedForms.requirement(doc), availabilityNote(doc)]), { open: true, keys: Assets.sectionKeys(defs, 'Availability').concat(['requirement', 'hidden']) }));
    pane.appendChild(sec('His own', hisOwn(doc), { open: true, keys: ['perks'], chips: [] }));
    // pass 69 (lane LE): a new OpenPose driver (driver_pose: lane ART's amp / lean / arms back, and level shoulders into <name>_lvl)
    const newDriver = el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: '+ New pose driver…', title: 'an OpenPose driver from a Mixamo FBX or an uploaded rigged model (driver_pose): frames, slice, arms, a sprint\'s amp and lean, and the shoulders levelled with the neck (a second driver <name>_lvl) for the back and side views', onclick: () => Assets.openJobForm(doc, { mode: 'driver', method: 'driver_pose' }) }),
      el('button', { class: 'btn small', type: 'button', text: '+ Tweak a driver…', title: 'pass 70: a copy of a library driver with one change in chosen views (driver_tweak): scale (a wide figure that leaves the clip; a view too big or too small is the Run size of the recipe, run_scale), spread or occlude (hands that show through on the back views), shoulders (levelled; tuck for the far arm of the side view); then name it for that view in the recipe of the look (pose_drivers.<view>) and re-roll that clip', onclick: () => Assets.openJobForm(doc, { mode: 'driver', method: 'driver_tweak' }) }),
      el('span', { class: 'muted small', text: 'the drivers above pick from tools/dl/drivers; run_side (side) and run_spread_lvl (back) keep the shoulders level (pass 69)' }));
    pane.appendChild(sec('Art words', Assets.rows(doc, defs, 'Art words', iss).concat([newDriver]), { foot: 'The words gen_art.py sends for the base look; title_* and badge.* feed gen_title_heroes.py and the badge job. Each look\'s own recipe (in Looks) overrides the clip keys.' }));
    const lookChips = [el('span', { class: 'achip', text: `${doc.looks.length} look${doc.looks.length === 1 ? '' : 's'}` })];
    pane.appendChild(sec('Looks & previews', [Assets.looksSection(doc, iss), previews(doc)].concat(Assets.rows(doc, defs, 'Looks & previews', iss)), { open: true, chips: lookChips, keys: ['looks', 'variant', 'variant_base', 'anims', 'strip_cols', 'frame_px', 'fps'] }));
  }

  /** hidden and availability kept in step (pass 69, lane UI's rule in JsonContent.build: only availability "hidden"
   *  hides; a hero to buy is on the title whatever `hidden` says; an available one with hidden: true stays hidden).
   *  Changing Availability above writes `hidden` too; this offers the fix when a hand edit left them apart. */
  function availabilityNote(doc) {
    const d = doc.data;
    const av = d.availability || (d.hidden ? 'hidden' : 'available');
    const agree = !!d.hidden === (av === 'hidden');
    if (agree) return null;
    const wrap = el('div', { class: 'anote warn', 'data-key': 'hidden' });
    wrap.appendChild(el('div', { class: 'small', text: `hidden is ${!!d.hidden} while availability is ${av}: ${av === 'purchase' ? 'the game shows a hero to buy anyway' : av === 'available' ? 'the game hides him (hidden wins for a free hero)' : 'availability hidden hides him'}.` }));
    wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: `Make hidden agree (hidden: ${av === 'hidden'})`, onclick: () => Assets.apply(doc, (dd) => { dd.hidden = av === 'hidden'; }, 'editor') }));
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
    for (const id of muts) { const m = fl ? fl.mutations.find((x) => x.id === id) : null; out.appendChild(line('mutation', id, 'hero mutation', m ? el('span', { class: 'muted small', text: `on ${m.weapon}${m.hidden ? ' · hidden: out of play (pass 69)' : m.weapon !== doc.data.favourite_weapon ? ' (not his favourite!)' : ''}` }) : null)); }
    if (!perks.length) out.appendChild(el('div', { class: 'muted small', text: 'No perks listed (content/perks with hero = this id; a hero on the title needs at least one: pass66_shape_test).' }));
    // pass 69 (lane LE): every perk opens in the perk form (Identity, Card, Special with its numbers, Art); + New perk
    const precs = Array.isArray(rec.perk_records) ? rec.perk_records : [];
    for (const id of perks) {
      const p = precs.find((x) => x.id === id) || { id };
      out.appendChild(el('div', { class: 'isub' }, el('img', { src: `/icon/perk/${id}`, alt: '', onerror: (e) => { e.target.style.visibility = 'hidden'; } }), el('span', { class: 'achip perk', text: 'perk' }), el('b', { text: p.name || id }),
        el('span', { class: 'muted small', text: `${id}${p.special ? ' · special ' + p.special : ' · effects only'}${p.hidden ? ' · hidden' : ''}`, title: p.text || '' }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Edit', onclick: () => Assets.open('perk', id) })));
    }
    const host = el('div', { class: 'acreate-host' });
    out.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: '+ New perk…', title: 'a new perk for this hero from any perk as a template (Inflatable May: the decoy)', onclick: () => { clear(host); host.appendChild(TypedForms.newPerkDialog(doc, host, () => {})); } })));
    out.appendChild(host);
    return out;
  }

  /** The round badge at 128 and 64 and the title cut-out (660x888 at a quarter; the title's stripes when missing). */
  function previews(doc) {
    const wrap = el('div', { class: 'hprev' });
    wrap.appendChild(Assets.iconPreview(doc, { key: 'icon' }));
    // pass 70: the cut-out of the look shown (its own `title`, else the hero's hero_<id>.png), and its pickers
    const looks = Array.isArray(doc.looks) ? doc.looks : [];
    const shown = looks.find((l) => l.code === doc.ui.look) || looks.find((l) => l.code === (doc.data.variant || doc.data.variant_base)) || null;
    const cutFile = shown && shown.title_file ? shown.title_file : `hero_${doc.id}.png`;
    const url = `/art/wanted/${encodeURIComponent(cutFile)}?v=${doc.baseMtime || 0}`;
    let cut;
    if (typeof CutoutPreview === 'function') { try { cut = CutoutPreview(url); } catch (_) { cut = null; } }
    if (!cut) {
      const img = el('img', { src: url, alt: '', onerror: (e) => { e.target.remove(); } });
      cut = el('div', { class: 'cutout', title: 'the title cut-out (game/art/ui/wanted/hero_<id>.png, 660x888) at a quarter; stripes = the title\'s placeholder' + (typeof LookGrid !== 'undefined' && LookGrid.WHERE_SHOWN ? ' · ' + LookGrid.WHERE_SHOWN.cutout : '') }, img,
        el('button', { class: 'btn small zoom', type: 'button', text: '⤢', title: 'at 1:1', onclick: () => {
          const box = el('div', { class: 'amodal-back' });
          box.appendChild(el('div', { class: 'amodal wide' }, el('h3', { text: `${cutFile} at 1:1 (660 × 888)` }), el('img', { src: url, alt: '', style: 'max-width:100%;display:block;background:repeating-linear-gradient(45deg,#3a3429 0 8px,#2a2520 8px 16px)' }), el('div', { class: 'amodal-actions' }, el('button', { class: 'btn', type: 'button', text: 'Close', onclick: () => box.remove() }))));
          box.addEventListener('click', (e) => { if (e.target === box) box.remove(); });
          document.body.appendChild(box);
        } }));
    }
    wrap.appendChild(el('div', { class: 'cutout-wrap' }, el('div', { class: 'muted small', text: `Title cut-out${shown ? ' of ' + shown.code : ''}${shown && shown.title_file ? ' (its own)' : ''}` }), cut, el('button', { class: 'btn small', type: 'button', text: '+ Title cut-out candidates…', onclick: () => Assets.openJobForm(doc, { method: 'hero_title', mode: 'title', code: shown && !shown.base ? shown.code : undefined }) })));
    if (shown && typeof LookGrid !== 'undefined' && typeof LookGrid.pickers === 'function' && !LookGrid.isStub(shown)) {
      const pk = LookGrid.pickers('hero', doc.id, shown);
      pk.classList.add('hprev-pickers');
      wrap.appendChild(pk);
    }
    return wrap;
  }

  return { render, redraw, card };
})();
