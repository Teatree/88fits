// The Puppet method in the Level Editor (pass 71, lane PLE). Garry (2026-10-13): "I quite like this approach, add that in
// to LevelEditor with the considerations that I asked you about earlier": choose which 2D reference feeds the 3D model,
// or have one painted locally; preview the animated 3D model in the editor; the method in the job form like the others.
//
//   Puppet.viewer(url, o)       the 3D preview of a puppet's GLB: Google's <model-viewer> (vendored: vendor/model-viewer-
//                               4.0.0.min.js, so the page works offline), orbit by drag, zoom by wheel, a clip picker (the
//                               GLB's animations: run, idle), play / pause, speed, front / side / back. Lazy: a poster until
//                               clicked (a job card is rebuilt while it runs; WebGL contexts are few). {el, destroy}.
//   Puppet.section(doc)         the hero's puppet in his Art words section: the viewer, what is on disk (the arms-out
//                               paintings, the shape, the rig, the clips), the guides made from it, "+ New look from the
//                               puppet…" (the job form on hero_puppet).
//   Puppet.formSection(body, c) the job form's part for hero_puppet (jobs.js buildForm calls it): start from (the puppet
//                               he has, a new one, his .blend, a Mixamo FBX), the 3D reference per view (paint arms-out
//                               locally, any look's still, an uploaded picture, or none for side/back), the painter, the
//                               words, the clips, which views walk on depth and which on stick figures, the framing, the
//                               run size from the puppet, the fringe remap, reuse or repaint the walks' stills.
//   Puppet.wordsText(c)         the arms-out words for "Show the words that will be sent" (mirror of tools/puppet.py's
//                               templates; selftest_PLE pins the mirror).
//   Puppet.groupPick / rerollStage / outputCell   the job card's hooks (jobs.js): one pick per group (side, back), a
//                               re-run from a puppet stage, the GLB output.
'use strict';

const Puppet = (() => {
  const { el, clear } = U;
  const VIEWER_SRC = '/vendor/model-viewer-4.0.0.min.js';
  const STAGES = ['apose', 'shape', 'rig', 'anim', 'guides'];
  const STAGE_LABEL = { apose: 'the arms-out paintings', shape: 'the 3D shape (Hunyuan3D)', rig: 'the rig', anim: 'the clips and colours (GLB)', guides: 'the guides' };
  const VIEWS5 = ['front', 'fd', 'side', 'bd', 'back'];
  const DEPTH_DEFAULT = ['fd', 'side', 'bd', 'back'];
  // tools/puppet.py's templates (APOSE_FRONT, APOSE_SIDE, APOSE_BACK, SCREENS): {screen}, {who}; selftest_PLE checks the copy
  const SCREEN_WORDS = {
    blue: 'isolated on a flat solid bright blue (#0000FF) background that fills the entire frame, floating in empty space with no ground plane, no cast shadow, no text, no watermark',
    green: 'isolated on a flat solid bright green (#00FF00) background that fills the entire frame, floating in empty space with no ground plane, no cast shadow, no text, no watermark',
  };
  const WORDS = {
    front: 'Edit the reference image: the exact same character with the same head, face, outfit, colours, proportions and art style, full body seen straight from the front, standing straight and facing the viewer in a relaxed A-pose for a 3D model turnaround sheet: both arms hang down and out to the sides at 45 degrees from the body, so the hands are at the height of the hips but a forearm\'s length out to the side of them, the elbows straight, the hands open with the palms facing the legs, clear {screen} background between each arm and the torso all the way from the armpit to the hand; the legs straight and a little apart with a gap between them, the feet fully visible. Nothing in the hands. {who}',
    side: 'The first reference image shows a character standing in an A-pose, the arms held out to the sides. The second reference image shows how the same character looks from the side. Draw the same character seen from the side in a strict profile, facing to the right of the frame, standing straight: the arms reach out sideways toward and away from the viewer, so from the side the near arm hangs straight down over the side of the torso with the hand at the height of the hips, nothing held forward, the far arm hidden behind the body, the legs straight. Keep the outfit, colours, proportions and art style of the references, the same height as the first image. ',
    back: 'The first reference image shows a character standing in an A-pose, the arms held out to the sides. The second reference image shows how the same character looks from behind. Draw the same character in exactly the same A-pose seen directly from behind: the back of the head, no face visible, both arms held straight out away from the body and angled 45 degrees down from the shoulders, a wide gap between each arm and the torso, the legs straight and a little apart. Keep the outfit (what its back shows), the colours, the proportions and the art style of the references. ',
  };
  const S = { viewerP: null, recs: new Map(), style: false };

  // ------------------------------------------------------------------ helpers

  function injectStyle() {
    if (S.style || typeof document === 'undefined') return;
    S.style = true;
    const css = `
.pviewer { display: flex; flex-direction: column; gap: 6px; background: var(--surface-2); border: 1px solid var(--border); border-radius: 8px; padding: 8px; }
.pviewer model-viewer { width: 100%; height: 360px; background: radial-gradient(ellipse at 50% 40%, #34332f 0%, #191917 75%); border-radius: 6px; --poster-color: transparent; }
.pviewer .pv-poster { position: relative; width: 100%; height: 360px; display: flex; align-items: center; justify-content: center; background: #191917 center / contain no-repeat; border-radius: 6px; cursor: pointer; }
.pviewer .pv-poster b { background: rgba(13,13,13,0.82); border: 1px solid var(--border-2); padding: 8px 14px; border-radius: 20px; font-size: 0.95rem; }
.pviewer .pv-bar { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; font-size: 0.82rem; color: var(--ink-2); }
.pviewer .pv-bar select { font-size: 0.82rem; }
.pviewer .pv-note { font-size: 0.76rem; color: var(--muted); }
.pviewer.compact model-viewer, .pviewer.compact .pv-poster { height: 240px; }
.joutput.joutput-glb { max-width: 440px; width: 440px; }
.joutput.joutput-glb .pviewer { width: 100%; }
.psec { display: flex; flex-direction: column; gap: 8px; margin: 8px 0; padding: 10px; border: 1px solid var(--border); border-radius: 8px; background: var(--surface); }
.psec h4 { margin: 0; font-size: 0.95rem; }
.psec .pfacts { display: grid; grid-template-columns: max-content 1fr; gap: 3px 12px; font-size: 0.82rem; }
.psec .pfacts > span:nth-child(odd) { color: var(--muted); }
.pthumbs { display: flex; flex-wrap: wrap; gap: 6px; }
.pthumbs figure { margin: 0; display: flex; flex-direction: column; align-items: center; gap: 2px; font-size: 0.72rem; color: var(--muted); }
.pthumbs img { width: 96px; height: 96px; object-fit: contain; background: var(--surface-2); border-radius: 4px; cursor: zoom-in; }
.pstages { display: flex; flex-wrap: wrap; gap: 4px; }
.pstages span { font-size: 0.74rem; padding: 2px 8px; border-radius: 10px; border: 1px solid var(--border); color: var(--muted); }
.pstages span.on { color: var(--good); border-color: rgba(12,163,12,0.5); }
.pref { display: grid; grid-template-columns: 70px 1fr 104px; gap: 8px; align-items: center; padding: 6px; border: 1px solid var(--border); border-radius: 6px; background: var(--surface-2); margin: 4px 0; }
.pref img { width: 100px; height: 100px; object-fit: contain; background: #191917; border-radius: 4px; cursor: zoom-in; }
.pref .pref-src { display: flex; flex-direction: column; gap: 4px; }
.pref .pref-src select { max-width: 100%; }
.pviews { display: flex; flex-wrap: wrap; gap: 8px; }
.pviews label { display: inline-flex; gap: 4px; align-items: center; padding: 3px 8px; border: 1px solid var(--border); border-radius: 12px; font-size: 0.8rem; }
.pviews label.depth { border-color: rgba(57,135,229,0.6); }
.pwarn { font-size: 0.8rem; color: var(--warn); }
.pp-group { font-size: 0.78rem; color: var(--ink-2); margin: 6px 0 2px; }
select.pp-wide { min-width: 420px; max-width: 100%; }
.pref .pref-src select { width: 100%; }
`;
    const st = document.createElement('style');
    st.textContent = css;
    document.head.appendChild(st);
  }

  async function fetchJson(url, dflt) { try { const r = await fetch(url, { cache: 'no-store' }); if (!r.ok) return dflt; return await r.json(); } catch (_) { return dflt; } }

  /** The hero's puppet record (GET /api/puppet/<id>), cached for 10 s (the form redraws often). */
  function record(id, fresh) {
    const hit = S.recs.get(id);
    if (hit && !fresh && Date.now() - hit.at < 10000) return hit.p;
    const p = fetchJson(`/api/puppet/${encodeURIComponent(id)}`, { ok: false, error: 'the server has no puppet route (an editor from before pass 71: restart it)' });
    S.recs.set(id, { at: Date.now(), p });
    return p;
  }

  /** model-viewer, loaded once as a module from the page's own server (offline). */
  function ensureViewer() {
    if (S.viewerP) return S.viewerP;
    S.viewerP = new Promise((resolve, reject) => {
      if (typeof customElements !== 'undefined' && customElements.get('model-viewer')) { resolve(true); return; }
      const sc = document.createElement('script');
      sc.type = 'module';
      sc.src = VIEWER_SRC;
      sc.onerror = () => { S.viewerP = null; reject(new Error(`${VIEWER_SRC} did not load (tools/level_editor/vendor/)`)); };
      document.head.appendChild(sc);
      customElements.whenDefined('model-viewer').then(() => resolve(true));
    });
    return S.viewerP;
  }

  function zoom(url, label) { if (typeof StripPlayer !== 'undefined') StripPlayer.openImage(url, label || url); }

  // ------------------------------------------------------------------ the viewer

  /** A puppet's GLB in 3D. o: {poster, title, compact, autoload, clip ('run')}. The GLB's own clips fill the picker
   *  (model-viewer's availableAnimations); the camera starts on the front at the game's 25-degree pitch. */
  function viewer(url, o) {
    injectStyle();
    const opts = o || {};
    const wrap = el('div', { class: 'pviewer' + (opts.compact ? ' compact' : '') });
    const stage = el('div');
    const clipSel = el('select', { title: 'the GLB\'s clips' }, el('option', { value: '', text: '(loading)' }));
    const playBtn = el('button', { type: 'button', class: 'btn small', text: '❚❚ Pause', disabled: true });
    const speed = el('select', { title: 'playback speed' }, ['0.25', '0.5', '1', '1.5'].map((v) => el('option', { value: v, text: `${v}×`, selected: v === '1' })));
    const camBtns = [['front', '0deg'], ['3/4', '45deg'], ['side', '90deg'], ['back', '180deg']].map(([label, yaw]) => el('button', { type: 'button', class: 'btn small ghost', text: label, disabled: true, dataset: { yaw } }));
    const note = el('span', { class: 'pv-note', text: 'drag to turn, wheel to zoom, right-drag to pan' });
    const bar = el('div', { class: 'pv-bar' }, el('span', { text: 'clip' }), clipSel, playBtn, speed, el('span', { class: 'muted', text: 'camera' }), camBtns, note);
    wrap.append(stage, bar);
    if (opts.title) wrap.prepend(el('div', { class: 'pv-note', text: opts.title }));
    let mv = null;
    let alive = true;
    function load() {
      if (mv || !alive) return;
      clear(stage);
      stage.appendChild(el('div', { class: 'pv-poster', style: opts.poster ? `background-image:url('${opts.poster}')` : '' }, el('b', { text: 'loading the 3D viewer…' })));
      ensureViewer().then(() => {
        if (!alive) return;
        mv = document.createElement('model-viewer');
        mv.setAttribute('src', url);
        mv.setAttribute('camera-controls', '');
        mv.setAttribute('autoplay', '');
        mv.setAttribute('shadow-intensity', '0.7');
        mv.setAttribute('exposure', '1.05');
        mv.setAttribute('environment-image', 'neutral');
        mv.setAttribute('interaction-prompt', 'none');
        mv.setAttribute('camera-orbit', '0deg 70deg auto');
        mv.setAttribute('animation-name', opts.clip || 'run');
        mv.setAttribute('alt', opts.title || 'the 3D puppet');
        mv.addEventListener('load', () => {
          const names = Array.isArray(mv.availableAnimations) ? mv.availableAnimations : [];
          clear(clipSel);
          for (const n of names) clipSel.appendChild(el('option', { value: n, text: n, selected: n === (opts.clip || 'run') }));
          if (!names.length) clipSel.appendChild(el('option', { value: '', text: '(no clips)' }));
          playBtn.disabled = !names.length;
          for (const b of camBtns) b.disabled = false;
          note.textContent = `${names.length} clip${names.length === 1 ? '' : 's'}: ${names.join(', ') || 'none'} · drag to turn, wheel to zoom, right-drag to pan`;
          try { mv.play(); } catch (_) { /* a GLB without clips */ }
        });
        mv.addEventListener('error', (e) => { note.textContent = `the GLB did not load: ${(e && e.detail && e.detail.sourceError && e.detail.sourceError.message) || url}`; note.className = 'pwarn'; });
        clear(stage);
        stage.appendChild(mv);
      }).catch((e) => { clear(stage); stage.appendChild(el('div', { class: 'pwarn', text: e.message })); });
    }
    clipSel.addEventListener('change', () => { if (!mv) return; mv.animationName = clipSel.value; mv.currentTime = 0; mv.play(); playBtn.textContent = '❚❚ Pause'; });
    playBtn.addEventListener('click', () => { if (!mv) return; if (mv.paused) { mv.play(); playBtn.textContent = '❚❚ Pause'; } else { mv.pause(); playBtn.textContent = '▶ Play'; } });
    speed.addEventListener('change', () => { if (mv) mv.timeScale = Number(speed.value) || 1; });
    for (const b of camBtns) b.addEventListener('click', () => { if (!mv) return; mv.cameraOrbit = `${b.dataset.yaw} 70deg auto`; mv.cameraTarget = 'auto auto auto'; });
    if (opts.autoload) load();
    else {
      const poster = el('div', { class: 'pv-poster', title: 'click: the 3D puppet with its clips', style: opts.poster ? `background-image:url('${opts.poster}')` : '' }, el('b', { text: '▶ 3D puppet: click to load' }));
      poster.addEventListener('click', load);
      stage.appendChild(poster);
    }
    return { el: wrap, load, destroy() { alive = false; if (mv) { try { mv.pause(); } catch (_) { /* gone */ } mv.remove(); mv = null; } } };
  }

  // ------------------------------------------------------------------ the hero's Art section

  /** The hero's puppet (tools/dl/puppet/<id>/) in his Art words section. */
  function section(doc) {
    injectStyle();
    const box = el('div', { class: 'psec', 'data-key': 'puppet' });
    box.appendChild(el('h4', { text: 'The 3D puppet (the Puppet method, pass 71)' }));
    const body = el('div', { text: 'reading tools/dl/puppet…', class: 'muted small' });
    box.appendChild(body);
    record(doc.id).then((r) => fillSection(body, doc, r));
    return box;
  }

  function fillSection(body, doc, r) {
    clear(body);
    body.className = '';
    if (!r || !r.ok) { body.appendChild(el('div', { class: 'pwarn', text: (r && r.error) || 'no answer' })); return; }
    const has = r.stages || {};
    const newLook = () => { if (typeof Assets !== 'undefined' && Assets.openJobForm) Assets.openJobForm(doc, { mode: 'look', method: 'hero_puppet' }); };
    if (!has.apose && !has.shape && !has.anim) {
      body.appendChild(el('p', { class: 'help', text: `${r.name} has no puppet yet. The Puppet method paints him with his arms out (or takes a picture you choose), makes a 3D shape of it with Hunyuan3D on the AI server, rigs it with Mixamo's bones in Blender, plays a Mixamo clip on it, and walks his look on its own OpenPose and depth guides.` }));
      body.appendChild(el('div', { class: 'alt-actions' }, el('button', { class: 'btn small primary', type: 'button', text: '+ Make a puppet look…', onclick: newLook })));
      return;
    }
    if (r.glb) {
      const v = viewer(r.glb, { title: `${r.glb_file} · clip ${r.clip || '?'} · idle ${r.idle || '?'}` });
      body.appendChild(v.el);
      body.__viewer = v;
    }
    const stages = el('div', { class: 'pstages' }, STAGES.map((s) => el('span', { class: (s === 'guides' ? (r.guides || []).length > 0 : has[s]) ? 'on' : '', text: `${(s === 'guides' ? (r.guides || []).length > 0 : has[s]) ? '✓' : '·'} ${STAGE_LABEL[s]}` })));
    body.appendChild(stages);
    const facts = el('div', { class: 'pfacts' });
    const fact = (k, v) => facts.append(el('span', { text: k }), el('span', { text: v }));
    fact('folder', r.dir);
    if (r.blend) fact('the rig (.blend)', `${r.blend}: change the joints or the weights in Blender, save, then a new look "from his .blend"${r.rig_howto ? ' (how: ' + r.rig_howto + ')' : ''}`);
    if (r.clip) fact('clips in the GLB', `run = ${r.clip}; idle = ${r.idle}`);
    if (r.picks) fact('arms-out picks', Object.entries(r.picks).map(([k, v]) => `${k} c${v}`).join(', '));
    body.appendChild(facts);
    const th = el('div', { class: 'pthumbs' });
    for (const [k, label] of [['apose_front', 'arms-out front'], ['apose_side', 'arms-out side'], ['apose_back', 'arms-out back'], ['shape_preview', 'the shape (clay)'], ['rig_front', 'the rig (x-ray)'], ['preview', 'turntable and run']]) {
      const u = r.files && r.files[k];
      if (!u) continue;
      const img = el('img', { src: u, alt: '', loading: 'lazy', title: label });
      img.addEventListener('click', () => zoom(u, `${r.name} · ${label}`));
      th.appendChild(el('figure', {}, img, el('figcaption', { text: label })));
    }
    if (th.children.length) body.appendChild(th);
    if ((r.guides || []).length) {
      body.appendChild(el('div', { class: 'pp-group', text: 'Guides made from it (a puppet look names them in its recipe: pose_drivers, ctl_drivers, run_fit)' }));
      for (const g of r.guides) {
        const ratios = g.ratios && Object.keys(g.ratios).length ? ' · run/idle ' + VIEWS5.filter((v) => g.ratios[v] != null).map((v) => `${v} ${Number(g.ratios[v]).toFixed(3)}`).join(', ') : '';
        const line = el('div', { class: 'small' }, el('code', { text: g.name }), el('span', { class: 'muted', text: ` framed by the ${g.frame} · ${String(g.clip || '').split('/').pop()}${g.depth ? ' · depth ' + g.depth : ''}${ratios}` }));
        if (g.sheet) line.appendChild(el('a', { href: '#', text: ' sheet', onclick: (e) => { e.preventDefault(); zoom(g.sheet, g.name); } }));
        body.appendChild(line);
      }
    }
    body.appendChild(el('div', { class: 'alt-actions' },
      el('button', { class: 'btn small primary', type: 'button', text: '+ New look from the puppet…', title: 'the job form on the Puppet method: the stages on disk are kept (no new shape or rig), the walks are made on the puppet\'s guides', onclick: newLook }),
      el('span', { class: 'muted small', text: 'a new puppet, his .blend or a Mixamo FBX: "Start from" in that form' })));
  }

  // ------------------------------------------------------------------ the job form

  function defaults(played) {
    return { source: played || '', stills: 'reuse', refs: { front: 'paint', side: 'paint', back: 'paint' }, painter: 'klein', steps: 0, seeds: 4, seed: 0,
      words: { front: '', side: '', back: '' }, screen: '', tries: 2, faces: 60000, reuse: 'auto', fbx: '', clip: 'running.fbx', idle: '', frame: 'soles',
      face: 'nose', depth_views: DEPTH_DEFAULT.slice(), run_fit: true, fringe: true };
  }

  /** Pass 71 follow-up (Garry: every improvement a setting of the method, visible, with plain help, on by default): the
   *  walk settings, in the order the form shows them; `key` is the field of spec.puppet (and of the look's
   *  recipe.puppet, where the job records them), `on` the value that means "on". */
  const WALK_SETTINGS = [
    { key: 'run_fit', on: true, off: false, label: 'Size from the 3D model', text: 'size each view\'s walk from the 3D model\'s own heights (run_fit)',
      help: 'each view\'s walk stands as tall as the 3D model\'s run stands against its idle in that view (by the middle frame), instead of its tallest frame being stretched to the standing height. Prevents a crouching side run coming out taller than the others; no Run size to tune. On by default.' },
    { key: 'frame', on: 'soles', off: 'ankles', label: 'Frame by the soles', text: 'frame the stick figures by the soles (frame: soles)',
      help: 'the stick figures sit in the canvas measured from the lowest sole, not the ankles, so chunky boots or long feet stay inside the picture (MAY-P\'s front walk left the canvas at the bottom). New guides are made when this differs from the ones on disk; looks keep theirs. On by default.' },
    { key: 'fringe', on: true, off: false, label: 'Clean colour fringes', text: 'clean up the colour fringing on sleeves and boots (fringe_remap)',
      help: 'colours the view\'s own painting does not have (the rainbow fringes the video model leaves on sleeves and boots) are turned into its nearest own colour; the painting\'s colours stay. On by default.' },
    { key: 'face', on: 'nose', off: 'head', label: 'Keep the face angle', text: 'keep the correct face angle: the ears from the nose (face: nose)',
      help: 'the stick figures\' ears are placed from the 3D model\'s measured nose, so a side view stays in profile (with the ears on the head bone May\'s side run turned its face to the camera), and the back and back-diagonal views are walked on words without the face (a depth video cannot tell a front from a back: MAY-R\'s first back walk ran facing the camera). The depth video has no face at all: keep the front on the stick figure above. On by default.' },
  ];
  /** Whether a walk setting is on: a yes/no is on unless false (absent = the default, on); a choice is on at its `on`. */
  function isOn(pp, s) { return typeof s.on === 'boolean' ? pp[s.key] !== false : (pp[s.key] == null ? true : pp[s.key] === s.on); }

  /** The puppet part of the hero_puppet job form (spec.job.puppet; jobs.py puppet_spec reads it). */
  function formSection(body, c) {
    injectStyle();
    const { id, state, dlg } = c;
    const spec = state.spec;
    if (!spec.job) spec.job = {};
    if (c.puppetRec === undefined) {
      c.puppetRec = null;
      record(id, true).then((r) => { c.puppetRec = r || { ok: false }; if (dlg && dlg.isConnected) c.draw(); });
    }
    const r = c.puppetRec && c.puppetRec.ok ? c.puppetRec : null;
    // the settings the look's recipe records (recipe.puppet: an edited job or a re-roll), then the job's own
    const recorded = spec.recipe && spec.recipe.puppet && typeof spec.recipe.puppet === 'object' ? spec.recipe.puppet : {};
    const pp = spec.job.puppet = Object.assign(defaults(r ? r.played : ''), recorded, spec.job.puppet || {});
    if (typeof pp.depth_views === 'string') pp.depth_views = pp.depth_views.split(',').map((x) => x.trim()).filter(Boolean);
    if (!pp.refs || typeof pp.refs !== 'object') pp.refs = { front: 'paint', side: 'paint', back: 'paint' };
    if (!pp.words || typeof pp.words !== 'object') pp.words = { front: '', side: '', back: '' };
    if (!Array.isArray(pp.depth_views)) pp.depth_views = DEPTH_DEFAULT.slice();
    if (!pp.source && r) pp.source = r.played;
    const line = (label, control, help) => el('div', { class: 'fieldline' }, el('label', { text: label, title: help || '' }), control, help ? el('div', { class: 'fh', text: help }) : null);
    const sel = (opts, cur, on) => { const s = el('select', { class: 'pp-wide' }); for (const [v, t] of opts) s.appendChild(el('option', { value: v, text: t, selected: String(cur) === String(v) })); s.addEventListener('change', () => on(s.value)); return s; };
    const num = (cur, on, min, max) => { const n = el('input', { type: 'number', class: 'num', value: cur, min, max, step: 1 }); n.addEventListener('change', () => on(Math.max(min, Math.min(max, Math.round(Number(n.value) || min))))); return n; };
    const cb = (cur, label, on, title) => { const x = el('input', { type: 'checkbox' }); x.checked = !!cur; x.addEventListener('change', () => on(x.checked)); return el('label', { class: 'cb', title: title || '' }, x, el('span', { text: label })); };

    body.appendChild(el('h2', {}, 'The 3D puppet', el('small', { text: 'tools/puppet.py: the arms-out paintings → Hunyuan3D\'s shape → the rig → the clip on it → its guides; then the walks of this look on them' })));
    if (!c.puppetRec) { body.appendChild(el('p', { class: 'help', text: 'reading the hero\'s puppet (tools/dl/puppet)…' })); return; }
    if (!r) { body.appendChild(el('p', { class: 'help warn-text', text: `no puppet record: ${(c.puppetRec && c.puppetRec.error) || 'the server did not answer'}` })); return; }
    const has = r.stages || {};
    const hasAny = has.apose || has.shape || has.anim;
    // what he has
    const st = el('div', { class: 'pstages' }, STAGES.map((s) => { const on = s === 'guides' ? (r.guides || []).length > 0 : has[s]; return el('span', { class: on ? 'on' : '', text: `${on ? '✓' : '·'} ${STAGE_LABEL[s]}` }); }));
    body.appendChild(line('on disk', st, hasAny ? `${r.dir}: what the puppet has; "the puppet he has" keeps it (no new paintings, shape or rig)` : `${r.name} has no puppet yet: every stage is made`));
    if (r.glb) {
      if (c.__pv) c.__pv.destroy();   // the form redraws on every change: one viewer at a time
      const v = viewer(r.glb, { compact: true, title: `${r.glb_file} (clip ${r.clip}, idle ${r.idle})` });
      c.__pv = v;
      dlg.__players = dlg.__players || [];
      dlg.__players.push(v);
      body.appendChild(line('preview', v.el, 'the puppet as it is now; a new clip below makes the GLB again'));
    }
    // 1. start from
    const reuseOpts = [['auto', hasAny ? 'the puppet he has (what is on disk is kept)' : 'a new puppet (nothing on disk yet)'], ['fresh', 'a new puppet (the old one moved aside to old/<stamp>/)']];
    if (r.blend) reuseOpts.push(['blend', `his .blend (a rig you changed in Blender): ${r.blend}`]);
    reuseOpts.push(['fbx', 'a Mixamo-rigged FBX (mixamo.com\'s auto-rigger)']);
    body.appendChild(line('start from', sel(reuseOpts, pp.reuse, (v) => { pp.reuse = v; c.draw(); }), 'what the puppet is made from: the stages on disk are kept unless you start a new one; his .blend or an FBX skips the paintings, the shape and the rig (the clips, the colours and the guides are made again)'));
    if (pp.reuse === 'fbx') {
      const fbxs = ((c.refs && c.refs['3d']) || []).filter((u) => /\.fbx$/i.test(u.file || '')).map((u) => [`tools/dl/uploads/3d/${u.slug}/${u.file}`, `${u.slug}/${u.file}`]);
      body.appendChild(line('the FBX', fbxs.length ? sel([['', '(choose an uploaded FBX)']].concat(fbxs), pp.fbx, (v) => { pp.fbx = v; }) : el('span', { class: 'pwarn', text: 'no FBX uploaded yet: + New pose driver… → upload the FBX, then come back' }),
        'download from mixamo.com "FBX Binary, Original Pose, With Skin" (not T-pose: the colours come from the arms-out paintings); its bones get the mixamorig: names'));
    }
    const makesShape = pp.reuse === 'fresh' || (pp.reuse === 'auto' && !has.shape);
    const lookOpts = (r.looks || []).filter((l) => l.stills && l.stills.front).map((l) => [l.code, `${l.code || 'his own paintings'}${l.played ? ' (played)' : ''}${l.shelved ? ' (shelved)' : ''} · stills ${l.slug || '(his own)'}`]);
    body.appendChild(line('source look', sel(lookOpts.length ? lookOpts : [[pp.source, pp.source || '(none)']], pp.source, (v) => { pp.source = v; c.draw(); }),
      'the look whose stills the arms-out paintings are edited from (and, below, the walks\' stills by default); the one he is played in by default'));
    // 2. the 3D reference per view
    if (makesShape) {
      body.appendChild(el('h3', { class: 'jsub', text: 'The 3D reference: the picture each view of the shape is made from' }));
      body.appendChild(el('p', { class: 'help', text: 'Hunyuan3D makes the 3D shape from a front, a back and a side picture (the side mirrored for the other side). The arms must stand clear of the body: a hanging arm fuses into the torso and cannot be rigged. "Paint arms-out locally" edits the source look\'s still into an A-pose (candidates; you pick one on the job card).' }));
      const src = (r.looks || []).find((l) => l.code === pp.source) || null;
      for (const v of ['front', 'side', 'back']) body.appendChild(refRow(v, pp, r, c, src));
      body.appendChild(line('painter', sel([['klein', 'Flux.2 Klein (about 20 s a candidate)'], ['dev', 'Flux.2 dev (4-5 min a candidate, a restart each)']], pp.painter, (v) => { pp.painter = v; c.draw(); }), 'the arms-out paintings\' painter (the Model settings above are the walks\' stills)'));
      body.appendChild(line('passes', num(pp.steps || 0, (v) => { pp.steps = v; }, 0, 60), '0 = the painter\'s own (Klein 4, dev 8 with Turbo)'));
      body.appendChild(line('front candidates', num(pp.seeds || 4, (v) => { pp.seeds = v; }, 1, 12), 'arms-out fronts to pick from; the side and the back get half, at least 3'));
      body.appendChild(line('screen', sel([['', `the look's own (${r.screen || 'blue'})`], ['green', 'green (a blue figure: Jeżyk)'], ['blue', 'blue']], pp.screen || '', (v) => { pp.screen = v; }), 'the screen the arms-out paintings are made on and keyed off'));
      body.appendChild(line('Hunyuan3D tries', num(pp.tries || 2, (v) => { pp.tries = v; }, 1, 6), 'shapes to pick from (about 90 s each on the R9700; ComfyUI restarts before and after)'));
      body.appendChild(line('triangles', num(pp.faces || 60000, (v) => { pp.faces = v; }, 5000, 200000), 'the cleaned mesh\'s budget (60,000: the trial\'s; more = slower Blender)'));
    }
    // 3. the clips
    const clips = (r.clips || []).map((f) => [f, f]);
    body.appendChild(el('h3', { class: 'jsub', text: 'The clips: Mixamo FBX files in tools/dl/mixamo/' }));
    body.appendChild(line('moving clip', sel(clips.length ? clips : [['running.fbx', 'running.fbx']], pp.clip, (v) => { pp.clip = v; }), 'retargeted onto the rig as "run"; another clip than the GLB has makes the GLB and the guides again (the old GLB moved aside)'));
    body.appendChild(line('idle', sel([['', 'procedural (arms down, a breath, a sway)']].concat(clips), pp.idle || '', (v) => { pp.idle = v; }), 'the standing clip ("idle"): no Mixamo idle is on disk yet; download one "In Place", 30 fps, into tools/dl/mixamo/'));
    // 4. the walks
    body.appendChild(el('h3', { class: 'jsub', text: 'The walks of this look' }));
    const vw = el('div', { class: 'pviews' });
    for (const v of VIEWS5) {
      const on = pp.depth_views.includes(v);
      const x = el('input', { type: 'checkbox' }); x.checked = on;
      x.addEventListener('change', () => { pp.depth_views = VIEWS5.filter((w) => (w === v ? x.checked : pp.depth_views.includes(w))); c.draw(); });
      vw.appendChild(el('label', { class: on ? 'depth' : '', title: on ? 'walked by Wan 2.2 Fun Control on the puppet\'s depth video' : 'walked by Wan Animate on the puppet\'s OpenPose stick figure' }, x, el('span', { text: `${v}: ${on ? 'depth' : 'stick figure'}` })));
    }
    body.appendChild(line('Depth or stick figure', vw, 'per view: ticked = the depth video of the 3D model (Wan Fun Control: the body\'s own shape and size, but no face), unticked = the stick figure from its bones (Wan Animate: with the face points). Keeps the face right: the front walks on the stick figure (the depth video painted May\'s face crosshatched). The trial\'s best mix: depth for fd, side, bd and back, the stick figure for the front.'));
    // pass 71 follow-up: the four improvements, each a named setting with plain help, on by default
    for (const st of WALK_SETTINGS) {
      body.appendChild(line(st.label, cb(isOn(pp, st), st.text, (v) => { pp[st.key] = v ? st.on : st.off; }), st.help));
    }
    const srcLook = (r.looks || []).find((l) => l.code === pp.source);
    body.appendChild(line('the walks\' stills', sel([['reuse', `reuse ${pp.source || 'the source look'}'s stills (${srcLook ? (srcLook.slug || 'his own') : '?'}): nothing painted again`], ['repaint', 'paint this look\'s own stills (the Model settings above)']], pp.stills, (v) => { pp.stills = v; }), 'the walks are Wan clips of these stills; the badge and the cut-out candidates follow the look\'s front still'));
    const m = (c.all || []).find((x) => x.id === 'hero_puppet');
    if (m && m.stage_times) body.appendChild(el('div', { class: 'jnote', text: 'Measured in the trial: ' + Object.entries(m.stage_times).map(([k, v]) => `${k} ${v}`).join(' · ') }));
  }

  /** One view's 3D reference: paint arms-out locally, a still of any look, an uploaded picture, or none (side/back). */
  function refRow(view, pp, r, c, src) {
    const cur = String(pp.refs[view] || 'paint');
    const s = el('select');
    s.appendChild(el('option', { value: 'paint', text: `paint arms-out locally (an edit of ${src ? src.code + '\'s' : 'the source look\'s'} ${view === 'front' ? 'front' : view + ' and the picked front'})`, selected: cur === 'paint' }));
    const grp1 = el('optgroup', { label: 'a still of a look (as it is: arms down fuse into the body)' });
    let thumb = '';
    for (const l of r.looks || []) {
      const st = l.stills && l.stills[view];
      if (!st) continue;
      const v = 'still:' + st.key;
      grp1.appendChild(el('option', { value: v, text: `${l.code ? l.code + "'s" : 'his own'} ${view} (${st.key})`, selected: cur === v }));
      if (cur === v) thumb = st.url;
    }
    if (grp1.children.length) s.appendChild(grp1);
    const ups = ((c.refs && c.refs['2d']) || []);
    if (ups.length) {
      const grp2 = el('optgroup', { label: 'an uploaded picture (tools/dl/uploads/2d)' });
      for (const u of ups) {
        const v = u.path || `tools/dl/uploads/2d/${u.name}`;
        grp2.appendChild(el('option', { value: v, text: u.name, selected: cur === v }));
        if (cur === v) thumb = u.url;
      }
      s.appendChild(grp2);
    }
    if (view !== 'front') s.appendChild(el('option', { value: 'none', text: `none: the shape without a ${view} picture`, selected: cur === 'none' }));
    if (cur === 'paint') thumb = src && src.stills && src.stills[view] ? src.stills[view].url : '';
    s.addEventListener('change', () => { pp.refs[view] = s.value; c.draw(); });
    const srcBox = el('div', { class: 'pref-src' }, s);
    if (cur === 'paint') {
      const ta = el('textarea', { rows: 3, placeholder: `empty = the template (Show the words below): ${WORDS[view].slice(0, 120)}…` });
      ta.value = pp.words[view] || '';
      ta.addEventListener('change', () => { pp.words[view] = ta.value.trim(); });
      srcBox.appendChild(ta);
      srcBox.appendChild(el('span', { class: 'muted small', text: 'the edit\'s words: empty = the template (the arms 45 degrees out, the hands at hip height, clear screen between the arms and the body)' }));
    } else if (cur !== 'none') srcBox.appendChild(el('span', { class: 'pwarn', text: 'used as it is: if its arms touch the body, the rig cannot free them; an arms-out picture is best' }));
    const img = thumb ? el('img', { src: thumb, alt: '', title: cur === 'paint' ? 'the still the arms-out painting is edited from' : 'the picture the shape is made from' }) : el('div', { class: 'muted small', text: cur === 'none' ? 'left out' : '(no picture)' });
    if (thumb) img.addEventListener('click', () => zoom(thumb, `${view}: ${cur}`));
    return el('div', { class: 'pref' }, el('b', { text: view }), srcBox, img);
  }

  /** The arms-out words for "Show the words that will be sent" (tools/puppet.py's templates, or the view's own). */
  function wordsText(c) {
    const pp = (c.state.spec.job && c.state.spec.job.puppet) || defaults('');
    const r = c.puppetRec && c.puppetRec.ok ? c.puppetRec : null;
    const screen = pp.screen || (r && r.screen) || 'blue';
    const who = c.contentJson ? String(c.contentJson.appearance || String(c.contentJson.art_prompt || '').split(';')[0]).trim().replace(/[. ]+$/, '') : '';
    const lines = ['The Puppet method (tools/puppet.py), the arms-out paintings (an edit each, ' + (pp.painter === 'dev' ? 'Flux.2 dev' : 'Flux.2 Klein') + '):'];
    for (const v of ['front', 'side', 'back']) {
      const ref = (pp.refs || {})[v] || 'paint';
      if (ref !== 'paint') { lines.push(`  ${v}: ${ref === 'none' ? 'left out of the shape' : 'the picture ' + ref + ', as it is (no painting)'}`); continue; }
      const own = (pp.words || {})[v];
      const text = own ? own + ' ' : WORDS[v].replace('{screen}', screen).replace('{who}', who ? `The character: ${who}. ` : '');
      lines.push(`  ${v} (references: ${v === 'front' ? 'the source look\'s front still' : 'the picked front, then the source look\'s ' + v + ' still'}):`);
      lines.push('    ' + text + (SCREEN_WORDS[screen] || SCREEN_WORDS.blue) + '.');
    }
    lines.push('Then Hunyuan3D-2mv (ComfyUI\'s own nodes): the front, the back, the side as "right" and its mirror as "left", keyed onto white; 30 steps, cfg 5, octree 380.');
    lines.push(`The clip: ${pp.clip || 'running.fbx'} as "run", idle ${pp.idle || 'procedural'}; guides framed by the ${pp.frame || 'soles'}, the ears ${pp.face === 'head' ? 'on the head bone' : 'from the nose'}; depth for ${(pp.depth_views || []).join(', ') || 'no view'}, the stick figure for the rest; size from the 3D model ${pp.run_fit === false ? 'off' : 'on'}; colour fringes ${pp.fringe === false ? 'kept' : 'cleaned'}.`);
    return lines.join('\n');
  }

  // ------------------------------------------------------------------ the job card's hooks

  /** One pick per group (the side and the back are picked together): the choice string jobs.pick takes ("side=1,back=0"),
   *  or '' while a group has none. */
  function groupPick(picked) {
    const vals = Object.values(picked || {}).filter(Boolean);
    return vals.join(',');
  }

  /** The GLB as a job card output: the lazy viewer (destroyed with the card). */
  function outputCell(o, holder) {
    const v = viewer(o.url, { compact: true, title: `${o.file || ''}${o.blend ? ' · rig: ' + o.blend : ''}` });
    if (holder) holder.push(v);
    return v.el;
  }

  /** The re-roll panel's puppet row: run the job again from one puppet stage. */
  function rerollStage(box, picks) {
    const s = el('select');
    s.appendChild(el('option', { value: '', text: '(no: the stages on disk are kept)' }));
    for (const st of STAGES) s.appendChild(el('option', { value: st, text: `from ${STAGE_LABEL[st]}` }));
    s.addEventListener('change', () => { picks.stage = s.value; });
    box.appendChild(el('div', { class: 'row' }, el('span', { class: 'muted small', text: 'run the puppet again from a stage (its outputs and the later ones move to tools/dl/puppet/<hero>/old/<stamp>/; new guides get a new folder):' }), s));
  }

  return { viewer, section, formSection, refRow, wordsText, groupPick, outputCell, rerollStage, record, ensureViewer, defaults, isOn, WALK_SETTINGS, WORDS, SCREEN_WORDS, STAGES, VIEWS5, DEPTH_DEFAULT, VIEWER_SRC };
})();
if (typeof module !== 'undefined') module.exports = Puppet;
