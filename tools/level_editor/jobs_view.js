// The live job pieces shared by the Jobs card and the look card's stage (pass 97, lane LIVE: UI-04 + UI-05). The Jobs tab
// (jobs.js) and the look grid's stage (looks.js) draw the same things from the same records:
//
//   JobsView.stagesRow(j)                the stages a job went through ("side 41s · cached")
//   JobsView.logTail(j, lines, u)        the log's last lines; the page state u.log says whether it was at the bottom
//   JobsView.patchLog(pre, j, lines, u)  the same <pre> given the new lines in place: it pins to the bottom only when it
//                                        was there (a log scrolled up keeps its place)
//   JobsView.outputs(j, holder, ctx)     the job's outputs (stills with their QA, clips played from out_NN frames, the
//                                        strip, the GLB, the ComfyUI workflows); `holder` is an array (players pushed, as
//                                        before pass 97) or a JobsView.Bank: players kept by URL and reused, so a clip
//                                        keeps playing when the card is patched
//   JobsView.substageLine(j)             lane PROGRESS's progress.substage: "side · KSampler step 3 of 4 · 41 s", and
//                                        progress.comfy_error in red
//   JobsView.liveBlock(model, o)         the look stage's live block from JobsModel.liveModel (its jobs and its request)
//   JobsView.requestStrip(req, o)        the request's line in that block: iteration k of n, the budget, the provisional
//                                        winner, Approve (the pass-96 batch box)
//
// Nothing here polls: jobs.js polls and tells its subscribers (Jobs.subscribe), which patch these in place.
'use strict';

const JobsView = (() => {
  const el = (...a) => U.el(...a);
  const JM = typeof JobsModel !== 'undefined' ? JobsModel : (typeof require === 'function' ? require('./jobs_model.js') : null);
  const clear = (n) => U.clear(n);
  const seen = new Map();   // a render's prompt id -> when the page first saw it (substage seconds without a server time)

  /** Players kept by key (a clip's URL and frames) across rebuilds of an outputs box: take() reuses, sweep() destroys
   *  the ones the newest build did not use; push() keeps the array API (Puppet.outputCell) for unkeyed ones. */
  class Bank {
    constructor() { this.map = new Map(); this.used = new Set(); this.loose = []; this.prevLoose = []; }
    begin() { this.used = new Set(); this.prevLoose = this.loose; this.loose = []; return this; }
    take(key, make) {
      let p = this.map.get(key);
      if (!p || p.destroyed) { p = make(); this.map.set(key, p); }
      this.used.add(key);
      return p;
    }
    has(key) { const p = this.map.get(key); return !!(p && !p.destroyed); }
    push(p) { if (p) this.loose.push(p); return this.loose.length; }
    sweep() {
      for (const [k, p] of [...this.map]) if (!this.used.has(k)) { try { p.destroy(); } catch (_) { /* gone */ } this.map.delete(k); }
      for (const p of this.prevLoose) if (!this.loose.includes(p)) { try { p.destroy(); } catch (_) { /* gone */ } }
      this.prevLoose = [];
    }
    destroyAll() {
      for (const p of this.map.values()) { try { p.destroy(); } catch (_) { /* gone */ } }
      for (const p of this.loose.concat(this.prevLoose)) { try { p.destroy(); } catch (_) { /* gone */ } }
      this.map.clear(); this.loose = []; this.prevLoose = []; this.used = new Set();
    }
    get size() { return this.map.size + this.loose.length; }
  }

  function stagesRow(j) {
    const p = j.progress || {};
    const row = el('div', { class: 'jstages' });
    // a stage's note says when it was not made by this job ("cached": the still or clip was on disk already)
    for (const s of p.stages || []) row.appendChild(el('span', { class: 'jstage ' + (s.state || '') + (s.note === 'cached' ? ' cached' : ''), text: s.name + (s.secs ? ` ${Math.round(s.secs)}s` : '') + (s.note ? ` · ${s.note}` : ''), title: `${s.name}: ${s.state || 'pending'}${s.note === 'cached' ? ' (reused from disk: this job did not paint it)' : s.note ? ' · ' + s.note : ''}` }));
    return row;
  }

  function tailText(j, lines) { return (j.log_tail || []).slice(-(lines || 12)).join('\n') || '(no output yet)'; }
  /** The log's last lines; u (the page state of the job: {log: 'bottom' | scrollTop}) says where it was. */
  function logTail(j, lines, u) {
    const st = u || { log: 'bottom' };
    const pre = el('pre', { class: 'jlog', text: tailText(j, lines) });
    pre.__lines = lines || 12;
    // the log pins to the bottom only when it was at the bottom; a scrolled-up log keeps its place (pass 96)
    requestAnimationFrame(() => { pre.scrollTop = typeof st.log === 'number' ? st.log : pre.scrollHeight; });
    pre.addEventListener('scroll', () => { st.log = pre.scrollTop + pre.clientHeight >= pre.scrollHeight - 4 ? 'bottom' : pre.scrollTop; });
    return pre;
  }
  /** New lines into the same <pre>: re-pinned only when it was at the bottom; true when the text changed. */
  function patchLog(pre, j, lines, u) {
    const text = tailText(j, lines || pre.__lines);
    if (pre.textContent === text) return false;
    const st = u || { log: 'bottom' };
    const keep = pre.scrollTop;
    pre.textContent = text;
    pre.scrollTop = st.log === 'bottom' ? pre.scrollHeight : (typeof st.log === 'number' ? st.log : keep);
    return true;
  }

  /** The job's outputs. holder: an array (the players are pushed, as before) or a Bank (kept by URL and reused);
   *  ctx: {ext: the ComfyUI extension installed?, title: the job's title, openAsset(t), act(path, body, busy)}. */
  function outputs(j, holder, ctx) {
    const c = ctx || {};
    const bank = holder instanceof Bank ? holder.begin() : null;
    const keep = (p) => { if (holder && !bank) holder.push(p); return p; };
    const title = c.title || j.title || j.kind || '';
    const box = el('div', { class: 'joutputs' });
    const flows = (j.outputs || []).filter((o) => o.type === 'workflow');
    if (flows.length) {
      // the ComfyUI workflows this job ran, one per render. Each run also saves its graph into the ComfyUI page's own
      // Workflows sidebar (workflows/88fits/<job folder>/); "↗" opens the page on that copy through the 88fits_open
      // extension (Garry: "click a link and open the ComfyUI page with the workflow and everything"); "file" is the JSON.
      const ext = c.ext;
      const unsent = flows.filter((o) => !o.open_url).length;
      const row = el('div', { class: 'jflows' }, el('b', { text: 'ComfyUI workflows' }),
        el('span', { class: 'muted small', text: unsent ? ' (one per render)' : ' (one per render; each sits in the ComfyUI page\'s Workflows sidebar under 88fits)' }));
      for (const o of flows) {
        const set = el('span', { class: 'jflow-set' });
        if (o.open_url) set.appendChild(el('a', { class: 'jflow open', href: o.open_url, target: '_blank', rel: 'noopener', text: o.label + ' ↗', title: ext === false ? `opens the ComfyUI page; its 88fits_open extension is not installed yet, so pick the workflow in the Workflows sidebar: ${o.userdata}` : `open the ComfyUI page on this workflow (${o.userdata})` }));
        else set.appendChild(el('span', { class: 'jflow pending', text: o.label, title: 'not in the ComfyUI sidebar yet: Send to ComfyUI' }));
        set.appendChild(el('a', { class: 'jflow file', href: o.url, target: '_blank', rel: 'noopener', text: 'file', title: 'the workflow file (drag it into the ComfyUI page)' }));
        row.appendChild(set);
      }
      if (unsent && c.act) row.appendChild(el('button', { type: 'button', class: 'btn small', text: `Send to ComfyUI (${unsent})`, title: 'save these workflows into the ComfyUI page\'s Workflows sidebar (88fits folder); the links then open them', onclick: async () => {
        const res = await c.act('push_workflows', {}, 'sending the workflows to ComfyUI');
        const errs = res && res.ok && res.job && Array.isArray(res.job.push_errors) ? res.job.push_errors : [];
        if (errs.length && typeof App !== 'undefined') App.status(`${title}: ${(res.job.pushed || []).length} sent, ${errs.length} failed: ${errs[0]}`, 'bad', errs.join('\n'));
      } }));
      if (ext === false) row.appendChild(el('span', { class: 'warn-text small', text: 'the ComfyUI page has no 88fits_open extension yet: a link opens the page and the workflow waits in its Workflows sidebar (ask Claude: python tools/comfy.py --install-ext)' }));
      box.appendChild(row);
    }
    for (const o of j.outputs || []) {
      if (o.type === 'workflow') continue;
      const cellEl = el('div', { class: 'joutput' });
      if (o.type === 'clip' && o.url) {
        const n = Number(o.frames) || 12;
        const base = String(o.url).replace(/\/?$/, '/');
        const make = () => StripPlayer.createSeq({ pattern: base + 'out_%02d.png', count: n, fps: Number(o.fps) || 12, size: 120, mode: 'hover', label: o.label || 'clip' });
        // pass 97: a clip's player is kept by its URL, frames and rate: a patched card moves it, never restarts it
        const p = bank ? bank.take(`clip|${base}|${n}|${Number(o.fps) || 12}`, make) : keep(make());
        cellEl.appendChild(p.el);
      } else if (o.type === 'strip' && o.url) {
        cellEl.appendChild(el('a', { href: '#', text: 'the strip', onclick: (e) => { e.preventDefault(); if (c.openAsset) c.openAsset(j.target); } }));
      } else if (o.type === 'glb' && o.url && typeof Puppet !== 'undefined') {
        // pass 71: the puppet's GLB in the 3D viewer (lazy: a click loads it; destroyed with the card)
        cellEl.classList.add('joutput-glb');
        if (bank) {
          const v = bank.take(`glb|${o.url}`, () => { const tmp = []; const node = Puppet.outputCell(o, tmp); const viewer = tmp[0] || { destroy() {}, destroyed: false }; viewer.el = viewer.el || node; return viewer; });
          cellEl.appendChild(v.el);
        } else cellEl.appendChild(Puppet.outputCell(o, holder));
      } else if (o.url) {
        const img = el('img', { src: o.url, alt: '', loading: 'lazy', title: o.label || '' });
        img.addEventListener('click', () => StripPlayer.openImage(o.url, `${title} · ${o.label || o.type}`));
        cellEl.appendChild(img);
      }
      cellEl.appendChild(el('span', { text: o.label || o.type || '' }));
      if (o.clip_kind) cellEl.appendChild(el('span', { class: o.clip_kind === 'free' || o.clip_kind === 'procedural' ? 'qa-bad' : 'muted', text: o.clip_kind + (o.clip_kind === 'free' ? ' (fell back from the driver)' : ''), title: 'how the clip was made: pose (a driver), control (a depth video), free (Wan guessed), procedural (no video)' }));
      if (o.qa && o.qa.problems && o.qa.problems.length) cellEl.appendChild(el('span', { class: 'qa-bad', text: 'QA: ' + o.qa.problems.join(', ') }));
      else if (o.qa) cellEl.appendChild(el('span', { class: 'muted', text: 'QA ok' }));
      box.appendChild(cellEl);
    }
    // pass 93 (lane PREVIEW): a driver job's new driver (any output under /dl/drivers/<name>/) opens in the viewer
    const made = Array.from(new Set((j.outputs || []).map((o) => /^\/dl\/drivers\/([A-Za-z0-9_-]+)\//.exec(String(o.url || ''))).filter(Boolean).map((m2) => m2[1])));
    if (made.length && typeof Drivers !== 'undefined') {
      box.appendChild(el('div', { class: 'joutput' }, made.map((nm) => el('button', { type: 'button', class: 'btn small', text: `▶ preview ${nm}`, title: `play ${nm} frame by frame with its frame numbers (the Drivers tab's viewer)`, onclick: () => { Drivers.ensureList(true); Drivers.open(nm, {}); } }))));
    }
    if (bank) bank.sweep();
    return box;
  }

  /** "side · KSampler step 3 of 4 · 41 s" and the ComfyUI error in red, or null (no substage on this job). */
  function substageLine(j, now) {
    const p = (j && j.progress) || {};
    const s = p.substage && typeof p.substage === 'object' ? p.substage : null;
    if (s && s.prompt && !seen.has(s.prompt)) { seen.set(s.prompt, Date.now()); if (seen.size > 200) seen.delete(seen.keys().next().value); }
    const m = JM ? JM.substageText(p, now, s && s.prompt ? seen.get(s.prompt) : null) : null;
    if (!m) return null;
    const line = el('div', { class: 'jsubstage' + (m.stale ? ' stale' : ''), title: 'the ComfyUI node running now and its step (the tool prints a line at most every 2 s and on every node change; tools/comfy.py\'s progress thread)' });
    if (m.text) line.appendChild(el('span', { class: 'jsub-text', text: m.text }));
    if (m.error) line.appendChild(el('span', { class: 'jsub-error', text: 'ComfyUI: ' + m.error, title: 'the error ComfyUI reported for this render' }));
    return line;
  }

  /** The request's line on the look stage: its chip, iteration k of n, the budget bars, the provisional winner, Approve. */
  function requestStrip(req, o) {
    const opts = o || {};
    const box = el('div', { class: 'lg-live-req' });
    box.appendChild(el('div', { class: 'row' },
      el('span', { class: `chip state-${req.chip.cls}`, text: 'request · ' + req.chip.text }),
      el('b', { text: req.iteration }),
      el('span', { class: 'muted small', text: req.provisional }),
      el('a', { href: req.link, class: 'small', text: 'open in Jobs', title: 'the request\'s card on the Jobs tab' })));
    if (req.lastOp) box.appendChild(el('div', { class: 'muted small', text: 'last op: ' + req.lastOp }));
    if (req.waiting) box.appendChild(el('div', { class: 'rwait small', text: req.waiting }));
    if (req.budgets && req.budgets.length) {
      const bb = el('div', { class: 'rbudgets' });
      for (const b of req.budgets) bb.appendChild(el('div', { class: 'rbudget' + (b.full ? ' full' : ''), title: `${b.label}: ${b.text}` }, el('div', { class: 'lbl' }, el('span', { text: b.label }), el('span', { text: b.text })), el('div', { class: 'bar' }, el('i', { style: `width:${b.pct}%` }))));
      box.appendChild(bb);
    }
    if (req.approve && opts.onApprove) box.appendChild(el('div', { class: 'row' }, el('button', { type: 'button', class: 'btn small primary', text: 'Approve…', title: 'ONE box lists the whole staged batch of the provisional winner (every changed frame before and after); one click exports it and installs', onclick: () => opts.onApprove(req) })));
    return box;
  }

  /** The look stage's live block (model = JobsModel.liveModel): one row per queued / running / waiting job of the look
   *  (its chip, stage k of N, elapsed / ETA, a lock wait, the substage, the stages, the 3 newest outputs as thumbnails,
   *  "open in Jobs") and the request on it. o: {jobs: the page's records by id, onApprove(req)}. */
  function liveBlock(model, o) {
    const opts = o || {};
    const box = el('div', { class: 'lg-live' });
    if (!model || (!model.jobs.length && !model.request)) { box.hidden = true; return box; }
    box.appendChild(el('div', { class: 'lg-live-head' }, el('b', { text: 'Live' }), el('span', { class: 'muted small', text: model.jobs.length ? `${model.jobs.length} job${model.jobs.length === 1 ? '' : 's'} on this look` : 'its art request' })));
    if (model.request) box.appendChild(requestStrip(model.request, opts));
    for (const m of model.jobs) {
      const j = opts.jobs && opts.jobs.get ? opts.jobs.get(m.id) : null;
      const row = el('div', { class: 'lg-live-job', 'data-id': m.id });
      const head = el('div', { class: 'row' },
        el('span', { class: `chip state-${m.chip.cls}`, text: m.chip.text }),
        el('span', { class: 'small', text: m.title }),
        el('span', { class: 'muted small', text: m.stage }));
      if (m.state === 'running') head.appendChild(el('span', { class: 'jelapsed small', 'data-started': m.started, 'data-eta': m.eta != null ? String(m.eta) : '', text: m.elapsed }));
      else if (m.elapsed) head.appendChild(el('span', { class: 'muted small', text: m.elapsed }));
      head.appendChild(el('a', { href: m.link, class: 'small', text: 'open in Jobs', title: 'its card on the Jobs tab' }));
      row.appendChild(head);
      if (m.lock) row.appendChild(el('div', { class: 'warn-text small', text: m.lock }));
      if (j) { const sl = substageLine(j); if (sl) row.appendChild(sl); }
      if (j && j.progress && (j.progress.stages || []).length) row.appendChild(stagesRow(j));
      if (m.thumbs.length) {
        const th = el('div', { class: 'lg-live-thumbs' });
        for (const t of m.thumbs) {
          const img = el('img', { src: t.url, alt: '', loading: 'lazy', title: t.label + (t.type === 'clip' ? ' (its first frame; the clip plays on the Jobs card)' : '') });
          img.addEventListener('click', () => StripPlayer.openImage(t.url, `${m.title} · ${t.label}`));
          th.appendChild(img);
        }
        row.appendChild(th);
      }
      box.appendChild(row);
    }
    return box;
  }

  return { Bank, stagesRow, logTail, patchLog, outputs, substageLine, requestStrip, liveBlock, seen };
})();
if (typeof module !== 'undefined') module.exports = JobsView;
