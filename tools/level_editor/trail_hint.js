'use strict';
// Pass 130 (lane LE): the Trail tab's hint box, its page-free part. Garry: "add some kind of a simple hint system for the
// selected upgrade, which describes what that upgrade does."
//
//   build(M, doc, sel, hints, picks) -> {title, sub, lines: [{k, label, text}]} | null
//       M      trail_model.js (index, fmtValue, giveText, giveWhat, groupKey, resolveFrom)
//       sel    {id} a node of the file, or {id, upgrade} the same node with another upgrade type looked at (the pick
//              list while it is open), or {upgrade} a type alone
//       hints  trail_hints.json ({type: {what, note}}); a type without an entry falls back to its `text`
//       picks  GET /api/trail's lists (names; `locks` = what each thing was locked behind, trail_io.locks)
//   lines, in order: what (what it does in play), note (a designer's note), reads (how the amount is written and the
//   stat behind it), stands (how many nodes give the type, their sum, the sum up to this node's level), unlock (what an
//   unlock node opens and what that thing was locked behind), kind (what a choice / optional / needs-others node means)
//   amountLine / sums / kindLine / unlockLine are the pieces, exported for selftest_P130LE.py (run under Node).
const TrailHint = (() => {
  const isObj = (x) => x != null && typeof x === 'object' && !Array.isArray(x);
  const isNum = (x) => typeof x === 'number' && Number.isFinite(x);
  const tidy = (x) => Number(Number(x).toPrecision(12));
  const plural = (n, one, many) => `${n} ${n === 1 ? one : (many || one + 's')}`;
  const KIND_READS = {
    percent: 'a percent: 0.03 in the file is "+3%" on the card (type 3 in the amount cell)',
    flat: 'a plain number: 2 in the file is "+2"',
    count: 'a whole count: 1 in the file is "+1"',
    seconds: 'seconds: 1.5 in the file is "+1.5 s"',
    word: 'a word: the type has no amount, a node only switches it on',
  };
  const GIVE_SAYS = {
    outlaw: 'the outlaw is owned once this node is bought; until then his tile reads "Reach Trail Level N" and he is never on sale for gold',
    skin: 'the skin is owned once this node is bought; until then it reads "Reach Trail Level N"',
    weapon: 'the weapon joins the pool: from then on it can be offered in every run',
    passive: 'it joins the pool: from then on it can be offered in every run',
    stage: 'the stage may be played. Its other rule stays: the boss of the stage before it must be beaten too',
    map: 'the map may be played',
    structure: 'the structure may stand on maps',
    powerup: 'the power-up may drop (kills, barrels, the timed roster, the Cake and Pickpocket drops)',
    feature: 'the feature opens',
  };

  /** How one upgrade type's amount is written and which stat it moves. */
  function amountLine(u) {
    if (!isObj(u)) return '';
    const kind = KIND_READS[u.kind] ? u.kind : 'flat';
    const fx = (Array.isArray(u.effects) ? u.effects : []).filter((e) => isObj(e) && typeof e.stat === 'string').map((e) => {
      const per = isNum(e.per) ? e.per : 1;
      const times = per === 1 ? 'the amount' : `the amount × ${per}`;
      return e.op === 'mul' ? `\`${e.stat}\` is multiplied by 1 + ${times}` : `\`${e.stat}\` gets ${times} added`;
    });
    return `The amount is ${KIND_READS[kind]}.${fx.length ? ` Behind it: ${fx.join('; ')}.` : ''} All bought nodes of the type add up first.`;
  }

  /** The nodes that give `type`: {count, max, sure, choice, optional} over the whole file, or up to and including `upTo`. */
  function sums(M, doc, type, upTo) {
    const ix = M.index(doc);
    const out = { count: 0, sure: 0, choice: 0, optional: 0, max: 0 };
    const best = new Map();
    for (const n of ix.nodes) {
      const g = n.gives;
      if (!isObj(g) || g.type !== 'upgrade' || g.upgrade !== type) continue;
      if (upTo != null && !(n.level <= upTo)) continue;
      const v = isNum(g.value) ? g.value : 0;
      out.count++;
      if (n.kind === 'optional') out.optional = tidy(out.optional + v);
      else if (n.kind === 'choice' && n.group != null && n.group !== '') { const k = M.groupKey(n); best.set(k, Math.max(best.get(k) || 0, v)); }
      else out.sure = tidy(out.sure + v);
    }
    for (const v of best.values()) out.choice = tidy(out.choice + v);
    out.max = tidy(out.sure + out.choice + out.optional);
    return out;
  }
  function standsLine(M, doc, type, u, n) {
    const kind = (u && u.kind) || 'flat';
    const all = sums(M, doc, type);
    const name = (u && u.name) || type;
    if (!all.count) return `No node gives ${name} yet.`;
    const f = (v) => M.fmtValue(kind, v) || '0';
    const parts = [];
    if (all.choice || all.optional) {
      if (all.sure) parts.push(`${f(all.sure)} sure`);
      if (all.choice) parts.push(`${f(all.choice)} from choices (the best member of each group)`);
      if (all.optional) parts.push(`${f(all.optional)} optional`);
    }
    let s = `${plural(all.count, 'node')} give${all.count === 1 ? 's' : ''} ${name}: ${kind === 'word' ? 'no amount' : f(all.max) + ' at most'}${parts.length ? ` (${parts.join(', ')})` : ''}.`;
    if (n && Number.isInteger(n.level) && kind !== 'word') {
      const to = sums(M, doc, type, n.level);
      s += ` Up to and including level ${n.level}: ${to.count ? `${f(to.max)} over ${plural(to.count, 'node')}` : 'nothing yet'}.`;
    }
    return s;
  }

  /** One line on what the node's kind means: a choice, an optional node, a node that names the nodes it needs. */
  function kindLine(M, doc, n) {
    if (!isObj(n)) return '';
    const ix = M.index(doc);
    const out = [];
    if (n.kind === 'choice') {
      const mates = (ix.byLevel.get(n.level) || []).filter((m) => m.kind === 'choice' && M.groupKey(m) === M.groupKey(n));
      out.push(`Choice: the player takes one of the ${mates.length} nodes of group ${n.group == null || n.group === '' ? '(no name)' : n.group} (${mates.map((m) => m.id).join(', ')}) and the others close for good. No refund, no swap; the sums count a group's best member.`);
    } else if (n.kind === 'optional') {
      out.push(`Optional: it sits beside level ${n.level} and never holds the Trail Level back. It stays open to buy once its level is reached; the sums list it apart.`);
    }
    if (Array.isArray(n.from) && n.from.length) {
      const any = n.need === 'any';
      out.push(`Needs others: it opens only when ${n.from.length === 1 ? n.from[0] + ' is' : (any ? 'any one of ' : 'all of ') + n.from.join(', ') + (any ? ' is' : ' are')} bought. When ${any && n.from.length > 1 ? 'every one of them' : 'one of them'} closes (a choice not taken), this node closes for good too.`);
    }
    return out.join(' ');
  }

  /** What an unlock node opens and what that thing was locked behind. */
  function unlockLine(M, doc, n, picks) {
    const g = isObj(n) ? n.gives : null;
    if (!isObj(g) || g.type === 'upgrade' || !GIVE_SAYS[g.type]) return '';
    const p = isObj(picks) ? picks : {};
    let s = `Unlocks ${M.giveText(doc, n, p) || g.type}: ${g.type === 'feature' && g.id === 'wanted' ? 'the Bounty Board opens' : GIVE_SAYS[g.type]}.`.replace('Level N', `Level ${n.level}`);
    const key = `${g.type}:${M.giveWhat(g)}`;
    if (!isObj(p.locks)) return `${s} (What it was locked behind shows once the Level Editor is restarted.)`;
    const was = p.locks[key];
    if (g.type === 'outlaw') {
      const o = (Array.isArray(p.outlaws) ? p.outlaws : []).find((x) => isObj(x) && x.id === g.id);
      const bits = [];
      if (was) bits.push(was);
      if (o && isNum(o.price) && o.price > 0) bits.push(`a price of ${o.price} gold in his own file (as a Trail node he costs this node's price instead)`);
      s += ` Before the Trail: ${bits.length ? bits.join('; then ') : 'nothing, he was free'}.`;
    } else if (g.type === 'stage') {
      s += ' Before the Trail: only that boss.';
    } else {
      s += ` Before the Trail: ${was || 'nothing, it was free'}.`;
    }
    if (n.kind === 'choice') s += ' An unlock inside a choice can be lost for good.';
    return s;
  }

  function build(M, doc, sel, hints, picks) {
    if (!M || !isObj(doc) || !isObj(sel)) return null;
    const H = isObj(hints) ? hints : {};
    const n = sel.id != null ? (Array.isArray(doc.nodes) ? doc.nodes : []).find((x) => isObj(x) && x.id === sel.id) || null : null;
    const g = n && isObj(n.gives) ? n.gives : {};
    const looking = typeof sel.upgrade === 'string' && sel.upgrade !== '';
    const type = looking ? sel.upgrade : (g.type === 'upgrade' ? g.upgrade : null);
    const lines = [];
    let title = '', sub = '';
    if (type != null) {
      const u = isObj(doc.upgrades) ? doc.upgrades[type] : null;
      const h = isObj(H[type]) ? H[type] : null;
      title = (u && u.name) || type;
      const value = !looking || (g.type === 'upgrade' && g.upgrade === type) ? g.value : undefined;
      sub = u ? `${u.text || ''} ${isNum(value) ? M.fmtValue(u.kind, value) : ''}`.trim() : 'not an upgrade type of this file';
      if (looking && n && !(g.type === 'upgrade' && g.upgrade === type)) sub += ` · looking at it for ${n.id}`;
      lines.push({ k: 'what', label: 'In play', text: (h && h.what) || (u && u.text) || 'No description yet (add one to tools/level_editor/trail_hints.json).' });
      if (h && h.note) lines.push({ k: 'note', label: 'Note', text: h.note });
      if (u && u.warn) lines.push({ k: 'warn', label: 'The player is warned', text: u.warn });
      if (u) lines.push({ k: 'reads', label: 'Amount', text: amountLine(u) });
      lines.push({ k: 'stands', label: 'In the file', text: standsLine(M, doc, type, u, n) });
    } else if (n) {
      title = M.giveText(doc, n, picks) || String(g.type || '?');
      sub = `level ${n.level}`;
      const un = unlockLine(M, doc, n, picks);
      if (un) lines.push({ k: 'unlock', label: 'Unlock', text: un });
    } else return null;
    if (n) {
      const kl = kindLine(M, doc, n);
      if (kl) lines.push({ k: 'kind', label: 'This node', text: kl });
    }
    return { title, sub, lines, id: n ? n.id : null, type };
  }

  return { build, amountLine, sums, standsLine, kindLine, unlockLine, KIND_READS, GIVE_SAYS };
})();
if (typeof module !== 'undefined') module.exports = TrailHint;
