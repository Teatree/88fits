// The Settings tab (pass 53, pass 54): every scalar of the timeline in a form with its one-line help, the arrays as small
// lists, then the pickups, specials, structures and portal wave blocks. Keys the editor does not know are shown read-only
// and ride along unchanged. Pass 54: the spawn sides as one compass block, the HP x / ATK x curves with their mode switch,
// creature_damage_mult beside creature_hp_mult, hp_growth / hp_power marked legacy.
'use strict';

const Settings = (() => {
  const { el, clear, fmtT } = U;

  const KNOWN = new Set(['roster', 'waves', 'events', 'pickups', 'specials', 'structures', 'portal_wave', 'cap_curve', 'path_times']);
  for (const d of FIELDS.SCALARS) KNOWN.add(d.key.split('.')[0]);

  function render(container) {
    Forms.closePop();
    const active = container.contains(document.activeElement) ? document.activeElement.dataset.path : null;
    const scroll = container.scrollTop;
    clear(container);
    const tl = App.tl();
    const page = el('div', { class: 'settings' });
    page.appendChild(el('p', { class: 'lead', text: 'The numbers behind the lanes. Every change is undoable (Ctrl+Z) and goes to the file with Save. Hover a label, or press its "?", for what the number does.' }));
    const grid = el('div', { class: 'settings-grid' });
    for (const group of FIELDS.SCALAR_GROUPS) {
      const card = el('section', { class: 'card' + (group === 'Scaling' ? ' tall' : '') }, el('h2', { text: group }));
      const blocks = new Set();
      for (const def of FIELDS.SCALARS.filter((d) => d.group === group)) {
        if (def.block) {
          // a block of several keys drawn as one control (the spawn sides' compass)
          if (blocks.has(def.block)) continue;
          blocks.add(def.block);
          if (def.block === 'spawn_sides') card.appendChild(el('div', { class: 'block-row' }, el('h3', { class: 'block-title', text: 'Spawn sides' }), Forms.spawnSidesBlock(tl)));
          continue;
        }
        if (def.type === 'points') { card.appendChild(Forms.row(def, Forms.pointsBlock(tl))); continue; }
        if (def.type === 'path_times') { card.appendChild(Forms.row(def, Forms.pathTimesBlock(tl))); continue; }
        if (def.type === 'curve') { card.appendChild(Forms.row(def, Forms.curveBlock(tl, def.key), { cls: 'wide-ctl' })); continue; }
        card.appendChild(Forms.fieldRow(def, tl, { labels: def.type === 'list' ? (i) => `stage ${i + 1}` : undefined }));
      }
      if (group === 'Stages') card.appendChild(el('p', { class: 'muted small', text: `Stage 1 ${fmtT(0)}–${fmtT(App.stageLength())}, stage 2 to ${fmtT(App.stageLength() * 2)}, stage 3 to ${fmtT(App.stageLength() * 3)}; the run clock stands still through boss fights and portals.` }));
      // pass 69 (lane EN)
      if (group === 'Coloured specials') card.appendChild(el('p', { class: 'muted small', text: 'The numbers of a coloured special (the rarer, bigger, tougher, glowing one) wherever a creature\'s own Special block (Enemies tab) leaves a box empty; a creature\'s own number always wins, an empty box here is the game\'s default (the grey number). Every creature names its own size, HP and ATK; none names a glow, so Glow here sets all of them.' }));
      // pass 72 (lane BOSS): the references, the chart and the thinking under the Boss HP card's five rows
      if (group === 'Boss HP' && typeof BossScaling !== 'undefined') card.appendChild(BossScaling.block(tl));
      if (group === 'Scaling') card.appendChild(el('p', { class: 'muted small', text: 'An ordinary creature spawns with HP = its hp × the stage multiplier × the HP curve at that second × the hero-level factor × creature_hp_mult, and bites for its damage × the stage multiplier × the damage curve × the hero-level factor × creature_damage_mult. The hover cards on the Timeline show both for any second.' }));
      grid.appendChild(card);
    }
    grid.appendChild(el('section', { class: 'card' }, el('h2', { text: 'Power-up drops' }), el('p', { class: 'muted small', text: 'What kills drop and how often; the harder the creature (its xp_mult) the likelier a drop and the more the hard_bias counts.' }), Forms.pickupsBlock(tl)));
    grid.appendChild(el('section', { class: 'card' }, el('h2', { text: 'Specials' }), el('p', { class: 'muted small', text: 'The Vulture Raider, the Saiga Sniper and the harpooner: not roster creatures but a clock of their own; one comes at a time, drawn evenly from the rows whose stage has come.' }), Forms.specialsBlock(tl)));
    const other = Object.keys(tl).filter((k) => !KNOWN.has(k));
    if (other.length) {
      const o = {};
      for (const k of other) o[k] = tl[k];
      grid.appendChild(el('section', { class: 'card' }, el('h2', { text: 'Other keys (kept as they are)' }), el('p', { class: 'muted small', text: 'The editor does not know these; they are written back unchanged.' }), el('pre', { class: 'json', text: JSON.stringify(o, null, 2) })));
    }
    page.appendChild(grid);
    container.appendChild(page);
    container.scrollTop = scroll;
    if (active) { const again = container.querySelector(`[data-path="${CSS.escape(active)}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  return { render };
})();
