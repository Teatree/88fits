// The Instructions tab (pass 53, pass 54): what the editor is, the model in one picture, every lane, field and override (read from
// fields.js, so these words and the forms never drift apart), a worked example with its block, its inspector values and
// the JSON it writes, how Save works, the two .cmd files, the keys, and the schema doc itself (docs/waves_schema.md via
// /api/schema) at the end. Garry asked for "an Instructions tab describing each tool with a simple example with graphics".
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
    pass54(root);
    picture(root);
    lanes(root);
    fields(root);
    example(root);
    saving(root);
    cmds(root);
    keys(root);
    schema(root);
    container.appendChild(root);
  }

  const p = (text) => el('p', { html: text });
  const li = (text) => el('li', { html: text });
  const kbd = (k) => `<span class="kbd">${k}</span>`;

  // ------------------------------------------------------------------ what this is

  function intro(root) {
    const m = App.S.maps.find((x) => x.id === App.S.mapId);
    root.appendChild(el('h1', { text: 'How the Level Editor works' }));
    root.appendChild(p(`This page edits the <b>wave timeline</b> of one map: the <code>timeline_data</code> block of <code>${m ? m.file : 'game/content/maps/<map>/<map>.json'}</code>. The game's director (<code>WaveDirector</code>) reads that block and nothing else decides which creatures come when, how many, with what numbers. Everything else in the file (the scene, the music, the skins) rides along untouched.`));
    root.appendChild(el('ul', {},
      li('<b>Every time is a second of the run clock</b>, shown as mm:ss. The clock runs only while the hero is in the open: it stands still through a boss fight and while the portal waits. Stage 2 starts at <code>stage_length</code>, stage 3 at twice it; after the last stage the run is endless.'),
      li('<b>Timeline</b> is the calendar: the cap (the ceiling), the HP × and ATK × curves, the roster (the stream) and its share band, the waves (scripted bursts), the events (bosses, Elites, swarms), the specials and the path offers, on one time axis. Hover for the readout of any second or the card of any item; click anything to edit it in the inspector on the right; drag to move it.'),
      li('<b>Settings</b> holds every number of the timeline in a form, each with a one-line help. <b>Creatures</b> is the palette: what every creature is made of, with a button that starts a wave or a row with it, and its art variants: a click on one sets it as the creature\'s default look. <b>Instructions</b> is this page.'),
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
      li('<b>Knockback</b> per creature (Body → Knockback; the grey number is its own, or <code>clamp(3.4 × √(damage / 4), 2.5, 7)</code>), <b>creature_damage_mult</b> (Settings → Scaling: every hostile damage) and the <b>spawn sides</b> (Settings → Spawning: top / bottom / left / right weights, or the old facing rule).'),
      li('<b>Default look</b>: on the Creatures tab, click a variant and "Set as default look"; after you confirm, the server writes that creature JSON\'s <code>variant</code> (after a backup) and imports it.')));
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
    root.appendChild(p('The hover card\'s numbers follow the game (EnemyManager.spawn): an ordinary creature has <code>HP = hp × stage_mult × HP curve(t) × level × creature_hp_mult</code>; an Elite-archetype mini-boss <code>hp × elite.hp_mult_per_stage^stage × stage_mult × creature_hp_mult</code> (no curve, no level); a boss <code>hp × boss.hp_mult_per_stage^stage × stage_mult</code>. ATK is <code>damage × stage_mult × damage curve(t) × level × creature_damage_mult</code> for all of them. A row\'s <code>hp</code> / <code>damage</code> overrides replace the base and its <code>*_mult</code> keys multiply it.'));
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
    ];
    t.appendChild(el('tbody', {}, rows.map(([a, b]) => el('tr', {}, el('td', { class: 'name', html: a }), el('td', { class: 'help', text: b })))));
    root.appendChild(t);
  }

  function schema(root) {
    root.appendChild(el('h2', { text: 'The schema (docs/waves_schema.md)' }));
    root.appendChild(p('The contract between this editor and the game, as the repository holds it. The editor writes exactly these keys.'));
    root.appendChild(el('div', { class: 'schema-doc', html: App.S.schema ? markdown(App.S.schema) : '<p class="muted">loading…</p>' }));
  }

  return { render, EXAMPLE };
})();
