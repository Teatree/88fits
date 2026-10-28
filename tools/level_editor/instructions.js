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
    // pass 111 (lane SKINS): a hero's looks sold as skins, their goals, the currencies (skins.js writes the section)
    if (typeof Skins !== 'undefined' && Skins.instructions) Skins.instructions(root);
    pass87Stages(root);     // pass 87 (lane STOOLS): the stage tabs, a stage's card, the estimate and the Sim per stage
    pass84Timeline(root);   // pass 84 (lane TIMELINE): the Timeline in sections, one spawning language
    // pass 83 (lane SCALE): boss HP by seconds of full DPS, the hero's power level (power_card.js writes the section)
    if (typeof PowerCard !== 'undefined' && PowerCard.instructions) PowerCard.instructions(root);
    pass77Sim(root);   // pass 77 (lane SIMUI): the Sim tab
    pass76Icons(root);   // pass 76 (lane ICON): the icon guard
    // pass 72 (lane BOSS): boss HP pegged to DPS, the custom boss attacks (boss_attacks.js writes the section)
    if (typeof BossAttacks !== 'undefined' && BossAttacks.instructions) BossAttacks.instructions(root);
    pass71(root);   // pass 71 (lane PLE): the Puppet method
    pass70(root);
    pass69(root);
    pass68(root);
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
      li('<b>Every time is a second of the run clock</b>, shown as mm:ss. The clock runs only while the hero is in the open: it stands still through a boss fight and while the portal waits. Since pass 87 each stage is a window of the clock with its own length (the stage tabs) and a run plays one stage; without a stage list stage 2 starts at <code>stage_length</code>, stage 3 at twice it.'),
      li('<b>Timeline</b> is the calendar: the cap (the ceiling), the HP × and ATK × curves, the roster (the stream), the waves (scripted bursts), the events (bosses, Elites, swarms), the specials and the path offers, on one time axis. Hover for the readout of any second or the card of any item; click anything to edit it in the inspector on the right; drag to move it.'),
      li('<b>Settings</b> holds every number of the timeline in a form, each with a one-line help. <b>Creatures</b> is the palette: what every creature is made of, with a button that starts a wave or a row with it, its looks as pictures (a click on one, and a yes, makes it the creature\'s default look) and its blood colour (the death splash). <b>Instructions</b> is this page.'),
      li(`<b>Save</b> (${kbd('Ctrl+S')}) writes the JSON (after a backup) and runs the JSON → .tres import, so the next launch of the game from the editor binary plays it. The JSON is what goes into git. Errors (red) block the save; warnings (yellow) never do.`)));
    root.appendChild(p('The loop Garry asked for: look at the long map of the run, pick the snippets of time when creatures appear, set their count, their bursts, their numbers, their look, save, play, come back. Every change is one undo step.'));
  }

  // ------------------------------------------------------------------ pass 87 (lane STOOLS)

  /** Pass 87: stages as their own runs, on the Timeline (the tabs, a stage's card), the estimate, the Sim and the Watch. */
  function pass87Stages(root) {
    root.appendChild(el('h2', { text: 'Pass 87: stages as their own runs' }));
    root.appendChild(p('Garry: <i>"Now Player Unlocks Stages and is only able to enter them after having completed the previous one. They differ in how long it takes to complete them as well."</i> The map still has <b>one timeline</b> on one run clock (the rows, the events, the curves), and each stage is a <b>window</b> of it: stage k starts where the stages before it end (Red Canyon: 0:00–7:10, 7:10–17:10, 17:10–30:10) and its boss comes at its end. A run plays <b>one</b> stage: a fresh hero (level 1, his start weapon) at the window\'s start; after the boss the portal opens with a countdown and only EXTRACT; when it runs out, <b>Endless</b> (a huge wave, then a wave every few seconds, each tougher) until he falls.'));
    root.appendChild(el('ul', {},
      li('<b>The stage tabs</b> above the Timeline: <b>All</b> (the whole map, every window on the one clock) and one tab a stage. A stage tab shows only its window: the ruler counts the stage\'s own clock (0:00 at its start, the map\'s clock in brackets), the rows open in it (a row spanning two windows shows on both), its boss, the portal\'s countdown and two minutes of Endless after it. Each tab remembers its own Sim.'),
      li('<b>A stage\'s card</b> (click its tab, or its band on the ruler): its name, the difficulty line and the description the Stages menu shows, its picture, its <b>length</b>, its <b>boss</b>, its <b>look</b> (a colour and a strength the world is multiplied by: blue for an evening, red for a blood moon; <i>On creatures</i> is how much of it the creatures take, lower keeps them brighter; the preview shows the map\'s colours in daylight and in the stage\'s look) and the hell ground. A new length asks first: <b>Keep its times</b> (what is in the stage stays where it is; longer: its rows that ran to its end run on; shorter: what lies past the new end is cut, named in the question) or <b>Stretch</b> (everything in it moves in proportion, nothing is cut). Either way the later stages and everything in them move with their windows.'),
      li('<b>+ Stage</b> appends a stage with the last one\'s settings (its length, boss, look; no rows yet) and its boss at its end; <b>Delete stage</b> (on its card) asks, then removes the stage and what lies wholly in its window, shortens what spans it, and moves the later stages back. A map without a stage list shows its old stages (Stage length × Stages in Settings); the first stage edit writes a stage list.'),
      li('<b>The estimate</b> of a stage tab is that stage\'s run: an empty map at its start, only its own events (not the stage before\'s boss), its boss, the countdown, then Endless by the map\'s <code>endless</code> numbers (Settings → Endless). <b>All</b> stitches every stage\'s run on the clock, so the counts start again at each window. The hover cards\' hero level and the typical hero start at level 1 / power 1 at each window.'),
      li('<b>The Sim tab</b> has a <b>Stage</b> box: every run of the sim plays that stage (the bot never extracts, so a run goes on into Endless until the stop or its death); its history and its result say the stage; the result\'s summary counts the boss kills, the outcomes and the median seconds lasted in Endless. <b>The Watch</b>\'s Hero Settings has a Stage row (every stage with Every unlock on; with it off, only the stages your PC save has unlocked).')));
  }

  // ------------------------------------------------------------------ pass 84 (lane TIMELINE)

  /** Pass 84: the Timeline in sections, the marks, the view lanes and what they are made of, the spawn rows, the warnings. */
  function pass84Timeline(root) {
    root.appendChild(el('h2', { text: 'Pass 84: the Timeline in sections, one way to spawn' }));
    root.appendChild(p('The Timeline tab is a stack of <b>sections</b>, each a bar with its name, a line of what it is and its own controls. <b>Click a bar to collapse it</b>: it stays where the section was, hatched, with a dashed frame, a summary of what it holds and <i>collapsed: click to open</i> in yellow, so you always see where it went. Each map remembers its sections in this browser; <b>Collapse all</b> / <b>Open all</b> are in Ruler and controls (the ruler itself always stays at the top). The inspector folds too: ⇥ at its top right, a hatched strip to open it again.'));
    const marks = el('ul', {},
      li('<b>The marks.</b> An <b>eye</b> on a section or a lane (and a darker, recessed background) means <b>view only</b>: worked out from the map, the estimate and the Sim, nothing there changes the map. A <b>pencil</b> (and the normal surface) means <b>editing</b>: drag, click and type there to change the map. The inspector\'s groups carry the same marks.'));
    root.appendChild(marks);
    const list = el('div', { class: 'lanes-list' });
    for (const sec of FIELDS.SECTIONS) list.appendChild(el('div', { class: 'lane-card' }, el('b', { text: `${sec.kind === 'view' ? 'view only' : 'editing'} · ${sec.name}` }), sec.what));
    root.appendChild(list);
    root.appendChild(p('<b>Charts you can read.</b> Every view section starts with <i>What is this?</i>, a legend naming each line, and <i>How it is worked out</i>: the exact recipe and units. In short:'));
    root.appendChild(el('ul', {},
      li('<b>On screen</b>: creatures alive each second (a count of bodies). The estimate fills the lane (the hell channel red on top), the Sim\'s real count is dashed, the cap is drawn in bodies (the cap counts load units: a skeleton is half a unit, so cap ÷ the average load per body alive), the floor dotted green. Red behind the lane: the cap is full there and rows that wanted to spawn starve; hover it for which.'),
      li('<b>Challenge</b>: <b>seconds of the hero\'s damage to clear the screen</b> = the crowd\'s HP on screen ÷ his damage a second (the Sim\'s hero when a Sim is shown, else a typical hero from the power curve). The switch in its bar shows the second measure, <b>health bars lost clearing the screen</b> = the crowd\'s HP × bite ÷ (his damage × his effective HP), the Sim\'s "challenge". Green, amber and red are under the easy limit, up to the hard limit, past it (the two boxes in the bar; each measure keeps its own). Red dots: the Sim\'s deaths.'),
      li('<b>Composition</b>: each creature\'s share of the crowd on screen (or of what spawned in the past N seconds), stacked to 100%; the estimate\'s or the Sim\'s.'),
      li('<b>Ruler and controls</b> holds what every chart assumes: the estimate\'s kill rate, boss fight and portal wait (empty = from your runs), <b>Sim to show</b> (the newest finished Sim of this map by default) and <b>lifetimes from the Sim</b> (the estimate lets each creature the Sim measured live its measured seconds).')));
    root.appendChild(p('<b>One way to spawn.</b> Swarms, coloured elites and Elites every are <b>spawn rows</b> now, with every option they had and more: a row is <b>Continuous</b> (drawn into the cap), <b>Waves every N s</b> (Every may be two numbers: a fresh random gap each time) or <b>Once</b> (one wave at its start + Offset). Its creatures are one creature, a list drawn by weight, or <b>the roster draw</b> (the coloured-elite draw by the rows\' Elite weight). It may wear an elite modifier, come as its special, show a banner, spawn on a ring of its own radius, roll a chance and a jitter, carry a role and a name. The events keep the bosses and the Elite mini-bosses; the portal after each boss is marked on the Events lane (click it). An old map\'s swarm, elite and Elites-every events are read as rows when it loads (the game plays both alike); Save writes the rows.'));
    root.appendChild(el('ul', {},
      li('<b>+ Row</b> offers each kind: continuous, waves, once (a swarm), a coloured elite, Elites every, a special.'),
      li('<b>Spawn rows</b> are grouped by stage (or role, both, none: the bar\'s <i>group</i> box), each group folding to a hatched band with its rows as thin lines. Bars are coloured by role (or by creature). On a bar: who, how many and how often (≈ per minute for a continuous row: the estimate over its life), its HP and ATK in play at its start, its weight, then badges (★ elite modifier, ◆ special, ⚑ banner, the pattern, hell, the look, a wrench for overrides). <b>Suggest roles</b> gives every untagged row a role from its keys and its creature (one undo step).'),
      li('<b>The inspector</b> holds every option of a row in groups that fold (Schedule, Creature, Where and how, Presence, In the estimate with a mini-chart of what it spawns each second and its HP over its life, Overrides with every group: Body, Colour, Attacks, Ranged, Charge, Kamikaze, Artillery, Sniper, Flee on hit, Spawning, Drops, Power-ups, Elite, Mini-boss, Boss). <b>Split at …</b> cuts the row at the second under the pointer (the second part\'s numbers fixed afresh there); <b>→ once / → waves / → continuous</b> repace it.'),
      li('<b>The floor</b> (Curves → Floor; + Floor starts one): the least creatures alive; while fewer are alive the director draws the continuous rows at once, within the cap.'),
      li('<b>Warnings</b> lists what the estimate finds, each with <b>Go to</b>: the cap full and which rows starve (when), rows that never spawn or never make 1% of what spawns in any 10 s of their life, the crowd\'s HP more than doubling in a second, a floor above the cap, two identical rows overlapping. The map\'s own checks (errors block Save) stay in the inspector when nothing is selected.')));
  }

  // ------------------------------------------------------------------ what pass 54 added

  function pass54(root) {
    root.appendChild(el('h2', { text: 'Pass 54: what is new' }));
    root.appendChild(p('<b>The cap points.</b> The points on the Cap lane are the control points of the live cap curve (how many creatures may be alive): the line is linear between them and flat before the first and after the last. They are <b>not spawn events</b>: nothing spawns at a point. The director spawns up to the cap on its own interval (every <code>spawn_interval</code> seconds, a burst of <code>burst_min</code> to <code>burst_max</code> load units while there is room). Every point shows its cap as a faint number.'));
    root.appendChild(el('ul', {},
      li('<b>Presence keyframes</b> replace <code>weight</code> / <code>weight_late</code>: a roster row\'s <code>weights</code> is a list of <code>[time, weight]</code> points, linear between them, flat outside. The bar draws them as a filled area in the creature\'s colour; drag a point up or down (or along), double-click the bar to add one, double-click a point to remove it (a row keeps two). An old row is read as <code>[[t, weight], [weight_late_t, weight_late]]</code> on load and Save writes the new shape; <code>weight_late_t</code> stays in the file for old rows elsewhere.'),
      li('<b>Who spawns</b> (pass 83): hover the timeline and the readout lists every roster row and wave with its share of all the creatures spawned in the <b>past N seconds</b> (the box next to Snap on, 5 by default), read off the Spawned so far estimate; the roster bars that spawned nothing in that window dim. Hover a bar for its share, a yellow tick for that wave (its count and its share of the N seconds from it) or that draw (how often, how much a draw holds). A continuous row is drawn at the spawn check (Settings → Spawning, 0.7 s on Red Canyon) unless its <b>Draw every</b> gives it its own clock.'),
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
    root.appendChild(p(`Red <b>!</b> marks on a bar, block or marker are errors (the inspector says what), yellow ones warnings. With nothing selected the inspector lists every issue; click one to jump to it. The lanes zoom with ${kbd('+')} / ${kbd('−')} or ${kbd('Ctrl')} + wheel (at the mouse), "Fit" shows the whole run; in the Spawn rows, hold the right mouse button and drag to pan (time and rows).`));
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
      case 'floor_points': return '[[seconds, creatures], …]';
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
      // pass 81 (lane PACE): a roster row's waves-only fields say so
      const only = d.only ? ` (${d.only.map((k) => FIELDS.EVENT_TYPES[k].label).join(', ')} only)` : d.paced ? ' (Pacing: Waves every N s only)' : '';
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
    // pass 81 (lane PACE): a row's own pacing
    root.appendChild(p('<b>Pacing</b> (pass 81; Garry: "the frequency at which enemy waves come"). A row is <b>Continuous</b> by default, as every row always was: at every spawn check (<code>spawn_interval</code>) the director draws a burst of <code>burst_min</code> to <code>burst_max</code> load units from the open rows by their weights into the cap (Settings → Spawning). Set its Pacing to <b>Waves every N s</b> (<code>"pace": "waves"</code>) and it comes in waves instead: <code>count</code> creatures (default the row\'s pack) every <code>every</code> seconds (default 30; 0 = one wave), the first at <code>t</code> + <code>offset</code>, while the row is open, in its pattern; a wave due while its presence weight is 0 does not come. <code>respect_cap</code> (default on): a wave fills the free room of its channel\'s cap and the rest comes first as room frees, until the row\'s next wave; off = all at once on top of the cap. <code>trickle</code> (default off) keeps it in the continuous draw between its waves too. On the Timeline each bar carries yellow etches: a line where a continuous row is drawn, a tick at each wave.'));
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
      ['Hover the lanes', 'the cursor and the readout (time, stage, cap, HP × and ATK ×, each roster row\'s and wave\'s share of the past N seconds, the waves running, the next event)'],
      ['Hover a bar, block, stripe, flag or the specials band', 'its card: the creature\'s picture, HP and ATK at that second (orange dot = changed by an override, * = other stats overridden) and its share of what spawned in the past N seconds (the box next to Snap on)'],
      ['Hero level (top bar)', 'the hero level the cards and the readout assume (creatures grow with it); never written to the map'],
      ['Creatures tab: click a variant · "Set as default look" · confirm', 'select it · ask to make it the look in play · the server writes the creature JSON and imports it'],
      ['A picker with pictures: type · ' + kbd('↑') + ' / ' + kbd('↓') + ' · ' + kbd('Enter') + ' · ' + kbd('Esc'), 'filter · move · choose · close'],
      [kbd('Ctrl') + ' + wheel · ' + kbd('+') + ' / ' + kbd('−') + ' · Fit', 'zoom at the mouse · zoom · the whole run'],
      ['Hold the right mouse button in the Spawn rows and drag', 'pan the view: time left and right, the rows up and down (no menu there; it never moves a bar)'],
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

  // ------------------------------------------------------------------ pass 71: the Puppet method (lane PLE)

  /** Garry (2026-10-13): "I quite like this approach, add that in to LevelEditor with the considerations that I asked you
   *  about earlier": choose which 2D reference feeds the 3D model (or have one painted locally), preview the animated 3D
   *  model in the editor, the Puppet method in the job form like the others with its warnings and timings. */
  function pass71(root) {
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, intro2, steps) => { root.appendChild(el('h3', { text: title })); if (intro2) root.appendChild(p(intro2)); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 71: the Puppet method' }));
    root.appendChild(p('A hero\'s painting becomes a rigged 3D figure (a <i>puppet</i>) whose own renders guide the video model, instead of a flat Mixamo stick figure. The trial on May showed it keeps each view at its right size without Run size, keeps the back-diagonal turned away, and needs no hand-tuned driver. Now it is a method in the job form, any hero\'s.'));
    root.appendChild(el('ul', {},
      li('<b>What it does</b> (<code>tools/puppet.py</code>, one job on the Jobs tab): (1) the <b>arms-out paintings</b>: Klein (or Flux.2 dev) edits the look\'s front still into an A-pose, then the side and the back, and you pick one of each on the job card; (2) the <b>3D shape</b>: Hunyuan3D-2mv on the AI server (two tries, you pick one); (3) Blender cleans it, finds the joints and <b>rigs</b> it with Mixamo\'s bones; (4) plays the <b>Mixamo clip</b> on it, colours it from the paintings and makes the <b>GLB</b> you can turn in the editor; (5) the <b>guides</b>: stick figures from its own bones (framed by the soles), depth videos and its silhouette; (6) the <b>walks</b> of the look on them (gen_art, as any hero look).'),
      li('<b>The 3D reference, your choice per view</b>: in the form\'s <i>The 3D puppet</i> section each of front, side and back says what its picture is: <i>paint arms-out locally</i> (the default), a still of <i>any</i> look of the hero (shown as a thumbnail), an uploaded picture, or (side and back) none. A picture is used as it is: if its arms touch the body, the arms fuse into the torso and cannot be rigged.'),
      li('<b>The 3D preview</b>: the hero\'s <i>Art words</i> section shows his puppet (click <i>▶ 3D puppet</i>): drag to turn, wheel to zoom, the clip picker (<i>run</i>, <i>idle</i>), Play / Pause, the speed, the camera at front, 3/4, side, back. The puppet job\'s card shows the same viewer. It works offline (the viewer is in <code>tools/level_editor/vendor/</code>).'),
      li('<b>Reuse</b>: a hero who has a puppet starts the next puppet look from it (no paintings, no shape, no rig: the walks only, about 11 minutes); or from his <code>.blend</code> after you moved a joint in Blender; or from a Mixamo-rigged FBX; or a new puppet (the old one is moved to <code>tools/dl/puppet/&lt;hero&gt;/old/</code>, never deleted).'),
      li('<b>Options</b>: the moving clip and the idle (Mixamo FBX files in <code>tools/dl/mixamo/</code>), which views walk on the depth video and which on the stick figure (depth for fd, side, bd, back and the stick figure for the front: the trial\'s best), the framing (by the soles), <b>run size from the puppet</b> (<code>run_fit</code>: each view\'s walk stands at the height the 3D run has against its idle in that view; no Run size to tune), the <b>fringe remap</b> (<code>fringe_remap</code>: colours the painting does not have moved to its own), and the walks\' stills (the source look\'s, nothing painted again, or the look\'s own).'),
      li('<b>The settings</b> (the form\'s <i>The 3D puppet</i> → <i>The walks of this look</i>; each on by default and recorded in the look\'s recipe under <code>puppet</code>, so <b>Recipe (typed)…</b> shows what a look ran with and a re-queue runs what it holds): <b>Size from the 3D model</b> (<code>puppet.run_fit</code>: each view\'s walk as tall as the 3D model\'s run stands against its idle, by the middle frame; no Run size to tune), <b>Frame by the soles</b> (<code>puppet.frame</code>: the boots stay inside the picture), <b>Clean colour fringes</b> (<code>puppet.fringe</code>: the rainbow fringes on sleeves and boots turned into the painting\'s own colours), <b>Keep the face angle</b> (<code>puppet.face</code>: the stick figures\' ears placed from the 3D model\'s nose, so a side view stays in profile, and the back views walked on words without the face; May\'s side run turned its face to the camera without it, and MAY-R\'s first back walk faced the camera), and per view <b>Depth or stick figure</b> (<code>puppet.depth_views</code>: the depth video has no face, so the front walks on the stick figure).'),
      li('<b>Watch for</b>: Hunyuan3D-2mv\'s licence does not cover the European Union, the UK or South Korea (Garry accepted it for this project; read it again before anything made with it ships from there); the AI server is AMD, so only ComfyUI\'s built-in 3D nodes run and ComfyUI restarts before and after the shape; a depth video carries no face (the front walks better on the stick figure); Klein sometimes paints four hands: pick by eye.')));

    how('Make a puppet look (a hero without a puppet: Jeżyk\'s way)', 'About 20 minutes of machine time, three picks. Each pick waits on the Jobs tab; the comfy lane runs other jobs meanwhile.', ol(
      'Heroes tab → the hero → <b>Art words</b> → <i>The 3D puppet</i> → <b>+ Make a puppet look…</b> (or Looks &amp; previews → <b>+ New look…</b> → the method <b>Hero: a 3D puppet of the painting walks him</b>).',
      '<b>The 3D puppet</b> section: <i>source look</i> = the look whose stills are edited (the one he is played in); the <b>3D reference</b> rows: leave <i>paint arms-out locally</i>, or choose a look\'s still or an uploaded arms-out picture for a view; the painter (Klein: 20 s a candidate), the front candidates (4), the screen (green for a blue figure).',
      '<i>The clips</i>: running.fbx and the procedural idle are the trial\'s. <i>The walks</i>: keep depth for fd, side, bd, back, the soles framing and the run size from the puppet. The badge and cut-out candidates (3 each) come with the new look as with any look → <b>Queue</b>.',
      'Jobs tab → the job stops: <b>pick the arms-out front</b> (arms clear of the body all the way down, five fingers a hand, a gap between the legs) → Pick. It stops again: <b>one side and one back</b> (click one of each) → Pick. Then <b>the 3D shape</b> (each try in grey clay from six sides: pick the cleaner arms and legs) → Pick.',
      'The rest runs by itself (Blender on the local lane, then the walks on the comfy lane). The card shows every stage, the 3D puppet to turn and play, the guides and the walks. Look at each view of the new look against its idle, Approve it, and <b>Make default</b> to play it.'));

    how('A new look from the puppet he already has', null, ol(
      'Art words → <i>The 3D puppet</i> → <b>+ New look from the puppet…</b>; <i>start from</i>: <b>the puppet he has</b>.',
      'Change what the look changes: another clip (a walk: new guides are made from the same rig), the depth / stick-figure views, the fringe remap, or <i>the walks\' stills</i> → paint this look\'s own. → Queue. No paintings, no shape, no rig: a minute of Blender at most, then the walks.'));

    how('Fix the rig in Blender and walk again from it', 'The joints are found from the shape; an elbow or a knee in the wrong place shows as a bent sleeve in the 3D preview.', ol(
      'Open <code>tools/dl/puppet/&lt;hero&gt;/&lt;hero&gt;_puppet.blend</code> in Blender 5.2 (the mesh is named after the hero, the armature &lt;Name&gt;_Rig; <code>tools/dl/puppet/may/RIG_HOWTO.md</code> has every step): move the joint in Edit Mode, Ctrl+P → With Automatic Weights, check the head, Ctrl+S.',
      'A new puppet look → <i>start from</i>: <b>his .blend</b> → Queue: the clip is played on your rig again, the GLB, the preview and new guides (a new folder: the looks that walked on the old ones keep them), then the walks.',
      'Mixamo\'s auto-rigger instead: export the mesh, rig it on mixamo.com, download "FBX Binary, Original Pose, With Skin", upload it (+ New pose driver… → Upload), then <i>start from</i>: <b>a Mixamo-rigged FBX</b>.'));

    how('Run a puppet job again from one stage', null, ol(
      'Jobs tab → the puppet job → <b>Re-roll…</b> → <i>run the puppet again from a stage</i>: the arms-out paintings, the shape, the rig, the clips and colours, or the guides. That stage\'s files and the later ones move to <code>old/&lt;stamp&gt;/</code> and are made again; then the walks.',
      'On a pick: <b>Re-roll 4 more</b> paints that pick\'s candidates again on new seeds. In the job form of a look: re-roll <i>run the puppet again from a stage</i>.'));
  }

  // ------------------------------------------------------------------ pass 76: the icon guard (lane ICON)

  /** Garry (pass 76): "Bring back the old Solenne icon, I made a variant of an Icon and can't find the old one. Make a fix
   *  in LevelEditor to make sure that this doesn't happen." What changed, and how to find, undo and choose icons now. */
  /** Pass 77 (lane SIMUI): the Sim tab. Garry: "simulate like 10 players (editable) and the output is the average ...
   *  charts per second ... the sim requires a manual button press". */
  function pass77Sim(root) {
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, intro2, steps) => { root.appendChild(el('h3', { text: title })); if (intro2) root.appendChild(p(intro2)); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 77: the Sim tab (the game plays your map, run after run)' }));
    root.appendChild(p('The <b>Sim</b> tab (right after Timeline) plays the <b>saved</b> map with the real game, headless, as many times as you ask, with a bot at the controls (it kites the crowd like the difficulty probe, gathers gems when the way is clear, steps out of red warning rings, takes the level-up cards a sensible player would, takes chests, walks to the boss\'s chest and the portal; every item unlocked), and averages every second of play into charts. Every multiplier, the cap, the waves, specials, Elites and the bosses\' HP pegging count, because it is the game itself. Nothing runs until you press <b>Run sim</b>. It is one page that scrolls as a whole.'));
    how('Run a sim', null, ol(
      'In <b>Run a sim</b> (on top; <b>Hide settings</b> folds it to one line): the <b>Hero</b>; <b>Runs</b> (how many are played and averaged, 10 by default); <b>At once</b> (auto: as many as the runs, at most the PC\'s logical processors less 2); <b>Stop at</b> (play time, 25:00 by default; boss fights and portal waits count, the timeline\'s clock stops in them); <b>On death</b> (end the run at the first death, revive once with an ad then end, or keep playing and count every death); the <b>Seed</b>; a <b>Note</b> to find it later; <b>Drawing</b> (on: the runs skip the drawing and the sounds, the runner\'s sim mode, much faster; off: everything drawn as in the game, a check that the sim mode changes nothing).',
      'The <b>Upgrade board</b>: each of the eight talents with its rank (0-6) and its form. The buttons fill them: <b>none</b>, <b>a quarter</b>, <b>half</b>, <b>full</b> (each talent in its usual form, as the difficulty probe plays them) and <b>my save</b> (what you bought in your save on this PC). Change a row and the board is custom. Every run plays the same board.',
      'Press <b>Run sim</b>. With unsaved map changes it asks first: <b>Save and run</b>, or <b>Run the saved map</b>. Under the button: about how long it takes if every run lasts to the stop (runs that end at a death make it shorter), and why (it plays the real game frame by frame, 60 frames to a second of play, several runs at once; it learns the PC\'s speed from every full sim).',
      'While it runs, the card under the settings shows every run\'s clock, how many are done and about how long is left; <b>Cancel</b> stops it (the runs already finished stay as a partial result). The charts take over as soon as your sim\'s first run finishes. You can keep editing and saving meanwhile: the sim plays the copy it took when it started.'));
    how('Read the charts', null, el('ul', {},
      li('Five sections, in your order: <b>The hero</b> (DPS, HP), <b>Death</b> (runs still playing, deaths so far), <b>How hard is each second?</b>, <b>Rewards</b> (coins, damage, kills), <b>Growth</b> (level, XP, the build). The x axis is <b>play time</b>; thin lines mark where each stage starts and amber washes the boss fights.'),
      li('Each chart is the <b>average of the runs still playing</b> at that second; the pale band holds the middle 80% of the runs. <b>Runs still playing</b> says how many that is. <b>Deaths so far</b> counts every run, a finished run keeping its count.'),
      li('<b>How hard is each second?</b> <b>Danger</b>: the share of his max health the hero loses each second, before healing and after it (dashed). <b>Keeping up</b>: how many seconds of his own damage he would need to kill everything alive, the boss left out (rising = falling behind), and the boss alone (dashed). <b>Close crowd</b>: creatures within 3 m. Then who is alive, runs in trouble (under 30% health), what hurt him, hits taken, healing, the crowd against the cap, spawned and killed, and how strong a creature spawned now is. A chart the runs cannot draw is named under the section.'),
      li('Move the mouse over any chart: a line follows it on <b>every</b> chart and the numbers under each say what they were at that second. Without the mouse they show the end. <b>Table</b> shows the numbers every minute, <b>CSV</b> saves every second for a spreadsheet.')));
    how('Compare two versions of the map', null, ol(
      'Run a sim. Change the map (or a creature) and save.',
      'Run a sim again with the same settings and seed.',
      'In the <b>History</b> (the last 10 sims; <b>Keep</b> one to never lose it), press <b>Compare</b> on the first: its lines come in dashed grey on every chart of the one shown, and the numbers under each chart list both. The header says which map save each played.'));
  }

  function pass76Icons(root) {
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, intro2, steps) => { root.appendChild(el('h3', { text: title })); if (intro2) root.appendChild(p(intro2)); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 76: an icon is never lost again' }));
    root.appendChild(p('Solenne\'s old badge had not gone: a badge painted for her base was installed into SOL-B, the look the game plays, so every screen showed the new one. Her old badge is back (SOL-B shows her own again); the other one, <code>solenne_icon_b.png</code>, is still on disk. From now on:'));
    root.appendChild(el('ul', {},
      li('<b>Nothing is overwritten.</b> An installed badge, icon or card gets a new file of its own (<code>solenne_icon_b_3d3c_c2.png</code> = candidate c2 of job #3d3c for SOL-B); the old file stays.'),
      li('<b>The editor asks first</b> when the icon of <b>the look the game plays</b>, or of <b>the base look</b> (which every look without its own icon shows), would change: the picture now and the new one side by side, with their file names. <b>Cancel</b> changes nothing.'),
      li('<b>Every change is remembered</b> with a copy of the old picture under <code>tools/level_editor/backups/&lt;id&gt;/</code>, and <b>Revert icon</b> undoes the last one.')));
    how('Find an old icon and put it back', null, ol(
      'Heroes (or Enemies) tab → the hero → <b>Looks &amp; previews</b> → click the look\'s card. An item: Items tab → the item → <b>Art</b>.',
      'Under the pictures, the <b>Icon now</b> box says which file the game shows for that look and where it comes from. Open <b>All icons on disk</b>: every picture of that hero, creature or item that exists anywhere (its folder, the editor\'s backups, removed looks\' files, older tools\' copies), each once, with the looks that use it. Double-click one to see it big.',
      'Press <b>Use for &lt;look&gt;</b> under the one you want. For the look in play or the base the editor asks first; say yes. A backup copy is put back into the folder under its own name, then the import runs.'));
    how('Undo an icon change', null, ol(
      'The look\'s <b>Icon now</b> box → <b>Revert icon</b> (it is greyed out when there is nothing to undo; <b>Changes</b> lists every change, newest first).',
      'Look at the question (now → back to) and say yes: the look shows what it showed before, and the file it showed stays on disk.'));
    how('Install a candidate without surprises', null, ol(
      'Any <b>Install</b> button (a look\'s <i>Choose … from everything painted</i>, the Jobs tab\'s candidates, an item\'s icon candidates).',
      'For the look in play or the base, the question says what changes and where: "SOL-B is the look the game plays", or "SOL-A is the base look: SOL-B, SOL-C … show it too". Check the two pictures and the look\'s code before you say yes.',
      'Close the Level Editor and open it again once (<code>tools\\level_editor.cmd</code>) to get all of this: an editor started before pass 76 does not have it.'));
  }

  // ------------------------------------------------------------------ pass 69: how to use what pass 69 added (lane LE)

  /** Garry (pass 70, "LevelEditor"): distinct seeds per candidate; choose a look's icon and title cut-out from everything
   *  painted (and May's missing badge in the Heroes list); the Bandit error (what went wrong, a check); removing MAY-A;
   *  the inherited values already in their boxes; and how to make May's and Jeżyk's fixes in the editor alone. */
  function pass70(root) {
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, intro2, steps) => { root.appendChild(el('h3', { text: title })); if (intro2) root.appendChild(p(intro2)); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 70: candidates, pictures, the base look, inherited words' }));
    root.appendChild(p('What changed in the editor (and why), then one how-to each.'));
    root.appendChild(el('ul', {},
      li('<b>Every candidate on a seed of its own.</b> Within one job the seeds already differed, but every <i>new</i> job of the same look painted the same seeds again (May\'s two MAY-E badge jobs both painted seeds 2768, 3768, 4768; every title job of a hero 11, 112, 213, 314; a front from a picture always the same, and a re-run handed the very same files back from the cache). Now candidate k is a million seeds from k-1, every job moves its seeds by its own id, every re-run by its attempt, and a front from a picture moves its earlier candidates aside before it paints. Candidates still look alike when the words ask for the reference\'s own pose: they are edits of that picture. Ask for a different pose, action or camera to get variety.'),
      li('<b>Choose a look\'s badge, icon or title cut-out from everything painted.</b> Click a look: beside the big player, <i>Choose &lt;CODE&gt;\'s badge from everything painted</i> and <i>…title cut-out…</i> (a creature: <i>…icon…</i>) list every finished candidate job of that hero or creature; pick one, <b>Install</b>. The Heroes list now shows the badge of the look each hero is played in: May showed none because the list read her base look\'s icon, a dark placeholder, while her badge is MAY-G\'s own.'),
      li('<b>The Bandit error.</b> The job failed because <b>Stills</b> held the picture\'s path (<code>tools/dl/uploads/2d/bandit.png</code>). Stills is only a <i>short name</i> for the look\'s paintings (<code>bdb</code> → <code>buckshot_dwarf_bdb_front.png</code>); the picture belongs in <b>Reference</b>. The job built ComfyUI\'s upload name from Stills and the path in it made ComfyUI answer "500". Now the job form, the server and the recipe editor refuse such a Stills with "Stills is a short name for this look\'s paintings, like bdb; the picture goes in Reference", and an odd upload name is made safe before it reaches ComfyUI.'),
      li('<b>The base look can be removed.</b> Its card has <b>Remove…</b>: it asks which look becomes the base (the one in play first). MAY-A is gone this way: MAY-G is May\'s base.'),
      li('<b>Inherited words are in their boxes.</b> A look\'s recipe, the job form and a mutation\'s typed params show what a field inherits <i>in</i> the box (italic, dashed, marked <i>inherited from …</i>), so changing three words of a long prompt is typing three words. Edit it: it becomes the look\'s own. Empty it (or <b>↺ inherit</b>): it inherits again. A box you do not change writes nothing.'),
      li('<b>Fix one view</b>: <b>Run size</b> (the recipe\'s <code>run_scale</code>, one number per view) makes one view\'s walk bigger or smaller without painting anything; <b>+ Tweak a driver…</b> (a hero\'s Art words) makes a copy of a driver with one change (hands out, hands hidden, shoulders level; scale only keeps a wide figure inside the clip), and <b>Re-roll… → redo one view\'s walk</b> walks only that view again. A re-queue on the Jobs tab now reads the look\'s recipe as you saved it.'),
      li('<b>Two traps closed</b>: the pick of a front from a picture now writes only its Stills into the look\'s recipe (a look job queued before the pick kept losing its words: BD-A\'s first walk ran on the base dwarf\'s); and a Godot step of an import that hangs is stopped after 10 minutes (the job fails with the reason, <b>Re-queue</b> runs it again), so it never holds the Godot lock for everyone.')));

    how('Make a look from a picture (the Bandit), the right way', 'A front from a picture paints candidate fronts from your picture and your words; you pick one; then the look\'s walk is painted from that front.', ol(
      'Enemies tab → the creature (Buckshot Dwarf) → <b>Looks</b> → <b>+ New look…</b> → method <b>A front from a picture</b>.',
      '<b>Reference picture</b> → <b>Upload…</b> your picture (or <b>Change…</b> to one already uploaded): this is where <code>bandit.png</code> goes.',
      '<b>Stills</b> → a short name of letters, digits and _ for this look\'s paintings: <code>bdb</code> (any free one; the form says at once when it is not one).',
      '<b>prompt</b> → the creature in words, as <i>one</i> figure seen from the front (a turnaround prompt asks for two figures in one picture: keep every detail, drop the "front and back on one sheet" words); <b>keep</b> → what must survive ("the colours of the clothes, the barrel up and to the right"). Candidates 3 or more → <b>Queue</b>.',
      'Jobs tab → the job stops with the fronts: pick the best. Its look (BD-x) then shows <b>Generate…</b>: choose the walk method the creature\'s other looks use (A creature walked front and back), leave Stills as it is (it names the picked front) → Queue. Approve the look when it walks right; it stays NEW (not played) until you <b>Make default</b>.'));

    how('Choose a look\'s badge, icon or title cut-out from everything painted', null, ol(
      'Heroes (or Enemies) tab → the hero → <b>Looks &amp; previews</b> → click the look\'s card: its facts show beside the big player.',
      'Open <b>Choose &lt;CODE&gt;\'s badge from everything painted</b> (or <b>…title cut-out…</b>; a creature: <b>…icon…</b>): every finished candidate job of this hero, newest first, each saying which look it was painted for. The same two pickers sit under the badge and cut-out previews.',
      'Click the picture you want (any job\'s, any look\'s), then <b>Install … as &lt;CODE&gt;\'s badge</b>. An install job runs on the local lane: the round badge is made from the portrait (the old file backed up), the look\'s entry names it, then an import. The base look\'s choice goes to the hero\'s own files.',
      'More to choose from: <b>Badge candidates…</b> / <b>Cut-out candidates…</b> on the look\'s card (with other words: a different action or pose gives different pictures).'));

    how('Remove a base look (MAY-A)', 'The base look is the JSON\'s top-level strip (<code>variant_base</code>). Removing it makes another look the base.', ol(
      'The hero → Looks &amp; previews → the card with the <b>base</b> chip → <b>Remove…</b> (the look in play cannot be removed: make another the default first).',
      'Choose <b>which look becomes the base</b> (the one in play is first) → <b>Yes, remove …</b>.',
      'What happens: the new base\'s strip, icon, anims and fps become the JSON\'s top-level art (no file is renamed; its entry and recipe stay, so a re-roll of it still uses its own recipe), the old base\'s entry goes, its own files (the old top-level strip and icon) move to <code>tools/level_editor/backups/deleted/&lt;id&gt;/&lt;stamp&gt;/</code> with <code>base_&lt;CODE&gt;.json</code> saying what it was, and the JSON is imported. Looks that used the old top-level anims or fps get them written into their own entries.'));

    how('Change a few words of an inherited prompt or hint', null, ol(
      'The look → <b>Recipe (typed)…</b> (or the job form\'s <i>What to paint</i>): an inherited field already holds the words (italic, dashed, <i>inherited from the hero\'s art_prompt</i>).',
      'Click in it and change the words you want; when you leave the box it is this look\'s own (the mark turns <i>own</i>). <b>Save asset</b>.',
      'To go back: empty the box (it fills with the inherited words again) or press <b>↺ inherit</b>. A box you never changed writes nothing.'));

    how('Fix one view of a look (May\'s side runs, Jeżyk\'s back run, hands that show)', 'Every view of a hero look is walked on a pose driver (a stick-figure video); a view that comes out wrong usually needs another driver for that view, or other words for its painting.', ol(
      '<b>Look</b>: the look\'s card → the big player → animation <i>run</i>, the facing (front, fd, side, bd, back), step a frame at a time; compare each view\'s run with its own <i>idle</i> (the standing painting) and with the other views on the 1 m bar.',
      '<b>A view too tall or too small</b> (May\'s side run, Jeżyk\'s back run): not the driver. gen_art fits every walk back to the standing height by its tallest frame, so a run that crouches in every frame (a side run) comes out bigger and one whose foot reaches toward the camera (a back run) smaller, whatever the driver\'s size. <b>Recipe (typed)…</b> → <b>Run size: side</b> (and the others; the recipe key <code>run_scale</code>) → 0.88 makes that view\'s walk 12 % smaller (1 = as fitted; 0.5..1.5) → <b>Save asset</b> → <b>Re-roll…</b> with re-roll <i>none</i> → Queue: the cached walks are only placed again, nothing is painted (a minute). A view can grow only while its tallest frame fits the cell: shrink the others instead.',
      '<b>Which driver</b>: <b>Recipe (typed)…</b> → <i>Driver: side</i> (and the others): the view\'s driver (empty = the hero\'s own, named beside it).',
      '<b>Another driver</b>: pick one from the library in that row (the levelled <code>run_side</code>, <code>run_spread_lvl</code>, …), or make one: Art words → <b>+ Tweak a driver…</b> → <i>src</i> the view\'s driver → <i>op</i>: <b>scale</b> (only a wide figure that leaves the clip: 0.85 keeps arms or a hat inside; it does not change the sprite\'s size, Run size does), <b>spread</b> (hands painted on a back: the back wrists pushed out past the body), <b>occlude</b> (those wrists dropped), <b>shoulders</b> (a raised or sagging shoulder; tuck 25 for the side\'s far arm) → a new <i>name</i> → Queue (seconds) → look at its sheets on the job card. Name it in the look\'s recipe row → <b>Save asset</b>.',
      '<b>Walk that view again</b>: the look\'s card → <b>Re-roll…</b> → re-roll <b>redo one view\'s walk</b> → the view → Queue. Only that clip is made again; the other views and the paintings stay.',
      '<b>A painting problem</b> (straps missing on the back-diagonal, hands through the clothes on the front still): the view is painted from words: change the look\'s hint in place (<i>back_hint</i> for the back views, <i>side_hint</i>, <i>anim_hint</i> for the clips) → Save asset → Jobs tab → the look\'s job → <b>Re-roll…</b> → tick that view\'s still and its clip → Re-queue.',
      'Approve the look when every view plays right; <b>Make default</b> to play it.'));
  }

  /** Garry (pass 69): "When making changes to Items along the way, make sure to update the LevelEditor and include
   *  instructions on how I would be able to use the newly created tools in the future" (and the same for heroes). One
   *  short how-to per new tool, each a list of steps on the page as it is. */
  function pass69(root) {
    const ol = (...steps) => el('ol', { class: 'howto' }, steps.map((s) => li(s)));
    const how = (title, intro2, steps) => { root.appendChild(el('h3', { text: title })); if (intro2) root.appendChild(p(intro2)); root.appendChild(steps); };
    root.appendChild(el('h2', { text: 'Pass 69: how to use the new tools' }));
    root.appendChild(p('Garry: "make sure to update the LevelEditor and include instructions on how I would be able to use the newly created tools in the future." What changed in the editor, then one how-to per tool.'));
    root.appendChild(el('ul', {},
      li('<b>Typed params</b>: a weapon\'s <i>Params</i> section and a mutation\'s <i>Effect</i> section now show the knobs the Salt (<code>SaltShaker</code>), the Frisbee (<code>Frisbee</code>) and the basketball\'s new mechanisms read as fields, one per knob, each with a <b>?</b> that says what it does. An empty box shows in grey what applies without it and where that comes from (the weapon\'s own value for a mutation, else the game\'s default). The JSON box stays under them for every other key; both write the same file.'),
      li('<b>Perks have a form</b>: on the Heroes tab, a hero\'s <i>His own</i> section lists his perks with <b>Edit</b> and <b>+ New perk…</b>. The perk form has Identity (name, hero, rarity, weight), Card (text, effects), Special (the mechanism and its numbers as fields) and Art (the icon, icon candidates).'),
      li('<b>Heroes to buy</b>: Availability now means what the game does (free · to buy · hidden), with the price, the currency and a <b>Requirement</b> (his unlock quest) right under it.'),
      li('<b>Icon candidates install from the item</b>: an item\'s <i>Art</i> section lists every finished icon candidate job of it (Rebound has three designs), each picture with <b>Install</b>.'),
      li('<b>The new passive items\' stats</b> are in the effect picker with a line each on what they do: <code>counter_damage</code>, <code>counter_haste</code>, <code>counter_speed</code>, <code>counter_seconds</code> (Counterpunch), <code>heavyweight</code>, <code>overheal</code> (Snake Oil), <code>heal_pulse</code> (Hot Springs), <code>last_stand</code>, <code>xp_pull_radius</code> and <code>xp_pull_rate</code> (the Magnet: a "word" stat, the card says "pulls more often", never a number).'),
      li('<b>Special enemies</b> (lane EN): an Enemies-tab section of their own (chance, size, HP ×, ATK ×, XP ×, colour, colour strength, glow), the map\'s <i>Coloured specials</i> in Settings, and a swarm event\'s <i>Special</i> box on the Timeline.'),
      li('<b>Level steps show their effects</b>: a weapon\'s or a passive item\'s <i>Levels</i> listed no effects before (and the first edit of one turned the list into an object); fixed, each level shows its effects with the card\'s words and what the stat does.'),
      li('<b>The quest-locked band</b> the Items tab shows now wants 28-56% (pass44_test was re-pinned when the Salt, the Frisbee and five passive items came unlocked: 23 of 75).')));

    how('Make a weapon like the Salt or the Frisbee, and tune its patches or its arcs', 'A new weapon starts as a copy of another: its behaviour (the code that fires it) comes with it, so copy the Salt for patches on the ground and the Frisbee for curving discs.', ol(
      'Items tab → <b>+ New from template ▾</b> → Kind <i>a weapon</i> → Template <b>Salt</b> (or <b>Frisbee</b>) → a Name (the id follows) → <b>Create</b>. It is created hidden with three template mutations and a template evolution, all hidden.',
      'Base stats: for the Salt, <i>damage</i> is a tick\'s damage, <i>cooldown</i> the seconds between pours, <i>amount</i> the patches each pour lays, <i>area</i> × the patch size, <i>duration</i> the seconds a patch lies. For the Frisbee: damage, cooldown, amount (discs a volley), speed, range (it always flies its whole range), knockback.',
      'Params → the typed groups. Salt: <i>Salt patches</i> (radius, tick, spacing, most patches, colour, opacity, the shaker\'s contents, the × knobs the mutations use) and <i>The floating shaker</i> (distance, height, orbit speed, bob). Frisbee: <i>Flight</i> (bend, more bend per extra disc, fan, the drop-off a creature and its floor, cut radius, height, glide), <i>The disc</i> (look plain / razors / saucer, radius, size ×, colours, glow, spin, trail, haze), <i>Carry</i>, <i>Trick Shot and stun</i>, <i>The loop</i>.',
      'Levels: five steps, level 1 empty; give level 3 and 5 an <i>amount</i> +1 the way the two do (more patches, more discs).',
      'Evolution &amp; path → fill the three template mutations (each needs card text and an effect or a param) and name the evolution, then Availability → available (the server refuses while the path is not whole).',
      '<b>Save asset</b> writes the JSON and imports it. A new behaviour (not patches, not discs) needs code: ask Claude.'));

    how('Add a mutation, or hide one (Full Court Press)', 'A weapon\'s path is one mutation of each kind in play: element, volume, motion. Full Court Press was hidden in pass 69 and Alley-Oop took its volume slot.', ol(
      '<b>Hide</b>: Items tab → the weapon\'s card → the mutation\'s <b>Edit</b> → Availability → tick <b>Hidden</b> → <b>Save asset</b>. A hidden mutation is never offered; its file stays.',
      '<b>Add</b>: Items tab → <b>+ New from template ▾</b> → Kind <i>a mutation of a weapon</i> → Template: a mutation of the same weapon (its Weapon and Kind come with it) → Create. In its form set Kind to the slot it fills, write the Card text, then its Effects (stat changes) and/or its typed params.',
      'Only one non-hidden mutation of each kind: hide the one it replaces first (the weapon\'s Evolution &amp; path strip shows the three slots and warns on two of a kind).',
      'A hero mutation is Kind <i>hero</i> plus the Hero it belongs to; a hero on the title needs exactly one, on his favourite weapon.'));

    how('Give a mutation a ball or disc look', 'The look is params on the mutation, merged over the weapon\'s while it is held; the evolution\'s goes in its <code>final</code>.', ol(
      'A basketball mutation → Effect → <i>Ball colour (body and seams)</i>: <b>Body colour</b> paints the ball flat (Alley-Oop #0A4FA8 dark blue, Slam Dunk #141414 black), <b>Glow colour</b> and strength a faint glow, <b>Lit by the sky</b> no keeps a dark ball dark on the sand, <b>Seam colour</b> / <b>Seam glow</b> the seams (Slam Dunk\'s ember seams #FF5A14). <i>Heat on the ball</i> is how the Heat shows on the ball itself (glow, trail, flames, the beating halo at the top): no HUD gauge since pass 69.',
      'A Frisbee mutation → Effect → <i>The disc</i>: <b>Look</b> razors (Poison Razors\' blades round the rim) or saucer (the Flying Saucer), <b>Colour</b>, <b>Glow colour</b>, <b>Size ×</b> (Carry\'s 1.5), <b>Poison haze</b>.',
      'An evolution: Params → <b>Edit: params.final</b> (over the mutations) so its look wins over theirs; <i>its own params</i> are what plays under them.',
      'Empty boxes keep the weapon\'s look (the grey text says which); <b>Save asset</b>. The new icon: Art → <b>+ Icon candidates…</b>.'));

    how('Swap an icon for another candidate (Rebound\'s three designs)', null, ol(
      'Items tab → the item (Rebound: the basketball\'s card → Rebound → Edit) → <b>Art</b>.',
      'Under the icon, <i>Icon candidates</i> lists every finished candidate job of the item: Design A, B, C, each with its pictures. Click a picture to choose it (double-click to see it big), then <b>Install</b>.',
      'Install is a job on the local lane: the picture becomes <code>&lt;id&gt;_icon.png</code> (the old one backed up) and is imported. Every design stays listed, so you can swap again later. ↻ asks the queue again; more designs: <b>+ Icon candidates…</b> with other words.'));

    how('Tune special enemies: colour, glow, strength', 'A special is a creature rolled bigger, tougher and coloured (pass 69: three times rarer, ATK × 2; pass 72: size × 1.5, HP × 15, a chest on its death at 0.35, at most 3 alive at once).', ol(
      '<b>One creature</b>: Enemies tab → the creature → <b>Special</b>: Chance (0.04 = one in 25, after the map\'s Colour after kills), Size ×, HP ×, ATK ×, XP ×, <b>Colour</b> (the picker: the wash and the glow\'s hue; a dark, saturated one reads best), <b>Colour strength</b>, <b>Glow</b> (0 none … 1 the widest rim), <b>Chest chance</b> (pass 72: 0.35 = about one in three of their deaths drops a chest). The table under it says what applies and whether it is the creature\'s own, the map\'s or the game\'s; the two pictures are a plain one and its special. <b>Save asset</b>.',
      '<b>Every creature at once</b>: Settings → <b>Coloured specials</b>: the map\'s numbers for any box a creature leaves empty. Every creature leaves Glow and Chest chance empty today, so those two here are the knobs for all of them. <b>Max alive</b> (pass 72, 3; 0 = no limit): past it a creature that rolled its special comes plain, a swarm set to Special still brings one. Save (the map).',
      'A roster row, wave or event can override them for its creatures: the inspector\'s Elite group → Special glow and the rest.'));

    how('Place, move or delete a special at a set second (the Goblin moment)', 'Red Canyon\'s "Special Goblin" is a swarm event of Count 1 with <b>Special</b> ticked at 2:00, where the first roster row ends (its creature is the red goblin, the green goblin being retired).', ol(
      '<b>Place</b>: Timeline → the Events lane\'s <b>+ Event</b> → <i>Swarm</i> → Creature, <b>Count 1</b>, Pattern (In front: from the top of the screen), tick <b>Special</b>. The note under the box says the numbers it will come with. No SWARM! banner shows for a special swarm.',
      '<b>Move</b>: drag its star along the lane (it snaps to the ends of rows and waves; hold Alt to drag freely), or type its time in the inspector; the arrow keys nudge it a second (Shift: ten).',
      '<b>Delete</b>: click it, then the Delete key or the inspector\'s <b>Delete</b>. <b>Save</b> (Ctrl+S) writes the map.'));

    how('Set a hero\'s price and unlock requirement', null, ol(
      'Heroes tab → the hero → <b>Availability</b> → Availability <b>to buy</b> → <b>Price</b> (whole gold) → Currency gold → <b>Save asset</b>.',
      '<b>Requirement</b> (under it) → <b>+ Add a requirement</b> (or <b>Edit requirement</b>) → Condition (kill the stage boss, kills in all, survive minutes, reach a level, extract after a stage, ...) and its numbers → <b>Create requirement</b>. It writes <code>content/quests/unlock_&lt;hero&gt;</code> at once (unlocks {type character}) and shows the words the title will show ("Kill 2,500 creatures, all time.").',
      'Until the requirement is done the hero is a black silhouette called "Unknown" with the requirement over his plaque; then BUY appears over him for the price; bought, he is kept in the save (<code>heroes_owned</code>). <b>Remove requirement</b> puts him on sale at once.',
      'The numbers in play: Calavera 300 (kill the Tumbleweed King), Ironwood 400 (2,500 kills), Solenne 600 (extract after stage 2), Jeżyk 500 (survive 15 minutes), May 700 (level 30), Fadeaway 50 (no requirement), Mira 9,999 (99,999,999 kills: out of reach on purpose).'));

    how('Make a hero free, to buy, or hidden', null, ol(
      'Heroes tab → the hero → Availability: <b>free</b> (his from the start; with a requirement, his once it is done, nothing to pay), <b>to buy</b> (on the title, locked until his requirement, then BUY), <b>hidden</b> (out of play: not on the title or in the hero drawer; his perks and hero mutation hidden too). The Hidden box follows it.',
      'A hero on the title (free or to buy) must be whole: at least one perk and exactly one hero mutation on his favourite weapon (the form warns otherwise).',
      '<b>Save asset</b>. The developer menu\'s "Heroes · own every one" lets you play any of them while testing.'));

    how('Give a hero a perk with the decoy special (Inflatable May)', 'A perk\'s <i>special</i> is a mechanism the game runs; its numbers are fields. <b>decoy</b> and <b>periodic_buff</b> work on any perk; the others are checked by their own perk\'s id in the game, so a copy under a new id keeps the numbers but never fires (the form warns): ask Claude for those.', ol(
      'Heroes tab → the hero → <b>His own</b> → <b>+ New perk…</b> → Template <b>Inflatable May</b> → a Name → <b>Create</b>. The perk is his (Hero), with the decoy special and its numbers.',
      'In the perk form → <b>Special</b>: every (seconds between throws), first (to the first throw), throw min / max (how far the doll lands), flight, radius (the circle: everything inside goes for the doll, Elites too, never a boss; keep it under half a screen, 6.5 m), duration (how long the doll stands before it pops). Empty = the game\'s default in grey.',
      'Card → the card text with your numbers; Identity → rarity and weight among his cards. <b>Save asset</b>. The doll\'s picture is May\'s (<code>content/characters/may/may_decoy.png</code>) for any hero today.',
      'An existing perk: His own → its <b>Edit</b>.'));

    how('Make a run driver with level shoulders (or a sprint, or a dash)', 'Garry: "a couple of weird frames where the shoulder of the hero is higher than it\'s supposed to be ... for Fadeaway in particular the shoulders look very sagged". The cause was the driver: its neck sits above the shoulder line. Lane ART\'s levelled drivers are in the library: <code>run_side</code> (the side view), <code>run_spread_lvl</code> (the back views), <code>run_lvl</code>, the sprint <code>run_sprint_lvl</code> and the dash <code>run_dash_lvl</code>.', ol(
      'Heroes tab → the hero → <b>Art words</b> (or a look\'s typed recipe) → <i>Driver: side</i> / <i>back</i> / ... pick a levelled driver per view, or:',
      '<b>+ New pose driver…</b> (under the drivers) → src: a Mixamo FBX or an upload → name → frames 24 (a hero run) → <b>amp</b> 1.35 and <b>lean</b> 12 for a sprint, <b>arms</b> back and lean 14 for a dash → <b>shoulders</b> 0.3 with <b>shoulder_views</b> back,bd (the back driver) or side,fd and <b>tuck</b> 25 (the side driver) → Queue. It makes <code>&lt;name&gt;</code> and the levelled <code>&lt;name&gt;_lvl</code>; use the _lvl one.',
      'Then queue the look (next how-to) with those drivers in its recipe.'));

    how('Queue a new hero look with badge and cut-out candidates', null, ol(
      'Heroes tab → the hero → <b>Looks &amp; previews</b> → <b>+ New look…</b> → pick the method (a pose-driven run for a hero) → its recipe (the drivers per view: the levelled ones of the how-to above) → the words.',
      'A new look comes with at least <b>3 badge candidates and 3 title cut-out candidates</b>: jobs of their own queued right after the look with the same settings, their words and reference filled from the look (each tagged with where it came from). Queue refuses fewer than 3; raise the counts for more choice.',
      'Jobs tab: the look paints, then waits for picks; the badge and cut-out jobs end in <b>Install</b> on the picture you like (it lands in that look: its own badge and cut-out).',
      'Back on the hero: the new look card has a NEW chip: play it (hover), <b>Approve</b> it.'));

    how('Pick the look a hero is played in', null, ol(
      'Heroes tab → the hero → Looks &amp; previews → the look\'s card → <b>Make default</b>: written into his JSON as <code>variant</code> and imported; the badge and the title follow the look he is played in.',
      '<b>Shelve</b> the looks you do not want offered (the deer looks of Jeżyk once his tracksuit look plays); the look in play cannot be shelved. In the game the arena\'s look chips (debug mode) try any look without changing the file.'));
  }

  // ------------------------------------------------------------------ pass 68: drafts, candidates with their defaults, the queue order (lane W)

  function pass68(root) {
    root.appendChild(el('h2', { text: 'Pass 68: drafts, candidates and the queue order' }));
    root.appendChild(p('Garry: "Duplicate must not start generating: it makes a copy I edit, and a button starts the paint" · "a new look must always come with icon and cut-out candidates, at least 3 each" · "the hero\'s description already there by default, and a reference picture for consistency" · "the upcoming jobs at the top".'));
    root.appendChild(el('ul', {},
      li('<b>Duplicate…</b> on a look card makes a <b>draft</b>: a new code with the source\'s recipe copied (its method recorded, its painter kept, <code>from</code> naming the source) and nothing painted. The draft is selected and its typed recipe opens under the grid; change what you like and <b>Save asset</b>. A draft card has a purple <i>draft</i> chip and a primary <b>Generate…</b>, which saves the document first if it has unsaved changes, then opens the job form for that code as a new look (its Model settings from the recorded painter, and a box "reuse &lt;source&gt;\'s paintings"). A stub whose job failed or was cancelled is a draft too.'),
      li('<b>A new look comes with its candidates</b>: <b>+ New look…</b> and Generate… show, under Looks, <i>icon candidates</i> (a creature) or <i>badge candidates</i> and <i>title cut-out candidates</i> (a hero), each 3 by default and at least 3: Queue refuses fewer. They are jobs of their own queued right after the look with the same Model settings; the server fills their words and takes the new look\'s front still as the reference. A recolour and a front from a picture need none. On a re-roll they are optional.'),
      li('<b>Badge, title cut-out and icon candidates</b> show what will be sent, filled in and editable: <i>Character</i> (the look\'s <code>appearance</code>, else its art_prompt with the pose clause cut), <i>Action</i> (the badge: portrait_prompt), <i>Pose</i>, <i>Holds</i> and <i>Camera</i> (the title: title_pose, title_holds, title_camera), the <i>Reference picture</i> (the look\'s own front still by default, with a thumbnail, <b>Change…</b> for the picture library and <b>Upload…</b>) and the title\'s <i>Extra reference</i>; a small tag on each says where its value came from. A hero\'s icon is the round badge: the hero page\'s and the hero look cards\' buttons open badge candidates, never square icon candidates. The candidates of a look land in that look (its own icon, its own cut-out); the base look\'s go to the hero\'s own files.'),
      li('<b>The form is honest</b>: the 2D / 3D reference rows are gone (no tool read them); each method says where its picture goes instead ("this method paints from words: to start from a picture, use the front from a picture first"; gen_ctl: look_ref; front from a picture: its Reference picture). The re-roll choices now reach the server (<code>spec.reroll</code>); when a re-roll\'s Model settings differ from the painter the look recorded, <i>repaint the stills</i> is selected, since a painter only paints stills; <i>redo one view</i> shows for gen_ctl only.'),
      li('<b>Where the pictures show in the game</b>: a look\'s <i>badge</i> is what the hero sheet, the results, the Collection and the arena show for it (the look the hero is played in); its <i>title cut-out</i> shows on the Painted title only (Settings, debug mode: Main menu → Painted): the Live title, the default, draws the look\'s strip instead.'),
      li('<b>The painter line</b> says when the stills were reused rather than painted ("stills reused from earlier paintings: this painter painted none of them", or "3 of 12 painted"), and a job card\'s stages say <i>cached</i> for what was on disk already.'),
      li('<b>The Jobs tab</b> lists <b>Up next</b> first, in the order the workers take the jobs (by lane: comfy, godot, local; within a lane the queue\'s order, a picked job resuming first), each card numbered in its lane ("#1 of 3 in the comfy lane · next"), then Waiting for a pick, Running and Finished. ▲ ▼ move a job within its lane.')));
  }

  // ------------------------------------------------------------------ pass 66: the asset editors, the looks, the art jobs, the Jobs tab (lane V)

  let demo = [];          // the strip players of this tab's demo, destroyed on the next render
  let assetsSchema = null; // docs/assets_schema.md as served, once fetched (null = not yet, '' = not served)

  function pass66(root) {
    for (const p of demo) p.destroy();
    demo = [];
    root.appendChild(el('h2', { text: 'Pass 66: the asset editors' }));
    root.appendChild(p('The editor now edits the <b>assets</b> themselves, not only when they come: <b>Enemies</b> (the palette, and an editor for every creature, elite and boss), <b>Heroes</b> and <b>Items</b> (weapons with their mutations and evolutions, cards (the line items, pass 73) with their Risen forms and their looks, passive items), each a form over the asset\'s own JSON under <code>game/content/</code>; plus <b>Jobs</b>: the local AI\'s queue that paints new looks, icons, badges and title cut-outs. Garry: "I go to our LevelEditor HTML and I choose to either edit or create an Enemy, Hero or Item ... Heroes and Items should get their own tabs with inclusion of everything we already have in the game at the proper status, stats, and everything that\'s true to what\'s in the game right now."'));
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
    root.appendChild(p('A <b>look</b> is one painted strip of a creature or a hero (its icon too, for a creature): the JSON\'s <code>variants[CODE]</code>. The <b>Looks</b> section of an enemy or a hero shows every look as a card with a live preview (hover it to play, click it for the player above, double-click for the close look), the chips <i>● default · NEW · shelved · not imported · stub · draft</i>, its note, and the actions <b>Make default</b> (the look the game plays for every row that names none), <b>Approve</b> (you looked at it: clears NEW), <b>Shelve / Unshelve</b> (kept in the JSON, hidden from the arena chips and the default lists), <b>Remove</b> (the entry goes; its PNGs move to <code>tools/level_editor/backups/deleted/</code>), <b>Edit note / recipe</b> (the raw JSON), <b>Recipe (typed)…</b> (every field of the method with its source: <i>own</i>, <i>inherited</i> from the creature\'s own art words, or the method\'s <i>default</i>; a look with no recipe recorded says so, and keys the form has no row for are listed), <b>Re-roll…</b>, <b>Duplicate…</b> (since pass 68 a <i>draft</i>: a new code with this recipe, nothing painted until <b>Generate…</b> on the draft) and <b>Icon candidates…</b> (a hero: <b>Badge candidates…</b> and <b>Cut-out candidates…</b>; these and Re-roll… open the job form). Each card also names its method, how many keys its recipe holds of its own and the painter it ran with (<code>variants[CODE].recipe.painter</code>: the model and the passes, written by every look job). A recipe keeps only what differs from the creature\'s own art words: an empty field inherits, it is not lost. The pane\'s header stays pinned while you scroll and carries the look\'s icon and the name, so the asset being edited is always in view. Built for fifty looks of one creature: a filter box, a status filter, pages of 24, ☐ select with bulk Shelve / Unshelve / Remove.'));
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
      li('<b>Re-roll</b> (pass 68: the choice reaches the server as <code>spec.reroll</code>): <i>new seeds</i> paints the stills again under new seeds and makes the clips again from them; <i>keep the stills, redo the clips</i> moves the clip folders to <code>&lt;key&gt;_old&lt;stamp&gt;</code> and makes the walks again; <i>redo one view</i> paints candidates of that view to pick from (gen_ctl only); <i>repaint the stills</i> paints them again and keeps the clips (walked from the old stills). A look that shares the creature\'s or the hero\'s paintings gets its own first, so those are never touched. Without a re-roll, cached work is reused.'),
      li('<b>Where things live</b>: stills <code>tools/dl/ai_raw_anime/&lt;key&gt;.png</code> (+ <code>.json</code> with the seed, the prompt, the refs, the QA verdict); clips <code>tools/dl/ai_anim/&lt;key&gt;/</code> (<code>out_NN.png</code> the kept frames, <code>cycle_sheet.png</code>); review sheets <code>tools/dl/review/</code>; icon candidates <code>tools/dl/icons_le_&lt;job&gt;/</code>; title candidates <code>tools/dl/title_heroes/</code>; uploads <code>tools/dl/uploads/2d|3d/</code>; the queue and every job\'s log <code>tools/dl/jobs/</code>. A finished look lands in the content folder as <code>&lt;id&gt;_sprite_&lt;letter&gt;.png</code> (+ <code>_icon_</code>) and in the JSON as <code>variants[CODE]</code> marked NEW; a job that could not merge its result into a hand-edited file ends done with <i>unmerged</i> and the card offers "Merge again" and "Re-dump this file (changes its layout)".'),
      li('<b>What a picture cannot do</b>: a 2D reference reaches the front still of a creature (or the side, for the 3D-control method); the other views are edits of that painting; motion comes from a driver or Wan\'s guess, never from a picture; the vision QA counts subjects, legs and views, never likeness. The authoritative words are what <code>tools/asset_job.py --dry-run</code> records.')));

    root.appendChild(el('h2', { text: 'The Jobs tab' }));
    root.appendChild(p('Garry: "a list of jobs that are in queue for the local AI, which are being worked on and as much detail about those jobs as possible ... cancel the jobs and edit them (while they are not running, obviously) ... add as many as I like." The tab asks the server every 2 s (6 s from other tabs, nothing while the page is hidden) and draws a card per job, grouped by state:'));
    root.appendChild(el('ul', {},
      li('<b>RUNNING</b>: the stage and the stages done, the elapsed time against a "~" estimate (the method\'s measured median × its stages: a Flux.2 dev restart can add minutes), the last 12 log lines, <b>Cancel</b> (kills the tool; a ComfyUI job also interrupts the server\'s queue, which holds only ours under the lock), <b>Open asset</b>, <b>Log</b>. "stalled" after 20 minutes of silence: never killed on its own.'),
      li('<b>WAITING FOR PICK</b>: the candidates (click a picture to zoom, click a card to choose), <b>Pick</b>, <b>Re-roll N more</b>, <b>Cancel</b>, <b>Edit</b> (back to the queue at phase 1).'),
      li('<b>UP NEXT</b> (listed first since pass 68, in the order the workers take them): its place in its lane ("#1 of 3 in the comfy lane · next"), <b>Edit</b> (the form again), ▲ ▼ within its lane, <b>Cancel</b>.'),
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
