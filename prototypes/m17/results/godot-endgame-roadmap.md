# VoxelWorld Godot — M23 to Finished Playable World Roadmap

**Purpose:** Continue the Godot prototype from M23 to a complete, playable, resource-driven voxel building game whose visual language is guided by the supplied Dragon Quest Builders-style references.

**Project:** `prototypes/m17/godot/`  
**Current handoff:** **M22–M28 are implemented and verified**, plus the post-endgame user request for a **complete starter house near spawn** (M29 in the progress/roadmap docs). The final showcase is a player-authored village + castle built block-by-block on a normal generated world, saved/reloaded through the real `SaveManager`, and captured at day/dusk/night. The final definition of done is met for this roadmap, with the documented caveats that the journey is scripted through the real systems (no human play-through) and the M27 visual gaps remain.  
**Reference images:** `prototypes/m17/references/visual/dragon-quest-builders/` (see image workflow below).

This roadmap complements the existing `prototypes/m17/results/godot-roadmap.md`, `GODOT_MISSION.md`, `AGENTS.md`, and `ARCHITECTURE.md`. It does not replace their rules or change the production Python/Ursina game. Treat this as the playable endgame plan and keep milestone work scoped to one milestone at a time.

## Product goal

Deliver a stable single-player world where the player starts in a natural, explorable landscape, finds and harvests resources, crafts a useful architectural palette, and builds their own home, village, and castle block by block. The world should evoke the references through layered green terrain, forests and water, warm timber, stone foundations, shaped tiled roofs, paths, gardens, bridges, windows, fences, and warm lantern light.

The finished showcase must be **player-built**. Do not make a prebuilt village or castle the main result or a prerequisite for play. Existing procedural ruins or isolated exploration landmarks may remain, but the player’s intended settlement site should be an empty, buildable natural area. Do not copy Dragon Quest Builders assets or branding; use the images as composition, color, material, and atmosphere references.

## Operating rules for OpenCode

1. Start each run by reading `AGENTS.md`, `ARCHITECTURE.md`, this roadmap, the current `prototypes/m17/results/godot-roadmap.md`, recent progress notes, and `git status`. Inspect actual code and evidence before deciding status. Preserve all unrelated modified and untracked files. Never reset, clean, or overwrite them. Keep every change inside the Godot prototype and its relevant documentation/reference folders; leave the original Python/Ursina implementation untouched.
2. M23 is already underway. First determine what OpenCode has changed, what remains, and whether its acceptance checks pass. Continue that work in place. Do not reimplement a passing feature.
3. Work on **one milestone at a time**, in dependency order. Keep the next milestone parked until the current milestone has passing tests, direct runtime checks, visual review where required, and a truthful progress entry. An unresolved criterion stays open; do not mark it complete because code exists.
4. Make the smallest coherent change that meets the criteria. Reuse existing voxel data, recipes, save formats, chunk streaming, test harnesses, capture switches, and generated-texture tools. Do not replace the renderer, engine, or architecture without measured evidence and a documented, necessary reason.
5. Favor local procedural/generated assets and existing licensed assets. If adding external assets, verify source and license and update `prototypes/m17/godot/ASSET_MANIFEST.md`. Do not add paid assets, secrets, unexplained dependencies, or copied game art.
6. Be budget-conscious: inspect first; write a short implementation checklist; run only the relevant tests during iteration; run the full unit, integration, determinism/smoke, and required visual checks once at the milestone gate. Reuse captures and reports when code has not affected them. Do not repeatedly regenerate assets, reinstall tools, benchmark unchanged code, or spend a run re-evaluating Godot.
7. Capture evidence to the existing `prototypes/m17/results/godot/` location. Update `prototypes/m17/results/godot-progress.md` and `godot-roadmap.md` with files changed, commands/results, screenshots, measured limits, and open items. Distinguish automated, runtime, and visual evidence. Do not claim human input or visual inspection that did not happen.
8. If a tool, display, or resource is unavailable, try a practical local fallback and continue. Stop only for a genuine external blocker, data-loss risk, a paid/credentialed action, incompatible architecture that cannot be resolved safely, or an acceptance criterion that needs a product decision. Record the exact blocker, evidence, and smallest decision needed; do not silently skip a requirement.
9. At each completed milestone, save a recoverable Git state according to repository conventions, staging only files belonging to that milestone. If repository state or permissions prevent a safe savepoint, report that plainly and preserve the working files.
10. At the end of each run, report milestone status, evidence paths, known limitations, and the exact next action. Do not continue into the next milestone during the same run unless the task explicitly asks for it.

## Image reference workflow

Keep the three supplied images together in `prototypes/m17/references/visual/dragon-quest-builders/` with descriptive names such as `castle-exterior.png`, `village-market.png`, and `landscape-bridge.png`. These are visual references only; preserve their original image files and attribution/context if available. Do not transform them into game textures.

For every visual milestone:

- Read the references before choosing materials, colors, foliage density, roof shapes, framing, or lighting. Write a brief observation list in that milestone’s progress report (e.g. terraced grass and exposed soil/stone; warm timber against pale stone; roof overhangs and ridge detail; clustered but readable buildings; winding path, bridge, water, flowers, and warm point lights).
- Run a **normal playable-world capture** on a fixed seed and record seed, render distance, resolution, time of day, and camera coordinates/direction. Capture both a broad landscape view and close views of terrain/materials and player-built architecture. Use the existing `--visual-test` only for isolated diagnostics; it is not evidence that ordinary world generation or the player’s building loop works.
- Compare the runtime captures side by side with the references at the same displayed size. Record concrete differences and fix the largest visible gaps first. Assess terrain silhouette/layers, palette, readable block materials, vegetation variety, water/path integration, roof/beam/window detail, depth/atmosphere, lighting, and camera composition. Avoid claiming pixel matching: the references are stylized targets, while VoxelWorld keeps its own assets and voxel scale.
- Preserve before/after screenshots with stable, descriptive names. A screenshot proves only what is visible in that frame; pair it with tests/runtime interaction evidence for gameplay claims.

If the images are not yet in the repository folder, copy the supplied originals there before beginning visual comparisons. Do not block nonvisual work while waiting for them; record their absence and continue other milestone checks.

## Milestones

### M23 — Finish roof stairs and verify stair behavior — **COMPLETE 2026-10-20**

**Goal:** Complete the already-started stair feature so roofs can form intentional slopes and edges, with correct voxel interaction and survival across streaming and saves.

**Status:** Delivered. The delegated handoff had a non-compiling mesher (three type-inference errors) and had accidentally deleted the normal cube/water face emitter; both were fixed, the stair face-count contract was corrected to the verified 22 half-faces, and the v8 legacy-save test payload was repaired. Evidence: `godot-progress.md` M23 section, `m23-stairs-roof.png`, `m23-stairs-profile.png`, `m23-stairs-dusk.png`.

**Dependencies:** Existing M22 roof-tile/ridge vocabulary, block definitions, mesher, interaction, inventory/crafting, persistence, chunk streaming.

**Acceptance criteria:**

- Inspect and continue the delegated implementation; add only missing work. Stair placement/orientation is predictable from the aimed face/player direction and produces a readable stepped roof silhouette.
- Stair geometry and collision agree; faces cull correctly against adjacent blocks and stairs; no invisible, inverted, or floating faces at chunk boundaries.
- Stairs can be crafted from reachable resources, selected, placed, mined, and returned as the correct item/drop using existing inventory/tool rules.
- Stairs round-trip through save/load and chunk unload/reload with orientation intact; deterministic world behavior remains unchanged except for the intended feature.
- Relevant unit/integration tests pass; a normal runtime roof capture and a close orientation/collision check are inspected. Record any live input limitation honestly.

**Evidence:** focused stair tests, full milestone-gate suite, smoke/determinism result, normal-play roof screenshot, close screenshot, updated progress entry.

**Gate:** Do not start M24 until every criterion is verified or an explicit blocker is recorded.

### M24 — Make exploration yield a useful building economy — **COMPLETE 2026-10-20**

**Goal:** Make a fresh player journey supply the materials needed for attractive construction through exploration, harvesting, mining, crafting, and smelting.

**Status:** Delivered. Gravel now generates in the submerged subsurface band (the path recipe previously had no world source). `test_economy.gd` scans real terrain for every raw material and follows an empty-inventory route through the real tool gates, station scan and crafting transactions to the full build kit. Gate: unit 1912 / integration 426 assertions, smoke `world_hash=2065363152372568468` stable. Evidence: `godot-progress.md` M24 section.

**Dependencies:** M23 complete; existing M20 inventory/crafting, M21 survival/progression, M22 recipes and blocks.

**Acceptance criteria:**

- Trace a fresh-world route from starter state to a small, varied build kit: harvest wood/foliage, gather dirt/stone, find ore or clay, and craft/refine timber, masonry, roof pieces, glass, doors/windows, paths, fences, and lighting using the actual item/station systems.
- Confirm every core build material is obtainable through a reachable source/recipe chain; no recipe depends on an unobtainable item or hidden debug grant. Starter items do not bypass the intended progression.
- Validate tool gates, drop quantities, fuel, station access, inventory capacity/feedback, and recipe readability for the route. Fix only concrete progression dead ends or confusing blockers within this scope.
- Show the player can choose where to establish a home; generated structures are optional landmarks and do not supply a ready-made player village/castle.

**Evidence:** reachable-recipe/dependency checks, targeted integration route, fresh-world play evidence or a deterministic harness that follows the real player/inventory/station path, and updated recipes/progression notes.

### M25 — Make voxel construction expressive and dependable — **COMPLETE 2026-10-20**

**Goal:** Let a player comfortably shape a house, village street, and castle with the existing authoritative voxel world.

**Status:** Delivered. Added stair rotation (`R`), a live placement preview (material, aimed face, count, valid/blocked reason, facing) and a scripted player-authored cottage + tower built cell-by-cell through the real block API (`--build-demo`, no `StructureDB` stamp). Gate: unit 1943 / integration 429 assertions, smoke hash unchanged; captures `m25-build-{wide,cottage,tower,dusk}.png` inspected. Evidence: `godot-progress.md` M25 section.

**Dependencies:** M24’s reachable materials; M23 stairs; current single-block mining/placement and save model.

**Acceptance criteria:**

- Define a compact architectural set with meaningful material contrast: foundation/masonry, timber/log/frame, wall infill, glass/openings, door, floor/path, stairs/roof/ridge, fence/gate, lantern, and small work/storage props. Reuse existing M22 content where it already meets the visual and gameplay need; add only high-value gaps (for example slabs or additional roof edges) after inspecting references and current assets.
- Improve placement feedback so target face, valid/blocked placement, selected material, and resource consumption are clear. Add orientation controls only where models need them and document the controls in-game.
- Verify building/removal at negative coordinates, chunk seams, overhangs, and around the player. Placement must never corrupt collision or allow placing inside the player. Mining/building updates only affected chunk meshes and neighboring seams.
- Player-made structures remain ordinary world blocks: mineable, craftable, collidable, and persistent; no showcase-only model or stamped prefab is required to build the target forms.
- Demonstrate a simple player-made cottage and a distinct stone/timber tower or castle section from gathered/crafted materials.

**Evidence:** interaction tests, real-scene placement/mining checks, two captures showing player-authored builds, and concise control/help text.

### M26 — Protect player-built worlds through saving and streaming — **COMPLETE 2026-10-20**

**Goal:** Make long-term building reliable across normal play, saves, chunk movement, and restart.

**Status:** Delivered. The save write now keeps a recoverable `.bak` across the finalise rename (restored on failure or by `read()` after an interruption), and `test_m26_protection.gd` proves a multi-chunk oriented build through fresh-world apply, far-chunk unload/regeneration, `clear_edits()` + re-apply and read-from-disk restart, plus corrupt-save rejection without mutating the live world. Gate: unit 2004 / integration 429 assertions, smoke hash unchanged; no meshing/streaming code changed, so no new benchmark. Evidence: `godot-progress.md` M26 section.

**Dependencies:** M25’s block palette and placement interactions; existing M16 streaming and save manager.

**Acceptance criteria:**

- Save/reload retains player location/state, inventory, placed and removed blocks, orientation/state for special blocks, station contents, and any relevant progression. Older save versions either migrate safely or fail with a clear, non-destructive message.
- A multi-chunk player build survives moving out of render range, unloading/reloading chunks, closing/restarting the game, and reopening the save. Boundary edits rebuild all required neighbors without duplicating or losing blocks.
- Saving remains atomic/recoverable; invalid or interrupted saves cannot silently replace a good world. Visual test mode remains isolated from normal user saves.
- Run deterministic world-generation/smoke checks and focused persistence/streaming integration tests; compare performance to the recorded baseline if these changes touch save, chunk, meshing, or streaming cost.

**Evidence:** save/reload integration results, restart/unload scenario, determinism hashes, any relevant before/after performance report, and updated compatibility notes.

### M27 — Bring normal generated worlds closer to the visual references — **COMPLETE 2026-10-20**

**Goal:** Improve the actual explorable world’s visual identity, not just a test arena.

**Status:** Delivered increment. Fixed the shallow-water z-fighting/checkerboard (water culls against solids), restored real cutout oak/pine leaf art (M18 had made it opaque), added AO on foliage, per-tree crown lean/raggedness, stronger green variation, denser ground cover, stone on slope ≥ 3, and retuned water/clouds/fog/aerial perspective. Before/after fixed-seed normal-world captures and the player-built cottage/tower were inspected; settle p95/p99 are at or below baseline. Gate: unit 2005 / integration 429 assertions, smoke `world_hash=5222532724760257225`. Remaining gaps are recorded in `godot-progress.md` (canopy still reads as a carpet from high above, visible loaded-region edge, no generated gorge terraces). Evidence: `godot-progress.md` M27 section and `m27-*.png`.

**Dependencies:** M23–M26 stable enough to avoid visual iteration on broken building/persistence systems; reference images present.

**Acceptance criteria:**

- Tune terrain layering and silhouettes so hills, exposed dirt/stone, rivers/ponds, clearings, and tree lines read as a coherent voxel landscape at close and middle distance.
- Preserve recognizable biome variety while improving natural foliage shapes/density, ground accents, paths/water edges, and color harmony. Keep flowers/foliage readable and avoid a uniform green canopy or a washed-out horizon.
- Refine the available construction palette using the existing generated-texture workflow: warm wood, contrasting stone, readable glass, coherent roof/ridge pieces, and useful small details. Maintain per-face consistency and block-edge readability.
- Tune daylight, distance haze, shadows, dusk/night, and warm lantern pools so objects remain readable and frame time remains acceptable. Do not use post-processing to hide geometry/material defects.
- Evaluate fixed-seed normal-world captures against all three references using the image workflow above. Also capture the player-built cottage/tower in its natural setting; a preplaced showcase alone cannot satisfy this milestone.
- Keep generation deterministic, collision/harvesting correct, and performance within a documented acceptable range relative to current measurements.

**Evidence:** fixed-seed broad/close/day/dusk captures, written side-by-side comparison and fixes, generation/determinism tests, runtime check, and performance report when affected.

### M28 — Finish the playable loop and release-quality pass — **COMPLETE 2026-10-20**

**Goal:** Prove the game is a complete, coherent small sandbox rather than a collection of systems.

**Status:** Delivered. `FinalDemo` builds a home, longhouse, market stalls, tower, street, gardens, well, lanterns and a recognizable castle on a natural site, cell-by-cell through the real build API and recorded as player edits; `_final_journey_section` saves and reloads it in the live scene. Gate: unit 2026 / integration 438 assertions, smoke `world_hash=5222532724760257225`; captures `m28-final-{wide,village,castle,dusk,night}.png` inspected. The journey is scripted, not a human play-through; the site is levelled by the harness. Evidence: `godot-progress.md` M28 section.

**Dependencies:** M24 progression, M25 construction, M26 persistence, M27 world presentation.

**Acceptance criteria:**

- Complete an end-to-end fresh-world journey: spawn safely; explore; harvest and mine; craft/refine materials; build and furnish a home; extend it into several distinct village buildings/paths/lighting; build a recognizable castle/tower using gathered materials; save, quit, reload, and continue.
- The starting/building area is natural and unbuilt. The final village/castle visible in evidence was constructed by the player during the journey. Document any test harness help and do not count debug grants or a pre-stamped structure as proof.
- Core menus, HUD, inventory, recipes, controls, pause/death/respawn, and save/load provide enough feedback to play without consulting source code. Fix high-impact input/UI/audio/visual blockers discovered in this complete journey; avoid unrelated feature expansion.
- Verify previous M1–M22 behavior relevant to this journey; run all unit and integration tests, headless smoke and deterministic generation checks, then a windowed runtime playthrough and visual review. Record hardware/display/tool limits and any unavailable human-only input checks.
- Record known defects and performance limits. There must be no known data-loss, lost-item, unusable-recipe, game-blocking progression, or player-build corruption defects.

**Evidence:** end-to-end route notes, final player-built-world screenshots (broad village/castle, close material/building details, daytime and dusk/night), test/runtime logs, save-reload result, final updated roadmap/progress docs.

## Dependencies at a glance

`M23 stairs` → `M24 reachable resource/building economy` → `M25 expressive reliable construction` → `M26 durable saves and streaming` → `M27 normal-world visual refinement` → `M28 complete end-to-end playable proof`.

If inspection shows a dependency is already fully implemented and verified, document the evidence and close that criterion without repeating the work. If a dependency is only partially implemented, finish the smallest necessary gap in its owning milestone.

## Final definition of done

VoxelWorld Godot is done for this roadmap only when all of these are demonstrated in the same maintained project:

- The player explores deterministic, natural voxel terrain with readable forests, hills, water, and material variety inspired by the visual references.
- The player can independently obtain and craft the materials to build with a coherent architectural vocabulary, including useful roofs and settlement details.
- The player can author a cottage, a village layout, and a recognizable castle/tower in ordinary gameplay; these are not supplied as a prebuilt player settlement.
- Player-made work survives mining/placement interactions, chunk boundaries, streaming, saving, closing, and reloading.
- A complete fresh-world resource-to-castle journey is playable and evidenced, with automated tests, direct runtime validation, visual comparison captures, and performance/known limitations accurately reported.
- The production Python/Ursina implementation and unrelated user changes remain preserved.

## Stop conditions and handoff

Stop and write a handoff when a true external blocker requires user credentials, payment, a destructive choice, unavailable hardware/tool access with no useful fallback, or a product choice that materially changes the build loop. Before stopping, preserve current work, run the safest relevant checks, update progress, and state the exact decision/input needed. Do not stop merely because one milestone is complete; the roadmap’s goal is the finished playable loop.
