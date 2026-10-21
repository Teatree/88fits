# 88FITS Tooling Modernization — Critical Architecture Assessment (DO NOT IMPLEMENT YET)

> **Role:** You are Claude Code, the engineer with access to the current 88FITS game repository, local tooling, ComfyUI environment, project conventions, and development history. Act as a critical principal engineer, UX architect, technical artist, and production-pipeline designer. **Your task now is to assess a proposed roadmap, not execute it.**
>
> **Deliverable:** A thorough, evidence-backed, item-by-item decision report with a master assessment table. Every independently actionable proposal below must receive exactly one of three statuses: `accepted`, `rejected`, or `questions`.
>
> **Absolute stop condition:** Do **not** implement any feature, refactor code, download model weights, install dependencies, migrate data, modify ComfyUI workflows, edit production assets, or alter configuration during this assessment. Read-only inspection, safe commands, and non-mutating feasibility checks are permitted. Wait for my approval of the assessed plan before modifying the project.

## A. What I'm trying to accomplish

I develop a Western-themed roguelike with a custom art pipeline, locally generated game assets, Hero and Enemy animation, multiple *Looks* per character, and tools to supervise production. My current dashboard is useful but feels more like a set of background scripts with a web front end than a **modern, live, interactive production application**.

I want a **real-time, artifact-centric, human-in-the-loop AI production studio**:

- The browser **never needs a manual refresh** to see newly generated frames, candidates, status changes, Gemini evaluations, changed decisions, or errors. No blanking/rebuilding of active UI while background work proceeds.
- ComfyUI runs on an AI server on my LAN. The dashboard can queue work, observe progress, receive outputs, and request changes and repairs without losing state.
- A cheap multimodal vision evaluator (ideally Gemini, but provider-agnostic) performs the **visual review, comparison, and targeted correction decisions** normally consuming Claude Code's tokens. Deterministic/local checks should remain useful.
- Claude Code (working on the *game itself*) can submit a high-level art request and receive a **job ID and a compact final result**, without consuming tokens inspecting every candidate/frame or orchestrating every iteration.
- Each image/frame has transparent provenance: source, generation settings, evaluation findings, replacement candidates, revisions, approval, and the final installed version.
- I can intervene anytime: pause, approve, reject, edit AI-proposed prompt changes, replace individual frames, review decisions, override choices, and commit multiple changes together.
- **Animation quality and identity consistency** matter especially: occasional frames are malformed, unstable, poorly animated, or visually inconsistent across angles/views. A VACE-based repair path must be assessed for *all* Hero/Enemy animation methods, **including already-existing assets**.

Do not conflate “more animation in the interface” with better UX: prioritize instant meaningful feedback, stable layout, correct state, clear affordances, keyboard/mouse efficiency, and robust recovery.

## B. First establish what actually exists

Before assigning statuses, inspect the **current repository**. Treat the following names as starting points only; code may have evolved since this brief was prepared:

- `tools/level_editor/`: especially `jobs.js`, `jobs.py`, `server.py`, `index.html`, `app.js`, `style.css`, `looks.js`, `strip_player.js`, `methods.json`, and existing tests.
- Generation and animation: `tools/gen_art.py`, `tools/animate.py`, `tools/comfy.py`, `tools/asset_job.py`, related scripts, ComfyUI workflow JSON, and any newly added VACE instructions/workflows/scripts.
- Hero/Enemy data models, Look/version storage, sprite strips and animations, caches, background workers, import/export paths, locks, and current visual QA integrations.
- Existing available Python/frontend frameworks, process boundaries, network/security assumptions, QA tests, and game-engine-specific sprite metadata.
- Existing automation entry points used by Claude Code (CLI, HTTP API, scripts, hooks/MCP, etc.).

**Previous review hypotheses to verify, not assume:** the Jobs UI used `/api/jobs?since=...` polling at roughly 2/6-second intervals; cards were sometimes reconstructed; ComfyUI completion used `/history/{prompt_id}` polling; local LM Studio vision QA checked basic errors; job queues, caching, candidate selection, clip rerolls, Looks, and ComfyUI resource locks already existed. If a claim is now false, correct it explicitly and explain why the proposed change should be dropped or modified.

**Inventory every animation-producing Hero and Enemy method.** The previous `methods.json` snapshot included `hero_pose5`, `hero_fit`, `hero_puppet`, `creature_free2`, `creature_pose2`, `creature_free8`, `creature_ctl`, `creature_proc`, `creature_pictures`; also examine animation derived from `recolour`, copied/reused Looks, changed rigs/drivers, imported or preexisting strips, death/hit/idle/run sequences, and any newer methods. Do not assume only video-generated animations qualify. Determine the actual method inventory from the live repository.

For each relevant method, trace:

`input/reference → stills → clip or procedural frames → trims/selection/cropping/scaling → sprite strip / animation metadata → asset installation → runtime use`.

Identify **where a frame-level repair can be inserted without undoing it** during a subsequent repack, requeue, import, regeneration, or automatic export. This is essential.

## C. Decision rules — critical, not deferential

Assess **every numbered proposal independently**. You are allowed, and expected, to reject ideas that are unnecessary, already adequately implemented, poorly scoped, architecturally harmful, fragile, overengineered, or lower-value than a simpler alternative.

For each proposal:

1. **What is good about it?** Identify concrete expected improvements.
2. **What is bad about it?** Identify cost, UX complexity, failure modes, operational burden, coupling, migration risks, or needless technology.
3. **What exists today?** Cite relevant paths, symbols, endpoints, schemas, and tests; identify what can be reused.
4. **What is your decision?** Exactly one status:
   - `accepted` — **will implement if I approve the plan**; choose an appropriate scoped implementation, dependencies, test and completion criteria. **Do not implement now.**
   - `rejected` — not worth doing **as proposed**; explain precisely why, and propose a better alternative if one exists. “Already implemented and sufficient” can be a valid rejection, with evidence.
   - `questions` — **material ambiguity** about the required behavior, scope, feasibility, UX contract, or value prevents a responsible decision. State **specific questions for me**, possible options, your provisional recommendation if useful, and what answer would unblock it.
5. Do not use `questions` merely because there are minor engineering details to decide; make reasonable implementation choices yourself. Conversely, do not silently invent product behavior where materially different outcomes are plausible.
6. Separate hard requirements from suggested implementation technologies. You may accept the objective while rejecting React, SSE, MCP, a database migration, or any specific mechanism; be explicit about that distinction.
7. Do not claim a Google subscription provides unlimited or permitted third-party automated Gemini invocations. Verify the access route, automation restrictions, actual image input support, quota behavior, and availability; treat uncertain consumer CLI integrations as experimental, not guaranteed.
8. Do not mark features `accepted` merely to please me. I expect a skeptical technical review with genuine tradeoffs.

## D. Improvement candidates — evaluate EACH ID separately

### D1 — Live UI and application architecture

**UI-01 — Push-driven job updates.** Replace or supplement browser polling with an event stream so generations, new frames, QA findings, approvals, prompts, and errors appear immediately. Compare **SSE vs WebSockets** based on actual bidirectional needs and existing server stack; ordinary HTTP for user commands is acceptable.

**UI-02 — Reliable reconnect and state reconstruction.** A reload, connection drop, tab switch, or reopening the dashboard must reconstruct the current job, frames, selections, history, and outstanding decisions. Consider event sequence IDs, snapshot + replay, missed-event recovery, duplicate-event handling, and offline/disconnected indication.

**UI-03 — Reactive component architecture.** Assess introducing **React + TypeScript + Vite** (and optionally Tailwind/shadcn/ui) for the Jobs/Art Studio area. Compare an incremental React island against a wholesale SPA rewrite and against improving the existing vanilla JS. Don't recommend React merely because it is fashionable.

**UI-04 — Stable interaction state.** Updating progress must not remount an entire card, collapse an expanded panel, reset scrolling, erase an edited field, drop a selected frame, or interrupt playback. Separate server state from local UI interaction state; use targeted updates and stable keys.

**UI-05 — Dedicated Art Studio workspace.** Provide a purposeful asset-centric production view distinct from generic Jobs diagnostics: current candidate, previous best, visual review, live pipeline stages, timeline/history, relevant controls, and access to per-frame animation tooling. Critique whether a new tab or integrated expansion is better.

**UI-06 — Rich but restrained live status.** Show queued/running/evaluating/revising/exporting/awaiting approval/completed/error states, meaningful substage progress, current ComfyUI operation, pending actions, resource contention, and visible errors. Use skeleton/optimistic updates where appropriate, but never imply a step succeeded before confirmation. Avoid flicker and excessive motion.

**UI-07 — Interactive candidate comparison.** Compare generated images side by side at synchronized zoom/pan; optionally blink, onion-skin, overlay, or slider-diff for related frames. Keep the incumbent best pinned, allow A/B choice, and record human overrides. Assess the actual value of each comparison interaction.

**UI-08 — Image-attached findings and annotations.** Show evaluator issues **next to or on the image**, with severity, affected frame/view, optional normalized region/bounding box, click-to-zoom, and confidence/uncertainty where available. Let me draw or select a region and add my own correction instructions. Treat localization as approximate unless validated.

**UI-09 — Visible prompt / parameter diffs.** Whenever AI proposes a change, show the original specification, proposed prompt changes, source prompt versus derived revision prompt, seed/mask/workflow differences, and an editable confirmation control. Preserve the immutable original art brief.

**UI-10 — Keyboard-efficient control surface.** Assess shortcuts/commands for preview, play/pause, previous/next frame, approve, reject, compare, annotate, queue repairs, and commit; support bulk selection and undo where safe. Decide whether a command palette, dockable panels, resizable split views, or multi-monitor-friendly layout would meaningfully help.

### D2 — Workflow engine, state, and reliability

**WF-01 — Parent production workflow above ordinary jobs.** Model an art request as an ongoing workflow with iterations, candidates, evaluations, repairs, approvals, and final artifacts. Reuse existing job queue and lanes rather than replacing working infrastructure merely for a new abstraction.

**WF-02 — Durable event and decision record.** Persist state transitions, creation of candidates/frames, AI critiques, attempted/successful edits, user overrides, selected winners, exports, errors, and timestamps. Evaluate whether existing JSON files suffice or whether SQLite/event tables are warranted.

**WF-03 — Bounded automatic iteration.** Add explicit max candidates, rerolls, repair rounds, timeouts, compute budgets, quota ceilings, stop-on-plateau, and graceful handoff to a human when no satisfactory result emerges. Never silently continue indefinitely.

**WF-04 — Preserve the best valid result.** Do not automatically replace the incumbent with a weaker later generation. Support pairwise comparison or a defensible score-plus-hard-gates scheme; avoid relying only on unstable raw LLM aesthetic scores. Record why a winner replaced the previous best.

**WF-05 — Controlled tool-command contract.** AI proposes narrowly scoped operations (accept, reject, compare, change seed/prompt, reroll clip, repair frames, request approval, stop). The orchestrator checks schema, permissions, constraints, resource availability, and target IDs before executing. No arbitrary shell execution, raw file rewriting, or unrestricted remote ComfyUI mutation by the visual evaluator.

**WF-06 — Async operations, idempotency, and conflict handling.** Job submission and editing should return quickly with stable IDs; retry must not duplicate work. Consider concurrent job controls, edit conflicts, cancellation and resumability, queue fairness, ComfyUI locks, atomic operations, and preventing one workflow's modifications from overwriting another's.

**WF-07 — ComfyUI native progress bridge.** Evaluate switching from completion polling to ComfyUI WebSocket progress events where valuable. Retain REST endpoints for job submission, history, and image download. Translate ComfyUI's low-level nodes/events into meaningful app stages; preserve existing locking/retries.

**WF-08 — Network and resource safety.** Assess LAN routing to the AI server, allowed hosts, endpoints, API auth and secrets, model downloads, path traversal, image upload validation, workflow JSON validation, timeouts, and GPU contention with other local processes. Avoid publicly exposing an unrestricted ComfyUI or orchestration endpoint.

**WF-09 — Incremental migration rather than a rewrite.** Propose a modular decomposition of existing oversized components only where it lowers real maintenance or failure risk; keep existing generation recipes, tests, caching, asset paths, import/export contracts, and other non-art dashboard capabilities intact.

### D3 — Evaluators, Gemini, and Claude-token optimization

**AI-01 — Provider-neutral visual evaluation interface.** Build an adapter contract for local LM Studio vision, Gemini API, Qwen/GLM APIs, and possible future providers. Define image/ref input, instructions, response schema, health checks, timeouts, budget reporting, and model provenance. Keep existing simple QA if it works.

**AI-02 — Layered QA, not one vague “good-looking” score.** Separate deterministic technical checks (dimensions/alpha/number of views/layout/cropping/metadata), local semantic QA, art/style critique, readability-at-gameplay-scale, animation continuity, and optional pairwise ranking. Define hard failures versus subjective preferences. The evaluator must compare to actual style references, not generic internet aesthetics.

**AI-03 — Structured, displayed AI decisions.** Produce validated machine-readable findings/actions; present concise user-facing explanations and action plans on the relevant candidate/frame, plus a durable agent activity timeline (started, image loaded, inspected, issues identified, action proposed/approved/executed). **Do not describe hidden chain-of-thought as exposed reasoning.** Distinguish facts, model judgments, and executed actions.

**AI-04 — Meaningful autonomy modes and approval gates.** Evaluate modes such as Observe, Suggest, Auto-iterate, Auto-select, and mandatory final human approval. Make scope explicit: allowed prompt edits, number of rerolls, cross-look mixing, installs, export/commit, overwrites, and pause/reject/override controls. Human control should be genuine, not merely a decorative button.

**AI-05 — Claude Code high-level handoff.** Expose a stable one-command art workflow interface (`start`, `status`, `cancel`, `result`, possibly `review`) using the simplest viable combination of CLI, REST, and optionally MCP. Claude should submit a brief and asset identity, receive job ID, then obtain only a compact terminal summary/paths unless details are needed. This is the principal way to save Claude's visual-review tokens.

**AI-06 — Evaluator runtime feasibility and subscription compliance.** Assess `agy`/Antigravity CLI *only if genuinely appropriate*: is scripted third-party orchestration allowed by current terms and supported by actual CLI capabilities? Does it accept local **image pixels** rather than merely their paths, especially in headless mode? What are concurrency, quotas, and output formats? Compare with official Gemini API/local models. No brittle OAuth token extraction, browser UI automation, or pretending CLI text-path prompts guarantee image vision. Flag open questions and suggest a safe fallback.

**AI-07 — Cost, latency, and quota-aware evaluator routing.** Use low-cost deterministic/local screening first and escalate only deserving frames/candidates. Consider batching images, review-on-demand versus every frame, cached critiques keyed by image+rubric+model, local fallback, API-budget cutoffs, and realistic GPU/time tradeoffs. Do not force cloud vision calls for obviously invalid images.

**AI-08 — Quality calibration and reproducible evaluation.** Build a modest test set of known good/bad assets (including angle mismatch, broken limbs, flicker, malformed transition, incorrect style, clean examples). Evaluate false positives/negatives, consistency with my choices, and whether repair advice actually improves results. Include a strategy for comparing alternative evaluator models rather than blindly trusting benchmark scores.

### D4 — New critical requirement: VACE-assisted animation/frame repair

**This is not a minor optional add-on.** My current local animation generator occasionally produces bad individual frames or inconsistent character identity between views/angles. I have already introduced a VACE repair concept or prompt in the project; **find and inspect that current implementation/instruction** before designing a duplicate. VACE is intended to be a targeted **frame-repair workflow inside ComfyUI**, ideally conditioning a damaged frame or temporal window on adjacent good frames and the appropriate character/view reference, rather than regenerating the entire character or clip.

**AN-01 — Exhaustive animation-method applicability.** Assess a “Repair Frames / VACE” capability for **EVERY Hero and Enemy art-asset method that results in any kind of animation**, including video-derived, pose/depth-driven, puppet-guided, procedural, copied/recolored, and preexisting/reimported assets. Produce a **method-by-method matrix** with current frame source, applicability, best hook point, technical constraints, and proposed fallback where VACE would not be appropriate (e.g., deterministic/procedural frames). Do not blindly use VACE when procedural regeneration or direct sprite editing is safer or better.

**AN-02 — Preflight VACE feasibility and installation.** Verify which VACE workflow and model variant is already configured or proposed, actual model availability, weights/source/license, required ComfyUI nodes, dependencies, network access, output format, VRAM and compute fit, compatibility with our existing AI server and generator, and practical edit/conditioning capabilities. **Check ability to download and install; do not actually download/install yet.** If blocked, describe the blocker, exact prerequisite, and alternative repair technique.

**AN-03 — Frame-by-frame animation review.** For each generated or existing Hero/Enemy animation, allow me to inspect **every individual frame** with scrubber, contact sheet/grid, frame indices, playback, zoom, neighboring-frame context, direction/view, clip/animation identity, selected Look, and warnings. Support selecting one or many frames for repair without requiring a whole-clip reroll.

**AN-04 — Targeted VACE repair of selected frames/segments.** Consider how to supply bad frame(s), neighboring good frames, source still(s), correct view/Look references, masks, temporal context, pose/driver information, and prompt corrections to VACE. Support one frame or a bounded contiguous span as appropriate to model limitations. Preserve timing, consistent pose progression, transparent background/alpha, visual style, silhouette, alignment, and sprite footprint. Critically assess whether the actual workflow truly supports *single-frame* replacement versus needing a sequence and cropping out relevant output frames.

**AN-05 — Frame consistency across frames AND angles.** Evaluate automated detection of temporal flicker, geometry/identity drift, costume/face/limb changes, view inconsistency (front, back, side, diagonals), scale/anchor shifts, sudden artifacts, repeated/stuck frames, missing motion arcs, and poor loop seams. The evaluator should highlight suspect frames and show *why*, but not silently repair every flagged frame.

**AN-06 — Durable per-frame candidate history.** Every regenerated/repaired frame should become a non-destructive **candidate/version**, never an invisible overwrite. For each timeline slot, show all historical versions, preview them, compare with neighbors, choose any earlier version, and see source, seed/prompt, source clip/look, model/workflow, generated time, human/AI selection, and QA status. Preserve this across reloads and rerolls; assess sensible archival/storage retention.

**AN-07 — Cross-Look frame library and selection.** I want to select a frame not only from the current Look's repair history but from **any Look ever generated** for the same relevant asset. Provide navigable labels such as `SP-A-1`, `SP-A-2`, `SP-B-1` (exact schema is negotiable), filters by Look/view/clip/time/frame, source previews, and one-click staging for substitution. Define immutable internal IDs separately from human-readable labels. Prevent accidental mismatch of animation slot, direction, resolution, alignment, pose, costume/style; show compatibility warnings and offer explicit override or adjustment as sensible. Clarify whether a frame is copied into a new version or permanently linked to the other Look.

**AN-08 — Batch frame edits with no export waiting.** I must be able to make **several frame substitutions/repairs in one sitting without blocking on save/export after each edit**. Selecting/replacing a frame should immediately update a *staged preview* and continue accepting user actions while repair jobs or exports run in the background. Assess multi-select repair, apply-to-selected, edit queue, undo/redo, optimistic updates, conflict handling, and how queued changes interact with active background generation.

**AN-09 — Non-destructive staged commit and atomic export.** Separate **edit** (stage candidate changes), **preview** (compose effective animation), **commit** (persist choices), and **export/install** (repack game-consumable strip/metadata, optionally asynchronously). Avoid making every per-frame click trigger expensive file writes, repacks, imports, or overwrites. Use a coherent transaction, explicit dirty state, consistent final validation, debouncing/coalescing where beneficial, and safe rollback if export fails. Define source-of-truth and how an interrupted app/job resumes. Ask me if a material ambiguity remains around auto-export/auto-install versus explicit commit.

**AN-10 — End-to-end compatibility with sprite packing and game runtime.** Trace how repaired/replaced frames interact with order, animation names, directional view mapping, stride cadence, normalized scale, pivots/origins, alignment, trimming, transparency, loop seams, frame count, atlas/strip layout, metadata, preview animation, game import, caching and subsequent rerolls. No “looks correct in editor but breaks in game” solution. Avoid a subsequent pipeline stage silently replacing repaired frames with regenerated originals.

**AN-11 — Retrofitting existing assets.** The review/repair/history workflow must be accessible from an **already existing Hero/Enemy asset or Look**, not only the currently running job. Determine how to ingest existing sprite strips/clip folders/metadata (including partial/missing provenance), create baseline version records, derive individual frames, edit, and rebuild safely without requiring full regeneration.

**AN-12 — AI-assisted frame fault triage and repair planning.** Let Gemini/another chosen evaluator flag likely damaged frames, explain defects adjacent to the frame, group related problems, and propose a repair strategy (swap from history, copy compatible version from another Look, simple image edit, single-frame VACE, short-window VACE, or regenerate an entire clip). Evaluate whether a **repair plan with multiple staged operations** is preferable to unbounded frame-by-frame autonomous activity. Never conflate evaluator recommendations with completed modifications.

**AN-13 — Approvals, acceptance and regression checks for repairs.** After repair, compare candidate against before, neighboring frames, original stills and applicable other views. Check identity, temporal continuity, pose and game-scale readability; verify alignment/alpha/format; retain prior best. Manual approval should remain possible, and repair should not create new visual glitches or break loop timing. Include a before/after replay and clear reasons for acceptance/rejection.

**AN-14 — Preservation of historical art and safe storage.** Define immutability/versioning, naming, deduplication/content hashes if helpful, garbage collection/retention policy, storage overhead, crash recovery, migrations, provenance and the effects of deleting/shelving a Look. Decide where original VACE inputs, masks, outputs, previews, and final chosen frames live. Never overwrite original assets without recoverable backup/versioning.

### D5 — Testing, observability, and deployment quality

**OPS-01 — Realistic end-to-end tests.** Include fixtures for successful/failed/aborted generations, streaming progress, reconnect, simultaneous edits, quota exhaustion, bad AI JSON, bad frame/angle, repairs, historical version recovery, cross-Look swap, export rollback, and existing-asset migration. Reuse existing self-test conventions where sound. Include a small runnable representative vertical slice.

**OPS-02 — Operational visibility.** Provide accessible error traces and metrics: generation/evaluation/repair/export durations, ComfyUI stage, queue/lock wait, currently active model, evaluation cost/quota where legitimately measurable, outcome distribution, reliability of QA, and user overrides. Present useful status in the UI while relegating detailed raw logs to diagnostics.

**OPS-03 — Minimal, deployable toolchain.** Assess local setup, Windows frontend/controller + LAN AI server, process lifecycle, ports, automatic reconnect, restart survival, updating dependencies, and running from Claude Code. Prefer a few dependable services over unnecessary infrastructure. Do not introduce Docker, Redis, a new database, Electron/Tauri, or a visual graph editor without showing genuine need.

## E. Required extra analysis of frame repair

In addition to assigning `accepted` / `rejected` / `questions` to **AN-01 through AN-14 individually**, present:

1. **Animation method coverage matrix:** one row for **every** current Hero/Enemy animation method and all relevant derived/look pathways; columns: method, output type, existing saved frames, VACE suitable? (yes/no/conditional), recommended repair operation, integration point, biggest risk, existing-asset support.
2. **Frame lineage/source-of-truth design:** explain the distinction between *timeline slot*, *frame candidate/version*, *Look*, *animation clip*, *view*, *generated source*, *staged selection*, and *installed/exported frame*. Show a compact proposed ID/data model and how human labels such as `SP-A-1` map to stable internal identities. Consider old game files without history.
3. **Staging/export semantics:** illustrate a concrete scenario: I open an existing Enemy's Look A, replace run/front frame 7 from Look B's history, regenerate frame 12 via VACE, switch frame 18 to an earlier candidate, continue browsing without waiting for exports, preview the effective animation, then commit once. Explain what writes to disk and when, what the UI shows, how failures/reloads behave, and how the game sees the final result.
4. **VACE feasibility proof plan:** identify prerequisites, test asset, candidate workflow, expected visual and metadata checks, approximate compute/storage costs if discoverable, and the **read-only preflight** possible now. Identify uncertainties requiring my choice or an eventual benchmark; do not report unrun tests as results.
5. **Failure-mode analysis:** at minimum incompatible frame size/view, costume/style mismatch across Looks, alpha loss, broken continuity, repair changing geometry, wrong direction mapping, caching overwriting repairs, multiple queued edits, crash mid-export, user editing during automatic repair, obsolete evaluation, and a Look removed while its frames are referenced.
6. **UX wireframe in words:** visual hierarchy and interactions for the per-frame browser, side-by-side/overlay review, issue badges, history drawer, cross-Look picker, staged-change queue, export status, and AI repair timeline. No actual frontend implementation yet.

## F. Exact response format I require

### F1. Brief factual architecture map

Explain existing frontend/server/jobs/generation/ComfyUI/sprite pipeline, major state boundaries, currently working features, and the top **five verified** blockers to my desired UX. Cite concrete code references, distinguish evidence from hypotheses, and say when environment verification isn't possible.

### F2. MASTER ASSESSMENT TABLE — mandatory, one row per ID

Include **every ID from UI-01 through OPS-03**, including **all fourteen AN items**. Do not merge rows, omit uninteresting proposals, or give a blanket acceptance to a category.

Use a Markdown table with at least these columns:

| ID | Proposed change (succinct) | What you like / expected benefit | What you dislike / cost, risks, or counterargument | Existing code or gap (evidence) | Status (`accepted` / `rejected` / `questions`) | Reason / specific questions / alternative |
|---|---|---|---|---|---|---|

Keep each cell readable. If a proposal requires extensive detail, put the full analysis in a subsection keyed to the same ID, **in addition** to its table row, not instead of it. Status labels must be exactly lowercase `accepted`, `rejected`, or `questions`. “Partially accepted”, “deferred”, “already exists”, “needs research”, and “conditional” are **not** additional status values: explain nuance in text while still selecting one of the three.

**Status interpretation:** `accepted` means you recommend implementing *after my approval*, not that you have done any work. `rejected` must contain an actual technical/product rationale. `questions` must list the questions I need to answer and the material competing alternatives.

### F3. Consolidated questions for me

Show only decisions genuinely blocked by ambiguity. Group questions by decision, provide a reasonable default/recommendation if possible, and reference affected proposal IDs. Avoid asking me things you can determine by reading the code or making an ordinary engineering choice.

### F4. Revised architecture recommendation

Give the **smallest viable coherent design** (components, state and storage, events, APIs, interfaces, model boundaries) and compare it with at least one simpler alternative. Explain how your design integrates with the existing code rather than assuming greenfield. Clearly identify *where* Gemini/Qwen/local QA, ComfyUI, Claude Code and human review interact. Recommend how to keep AI commands constrained and non-destructive.

### F5. Phased implementation proposal — still NO IMPLEMENTATION

For **accepted** items only, propose ordered phases with dependencies, expected complexity (S/M/L or approximate engineer-days if justifiable), key risks, migration strategy, minimum test criteria, and end-user visible outcome. Show a **minimum vertical slice** before any wider refactor:

`Claude submits one art job → ComfyUI generates → image appears live → evaluator comments beside image → chosen frame(s) are repaired or swapped → edits stage without blocking → one export commits → Claude receives compact final status.`

Keep risky experiments (especially subscription-based headless Gemini image evaluation and VACE compatibility) behind early feasibility gates; do not design the entire system around assumptions that have not been proven.

### F6. Critical recommendations

Finish with:

- Top five **highest-ROI** improvements, ranked and justified.
- Top five proposals you would **reject, simplify, or defer**, with reasons (even if most are accepted; clearly distinguish defer as an implementation sequence, not a fourth decision status).
- What must be preserved to avoid regressions.
- What you would benchmark or prototype before committing to a particular library, model, or architecture.
- Explicit statement confirming **no code, assets, weights, or environment were changed** during this review.

## G. Detailed product behaviors to reason about

While assessing, use these specific user journeys as practical tests of the architecture:

**Journey 1 — Claude delegates art production.** I ask Claude Code to “generate a new enemy with front/back animation in our style.” Claude sends one high-level request, returns the dashboard job link and goes back to game work. The dashboard autonomously generates candidates, performs low-cost QA and optional Gemini critique, displays every meaningful step, retains the best, and asks for approval only when appropriate. Claude later retrieves a compact result, not images and voluminous logs.

**Journey 2 — Frame 11 is visibly broken.** I open the animation preview, scrub to frame 11, see context for frames 9–13, click the flagged defect, choose a VACE repair, optionally edit the repair instruction, and compare original and repaired frames. The previous frame remains available; no destructive writes occur until the proper commit stage.

**Journey 3 — A better frame exists in another Look.** I open a character's Look A, browse prior frame variants and Look B's version history, choose a compatible version of the same logical motion/view/slot, stage it for Look A, receive compatibility warnings as needed, and keep the original Look B unchanged. Historical names like `SP-A-1` are human-readable labels, not identity guarantees.

**Journey 4 — Batch editing should feel instant.** I stage replacements for 3, 11, 19 and a 2-frame repaired segment, scrub/preview the composed animation immediately, undo one replacement, start a second repair in the background, then commit the final set with one export. UI input stays responsive while generation or export runs; failures do not destroy choices.

**Journey 5 — Existing assets.** An Enemy generated weeks ago has a bad side-view run loop. I open it directly from the asset browser, not from an old job record. The editor can reconstruct frames and metadata from its installed sprite strip if necessary, repair selected slots and export a corrected asset without regenerating everything.

**Journey 6 — Failure and recovery.** ComfyUI disconnects, a Gemini call errors, or the browser closes while frames are being reviewed. After reconnecting, I see actual status, outstanding reviews, selected versions, incomplete operations and actionable errors. No duplicate job, silent reset, lost frame history, or corrupt sprite export.

## H. Review quality bar

This assessment should resemble a serious architecture RFC review, **not** a generic “we should use React and add AI” wish list. Refer to actual code, identify reuse opportunities, challenge assumptions, and make concrete tradeoffs. Be particularly skeptical of solutions that hide the complexity of sprite provenance and non-destructive frame replacement behind a superficial UI.

My intention is to approve or challenge the plan after reading your assessment. **Do not begin implementation in this response.**
