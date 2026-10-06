"""ComfyUI client and workflow builders for the 88fits art pipeline (design bible section 15).

Everything runs on the AI server's ComfyUI (Flux.2 on a 32 GB R9700). Three workflows, all built here as
plain node graphs so they can be queued through the API *and* exported as JSON files that open in the
ComfyUI browser UI (tools/comfy_workflows/*.json, written by `python tools/comfy.py --export`):

  klein(...)      Flux.2 Klein 9B distilled: text (+ up to 4 reference images) -> image. 4 steps, cfg 1, euler,
                  Flux2Scheduler. References go through ImageScaleToTotalPixels -> VAEEncode -> ReferenceLatent on
                  both the positive and the zeroed negative, exactly like the official Klein edit template.
  flux2_dev(...)  Flux.2 dev (32B fp8) with the Turbo LoRA: FluxGuidance 4, BasicGuider, 8 steps. Slower, richer;
                  used when Klein is not enough (style anchor candidates).
  animate.wan_i2v Wan 2.2 14B image-to-video (tools/animate.py): a still becomes a run cycle; exported as 05_run_cycle_wan22.json.

Graph nodes are added with Graph.add(class_type, **inputs); an input value that is a (node_id, slot) tuple is a link.
"""
import io, json, os, sys, time, urllib.parse, urllib.request, uuid

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVER = os.environ.get("COMFY_SERVER", "http://192.168.137.54:8188")
for _a in sys.argv:
    if _a.startswith("--server="):
        SERVER = _a.split("=", 1)[1]

KLEIN_UNET = "flux-2-klein-9b-fp8.safetensors"
KLEIN_CLIP = "qwen_3_8b_fp8mixed.safetensors"
FLUX2_UNET = "flux2_dev_fp8mixed.safetensors"
FLUX2_CLIP = "mistral_3_small_flux2_fp8.safetensors"
FLUX2_TURBO_LORA = "Flux2TurboComfyv2.safetensors"
VAE = "flux2-vae.safetensors"

_OBJECT_INFO = None


# ---------------------------------------------------------------- http

def get(path, timeout=120):
    return json.load(urllib.request.urlopen(SERVER + path, timeout=timeout))


def post(path, obj, timeout=120):
    req = urllib.request.Request(SERVER + path, data=json.dumps(obj).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def object_info():
    """Node schemas, cached on disk (tools/dl/object_info.json) so UI export works offline."""
    global _OBJECT_INFO
    if _OBJECT_INFO is None:
        cache = os.path.join(REPO, "tools", "dl", "object_info.json")
        try:
            _OBJECT_INFO = get("/object_info", timeout=180)
            os.makedirs(os.path.dirname(cache), exist_ok=True)
            json.dump(_OBJECT_INFO, open(cache, "w", encoding="utf-8"))
        except Exception:
            _OBJECT_INFO = json.load(open(cache, encoding="utf-8"))
    return _OBJECT_INFO


def upload(png_bytes, name, subfolder="88fits"):
    """Upload an image into ComfyUI's input folder; returns the value LoadImage expects."""
    boundary = "----88fits" + uuid.uuid4().hex
    parts = []
    parts.append(b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"image\"; filename=\"" + name.encode() +
                 b"\"\r\nContent-Type: image/png\r\n\r\n" + png_bytes + b"\r\n")
    for k, v in (("subfolder", subfolder), ("overwrite", "true")):
        if k == "subfolder" and not v:
            continue
        parts.append(b"--" + boundary.encode() + b"\r\nContent-Disposition: form-data; name=\"" + k.encode() + b"\"\r\n\r\n" + v.encode() + b"\r\n")
    body = b"".join(parts) + b"--" + boundary.encode() + b"--\r\n"
    req = urllib.request.Request(SERVER + "/upload/image", data=body, headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    r = json.load(urllib.request.urlopen(req, timeout=120))
    return (r.get("subfolder", "") + "/" if r.get("subfolder") else "") + r["name"]


def upload_pil(img, name, subfolder="88fits"):
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return upload(buf.getvalue(), name, subfolder)


SERVER_SSH = ["ssh", "-i", os.path.expanduser("~/.ssh/id_ed25519_ai_server"), "-o", "ConnectTimeout=10", "teatree@192.168.137.54"]


def server_ram_used_gb():
    """RAM in use on the server (GB), or -1 when ssh fails."""
    import subprocess
    try:
        out = subprocess.run(SERVER_SSH + ["free -g | sed -n 2p"], capture_output=True, text=True, timeout=30).stdout.split()
        return int(out[2])
    except Exception:
        return -1


def release_models():
    """Flux.2 dev (35 GB) and its text encoder (18 GB) do not both fit the server's 47 GB of RAM twice over: after a
    render, ask ComfyUI to unload, and if the RAM does not come back restart the service (about 20 s)."""
    import subprocess
    try:
        post("/free", {"unload_models": True, "free_memory": True})
    except Exception:
        pass
    time.sleep(6)
    if server_ram_used_gb() > 20:
        return restart_server()
    return "freed"


def restart_server():
    """Restart the ComfyUI service and wait until it answers (about 20 s). Uploaded references live in its input folder
    and survive the restart."""
    import subprocess
    subprocess.run(SERVER_SSH + ["systemctl --user restart ai-comfyui.service"], capture_output=True, timeout=60)
    for _ in range(40):
        time.sleep(3)
        try:
            get("/system_stats")
            return "restarted"
        except Exception:
            continue
    raise RuntimeError("ComfyUI did not come back after the restart")


def run_dev(graph, timeout=1500, tries=2):
    """A Flux.2 dev render on a freshly started server (pass 46: the third dev render in one process sat for half an hour
    loading the models into a full RAM, then timed out and blocked the queue behind it), retried once after a restart
    when it times out."""
    for attempt in range(tries):
        restart_server()
        try:
            return run(graph, timeout=timeout)
        except RuntimeError as e:
            if "timeout" not in str(e) or attempt == tries - 1:
                raise
            try:
                post("/queue", {"clear": True})
                post("/interrupt", {})
            except Exception:
                pass


def run(graph, timeout=1200):
    """Queue a graph and wait for its SaveImage outputs. Returns (list of png bytes, seconds)."""
    r = post("/prompt", {"prompt": graph.api(), "client_id": "88fits-" + uuid.uuid4().hex[:8]})
    if r.get("error") or r.get("node_errors"):
        raise RuntimeError("ComfyUI rejected the graph: " + json.dumps({"error": r.get("error"), "node_errors": r.get("node_errors")})[:1500])
    pid = r["prompt_id"]
    t0 = time.time()
    while True:
        time.sleep(1.0)
        h = get("/history/" + pid)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                raise RuntimeError("ComfyUI error: " + json.dumps(st.get("messages"))[:1500])
            out = []
            for o in h[pid].get("outputs", {}).values():
                for im in o.get("images", []):
                    if im.get("type") != "output":
                        continue
                    url = SERVER + "/view?filename=%s&subfolder=%s&type=%s" % (urllib.parse.quote(im["filename"]), urllib.parse.quote(im["subfolder"]), im["type"])
                    out.append(urllib.request.urlopen(url, timeout=120).read())
            if not out:
                raise RuntimeError("ComfyUI produced no image")
            return out, time.time() - t0
        if time.time() - t0 > timeout:
            raise RuntimeError("ComfyUI timeout after %ds" % timeout)


# ---------------------------------------------------------------- graph

class Graph:
    def __init__(self):
        self.nodes = {}
        self.order = []
        self.titles = {}
        self._n = 0

    def add(self, class_type, _title=None, **inputs):
        self._n += 1
        nid = str(self._n)
        conv = {}
        for k, v in inputs.items():
            conv[k] = [str(v[0]), int(v[1])] if isinstance(v, tuple) else v
        self.nodes[nid] = {"class_type": class_type, "inputs": conv}
        self.order.append(nid)
        if _title:
            self.titles[nid] = _title
        return nid

    def api(self):
        return self.nodes

    # -- UI export ------------------------------------------------------------------
    def ui_workflow(self):
        """Convert to the LiteGraph JSON the ComfyUI frontend loads (File > Open / drag and drop)."""
        info = object_info()
        depth = {}

        def d_of(nid):
            if nid in depth:
                return depth[nid]
            best = 0
            for v in self.nodes[nid]["inputs"].values():
                if isinstance(v, list) and len(v) == 2 and str(v[0]) in self.nodes:
                    best = max(best, d_of(str(v[0])) + 1)
            depth[nid] = best
            return best

        for nid in self.order:
            d_of(nid)
        col_count = {}
        nodes_out, links_out = [], []
        link_id = 0
        pending_links = {}   # (target_nid, input_name) -> link id
        outputs_links = {}   # nid -> {slot: [link ids]}
        for nid in self.order:
            for name, v in self.nodes[nid]["inputs"].items():
                if isinstance(v, list) and len(v) == 2 and str(v[0]) in self.nodes:
                    link_id += 1
                    pending_links[(nid, name)] = link_id
                    outputs_links.setdefault(str(v[0]), {}).setdefault(int(v[1]), []).append(link_id)
        for nid in self.order:
            n = self.nodes[nid]
            spec = info.get(n["class_type"], {})
            spec_in = spec.get("input", {})
            ordered = list(spec_in.get("required", {}).items()) + list(spec_in.get("optional", {}).items())
            inputs, widgets = [], []
            for name, s in ordered:
                typ = s[0]
                opts = s[1] if len(s) > 1 and isinstance(s[1], dict) else {}
                is_widget = isinstance(typ, list) or typ in ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO")
                val = n["inputs"].get(name)
                linked = (nid, name) in pending_links
                if linked:
                    inputs.append({"name": name, "type": typ if isinstance(typ, str) else "COMBO", "link": pending_links[(nid, name)]})
                    if is_widget:
                        widgets.append(val if val is not None else opts.get("default"))
                elif is_widget:
                    if val is None:
                        if isinstance(typ, list):
                            val = typ[0] if typ else ""
                        elif typ == "COMBO":
                            val = (opts.get("options") or [""])[0] if not opts.get("default") else opts.get("default")
                        else:
                            val = opts.get("default")
                    widgets.append(val)
                    if name in ("seed", "noise_seed") or opts.get("control_after_generate"):
                        widgets.append("fixed")
                else:
                    inputs.append({"name": name, "type": typ if isinstance(typ, str) else "COMBO", "link": None})
            if n["class_type"] == "LoadImage":
                widgets = [n["inputs"].get("image", ""), "image"]
            outs = []
            for i, t in enumerate(spec.get("output", [])):
                outs.append({"name": (spec.get("output_name") or spec.get("output"))[i], "type": t, "links": outputs_links.get(nid, {}).get(i, []), "slot_index": i})
            d = depth[nid]
            row = col_count.get(d, 0)
            col_count[d] = row + 1
            node = {"id": int(nid), "type": n["class_type"], "pos": [60 + d * 400, 60 + row * 230],
                    "size": [360, 90 + 26 * len(widgets) + 20 * len(inputs)], "flags": {}, "order": self.order.index(nid), "mode": 0,
                    "inputs": inputs, "outputs": outs, "properties": {"Node name for S&R": n["class_type"]}, "widgets_values": widgets}
            if nid in self.titles:
                node["title"] = self.titles[nid]
            nodes_out.append(node)
        for (tnid, name), lid in pending_links.items():
            src = self.nodes[tnid]["inputs"][name]
            spec = info.get(self.nodes[str(src[0])]["class_type"], {})
            typ = (spec.get("output") or ["*"])[int(src[1])] if spec.get("output") else "*"
            tin = [i for i, x in enumerate([ni for ni in nodes_out if ni["id"] == int(tnid)][0]["inputs"]) if x["name"] == name][0]
            links_out.append([lid, int(src[0]), int(src[1]), int(tnid), tin, typ])
        return {"last_node_id": self._n, "last_link_id": link_id, "nodes": nodes_out, "links": links_out, "groups": [],
                "config": {}, "extra": {"88fits": "generated by tools/comfy.py"}, "version": 0.4}


# ---------------------------------------------------------------- workflows

def _refs(g, refs, vae, pos, neg=None, megapixels=1.0):
    for r in refs:
        li = g.add("LoadImage", "reference", image=r)
        sc = g.add("ImageScaleToTotalPixels", image=(li, 0), upscale_method="lanczos", megapixels=megapixels, resolution_steps=1)
        enc = g.add("VAEEncode", pixels=(sc, 0), vae=(vae, 0))
        pos = g.add("ReferenceLatent", conditioning=(pos, 0), latent=(enc, 0))
        if neg is not None:
            neg = g.add("ReferenceLatent", conditioning=(neg, 0), latent=(enc, 0))
    return pos, neg


def klein(prompt, seed, width=1024, height=1024, refs=(), steps=4, cfg=1.0, prefix="88fits/klein", negative=""):
    """Flux.2 Klein 9B distilled. refs: LoadImage names (see upload())."""
    g = Graph()
    m = g.add("UNETLoader", "Flux.2 Klein 9B", unet_name=KLEIN_UNET, weight_dtype="default")
    c = g.add("CLIPLoader", "Qwen3 8B text encoder", clip_name=KLEIN_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    if negative:
        neg = g.add("CLIPTextEncode", "negative", clip=(c, 0), text=negative)
    else:
        neg = g.add("ConditioningZeroOut", conditioning=(pos, 0))
    pos, neg = _refs(g, refs, v, pos, neg)
    guider = g.add("CFGGuider", model=(m, 0), positive=(pos, 0), negative=(neg, 0), cfg=cfg)
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=steps, width=width, height=height)
    lat = g.add("EmptyFlux2LatentImage", width=width, height=height, batch_size=1)
    noise = g.add("RandomNoise", noise_seed=seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=(sig, 0), latent_image=(lat, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


def flux2_dev(prompt, seed, width=1024, height=1024, refs=(), steps=8, guidance=4.0, turbo=True, prefix="88fits/flux2dev"):
    """Flux.2 dev with the Turbo LoRA (8 steps) or plain (20 steps)."""
    g = Graph()
    m = g.add("UNETLoader", "Flux.2 dev", unet_name=FLUX2_UNET, weight_dtype="default")
    if turbo:
        m = g.add("LoraLoaderModelOnly", "Turbo LoRA", model=(m, 0), lora_name=FLUX2_TURBO_LORA, strength_model=1.0)
    c = g.add("CLIPLoader", "Mistral text encoder", clip_name=FLUX2_CLIP, type="flux2", device="default")
    v = g.add("VAELoader", vae_name=VAE)
    pos = g.add("CLIPTextEncode", "prompt", clip=(c, 0), text=prompt)
    pos, _ = _refs(g, refs, v, pos, None)
    pos = g.add("FluxGuidance", conditioning=(pos, 0), guidance=guidance)
    guider = g.add("BasicGuider", model=(m, 0), conditioning=(pos, 0))
    sampler = g.add("KSamplerSelect", sampler_name="euler")
    sig = g.add("Flux2Scheduler", steps=steps if turbo else max(steps, 20), width=width, height=height)
    lat = g.add("EmptyFlux2LatentImage", width=width, height=height, batch_size=1)
    noise = g.add("RandomNoise", noise_seed=seed)
    out = g.add("SamplerCustomAdvanced", noise=(noise, 0), guider=(guider, 0), sampler=(sampler, 0), sigmas=(sig, 0), latent_image=(lat, 0))
    dec = g.add("VAEDecode", samples=(out, 0), vae=(v, 0))
    g.add("SaveImage", images=(dec, 0), filename_prefix=prefix)
    return g


def export_workflows(out_dir):
    """Write the three pipeline workflows as ComfyUI UI files, with the real prompts used by tools/gen_art.py."""
    os.makedirs(out_dir, exist_ok=True)
    try:
        import gen_art
        style, bg = gen_art.STYLE, gen_art.BG_GREEN
        anchor_prompt = gen_art.anchor_prompt()
        ex = "a tan coyote creature with sandy fur, tall pointed ears and a mischievous grin with its tongue out"
    except Exception:
        style, bg, anchor_prompt = "Clash Royale style", "flat green background", "style sheet"
        ex = "a goofy coyote"
    # the UI's LoadImage combo only lists top-level input files, so the exported graphs reference top-level copies
    for src, name in ((os.path.join(REPO, "game", "art", "style", "style_anchor.png"), "style_anchor.png"),
                      (os.path.join(REPO, "tools", "dl", "ai_raw2", "drifter_front.png"), "drifter_front.png")):
        if os.path.exists(src):
            try:
                upload(open(src, "rb").read(), name, "")
            except Exception as e:
                print("  (could not upload %s to the server: %s)" % (name, e))
    wf = {
        "01_style_anchor_klein.json": klein(anchor_prompt, 1234, 1536, 768, prefix="88fits/anchor"),
        "02_item_from_anchor_klein.json": klein("Using exactly the same art style as the reference image, draw " + ex + ". Full body, front view, " + style + ". " + bg,
                                                42, 1024, 1024, refs=["style_anchor.png"], prefix="88fits/item"),
        "03_character_back_view_klein.json": klein("Turn this exact character around to show a full back view seen directly from behind. Same outfit, colors and proportions, standing straight. " + bg,
                                                   42, 1024, 1024, refs=["drifter_front.png"], prefix="88fits/back"),
        "04_style_anchor_flux2_dev.json": flux2_dev(anchor_prompt, 1234, 1536, 768, prefix="88fits/anchor_dev"),
    }
    try:
        import animate
        wf["05_run_cycle_wan22.json"] = animate.wan_i2v("A 2D anime game character sprite, running in place at a steady jog, seen in strict side profile facing right. "
                                                        "The character stays exactly in the centre of the frame like on a treadmill, a seamless looping run cycle, "
                                                        "camera locked off, flat solid blue background, no ground, no shadow.", "drifter_side_still.png", 1)
    except Exception as e:
        print("  (no Wan workflow exported: %s)" % e)
    for name, g in wf.items():
        json.dump(g.ui_workflow(), open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="\n"), indent=1)
        print("wrote", os.path.join(out_dir, name))


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if "--export" in sys.argv:
        export_workflows(os.path.join(REPO, "tools", "comfy_workflows"))
    else:
        s = get("/system_stats")
        print("ComfyUI", s["system"].get("comfyui_version"), "on", s["devices"][0].get("name"), "at", SERVER)
        print("diffusion models:", get("/models/diffusion_models"))
