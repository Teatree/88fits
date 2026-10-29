'use strict';
// Pass 113, lane TASKS (Garry: "Add the following task types everywhere in the game where we have tasks ... Deal N Damage
// with Weapon - Weapon Picture; Restore N HP with Item - relevant picture; Restore N HP with (Heal Power-up, Structure) -
// Relevant Picture; Upgrade Item to N Level - Item Picture; Destroy N Barrels - barrel picture; Claim N Totems - (totem
// picture); Deal N Poison/Fire damage - Poison or Fire picture"): what the quest rows (the hero's Requirement, an item's
// quest lock, a skin's goal: AFIELDS.QUEST_ROWS) need beyond the plain controls:
//  - the picture under a condition (the "Picture" row each quest editor adds after QUEST_ROWS: row()), the same still the
//    game draws (AssetsModel.questPicture mirrors QuestTracker.picture_of; the Wanted posters' pictures);
//  - the pickers of the healing items (cards and passive items whose levels heal, read off /api/items) and of the heal
//    sources (the healing power-ups and structures, /api/wanted/sources: new in pass 113, the editor needs a restart to
//    serve it; until then every power-up is listed and the structures cannot be).
const TaskPics = (() => {
  const { el } = U;
  const ART = '/api/wanted/art/';
  const S = { sources: null, loading: false, failed: false, fallback: false };

  async function getJSON(url) { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`); return r.json(); }

  /** The heal sources: /api/wanted/sources (pickups and structures with their effect), else /api/pickups (no effect: every
   *  power-up that is not a small one, marked as such). */
  function load() {
    if (S.sources || S.loading) return;
    S.loading = true;
    getJSON('/api/wanted/sources').then((d) => {
      S.sources = { pickups: d.pickups || [], structures: d.structures || [] };
      S.loading = false;
      rerender();
    }).catch(() => getJSON('/api/pickups').then((list) => {
      S.sources = { pickups: (Array.isArray(list) ? list : []).filter((p) => !p.small).map((p) => Object.assign({ effect: '?' }, p)), structures: [] };
      S.fallback = true;
      S.loading = false;
      rerender();
    }).catch(() => { S.failed = true; S.loading = false; }));
  }
  function rerender() { if (typeof App !== 'undefined' && App.render && App.S && (App.S.tab === 'heroes' || App.S.tab === 'items' || App.S.tab === 'wanted')) App.render('tab'); }

  const healPickups = () => ((S.sources && S.sources.pickups) || []).filter((p) => p.effect === 'heal' || p.effect === '?').filter((p) => !p.small && !p.credit_stat && !p.hidden);
  const healStructures = () => ((S.sources && S.sources.structures) || []).filter((s) => !s.hidden && (s.effect === 'heal' || (s.effect === 'dice' && (!Array.isArray(s.outcomes) || s.outcomes.includes('heal')))));

  /** The id picker's options for the task kinds (Assets.idOptions hands them here): heal_item (an item id), heal_source (a
   *  "pickup:<id>" or "structure:<id>" value, or "pickup:" / "structure:" for any of the kind). `mk(list, kind)` is
   *  Assets' option maker. Null while the sources load. */
  function options(kind, mk) {
    const fl = typeof Assets !== 'undefined' ? Assets.flatItems() : null;
    if (kind === 'heal_item') {
      if (!fl) return null;
      const byId = {};
      for (const p of fl.passives) byId[p.id] = p;
      const heals = fl.passives.filter((p) => !p.evolves_from && (AssetsModel.passiveHeals(p) || (p.evolves_into && AssetsModel.passiveHeals(byId[p.evolves_into])) || (p.evolved && AssetsModel.passiveHeals(p.evolved))));
      return [{ group: 'Cards', options: mk(heals.filter((p) => p.line), 'passive') }, { group: 'Passive items', options: mk(heals.filter((p) => !p.line), 'passive') }];
    }
    load();
    if (!S.sources) return null;
    if (kind === 'heal_source') {
      const pk = mk(healPickups().map((p) => Object.assign({}, p, { icon: p.icon || `/icon/pickup/${encodeURIComponent(p.id)}` })), 'pickup').map((o) => Object.assign(o, { v: `pickup:${o.v}` }));
      if (S.fallback) pk.forEach((o) => { o.sub = `${o.sub} · restart the editor to list only the healing ones`; });
      const st = mk(healStructures(), 'structure').map((o) => Object.assign(o, { v: `structure:${o.v}` }));
      const any = [{ v: 'pickup:', label: 'any healing power-up', sub: 'pickup:' }, { v: 'structure:', label: 'any healing structure', sub: 'structure:' }];
      return [{ group: 'Power-ups', options: pk }, { group: 'Structures', options: st }, { group: 'Any of a kind', options: any }];
    }
    return [];
  }

  /** weapon | card | passive for an item id (the lists), '' when unknown. */
  function kindOf(id) {
    const fl = typeof Assets !== 'undefined' && Assets.flatItems ? Assets.flatItems() : null;
    if (!fl) return '';
    if (fl.weapons.some((w) => w.id === id) || (fl.evolutions || []).some((w) => w.id === id)) return 'weapon';
    const p = fl.passives.find((x) => x.id === id);
    if (!p) return '';
    return p.line || (p.evolves_from && fl.passives.some((x) => x.id === p.evolves_from && x.line)) ? 'card' : 'passive';
  }

  /** The URL of a still {kind, id, stage?} ('' when there is none), as the game's WPoster.still_texture picks it. */
  function urlOf(still) {
    const s = still || {};
    const id = String(s.id || '');
    const fl = typeof Assets !== 'undefined' && Assets.flatItems ? Assets.flatItems() : null;
    const enc = encodeURIComponent(id);
    switch (s.kind) {
      case 'weapon': {
        const w = fl && (fl.weapons.find((x) => x.id === id) || (fl.evolutions || []).find((x) => x.id === id));
        return w ? (w.icon_play || w.icon || `/icon/weapon/${enc}`) : `/icon/weapon/${enc}`;
      }
      case 'card': case 'passive': {
        const p = fl && fl.passives.find((x) => x.id === id);
        return p ? (p.icon_play || p.icon || `/icon/passive/${enc}`) : `/icon/passive/${enc}`;
      }
      case 'enemy': case 'boss': {
        const c = typeof App !== 'undefined' && App.creature ? App.creature(id) : null;
        return (c && (c.icon_play || c.icon)) || `/icon/enemy/${enc}`;
      }
      case 'hero': {
        const h = typeof Assets !== 'undefined' ? (Assets.S.lists.heroes || []).find((x) => x.id === id) : null;
        return (h && (h.icon_play || h.icon)) || `/icon/hero/${enc}`;
      }
      case 'pickup': return `/icon/pickup/${enc}`;
      case 'structure': return `/api/wanted/structure_icon/${enc}`;
      case 'stage': return `${ART}stages/${enc}_s${Math.trunc(Number(s.stage || 0)) + 1}.jpg`;
      case 'art': return ({ barrel: `${ART}wanted/barrel.png`, poison: `${ART}wanted/poison.png`, fire: `${ART}sources/fire.png`,
        chest: `${ART}wanted/chest_closed.png`, coin: `${ART}wanted/coin.png` })[id] || '';
      case 'badge': return `${ART}badges/${enc}.png`;
      default: return '';
    }
  }

  /** The "Picture" row the quest editors add under the condition (typed_forms requirement, items quest lock, skins goal):
   *  a Forms row whose control is node(). */
  function row(draft) {
    const def = { key: 'picture', label: 'Picture', help: 'what the game draws for this goal (the Wanted posters\' pictures: the weapon, the item, the Heart, the barrel, the Totem Pole, fire or poison); the Collection and the hero sheet show it beside the words' };
    return Forms.row(def, node((draft && draft.condition) || {}), {});
  }

  /** The picture of the condition `cond` beside a few words saying what it is. */
  function node(cond) {
    load();
    const still = AssetsModel.questPicture(cond || {}, kindOf);
    const url = urlOf(still);
    const box = el('span', { class: 'qpic', 'data-still': still.kind ? `${still.kind}:${still.id}` : '', style: 'display:inline-flex;align-items:center;gap:8px' });
    if (!url) {
      box.appendChild(el('span', { class: 'muted small', text: 'no picture: the goal names no single thing to draw (the words alone)' }));
      return box;
    }
    const img = el('img', { src: url, alt: '', class: 'qpic-img', width: 40, height: 40, style: `width:40px;height:40px;object-fit:${still.kind === 'stage' ? 'cover' : 'contain'};border:1px solid var(--line, #444);border-radius:4px;background:rgba(255,255,255,0.04)` });
    img.addEventListener('error', () => { img.replaceWith(el('span', { class: 'qpic-miss', text: '?', style: 'display:inline-block;width:40px;height:40px;line-height:40px;text-align:center;border:1px dashed var(--line, #444);border-radius:4px', title: `${url} did not load${still.kind === 'structure' || (still.kind === 'art' && still.id === 'fire') ? ' (restart the editor: the route is new in pass 113)' : ''}` })); });
    box.appendChild(img);
    box.appendChild(el('span', { class: 'muted small', text: `${still.kind}${still.id ? ': ' + still.id : ''}` }));
    return box;
  }

  // the sources early, so the pickers are full when a quest is opened
  if (typeof window !== 'undefined' && typeof fetch !== 'undefined') setTimeout(load, 0);

  return { load, options, kindOf, urlOf, node, row, S, healPickups, healStructures };
})();
if (typeof module !== 'undefined') module.exports = TaskPics;
