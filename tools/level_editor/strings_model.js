'use strict';
// Pass 137, lane LOCKIT: the Strings tab's page-free part: the text renderer (game/core/systems/Loc.gd's and
// strings_io.py's twin; fixtures/loc_cases.json pins the three) and a row's checks (strings_io.check_text's twin).
//   {name}            the value handed in
//   {name?one:many}   the first part when the value is exactly 1 ("1"), else the second; either part may hold {other}
//   {{  }}            a literal brace
// Run under Node with the fixture as its argument to check it: node strings_model.js fixtures/loc_cases.json
const StringsModel = (() => {
  const ID = /^[a-z0-9_]+$/;

  function closing(src, i) {
    let depth = 0;
    for (; i < src.length; i++) {
      if (src[i] === '{') depth++;
      else if (src[i] === '}') { depth--; if (depth === 0) return i; }
    }
    return -1;
  }

  function placeholder(inner, raw, probs) {
    const q = inner.indexOf('?');
    if (q < 0) {
      const name = inner.trim();
      if (probs && !ID.test(name || '-')) probs.push(`{${inner}} is not a variable name (letters, digits and _ only)`);
      return { v: name, raw };
    }
    const rest = inner.slice(q + 1);
    let depth = 0, split = -1;
    for (let j = 0; j < rest.length; j++) {
      const c = rest[j];
      if (c === '{') depth++;
      else if (c === '}') depth--;
      else if (c === ':' && depth === 0) { split = j; break; }
    }
    const name = inner.slice(0, q).trim();
    if (probs && !ID.test(name || '-')) probs.push(`{${inner.slice(0, q)}} is not a variable name (letters, digits and _ only)`);
    if (split < 0) {
      if (probs) probs.push(`{${inner}} needs a ':' between its two parts ({n?one:many})`);
      const part = parse(rest, probs);
      return { v: name, raw, one: part, many: part };
    }
    return { v: name, raw, one: parse(rest.slice(0, split), probs), many: parse(rest.slice(split + 1), probs) };
  }

  /** The segments of a text: strings and {v, raw, one?, many?}; `probs` (an array) collects what is broken. */
  function parse(src, probs) {
    const segs = [];
    let buf = '', i = 0;
    while (i < src.length) {
      const c = src[i];
      if (c === '{') {
        if (src[i + 1] === '{') { buf += '{'; i += 2; continue; }
        const close = closing(src, i);
        if (close < 0) { if (probs) probs.push('a { with no } (write {{ for a brace that shows)'); buf += src.slice(i); break; }
        if (buf) { segs.push(buf); buf = ''; }
        segs.push(placeholder(src.slice(i + 1, close), src.slice(i, close + 1), probs));
        i = close + 1;
        continue;
      }
      if (c === '}') {
        if (src[i + 1] === '}') { buf += '}'; i += 2; continue; }
        if (probs) probs.push('a } with no { (write }} for a brace that shows)');
      }
      buf += c; i++;
    }
    if (buf) segs.push(buf);
    return segs;
  }

  const isOne = (v) => (typeof v === 'number' ? v === 1 : String(v).trim() === '1');

  function emit(segs, vals) {
    let out = '';
    for (const s of segs) {
      if (typeof s === 'string') out += s;
      else if (!Object.prototype.hasOwnProperty.call(vals, s.v)) out += s.raw;
      else if (s.one) out += emit(isOne(vals[s.v]) ? s.one : s.many, vals);
      else out += String(vals[s.v]);
    }
    return out;
  }

  const render = (text, vals) => emit(parse(String(text)), vals || {});

  function variables(text) {
    const out = [];
    const walk = (segs) => { for (const s of segs) if (typeof s !== 'string') { if (!out.includes(s.v)) out.push(s.v); if (s.one) { walk(s.one); walk(s.many); } } };
    walk(parse(String(text)));
    return out;
  }

  function problems(text) { const p = []; parse(String(text), p); return [...new Set(p)]; }

  // Excel's mangled characters (UTF-8 read as Windows-1252), or a lost byte
  const MOJIBAKE = /(â€|Ã.|Â[^A-Za-z]|�)/;

  /** {errors, warnings} for `text` as the new text of `row` ({text, vars}). */
  function check(row, text) {
    const errors = [], warnings = [];
    if (String(text).trim() === '') errors.push('the text is empty');
    const probs = problems(text);
    errors.push(...probs);
    if (MOJIBAKE.test(text) && !MOJIBAKE.test(row.text || '')) errors.push(`mangled characters (${text.match(MOJIBAKE)[0]}): the text lost its UTF-8`);
    const known = new Set(row.vars || []);
    const used = probs.length ? [] : variables(text);
    const unknown = used.filter((v) => !known.has(v)).sort();
    if (unknown.length) errors.push(`unknown variable${unknown.length > 1 ? 's' : ''} ${unknown.map((u) => `{${u}}`).join(', ')} (this text has: ${[...known].sort().map((k) => `{${k}}`).join(', ') || 'none'})`);
    if (!errors.length) {
      const dropped = variables(row.text || '').filter((v) => !used.includes(v)).sort();
      if (dropped.length) warnings.push(`no longer shows ${dropped.map((d) => `{${d}}`).join(', ')}`);
    }
    return { errors, warnings };
  }

  return { parse, render, variables, problems, check };
})();

if (typeof module !== 'undefined') {
  module.exports = StringsModel;
  if (require.main === module && process.argv[2]) {
    const fx = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
    let bad = 0;
    for (const c of fx.cases) { const got = StringsModel.render(c.t, c.v); if (got !== c.out) { bad++; console.log(`FAIL render ${JSON.stringify(c.t)}: ${JSON.stringify(got)} != ${JSON.stringify(c.out)}`); } }
    for (const c of fx.variables) { const got = JSON.stringify(StringsModel.variables(c.t)); if (got !== JSON.stringify(c.names)) { bad++; console.log(`FAIL variables ${c.t}: ${got}`); } }
    for (const t of fx.broken) if (!StringsModel.problems(t).length) { bad++; console.log(`FAIL broken not caught: ${t}`); }
    console.log(bad ? `${bad} failure(s)` : `strings_model: ${fx.cases.length + fx.variables.length + fx.broken.length} checks ok`);
    process.exit(bad ? 1 : 0);
  }
}
