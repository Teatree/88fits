'use strict';
// Pass 112 (lane BARREL): the Settings tab's Barrels card. The respawn rows (barrels.respawn.*) are plain field rows drawn
// by settings.js from fields.js; this draws the line under them (about how many come back a stage) and the block of what
// each barrel kind holds (barrels.brown / barrels.black: the power-up chance, which power-up with its weights and shares,
// the throw distance, the gems and the coins). The maths: barrel_model.js.
const BarrelCard = (() => {
  const { el, fmtT } = U;

  /** One line: about how many barrels can come back a stage, or that none do. */
  function summary(tl) {
    const c = BarrelModel.respawnOf(tl.barrels);
    if (!c.enabled) return `Broken barrels do not come back: the map has only its ${BarrelModel.START_COUNT} start barrels (${mix(tl)}).`;
    const per = App.stageList().map((w) => `${w.name} ${BarrelModel.turnsIn(c, w.length)}`);
    const every = c.every[0] === c.every[1] ? `${c.every[0]} s` : `${c.every[0]} to ${c.every[1]} s`;
    return `At most ${per.join(', ')} barrels come back in a stage's own time (the first at ${fmtT(c.first)}, then one every ${every})${c.in_boss ? ', and more while the boss fight lasts' : ''}; ${c.max_lying ? `only while fewer than ${c.max_lying} stand (${c.max_lying === BarrelModel.START_COUNT ? 'the start\'s count: only smashed ones come back' : `the start has ${BarrelModel.START_COUNT}`})` : 'with no limit on how many stand'}. Kinds: ${mix(tl)}.`;
  }

  /** The kinds' shares in words (pass 116). */
  function mix(tl) {
    const sh = BarrelModel.kindShares(tl.barrels);
    return BarrelModel.TYPES.map((t, k) => `${BarrelModel.NAMES[t]} ${Math.round(sh[k] * 100)}%`).join(', ');
  }

  /** The two barrel kinds' contents (the rows with block 'barrel_contents'). */
  function block(tl) {
    const wrap = el('div', { class: 'block-form barrel-card' });
    wrap.appendChild(el('h3', { class: 'block-title', text: 'What a barrel holds' }));
    wrap.appendChild(el('p', { class: 'muted small', text: 'Three kinds (pass 116, Garry\'s board). The EXP barrel bursts into gems, the EXP + Coins barrel into gems and coins, the Power-up barrel only throws out a power-up that lands a few metres away (the player chooses whether to walk over for it). Weight = each kind\'s share of the barrels, at the start and when they come back.' }));
    for (const ty of BarrelModel.TYPES) wrap.appendChild(typeBlock(tl, ty));
    return wrap;
  }

  function typeBlock(tl, ty) {
    const box = el('div', { class: 'barrel-type', style: 'margin:8px 0 12px;padding-top:6px;border-top:1px solid var(--line, #3334)' });
    box.appendChild(el('h4', { text: `${BarrelModel.NAMES[ty]} (${Math.round(BarrelModel.kindShares(tl.barrels)[BarrelModel.TYPES.indexOf(ty)] * 100)}% of barrels)`, style: 'margin:4px 0 6px' }));
    for (const def of FIELDS.SCALARS.filter((d) => d.block === 'barrel_contents' && d.key.startsWith(`barrels.${ty}.`))) {
      const bare = def.label.replace(/^(EXP \+ Coins|EXP|Power-up) barrel: /, '');
      const short = Object.assign({}, def, { label: bare.charAt(0).toUpperCase() + bare.slice(1) });
      // the list takes the card's whole width (the power-ups' names are cut short beside the label)
      if (def.type === 'barrel_powerups') { box.appendChild(Forms.row(short, powerupsTable(tl, ty), { cls: 'wide-ctl' })); continue; }
      box.appendChild(Forms.fieldRow(short, tl));
    }
    return box;
  }

  /** Which power-up comes out: the kind's own list (power-up, weight with its share, ×), or, when it has none, the drops
   *  roster it falls back to, named with its shares, and a button that copies it in to edit. */
  function powerupsTable(tl, ty) {
    const name = (id) => { const p = (App.S.pickups || []).find((x) => x.id === id); return p ? p.name : id; };
    const own = U.getPath(tl, `barrels.${ty}.powerups`);
    const list = Array.isArray(own) ? own : [];
    const wrap = el('div', { class: 'barrel-pu' });
    if (!list.length) {
      const dl = BarrelModel.drawList(tl, ty);
      const sh = BarrelModel.shares(dl.list);
      wrap.appendChild(el('p', { class: 'muted small', text: dl.list.length ? `None listed: the Power-up drops mix (${dl.list.map((r, k) => `${name(r.id)} ${Math.round(sh[k] * 100)}%`).join(', ')}).` : 'None listed and no Power-up drops roster: nothing comes out.' }));
      wrap.appendChild(el('button', { class: 'btn small', type: 'button', text: dl.list.length ? 'Copy that mix here to edit' : '+ power-up', onclick: () => App.apply((d) => {
        const rows = dl.list.length ? dl.list.map((r) => ({ id: r.id, weight: r.weight })) : [{ id: 'heart', weight: 1 }];
        U.setPath(d, `barrels.${ty}.powerups`, rows);
      }) }));
      return wrap;
    }
    const sh = BarrelModel.shares(list);
    const tbl = el('div', { class: 'mini-table' }, el('div', { class: 'mini-head' }, el('span', { text: 'power-up' }), el('span', { text: 'weight' }), el('span')));
    list.forEach((r, k) => {
      const pre = `barrels.${ty}.powerups.${k}`;
      tbl.appendChild(el('div', { class: 'mini-row' },
        el('span', { class: 'cell-ico' }, Forms.control(FIELDS.PICKUP_ROW[0], r, { pathPrefix: pre, allPickups: true })),
        el('span', { class: 'with-hint' }, Forms.control(FIELDS.PICKUP_ROW[1], r, { pathPrefix: pre, cls: 'short' }), el('span', { class: 'hint', text: `${Math.round(sh[k] * 100)}%` })),
        el('button', { class: 'x', type: 'button', text: '×', title: 'remove (removing the last one goes back to the Power-up drops mix)', onclick: () => App.apply(() => { list.splice(k, 1); if (!list.length) U.setPath(tl, `barrels.${ty}.powerups`, null); }) })));
    });
    tbl.appendChild(el('button', { class: 'btn small', type: 'button', text: '+ power-up', onclick: () => App.apply(() => {
      const used = new Set(list.map((x) => x.id));
      const p = (App.S.pickups || []).find((x) => !x.small && !used.has(x.id)) || (App.S.pickups || [])[0];
      list.push({ id: p ? p.id : 'heart', weight: 1 });
    }) }));
    wrap.appendChild(tbl);
    return wrap;
  }

  return { summary, block, powerupsTable };
})();
