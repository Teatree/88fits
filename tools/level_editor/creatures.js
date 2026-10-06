// The Creatures tab (pass 53, pass 54): the palette. A card per creature with its numbers, its art variants, its badges
// and its doc line, a filter box, and buttons that start a wave or a roster row with it. The creature data lives in the
// creature's own JSON; pass 54 lets one thing be set from here: the default look (a variant figure's "Set as default
// look" writes the JSON's top-level `variant` through the server, after a backup, and imports that creature).
'use strict';

const Creatures = (() => {
  const { el, clear, fmtN } = U;
  let filter = '';
  let showRetired = true;
  const picked = {};          // creature id -> the variant code whose figure is selected
  let confirming = null;      // {id, code} while the inline "are you sure" shows
  let busy = null;            // the creature id a request is running for

  function render(container) {
    clear(container);
    const bar = el('div', { class: 'palette-bar' });
    const box = el('input', { type: 'search', class: 'txt wide', placeholder: 'filter by name, id, archetype or brain…', value: filter });
    box.addEventListener('input', () => { filter = box.value.trim().toLowerCase(); draw(); });
    const cb = el('input', { type: 'checkbox' }); cb.checked = showRetired;
    cb.addEventListener('change', () => { showRetired = cb.checked; draw(); });
    bar.appendChild(box);
    bar.appendChild(el('label', { class: 'cb' }, cb, el('span', { text: 'show retired and hidden' })));
    const count = el('span', { class: 'muted' });
    bar.appendChild(count);
    bar.appendChild(el('span', { class: 'muted small', text: 'Click a variant to set it as the creature\'s default look (the look in play wherever a row names no variant).' }));
    container.appendChild(bar);
    const grid = el('div', { class: 'palette' });
    container.appendChild(grid);
    draw();

    function draw() {
      clear(grid);
      const rosterIds = new Set((App.tl().roster || []).map((r) => r.enemy));
      const list = App.S.enemies.filter((c) => {
        if (!showRetired && (c.retired || c.hidden)) return false;
        if (!filter) return true;
        return [c.name, c.id, c.archetype, c.brain, c.kind].some((s) => String(s).toLowerCase().includes(filter));
      });
      const order = { enemy: 0, boss: 2 };
      list.sort((a, b) => (a.archetype === 'elite') - (b.archetype === 'elite') || order[a.kind] - order[b.kind] || (a.retired || a.hidden) - (b.retired || b.hidden) || a.name.localeCompare(b.name));
      count.textContent = `${list.length} of ${App.S.enemies.length}`;
      for (const c of list) grid.appendChild(card(c, rosterIds.has(c.id), () => draw()));
    }
  }

  function card(c, onRoster, redraw) {
    const tags = [];
    if (c.kind === 'boss') tags.push('boss');
    if (c.archetype === 'elite') tags.push('elite');
    if (c.max_alive === 1 && c.kind === 'enemy' && c.archetype !== 'elite') tags.push('special');
    if (c.retired) tags.push('retired');
    if (c.hidden) tags.push('hidden');
    if (!c.can_be_elite) tags.push('never coloured');
    if (onRoster) tags.push('on the roster');
    const drops = [];
    const d = c.drops || {};
    for (const k of ['small', 'medium', 'large']) if (d[k]) drops.push(`${k[0]} ${fmtN(d[k])}`);
    if (d.gold) drops.push(`coin ${pct(d.gold)}`);
    if (d.chest) drops.push(`chest ${pct(d.chest)}`);
    if (d.chests) drops.push(`${d.chests} chests`);
    if (d.coins) drops.push(`${d.coins} coins`);
    if (d.pickup && d.pickup.id) drops.push(`${App.pickup(d.pickup.id) ? App.pickup(d.pickup.id).name : d.pickup.id} ${pct(d.pickup.chance)}`);
    const el2 = el('article', { class: 'ccard' + (c.retired || c.hidden ? ' dim' : ''), 'data-id': c.id });
    el2.appendChild(el('div', { class: 'ccard-top' },
      el('img', { class: 'ccard-icon', src: c.icon_play || c.icon, alt: '', width: 72, height: 72, title: c.play ? `the look in play: ${c.play}` : '' }),
      el('div', { class: 'ccard-id' },
        el('h3', { text: c.name }),
        el('div', { class: 'muted small', text: `${c.id} · ${c.archetype} / ${c.brain}${c.play ? ' · plays ' + c.play : ''}` }),
        el('div', { class: 'tags' }, tags.map((t) => el('span', { class: 'tag ' + t.replace(/ /g, '-'), text: t }))))));
    const stats = el('dl', { class: 'cstats' });
    const stat = (k, v, title) => { stats.appendChild(el('dt', { text: k, title: title || '' })); stats.appendChild(el('dd', { text: v, title: title || '' })); };
    stat('HP', fmtN(c.hp)); stat('bite', fmtN(c.damage)); stat('speed', `${fmtN(c.speed)} m/s`); stat('size', `${fmtN(c.size)} m`);
    stat('pack', String(c.pack_size)); stat('cap', `${fmtN(c.cap_share)} slot`); stat('XP ×', fmtN(c.xp_mult));
    const kb = Model.knockbackOf(c, null);
    stat('knock', `${fmtN(kb.value, 2)} m/s${kb.from === 'default' ? ' (default)' : ''}`, kb.from === 'default' ? 'no knockback in its JSON: the game\'s default from its damage, clamp(3.4 × √(damage / 4), 2.5, 7)' : 'the bite\'s shove on the hero (its JSON\'s knockback)');
    if (c.damage_reduction) stat('DR', `${Math.round(c.damage_reduction * 100)}%`);
    if (c.max_alive) stat('max alive', String(c.max_alive));
    if (c.ranged) stat('ranged', `every ${fmtN(c.ranged.cooldown)} s, ${fmtN(c.ranged.range)} m`);
    if (c.charge) stat('charge', `${fmtN(c.charge.speed)} m/s every ${fmtN(c.charge.cooldown)} s`);
    if (c.boss) stat('attacks', [...new Set(c.boss.attacks)].join(', '));
    stat('drops', drops.join(' · ') || '—');
    el2.appendChild(stats);
    const vr = c.variance || {};
    if ((Array.isArray(vr.tints) && vr.tints.length) || vr.special_chance) {
      const sp = vr.special || {};
      el2.appendChild(el('div', { class: 'cvariance' },
        el('span', { class: 'muted small', text: 'tints' }),
        (vr.tints || []).map((h) => el('span', { class: 'sw-chip', style: `background:${h}`, title: `${h} at ${fmtN(vr.tint_strength == null ? 0 : vr.tint_strength, 2)}` })),
        vr.special_chance ? el('span', { class: 'muted small', text: ` · special ${Math.round(Number(vr.special_chance) * 100)}%` }) : null,
        sp.tint ? el('span', { class: 'sw-chip big', style: `background:${sp.tint}`, title: `the special's colour ${sp.tint}: HP ×${sp.hp || 1.6}, damage ×${sp.damage || 1.2}, size ×${sp.size || 1.3}, XP ×${sp.xp || 2}` }) : null));
    }
    if (c.variants.length) el2.appendChild(variantsRow(c, redraw));
    if (c.doc) el2.appendChild(el('p', { class: 'doc', text: c.doc }));
    el2.appendChild(el('div', { class: 'ccard-actions' },
      el('button', { class: 'btn small', type: 'button', text: '+ wave', title: 'a new wave of this creature at the view\'s centre', onclick: () => { App.switchTab('timeline'); App.newWave(c.id, null); App.select(App.S.sel, { scroll: true }); } }),
      el('button', { class: 'btn small', type: 'button', text: '+ roster row', title: 'a new roster row of this creature at the view\'s centre', onclick: () => { App.switchTab('timeline'); App.newRow(c.id, null); App.select(App.S.sel, { scroll: true }); } })));
    return el2;
  }

  /** The art variants as figures: the one in play ringed and dotted; a click selects one, and a selected (or hovered)
   *  figure that is not in play offers "Set as default look", confirmed inline before anything is written. */
  function variantsRow(c, redraw) {
    const wrap = el('div', { class: 'variants-wrap' });
    const vs = el('div', { class: 'variants' });
    for (const v of c.variants) {
      const inPlay = v.code === c.play;
      const isSel = picked[c.id] === v.code;
      const fig = el('figure', { class: 'variant' + (inPlay ? ' in-play' : '') + (isSel ? ' picked' : '') + (v.ready ? '' : ' not-ready'), title: `${v.code}${v.note ? ': ' + v.note : ''}${inPlay ? ' (in play)' : ''}${v.ready ? '' : ' (not painted yet: the game would play the base strip)'}`, tabindex: 0 },
        el('img', { src: v.icon, alt: '', width: 40, height: 40, onerror: (e) => { e.target.src = c.icon; } }),
        el('figcaption', { text: v.code + (inPlay ? ' ●' : '') }));
      if (!inPlay) {
        fig.appendChild(el('button', { class: 'set-default', type: 'button', text: 'Set as default look', disabled: !v.ready || busy === c.id, title: v.ready ? `make ${v.code} the look in play` : 'not painted yet',
          onclick: (e) => { e.stopPropagation(); picked[c.id] = v.code; confirming = { id: c.id, code: v.code }; redraw(); } }));
      }
      const pick = () => { picked[c.id] = isSel ? undefined : v.code; if (confirming && confirming.id === c.id) confirming = null; redraw(); };
      fig.addEventListener('click', pick);
      fig.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); } });
      vs.appendChild(fig);
    }
    wrap.appendChild(vs);
    if (confirming && confirming.id === c.id) {
      const code = confirming.code;
      wrap.appendChild(el('div', { class: 'confirm' },
        el('span', { text: `Make ${code} the default look of ${U.theName(c.name)}? This writes the top-level "variant" of ${c.id}.json (after a backup) and imports it; every row that names no variant plays it.` }),
        el('button', { class: 'btn small primary', type: 'button', text: busy === c.id ? 'Setting…' : `Yes, play ${code}`, disabled: busy === c.id, onclick: () => setDefault(c, code, redraw) }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', disabled: busy === c.id, onclick: () => { confirming = null; redraw(); } })));
    }
    return wrap;
  }

  async function setDefault(c, code, redraw) {
    busy = c.id;
    redraw();
    App.status(`Setting ${c.id}'s default look to ${code} and importing…`, 'busy');
    try {
      const r = await fetch(`/api/enemy/${encodeURIComponent(c.id)}/variant`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ code }) });
      const res = await r.json();
      if (!res.ok) throw new Error(res.error || `HTTP ${r.status}`);
      confirming = null;
      picked[c.id] = undefined;
      busy = null;
      await App.refreshCreatures();
      if (res.import_ok) App.status(`${c.name} now plays ${code} (was ${res.was || 'its base'}) · ${res.wrote} · import OK · backup ${String(res.backup).split('/').pop()}`, 'good', res.output);
      else App.status(`${c.name} now plays ${code} in its JSON · IMPORT FAILED (the game still plays the old .tres)`, 'bad', res.output);
      App.toast(`${c.name}: ${code} is the look in play`);
      return;   // refreshCreatures drew the tab again with the new look ringed
    } catch (e) {
      busy = null;
      App.status(`Could not set ${c.id}'s look: ${e.message}`, 'bad');
    }
    if (App.S.tab === 'creatures') redraw();
  }

  function pct(v) { const p = Number(v) * 100; return (p >= 10 ? Math.round(p) : p >= 1 ? p.toFixed(1) : p.toFixed(2)) + '%'; }

  return { render };
})();
