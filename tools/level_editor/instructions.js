// The Instructions tab (pass 53, pass 54): what the editor is, the model in one picture, every lane, field and override (read from
// fields.js, so these words and the forms never drift apart), a worked example with its block, its inspector values and
// the JSON it writes, how Save works, the two .cmd files, the keys, and the schema doc itself (docs/waves_schema.md via
// /api/schema) at the end. Garry asked for "an Instructions tab describing each tool with a simple example with graphics".
// Pass 57: the Ring and In front spawn patterns, with a picture of each. Pass 58: rows fixed from their start, the Actual
// lanes, the size and colour ranges, the default look strip and the blood colour, with a picture of "fixed from its start".
// Pass 61: snapping (the toggle, S, Alt, what snaps to what, the guide line).
'use strict';

const Instructions = (() => {
  const { el, svg, clear, markdown, fmtT } = U;

  // Garry's own example: "the next 20 enemies that will spawn in bursts of 5 every 2 second will be 50% chance that they
  // will all 20 be skeletons with 10 hp, 15 atk melee, and a 50% chance that all 20 will be goblins with 15 hp, 10 atk"
  const EXAMPLE = {
    id: 'w1', name: 'Opening skeletons', t: 0, until: 30, count: 20, burst: 5, every: 2.0, pattern: 'pack', respect_cap: true,
    alts: [
      { chance: 0.5, enemy: 'skeleton', stats: { hp: 10, damage: 15 } },
      { chance: 0.5, enemy: 'goblin', stats: { hp: 15, damage: 10 } },
    ],
  };

  function render(container) {
    clear(container);
    const root = el('div', { class: 'instr' });
    intro(root);
    pass66(root);
    pass61(root);
    pass58(root);
    pass54(root);
    pass57(root);
    picture(root);
    lanes(root);
    fields(root);
    example(root);
    saving(root);
    cmds(root);
    keys(root);
    schema(root);
    schemaAssets(root);
    container.appendChild(root);
  }

  const p = (text) => el('p', { html: text });
  const li = (text) => el('li', { html: text });
  const kbd = (k) => `<span class="kbd">${k}</span>`;

  // ------------------------------------------------------------------ what this is

  function intro(root) {
    const m = App.S.maps.find((x) => x.id === App.S.mapId);
    root.appendChild(el('h1', { text: 'How the Level Editor works' }));
    root.appendChild(p(`This page edits the <b>wave timeline</b> of one map: the <code>timeline_data</code> block of <code>${m ? m.file : 'game/content/maps/<map>/<map>.json'}</code>. The game's director (<code>WaveDirector</code>) reads that block and nothing else decides which creatures come when, how many, with what numbers. Everything else in the file (the scene, the music, the skins, the <code>weapon_grade</code> block that darkens the 3D weapons under this map's light) rides along untouched.`));
    root.appendChild(el('ul', {},
      li('<b>Every time is a second of the run clock</b>, shown as mm:ss. The clock runs only while the hero is in the open: it stands still through a boss fight and while the portal waits. Stage 2 starts at <code>stage_length</code>, stage 3 at twice it; after the last stage the run is endless.'),
      li('<b>Timeline</b> is the calendar: the cap (the ceiling), the HP × and ATK × curves, the roster (the stream) and its share band, the waves (scripted bursts), the events (bosses, Elites, swarms), the specials and the path offers, on one time axis. Hover for the readout of any second or the card of any item; click anything to edit it in the inspector on the right; drag to move it.'),
      li('<b>Settings</b> holds every number of the timeline in a form, each with a one-line help. <b>Creatures</b> is the palette: what every creature is made of, with a button that starts a wave or a row with it, its looks as pictures (a click on one, and a yes, makes it the creature\'s default look) and its blood colour (the death splash). <b>Instructions</b> is this page.'),
      li(`<b>Save</b> (${kbd('Ctrl+S')}) writes the JSON (after a backup) and runs the JSON → .tres import, so the next launch of the game from the editor binary plays it. The JSON is what goes into git. Errors (red) block the save; warnings (yellow) never do.`)));
    root.appendChild(p('The loop Garry asked for: look at the long map of the run, pick the snippets of time when creatures appear, set their count, their bursts, their numbers, their look, save, play, come back. Every change is one undo step.'));
  }

  // ------------------------------------------------------------------ what pass 54 added

  function pass54(root) {
    root.appendChild(el('h2', { text: 'Pass 54: what is new' }));
    root.appendChild(p('<b>The cap points.</b> The points on the Cap lane are the control points of the live cap curve (how many creatures may be alive): the line is linear between them and flat before the first and after the last. They are <b>not spawn events</b>: nothing spawns at a point. The director spawns up to the cap on its own interval (every <code>spawn_interval</code> seconds, a burst of <code>burst_min</code> to <code>burst_max</code> load units while there is room). Every point shows its cap as a faint number.'));
    root.appendChild(el('ul', {},
      li('<b>Presence keyframes</b> replace <code>weight</code> / <code>weight_late</code>: a roster row\'s <code>weights</code> is a list of <code>[time, weight]</code> points, linear between them, flat outside. The bar draws them as a filled area in the creature\'s colour; drag a point up or down (or along), double-click the bar to add one, double-click a point to remove it (a row keeps two). An old row is read as <code>[[t, weight], [weight_late_t, weight_late]]</code> on load and Save writes the new shape; <code>weight_late_t</code> stays in the file for old rows elsewhere.'),
      li('<b>Share</b>: a band under the Roster lane stacks each creature\'s share of the draw over time (normalised per channel), one colour per creature; the icons in its label are the legend.'),
      li('<b>Row order</b>: the grip, ▲ / ▼ at the left of each row (and in the inspector, and Alt+↑ / ↓) reorder the rows. Each row carries a stable <code>id</code> (r1, r2, …) so Save keeps its numbers. The order is for this page only: the game draws by weight.'),
      li('<b>Hover cards</b>: hover a roster bar, a wave block, an alternative\'s stripe, an event flag or the specials band for the creature\'s picture, its <b>HP and ATK at that second</b> (the game\'s formula: the stage, the HP / ATK curves, creature_hp_mult / creature_damage_mult and the hero level in the top bar\'s box), an orange dot before a number an override changed, <code>*</code> when other stats are overridden, and its share of the draw.'),
      li('<b>HP × and ATK ×</b>: two lanes under the Cap, each a curve over the run clock with a mode switch in the inspector: manual points (drag them) or a formula (linear <code>1 + a·m</code>, power <code>(1 + a·m)^b</code>, exponential <code>(1 + a)^m</code>, m = minutes). Switching to manual seeds the points from the formula at the stage marks; both are kept in the file (<code>hp_curve</code>, <code>damage_curve</code>). Without an <code>hp_curve</code> the legacy <code>hp_growth</code> / <code>hp_power</code> pair applies.'),
      li('<b>Creature pickers with pictures</b>: every creature, art variant, elite modifier and power-up choice is a list with icons (the look in play), a filter box and the keyboard (↑ ↓ Enter Esc). An empty art variant means the look in play, named in the box.'),
      li('<b>Elite overrides</b> are the variance block (size and speed spread, tints, the coloured special and its numbers) plus <code>elite_weight</code> (how often a random coloured elite is drawn from the row; 0 = never) and <code>elite_formats</code> (alone / as its pack / as a ring). The old <code>elite.hp_mult_per_stage</code> lives under <b>Mini-boss</b>: only Elite-archetype creatures read it.'),
      li('<b>Knockback</b> per creature (Body → Knockback; the grey number is its own, or <code>clamp(3.4 × √(damage / 4), 2.5, 7)</code>), <b>Knockback resist</b> (pass 67, the other direction: Body → Knockback resist on the Enemies tab and a row\'s Body override; the share of every shove from the hero\'s side the creature shrugs off, 0..1; the Hammer Giant 0.67 = a third of the push), <b>creature_damage_mult</b> (Settings → Scaling: every hostile damage) and the <b>spawn sides</b> (Settings → Spawning: top / bottom / left / right weights, or the old facing rule).'),
      li('<b>Default look</b>: on the Creatures tab (since pass 58 an always-visible strip of pictures on every card): click a look; after you confirm, the server writes that creature JSON\'s <code>variant</code> (after a backup) and imports it.')));
  }

  // ------------------------------------------------------------------ what pass 61 added

  function pass61(root) {
    root.appendChild(el('h2', { text: 'Pass 61: snapping' }));
    root.appendChild(p('Garry: <i>"Add togglable snapping for Roster, Cap and anywhere else it makes sense for start and end, so when I am placing an enemy wave or changing it\'s start or end time it snaps to Cap and other Enemy Waves (Cap prio)."</i>'));
    root.appendChild(el('ul', {},
      li(`<b>Snap on / Snap off</b>: the toggle at the left of the zoom buttons, or ${kbd('S')}. On by default; the browser remembers it (the map never sees it). Hold ${kbd('Alt')} while dragging to place that drag freely.`),
      li('<b>What snaps</b>, the time only: a roster bar or a wave block moved whole (its start or its end, whichever finds the better target), their end handles, an event flag, a presence point, a cap point, an HP × / ATK × point. Typed numbers, the arrow nudges and double-click-added points never snap.'),
      li('<b>What it snaps to</b>, within 8 pixels on screen at any zoom, the first of these in range: <b>1.</b> the cap curve\'s points (a cap point beats even a nearer row); <b>2.</b> the other rows\' and waves\' starts and ends; <b>3.</b> the events; <b>4.</b> the stage marks; <b>5.</b> only when none of those is near, whole and half minutes (from 4 px). Within one of these, the nearest. Nothing snaps to itself.'),
      li('<b>What you see</b>: a thin line across the lanes at the snapped second in the target\'s colour (cap points blue, rows pink, waves green, events their flag\'s colour), a tag "snapped to cap 6:03" / "snapped to r16 start" above the mouse, the target ringed, and the clock line at the right of the toolbar ending in the same words. The time saved is exactly the whole second shown.')));
  }

  // ------------------------------------------------------------------ what pass 58 added

  function pass58(root) {
    root.appendChild(el('h2', { text: 'Pass 58: a row keeps its numbers, Actual HP × / ATK ×, sizes, colours, looks and blood' }));
    root.appendChild(p('Garry: <i>"I don\'t actually want it to change for the same \'wave\' of enemies on the fly, because then it feels weird for the Player that shooting the same enemy with the same weapon suddenly doesn\'t kill it even though it was killing them just a 20 seconds ago."</i> So a row reads the HP × and ATK × curves <b>once, at its start</b>, and every creature it sends keeps those numbers. The stage multiplier still steps them up at a new stage (and each endless wave), and the hero level is the one at the row\'s first spawn.'));
    root.appendChild(el('ul', {},
      li('<b>A row\'s HP and Damage</b>: the green line under From / Until (in sight whether Overrides is open or not) says <code>Row HP · ATK, fixed from mm:ss</code>: the creature\'s own × the curves <i>at the row\'s start</i>, where each number comes from, and what a creature of it has in play there (× the stage, creature_hp_mult and the hero level). Drag the bar and it follows, with the grey numbers in Overrides → Body → HP and Damage and the Presence times. A number typed into HP or Damage takes no curve. A wave shows it under each creature (its own start), an event under its creature (the second it fires; an <b>Elites every</b> lists its first firings, each taking the curves at its own second), the specials the second each one comes. An Overrides block you open stays open.'),
      li('<b>An event joins a row</b> (the game\'s rule since lane WV\'s fix round): a swarm, a coloured elite, a firing of an Elites every, a special or a boss\'s brood of a creature that a roster row (or else a wave) is bringing at that second in the same look plays that row\'s HP and ATK, fixed from the row\'s start, for each of the two its own Overrides leave alone, so the same creature never comes with two different numbers at once. Its green line names the row it joins. An elite drawn from the rows comes with its row\'s numbers. <b>Endless</b>: every row and wave is fixed afresh at each endless wave, from the wave\'s start (the step comes with the WAVE banner); the lanes and the cards show it. <b>A long bar</b>: on a bar longer than three minutes whose HP curve has climbed more than 15% past its start by its last second, its green line says so in yellow (its creatures keep the start\'s numbers all the way): split the bar for a step up.'),
      li('<b>Actual HP ×</b> and <b>Actual ATK ×</b>, a lane above each curve, on its scale while the rows fit under it (higher multiples give the Actual lane its own, up to 1.5 times as tall, and a ▲ with the number marks anything past its top, so the curve you drag never shrinks): what the creatures spawning at each second really carry. Solid: the average of the rows and waves spawning round that second, each weighted by how many it spawns there (the Spawned so far estimate); dashed: the largest; dotted: the intended curve. A long row lags the curve, a row with its own HP sits wherever that puts it. Hover for the rows behind the numbers; the curve\'s inspector has the same as a table.'),
      li('<b>Size (m)</b> in Overrides → Body: one number as before, or <i>from</i> and <i>to</i>: every creature of the row rolls its own size in that range (instead of the variance\'s spread) and its body grows with it (radius × size / its own size) unless Radius is set. The creature\'s own size and spread show under the boxes; a range that runs backwards or a size of 0 is an error. A list of one size written by hand, <code>[2]</code>, is read as the game reads it: every creature exactly 2 m, no spread, its radius following.'),
      li('<b>Colour</b> (a new override group): a hue range on the colour wheel (two handles; an end below the start runs through red, ⇄ takes the other side), saturation, brightness and amount, and the creature\'s standing frame on the sand washed as the game washes it at five hues across the range. Every creature of the row rolls its own hue; it replaces the creature\'s own random tints from its first spawn. A coloured special of the row (once Colour after kills is reached) is a darker, stronger shade of the hue it rolled (saturation +0.15, brightness ×0.7, amount +0.15 over the larger of Amount and its own tint strength): the last picture, at the middle hue. An elite modifier, burn, poison and freeze still show over it. Click a picture to see it larger. A bright colour at a high amount reads pale in the game (it mixes in linear light): lower the brightness for deep colours.'),
      li('<b>Default look</b> on the Creatures tab: every card shows its looks as pictures, the default ringed and tagged; a click on another one asks, then writes the creature\'s <code>variant</code> (after a backup) and imports it. A row whose Art variant says <b>Default (CODE)</b> follows it; a code picked there pins the row. New rows, waves and events name no look.'),
      li('<b>Blood</b> on the Creatures tab: the colour of the creature\'s death splash, a picker and its hex; Save writes its <code>blood</code> (after a backup) and imports it.')));
    root.appendChild(el('div', { class: 'instr-pic' }, fixedPic()));
  }

  /** R1 in one picture: the intended HP × curve rising, two rows that each keep the curve of their own start, a row with
   *  its own HP flat above it, and the Actual average between them. A fixed drawing, no map data. */
  function fixedPic() {
    const W = 760, H = 230, X0 = 50, X1 = 720, Y0 = 190, Y1 = 52;
    const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H });
    const xt = (t) => X0 + (X1 - X0) * t / 1290, ym = (m) => Y0 - (Y0 - Y1) * (m - 0.8) / 3.4;
    const curve = (t) => Math.pow(1 + 0.0977 * t / 60, 1.25);
    s.appendChild(svg('line', { x1: X0, x2: X1, y1: Y0, y2: Y0, stroke: '#383835' }));
    for (const [t, lab] of [[0, '0:00'], [430, '7:10'], [860, '14:20'], [1290, '21:30']]) {
      s.appendChild(svg('line', { x1: xt(t), x2: xt(t), y1: Y0, y2: Y0 + 5, stroke: '#898781' }));
      s.appendChild(svg('text', { x: xt(t) - 12, y: Y0 + 18, class: 'pic-text', text: lab }));
    }
    let d = '';
    for (let t = 0; t <= 1290; t += 15) d += `${xt(t)},${ym(curve(t))} `;
    s.appendChild(svg('polyline', { points: d, fill: 'none', stroke: '#199e70', 'stroke-width': 1.6, 'stroke-dasharray': '1.5 3.5', 'stroke-linecap': 'round' }));
    s.appendChild(svg('text', { x: xt(1290) - 150, y: ym(curve(1290)) - 10, class: 'pic-text', text: 'the HP × curve (intended)' }));
    const row = (t0, t1, m, color, label) => {
      s.appendChild(svg('line', { x1: xt(t0), x2: xt(t1), y1: ym(m), y2: ym(m), stroke: color, 'stroke-width': 5, 'stroke-linecap': 'round', opacity: 0.85 }));
      s.appendChild(svg('circle', { cx: xt(t0), cy: ym(m), r: 4, fill: '#fff' }));
      s.appendChild(svg('text', { x: xt(t0) + 6, y: ym(m) - 9, class: 'pic-text', text: label }));
    };
    row(192, 700, curve(192), '#3987e5', 'a row from 3:12 keeps ×1.41');
    row(860, 1290, curve(860), '#d95926', 'a row from 14:20 keeps ×2.99');
    row(192, 430, 2.0, '#c98500', 'hp 20 over 10: ×2 (no curve)');
    s.appendChild(svg('text', { x: X0, y: 14, class: 'pic-text', text: 'every creature of a row has the row\'s numbers; the stage multiplier and the hero level come on top in the game' }));
    return s;
  }

  // ------------------------------------------------------------------ the two spawn patterns pass 57 added

  function pass57(root) {
    root.appendChild(el('h2', { text: 'Pass 57: the Ring and In front patterns' }));
    root.appendChild(p('Two more choices in a roster row\'s or a wave\'s <b>Pattern</b> (a swarm event takes In front too). The note under the field says what the choice will do with that row\'s numbers.'));
    root.appendChild(el('ul', {},
      li('<b>Ring</b>: the creatures of one spawn stand evenly round the hero on a ring <b>11.7 m</b> out (the debug arena\'s 9 m ring × 1.3; Garry: "about 30% further from the Player"), slid a little in and out so a full ring reads thick. A row\'s spawn is its pack, cut as always to what one burst holds and to the cap\'s room (at most 24 skeletons at once on Red Canyon: <code>burst_max</code> 12 load units, a skeleton takes 0.5); a wave\'s is its whole burst, at once. The note says how many of that creature make <i>a thick ring with few gaps</i>: the ring\'s 73.5 m over a body\'s width (2 × its radius) closes one row, and about 1.5 times that is a thick ring: about <b>105 skeletons</b> (70 close one row). A ring that big is a wave\'s job: Per burst about 105, Respect the cap off. The swarm event keeps its own 16 m ring (its note counts for 16 m).'),
      li('<b>In front</b>: every creature of the spawn comes from the top of the screen, each at its own point 19–24 m up within ±45° of straight up, <b>whatever Settings → Spawning → Spawn side says</b> (Garry: "an override to the Spawning part in the Settings"): a loose band across the top that walks down at the hero. The follow camera turns it with the screen.')));
    root.appendChild(el('div', { class: 'instr-pic' }, patternPic()));
  }

  /** The two patterns at one scale (6 px a metre): the screen at the run's zoom round the hero, a ring of 40 at 11.7 m,
   *  and a band of 14 in the top wedge 19-24 m out. A fixed jitter, so the picture never changes. */
  function patternPic() {
    const W = 760, H = 304, S = 6;
    const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H });
    const screen = (cx, cy, labelY) => {
      s.appendChild(svg('rect', { x: cx - 8 * S, y: cy - 17 * S, width: 16 * S, height: 28 * S, rx: 6, fill: 'none', stroke: '#898781', 'stroke-dasharray': '4 3' }));
      s.appendChild(svg('text', { x: cx - 8 * S + 5, y: labelY, class: 'pic-small', text: 'the screen' }));
      s.appendChild(svg('circle', { cx, cy, r: 5, fill: '#ffd166' }));
    };
    const dot = (x, y) => s.appendChild(svg('circle', { cx: x, cy: y, r: 3.2, fill: '#c3c2b7' }));
    const jit = (k) => Math.sin(k * 12.9898) * 0.5;      // a fixed -0.5..0.5 per index
    // the ring: 40 round the hero at 11.7 m, slid up to 0.2 of the spacing and 0.6 m in or out, as the game places them
    const rx = 190, ry = 162;
    screen(rx, ry, ry - 17 * S + 13);
    for (let k = 0; k < 40; k++) {
      const a = (k + jit(k) * 0.4) * Math.PI * 2 / 40;
      const r = (11.7 + jit(k + 99) * 1.2) * S;
      dot(rx + Math.cos(a) * r, ry + Math.sin(a) * r);
    }
    s.appendChild(svg('line', { x1: rx, y1: ry, x2: rx + 11.7 * S - 6, y2: ry, stroke: '#ffd166', 'stroke-width': 1 }));
    s.appendChild(svg('text', { x: rx + 20, y: ry - 7, class: 'pic-small', text: '11.7 m' }));
    s.appendChild(svg('text', { x: rx - 14, y: ry + 19, class: 'pic-small', text: 'hero' }));
    s.appendChild(svg('text', { x: 20, y: 22, class: 'pic-text strong', text: 'Ring: the whole spawn round the hero' }));
    s.appendChild(svg('text', { x: 20, y: H - 10, class: 'pic-small', text: 'a row: its pack · a wave: its burst · thick ≈ 1.5 × one closed row' }));
    // in front: 14 each at its own point in the top wedge, 19-24 m out, +-45 degrees of straight up
    const fx = 570, fy = 212;
    screen(fx, fy, fy + 11 * S - 6);
    for (const sgn of [-1, 1]) {
      const a = sgn * Math.PI / 4;
      s.appendChild(svg('line', { x1: fx, y1: fy, x2: fx + Math.sin(a) * 24 * S, y2: fy - Math.cos(a) * 24 * S, stroke: '#46d39a', 'stroke-dasharray': '3 3', opacity: 0.8 }));
    }
    for (let k = 0; k < 14; k++) {
      const a = (-0.9 + 1.8 * (k + 0.5 + jit(k * 3 + 1) * 0.8) / 14) * Math.PI / 4;
      const r = (21.5 + jit(k * 7 + 5) * 5) * S;
      dot(fx + Math.sin(a) * r, fy - Math.cos(a) * r);
    }
    s.appendChild(svg('text', { x: fx + 9, y: fy + 4, class: 'pic-small', text: 'hero' }));
    s.appendChild(svg('text', { x: 430, y: 22, class: 'pic-text strong', text: 'In front: from the top of the screen' }));
    s.appendChild(svg('text', { x: 430, y: H - 10, class: 'pic-small', text: '19–24 m up, ±45°, whatever the spawn side says' }));
    return s;
  }

  // ------------------------------------------------------------------ the model in one picture

  function picture(root) {
    root.appendChild(el('h2', { text: 'The model in one picture' }));
    root.appendChild(p('The <b>cap</b> is the ceiling: how many creatures may be alive. Whenever there is room under it, the director draws a burst from the <b>roster</b> rows open at that second, each row\'s share by its weight: that is the stream that fills the run. <b>Waves</b> are scripted bursts laid on top of the stream (into the cap\'s free room, or over it). <b>Events</b> are the flags: a boss stops the clock, an Elite arrives, a swarm lands round the hero.'));
    const W = 900, H = 348, X0 = 70, X1 = 860, AX = 262;
    const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H, class: 'model-pic' });
    const stages = [['Stage 1', '#1f3a5c'], ['Stage 2', '#4a2f1a'], ['Stage 3', '#4d1f1f']];
    const sw = (X1 - X0) / 3;
    stages.forEach(([name, col], k) => {
      s.appendChild(svg('rect', { x: X0 + k * sw, y: AX + 4, width: sw - 2, height: 18, fill: col, rx: 3 }));
      s.appendChild(svg('text', { x: X0 + k * sw + 6, y: AX + 17, class: 'pic-text', text: `${name}  ${k === 0 ? '0:00' : k === 1 ? '7:10' : '14:20'} →` }));
    });
    s.appendChild(svg('line', { x1: X0, x2: X1, y1: AX, y2: AX, stroke: '#c3c2b7' }));
    // the cap: a rising ceiling (the curve), the hard cap dashed above it; the flags sit in their own row above the curve
    const cap = (x) => { const f = (x - X0) / (X1 - X0); return AX - 30 - 118 * Math.min(1, f * 1.1); };
    s.appendChild(svg('line', { x1: X0, x2: X1, y1: 30, y2: 30, class: 'hard-cap' }));
    s.appendChild(svg('text', { x: X0 + 4, y: 26, class: 'hard-cap-text', text: 'hard cap: a count of bodies nothing crosses, swarms and no-cap waves included' }));
    // the roster: stacked areas under the ceiling, split by weight (rows arrive, weights slide)
    const rows = [
      { name: 'skeletons', color: '#2f4f7a', from: X0, w: (f) => 9 - 6 * f },
      { name: 'scorpions', color: '#3a6a4a', from: X0 + 60, w: (f) => 8 - 3 * f },
      { name: 'armadillos', color: '#6b4f2a', from: X0 + 190, w: (f) => 8 - 2 * f },
      { name: 'mummies', color: '#5a3a6a', from: X0 + sw, w: (f) => 3 + 2 * f },
      { name: 'hell channel', color: '#6a2a24', from: X0 + sw, w: (f) => 2 + 3 * f },
    ];
    const step = 10;
    const polys = rows.map(() => []);
    for (let x = X0; x <= X1; x += step) {
      const f = (x - X0) / (X1 - X0);
      const open = rows.map((r, i) => (x >= r.from ? r.w(f) : 0));
      const total = open.reduce((a, b) => a + b, 0) || 1;
      let y = AX;
      const top = cap(x);
      open.forEach((w, i) => {
        const h = (AX - top) * (w / total);
        polys[i].push([x, y, y - h]);
        y -= h;
      });
    }
    rows.forEach((r, i) => {
      const pts = polys[i];
      const d = pts.map(([x, y0]) => `${x},${y0}`).join(' ') + ' ' + pts.slice().reverse().map(([x, , y1]) => `${x},${y1}`).join(' ');
      s.appendChild(svg('polygon', { points: d, fill: r.color, opacity: 0.85 }));
      const mid = pts[Math.floor(pts.length * (i === 0 ? 0.12 : i === 1 ? 0.3 : i === 2 ? 0.48 : i === 3 ? 0.8 : 0.9))];
      if (mid && mid[1] - mid[2] > 14) s.appendChild(svg('text', { x: mid[0], y: (mid[1] + mid[2]) / 2 + 4, class: 'pic-small', fill: '#fff', text: r.name }));
    });
    let d = '';
    for (let x = X0; x <= X1; x += step) d += `${x},${cap(x)} `;
    s.appendChild(svg('polyline', { points: d, class: 'cap-line' }));
    s.appendChild(svg('text', { x: X0 + sw + 8, y: cap(X0 + sw + 8) - 10, class: 'pic-text strong', text: 'cap: the ceiling, how many may be alive' }));
    // waves: blocks on top of the stream
    const block = (x, w, label, nocap) => {
      const y = cap(x + w / 2) - 48;
      s.appendChild(svg('rect', { x, y, width: w, height: 34, rx: 4, class: 'block-body', stroke: nocap ? '#e66767' : '#4f8f6f' }));
      s.appendChild(svg('rect', { x: x + 3, y: y + 17, width: w - 6, height: 6, fill: '#3987e5', opacity: 0.7 }));
      s.appendChild(svg('rect', { x: x + 3, y: y + 25, width: w - 6, height: 6, fill: '#d95926', opacity: 0.7 }));
      s.appendChild(svg('text', { x: x + 5, y: y + 12, class: 'pic-small', fill: '#fff', text: label }));
    };
    block(X0 + 8, 120, 'wave: 20 in 5s every 2 s', false);
    block(X0 + sw + 120, 110, 'wave: no cap', true);
    s.appendChild(svg('text', { x: X0 + 8, y: cap(X0 + 68) - 56, class: 'pic-text strong', text: 'waves: scripted bursts on top of the stream, one alternative rolled per run' }));
    // events: flags in their own row (y 40..62), each with a drop line to the axis
    const flag = (x, glyph, color, label) => {
      s.appendChild(svg('line', { x1: x, x2: x, y1: 62, y2: AX, stroke: color, opacity: 0.55, 'stroke-dasharray': '3 2' }));
      s.appendChild(svg('rect', { x: x - 11, y: 40, width: 22, height: 22, rx: 5, class: 'marker-bg' }));
      s.appendChild(svg('use', { href: '#g-' + glyph, x: x - 8, y: 43, width: 16, height: 16, fill: color }));
      if (label) s.appendChild(svg('text', { x: x + 14, y: 55, class: 'pic-small', text: label }));
    };
    flag(X0 + sw * 0.5, 'crown', '#e6a04a', 'Elite');
    flag(X0 + sw, 'skull', '#e66767', 'boss');
    flag(X0 + sw * 1.72, 'ring', '#46d39a', 'swarm');
    flag(X0 + sw * 2, 'skull', '#e66767', 'boss');
    flag(X0 + sw * 2.45, 'crown', '#e6a04a', 'Elite');
    flag(X1 - 2, 'skull', '#e66767', '');
    s.appendChild(svg('line', { x1: X0 + sw * 0.7, x2: X1, y1: 82, y2: 82, class: 'repeat-line' }));
    s.appendChild(svg('use', { href: '#g-repeat', x: X0 + sw * 0.7 - 8, y: 74, width: 16, height: 16, fill: '#9085e9' }));
    s.appendChild(svg('text', { x: X0 + sw * 0.7 + 12, y: 86, class: 'pic-small', text: 'elite_every: a coloured elite every so many seconds, for the rest of the run' }));
    s.appendChild(svg('text', { x: X0, y: AX + 40, class: 'pic-text', text: 'roster: the stream under the ceiling. Each row runs from its start to its end; its share of every burst is its weight (its presence keyframes) against the other open rows.' }));
    s.appendChild(svg('text', { x: X0, y: AX + 58, class: 'pic-text', text: 'flags: a boss (skull) stops the clock and drops the crowd to its boss share · an Elite (crown) is a mini-boss near the hero · a swarm (ring) lands round the hero, over the cap.' }));
    s.appendChild(svg('text', { x: X0, y: AX + 76, class: 'pic-text', text: 'time → (seconds of the run clock, in mm:ss; it stands still through boss fights and portals)' }));
    root.appendChild(el('div', { class: 'instr-pic' }, s));
  }

  // ------------------------------------------------------------------ the lanes

  function lanes(root) {
    root.appendChild(el('h2', { text: 'The lanes of the Timeline tab' }));
    const list = el('div', { class: 'lanes-list' });
    for (const l of FIELDS.LANES) list.appendChild(el('div', { class: 'lane-card' }, el('b', { text: l.name }), l.text));
    root.appendChild(list);
    root.appendChild(p('Above the lanes the <b>ruler</b> shows the stages as coloured bands with their multipliers, mm:ss ticks, a skull for every boss and a crown for every Elite event. Under the mouse a dashed <b>cursor</b> and a <b>readout</b> tell what the director does at that second: the stage, the cap, the HP multiplier <code>HP curve × stage_mult × level × creature_hp_mult</code> and the damage multiplier <code>damage curve × stage_mult × level × creature_damage_mult</code> (level = 1 + level_hp_per_level × (hero level − 1), the hero level from the top bar\'s box), the roster rows open then with their normalised weights, the waves running and the next event. Over a bar, a block, a stripe, a flag or the specials band the readout gives way to that item\'s <b>hover card</b>. The same mm:ss, stage and cap stand in the top bar.'));
    root.appendChild(p('The hover card\'s numbers follow the game (EnemyManager.spawn, pass 58): an ordinary creature has <code>HP = row HP × stage_mult(t) × level × creature_hp_mult</code>, where <code>row HP = (hp × HP curve(t0), or the row\'s own hp) × hp_mult</code> and <code>t0</code> is the row\'s start: the curve is read once, at the start, and the row keeps that number (an <code>hp</code> override takes no curve); an Elite-archetype mini-boss <code>hp × elite.hp_mult_per_stage^stage × stage_mult × creature_hp_mult</code> (no curve, no level); a boss <code>hp × boss.hp_mult_per_stage^stage × stage_mult</code>. ATK is the same with <code>damage</code>, the damage curve at <code>t0</code> and <code>creature_damage_mult</code> (an Elite or a boss keeps the live damage curve). The level is the hero\'s level at the row\'s first spawn (the top bar\'s box stands in for it).'));
    root.appendChild(p(`Red <b>!</b> marks on a bar, block or marker are errors (the inspector says what), yellow ones warnings. With nothing selected the inspector lists every issue; click one to jump to it. The lanes zoom with ${kbd('+')} / ${kbd('−')} or ${kbd('Ctrl')} + wheel (at the mouse), "Fit" shows the whole run.`));
  }

  // ------------------------------------------------------------------ fields

  function typeName(def) {
    switch (def.type) {
      case 'seconds': return 'time (s or mm:ss)';
      case 'int': return 'whole number';
      case 'number': return 'number';
      case 'percent': return 'percent (stored 0..1)';
      case 'bool': return 'yes / no';
      case 'bool3': return 'unset / yes / no';
      case 'select': return def.options.map((o) => o.v).join(' | ');
      case 'enemy': return 'creature id';
      case 'enemies': return 'creature id, or a list with weights';
      case 'variant': return 'art variant code';
      case 'elite': return 'none | random | modifier id';
      case 'interval': return 'seconds, or [min, max]';
      case 'overrides': return 'stat overrides (below)';
      case 'alts': return 'list of alternatives (below)';
      case 'list': return 'list of numbers';
      case 'points': return '[[seconds, cap], …]';
      case 'weights': return '[[seconds, weight], …]';
      case 'curve': return '{mode, points, formula}';
      case 'swatch': return 'colour #RRGGBB';
      case 'swatches': return 'list of colours';
      case 'size_range': return 'metres, or [min, max]';
      case 'tint': return '{hue: [from, to], sat, val, amount}';
      case 'text': return 'text';
      case 'path_times': return 'one list of seconds per stage';
      case 'pickup': return 'power-up id';
      case 'pickup_weights': return 'power-up id → weight';
      case 'attacks': return 'attack name → on / off';
      default: return def.type;
    }
  }

  function fieldTable(defs, opts) {
    const o = opts || {};
    const t = el('table', { class: 'fieldtab' });
    t.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Field' }), el('th', { text: 'JSON key' }), el('th', { text: 'Type' }), el('th', { text: 'Default' }), el('th', { text: 'What it does' }))));
    const tb = el('tbody');
    for (const d of defs) {
      const def = d.def === undefined ? '' : (d.def !== null && typeof d.def === 'object' ? (Array.isArray(d.def) || Object.keys(d.def).length ? JSON.stringify(d.def) : 'absent') : String(d.def));
      const only = d.only ? ` (${d.only.map((k) => FIELDS.EVENT_TYPES[k].label).join(', ')} only)` : '';
      tb.appendChild(el('tr', {}, el('td', { class: 'name', text: d.label + (d.required ? ' *' : '') }), el('td', { class: 'key', text: (o.prefix || '') + (d.key || d.path) }), el('td', { text: typeName(d) }), el('td', { class: 'def', text: def || (d.ph ? 'the creature\'s own' : '') }), el('td', { class: 'help', text: d.help + only })));
    }
    t.appendChild(tb);
    return t;
  }

  function fields(root) {
    root.appendChild(el('h2', { text: 'Every field' }));
    root.appendChild(p('These tables come from the same table the forms are built from (<code>fields.js</code>), so what you read here is what the inspector offers. A field left empty is not written to the JSON: the game uses its default. Keys the editor does not know are kept as they are.'));
    root.appendChild(el('h3', { text: 'A roster row' }));
    root.appendChild(p('The stream. <code>"roster": [ { "id": "r1", "t": 0, "enemy": "skeleton", "weights": [[0, 9], [860, 3]] }, … ]</code>. A row with no <code>until</code> runs to the end of the run (the bar shows ∞). <code>weights</code> are the presence keyframes (pass 54); a file that still says <code>"weight": 9, "weight_late": 3</code> is read as <code>[[t, 9], [weight_late_t, 3]]</code> and saved in the new shape.'));
    root.appendChild(fieldTable(FIELDS.roster));
    root.appendChild(el('h3', { text: 'A wave' }));
    root.appendChild(p('A scripted window. From <code>t</code>, a burst of <code>burst</code> creatures every <code>every</code> seconds (the first at <code>t</code>) until <code>count</code> have come (0 = no total) or the clock reaches <code>until</code> (missing = no end). The block\'s length on the lane is <code>until</code>, or the time the count takes.'));
    root.appendChild(fieldTable(FIELDS.wave));
    root.appendChild(el('h3', { text: 'An alternative of a wave' }));
    root.appendChild(p('One of the alternatives is rolled <b>once per wave per run</b> by its chance (the chances are normalised, so 50 / 50 and 1 / 1 both mean half). A wave without alternatives carries one creature itself: the same fields on the wave.'));
    root.appendChild(fieldTable(FIELDS.alt, { prefix: 'alts[].' }));
    root.appendChild(el('h3', { text: 'An event' }));
    const et = el('table', { class: 'fieldtab' });
    et.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Type' }), el('th', { text: 'JSON' }), el('th', { text: 'What happens' }))));
    const etb = el('tbody');
    for (const [k, info] of Object.entries(FIELDS.EVENT_TYPES)) etb.appendChild(el('tr', {}, el('td', { class: 'name' }, U.glyph(info.glyph), ' ', info.label), el('td', { class: 'key', text: `"type": "${k}"` }), el('td', { class: 'help', text: info.help })));
    et.appendChild(etb);
    root.appendChild(et);
    root.appendChild(fieldTable(FIELDS.event));
    root.appendChild(el('h3', { text: 'Stat overrides (`stats`)' }));
    root.appendChild(p('A roster row, a wave\'s alternative and an event may each carry a <code>stats</code> block. Every key is optional; a missing key keeps the creature\'s own number. The inspector shows the creature\'s own value in grey as the placeholder of each box, so you see what you are overriding; a yellow label means the key is set. Multipliers (<code>*_mult</code>) stack on the base. <code>ranged</code>, <code>charge</code>, <code>drops</code>, <code>variance</code>, <code>elite</code> and <code>boss</code> are merged over the creature\'s block key by key (a <code>variance.tints</code> list replaces the whole list).'));
    for (const group of FIELDS.OVERRIDE_GROUPS) {
      const defs = FIELDS.OVERRIDES.filter((d) => d.group === group);
      root.appendChild(el('h3', { text: group, class: 'muted' }));
      if (FIELDS.OVERRIDE_GROUP_HELP[group]) root.appendChild(p(U.markdown(FIELDS.OVERRIDE_GROUP_HELP[group]).replace(/^<p>|<\/p>$/g, '')));
      root.appendChild(fieldTable(defs, { prefix: 'stats.' }));
    }
    root.appendChild(el('h3', { text: 'The timeline\'s own numbers (Settings)' }));
    for (const group of FIELDS.SCALAR_GROUPS) {
      root.appendChild(el('h3', { text: group, class: 'muted' }));
      root.appendChild(fieldTable(FIELDS.SCALARS.filter((d) => d.group === group)));
    }
    root.appendChild(el('h3', { text: 'A curve block (hp_curve, damage_curve)' }));
    root.appendChild(p('<code>{"mode": "formula", "formula": {"kind": "power", "a": 0.0977, "b": 1.25}, "points": [[0, 1], [430, 1.94], [860, 2.99], [1290, 4.11]]}</code>: the mode picks which part the game reads; the other is kept.'));
    root.appendChild(fieldTable(FIELDS.CURVE, { prefix: '<curve>.' }));
    root.appendChild(el('h3', { text: 'Specials and power-up drops' }));
    root.appendChild(p('<code>specials</code>: the Vulture Raider and the harpooner are not roster creatures but a clock of their own: from <code>from</code>, one at a time (<code>max_alive</code>), the next a random <code>interval</code> after the last one dies, drawn from the <code>pool</code> (a row with a <code>stage</code> waits for that stage). <code>pickups</code>: <code>per_kill</code> is the chance a kill drops a power-up (times the creature\'s <code>xp_mult</code>), the roster gives each power-up its weight and how much the harder creatures\' kills favour it (<code>hard_bias</code>).'));
    root.appendChild(fieldTable(FIELDS.SPECIALS, { prefix: 'specials.' }));
    root.appendChild(fieldTable(FIELDS.PICKUP_ROW, { prefix: 'pickups.roster[].' }));
  }

  // ------------------------------------------------------------------ a worked example

  function exampleBlock() {
    const W = 520, H = 120, X0 = 12, PPS = 7.5;          // 7.5 px a second: a minute across the picture
    const x = (t) => X0 + t * PPS;
    const s = svg('svg', { viewBox: `0 0 ${W} ${H}`, width: W, height: H });
    for (let t = 0; t <= 64; t += 10) {
      s.appendChild(svg('line', { x1: x(t), x2: x(t), y1: 6, y2: 14, class: t % 30 === 0 ? 'tick' : 'tick minor' }));
      if (t % 30 === 0) s.appendChild(svg('text', { x: x(t) + 3, y: 24, class: 'tick-text', text: fmtT(t) }));
    }
    const y0 = 34, h = 22 + 14 * EXAMPLE.alts.length;
    s.appendChild(svg('rect', { x: x(0), y: y0, width: x(EXAMPLE.until) - x(0), height: h, rx: 5, class: 'block-body' }));
    s.appendChild(svg('text', { x: x(0) + 6, y: y0 + 14, class: 'block-head', text: `${EXAMPLE.name} · ${EXAMPLE.count} in ${EXAMPLE.burst}s every ${EXAMPLE.every} s` }));
    EXAMPLE.alts.forEach((a, k) => {
      const sy = y0 + 20 + k * 14;
      const c = App.creature(a.enemy);
      s.appendChild(svg('rect', { x: x(0) + 2, y: sy, width: x(EXAMPLE.until) - x(0) - 4, height: 13, rx: 2, fill: Timeline.ALT_COLORS[k], opacity: 0.55 }));
      if (c) s.appendChild(svg('image', { href: c.icon, x: x(0) + 4, y: sy, width: 13, height: 13, preserveAspectRatio: 'xMidYMid meet' }));
      s.appendChild(svg('text', { x: x(0) + 20, y: sy + 10, class: 'stripe-text', text: `50% ${App.creatureName(a.enemy)}  hp ${a.stats.hp}, damage ${a.stats.damage}` }));
    });
    // the bursts the count needs: 4 of 5 at 0:00, 0:02, 0:04, 0:06
    for (let k = 0; k < Math.ceil(EXAMPLE.count / EXAMPLE.burst); k++) {
      const bx = x(k * EXAMPLE.every);
      s.appendChild(svg('line', { x1: bx, x2: bx, y1: y0 + h + 3, y2: y0 + h + 11, stroke: '#46d39a', 'stroke-width': 2 }));
    }
    s.appendChild(svg('text', { x: x(0), y: y0 + h + 24, class: 'pic-small', text: '4 bursts of 5 at 0:00, 0:02, 0:04, 0:06 → 20 came, the wave is done (its `until` 0:30 is only the backstop)' }));
    s.appendChild(svg('line', { x1: x(EXAMPLE.until), x2: x(EXAMPLE.until), y1: y0 - 4, y2: y0 + h + 4, class: 'handle', fill: 'none', stroke: '#ffd166', 'stroke-dasharray': '3 2' }));
    s.appendChild(svg('text', { x: x(EXAMPLE.until) + 4, y: y0 + h + 2, class: 'pic-small', text: 'until 0:30 (drag this edge)' }));
    return s;
  }

  function example(root) {
    root.appendChild(el('h2', { text: 'A worked example' }));
    root.appendChild(p('Garry\'s own words: <i>"the next 20 enemies that will spawn in bursts of 5 every 2 second will be 50% chance that they will all 20 be skeletons with 10 hp, 15 atk melee, and a 50% chance that all 20 will be goblins with 15 hp, 10 atk"</i>, for the first 30 seconds. As a wave:'));
    const grid = el('div', { class: 'example' });
    const left = el('div', { class: 'card' });
    left.appendChild(el('h3', { text: 'On the Waves lane' }));
    left.appendChild(el('div', { class: 'instr-pic' }, exampleBlock()));
    left.appendChild(el('ul', {},
      li('At 0:00 the first burst of 5 lands as a pack; at 0:02 the next, then 0:04 and 0:06: 20 in all, the count is reached and the wave is done. Had the cap been full, a burst would wait for room (<i>Respect the cap</i> is on).'),
      li('Before the first burst the game rolls the alternative <b>once</b>: this run all 20 are skeletons with 10 HP and a 15 bite; the next run maybe all goblins with 15 HP and a 10 bite. The stripes show both with their share.'),
      li('The two creatures\' own numbers (the skeleton\'s HP 10, the goblin\'s 15 by their JSON) are the grey placeholders in the inspector; the yellow labels are the keys this wave sets. The time multipliers of the run (the HP curve, the stage) still apply on top: hover a stripe for its HP and ATK at that second.')));
    left.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn', type: 'button', text: 'Add this wave to the map', title: 'puts the example on the Waves lane at 0:00, selected (Ctrl+Z takes it back)', onclick: addExample })));
    const right = el('div', { class: 'card' });
    right.appendChild(el('h3', { text: 'In the inspector' }));
    const kv = el('table', { class: 'kv' });
    const row = (k, v) => kv.appendChild(el('tr', {}, el('td', { text: k }), el('td', { html: v })));
    row('Name', 'Opening skeletons'); row('From', '0 (0:00)'); row('Until', '30 (0:30)'); row('Total count', '20'); row('Per burst', '5'); row('Every (s)', '2'); row('Pattern', 'pack'); row('Respect the cap', 'yes'); row('Channel', 'regular (default, not written)'); row('Elite modifier', 'none'); row('Banner', 'empty');
    row('Alternative 1', 'Chance 50 % · Creature Skeleton · Overrides: HP <b>10</b>, Damage <b>15</b>');
    row('Alternative 2', 'Chance 50 % · Creature Goblin · Overrides: HP <b>15</b>, Damage <b>10</b>');
    right.appendChild(kv);
    right.appendChild(el('h3', { text: 'The JSON Save writes (under "waves")' }));
    right.appendChild(el('pre', {}, el('code', { text: JSON.stringify(EXAMPLE, null, 2) })));
    grid.appendChild(left); grid.appendChild(right);
    root.appendChild(grid);
    root.appendChild(p('Variations: give an alternative an <i>Art variant</i> (SK-B) to change only the look; set <i>Elite modifier</i> to <code>random</code> so the whole wave comes coloured; untick <i>Respect the cap</i> and set a <i>Banner</i> "SWARM!" for a burst over the crowd; set <i>Total count</i> 0 and an <i>Until</i> for a window that keeps bursting until then. The same <code>stats</code> block goes on a roster row (every creature of that row) or an event (a boss with an attack switched off: <i>Boss → Attacks</i>).'));
  }

  function addExample() {
    if (!App.S.map) return;
    App.apply((d) => {
      if (!Array.isArray(d.waves)) d.waves = [];
      const used = new Set(d.waves.map((w) => w.id));
      const w = U.clone(EXAMPLE);
      let n = 1;
      while (used.has('w' + n)) n++;
      w.id = 'w' + n;
      d.waves.push(w);
      App.S.sel = { kind: 'wave', i: d.waves.length - 1 };
    }, 'none');
    App.switchTab('timeline');
    App.select(App.S.sel, { scroll: true });
    App.toast('Added the example wave at 0:00 (Ctrl+Z takes it back)');
  }

  // ------------------------------------------------------------------ saving, the .cmd files, keys, the schema

  function saving(root) {
    const m = App.S.maps.find((x) => x.id === App.S.mapId);
    root.appendChild(el('h2', { text: 'How saving works' }));
    root.appendChild(el('ol', {},
      li(`Save (${kbd('Ctrl+S')}) runs the checks first. An <b>error</b> (an unknown creature, a burst over the hard cap, an end before a start, …) blocks it: the inspector lists them when nothing is selected, the lanes mark them red. A <b>warning</b> (a wave that runs forever, an event inside a boss fight, a path offer outside its stage) never blocks.`),
      li(`The server copies the file as it is to <code>tools/level_editor/backups/${App.S.mapId || '<map>'}-&lt;date&gt;-&lt;time&gt;.json</code> (the last 30 are kept; the folder is not in git).`),
      li(`It writes <code>${m ? m.file : 'game/content/maps/<map>/<map>.json'}</code>: only the keys the schema names change, every other key stays as it was, in the file's own order, so a one-number change is a one-line diff in git. Numbers stay numbers (whole where the file had whole ones).`),
      li('It runs the import: <code>Godot --headless --path game --script res://tools/import_json.gd -- only=maps/' + (App.S.mapId || '<map>') + '</code>. The game plays the generated <code>.tres</code>, so a saved JSON without the import changes nothing in play. The status line says "import OK" or shows the import\'s output; click the line to unfold it. On a machine without the Godot binary the JSON is saved and the line says the import must be run by hand.'),
      li('The next launch of the game from the editor binary (or the next <code>ship</code>) plays the new timeline. Commit the JSON (and the .tres beside it) when you are happy; <b>Revert</b> takes the page back to the saved file, <b>Export JSON</b> downloads a copy without touching anything.')));
  }

  function cmds(root) {
    root.appendChild(el('h2', { text: 'The two .cmd files' }));
    root.appendChild(el('ul', {},
      li('<code>tools\\level_editor.cmd</code>: double-click it from anywhere. It finds Python (<code>python</code>, else <code>py -3</code>), starts this server from the repo root and opens the page in the default browser; the window stays open while the editor runs (close it or press Ctrl+C to stop; it waits for a key on an error). Options pass through: <code>level_editor.cmd --port 8800 --no-browser</code>.'),
      li('<code>tools\\ship.cmd</code>: runs the existing <code>tools/ship.sh</code> (the checks, the signed APK, the install on the phone and the copy to Google Drive) through Git Bash, with the arguments passed through: <code>ship.cmd --quick</code> skips the tests and the smoke run, <code>ship.cmd --no-install</code> leaves the phone alone. It looks for bash in <code>C:\\Program Files\\Git\\bin</code>, then <code>…\\Git\\usr\\bin</code>, then on PATH, and says so when none is found. The window waits for a key at the end so the result can be read.')));
  }

  function keys(root) {
    root.appendChild(el('h2', { text: 'Mouse and keyboard' }));
    const t = el('table', { class: 'fieldtab' });
    const rows = [
      ['Click a bar, block, marker, the cap line, the specials band or the paths lane', 'select it: the inspector shows its form'],
      ['Drag a bar, block or marker', 'move it in time (both ends of a row or a wave move together)'],
      ['Drag the right edge of a bar or block', 'set its `until` (an open row gets an end)'],
      ['Snap on / off (the toggle by the zoom) · ' + kbd('S') + ' · hold ' + kbd('Alt') + ' while dragging', 'dragged times drop onto the cap\'s points first, then the other rows\' and waves\' starts and ends, the events, the stage marks, whole and half minutes (within 8 px) · switch it · place this drag freely'],
      ['Drag a cap point · double-click the cap line · double-click a point', 'move it · add a point there · remove it (the HP × and ATK × lanes work the same in manual-points mode)'],
      ['Drag a presence point on a roster bar · double-click the bar · double-click a point', 'change the row\'s weight at that time (up / down) or its time (along) · add a point · remove it (two stay)'],
      ['The grip ⠿ or ▲ / ▼ at the left of a roster row · ' + kbd('Alt') + ' + ' + kbd('↑') + ' / ' + kbd('↓'), 'reorder the rows (display only: the game draws by weight)'],
      ['Hover the lanes', 'the cursor and the readout (time, stage, cap, HP × and ATK ×, the roster\'s shares, the waves running, the next event)'],
      ['Hover a bar, block, stripe, flag or the specials band', 'its card: the creature\'s picture, HP and ATK at that second (orange dot = changed by an override, * = other stats overridden) and its share'],
      ['Hero level (top bar)', 'the hero level the cards and the readout assume (creatures grow with it); never written to the map'],
      ['Creatures tab: click a variant · "Set as default look" · confirm', 'select it · ask to make it the look in play · the server writes the creature JSON and imports it'],
      ['A picker with pictures: type · ' + kbd('↑') + ' / ' + kbd('↓') + ' · ' + kbd('Enter') + ' · ' + kbd('Esc'), 'filter · move · choose · close'],
      [kbd('Ctrl') + ' + wheel · ' + kbd('+') + ' / ' + kbd('−') + ' · Fit', 'zoom at the mouse · zoom · the whole run'],
      [kbd('Ctrl+S'), 'save (write + import)'],
      [kbd('Ctrl+Z') + ' / ' + kbd('Ctrl+Y'), 'undo / redo (the whole timeline, every change one step)'],
      [kbd('Delete') + ' / ' + kbd('Backspace'), 'delete the selection (a toast offers Undo)'],
      [kbd('Ctrl+D'), 'duplicate the selection'],
      [kbd('←') + ' / ' + kbd('→') + ' (' + kbd('Shift') + ')', 'nudge the selection by 1 s (10 s)'],
      [kbd('Esc'), 'deselect; in a box, leave it'],
      [kbd('Enter') + ' in a box', 'apply the value (so does leaving the box)'],
      ['"?" beside a label', 'unfold what the field does (the same text sits in the tooltip)'],
      // pass 66: the asset tabs route the keys to their own document; the strip player has keys of its own
      [kbd('Ctrl+S') + ' on the Heroes or Items tab, or with an enemy open', 'saves THAT asset (its JSON written in place, then imported); the map\'s Save needs the Timeline or Settings tab'],
      [kbd('Ctrl+Z') + ' / ' + kbd('Ctrl+Y') + ' on an asset tab', 'undo / redo the open asset\'s document; the map\'s history stays its own'],
      ['A strip player: ' + kbd('Space') + ' · ' + kbd('←') + ' / ' + kbd('→') + ' · ⤢ · ' + kbd('Esc'), 'play / pause · one frame back / on · the close look (4× in a dialog) · close it. A look card plays while the mouse is over it; double-click it for the close look'],
    ];
    t.appendChild(el('tbody', {}, rows.map(([a, b]) => el('tr', {}, el('td', { class: 'name', html: a }), el('td', { class: 'help', text: b })))));
    root.appendChild(t);
  }

  function schema(root) {
    root.appendChild(el('h2', { text: 'The schema (docs/waves_schema.md)' }));
    root.appendChild(p('The contract between this editor and the game, as the repository holds it. The editor writes exactly these keys.'));
    root.appendChild(el('div', { class: 'schema-doc', html: App.S.schema ? markdown(App.S.schema) : '<p class="muted">loading…</p>' }));
  }

  // ------------------------------------------------------------------ pass 66: the asset editors, the looks, the art jobs, the Jobs tab (lane V)

  let demo = [];          // the strip players of this tab's demo, destroyed on the next render
  let assetsSchema = null; // docs/assets_schema.md as served, once fetched (null = not yet, '' = not served)

  function pass66(root) {
    for (const p of demo) p.destroy();
    demo = [];
    root.appendChild(el('h2', { text: 'Pass 66: the asset editors' }));
    root.appendChild(p('The editor now edits the <b>assets</b> themselves, not only when they come: <b>Enemies</b> (the palette, and an editor for every creature, elite and boss), <b>Heroes</b> and <b>Items</b> (weapons with their mutations and evolutions, lines with their evolved forms, passive items), each a form over the asset\'s own JSON under <code>game/content/</code>; plus <b>Jobs</b>: the local AI\'s queue that paints new looks, icons, badges and title cut-outs. Garry: "I go to our LevelEditor HTML and I choose to either edit or create an Enemy, Hero or Item ... Heroes and Items should get their own tabs with inclusion of everything we already have in the game at the proper status, stats, and everything that\'s true to what\'s in the game right now."'));
    root.appendChild(el('ul', {},
      li('<b>Two panes</b>: the list on the left (cards with the numbers, the status chips and an Edit button; "+ New from template" creates a real folder under <code>game/content/</code> at once, placeholders and all), the editor on the right with a sticky header (<i>KIND · Name · file · N changes</i>, <b>Save asset</b>, <b>Test in game</b>, ✕), the issues line and collapsible sections.'),
      li('<b>One document per asset</b>. A field edit is one undo step of that document; dirty documents stay open while you switch tabs. ' + kbd('Ctrl+S') + ', ' + kbd('Ctrl+Z') + ' and ' + kbd('Ctrl+Y') + ' go to the open asset on an asset tab and to the map on the Timeline and Settings tabs; leaving the page asks about both.'),
      li('<b>Save asset</b> writes the JSON <i>in place</i> (only the keys you changed, the file\'s own layout, a backup first) and imports it, like the map\'s Save. A file changed on disk since you opened it is refused with Reload / Keep mine / Show the other. A hand-edited, compact file the writer cannot edit line by line is refused rather than re-dumped.'),
      li('<b>Chips</b>: <i>available · hidden · locked by a quest · hero-only · stage N+</i> on items; <i>available · hidden · purchase</i> on heroes (availability, price and currency are written and shown, not wired: a purchase hero stays hidden in play until the loop is built); <i>retired · hidden · elite · boss · special</i> on creatures.'),
      li('<b>What blocks Save</b>: the shape rules the ship tests used to pin (a creature needs a <code>doc</code> line; a weapon exactly five level steps; a playable hero at least one perk; ...), listed per kind below once the tables load. Warnings (an untested brain / attack combination, a hidden hero with a favourite weapon and no perk, a change that leaves the quest-locked band) never block.'),
      li('<b>Vocabularies are listable, not extendable</b>: brains, attack names, behaviours, stat ids and telegraphs are code constants read from the game\'s source; every such select ends with "a new kind needs code: ask Claude".'),
      li('<b>Test in game</b> launches the editor binary into the debug arena with that hero (and its look) or that creature (and its look, three of them), the PC save kept aside and put back after; it holds the Godot lock while the window lives.')));
    rulesTable(root);

    root.appendChild(el('h2', { text: 'Looks and previews' }));
    root.appendChild(p('A <b>look</b> is one painted strip of a creature or a hero (its icon too, for a creature): the JSON\'s <code>variants[CODE]</code>. The <b>Looks</b> section of an enemy or a hero shows every look as a card with a live preview (hover it to play, click it for the player above, double-click for the close look), the chips <i>● default · NEW · shelved · not imported · stub</i>, its note, and the actions <b>Make default</b> (the look the game plays for every row that names none), <b>Approve</b> (you looked at it: clears NEW), <b>Shelve / Unshelve</b> (kept in the JSON, hidden from the arena chips and the default lists), <b>Remove</b> (the entry goes; its PNGs move to <code>tools/level_editor/backups/deleted/</code>), <b>Edit note / recipe</b> (the raw JSON), <b>Recipe (typed)…</b> (every field of the method with its source: <i>own</i>, <i>inherited</i> from the creature\'s own art words, or the method\'s <i>default</i>; a look with no recipe recorded says so, and keys the form has no row for are listed), <b>Re-roll…</b>, <b>Duplicate…</b> (a new look from this one: the job form opens with its recipe, words and painter copied and the next free code; change the model or the passes, or tick "reuse the paintings" to redo only the clips) and <b>Icon candidates…</b> (the last three open the job form). Each card also names its method, how many keys its recipe holds of its own and the painter it ran with (<code>variants[CODE].recipe.painter</code>: the model and the passes, written by every look job). A recipe keeps only what differs from the creature\'s own art words: an empty field inherits, it is not lost. The pane\'s header stays pinned while you scroll and carries the look\'s icon and the name, so the asset being edited is always in view. Built for fifty looks of one creature: a filter box, a status filter, pages of 24, ☐ select with bulk Shelve / Unshelve / Remove.'));
    root.appendChild(el('ul', {},
      li('<b>The player</b> plays the strip as the game does: the animation (<i>idle · run · attack · hit · die</i>, heroes <i>idle · run · hit · die · cheer</i>), the direction (<b>2</b> for a strip with front and back sets only, <b>8</b> when it has side and three-quarter views: the left ones are the right ones mirrored, as the game mirrors them), ◀ ▶ one frame, play / pause, a scrub bar, the speed ×0.25 … ×2, the zoom 1× / 2× / 4× (nearest-neighbour pixels from 1× up), the sand backdrop with the foot line, the blob and a 1 m bar, and ⤢ the close look in a dialog (4×, or as big as fits; ' + kbd('Esc') + ' closes).'),
      li('<b>Which frames play</b>: the strip order is the game\'s (<code>EnemyDef.frame_offset</code>, <code>Player.gd</code>); a view the strip lacks falls back along the game\'s own chain (<code>Player._anim_for</code>: bd → s → base; s → bd → fd → base; fd → s → f; f → fd → base) and the line under the player says "(plays back view)". A creature\'s attack, hit and die are painted once (the front set).'),
      li('<b>Mirroring</b> follows <code>EnemyManager._face_bit</code>: side and three-quarter sets mirror when heading left; a creature\'s front and back sets too, the other way round when its <code>front_faces</code> / <code>back_faces</code> says <code>left</code>, never for <code>straight</code>; a hero\'s base and front views never (the ⇋ left box shows the heading-left case for creatures).'),
      li('<b>Rates are preview rates</b>: creatures run at <code>fps.run</code> (10 when unset) and die at <code>fps.die</code> (6), idle 6, attack and hit 8; heroes run at <code>fps.run</code> (14), hit <code>fps.hit</code> (12), die <code>fps.die</code> (8), idle and cheer 6. In the game a walk runs at <code>fps.run</code> × the map\'s pace and a standing creature plays at 3 fps; hit, die and cheer play once and hold (looped here).'),
      li('<b>Scale</b>: the cell is the creature\'s <code>size</code> metres tall (a hero 1.9 m) at ~94 px/m, the rate gen_art\'s review sheets use; the camera\'s pixels_per_metre is 90 without a target, so the bar says "approximate".'),
      li('<b>Garry: "I don\'t really want to see 100 animations happening at once."</b> One clock drives every player; a player ticks only while it is on screen, playing, and within the cap of <b>' + StripPlayer.MAX_ANIMATING + '</b> animating at once (the rest sit at frame 0 with "paused: 12 already playing" and resume as others leave the screen); a grid card plays only while hovered. Decoded strips live in a cache of at most ' + StripPlayer.LRU_MAX + ' (a hero strip is 47 MB decoded): one is dropped when its player leaves the screen and decoded again on re-entry.'),
      li('<b>The JSON</b>: <code>variants[CODE].shelved: true</code> hides a look from the arena and the lists (the game reads it: <code>variant_codes()</code> skips it; a map row naming the code still plays it); <code>variants[CODE].fresh: true</code> is page-only (the NEW chip; Approve deletes it; the game ignores it); an entry without a <code>sprite</code> is a <b>stub</b> (a job\'s placeholder: queued, running, failed or cancelled; the game skips it). The look in play can be neither shelved nor removed; a look a map row names cannot be removed.')));
    demoPlayers(root);

    root.appendChild(el('h2', { text: 'Art jobs' }));
    root.appendChild(p('An <b>art job</b> paints something with the local AI: one or more <b>looks</b> of a creature or a hero (<b>+ New look…</b> in the Looks section, <b>Re-roll…</b> or <b>Duplicate…</b> on a card), <b>icon candidates</b> of an item, a creature look or a hero, a hero\'s <b>round badge</b> or <b>title cut-out</b> candidates, or a new <b>3D driver</b> from an uploaded model. The job form asks for the <b>method</b> first (Garry: "they should be explained well enough, with some level of small visuals, maybe an example, so that I can choose them in an informed manner"): every method card below says what it needs, what it makes, how long it takes, what to watch for, and shows an example. Then the method\'s recipe fields, the job\'s own settings, the 2D references (a <i>role</i>: identity, style, or pose and anatomy; a <i>follow level</i>: loosely, closely, copy exactly), the 3D references (the driver library with its sheets played, or an upload), one row per look to paint with the code it will get, the counts, the seeds and re-roll options, and <b>Show the words that will be sent</b>. <b>Queue</b> posts one job per look. Every job card shows "the command Claude would type", so a job can always be run by hand. Every workflow a job runs (one per render) is kept beside it and saved into the ComfyUI page\'s own <b>Workflows</b> sidebar under <code>88fits/&lt;id&gt;_&lt;CODE&gt;/</code>, as it lands: the card\'s <b>↗</b> link opens the ComfyUI page on that workflow (through the <code>88fits_open</code> extension on the server; without it the page opens and the workflow waits in the sidebar), <b>file</b> is the JSON to drag in, and <b>Send to ComfyUI</b> pushes the workflows of a job that ran before this existed.'));
    const methodsBox = el('div', { class: 'muted', text: 'loading methods.json…' });
    root.appendChild(methodsBox);
    const reflBox = el('div');
    root.appendChild(reflBox);
    if (typeof Jobs !== 'undefined' && Jobs.methods) {
      Jobs.methods().then((m) => { if (methodsBox.isConnected) { methodsTable(methodsBox, m); wordingsTable(reflBox, m); } });
    } else methodsBox.textContent = 'the Jobs module is not loaded';
    root.appendChild(el('ul', {},
      li('<b>Locks</b>: one ComfyUI job and one Godot process at a time across the queue, Claude\'s scripts and the lanes (<code>tools/dl/locks/comfy.lock</code>, <code>godot.lock</code>, each with an <code>owner.json</code>). The Jobs tab\'s header shows who holds what; a lock without an owner file is "held by an unknown process" and only your explicit Force release removes it.'),
      li('<b>Re-roll</b>: <i>new seeds</i> rolls every still and clip again with the next seeds; <i>keep the stills, redo the clips</i> moves the clip folders to <code>&lt;key&gt;_old&lt;stamp&gt;</code> and makes the walks again; <i>redo one view</i> paints candidates of that view to pick from (gen_ctl); <i>repaint the stills</i> paints them again (the clips follow). Without a re-roll, cached work is reused.'),
      li('<b>Where things live</b>: stills <code>tools/dl/ai_raw_anime/&lt;key&gt;.png</code> (+ <code>.json</code> with the seed, the prompt, the refs, the QA verdict); clips <code>tools/dl/ai_anim/&lt;key&gt;/</code> (<code>out_NN.png</code> the kept frames, <code>cycle_sheet.png</code>); review sheets <code>tools/dl/review/</code>; icon candidates <code>tools/dl/icons_le_&lt;job&gt;/</code>; title candidates <code>tools/dl/title_heroes/</code>; uploads <code>tools/dl/uploads/2d|3d/</code>; the queue and every job\'s log <code>tools/dl/jobs/</code>. A finished look lands in the content folder as <code>&lt;id&gt;_sprite_&lt;letter&gt;.png</code> (+ <code>_icon_</code>) and in the JSON as <code>variants[CODE]</code> marked NEW; a job that could not merge its result into a hand-edited file ends done with <i>unmerged</i> and the card offers "Merge again" and "Re-dump this file (changes its layout)".'),
      li('<b>What a picture cannot do</b>: a 2D reference reaches the front still of a creature (or the side, for the 3D-control method); the other views are edits of that painting; motion comes from a driver or Wan\'s guess, never from a picture; the vision QA counts subjects, legs and views, never likeness. The authoritative words are what <code>tools/asset_job.py --dry-run</code> records.')));

    root.appendChild(el('h2', { text: 'The Jobs tab' }));
    root.appendChild(p('Garry: "a list of jobs that are in queue for the local AI, which are being worked on and as much detail about those jobs as possible ... cancel the jobs and edit them (while they are not running, obviously) ... add as many as I like." The tab asks the server every 2 s (6 s from other tabs, nothing while the page is hidden) and draws a card per job, grouped by state:'));
    root.appendChild(el('ul', {},
      li('<b>RUNNING</b>: the stage and the stages done, the elapsed time against a "~" estimate (the method\'s measured median × its stages: a Flux.2 dev restart can add minutes), the last 12 log lines, <b>Cancel</b> (kills the tool; a ComfyUI job also interrupts the server\'s queue, which holds only ours under the lock), <b>Open asset</b>, <b>Log</b>. "stalled" after 20 minutes of silence: never killed on its own.'),
      li('<b>WAITING FOR PICK</b>: the candidates (click a picture to zoom, click a card to choose), <b>Pick</b>, <b>Re-roll N more</b>, <b>Cancel</b>, <b>Edit</b> (back to the queue at phase 1).'),
      li('<b>QUEUED</b>: its place in its lane, <b>Edit</b> (the form again), ▲ ▼, <b>Cancel</b>.'),
      li('<b>DONE</b>: what was written and how (one entry in place, the whole variants block, or <i>unmerged</i> with its two buttons), the outputs (stills with their QA verdict, clips played, the strip), candidates to <b>Install</b> for icon, badge and title jobs, <b>Open look</b>, <b>Re-queue</b>, <b>Hide</b>, <b>Delete</b>.'),
      li('<b>FAILED / INTERRUPTED / CANCELLED</b>: the error, <b>Re-queue</b> (attempt + 1, the caches reused), <b>Edit</b>, <b>Log</b>, <b>Delete</b>, and <b>Remove the stub</b> for a look job that left an entry without a strip. INTERRUPTED is every job that was running when the server restarted.'),
      li('<b>The badge</b> on the tab button: ▸ running · queued, red with "?" when a pick waits. A job that finishes, fails or asks for a pick raises a toast with an "open" button. <b>Clear finished</b> deletes the finished records (the painted files stay).')));
    afieldTables(root);
  }

  /** The shape rules per kind from lane P's AFIELDS.RULES, when its tables are loaded. */
  function rulesTable(root) {
    if (typeof AFIELDS === 'undefined' || !AFIELDS.RULES) return;
    const kinds = Object.keys(AFIELDS.RULES).filter((k) => Array.isArray(AFIELDS.RULES[k]) && AFIELDS.RULES[k].length);
    if (!kinds.length) return;
    root.appendChild(el('h3', { text: 'The shape rules (errors block Save, warnings never do)' }));
    const t = el('table', { class: 'fieldtab' });
    t.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Kind' }), el('th', { text: 'Rule' }), el('th', { text: 'Level' }), el('th', { text: 'What it checks' }))));
    const tb = el('tbody');
    for (const k of kinds) for (const r of AFIELDS.RULES[k]) tb.appendChild(el('tr', {}, el('td', { class: 'name', text: k }), el('td', { class: 'key', text: r.key || '' }), el('td', { text: r.level || '' }), el('td', { class: 'help', text: r.help || r.text || (typeof r.msg === 'string' ? r.msg : '') })));
    t.appendChild(tb);
    root.appendChild(t);
  }

  /** Lane P's field tables (enemy, hero, weapon, line / passive, mutation, evolution), tolerant of functional `only` and `options`. */
  function afieldTables(root) {
    if (typeof AFIELDS === 'undefined') return;
    const kinds = [['enemy', 'An enemy, elite or boss'], ['hero', 'A hero'], ['weapon', 'A weapon'], ['evolution', 'An evolution'], ['mutation', 'A mutation'], ['passive', 'A line or a passive item']];
    const have = kinds.filter(([k]) => Array.isArray(AFIELDS[k]) && AFIELDS[k].length);
    if (!have.length) return;
    root.appendChild(el('h2', { text: 'Every field of the asset editors' }));
    root.appendChild(p('These tables come from the same tables the asset forms are built from (<code>assets_fields.js</code>). A field left empty is not written: the game uses its default. Keys the editor does not know stay as they are.'));
    for (const [k, title] of have) {
      root.appendChild(el('h3', { text: title }));
      const t = el('table', { class: 'fieldtab' });
      t.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Field' }), el('th', { text: 'JSON key' }), el('th', { text: 'Type' }), el('th', { text: 'Default' }), el('th', { text: 'Section' }), el('th', { text: 'What it does' }))));
      const tb = el('tbody');
      for (const d of AFIELDS[k]) {
        let type = d.type || '';
        if (type === 'select') { const o = typeof d.options === 'function' ? null : d.options; type = Array.isArray(o) ? o.map((x) => (typeof x === 'object' ? x.v : x)).join(' | ') : 'one of the game\'s list'; }
        const def = d.def === undefined || d.def === null ? '' : (typeof d.def === 'object' ? JSON.stringify(d.def) : String(d.def));
        tb.appendChild(el('tr', {}, el('td', { class: 'name', text: (d.label || d.key || d.path || '') + (d.required ? ' *' : '') }), el('td', { class: 'key', text: d.key || d.path || '' }), el('td', { text: type }), el('td', { class: 'def', text: def }), el('td', { text: d.section || '' }), el('td', { class: 'help', text: (d.help || '') + (d.art ? ' (art: tool-only)' : '') })));
      }
      t.appendChild(tb);
      root.appendChild(t);
    }
  }

  /** The methods table from methods.json with the example picture or a hover player per row. */
  function methodsTable(box, m) {
    clear(box);
    box.classList.remove('muted');
    const list = m && Array.isArray(m.methods) ? m.methods : [];
    if (!list.length) { box.appendChild(p('<span class="muted">tools/level_editor/methods.json is not served yet: the method cards appear when it is.</span>')); return; }
    const t = el('table', { class: 'fieldtab methods-table' });
    t.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Method' }), el('th', { text: 'What it does' }), el('th', { text: 'Needs' }), el('th', { text: 'Produces' }), el('th', { text: 'Time' }), el('th', { text: 'Watch for' }), el('th', { text: 'Example' }))));
    const tb = el('tbody');
    const fmtMin = (s) => (s == null ? '?' : s >= 90 ? `${Math.round(s / 60)} min` : `${Math.round(s)} s`);
    for (const x of list) {
      const ex = el('td');
      if (x.example && x.example.image) {
        const url = '/' + String(x.example.image).replace(/^\.?\//, '');
        const img = el('img', { src: url, alt: '', loading: 'lazy', title: 'click to zoom' });
        img.addEventListener('click', () => StripPlayer.openImage(url, x.name));
        img.addEventListener('error', () => img.replaceWith(el('span', { class: 'muted small', text: '(picture missing)' })));
        ex.appendChild(img);
      }
      if (x.example && x.example.strip && x.example.strip.id) exampleStrip(ex, x.example.strip);
      tb.appendChild(el('tr', {},
        el('td', { class: 'name' }, el('div', { text: x.name || x.id }), el('div', { class: 'muted small', text: `${x.id} · ${(Array.isArray(x.kinds) ? x.kinds : [x.kind]).join(', ')}` })),
        el('td', { class: 'help', text: x.summary || '' }),
        el('td', { class: 'help', text: (x.needs || []).join(' · ') }),
        el('td', { class: 'help', text: x.produces || '' }),
        el('td', { class: 'def', text: x.time ? `~${fmtMin(x.time.median_s)} (worst ${fmtMin(x.time.worst_s)})` : '' }),
        el('td', { class: 'help' }, el('ul', { style: 'margin:0; padding-left: 14px;' }, (x.weaknesses || []).map((w) => el('li', { text: w })))),
        ex));
    }
    t.appendChild(tb);
    box.appendChild(t);
    if (m.timings_note) box.appendChild(p(`<span class="muted small">${m.timings_note}</span>`));
    if (Array.isArray(m.deaths) && m.deaths.length) {
      box.appendChild(el('h3', { text: 'The deaths a creature method can make' }));
      const dt = el('table', { class: 'fieldtab' });
      dt.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'death' }), el('th', { text: 'Name' }), el('th', { text: 'What happens' }), el('th', { text: 'Time' }))));
      dt.appendChild(el('tbody', {}, m.deaths.map((d) => el('tr', {}, el('td', { class: 'key', text: d.value || '""' }), el('td', { class: 'name', text: d.name }), el('td', { class: 'help', text: d.text }), el('td', { class: 'def', text: d.seconds ? `~${d.seconds} s` : 'instant' })))));
      box.appendChild(dt);
    }
    if (m.insert_3d_text) { box.appendChild(el('h3', { text: 'A 3D reference' })); box.appendChild(el('div', { class: 'insert3d', text: m.insert_3d_text })); }
  }

  /** A hover player of an example look in a table cell, when its record is reachable (App.S.enemies or /api/heroes). */
  function exampleStrip(cell, st) {
    const kind = st.kind === 'hero' ? 'hero' : 'enemy';
    const done = (rec) => {
      if (!rec || !cell.isConnected || typeof LookGrid === 'undefined') return;
      const looks = rec.looks || rec.variants || [];
      const look = (st.code ? looks.find((l) => l.code === st.code) : null) || looks.find((l) => l.base) || looks.find((l) => l.code === (rec.play || rec.variant)) || looks[0];
      if (!look || !(look.anims || rec.anims)) return;
      const pl = StripPlayer.create(LookGrid.playerOpts(kind, rec, look, { mode: 'hover', zoom: 0.5, anim: 'run', label: `${st.id} ${look.code}` }));
      demo.push(pl);
      cell.appendChild(el('div', { class: 'sp-demo' }, pl.el, el('span', { class: 'muted small', text: `${st.id} ${look.code}: hover` })));
    };
    if (kind === 'enemy') done((App.S.enemies || []).find((c) => c.id === st.id));
    else fetch('/api/heroes', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : [])).then((list) => done(Array.isArray(list) ? list.find((h) => h.id === st.id) : null)).catch(() => {});
  }

  /** The reference roles and the proven wording each maps to (methods.json ref_wordings). */
  function wordingsTable(box, m) {
    clear(box);
    const rows = m && Array.isArray(m.ref_wordings) ? m.ref_wordings : [];
    if (!rows.length) return;
    box.appendChild(el('h3', { text: 'Reference roles and the words they become' }));
    box.appendChild(p(m.ref_note ? m.ref_note : 'There is no strength number: references steer by which pictures go in, in what order, and these words.'));
    const t = el('table', { class: 'fieldtab' });
    t.appendChild(el('thead', {}, el('tr', {}, el('th', { text: 'Role' }), el('th', { text: 'Follow' }), el('th', { text: 'The words sent (the picture\'s place in the list fills <n>)' }), el('th', { text: 'Source' }))));
    t.appendChild(el('tbody', {}, rows.map((r) => el('tr', {}, el('td', { class: 'name', text: r.role || '' }), el('td', { text: r.level || '' }), el('td', { class: 'help', text: r.text || '' }), el('td', { class: 'def', text: r.source || '' })))));
    box.appendChild(t);
  }

  /** Two live players under "Looks and previews": the first creature with painted looks the server describes. */
  function demoPlayers(root) {
    if (typeof StripPlayer === 'undefined' || typeof LookGrid === 'undefined') return;
    const list = App.S.enemies || [];
    const rec = list.find((c) => c.id === 'lesser_scorpion' && (c.looks || c.variants || []).some((l) => l.anims)) || list.find((c) => (c.looks || c.variants || []).some((l) => l.anims && l.ready !== false));
    if (!rec) { root.appendChild(p('<span class="muted small">(the live example appears when the server describes the looks\' frames: pass 66\'s /api/enemies)</span>')); return; }
    const looks = rec.looks || rec.variants || [];
    const look = looks.find((l) => l.code === (rec.play || rec.variant) && l.ready !== false) || looks.find((l) => l.ready !== false) || looks[0];
    if (!look) return;
    const a = StripPlayer.create(LookGrid.playerOpts('enemy', rec, look, { mode: 'controls', zoom: 1, anim: 'run', label: `${rec.name} ${look.code}` }));
    const b = StripPlayer.create(LookGrid.playerOpts('enemy', rec, look, { mode: 'hover', zoom: 0.5, anim: 'run', label: `${rec.name} ${look.code}` }));
    demo.push(a, b);
    root.appendChild(el('div', { class: 'sp-demo' }, a.el, el('div', {}, b.el, el('div', { class: 'muted small', text: 'a grid card: hover to play' }))));
    root.appendChild(p(`<span class="muted small">${U.theName ? U.theName(rec.name) : rec.name} ${look.code}, as the Looks section shows it: the full player, and a card at half size.</span>`));
  }

  /** docs/assets_schema.md at the end, like the waves schema (GET /api/schema/assets). */
  function schemaAssets(root) {
    root.appendChild(el('h2', { text: 'The asset schema (docs/assets_schema.md)' }));
    root.appendChild(p('The JSON keys of looks, heroes, items and created creatures, the look record, the jobs queue, the ledger and the locks, as the repository holds them.'));
    const box = el('div', { class: 'schema-doc', html: assetsSchema ? markdown(assetsSchema) : assetsSchema === '' ? '<p class="muted">the server does not serve it yet (GET /api/schema/assets); the file is docs/assets_schema.md in the repo.</p>' : '<p class="muted">loading…</p>' });
    root.appendChild(box);
    if (assetsSchema === null) {
      fetch('/api/schema/assets', { cache: 'no-store' }).then((r) => (r.ok ? r.text() : '')).catch(() => '').then((text) => {
        assetsSchema = text || '';
        if (box.isConnected) box.innerHTML = assetsSchema ? markdown(assetsSchema) : '<p class="muted">the server does not serve it yet (GET /api/schema/assets); the file is docs/assets_schema.md in the repo.</p>';
      });
    }
  }

  return { render, EXAMPLE, fieldTable, methodsTable };
})();
