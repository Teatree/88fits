// 88fits_open: open a saved workflow from the page's URL.
//
//   http://<server>:8188/?open=workflows%2F88fits%2Fgoblin_GOB-E%2F01_goblin_e_front.json
//
// The Level Editor saves every workflow an art job ran into the server's user data (the Workflows sidebar's
// 88fits folder) and links it on the job card as "open in ComfyUI"; this extension reads `?open=<userdata path>`,
// fetches the file through the userdata API and loads it as a workflow tab named after the file. The stock
// frontend knows only `?template=` and `?share=` links (frontend 1.48, checked 2026-10-11).
//
// Timing: the page restores its previous tabs right after the extensions' `setup` hooks run, so the load waits a
// moment, marks the graph (graph.extra["88fits_open"]) and loads once more if the restore replaced it. The `open`
// parameter is dropped from the address afterwards, so a refresh keeps whatever is open then.
import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

const PARAM = "open";
const PREFIX = "workflows/";
const MARK = "88fits_open";

function wanted() {
  const params = new URLSearchParams(window.location.search);
  const path = params.get(PARAM);
  if (!path || !path.startsWith(PREFIX) || path.includes("..") || !path.toLowerCase().endsWith(".json")) return null;
  return path;
}

function dropParam() {
  const params = new URLSearchParams(window.location.search);
  if (!params.has(PARAM)) return;
  params.delete(PARAM);
  const q = params.toString();
  history.replaceState(null, "", window.location.pathname + (q ? "?" + q : "") + window.location.hash);
}

async function load(path) {
  const r = await api.fetchApi("/userdata/" + encodeURIComponent(path));
  if (!r.ok) throw new Error("HTTP " + r.status + " for " + path);
  const data = await r.json();
  if (!data || typeof data !== "object" || !Array.isArray(data.nodes)) throw new Error(path + " is not a workflow file");
  data.extra = Object.assign({}, data.extra || {}, { [MARK]: path });
  const name = path.slice(PREFIX.length).replace(/\.json$/i, "");
  await app.loadGraphData(data, true, true, name);
}

function isOpen(path) {
  try { return !!(app.graph && app.graph.extra && app.graph.extra[MARK] === path); } catch (_) { return false; }
}

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

app.registerExtension({
  name: "88fits.OpenWorkflow",
  async setup() {
    const path = wanted();
    if (!path) return;
    // let the page finish restoring its previous tabs first
    await sleep(1500);
    try {
      await load(path);
    } catch (e) {
      console.warn("[88fits_open] could not open", path, e);
      return;
    }
    dropParam();
    // the tab restore may land after us: open again once
    for (let i = 0; i < 3; i++) {
      await sleep(1500);
      if (isOpen(path)) return;
      try { await load(path); } catch (e) { console.warn("[88fits_open] second open failed", e); return; }
    }
  },
});
