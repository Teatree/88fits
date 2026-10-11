// 88fits_open: open a saved workflow from the page's URL.
//
//   http://<server>:8188/?open=workflows%2F88fits%2Fgoblin_GOB-E%2Fj2026...%2F01_goblin_e_front.json
//
// The Level Editor saves every workflow an art job ran into the server's user data (the Workflows sidebar's
// 88fits folder) and links it on the job card as "open in ComfyUI"; this extension reads `?open=<userdata path>`
// and opens that file as a workflow tab. The stock frontend knows only `?template=` and `?share=` links
// (frontend 1.48, checked 2026-10-11).
//
// Timing: the extensions' `setup` hooks are awaited inside app.setup(), BEFORE the canvas store exists and before
// the page restores its previous tabs (GraphCanvas: setup -> initializeWorkflow -> restoreWorkflowTabsState), so
// the hook returns at once and the work runs on its own: wait until the page has an active workflow (its own
// init is done), then open ours. The saved file is opened through the workflow store when the store knows it
// (a real tab, with the file's name); else a copy is loaded as a temporary tab named after the file. The saved
// graphs carry no view (no extra.ds), so the view is fitted to the graph afterwards: a canvas panned far away in a
// long-lived browser would otherwise show an empty page. A toast says what happened. The `open` parameter is
// dropped from the address afterwards, so a refresh keeps whatever is open then.
import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

const PARAM = "open";
const PREFIX = "workflows/";
const TAG = "[88fits_open]";
const VERSION = 3;

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

const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
const nameOf = (path) => path.slice(PREFIX.length).replace(/\.json$/i, "").split("/").pop();

function workflowStore() {
  try { return app.extensionManager && app.extensionManager.workflow ? app.extensionManager.workflow : null; } catch (_) { return null; }
}

function toast(severity, summary, detail, life) {
  try {
    const t = app.extensionManager && app.extensionManager.toast;
    if (t && typeof t.add === "function") t.add({ severity, summary, detail, life: life || 6000 });
  } catch (_) { /* no toast store: the console has it */ }
}

/** The page's own start-up is done once it has a canvas and an active workflow (its restore or its default). */
async function pageReady(maxMs) {
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    const ws = workflowStore();
    // app.graph is not read here: before the canvas exists its getter logs "graph accessed before initialization"
    if (app.canvas && ws && ws.activeWorkflow) return true;
    await sleep(250);
  }
  return false;
}

async function fetchWorkflow(path) {
  const r = await api.fetchApi("/userdata/" + encodeURIComponent(path));
  if (!r.ok) throw new Error("HTTP " + r.status + " for " + path);
  const data = await r.json();
  if (!data || typeof data !== "object" || !Array.isArray(data.nodes)) throw new Error(path + " is not a workflow file");
  return data;
}

/** Through the store: the saved file becomes a real tab (its own name, Save writes it back). False when the store
 *  does not know the file (saved after the page loaded) or the API differs. */
async function openSaved(path) {
  const ws = workflowStore();
  if (!ws || typeof ws.getWorkflowByPath !== "function") return false;
  let wf = ws.getWorkflowByPath(path);
  if (!wf && typeof ws.syncWorkflows === "function") {
    try { await ws.syncWorkflows(); } catch (_) { /* the fallback below */ }
    wf = ws.getWorkflowByPath(path);
  }
  if (!wf) return false;
  if (!wf.isLoaded && typeof wf.load === "function") await wf.load();
  const data = wf.activeState || wf.initialState || (wf.originalContent ? JSON.parse(wf.originalContent) : null);
  if (!data || !Array.isArray(data.nodes)) return false;
  await app.loadGraphData(data, true, true, wf);
  return true;
}

/** A copy, as a temporary tab named after the file (no "/" in the name: the store would read it as a folder). */
async function openCopy(path) {
  const data = await fetchWorkflow(path);
  await app.loadGraphData(data, true, true, nameOf(path));
}

/** The whole graph in view: the saved graphs carry no view of their own. */
async function fitView() {
  await sleep(150);
  try {
    const cmd = app.extensionManager && app.extensionManager.command;
    if (cmd && typeof cmd.execute === "function") { await cmd.execute("Comfy.Canvas.FitView"); return; }
  } catch (e) { console.warn(TAG, "FitView command failed", e); }
  try {
    if (app.canvas && typeof app.canvas.fitView === "function") app.canvas.fitView();
    else if (app.canvas && app.canvas.ds && typeof app.canvas.ds.fitToBounds === "function" && app.graph) app.canvas.ds.fitToBounds(app.graph.boundingRect || app.graph.getBoundingRect?.());
  } catch (e) { console.warn(TAG, "fit view failed", e); }
}

/** Our tab is the active one; when the page's late restore took it over, bring it back once. */
async function keepActive(path) {
  for (let i = 0; i < 8; i++) {
    await sleep(1000);
    const ws = workflowStore();
    if (!ws || !ws.activeWorkflow) return;
    if (ws.activeWorkflow.path === path) return;
    const wf = typeof ws.getWorkflowByPath === "function" ? ws.getWorkflowByPath(path) : null;
    if (wf && typeof ws.openWorkflow === "function") {
      try { await ws.openWorkflow(wf); await fitView(); } catch (e) { console.warn(TAG, "could not bring the tab back", e); }
      return;
    }
  }
}

async function run(path) {
  const name = nameOf(path);
  if (!(await pageReady(20000))) console.warn(TAG, "the page took long to start; opening anyway");
  await sleep(300);
  try {
    let done = false;
    try { done = await openSaved(path); } catch (e) { console.warn(TAG, "store open failed, loading a copy", e); }
    if (!done) await openCopy(path);
    dropParam();
    await fitView();
    console.info(TAG, "opened", path);
    toast("success", "88fits: opened " + name, done ? "the exact prompt, seed, passes, models and references of that render are in the nodes (a tab of its own, from the Workflows sidebar)" : "a copy of that render's graph: its prompt, seed, passes, models and references are in the nodes", 8000);
    await keepActive(path);
  } catch (e) {
    console.warn(TAG, "could not open", path, e);
    toast("error", "88fits: could not open " + name, String(e && e.message ? e.message : e), 12000);
  }
}

app.registerExtension({
  name: "88fits.OpenWorkflow",
  setup() {
    const path = wanted();
    if (!path) return;
    console.info(TAG, "v" + VERSION, "will open", path);
    void run(path);   // never block app.setup(): the page's own init runs after the hooks
  },
});
