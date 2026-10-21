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
    const g = rec.gates || {};
    const calls = Array.isArray(rec.model_calls) ? rec.model_calls : [];
    const dollars = calls.reduce((a, c) => a + (Number(c.dollars) || 0), 0);
    const models = [...new Set(calls.map((c) => c.model).filter(Boolean))];
    const gates = `${g.pass === true ? 'gates passed' : g.pass === false ? 'gates failed' : 'gates: ?'} · ${Number(g.hard_failures) || 0} hard, ${Number(g.advisory) || 0} advisory${calls.length ? ` · ${calls.length} model call${calls.length === 1 ? '' : 's'}${models.length ? ' (' + models.join(', ') + ')' : ''}, $${dollars.toFixed(2)}` : ' · no model call'}`;
    return { badges, gates, sheet: rec.sheet || '', ok: items.filter((i) => i && i.ok === true).length, n: items.length };
  }

  const api = { FINAL, STATE_LABEL, STATE_CLS, MISSING_MS, sig, elapsedText, connectionLine, budgetBars, lastOp, waitingWords, buttonsFor, requestFold, findingsBadges, fmtT, hms };
  return api;
})();
if (typeof module !== 'undefined') module.exports = JobsModel;
