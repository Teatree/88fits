'use strict';
// Pass 69 (lane LE): the Level Editor for what pass 69 added. Garry: "When making changes to Items along the way, make
// sure to update the LevelEditor and include instructions on how I would be able to use the newly created tools in the
// future" (and the same for heroes). Four pieces, each a function the existing forms call:
//   TypedForms.params(doc, def)       the typed params of a weapon, an evolution or a mutation (AFIELDS.PARAM_GROUPS:
//                                     the Salt's patches and shaker, the Frisbee's flight, disc, carry, Trick Shot and
//                                     loop, the ball's launch, Heat look and colour, Trigger Happy's nonstop fire), each
//                                     box with what applies when it is empty and where that comes from;
//   TypedForms.perkParams(doc, def)   a perk's special's numbers (AFIELDS.PERK_SPECIALS: the decoy's, Buzzer Beater's...);
//   TypedForms.perkEditor(pane, doc)  the perk form on the Heroes tab (Identity, Card, Special, Art);
//   TypedForms.requirement(doc)       a hero's requirement: the quest whose unlocks is {type character, id}, written as
//                                     content/quests/unlock_<hero> through the availability op;
//   TypedForms.iconCandidates(doc)    an item's (or a perk's) finished icon candidate jobs with Install on each picture
//                                     (Rebound's three designs).
const TypedForms = (() => {
  const { el, clear } = U;
  const M = AssetsModel, F = AFIELDS;

  const fmt = (v) => (v == null || v === '' ? '—' : typeof v === 'boolean' ? (v ? 'yes' : 'no') : typeof v === 'number' ? M.plain(v) : typeof v === 'object' ? JSON.stringify(v) : String(v));
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  // ------------------------------------------------------------------ typed params (weapons, evolutions, mutations)

  /** The behaviour that reads a document's params, its weapon family's params (a mutation's weapon) and its name. */
  function familyOf(doc, o) {
    const fl = Assets.flatItems();
    if (doc.kind === 'mutation') {
      const w = fl ? fl.weapons.find((x) => x.id === doc.data.weapon) : null;
      return { behavior: String(doc.data.behavior || (w && w.behavior) || (o && o.behavior) || 'ProjectileEmitter'), params: w && M.isObj(w.params) ? w.params : {}, name: w ? (w.name || w.id) : String(doc.data.weapon || 'its weapon'), weapon: w };
    }
    return { behavior: String(doc.data.behavior || 'ProjectileEmitter'), params: null, name: '', weapon: null };
  }

  /** One typed row: the control for `full` (a path in doc.data), the inherited value as its placeholder, and a hint that
   *  says what applies without the box and where it comes from (memory: show effective values with their source). */
  function paramRow(doc, r, full, inherit) {
    const val = U.getPath(doc.data, full);
    const [inh, src] = F.paramInherited(r, inherit);
    const write = (v) => Assets.apply(doc, () => U.setPath(doc.data, full, v), 'editor');
    const ph = inh == null ? '' : inh;
    // pass 70: a value inherited from another item (a mutation's weapon, an evolution's own params) is IN the box,
    // marked, editable in place (Forms.inheritable); the game's own default stays the placeholder (it is a default)
    const isInherited = inh != null && typeof inh !== 'object' && !/default|none: off/.test(String(src || ''));
    const inhBox = isInherited ? { value: inh, from: src } : null;
    let ctl;
    switch (r.type) {
      case 'int': case 'number': ctl = Forms.numberInput({ key: full, min: r.min, max: r.max, step: r.step, int: r.type === 'int' }, val, write, { path: full, placeholder: ph, inherit: inhBox }); break;
      case 'swatch': ctl = Forms.swatchInput(val, write, { path: full, placeholder: typeof ph === 'string' ? ph : '' }); break;
      case 'bool3': ctl = Forms.bool3Input({ key: full }, val, write, { path: full, placeholder: inh == null ? 'off' : (inh ? 'yes' : 'no') }); break;
      case 'select': ctl = Forms.select(r.options || [], val == null ? '' : val, (v) => write(v == null || v === '' ? null : v), { emptyLabel: `— (${fmt(inh)})`, path: full }); break;
      case 'sfx': ctl = Assets.sfxSelect(doc, { key: full, group: r.group || 'w_' }); break;
      default: ctl = Forms.textInput({ key: full }, val, write, { path: full, placeholder: ph === '' ? '' : String(ph), inherit: inhBox });
    }
    const inBox = !!inhBox && ['int', 'number', 'text', undefined].includes(r.type);
    const hint = val == null
      ? el('span', { class: 'muted small pghint' + (inBox ? ' inh' : ''), text: inh == null ? (r.emptyText || `empty = ${src}`) : (inBox ? `inherited from ${src}: edit it here to make it this one's own` : `empty = ${fmt(inh)} (${src})`) })
      : el('span', { class: 'muted small pghint set', text: inh != null && !same(val, inh) ? `set here (${src}: ${fmt(inh)})` : 'set here' });
    if (inBox) ctl.addEventListener('inheritchange', (e) => { hint.textContent = e.detail && e.detail.own ? `set here once you leave the box (${src}: ${fmt(inh)})` : `inherited from ${src}: edit it here to make it this one's own`; });
    const row = Forms.row({ key: full, label: r.label, help: r.help }, ctl, { after: hint });
    row.dataset.key = full;
    return row;
  }

  /** The typed params row of a weapon / evolution / mutation form (`params_fields`): null when its behaviour has no
   *  typed group (the JSON box below stays the editor for those). */
  function params(doc, def, o) {
    const fam = familyOf(doc, o);
    const own = M.isObj(doc.data.params) ? doc.data.params : {};
    const isEvo = doc.kind === 'evolution' || !!doc.data.is_evolution;
    const target = isEvo ? (doc.ui.pgTarget || (M.isObj(own.final) ? 'final' : 'own')) : 'own';
    const base = target === 'final' ? 'params.final.' : 'params.';
    const block = target === 'final' ? (M.isObj(own.final) ? own.final : {}) : own;
    // where an empty box's value comes from: a mutation's weapon; an evolution's final block reads its own params first
    const inherit = doc.kind === 'mutation' ? [[fam.params, `the ${fam.name}'s params`]] : target === 'final' ? [[Object.assign({}, own, { final: undefined }), 'its own params']] : [];
    const family = doc.kind === 'mutation' ? fam.params : own;
    doc.ui.pgOpen = doc.ui.pgOpen || {};
    const groups = F.paramGroupsFor(fam.behavior, block, family, doc.ui.pgOpen);
    if (!groups.length) return null;
    const wrap = el('div', { class: 'ptyped' });
    if (isEvo) {
      const pick = (t) => el('button', { class: 'btn small' + (target === t ? ' primary' : ' ghost'), type: 'button', text: t === 'final' ? 'params.final (over the mutations)' : 'its own params (under the mutations)', onclick: () => { doc.ui.pgTarget = t; Assets.redraw(doc, 'editor'); } });
      wrap.appendChild(el('div', { class: 'pgtarget' }, el('span', { class: 'muted small', text: 'Edit:' }), pick('final'), pick('own'),
        el('span', { class: 'muted small', text: 'an evolution plays its own params, then its weapon\'s path mutations\' params merged over them, then params.final last: the "all three, amplified" numbers live in final.' })));
    }
    if (doc.kind === 'mutation') wrap.appendChild(el('div', { class: 'muted small', text: `${fam.behavior}: the ${fam.name}'s value is in each box (italic, dashed, "inherited from"): edit it in place to give the mutation its own, empty it to inherit again; a value of its own is merged over the ${fam.name}'s while the mutation is held; a box you did not change writes nothing.` }));
    const offers = [];
    for (const { group: g, on, set } of groups) {
      if (!on) {
        const offerable = g.show === 'set' || (g.show === 'family' && (F.isBall(block) || F.isBall(family)));
        if (offerable) offers.push(g);
        continue;
      }
      const id = 'pg:' + g.id;
      const det = el('details', { class: 'pgroup', 'data-group': g.id });
      det.open = doc.ui.open[id] == null ? true : !!doc.ui.open[id];
      det.addEventListener('toggle', () => { doc.ui.open[id] = det.open; });
      const nSet = g.rows.filter((r) => U.getPath(doc.data, base + r.key) != null).length;
      det.appendChild(el('summary', {}, el('b', { text: g.label }), el('span', { class: 'achip', text: nSet ? `${nSet} set here` : 'nothing set here' }), el('span', { class: 'muted small', text: ` ${g.src}` })));
      det.appendChild(el('p', { class: 'muted small pghelp', text: g.help }));
      for (const r of g.rows) det.appendChild(paramRow(doc, r, base + r.key, inherit));
      if (!set && doc.ui.pgOpen[g.id]) det.appendChild(el('button', { class: 'btn small ghost', type: 'button', text: 'Fold this group away', onclick: () => { delete doc.ui.pgOpen[g.id]; Assets.redraw(doc, 'editor'); } }));
      wrap.appendChild(det);
    }
    if (offers.length) {
      wrap.appendChild(el('div', { class: 'pgoffers' }, el('span', { class: 'muted small', text: 'More typed params this weapon\'s behaviour reads:' }),
        offers.map((g) => el('button', { class: 'btn small', type: 'button', text: `+ ${g.label}`, title: g.help, onclick: () => { doc.ui.pgOpen[g.id] = true; Assets.redraw(doc, 'editor'); } }))));
    }
    return wrap;
  }

  // ------------------------------------------------------------------ a perk's special and its numbers

  function specialTable() { return F.perkSpecialTable({ vocab: Assets.vocab() }); }

  function perkParams(doc) {
    const sp = String(doc.data.special || '');
    const spec = specialTable()[sp];
    const wrap = el('div', { class: 'ptyped' });
    if (!spec) { wrap.appendChild(el('div', { class: 'ferr warn', text: `the game runs nothing for "${sp}": only the effects count (a new mechanism needs code: ask Claude)` })); return wrap; }
    wrap.appendChild(el('p', { class: 'muted small pghelp', text: `${spec.by === 'id' ? 'That perk only (the game checks the perk\'s id): ' : 'Any perk can carry it: '}${String(spec.help || '').replace(/`/g, '')}` }));
    if (spec.by === 'id' && sp && sp !== doc.id) wrap.appendChild(el('div', { class: 'ferr warn', text: `the game fires "${sp}" only for the perk whose id is ${sp}; this one (${doc.id}) has the numbers but the mechanism never fires: ask Claude, or give it an "any perk" special (decoy, periodic_buff)` }));
    const keys = Object.keys(spec.params || {});
    if (!keys.length) { wrap.appendChild(el('div', { class: 'muted small', text: sp ? 'it has no numbers' : 'no special: the effects above are the whole perk' })); return wrap; }
    const help = F.PERK_PARAM_HELP[sp] || {};
    for (const k of keys) {
      const full = 'params.' + k;
      const dflt = spec.params[k];
      if (k === 'buff') {
        wrap.appendChild(Forms.row({ key: full, label: 'Buff', help: help[k] || 'the effects of the buff' }, Assets.statEffects(doc, { key: full, stats: 'player', target: 'player' }), { cls: 'wide-ctl' }));
        continue;
      }
      if (dflt == null && k !== 'first') {
        // a word or a list (a pickup id, the pod's drops): text, or the JSON box below for a list
        const cur = U.getPath(doc.data, full);
        if (Array.isArray(cur) || k === 'drops') { wrap.appendChild(Forms.row({ key: full, label: k, help: help[k] || '' }, el('span', { class: 'muted small', text: `${fmt(cur)} (a list: edit it in Params (JSON) below)` }), {})); continue; }
        wrap.appendChild(paramRow(doc, { key: k, label: k, type: 'text', def: null, help: help[k] || '' }, full, []));
        continue;
      }
      wrap.appendChild(paramRow(doc, { key: k, label: k.replace(/_/g, ' '), type: 'number', def: dflt, min: 0, step: 'any', emptyText: dflt == null ? 'empty = the same as every' : '', help: help[k] || `${sp}: ${k} (the game's default ${fmt(dflt)})` }, full, []));
    }
    return wrap;
  }

  /** The perk form (the Heroes tab): Identity, Card, Special, Art, with a way back to his hero. */
  function perkEditor(pane, doc) {
    const iss = Assets.issuesOf(doc);
    const defs = F.perk;
    pane.appendChild(Assets.header(doc, iss));
    const hero = String(doc.data.hero || '');
    if (hero) pane.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small ghost', type: 'button', text: `← ${hero}`, title: 'his hero form', onclick: () => Assets.open('hero', hero) }),
      el('span', { class: 'muted small', text: 'A perk is a card only his hero is offered, taken once: its effects go on his sheet, its special is a mechanism the game runs, tuned by its numbers (Run.perk_param).' })));
    for (const name of F.SECTIONS.perk) {
      const nodes = Assets.rows(doc, defs, name, iss);
      if (name === 'Art') { const ic = iconCandidates(doc); if (ic) nodes.push(ic); }
      pane.appendChild(Assets.section(doc, name, nodes, { open: name !== 'Art', marks: Assets.sectionMarks(iss, Assets.sectionKeys(defs, name)) }));
    }
  }

  /** "+ New perk" for a hero: the create dialog over the perks as templates, the new one naming this hero. */
  function newPerkDialog(heroDoc, host, onDone) {
    const hs = Assets.S.lists.heroes || [];
    const perks = [];
    for (const h of hs) for (const p of h.perk_records || []) perks.push(p);
    const tSpecial = specialTable();
    const templates = perks.map((p) => ({ v: p.id, label: p.name || p.id, icon: p.icon || `/icon/perk/${p.id}`, sub: `${p.id} · ${p.hero} · ${p.special || 'effects only'}${tSpecial[p.special] && tSpecial[p.special].by === 'special' ? ' · any perk can carry it' : ''}` }));
    const taken = new Set(perks.map((p) => p.id).concat(hs.map((h) => h.id)));
    const fl = Assets.flatItems();
    if (fl) for (const list of [fl.weapons, fl.evolutions, fl.mutations, fl.passives, fl.quests]) for (const x of list) taken.add(x.id);
    const who = String(heroDoc.data.name || heroDoc.id);
    const box = Assets.createDialog('perk', templates, taken, {
      label: `perk for ${who}`, docRequired: false, copyArt: false, fields: { fields: { hero: heroDoc.id } },
      note: `A copy of the template's numbers, text and special, ${who}'s own (its Hero is ${heroDoc.id}). Inflatable May (decoy) and Buzzer Beater (periodic_buff) are the specials any perk can carry; the others fire only for their own perk's id. A placeholder icon comes with the register job.`,
      onCreate: async (body) => { const d = await Assets.create('perk', body); if (d && onDone) onDone(); },
      onCancel: () => { clear(host); if (onDone) onDone(); },
    });
    // a perk has no Collection doc line: the dialog's Doc row is a creature's
    const docRow = box.querySelector('[data-path="create.doc"]');
    if (docRow && docRow.closest('.frow')) docRow.closest('.frow').remove();
    return box;
  }

  // ------------------------------------------------------------------ a hero's requirement (his unlock quest)

  function questWords(q) {
    const fl = Assets.flatItems();
    const nm = {
      weapon: (id) => { const w = fl && fl.weapons.find((x) => x.id === id); return w ? (w.name || id) : String(id || ''); },
      enemy: (id) => { const c = typeof App !== 'undefined' && App.creature ? App.creature(id) : null; return c ? (c.name || id) : String(id || ''); },
      // pass 100 (lane QUESTS): the build quests name a hero and an item (weapon, card, passive item, with its evolution)
      hero: (id) => { const h = (Assets.S.lists.heroes || []).find((x) => x.id === id); return h ? (h.name || id) : ''; },
      items: fl ? { weapons: fl.weapons.concat(fl.evolutions || []), passives: fl.passives, mutations: fl.mutations || [] } : null,
    };
    return M.questText(q, nm);
  }

  /** The Availability section's requirement block: what gates him (his quest in the game's words), Edit / Remove / Add,
   *  and what the title shows for each state. Written at once through the availability op (not by Save). */
  function requirement(doc) {
    const rec = Assets.listRecord(doc) || {};
    const q = doc.quest || rec.quest || null;
    let saved = {};
    try { saved = JSON.parse(doc.saved); } catch (_) { saved = {}; }
    const savedAvail = saved.availability || (saved.hidden ? 'hidden' : 'available');
    const av = doc.data.availability || (doc.data.hidden ? 'hidden' : 'available');
    const draft = doc.ui.reqDraft;
    const wrap = el('div', { class: 'frow wide-ctl', 'data-key': 'requirement' });
    wrap.appendChild(el('label', { class: 'flabel', text: 'Requirement', title: 'a quest whose unlocks is {type: character, id: ' + doc.id + '} (content/quests/unlock_' + doc.id + '): the hero stays locked (a black silhouette with these words over the plaque) until it is done' }));
    const ctl = el('div', { class: 'fctl' });
    if (q && !draft) {
      ctl.appendChild(el('div', { class: 'small' }, el('b', { text: `"${questWords(q)}"` }), el('span', { class: 'muted small', text: ` · ${q.id} (${(q.condition && q.condition.type) || '?'})` })));
      ctl.appendChild(el('div', { class: 'alt-actions' },
        el('button', { class: 'btn small', type: 'button', text: 'Edit requirement', onclick: () => { doc.ui.reqDraft = JSON.parse(JSON.stringify(q)); Assets.redraw(doc, 'editor'); } }),
        el('button', { class: 'btn small danger', type: 'button', text: 'Remove requirement', title: 'the quest file moves to the backups: a free hero is owned from the start, a hero to buy goes on sale at once', onclick: () => { if (confirm(`Remove ${q.id}? ${doc.id} needs nothing any more.`)) Assets.availabilityOp(doc, { availability: savedAvail, quest: null }); } })));
    } else if (!draft) {
      ctl.appendChild(el('div', { class: 'small muted', text: av === 'hidden' ? 'none (hidden: nothing to unlock)' : av === 'purchase' ? 'none: on sale at once (BUY on the title)' : 'none: owned from the start' }));
      ctl.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small', type: 'button', text: '+ Add a requirement', onclick: () => { doc.ui.reqDraft = { id: `unlock_${doc.id}`, name: String(doc.data.name || doc.id), condition: { type: 'kills_total', count: 2500 }, unlocks: { type: 'character', id: doc.id } }; Assets.redraw(doc, 'editor'); } })));
    }
    if (draft) {
      const box = el('div', { class: 'qdrawer' });
      box.appendChild(el('div', { class: 'small' }, el('b', { text: draft.id || `unlock_${doc.id}` }), el('span', { class: 'muted small', text: ` · content/quests/${draft.id || 'unlock_' + doc.id}/ · reads: "${questWords(draft)}"` })));
      const localApply = (fn) => { fn(); Assets.redraw(doc, 'editor'); };
      for (const def of F.QUEST_ROWS) {
        if (typeof def.only === 'function' && !def.only(draft)) continue;
        const def2 = Object.assign({}, def);
        if (typeof def.options === 'function') def2.options = F.options(def, Assets.vocab());
        let rowEl;
        if (def.type === 'enemy') rowEl = Forms.row(def2, Forms.enemyPick(U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, v)), { path: 'req.' + def.key, summary: false, emptyLabel: '—' }), {});
        else if (def.type === 'id_select') rowEl = Forms.row(def2, Forms.iconSelect(((def.kind === 'hero' ? Assets.ensureHeroes() : null), Assets.idOptions(def.kind || 'weapon')) || [], U.getPath(draft, def.key) || '', (v) => localApply(() => U.setPath(draft, def.key, v)), { emptyLabel: '—', path: 'req.' + def.key }), {});
        else rowEl = Forms.fieldRow(def2, draft, { apply: (fn) => localApply(fn), pathPrefix: 'req' });
        box.appendChild(rowEl);
      }
      box.appendChild(el('div', { class: 'alt-actions' },
        el('button', { class: 'btn small primary', type: 'button', text: q ? 'Save requirement' : 'Create requirement', title: 'writes content/quests/unlock_' + doc.id + ' at once and imports it (the hero JSON is not touched)', onclick: async () => { const ok = await Assets.availabilityOp(doc, { availability: savedAvail, quest: { condition: draft.condition, quest_text: draft.quest_text || '', name: draft.name || '' } }); if (ok) doc.ui.reqDraft = null; } }),
        el('button', { class: 'btn small ghost', type: 'button', text: 'Cancel', onclick: () => { doc.ui.reqDraft = null; Assets.redraw(doc, 'editor'); } })));
      ctl.appendChild(box);
    }
    // what the title shows for him, in words (Registry.hero_state)
    const price = Number(doc.data.price) || 0;
    const words = av === 'hidden' ? 'In play: hidden. Not on the title, not in the hero drawer; his perks and hero mutation are out of the card pool.'
      : av === 'purchase' ? `In play: on the title and in the hero drawer. ${q ? `Locked (a black silhouette, "Unknown", the requirement over the plaque) until "${questWords(q)}" is done, then` : 'On sale at once:'} BUY for ${price} ${doc.data.currency_type || 'gold'} over the preview; once bought the save keeps the hero (heroes_owned).`
        : `In play: free. ${q ? `Locked (a black silhouette with the requirement over the plaque) until "${questWords(q)}" is done, then owned, nothing to pay.` : 'Owned from the start.'}`;
    ctl.appendChild(el('div', { class: 'anote', text: words }));
    if (av !== savedAvail) ctl.appendChild(el('div', { class: 'muted small', text: `Availability changed to ${av} in the form: Save asset writes it (the requirement buttons write the quest only).` }));
    wrap.appendChild(ctl);
    return wrap;
  }

  // ------------------------------------------------------------------ an item's icon candidates (finished icon_cands jobs)

  async function install(job, choice) {
    App.status(`Installing ${choice} from ${job.id}…`, 'busy');
    let { status, data } = await Assets.postJSON(`/api/jobs/${encodeURIComponent(job.id)}/install`, { choice });
    // pass 76 (lane ICON): the item's own icon or the look in play asks first (now -> new), then goes with confirm: true
    if (data && data.confirm_needed && typeof LookGrid !== 'undefined' && LookGrid.confirmIconChange) {
      if (!(await LookGrid.confirmIconChange(data))) { App.status(`${job.id}: not installed, nothing changed`); return; }
      ({ status, data } = await Assets.postJSON(`/api/jobs/${encodeURIComponent(job.id)}/install`, { choice, confirm: true }));
    }
    if (!data || !data.ok) { App.status(`Could not install: ${(data && data.error) || status}`, 'bad'); return; }
    App.status(`Install of ${choice} queued (job ${(data.job && data.job.id) || ''}): the new icon gets a file of its own (the old one stays, Revert icon brings it back), then the import`, 'good');
    if (typeof Jobs !== 'undefined' && Jobs.poll) Jobs.poll();
  }

  /** The finished icon candidate jobs of this item, each picture with Install (pass 69: Rebound's three designs are three
   *  jobs; any one installs as the icon, and installing another later swaps it). Null when there are none. */
  function iconCandidates(doc) {
    if (typeof Jobs === 'undefined' || !Jobs.jobsFor) return null;
    const jobs = Jobs.jobsFor(doc.kind, doc.id).filter((j) => j.kind === 'icon_cands' && j.state === 'done' && Array.isArray(j.choices) && j.choices.length);
    const installs = Jobs.jobsFor(doc.kind, doc.id).filter((j) => j.kind === 'install');
    const wrap = el('div', { class: 'icands' });
    wrap.appendChild(el('div', { class: 'isub' }, el('b', { text: jobs.length ? `Icon candidates · ${jobs.length} job${jobs.length === 1 ? '' : 's'}` : 'Icon candidates' }),
      el('span', { class: 'muted small', text: jobs.length ? 'click a picture to choose it, then Install: it becomes this item\'s icon (the old one is backed up). Every design stays here, so you can swap later.' : 'none finished yet (+ Icon candidates… queues a job; the finished ones show here)' }),
      el('button', { class: 'btn small ghost', type: 'button', text: '↻', title: 'ask the job queue again', onclick: async () => { if (Jobs.poll) await Jobs.poll(); Assets.redraw(doc, 'editor'); } })));
    if (!jobs.length) return wrap;
    const lastInstall = installs.filter((j) => j.state === 'done').sort((a, b) => String(b.id).localeCompare(String(a.id)))[0];
    if (lastInstall) wrap.appendChild(el('div', { class: 'muted small', text: `last installed: ${(lastInstall.spec && lastInstall.spec.choice) || '?'} from ${(lastInstall.spec && lastInstall.spec.source_job) || '?'}` }));
    // the queue's own order (the order they were queued in: Rebound's A backboard, B return arrow, C catching hand)
    jobs.forEach((j, n) => {
      const subject = String((j.spec && j.spec.subject) || j.title || '');
      // pass 73 (lane CARDS): a job painted for a look (a card's B-E) says so; its Install lands in that look
      const code = j.target && j.target.code ? String(j.target.code) : '';
      const box = el('div', { class: 'icand-job' });
      box.appendChild(el('div', { class: 'small' }, el('b', { text: `Design ${String.fromCharCode(65 + n)}${code ? ' · for look ' + code : ''}` }), el('span', { class: 'muted small', text: ` · ${j.id} · ${subject.length > 140 ? subject.slice(0, 140) + '…' : subject}`, title: subject })));
      let picked = null;
      const btn = el('button', { class: 'btn small primary', type: 'button', text: 'Install', disabled: true, title: code ? `installs into look ${code} (${doc.id}_icon_${code.toLowerCase()}.png)` : 'installs as the item\'s icon', onclick: () => install(j, picked) });
      const grid = el('div', { class: 'icand-grid' });
      for (const ch of j.choices) {
        const key = ch.key != null ? ch.key : ch.label;
        const cell = el('div', { class: 'icand', title: ch.label || key }, el('img', { src: ch.url, alt: '', loading: 'lazy' }), el('span', { class: 'muted small', text: ch.label || key }));
        cell.addEventListener('click', () => { picked = key; for (const x of grid.children) x.classList.toggle('picked', x === cell); btn.disabled = false; btn.textContent = `Install ${ch.label || key}`; });
        cell.addEventListener('dblclick', () => { if (typeof StripPlayer !== 'undefined' && StripPlayer.openImage) StripPlayer.openImage(ch.url, `${doc.id} · ${ch.label || key}`); });
        grid.appendChild(cell);
      }
      box.appendChild(grid);
      box.appendChild(el('div', { class: 'alt-actions' }, btn));
      wrap.appendChild(box);
    });
    return wrap;
  }

  return { params, paramRow, perkParams, perkEditor, newPerkDialog, requirement, questWords, iconCandidates, familyOf };
})();
if (typeof module !== 'undefined') module.exports = TypedForms;
