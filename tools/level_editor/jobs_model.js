'use strict';
// Pass 96 (lane PAGE): the page-free part of the Jobs tab (jobs.js reads it; selftest_PAGE96.py runs it under Node).
//   sig(j, ctx)            a job card's signature WITHOUT the clock (UI-04 part 1): a running card is rebuilt only when
//                          something it shows changed; the elapsed clock lives on its own 1 s timer (jobs.js)
//   elapsedText(...)       "1:23 / ~4:00" for that timer
//   connectionLine(st)     the honest connection line (UI-02 part 1): last contact, "no answer since hh:mm:ss, retrying
//                          every 15 s", distinct from "no jobs API" and "another editor runs the queue"
//   requestFold(r, jobs)   an art request's fold (GET /api/requests, tools/level_editor/requests.py) as the card's words:
//                          the state chip, iteration k of n, the budget bars, the last op and why, waiting_for in words,
//                          the buttons the state allows (Pause / Stop / Resume / Step / Approve / Reject / Pick another)
//   findingsBadges(f)      the findings record (<job>/findings.json, INTERFACES) as badges beside the outputs
const JobsModel = (() => {
  const FINAL = ['done', 'failed', 'stopped', 'cancelled'];
  const STATE_LABEL = { queued: 'QUEUED', running: 'RUNNING', paused: 'PAUSED', waiting: 'WAITING', approved: 'APPROVED', done: 'DONE', failed: 'FAILED', stopped: 'STOPPED', cancelled: 'CANCELLED' };
  const STATE_CLS = { queued: 'queued', running: 'running', paused: 'queued', waiting: 'waiting', approved: 'done', done: 'done', failed: 'failed', stopped: 'cancelled', cancelled: 'cancelled' };
  const UNIT_LABEL = { rerolls: 're-rolls', repair_rounds: 'repair rounds', lane_seconds: 'lane time', evaluator_calls: 'evaluator calls', cloud_dollars: 'cloud $' };
  const MISSING_MS = 15000;

  function pad2(n) { return String(n).padStart(2, '0'); }
  function hms(ms) { const d = new Date(ms); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`; }
  function fmtT(s) {
    if (s == null || isNaN(s)) return '–';
    s = Math.max(0, Math.round(s));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    return h > 0 ? `${h}:${pad2(m)}:${pad2(sec)}` : `${m}:${pad2(sec)}`;
  }
  function toMs(s) {
    if (!s) return 0;
    const d = typeof s === 'number' ? new Date(s * (s < 1e12 ? 1000 : 1)) : new Date(String(s).replace(' ', 'T'));
    return isNaN(d.getTime()) ? 0 : d.getTime();
  }

  /** The card's signature: everything it draws except the clock. ctx: {hidden, ext} (the page's own terms). */
  function sig(j, ctx) {
    const c = ctx || {};
    const p = j.progress || {};
    return JSON.stringify([j.state, j.waiting_for, p.stage, p.done, p.total, p.stalled, (j.log_tail || []).slice(-1)[0], (j.outputs || []).length,
      (j.outputs || []).filter((o) => o.open_url).length, c.ext == null ? null : c.ext, (j.choices || []).length, j.ended, j.error, j.written && j.written.layout,
      j.written && j.written.frames && j.written.frames.note, j.merged_into, j.eta_s, !!c.hidden, !!j.front, !!j.held, j.lane, j.request || null, j.lock_waits ? Object.keys(j.lock_waits).join(',') : '']);
  }

  /** "1:23 / ~4:00": the elapsed since `started` (an ISO string or epoch) and the estimate. */
  function elapsedText(started, etaS, now) {
    const t0 = toMs(started);
    const el = t0 ? Math.max(0, ((now || Date.now()) - t0) / 1000) : 0;
    return fmtT(el) + (etaS != null && isFinite(Number(etaS)) ? ` / ~${fmtT(Number(etaS))}` : '');
  }

  /** The honest connection line. st: {now, lastContact (ms), downSince (ms), netError, apiMissing, apiError, readonly: {view_only, who, pid} | null}.
   *  -> {cls: 'ok' | 'down' | 'noapi' | 'readonly' | 'never', text}. */
  function connectionLine(st) {
    const s = st || {};
    const now = s.now || Date.now();
    if (s.downSince) {
      return { cls: 'down', text: `no answer from the Level Editor since ${hms(s.downSince)}${s.netError ? ' (' + s.netError + ')' : ''}: retrying every ${Math.round(MISSING_MS / 1000)} s${s.lastContact ? ' · last answer ' + hms(s.lastContact) : ''}` };
    }
    if (s.apiMissing) {
      return { cls: 'noapi', text: `the server answers but has no jobs API${s.apiError ? ' (' + s.apiError + ')' : ''}: asking again every ${Math.round(MISSING_MS / 1000)} s${s.lastContact ? ' · last answer ' + hms(s.lastContact) : ''}` };
    }
    if (s.readonly) {
      const ro = s.readonly;
      return { cls: 'readonly', text: ro.view_only ? `connected · last answer ${s.lastContact ? hms(s.lastContact) : '–'} · this editor shows the queue only (--no-jobs)` : `connected · last answer ${s.lastContact ? hms(s.lastContact) : '–'} · another editor runs the queue (${ro.who || 'level_editor'}${ro.pid ? ', pid ' + ro.pid : ''}): read-only here` };
    }
    if (!s.lastContact) return { cls: 'never', text: 'asking the Level Editor…' };
    const age = Math.max(0, (now - s.lastContact) / 1000);
    return { cls: 'ok', text: `connected · last answer ${hms(s.lastContact)}${age >= 10 ? ' (' + Math.round(age) + ' s ago)' : ''}` };
  }

  /** The budget bars: [{unit, label, spent, budget, pct, text}] (repair_rounds: the worst group of the per-group spent). */
  function budgetBars(budget, spent) {
    const b = budget || {}, s = spent || {};
    const out = [];
    for (const unit of ['rerolls', 'repair_rounds', 'lane_seconds', 'evaluator_calls', 'cloud_dollars']) {
      if (b[unit] == null) continue;
      let used = s[unit];
      let note = '';
      if (unit === 'repair_rounds' && used && typeof used === 'object') {
        const vals = Object.values(used).map(Number).filter((x) => isFinite(x));
        const worst = vals.length ? Math.max(...vals) : 0;
        const worstKey = Object.keys(used).find((k) => Number(used[k]) === worst);
        used = worst;
        note = worstKey ? ` (${worstKey})` : '';
      }
      used = Number(used) || 0;
      const cap = Number(b[unit]) || 0;
      const pct = cap > 0 ? Math.max(0, Math.min(100, Math.round(100 * used / cap))) : 0;
      let text;
      if (unit === 'lane_seconds') text = `${Math.round(used / 60)} of ${Math.round(cap / 60)} min`;
      else if (unit === 'cloud_dollars') text = `$${used.toFixed(2)} of $${cap.toFixed(2)}${cap <= 0 ? ' (cloud off)' : ''}`;
      else text = `${used} of ${cap}${note}`;
      out.push({ unit, label: UNIT_LABEL[unit] || unit, spent: used, budget: cap, pct, text, full: cap > 0 && used >= cap });
    }
    return out;
  }

  /** The last op and why from the history tail (the newest `op` event), and the newest event in words. */
  function lastOp(r) {
    const tail = Array.isArray(r && r.history_tail) ? r.history_tail : [];
    let op = null;
    for (let i = tail.length - 1; i >= 0; i--) {
      const e = tail[i] || {};
      if (e.event === 'op' || e.op) { op = e; break; }
    }
    const its = Array.isArray(r && r.iterations) ? r.iterations : [];
    if (!op && its.length) op = { op: its[its.length - 1].op, t: its[its.length - 1].started };
    if (!op) return null;
    const o = op.op && typeof op.op === 'object' ? op.op : op;
    const verb = o.op || op.verb || '?';
    const t = o.target || {};
    const where = [t.code, t.group, Array.isArray(t.slots) && t.slots.length ? 'slots ' + t.slots.join(',') : ''].filter(Boolean).join(' ');
    return { verb, why: o.why || op.why || '', text: `${verb}${where ? ' on ' + where : ''}${o.why || op.why ? ' · ' + (o.why || op.why) : ''}`, t: op.t || '' };
  }

  function waitingWords(r) {
    const w = r && r.waiting_for;
    if (w === 'approval') return 'waiting for your approval: Approve installs the provisional winner (one box for the whole staged batch), Reject sends it back with a reason, Pick another chooses a candidate or a frame version by hand';
    if (w === 'pick') return 'waiting for your pick: a job of this request needs a candidate chosen (its card is in "Waiting for a pick"), or Pick another here';
    if (r && r.state === 'paused') return 'paused: Resume continues the loop, Step runs one operation';
    return '';
  }

  /** The buttons the state allows, in order. */
  function buttonsFor(r) {
    const st = r && r.state;
    const w = r && r.waiting_for;
    if (FINAL.includes(st) || st === 'approved') return st === 'approved' ? ['Cancel'] : [];
    const out = [];
    if (st === 'running' || st === 'queued') out.push('Pause');
    if (st === 'paused') out.push('Resume', 'Step');
    if (st === 'waiting' && w === 'approval') out.push('Approve', 'Reject');
    if (st === 'waiting' || st === 'paused') out.push('Pick another');
    out.push('Stop');
    return out;
  }

  /** The fold as the card's words. r: the fold (requests.fold); jobs: the page's job records by id (optional). */
  function requestFold(r, jobsById) {
    const f = r || {};
    const it = f.iteration || {};
    const a = f.asset || {};
    const n = Number(it.n) || 0, of = Number(it.of) || 0;
    const byId = jobsById || new Map();
    const jobs = Array.isArray(f.jobs) ? f.jobs.map((j) => Object.assign({}, j, byId.get && byId.get(j.id) ? { live: byId.get(j.id) } : {})) : [];
    const running = jobs.filter((j) => ['queued', 'running', 'waiting'].includes(j.state)).length;
    const prov = f.provisional || null;
    const provText = prov ? `provisional winner: ${prov.code || a.code || '?'}${prov.groups && typeof prov.groups === 'object' ? ' · ' + Object.entries(prov.groups).map(([g, v]) => `${g}: ${Array.isArray(v.staged) ? v.staged.length + ' staged' : 'chosen'}`).join(', ') : ''}` : 'no provisional winner yet';
    return {
      rid: f.rid || '', chip: { text: STATE_LABEL[f.state] || String(f.state || '?').toUpperCase(), cls: STATE_CLS[f.state] || 'queued' },
      title: `${a.kind || ''} ${a.id || ''}${a.code ? ' · ' + a.code : ''}${a.method ? ' · ' + a.method : ''}`.trim(),
      goal: f.goal || '', mode: f.mode || 'auto',
      iteration: of ? `iteration ${n} of ${of}` : (n ? `iteration ${n}` : 'no iteration yet'),
      budgets: budgetBars(f.budget, f.spent), lastOp: lastOp(f), waiting: waitingWords(f), summary: f.summary || '',
      provisional: provText, sheet: f.sheet || (prov && prov.sheet) || '', buttons: buttonsFor(f),
      jobsLine: `${jobs.length} job${jobs.length === 1 ? '' : 's'}${running ? ` (${running} live)` : ''}`, jobs,
      final: FINAL.includes(f.state) || f.state === 'approved', result: f.result || null,
      currentJob: f.current_job || (jobs.length ? jobs[jobs.length - 1].id : null),
      latestJob: [...jobs].reverse().find((j) => FINAL.includes(j.state) || j.state === 'waiting') || null,
    };
  }

  /** The findings record as badges: [{text, title, cls, group, slot}] + the gates line. */
  function findingsBadges(f) {
    const rec = f || {};
    const items = Array.isArray(rec.items) ? rec.items : [];
    const badges = items.filter((i) => i && i.ok === false).map((i) => ({
      text: `${i.field || i.kind || '?'}${i.slot != null ? ' f' + String(i.slot).padStart(2, '0') : ''}${i.group ? ' · ' + i.group : ''}`,
      title: `${i.rule || i.field || ''}${i.value != null ? ' (' + i.value + ')' : ''}${i.model ? ' · ' + i.model : i.kind === 'measured' ? ' · measured' : i.kind === 'human' ? ' · Garry' : ''}`,
      cls: i.kind === 'model' ? 'model' : i.kind === 'human' ? 'human' : 'measured', group: i.group || '', slot: i.slot == null ? null : i.slot, model: i.model || '',
    }));
    // pass 98 (lane GEMINI): a finding that names its eye (Gemini's items carry `eye`) shows the eye's name and colour
    items.filter((i) => i && i.ok === false).forEach((i, k) => {
      if (!i.eye) return;
      const nm = ({ gemini: 'Gemini', local: 'Local' })[i.eye] || i.eye;
      Object.assign(badges[k], { text: `${nm}: ${i.label || i.value || i.field || '?'}${i.slot != null ? ' f' + String(i.slot).padStart(2, '0') : ''}${i.group ? ' · ' + i.group : ''}`,
        title: `${i.note || i.rule || ''}${i.model ? ' · ' + i.model : ''} (a hint, not a verdict)`, cls: `model eye-${['gemini', 'local'].includes(i.eye) ? i.eye : 'other'}`, eye: i.eye });
    });
    const g = rec.gates || {};
    const calls = Array.isArray(rec.model_calls) ? rec.model_calls : [];
    const dollars = calls.reduce((a, c) => a + (Number(c.dollars) || 0), 0);
    const models = [...new Set(calls.map((c) => c.model).filter(Boolean))];
    const gates = `${g.pass === true ? 'gates passed' : g.pass === false ? 'gates failed' : 'gates: ?'} · ${Number(g.hard_failures) || 0} hard, ${Number(g.advisory) || 0} advisory${calls.length ? ` · ${calls.length} model call${calls.length === 1 ? '' : 's'}${models.length ? ' (' + models.join(', ') + ')' : ''}, $${dollars.toFixed(2)}` : ' · no model call'}`;
    return { badges, gates, sheet: rec.sheet || '', ok: items.filter((i) => i && i.ok === true).length, n: items.length };
  }

  // ------------------------------------------------------------------ pass 97 (lane LIVE): the live page's page-free parts
  //   merge(jobs, d)          a poll's answer (the delta {rev, changed, removed, delta[, order, full, unchanged]} or the old
  //                           whole list {rev, jobs}) merged into the page's list by id, the server's order kept
  //   slotSigs(j, ctx, x)     one signature per card slot (head, sub, stage, bar, stages, log, outputs, choices, actions,
  //                           folds): a poll patches only the slots whose signature moved
  //   parseHash / formatHash  the page's routes (#tab, #jobs/<id>, #jobs?look=, #requests/<rid>, #frames/...)
  //   substageText(p, ...)    "side · KSampler step 3 of 4 · 41 s" from progress.substage (lane PROGRESS's field)
  //   liveModel / historyModel  the look card's live block and history line in words
  //   opsModel(ops, methods)  the Ops fold (GET /api/ops) as rows and sentences
  //   offlinePill(st)         "offline since hh:mm" from the connection state
  const ACTIVE = ['queued', 'running', 'waiting'];
  const KIND_TAB = { enemy: 'creatures', boss: 'creatures', hero: 'heroes' };
  const TABS = ['timeline', 'settings', 'creatures', 'heroes', 'items', 'jobs', 'bossattacks', 'sim', 'drivers', 'instructions'];

  /** -> {jobs, changed: [ids], removed: [ids], full, unchanged}. A record in `changed` replaces the page's whole record. */
  function merge(jobs, d) {
    const old = Array.isArray(jobs) ? jobs : [];
    const none = { jobs: old, changed: [], removed: [], full: false, unchanged: true };
    if (!d || typeof d !== 'object') return none;
    const oldIds = new Set(old.map((j) => j && j.id));
    if (!d.delta) {
      // a server without the delta (or a stand-in): the whole list, as before pass 97
      if (d.unchanged || !Array.isArray(d.jobs)) return none;
      const list = d.jobs.slice();
      const now = new Set(list.map((j) => j && j.id));
      return { jobs: list, changed: list.map((j) => j.id), removed: [...oldIds].filter((id) => !now.has(id)), full: true, unchanged: false };
    }
    if (d.unchanged) return none;
    const changed = (Array.isArray(d.changed) ? d.changed : []).filter((j) => j && j.id != null);
    if (d.full) {
      const map = new Map(changed.map((j) => [j.id, j]));
      const list = Array.isArray(d.order) ? d.order.filter((id) => map.has(id)).map((id) => map.get(id)) : changed.slice();
      if (list.length < map.size) { const inList = new Set(list.map((j) => j.id)); for (const j of changed) if (!inList.has(j.id)) list.push(j); }
      return { jobs: list, changed: list.map((j) => j.id), removed: [...oldIds].filter((id) => !map.has(id)), full: true, unchanged: false };
    }
    const map = new Map(old.map((j) => [j.id, j]));
    const removed = (Array.isArray(d.removed) ? d.removed : []).filter((id) => map.has(id));
    for (const id of removed) map.delete(id);
    for (const j of changed) map.set(j.id, j);
    let list;
    if (Array.isArray(d.order)) {
      list = d.order.filter((id) => map.has(id)).map((id) => map.get(id));
      const inOrder = new Set(d.order);
      for (const [id, j] of map) if (!inOrder.has(id)) list.push(j);
    } else {
      list = old.filter((j) => map.has(j.id)).map((j) => map.get(j.id));
      for (const j of changed) if (!oldIds.has(j.id)) list.push(j);
    }
    const moved = list.length !== old.length || list.some((j, i) => j.id !== old[i].id);
    return { jobs: list, changed: changed.map((j) => j.id), removed, full: false, moved, unchanged: !changed.length && !removed.length && !moved };
  }

  const J = (x) => JSON.stringify(x === undefined ? null : x);
  /** The signatures of a card's slots. ctx: {hidden, ext, method (the method's shown name), now?}; x: the card's place
   *  ({pos, n, held, up, down} for a queued job). The clock is in none of them (its own 1 s timer). */
  function slotSigs(j, ctx, x) {
    const c = ctx || {}, p = j.progress || {}, t = j.target || {}, w = x || {};
    const sp = j.spec || {};
    const sub = p.substage || null;
    const outs = (j.outputs || []).map((o) => [o.type, o.url, o.label, o.open_url ? 1 : 0, o.frames, o.fps, o.clip_kind, o.qa ? (o.qa.problems || []).join(',') || 'ok' : '']);
    const where = [w.pos, w.n, w.held ? 1 : 0, w.up || 0, w.down || 0].join('/');
    let stage;
    if (j.state === 'running') stage = [p.stage, p.done, p.total, p.stalled, j.lock_waits || null, p.last_output, j.eta_s, j.eta_source || null, j.started, sub ? [sub.node, sub.value, sub.max, sub.view, sub.prompt, sub.at, sub.started, sub.since] : null, p.comfy_error || null];
    else if (j.state === 'waiting') stage = [j.waiting_for, p.stage, (j.choices || []).map((ch) => [ch.key, ch.label, ch.url, ch.group, ch.sheet, ch.qa ? (ch.qa.problems || []).join(',') : ''])];
    else if (j.state === 'queued') stage = [where, !!j.front, !!j.held, j.lane, j.eta_s, t.code, t.id, sp.ref];
    else if (j.state === 'done') stage = [j.written || null];
    else stage = [j.state, j.error, p.comfy_error || null];
    return {
      head: J([j.state, j.id, j.title, j.kind, t.id, t.code, j.created, j.started, j.ended]),
      sub: J([t.kind, t.id, t.code, c.method || j.method || sp.method, j.lane, j.phase, j.attempt, sp.note, sp.defaults_from || null, sp.reroll || null, j.qa_online, j.request || null]),
      stage: J(stage),
      bar: J(j.state === 'running' ? [p.done, p.total, p.stalled] : null),
      stages: J((p.stages || []).map((s) => [s.name, s.state, s.secs ? Math.round(s.secs) : 0, s.note])),
      log: J((j.log_tail || []).slice(-12)),
      outputs: J([outs, c.ext == null ? null : c.ext, j.state === 'queued' ? (j.phase || 1) : 0]),
      choices: J(j.state === 'done' ? (j.choices || []).map((ch) => [ch.key, ch.label, ch.url]) : null),
      actions: J([j.state, j.kind, t.kind, t.id, t.code, j.method, where, !!j.front, !!j.held, (j.choices || []).length, sp.counts ? sp.counts.seeds : null, !!c.hidden]),
      folds: J([j.equiv, sp]),
    };
  }

  /** The page's routes. '' -> null; '#jobs' -> {tab: 'jobs'}; '#jobs/<id>'; '#jobs?look=SP-B&id=desert_spider&kind=enemy';
   *  '#requests/<rid>' (on the Jobs tab); '#frames/<kind>/<id>/<code>[/<anim>/<view>[/<slot>]]' (on the asset's tab). */
  function parseHash(h) {
    let s = String(h || '').trim();
    if (s.startsWith('#')) s = s.slice(1);
    if (!s) return null;
    let query = '';
    const qi = s.indexOf('?');
    if (qi >= 0) { query = s.slice(qi + 1); s = s.slice(0, qi); }
    const parts = s.split('/').filter((x) => x !== '').map((x) => { try { return decodeURIComponent(x); } catch (_) { return x; } });
    const ok = (x) => typeof x === 'string' && /^[A-Za-z0-9_][A-Za-z0-9_.\-]{0,95}$/.test(x) && !x.includes('..');
    const q = {};
    for (const kv of query.split('&')) { if (!kv) continue; const i = kv.indexOf('='); const k = i < 0 ? kv : kv.slice(0, i); let v = i < 0 ? '' : kv.slice(i + 1); try { v = decodeURIComponent(v.replace(/\+/g, ' ')); } catch (_) { /* as typed */ } q[k] = v; }
    const head = parts[0] || '';
    if (head === 'jobs') {
      if (parts[1] && ok(parts[1])) return { tab: 'jobs', job: parts[1] };
      if (q.look || q.id) {
        const f = {};
        if (q.look && ok(q.look)) f.look = q.look;
        if (q.id && ok(q.id)) f.id = q.id;
        if (q.kind && ok(q.kind)) f.kind = q.kind;
        return Object.keys(f).length ? { tab: 'jobs', filter: f } : { tab: 'jobs' };
      }
      return { tab: 'jobs' };
    }
    if (head === 'requests') return parts[1] && ok(parts[1]) ? { tab: 'jobs', request: parts[1] } : { tab: 'jobs' };
    if (head === 'frames') {
      const [, kind, id, code, anim, view, slot] = parts;
      if (!KIND_TAB[kind] || !ok(id) || !ok(code)) return null;
      const fr = { kind, id, code };
      if (anim && ok(anim)) fr.anim = anim;
      if (view && ok(view)) fr.view = view;
      if (slot != null && /^\d{1,4}$/.test(slot)) fr.slot = Number(slot);
      return { tab: KIND_TAB[kind], frames: fr };
    }
    if (TABS.includes(head) && parts.length === 1) return { tab: head };
    return null;
  }
  function formatHash(r) {
    if (!r || typeof r !== 'object') return '';
    const e = encodeURIComponent;
    if (r.frames) {
      const f = r.frames;
      let s = `#frames/${e(f.kind)}/${e(f.id)}/${e(f.code)}`;
      if (f.anim) { s += `/${e(f.anim)}`; if (f.view) { s += `/${e(f.view)}`; if (f.slot != null && isFinite(Number(f.slot))) s += `/${Math.max(0, Math.round(Number(f.slot)))}`; } }
      return s;
    }
    if (r.request) return `#requests/${e(r.request)}`;
    if (r.job) return `#jobs/${e(r.job)}`;
    if (r.filter && (r.filter.look || r.filter.id)) {
      const q = [];
      for (const k of ['look', 'id', 'kind']) if (r.filter[k]) q.push(`${k}=${e(r.filter[k])}`);
      return `#jobs?${q.join('&')}`;
    }
    return r.tab ? `#${r.tab}` : '';
  }
  /** Whether a job belongs to a route's filter ({look, id, kind}). */
  function filterMatch(j, f) {
    if (!f) return true;
    const t = (j && j.target) || {};
    if (f.look && String(t.code || '') !== f.look) return false;
    if (f.id && String(t.id || '') !== f.id) return false;
    if (f.kind && t.kind && t.kind !== f.kind && !((f.kind === 'enemy' && t.kind === 'boss') || (f.kind === 'boss' && t.kind === 'enemy'))) return false;
    return true;
  }

  /** "side · KSampler step 3 of 4 · 41 s" (lane PROGRESS's progress.substage {node, value, max, at, view?, prompt}); the
   *  seconds since the render began (its `started` when the server gives one, else since the page first saw the prompt
   *  `seen`, else since its tick `at`); "(no tick for N s)" once the ticks stop. -> {text, error, stale} or null. */
  function substageText(p, now, seen) {
    const pr = p || {};
    const s = pr.substage && typeof pr.substage === 'object' ? pr.substage : null;
    const err = pr.comfy_error ? String(pr.comfy_error) : '';
    if (!s && !err) return null;
    const t = now || Date.now();
    let text = '';
    if (s) {
      const node = String(s.node || 'ComfyUI');
      // lane PROGRESS: max 0 = a node that reports no steps (VAE Decode, a loader): its name alone; `since` = when the node began
      const step = s.max != null && Number(s.max) > 0 ? ` step ${Number(s.value) || 0} of ${Number(s.max)}` : '';
      const t0 = toMs(s.started) || toMs(s.since) || Number(seen) || toMs(s.at);
      const secs = t0 ? Math.max(0, Math.round((t - t0) / 1000)) : null;
      const age = toMs(s.at) ? Math.max(0, Math.round((t - toMs(s.at)) / 1000)) : 0;
      text = `${s.view ? s.view + ' · ' : ''}${node}${step}${secs != null ? ' · ' + (secs >= 90 ? fmtT(secs) : secs + ' s') : ''}${age >= 30 ? ` (no tick for ${age} s)` : ''}`;
      return { text, error: err, stale: age >= 30 };
    }
    return { text: '', error: err, stale: false };
  }

  function chipOf(j) { return { text: j.state === 'waiting' ? 'needs a pick' : j.state, cls: j.state }; }
  /** The look card's live block: its queued / running / waiting jobs and the art request on it. jobs: the page's list;
   *  requests: GET /api/requests' folds. -> {jobs: [...], request, n}. */
  function liveModel(jobs, requests, kind, id, code, now) {
    const t = now || Date.now();
    const sameKind = (k) => !kind || !k || k === kind || (kind === 'enemy' && k === 'boss') || (kind === 'boss' && k === 'enemy');
    const mine = (jobs || []).filter((j) => j && ACTIVE.includes(j.state) && j.target && j.target.id === id && String(j.target.code || '') === String(code || '') && sameKind(j.target.kind));
    const order = { running: 0, waiting: 1, queued: 2 };
    mine.sort((a, b) => (order[a.state] - order[b.state]));
    const out = mine.map((j) => {
      const p = j.progress || {};
      const stage = j.state === 'running' ? `stage ${p.stage || '…'}${p.total ? ` (${p.done || 0} of ${p.total})` : ''}` : j.state === 'waiting' ? `needs your pick${p.stage ? ' · ' + p.stage : ''}` : (j.held ? 'waiting for its look\'s front' : 'in the queue');
      const waited = j.lock_wait_s && typeof j.lock_wait_s === 'object' ? Object.entries(j.lock_wait_s).filter(([, v]) => Number(v) >= 1) : [];
      const lock = j.lock_waits && Object.keys(j.lock_waits).length ? 'waiting for a lock: ' + Object.entries(j.lock_waits).map(([k, v]) => `${k} ${v}`).join('; ')
        : waited.length ? 'waited for ' + waited.map(([k, v]) => `the ${k} lock ${fmtT(Number(v))}`).join(', ') : '';
      const thumbs = (j.outputs || []).filter((o) => o && o.url && o.type !== 'workflow' && o.type !== 'glb').slice(-3).reverse().map((o) => ({ type: o.type, url: o.type === 'clip' ? String(o.url).replace(/\/?$/, '/') + 'out_00.png' : o.url, label: o.label || o.type || '' }));
      return { id: j.id, state: j.state, chip: chipOf(j), kind: j.kind, title: j.title || j.kind, stage, elapsed: j.state === 'running' ? elapsedText(j.started, j.eta_s, t) : (j.eta_s != null ? `~${fmtT(j.eta_s)} once it runs` : ''),
        lock, sub: substageText(p, t), thumbs, link: formatHash({ job: j.id }), started: j.started || '', eta: j.eta_s != null ? j.eta_s : null };
    });
    const reqs = (requests || []).filter((r) => r && r.asset && r.asset.id === id && sameKind(r.asset.kind) && (String(r.asset.code || '') === String(code || '') || (r.provisional && String(r.provisional.code || '') === String(code || ''))));
    const live = reqs.filter((r) => !FINAL.includes(r.state));
    const r = (live.length ? live : reqs)[0] || null;
    let request = null;
    if (r) {
      const F = requestFold(r, new Map((jobs || []).map((j) => [j.id, j])));
      request = { rid: r.rid, chip: F.chip, iteration: F.iteration, budgets: F.budgets, provisional: F.provisional, waiting: F.waiting, approve: F.buttons.includes('Approve'), final: F.final, link: formatHash({ request: r.rid }), lastOp: F.lastOp ? F.lastOp.text : '' };
    }
    return { jobs: out, request, n: out.length + (request && !request.final ? 1 : 0) };
  }

  /** The history line: the look's past jobs (a filtered link), its exports (the frames store's exports.json lines) and
   *  the newest events (GET /api/events, lane PROGRESS's log). */
  function historyModel(jobs, exportsList, events, kind, id, code) {
    const past = (jobs || []).filter((j) => j && j.target && j.target.id === id && String(j.target.code || '') === String(code || '') && FINAL_JOB.includes(j.state));
    const by = {};
    for (const j of past) by[j.state] = (by[j.state] || 0) + 1;
    const ex = (exportsList || []).filter(Boolean).slice().sort((a, b) => String(b.time || '').localeCompare(String(a.time || '')));
    const evs = (events || []).filter((e) => e && ((e.look && e.look.id === id && String(e.look.code || '') === String(code || '')) || (e.target && e.target.id === id && String(e.target.code || '') === String(code || ''))))
      .sort((a, b) => (Number(b.seq) || 0) - (Number(a.seq) || 0)).slice(0, 3);
    const parts = [];
    parts.push(past.length ? `past jobs: ${past.length} (${Object.entries(by).map(([k, v]) => `${v} ${k}`).join(', ')})` : 'no past jobs in the list');
    if (exportsList) parts.push(ex.length ? `exports: ${ex.length} (last ${whenText(ex[0].time)}${ex[0].why ? ' · ' + ex[0].why : ''}${Array.isArray(ex[0].changed) ? ' · ' + ex[0].changed.length + ' frame' + (ex[0].changed.length === 1 ? '' : 's') : ''})` : 'no export yet');
    return { line: parts.join(' · '), jobsLink: formatHash({ filter: { look: code, id } }), past: past.length, exports: ex.length,
      events: evs.map((e) => `${whenText(e.t)} ${e.event || e.kind || '?'}${e.job ? ' #' + String(e.job).slice(-4) : ''}${e.by ? ' by ' + e.by : ''}`) };
  }
  const FINAL_JOB = ['done', 'failed', 'interrupted', 'cancelled'];
  function whenText(s) { const ms = toMs(s); if (!ms) return String(s || '?'); const d = new Date(ms); return `${d.getMonth() + 1}/${d.getDate()} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`; }

  /** The Ops fold from GET /api/ops (lane PROGRESS: {days, outcomes, medians, lock_wait, failures, qa_offline,
   *  interrupted, stalled, cost, eta_source}); methods: methods.json's {methods: [{id, name, time: {median_s}}]}. */
  function opsModel(ops, methods) {
    const o = ops || {};
    // outcomes: {state: {kind: {method: n}}} or {"state|kind|method": n} (both read)
    const rows = new Map();
    const states = new Set();
    const add = (state, kind, method, n) => { const k = `${kind || '?'}|${method || '-'}`; if (!rows.has(k)) rows.set(k, { kind: kind || '?', method: method || '-', n: {} }); rows.get(k).n[state] = (rows.get(k).n[state] || 0) + (Number(n) || 0); states.add(state); };
    const oc = o.outcomes && typeof o.outcomes === 'object' ? o.outcomes : {};
    for (const [k, v] of Object.entries(oc)) {
      if (v && typeof v === 'object') { for (const [k2, v2] of Object.entries(v)) { if (v2 && typeof v2 === 'object') { for (const [k3, n] of Object.entries(v2)) add(k, k2, k3, n); } else add(k, k2, '-', v2); } }
      else { const bits = String(k).split(/[|/ x×]+/).filter(Boolean); add(bits[0], bits[1], bits[2], v); }
    }
    const stateOrder = ['done', 'failed', 'interrupted', 'cancelled', 'running', 'waiting', 'queued'];
    const cols = [...states].sort((a, b) => ((stateOrder.indexOf(a) + 1 || 99) - (stateOrder.indexOf(b) + 1 || 99)) || a.localeCompare(b));
    const outcomes = [...rows.values()].sort((a, b) => a.kind.localeCompare(b.kind) || a.method.localeCompare(b.method)).map((r) => ({ kind: r.kind, method: r.method, cells: cols.map((c) => r.n[c] || 0), total: cols.reduce((s, c) => s + (r.n[c] || 0), 0) }));
    const mlist = methods && Array.isArray(methods.methods) ? methods.methods : [];
    const mt = (id) => { const m = mlist.find((x) => x.id === id); return m && m.time && m.time.median_s != null ? Number(m.time.median_s) : null; };
    const med = o.medians && typeof o.medians === 'object' ? o.medians : {};
    const sec = (x) => (x == null || !isFinite(Number(x)) ? '–' : fmtT(Number(x)));
    const medians = Object.entries(med).sort((a, b) => a[0].localeCompare(b[0])).map(([m, v]) => {
      const r = (v && v.rendered) || {}, c = (v && v.cached) || {};
      return { method: m, rendered: r.n ? `${sec(r.median)} (p90 ${sec(r.p90)}, ${r.n} runs)` : '–', cached: c.n ? `${sec(c.median)} (${c.n} runs)` : '–', table: mt(m) != null ? sec(mt(m)) : '–', measured: (Number(r.n) || 0) >= 5 };
    });
    const lock = Object.entries(o.lock_wait && typeof o.lock_wait === 'object' ? o.lock_wait : {}).map(([k, v]) => `${k} ${sec(v)}`).join(' · ');
    const failures = (Array.isArray(o.failures) ? o.failures : []).map((f) => `${Number(f.n) || 1}× ${String(f.reason || 'no reason recorded').replace(/\s+/g, ' ').slice(0, 220)}${f.last_job ? ` (last: #${String(f.last_job).slice(-4)})` : ''}`);
    const cost = o.cost && typeof o.cost === 'object' ? o.cost : {};
    const reqs = (Array.isArray(cost.requests) ? cost.requests : []).map((r) => `request ${String(r.rid || '?').slice(-4)}: $${(Number(r.dollars) || 0).toFixed(2)} in ${Number(r.calls) || 0} call${Number(r.calls) === 1 ? '' : 's'}`);
    const byModel = Object.entries(cost.by_model && typeof cost.by_model === 'object' ? cost.by_model : {}).map(([m, v]) => `${m} $${(Number(v && typeof v === 'object' ? v.dollars : v) || 0).toFixed(2)}`).join(' · ');
    const counts = [['qa_offline', 'with the QA offline'], ['interrupted', 'interrupted'], ['stalled', 'stalled']].filter(([k]) => Number(o[k]) > 0).map(([k, w]) => `${o[k]} ${w}`).join(' · ');
    return { days: Number(o.days) || null, cols, outcomes, medians, lock, failures, requests: reqs, total: cost.total_dollars != null ? `$${(Number(cost.total_dollars) || 0).toFixed(2)}` : '', byModel, counts,
      etaSource: o.eta_source === 'measured' ? 'the estimates use the measured medians (5 runs or more)' : o.eta_source === 'builtin' ? 'the estimates use methods.json\'s table (under 5 measured runs)' : '' };
  }

  /** "offline since hh:mm" while the Level Editor does not answer (the connection state of jobs.js). */
  function offlinePill(st) {
    const s = st || {};
    if (!s.downSince) return null;
    const d = new Date(s.downSince);
    return { text: `offline since ${pad2(d.getHours())}:${pad2(d.getMinutes())}`, title: `the Level Editor has not answered since ${hms(s.downSince)}${s.netError ? ' (' + s.netError + ')' : ''}; the page asks again every ${Math.round(MISSING_MS / 1000)} s and catches up when it answers` };
  }

  const api = { FINAL, STATE_LABEL, STATE_CLS, MISSING_MS, sig, elapsedText, connectionLine, budgetBars, lastOp, waitingWords, buttonsFor, requestFold, findingsBadges, fmtT, hms,
    merge, slotSigs, parseHash, formatHash, filterMatch, substageText, liveModel, historyModel, opsModel, offlinePill, toMs, TABS, KIND_TAB };   // pass 97
  return api;
})();
if (typeof module !== 'undefined') module.exports = JobsModel;
