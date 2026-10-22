// Gemini as a checker (pass 98, lane GEMINI). Garry: "how I will be able to tell that Gemini discovered something that's
// wrong". The eyes' findings live per frame version in the frames store (qa.eyes, written when an evaluate job lands;
// the old local button's qa.vision counts as the Local eye). This file draws them and holds the buttons:
//
//   EyesModel (page-free, checked under Node by selftest_GEMINI98.py)
//     latest(qa)            {eye: newest entry} of a version's qa (qa.eyes + qa.vision as Local)
//     badges(v)             one badge per eye ("Gemini: 9 legs", "Local: ghost part"), a strong "both" mark when two eyes
//                           flag the frame; title = the full note, the model, the time, "a hint, not a verdict"
//     cellMark(slot)        the sheet cell's mini mark from its shown version (G, L, G+L)
//     opsLine(status)       "Gemini today: 3 of 40 calls (37 left) · ready"
//     findingBadge(item)    a request card's finding with the eye's name and colour (items that carry `eye`)
//   Eyes (the page)
//     askFrames(...)        Ask Gemini: POST .../ask_gemini {slots} (an evaluate job), then wait for it and call back
//     checkLook(...)        Check with Gemini: POST /api/eyes/check (tiers 0, 1, 2 over the whole look)
//     lookLine(host, ...)   the look card's line ("Gemini flagged 3 frames in run/side")
//     opsInto(box)          the Ops fold's line (today's Gemini calls against the cap)
'use strict';

const EyesModel = (() => {
  const NAMES = { gemini: 'Gemini', local: 'Local' };
  const HINT = 'a hint, not a verdict';
  const FIELD = { broken: 'broken part', ghost: 'ghost part', colour: 'odd colour' };

  function latest(qa) {
    const out = {};
    for (const e of ((qa && qa.eyes) || [])) {
      if (!e || !e.eye) continue;
      if (!out[e.eye] || String(e.time || '') >= String(out[e.eye].time || '')) out[e.eye] = e;
    }
    const vis = qa && qa.vision;
    if (vis && vis.answer && typeof vis.answer === 'object') {
      const a = vis.answer;
      const bad = ['broken', 'ghost', 'colour'].filter((k) => a[k] === true).map((k) => FIELD[k]);
      const e = { eye: 'local', name: 'Local', model: vis.model, ok: !bad.length, label: bad.join(', ') || 'fine', note: String(a.note || ''), time: vis.time, hint: HINT, button: true };
      if (!out.local || String(e.time || '') > String(out.local.time || '')) out.local = e;
    }
    return out;
  }

  function when(t) { return t ? String(t).replace('T', ' ').slice(0, 16) : 'some time'; }

  function titleOf(e) {
    const who = `${e.name || NAMES[e.eye] || e.eye}${e.model ? ' (' + e.model + ')' : ''}`;
    const verdict = (e.ok === false ? 'flags this frame' : e.ok === true ? 'sees nothing wrong' : 'gave no verdict') + (e.fallback ? ' (Gemini failed on this frame: the local model checked it instead)' : '');
    const legsOnly = e.eye === 'gemini' && Array.isArray(e.defects) && e.defects.length && e.defects.every((k) => k === 'legs' || k === 'other');
    const legsNote = legsOnly ? `\nGemini's leg counts are unreliable (2 of 11 right in the blind bench): a leg count alone never drives a repair` : '';
    return `${who} ${verdict}, ${when(e.time)}${e.job ? ' · job #' + String(e.job).slice(-4) : e.button ? ' · the Ask button' : ''}\n${e.label || ''}${e.note && e.note !== e.label ? '\n' + e.note : ''}\n(${HINT})${legsNote}`;
  }

  /** One badge per eye that looked at this version, and the strong mark when two eyes flag it. */
  function badges(v) {
    const le = latest((v && v.qa) || {});
    const out = [];
    for (const eye of ['gemini', 'local', ...Object.keys(le).filter((k) => !['gemini', 'local'].includes(k))]) {
      const e = le[eye];
      if (!e) continue;
      const name = e.name || NAMES[eye] || eye;
      const bad = e.ok === false;
      out.push({ eye, bad, legacy: !!e.button, fallback: !!e.fallback, cls: `eye-badge eye-${eye in NAMES ? eye : 'other'}${bad ? ' bad' : e.ok === true ? ' ok' : ' none'}${e.fallback ? ' fallback' : ''}`,
        text: `${name}: ${bad ? (e.label || 'flagged') : e.ok === true ? 'fine' : 'no verdict'}`.slice(0, 60), title: titleOf(e), entry: e });
    }
    const flaggers = out.filter((b) => b.bad);
    if (flaggers.length >= 2) out.unshift({ eye: 'both', bad: true, cls: 'eye-badge eye-both', text: `${flaggers.map((b) => NAMES[b.eye] || b.eye).join(' + ')} both flag it`, title: `two eyes flag this frame: a stronger reason to look (and the loop repairs such frames first). Still ${HINT}.`, entry: null });
    return out;
  }

  /** The sheet cell's mini mark: the shown version's eyes that flag it (G, L, G+L), else a quiet mark that they looked. */
  function cellMark(s) {
    if (!s || !Array.isArray(s.versions)) return null;
    const v = s.versions.find((x) => x.id === s.effective) || null;
    if (!v) return null;
    const bs = badges(v).filter((b) => b.eye !== 'both');
    if (!bs.length) return null;
    const bad = bs.filter((b) => b.bad);
    if (!bad.length) return { cls: 'eye-mini ok', text: '✓', title: bs.map((b) => b.text).join(' · ') + ` (${HINT})` };
    const letters = bad.map((b) => (NAMES[b.eye] || b.eye).charAt(0)).join('+');
    return { cls: 'eye-mini ' + (bad.length >= 2 ? 'both' : 'eye-' + (bad[0].eye in NAMES ? bad[0].eye : 'other')), text: letters, title: bad.map((b) => b.text).join(' · ') + ` (${HINT})` };
  }

  function opsLine(st) {
    if (!st) return 'Gemini: asking…';
    if (st.missing) return 'Gemini: this Level Editor has no /api/eyes yet (pass 98): restart it';
    const t = st.today || {};
    const ready = t.quota_until ? `quota spent until ${t.quota_until} (the local model checks meanwhile)` : st.ready ? 'ready' : `not ready: ${st.why || '?'}`;
    const fb = Number(t.fallbacks) || 0;
    return `Gemini today: ${Number(t.calls) || 0} of ${Number(t.cap) || 0} calls (${Number(t.left) || 0} left) · ${ready}${st.auto ? ' · on for new requests' : ' · off for requests'}`
      + (fb ? ` · ${fb} fallback${fb === 1 ? '' : 's'} to the local model (Gemini failed${t.last_fallback && t.last_fallback.why ? ': ' + t.last_fallback.why : ''})` : '');
  }

  /** A finding item as a request card's badge, when it names its eye (pass 98 items); null for the older ones. */
  function findingBadge(i) {
    if (!i || !i.eye) return null;
    const name = NAMES[i.eye] || i.eye;
    return { text: `${name}: ${i.label || i.value || i.field || '?'}${i.slot != null ? ' f' + String(i.slot).padStart(2, '0') : ''}${i.group ? ' · ' + i.group : ''}`,
      title: `${i.note || i.rule || ''}${i.model ? ' · ' + i.model : ''} (${HINT})`, cls: `model eye-${i.eye in NAMES ? i.eye : 'other'}` };
  }

  return { NAMES, HINT, latest, badges, cellMark, opsLine, findingBadge, titleOf };
})();

if (typeof module !== 'undefined' && module.exports) module.exports = EyesModel;

const Eyes = (typeof document === 'undefined') ? null : (() => {
  const M = EyesModel;
  const el = (...a) => U.el(...a);
  const status = (msg, tone) => { if (typeof App !== 'undefined' && App.status) App.status(msg, tone); };
  let cache = null, cacheAt = 0;

  async function post(url, body) {
    try {
      const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}) });
      const j = await r.json().catch(() => ({}));
      if (!r.ok && !j.error) j.error = `HTTP ${r.status}`;
      return j;
    } catch (e) { return { ok: false, error: String(e) }; }
  }
  async function getJson(url) {
    try { const r = await fetch(url, { cache: 'no-store' }); if (r.status === 404) return { missing: true }; return await r.json(); } catch (e) { return { error: String(e) }; }
  }
  async function health(force) {
    if (!force && cache && Date.now() - cacheAt < 30000) return cache;
    cache = await getJson('/api/eyes'); cacheAt = Date.now();
    return cache;
  }
  const short = (id) => String(id || '').slice(-4);

  /** Wait for a job by id (the Jobs tab's poll), then call back with its record (done, failed, or null after 15 min). */
  function waitJob(id, cb) {
    const t0 = Date.now();
    const tick = async () => {
      if (typeof Jobs !== 'undefined' && typeof Jobs.poll === 'function') { try { await Jobs.poll(); } catch (_) { /* as it was */ } }
      const j = (typeof Jobs !== 'undefined' && Jobs.S && Array.isArray(Jobs.S.jobs)) ? Jobs.S.jobs.find((x) => x.id === id) : null;
      if (j && ['done', 'failed', 'cancelled', 'interrupted'].includes(j.state)) { cb(j); return; }
      if (Date.now() - t0 > 15 * 60 * 1000) { cb(null); return; }
      setTimeout(tick, 5000);
    };
    setTimeout(tick, 4000);
  }

  function jobWords(j) {
    if (!j) return 'no word from the job after 15 minutes (see the Jobs tab)';
    if (j.state !== 'done') return `the job ended ${j.state}${j.error ? ': ' + j.error : ''}`;
    const line = (j.eyes && j.eyes.line) || ((j.progress && j.progress.notes) || []).slice(-1)[0] || 'done';
    return line;
  }

  /** Ask Gemini about the chosen frames of one group; `done` is called when the job lands (the view reloads there). */
  async function askFrames(kind, id, code, base, view, slots, done) {
    const url = `/api/frames/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/${encodeURIComponent(code)}/${encodeURIComponent(base)}/${encodeURIComponent(view)}/ask_gemini`;
    const res = await post(url, { slots });
    if (!res || !res.ok) { status(`${id} ${code}: Gemini was not asked: ${(res && res.error) || 'refused'}`, 'bad'); return res; }
    const jid = res.job && res.job.id;
    status(`${id} ${code} ${base}/${view}: Gemini asked about frame${slots.length === 1 ? '' : 's'} ${slots.join(', ')} (job #${short(jid)}, one contact sheet${res.sheets > 1 ? ' x' + res.sheets : ''}; about 2 minutes). The badges appear on the frames when it answers.`, 'busy');
    if (jid) waitJob(jid, (j) => { status(`${id} ${code} ${base}/${view}: ${jobWords(j)} (${M.HINT})`, j && j.state === 'done' ? 'good' : 'bad'); health(true); if (done) done(j); });
    return res;
  }

  /** Check with Gemini: the whole look (every frame of every animation x view, sheets of up to 16). */
  async function checkLook(kind, id, code, done) {
    const h = await health(true);
    if (h && !h.missing && !h.error && h.today) {
      if (!confirm(`Check ${id} ${code} with Gemini? Every frame of every animation goes on sheets of up to 16 (one call a sheet, about 2 minutes each).\nToday: ${h.today.calls} of ${h.today.cap} calls used.`)) return null;
    }
    const res = await post('/api/eyes/check', { kind, id, code });
    if (!res || !res.ok) { status(`${id} ${code}: Gemini was not asked: ${(res && res.error) || 'refused'}`, 'bad'); return res; }
    const jid = res.job && res.job.id;
    status(`${id} ${code}: Check with Gemini queued (job #${short(jid)}, the local lane; tier 0, the local model and Gemini). Findings land on each frame as badges.`, 'good');
    if (jid) waitJob(jid, (j) => { status(`${id} ${code}: ${jobWords(j)} (${M.HINT})`, j && j.state === 'done' ? 'good' : 'bad'); health(true); if (done) done(j); });
    return res;
  }

  /** The look card's line: what the eyes say of the frames this look shows now (nothing when no eye looked). */
  async function lookLine(host, kind, id, code) {
    const res = await getJson(`/api/eyes/look/${encodeURIComponent(kind)}/${encodeURIComponent(id)}/${encodeURIComponent(code)}`);
    if (!host.isConnected || !res || !res.ok || !res.line) return;
    const both = Object.values(res.groups || {}).some((g) => (g.both || []).length);
    host.appendChild(el('div', { class: 'eye-line' + (both ? ' both' : ''), text: `Eyes: ${res.line}`, title: `per frame in the Frames view (badges); ${M.HINT}` }));
  }

  async function opsInto(box) {
    const st = await health(false);
    if (!box.isConnected) return;
    box.appendChild(el('div', { class: 'jops-sec eye-ops' + (st && st.today && st.today.fallbacks ? ' fallback' : ''), text: M.opsLine(st), title: `${(st && st.cap_key) || ''}; the ledger: ${(st && st.ledger) || ''}` }));
  }

  /** The badges of one version as spans (a click shows the full note in the status line). */
  function badgeSpans(v, opts) {
    const o = opts || {};
    return M.badges(v).filter((b) => !(o.skipLegacy && b.legacy)).map((b) => el('span', { class: 'fr-badge ' + b.cls, text: b.text, title: b.title, onclick: () => status(b.title.replace(/\n/g, ' · '), b.bad ? 'bad' : 'good') }));
  }

  function markCell(cell, s) {
    const m = M.cellMark(s);
    if (m) cell.appendChild(el('span', { class: m.cls, text: m.text, title: m.title }));
  }

  return { health, askFrames, checkLook, lookLine, opsInto, badgeSpans, markCell, waitJob };
})();
