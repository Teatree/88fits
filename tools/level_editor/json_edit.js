'use strict';
// Pass 114 (lane EDITOR; Garry: "Allow for editing the JSON directly in the 'Show JSON' window"): one JSON editor for the
// page. The Enemies / Heroes / Items document's "Show / edit the JSON" window (assets.js), the Boss attacks tab's, and the
// inspector's "JSON as it will be written" fold under a roster row, a wave or an event (inspector.js) are text boxes:
// Apply parses what is typed (a mistake is shown in place with its line and column, nothing changes), then the caller takes
// the object exactly as typed (every key, also the ones the form has no row for) as one undoable edit; Cancel / Close leaves
// everything as it was. A peek of derived data (a job's spec, a driver's meta) stays read-only, labelled so.
const JsonEdit = (() => {
  const elx = (typeof U !== 'undefined' && U.el) ? U.el : null;

  /** Where JSON text first goes wrong, in plain words: null when it is fine, else {pos, msg} (a small JSON reader of its
   *  own: the browsers' own messages often name no place, "Unexpected token '}' ... is not valid JSON"). Pure. */
  function locate(src) {
    let i = 0;
    const n = src.length;
    const ws = () => { while (i < n && ' \t\n\r'.includes(src[i])) i++; };
    const fail = (m) => { throw { pos: Math.min(i, n), msg: m }; };
    const str = () => {
      i++;
      while (i < n) {
        const c = src[i];
        if (c === '"') { i++; return; }
        if (c === '\\') { i += 2; continue; }
        if (c < ' ') fail('a line break inside a text in "quotes" (a missing " at its end?)');
        i++;
      }
      fail('a text in "quotes" never ends (a missing ")');
    };
    const value = () => {
      ws();
      if (i >= n) fail('the JSON ends too soon (a missing value, ] or })');
      const c = src[i];
      if (c === '{' || c === '[') {
        const close = c === '{' ? '}' : ']';
        i++;
        ws();
        if (src[i] === close) { i++; return; }
        for (;;) {
          ws();
          if (c === '{') {
            if (src[i] !== '"') fail(src[i] === '}' ? 'a comma before } (JSON allows none after the last key)' : i >= n ? 'the JSON ends too soon (a missing })' : 'expected a key in "double quotes"');
            str();
            ws();
            if (src[i] !== ':') fail('expected : after the key');
            i++;
          } else if (src[i] === ']') fail('a comma before ] (JSON allows none after the last item)');
          value();
          ws();
          if (src[i] === ',') { i++; continue; }
          if (src[i] === close) { i++; return; }
          fail(i >= n ? `the JSON ends too soon (a missing ${close})` : `expected , or ${close} (a missing comma?)`);
        }
      }
      if (c === '"') { str(); return; }
      const m = /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/.exec(src.slice(i, i + 64));
      if (m && m[0].length) { i += m[0].length; return; }
      for (const w of ['true', 'false', 'null']) if (src.startsWith(w, i)) { i += w.length; return; }
      fail(c === '}' || c === ']' || c === ',' ? 'expected a value here (a number, "text", true, false, null, [ ] or { })' : c === "'" ? "texts and keys take \"double quotes\", not 'single' ones" : `unexpected ${JSON.stringify(c)}`);
    };
    try {
      value();
      ws();
      if (i < n) fail('more after the end of the JSON');
      return null;
    } catch (e) {
      if (e && e.pos != null) return e;
      throw e;
    }
  }

  /** JSON.parse with the place of a mistake: {ok: true, value} or {ok: false, error, line, col, pos} (line and column
   *  count from 1; locate() finds the place and says it in plain words). Pure. */
  function parse(text) {
    const src = String(text == null ? '' : text);
    try {
      return { ok: true, value: JSON.parse(src) };
    } catch (e) {
      if (!src.trim()) return { ok: false, error: 'the box is empty', line: 1, col: 1, pos: 0 };
      const at = locate(src) || { pos: null, msg: String(e && e.message ? e.message : e) };
      let line = null, col = null;
      if (at.pos != null) {
        const before = src.slice(0, at.pos);
        line = before.split('\n').length;
        col = at.pos - before.lastIndexOf('\n');
      }
      return { ok: false, error: at.msg, line, col, pos: at.pos };
    }
  }

  /** The words for a parse mistake: "Line 3, column 5: Expected ',' or '}' after property value". Pure. */
  function where(r) {
    if (!r || r.ok) return '';
    return `${r.line != null ? `Line ${r.line}, column ${r.col}: ` : ''}${r.error} (nothing was changed)`;
  }

  /** What the caller's object must be: a JSON object ({...}), else the words why not. Pure. */
  function mustBeObject(v) {
    if (v === null || typeof v !== 'object' || Array.isArray(v)) return 'it must be one JSON object: { ... }';
    return '';
  }

  /** `target`'s keys replaced by `value`'s, in place (the same object, so a selection or a reference to it holds). */
  function replaceInto(target, value) {
    for (const k of Object.keys(target)) delete target[k];
    Object.assign(target, JSON.parse(JSON.stringify(value)));
    return target;
  }

  function markError(ta, msgEl, r) {
    msgEl.textContent = where(r);
    msgEl.hidden = false;
    if (r && r.pos != null && ta.setSelectionRange) {
      ta.focus();
      const p = Math.min(r.pos, ta.value.length);
      ta.setSelectionRange(p, Math.min(p + 1, ta.value.length));
      // the mistake's line in view
      const lh = parseFloat(getComputedStyle(ta).lineHeight) || 16;
      ta.scrollTop = Math.max(0, ((r.line || 1) - 4) * lh);
    }
  }

  /** The big window: {title, value (any JSON), note (a line under the title), readOnly, derived (read-only: derived data),
   *  onApply(value) -> '' when taken, or the words why not (shown in place, the window stays)}. Returns the window. */
  function modal(o) {
    const el = elx;
    const box = el('div', { class: 'amodal-back jedit-back' });
    const text = JSON.stringify(o.value, null, 2);
    const ro = !!(o.readOnly || o.derived || typeof o.onApply !== 'function');
    const ta = el('textarea', { class: 'jedit-text', spellcheck: false, 'data-path': 'json.edit', wrap: 'off' });
    ta.value = text;
    if (ro) ta.readOnly = true;
    const msg = el('div', { class: 'ferr bad jedit-msg', hidden: true });
    const state = el('span', { class: 'muted small jedit-state', text: ro ? (o.derived ? 'read-only (derived)' : 'read-only') : 'as the editor holds it' });
    const closeIt = () => { box.remove(); document.removeEventListener('keydown', onKey, true); };
    const apply = () => {
      const r = parse(ta.value);
      if (!r.ok) { markError(ta, msg, r); return; }
      const why = o.onApply(r.value);
      if (why) { msg.textContent = `${why} (nothing was changed)`; msg.hidden = false; return; }
      closeIt();
    };
    const dirty = () => ta.value !== text;
    ta.addEventListener('input', () => { msg.hidden = true; if (!ro) state.textContent = dirty() ? 'edited: Apply takes it, Cancel leaves the document as it was' : 'as the editor holds it'; });
    // Tab types two spaces (the box is for typing JSON); Ctrl+Enter applies; Escape cancels
    ta.addEventListener('keydown', (e) => {
      if (e.key === 'Tab' && !ro) {
        e.preventDefault();
        const a = ta.selectionStart, b = ta.selectionEnd;
        ta.value = ta.value.slice(0, a) + '  ' + ta.value.slice(b);
        ta.setSelectionRange(a + 2, a + 2);
        ta.dispatchEvent(new Event('input'));
      }
    });
    const onKey = (e) => {
      if (!document.body.contains(box)) return;
      if (e.key === 'Escape') { e.preventDefault(); e.stopImmediatePropagation(); if (!dirty() || confirm('Close without applying your edits?')) closeIt(); }
      else if (e.key === 'Enter' && (e.ctrlKey || e.metaKey) && !ro) { e.preventDefault(); e.stopImmediatePropagation(); apply(); }
      else if ((e.ctrlKey || e.metaKey) && String(e.key).toLowerCase() === 's') {
        // Ctrl+S: Apply what is typed, then the document's Save (o.onSave); a mistake stops both
        e.preventDefault(); e.stopImmediatePropagation();
        if (ro) return;
        if (dirty()) { const r = parse(ta.value); if (!r.ok) { markError(ta, msg, r); return; } const why = o.onApply(r.value); if (why) { msg.textContent = `${why} (nothing was changed)`; msg.hidden = false; return; } closeIt(); }
        else closeIt();
        if (typeof o.onSave === 'function') o.onSave();
      } else if ((e.ctrlKey || e.metaKey) && ['z', 'y'].includes(String(e.key).toLowerCase())) e.stopImmediatePropagation();
    };
    document.addEventListener('keydown', onKey, true);
    const acts = el('div', { class: 'amodal-actions' });
    if (!ro) {
      acts.appendChild(el('button', { class: 'btn primary', type: 'button', text: 'Apply', title: 'take the JSON as typed (Ctrl+Enter): the document is marked unsaved; Save writes it', onclick: apply }));
      acts.appendChild(el('button', { class: 'btn', type: 'button', text: 'Cancel', title: 'close: nothing changes (Escape)', onclick: () => { if (!dirty() || confirm('Close without applying your edits?')) closeIt(); } }));
      acts.appendChild(el('button', { class: 'btn ghost', type: 'button', text: 'Format', title: 'lay the JSON out again, two spaces a level (when it parses)', onclick: () => { const r = parse(ta.value); if (!r.ok) { markError(ta, msg, r); return; } ta.value = JSON.stringify(r.value, null, 2); ta.dispatchEvent(new Event('input')); } }));
    } else {
      acts.appendChild(el('button', { class: 'btn', type: 'button', text: 'Close', onclick: closeIt }));
    }
    acts.appendChild(state);
    box.appendChild(el('div', { class: 'amodal wide jedit' },
      el('h3', { text: o.title || 'JSON' }),
      o.note ? el('p', { class: 'muted small jedit-note', text: o.note }) : null,
      ta, msg, acts));
    box.addEventListener('click', (e) => { if (e.target === box && (!dirty() || confirm('Close without applying your edits?'))) closeIt(); });
    document.body.appendChild(box);
    requestAnimationFrame(() => { if (!ro) ta.focus(); });
    return box;
  }

  /** The inline fold (the inspector's "JSON as it will be written"): {summary, value, onApply(value) -> '' | words,
   *  derived (read-only, labelled "read-only (derived)")}. Appended to `container`. */
  function inline(container, o) {
    const el = elx;
    const text = JSON.stringify(o.value, null, 2);
    const ro = !!(o.derived || typeof o.onApply !== 'function');
    const det = el('details', { class: 'json-peek jedit-inline' + (ro ? ' ro' : '') },
      el('summary', { text: `${o.summary || 'JSON as it will be written'}${ro ? ' · read-only (derived)' : ' · edit it here'}` }));
    if (o.open) det.open = true;
    if (ro) { det.appendChild(el('pre', { text })); container.appendChild(det); return det; }
    const ta = el('textarea', { class: 'jedit-text inline', spellcheck: false, 'data-path': o.path || 'json.inline', wrap: 'off' });
    ta.value = text;
    ta.rows = Math.min(Math.max(text.split('\n').length + 1, 6), 40);
    const msg = el('div', { class: 'ferr bad jedit-msg', hidden: true });
    const applyBtn = el('button', { class: 'btn small primary', type: 'button', text: 'Apply', disabled: true, title: 'replace it with the JSON as typed (one undoable edit; Save writes the map)' });
    const resetBtn = el('button', { class: 'btn small', type: 'button', text: 'Reset', disabled: true, title: 'back to what it is now (nothing changes)' });
    const sync = () => { const d = ta.value !== text; applyBtn.disabled = !d; resetBtn.disabled = !d; det.classList.toggle('edited', d); };
    ta.addEventListener('input', () => { msg.hidden = true; sync(); });
    ta.addEventListener('keydown', (e) => {
      const ctrl = e.ctrlKey || e.metaKey;
      if (ctrl && e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); applyBtn.click(); return; }
      // Ctrl+S: what is typed is applied first, then the page's Save goes on (a mistake stops it)
      if (ctrl && String(e.key).toLowerCase() === 's' && !applyBtn.disabled) {
        const r = parse(ta.value);
        if (!r.ok) { e.preventDefault(); e.stopPropagation(); markError(ta, msg, r); return; }
        applyBtn.click();
        return;
      }
      // typing here never reaches the page's keys (Delete, the arrows)
      if (!ctrl) e.stopPropagation();
    });
    applyBtn.addEventListener('click', () => {
      const r = parse(ta.value);
      if (!r.ok) { markError(ta, msg, r); return; }
      const why = o.onApply(r.value);
      if (why) { msg.textContent = `${why} (nothing was changed)`; msg.hidden = false; }
    });
    resetBtn.addEventListener('click', () => { ta.value = text; msg.hidden = true; sync(); });
    det.appendChild(ta);
    det.appendChild(msg);
    det.appendChild(el('div', { class: 'alt-actions' }, applyBtn, resetBtn, el('span', { class: 'muted small', text: 'Ctrl+Enter applies; every key is kept, also ones without a box above' })));
    container.appendChild(det);
    return det;
  }

  return { parse, locate, where, mustBeObject, replaceInto, modal, inline };
})();
if (typeof module !== 'undefined') module.exports = JsonEdit;
