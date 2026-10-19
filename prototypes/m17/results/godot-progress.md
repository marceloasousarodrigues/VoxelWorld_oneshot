# M17 Godot — Progress and Resume Point

## M19 — Interactive crafting stations and persistent inventories (2026-10-19)

Mission: turn the placed crafting table and furnace into real, targetable world
objects with their own persistent inventories and dedicated interfaces, using the
existing inventory, recipe and save systems rather than a second implementation.
The work lives in the Godot project under `prototypes/m17/godot/`; the production
Ursina implementation was not touched.

### Implemented

**1. Reusable station inventory (`scripts/core/station_inventory.gd`)**

- Slot-role container (`grid`, `input`, `fuel`, `output`) with the same item
  id/count/durability model as the player `Inventory`.
- Role acceptance: grid takes any item, input only smeltable items, fuel only
  fuels, output only station writes. Stack caps come from `ItemDB`.
- Count-preserving `insert`/`take`/`split`/`move`/`swap`/`remove_item`/`deposit`
  and atomic `to_dictionary`/`from_dictionary`. A refused operation returns the
  untouched stack, so no move can duplicate or destroy an item.
- A `changed` signal drives UI refresh; nothing in the model knows about nodes.

**2. Station behaviour (`scripts/core/station.gd`, `scripts/core/smelting.gd`)**

- A station owns its kind (`crafting_table` / `furnace`) and inventory layout.
  Adding a future workstation is a kind + role list, not new UI logic.
- Crafting table: real 3x3 grid (`Crafting.match_grid`), shaped and shapeless
  recipes from the existing 32-recipe catalogue, a live result preview, and an
  **atomic** `craft_grid()` that checks the result slot first, then consumes one
  item from every occupied cell and stores the output. The result slot refuses
  player inserts; the grid is persistent station storage.
- Furnace: input/fuel/output, a timed `step(delta)` driven by data
  (`Smelting.FUEL_SECONDS`: coal 48 s, logs/planks 12 s, sticks 4 s; per-recipe
  cook time, iron 8 s, others 6 s). Fuel only burns while there is work and room
  for the output, output is produced atomically, a full result pauses the cook,
  and changing the input resets progress.
- `Crafting` smelting recipes gained a `time` field; the recipe catalogue remains
  the single source of truth for what an input smelts into.

**3. World identity (`scripts/core/station_registry.gd`)**

- Station state is keyed by world position (integer cell), independent of chunk
  load/unload and generation order. State is created lazily on first use, so an
  untouched station costs nothing.
- `station_at` validates the live block, drops stale state when the cell is no
  longer that station, and `prune()` sweeps only **loaded** cells (an unloaded
  chunk is not evidence that a station is gone).
- `tick(delta, focus)` advances only loaded furnaces within `ACTIVE_RADIUS` (64
  blocks), so processing cost follows the player's neighbourhood. Contents,
  burn time and cook progress are kept while unloaded and resume on return.
- `take_contents()` removes state and returns every stack for the destruction
  policy below.

**4. Targeting and interaction (`game.gd`, `game_hud.gd`, `project.godot`)**

- New `interact` action on **E** (physical key 69), using the existing camera
  voxel ray (`VoxelRay`, reach 6) — the same target the miner/outline uses, so a
  station must be loaded and within reach.
- Aiming at a table/furnace shows `E  use Crafting Table` under the crosshair;
  the existing outline still marks the cell.
- E (or Escape) closes the interface; Escape closes it before pausing. Opening a
  station closes the crafting, inventory and settings overlays (mutual
  exclusion), disables `player.can_interact`, shows the mouse and captures no
  world input.
- Invalid targets report `Nothing to interact with` / `X is not a workstation`;
  beyond reach the block is simply not targetable and the message is shown.
- Breaking a station recovers its contents into the player's inventory and
  reports the outcome; placing a station clears any state in that cell so a new
  object never inherits an old inventory.

**5. Interfaces (`game/station_slot.gd`, `game/station_panel.gd`)**

- `StationSlot` draws either a player or station slot (icon, count, durability,
  role caption, tooltip with name/quantity) and implements click, right-click,
  shift-click and Godot drag & drop without mutating a model.
- `StationPanel` is one overlay for both kinds, in the M18 visual language: dark
  rounded panel, 3x3 grid + result (with ghost preview) for a table; input, fuel,
  output, COOK and FUEL bars and a live status sentence for a furnace; the nine
  player slots, a carrying slot and a hint line. It reads the models and emits
  messages only.
- Table controls: `Return grid` (returns leftovers to the player, keeps anything
  that does not fit), `Take result`, and clicking the result crafts and takes.
  Right-click splits/places one; shift-click quick-moves between inventories.
- Closing with a carried stack returns it to the player and then to the station,
  so closing cannot destroy an item. Ingredients left in the grid stay in the
  station (documented persistent-storage policy).

**6. Persistence (`save_manager.gd`, save VERSION 6)**

- New `stations` payload: `[x, y, z, station state]` rows; each station state
  includes kind, slot contents and furnace timers. Validated before any live
  state changes; rows are validated/rejected individually by the registry.
- Versions 1–5 still load with no station state. The game passes the payload
  through `_stations_payload()` / `_apply_stations()`.
- **Bug found and fixed by the new test:** `_reload_now()` passed
  `result["data"]` to `SaveManager.apply()` (which expects the `ok`/`data`
  wrapper), so every F9 reload failed with "save is not validated". It now passes
  the validated result; station save/load is covered by the integration test.

### Explicit policies

- **Closing the interface:** carried stacks return to the player, then the
  station; grid/input/fuel/output contents stay in the station.
- **Destroying a station:** its contents transfer to the player. If the inventory
  is full the remainder is reported and lost — the same explicit rule the game
  already applies to a mined block's drop, because there is no dropped-item
  entity system. The block itself still drops normally.
- **Chunk unload/reload:** station state stays in the registry (keyed by cell),
  so it survives; the registry only prunes a station when a *loaded* cell no
  longer holds it.
- **Coexistence with the recipe-list panel:** `C` still opens the existing
  catalogue interface (a deliberate convenience that uses the same `Crafting`
  model and consumption rules). The world-object panels are the new interaction;
  both consume through `Crafting`/`Station`, so there is one source of truth.
- **Grid matching is per cell:** four planks need four cells, exactly as placing
  ingredients in a Minecraft grid; a stack of four in one cell is not a recipe.

### Verification actually run (Godot 4.7.2 stable mono, Windows)

- Unit: `--headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd`
  → **1447 assertions**, exit 0, **0 bytes stderr**. New `test_stations.gd`
  covers role acceptance, caps, insert/take/split/move/swap/deposit, refused
  operations, serialisation/rejection, smelting data, shaped/shapeless crafting,
  atomic craft refusal, result capacity, leftovers, furnace ignition/progress/
  fuel economy/output-full pause/serialisation/determinism, registry lazy
  creation, two independent stations, stale-state removal, chunk unload/reload,
  persistence round-trip and tick radius. `test_persistence.gd` covers save v6
  station rows, the v3 legacy path and a malformed `stations` payload.
- Integration: `--headless --path prototypes/m17/godot --script
  res://scripts/tests/run_integration.gd -- --straight-to-game` → **257
  assertions**, exit 0, **0 bytes stderr**. New assertions drive the real scene:
  target a placed table, open it with the real `interact` action, move items
  through the panel's own handlers, preview/craft/take a table, keep the world
  untouched while the interface owns input, open a separate furnace, insert sand
  and coal, advance it through the registry's real tick, take the glass, save →
  clear → reload → verify contents/progress, unload/reload the chunk, break the
  table through the player path and verify contents recovery, and verify sky and
  out-of-range interactions open nothing.
- Smoke: `--straight-to-game --quit-after=25` → exit 0, 0 bytes stderr,
  `world_hash=7995773462820745781`, `faces=170492`,
  `faces_hash=6834793821708419232` (unchanged from M18), `stations.count=0`.
- Windowed captures inspected (1280x720, seed 17017, `--time=0.25`):
  `results/godot/m19-crafting-table.png` — 3x3 grid with four planks, a ghost
  result preview and "Ready: 1 Crafting Table", the player row and carrying row;
  `results/godot/m19-furnace.png` — sand input, coal fuel, glass output (3),
  COOK and FUEL bars, "Smelting Sand → 1 Glass", "Furnace is cooking" and
  "Fuel: Coal · active". The furnace capture also proves live ticking: the
  screenshot was taken after the furnace completed a cook while the panel was
  open.

### Limitations / not verified

- No human keyboard/mouse play-through; all runtime evidence is scripted
  headless integration plus inspected windowed captures.
- There is no dropped-item entity, so a full inventory loses the reported
  remainder when a station is destroyed (explicit policy above).
- Furnaces process only within 64 blocks and only in loaded chunks; an unloaded
  furnace pauses with its progress preserved.
- One nine-slot player inventory row, as before; station slots are one page.
- The recipe-list panel remains available; it is not removed or replaced.
- Add/remove of station state is bounded by stations the player has used; the
  save payload grows with those stations (no per-chunk inventory bookkeeping).

### Resume point

Next independent work: the roadmap's remaining Phase D/C items (weather, city
management, player construction beyond single blocks) or a human play-through of
M19. The M19 system itself is implemented, tested, captured and documented.

---

## M18 — Visual quality upgrade (2026-10-19)

Mission: raise the Godot world to a polished stylized voxel-survival look without
changing the voxel architecture or the production Ursina implementation. Visual
design contract: `prototypes/m17/results/m18-visual-design.md`.

### Implemented and verified in the running game

- **Reproducible visual test area**: `--visual-test[=close|normal|wide|shore|sky]`
  builds a deterministic forest clearing at `(72, 65, -88)` with material pads,
  terraces, a sand-rimmed pond, boulders with ores, a crafting table, furnace,
  plank/glass wall and planted oak/pine trees, then places the camera at fixed
  viewpoints. It uses the real world, mesher, materials, fluid and streamer; it is
  disabled from autosave/creatures/NPCs/raids so captures are stable.
- **Materials**: `TextureLibrary` grades the vendored Minetest art in memory
  (brightness/contrast/saturation plus per-material channel tints) into a
  restrained palette; biome tints are now near-white hue shifts and grass is tinted
  on its top face only. A slow world-space macro-noise term in the voxel shaders
  breaks up tiling; a deterministic per-cell brightness variation is baked into the
  mesh.
- **Baked ambient occlusion**: the mesher computes standard 4-corner AO per opaque
  face (opaque/leaves/cactus occlude), so terrain, tree bases and station contact
  areas gain readable depth. The AO path is a flat offset table and skips
  cutout/transparent layers; it was optimized after an initial 2x mesher cost.
- **Custom stations**: the crafting table and furnace are real models emitted by the
  chunk mesher inside the one-metre cell (tabletop with a 3x3 grid, four legs,
  aprons, raised rim; furnace with plinth, body, top cap, recessed opening and a
  glowing ember interior). Collision and logical identity are still the full cube.
  New derived textures: `crafting_table_top`, `crafting_table_side`,
  `furnace_opening` (with an emissive flag carried in `UV2.y`).
- **Trees and rocks**: oaks and pines use rounded/conical multi-layer crowns and
  denser leaf textures (`oak_leaves_clean`/`pine_leaves_clean`); sparse boulder
  clusters with ore faces generate deterministically on flat dry land;
  `WorldGen.plant_tree` plants production-shaped trees at runtime.
- **Lighting/sky**: custom `shaders/sky.gdshader` (layered gradient, warm
  dawn/dusk band, sun/moon disc from the scene light, drifting clouds, night stars)
  driven by the existing `DayNight` clock; ACES tonemapping; four-split blended
  shadows; fog with sun scatter and aerial perspective; retuned day/night palette
  for readable nights.
- **Water**: rewritten `voxel_water.gdshader` with depth-based absorption/opacity
  from the depth prepass, world-space wave normals, shoreline thinning and a
  reduced atlas contribution (no more checkerboard). Source water surfaces are
  emitted at full height, so oceans are a single flat plane.

### Evidence

- Unit suite: **1273 assertions**, exit 0, 0 bytes stderr (`run_tests.gd`), including
  the new `test_visuals.gd` (station geometry/collision, AO, grass tinting,
  planted trees, boulders, visual-arena contents, sky curves).
- Integration suite: **184 assertions**, exit 0, 0 bytes stderr.
- Inspected captures (all `--hide-hud`, seed 17017, radius 5): `m18-step9-close-noon`,
  `m18-step9-normal-noon`, `m18-step9-normal-night`, `m18-step9-ocean-noon`,
  `m18-step9-ocean-sunset`, `m18-step6-coast-sunrise`, `m18-step6-shore-noon`,
  `m18-step6-water-noon`, plus the pre-change baselines `m18-baseline-vt4-*`.
- Day/night transition series at the coast (`m18-cycle-0.0.png` sunrise,
  `m18-cycle-0.55.png` twilight, `m18-cycle-0.9.png` pre-dawn): the warm horizon,
  moon, stars, sea colour and shadow direction all follow the clock; the twilight
  frame is dark but readable, consistent with the M17 tuning choice.
- Final noon captures after deepening the day sky and making the leaf textures
  solid (no cutout specks): `m18-step12-close-noon.png` and
  `m18-step12-ocean-noon.png`; fixed-yaw rotation stills `m18-sweep-1.png` /
  `m18-sweep-3.png` (compact `--shots` plus the new `--shot-prefix`) show stable
  materials around the clearing.
- Frame-time harness (`run_perf.gd`, radius 5, RTX 3080 / i7-10700K), M18:

  | scenario | p50 | p95 | p99 | 1 % low |
  | --- | --- | --- | --- | --- |
  | settle | 2.25 ms | 6.61 ms | 10.15 ms | 54 fps |
  | look | 1.96 ms | 2.79 ms | 3.22 ms | 177 fps |
  | walk | 2.01 ms | 6.05 ms | 9.63 ms | 77 fps |
  | cross | 1.81 ms | 4.14 ms | 7.05 ms | 104 fps |
  | water | 2.00 ms | 2.69 ms | 3.19 ms | 193 fps |

  Draw calls rose (settle ≈510 vs ≈369 before) because shadows now use four blended
  splits rather than two; frame times are unchanged-to-better and stream-work frames
  remain in the same range. Mesher CPU also rose (spawn emit ≈3.1 s for 392 chunks
  vs ≈1.8 s pre-M18; worst chunk ≈25 ms) from baked AO, denser canopies and more
  generated faces; meshing runs on the worker thread, so frame times are not
  affected, but the initial fill is slightly longer.
- Asset manifest and `assets/texture_sources.json` record the six M18 derived
  textures and their attribution.

### Limitations / not verified

- No human keyboard/mouse play-through; all runtime evidence is scripted captures
  plus headless unit/integration and the windowed perf harness.
- Runtime captures are frozen-clock; the live day/night transition was validated by
  the clock tests and earlier M17 cycle captures, not re-recorded as video here.
- The `boot` phase of one perf run showed a 1.35 s first-use frame (single run;
  other runs ~50 ms). It looks like one-off engine/first-use work, not a per-frame
  regression, but it is recorded rather than hidden.
- Leaf transparency still uses an alpha scissor; the denser leaf texture reduces
  shimmer/confetti. A five-step 20° yaw sweep was captured (`m18-sweep-*`, compact
  `--shots` without spaces plus `--shot-prefix`) and inspected as stills with no
  visible crawl, but no encoded rotating clip was produced, so motion shimmer is
  reduced-by-evidence, not eliminated-by-measurement.

Next useful work (not started): weather/particles, richer bark/grass side variants,
an in-game quality menu for shadows/SSAO/fog, and a scripted rotating-camera clip
for shimmer inspection.

## Renderer investigation — texture corruption and streaming frame-time spikes (2026-10-16, autonomous session)

Two independent defects were reproduced from the 15:39 and 17:27 recordings and fixed.
Each was diagnosed with instrumentation before any code changed, and each fix was measured
with the same seed (17017), render distance (4) and camera paths before and after.

### 1. Texture corruption: the array-layer coordinate was sampled at its midpoint (FIXED)

Symptoms (both recordings): grass surfaces covered in gravel-like pale blotches, sand with
large bright wedges and streaks, fruit/foliage streaked, and the pattern changing as the
camera moved. The committed `fix-spawn.png` already showed it (it had been read as a dirt
path next to the spawn).

Evidence gathered before touching code:

- Frames extracted from both recordings with ffmpeg; the artifacts are patchy, per-face and
  view dependent.
- Atlas probe (temporary windowed script): all 47 `Texture2DArray` layers are byte-identical
  to the source mip chains (worst byte difference 0) — the atlas data is correct.
- CPU probe (temporary headless script): `face_layer` resolves all 204 block faces correctly,
  the emitted buffers carry the right layer per face (grass top 21, sides 20, log 26, leaves
  25) and UV2 survives `add_surface_from_arrays` intact.
- Remaining candidate — the shader. Every voxel shader sampled
  `texture(atlas, vec3(UV, UV2.x + 0.5))`. For a `sampler2DArray` the third coordinate selects
  the layer; `+ 0.5` places it exactly on the boundary between two layers. This engine build
  rounds the coordinate, so faces — and, through per-pixel interpolation noise around the exact
  midpoint, parts of faces — sampled the *next* layer in sorted order:
  `grass_top`(21)→`gravel`(22), `sand`(33)→`sandstone`(34),
  `oak_leaves`(25)→`oak_log_side`(26), water animation frames→the next frame. Because the flip
  is driven by per-pixel interpolation, the patches move with the camera.
- Minimal experiment: removing `+ 0.5` from `voxel_opaque.gdshader` **only** cleaned the grass
  and left the leaves streaked (`m17-bug-oddlayer-test.png`), exactly as predicted.

Fix: sample the exact integer layer in all five voxel shaders; the water shader adds only the
integer animation frame index.

Regression test: `test_textures.gd` reads the five shader sources and fails if any atlas sample
offsets the layer coordinate by `+ 0.5` (the headless suite cannot execute the fragment path,
so the contract is pinned at source level).

Runtime evidence: before `m17-bug-baseline.png` (beach vantage) and `fix-spawn.png` (spawn);
experiment `m17-bug-oddlayer-test.png`; after `godot-game-tour-0.png` (same spawn vantage as
`fix-spawn.png`), `godot-game-tour-2.png` (terrace strata), and the separately required
foliage/water checks `m17-fix-foliage.png` and `m17-fix-water.png`.

Limitation: the engine build's rounding behaviour was established empirically; the contract
test protects our shaders, not a future engine version.

### 2. Frame-time spikes: in-frame chunk meshing and generation (FIXED)

Baseline method (new `scripts/tests/run_perf.gd`): boots the real scene windowed with vsync
disabled, drives one of six scripted activities (`settle`, `look`, `walk`, `cross`, `foliage`,
`water`), and records per frame the frame interval, `TIME_PROCESS`, generation/mesh/attach
milliseconds, queued/loaded counts and draw calls into
`../results/godot/perf-<scenario>-<label>.json`.

Attribution (before): steady state is cheap — settled `look`, `foliage` and `water` frames
average 1.10–1.29 ms (~800 fps), so draw calls and triangle counts are not the limit. **Every**
frame over 20 ms did chunk generation and/or meshing on the main thread: frames doing both
averaged 23.4–24.5 ms and there were 161–435 of them per run. Generation costs ~6 ms/chunk and
meshing ~5.7 ms/chunk (worst 17 ms), so two units cannot fit in a 16.7 ms frame.

Fix (remove the blocking work rather than hide it, no reduction in detail or render distance):
mesh construction now runs on a dedicated worker thread.

- `chunk_mesher.gd` is split into `capture_input` (main-thread snapshot of the chunk plus its
  six neighbours), `build_geometry` (pure arrays, creates no engine resources, safe off-thread)
  and `assemble` (ArrayMesh + collision shape on the main thread). `build()` keeps the old
  synchronous behaviour for tests.
- `chunk_streamer.gd` submits snapshots to one worker thread (`Thread` + `Mutex` + `Semaphore`),
  attaches finished geometry on the main thread, and stops/joins the worker deterministically in
  `clear()` and `_exit_tree()`.
- `chunk_data.gd` gained `mesh_revision`, bumped by `mark_dirty()`. The streamer only clears
  `mesh_dirty` when no newer edit landed while the build was in flight, and skips coordinates
  that already have a build in flight (without that it re-meshed the same chunks endlessly).

Measured before → after:

| activity | metric | before | after |
| --- | --- | --- | --- |
| walking (`walk`) | p95 / p99 / worst | 19.8 / 28.5 / 39.7 ms | 4.7 / 16.3 / 28.1 ms |
| walking | 1 % low | 31.9 fps | 53.5 fps |
| walking | frames > 20 ms that did gen+mesh | 432 | 46 |
| crossing chunks (`cross`) | p99 / worst | 20.6 / 39.2 ms | 7.5 / 26.6 ms |
| crossing chunks | 1 % low | 39.1 fps | 65.9 fps |
| settling (`settle`) | avg / p95 / p99 | 8.9 / 26.5 / 29.9 ms | 4.3 / 16.2 / 20.7 ms |
| settling | wall-clock until settled | 4.45 s | 3.32 s |
| settled `look` / `foliage` / `water` | average frame | 1.10–1.29 ms | 1.07–1.25 ms (unchanged) |

Streaming is not slower: mesh throughput during the settle phase rose from ~65 to ~90 units/s
and wall-clock settling fell ~27 %, because generation and meshing now overlap instead of
serialising inside the frame.

Regression tests: `test_mesher.gd` asserts a captured snapshot is immune to later edits and
that a fresh snapshot sees them; `test_determinism.gd` streams the same region synchronously
and threaded and requires the identical geometry hash; the existing fingerprint assertions pin
`world_hash=441363152919021799`, `faces=166074`, `faces_hash=6977993294663025454` (re-verified
unchanged).

Remaining limitations:

- One first-PLAYING frame costs ~49–50 ms in every run, before and after (first-use engine work;
  an identical frame exists in the baseline).
- Chunk **generation** still runs in the frame (~6 ms typical, up to ~21 ms), so a heavy chunk
  can still drop a single frame. Threaded generation is the next step (roadmap).
- The settle-phase 36–46 ms frames are dominated by first-use GPU work when a burst of geometry
  first appears; the attach time measured in those frames is only 1.7–23 ms. An attachment cap
  of 2 per frame was tried (`perf-{settle,walk}-after2.json`) and changed nothing measurable
  (settle p95 16.4 vs 16.2 ms, walk p99 16.3 vs 16.3 ms), so it was not kept.

### 3. "Apparent suspended terrain" (explained, not a defect)

The 17:27 recording shows terrain apparently floating in the sky (HUD `XY 8.6 / 1.1 / 8.4`,
`56/196` chunks). This is the world seen from *underneath* while it streams: the player is at
y≈1 (bottom chunk) and the mesher only emits outward faces (an unloaded neighbour must never
cull anything), so loaded chunks appear as detached shells; the dark quads are faces in shadow
(no sunlight reaches under the terrain). Reproduced deliberately with
`--fly --player-at=8.6,1.1,8.4 --look=38,20` → `m17-fix-underground.png`, which shows the same
appearance with correct textures. Face winding is already pinned by `test_mesh_winding.gd`.
No code change was made for this.

### Files changed

- `shaders/voxel_{opaque,cutout,blend,deco,water}.gdshader` — exact-integer layer sampling.
- `scripts/core/chunk_mesher.gd` — snapshot / pure build / assemble split.
- `scripts/core/chunk_streamer.gd` — worker-thread meshing, revision guard, deterministic teardown.
- `scripts/core/chunk_data.gd` — `mesh_revision`.
- `scripts/game/game.gd` — smoke/capture summaries report the worker mesher's statistics.
- `scripts/tests/run_perf.gd` (new) — reproducible frame-time harness.
- `scripts/tests/test_textures.gd`, `test_mesher.gd`, `test_determinism.gd` — regression tests.

### Verification on the frozen code (this session)

- `run_tests.gd` (headless): **M17_TESTS_PASS 615 assertions**, exit code 0, 0 bytes of stderr.
- `run_integration.gd -- --straight-to-game` (headless): **M17_INTEGRATION_PASS 35 assertions**,
  exit code 0, 0 bytes of stderr.
- Headless smoke `--straight-to-game --quit-after=25`: exit code 0,
  `world_hash=441363152919021799`, `faces=166074`, `faces_hash=6977993294663025454`.
- Perf reports and screenshots: `results/godot/perf-{look,settle,walk,cross,foliage,water}-{before,after}.json`,
  `m17-bug-baseline.png`, `m17-bug-oddlayer-test.png`, `godot-game-tour-0..4.png`,
  `m17-fix-foliage.png`, `m17-fix-water.png`, `m17-fix-underground.png`.

```powershell
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\...\Godot_v4.7.2-stable_mono_win64.exe'
# unit suite / integration suite
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
# frame-time benchmark (windowed; one scenario per run)
& $godot --path prototypes/m17/godot --script res://scripts/tests/run_perf.gd -- --straight-to-game --seed=17017 --scenario=walk --label=perf-walk-after
```

---

## Reviewer follow-up — survival/save fixes (2026-10-16)

Addressed the health/survival review findings without touching the Ursina
reference or voxel architecture:

- Current v3 saves now reject breath outside `[0, Survival.MAX_BREATH]` during
  read/sanitisation and quarantine invalid files. v1/v2 missing breath remains
  the legacy `-1` sentinel. `apply()` validates current-version breath and health
  before mutating any live health/world/player/inventory state.
- `Health.set_health()` emits `died` exactly once on a living-to-zero transition.
- Added integration coverage for lethal game-owned health signal, DEAD state,
  disabled physics/interaction and visible death overlay, then Respawn button
  signal activation and restored PLAYING/health/breath/physics/spawn/overlay.

Validation (Godot 4.7.2, headless): `run_tests.gd` passed **552 assertions**;
`run_integration.gd -- --straight-to-game` passed **29 assertions**. Respawn was
activated by emitting the real Respawn Button's `pressed` signal; a human-visible
mouse click was not tested. No game-render output was changed, so existing
captures were not re-captured.

Last updated: 2026-10-16 (autonomous Godot development session, third checkpoint —
stabilization pass: WASD movement, rendering, water).
Mission: `prototypes/m17/GODOT_MISSION.md`.
Roadmap: `prototypes/m17/results/godot-roadmap.md`.

**Savepoints**: `c22d056` — “M17 Godot: fix inverted triangle winding (movement +
rendering)” (current). Previous: `fd9f7d2` — “M17 Godot: day/night cycle (clock-driven
sun, sky, ambient, fog and water)”; `e029c68` — “M17 Godot: playable voxel game,
streaming, water, persistence, tests and docs”. Full log in §10.

---

## 1. Current objective

Turn VoxelWorld into a real, playable Godot 4 first-person voxel game and keep
expanding it toward a survival/building game (mission phases A → D). Phase A
(the playable voxel foundation) is complete and visually verified; work is now on
phase B (survival systems) and C (living world). This checkpoint was a stabilization
pass on the Phase A foundation: the user-reported WASD movement failure and the
rendering defects were reproduced, traced to a single inverted-face-winding bug, and
fixed (§8).

## 2. Current phase and next concrete task

- **Phase**: A complete (post-fix, re-verified), B in progress.
- **Next concrete task**: see §9 “Resume”.

## 3. What actually works (verified)

Verified means: observed in a run of the real project, not merely written.

| Area | State | Evidence |
| --- | --- | --- |
| Project opens and runs | verified | windowed runs, 60 fps, exit code 0, empty stderr |
| Deterministic terrain generation | verified | 3 consecutive runs, `world_hash=6372495951065888771`, `faces=166074` (unchanged after the winding fix); the hash is now `441363152919021799` after the clay-generation fix (§12), `faces` unchanged |
| Chunk meshing (face culling) | verified | 392 chunks, 166 074 faces, 332 148 triangles at radius 4 |
| **Correct face winding** | verified | `test_mesh_winding.gd` pins every solid + collision triangle to Godot's `BoxMesh` convention; `winding-test.png` |
| Streaming + bounded work | verified | `queued=0`, `worst_mesh_ms≈16`, `generation_ms_total≈2.8 s` |
| Player movement + collision | verified | `run_integration.gd` (17 assertions): lands at `y=70.000`, `is_on_floor()`, WASD forward/strafe/back, pause/resume, chunk-boundary walk |
| Block breaking / placing | verified | integration test + automated tests + HUD target readout in captures |
| Negative coordinates | verified | `test_coordinates.gd`, floor-based conversion |
| Water (logical + rendered) | verified | `test_fluid.gd`, water visible in `fix-water*.png`; no independent water defect found |
| Save / load, versioned | verified | `test_persistence.gd` drives `SaveManager` write→read→apply (blocks, fluid, player, inventory, clock), seed-mismatch rejection, version-1 load and corrupt-save quarantine |
| Main menu / pause / play loop | verified | menu is the boot scene; `--straight-to-game` skips it |
| HUD, hotbar, item counts | verified | visible in `diag-shore.png`, `godot-game-tour-*.png` |
| Textures, lighting, sky, fog | verified | inspected captures (see §6) |
| Day/night cycle | verified | test module + `day-noon.png` / `day-dusk.png` / `day-night.png` inspected |

## 4. Files and architecture

Godot project root: `prototypes/m17/godot/`.
`project.godot` main scene: `res://scenes/game.tscn` → `scripts/game/game.gd`.

**Engine layer** (`scripts/core/`, no scene-tree knowledge):

- `chunk_data.gd` — 16³ voxel storage, chunk/world coordinate conversion (floor semantics).
- `day_night.gd` — `DayNight` clock: time of day, sun angles/energy, ambient colour and
  energy, sky/ground/fog colours and the water tint as pure functions of the time;
  `--time=` / `--time-rate=` control it and it is saved with the world.
- `block_db.gd` — 34 block definitions in packed arrays (layer, solid, opaque, cull, liquid, hardness, drop, face texture keys).
- `world_gen.gd` — deterministic generation: continent/height field, biomes, caves, ores, trees, decoration, `SEA_LEVEL = 62`, `WORLD_HEIGHT = 128`.
- `voxel_world.gd` — authoritative voxel store, edit overlay, `block_changed` signal, `fingerprint()`.
- `chunk_mesher.gd` — face-culled greedy-less mesher, five render layers, water UV animation.
- `fluid_sim.gd` — bounded water solver, cross-chunk propagation, deterministic.
- `voxel_ray.gd` — voxel DDA raycast for targeting.
- `texture_library.gd` / `voxel_materials.gd` — `Texture2DArray` atlas + five `ShaderMaterial`s.
- `fixture_adapter.gd` — bridge to the shared M17 fixture (`shared/fixture/world.json`).

**Game layer** (`scripts/game/`):

- `game.gd` — orchestrator: state machine (MENU/LOADING/PLAYING/PAUSED), environment, CLI options, capture harness, persistence.
- `chunk_streamer.gd` — streaming queue, per-frame budgets, `face_counts`/`faces_fingerprint()`.
- `voxel_player.gd` — first-person controller, break/place, fly mode, targeting.
- `inventory.gd` — 9-slot hotbar model, serialisable.
- `game_hud.gd` / `main_menu.gd` — interface, title and pause screens.
- `save_manager.gd` — versioned JSON save, atomic write, corrupt-save quarantine.

**Legacy/compat**: `scripts/main.gd`, `scenes/main.tscn`, `scripts/capture.gd` and
`scripts/regression.gd` are the earlier fixture-slice entry points; they still run
but are no longer the project's main scene.

**Diagnostics**: the capture harness inside `game.gd`, `scripts/tests/*` (`run_tests.gd` is
the headless unit runner; `run_integration.gd` boots the real scene and drives player
input/collision; `run_perf.gd` is the frame-time benchmark harness),
`prototypes/m17/tools/image_stats.py` (objective image statistics).

## 5. Commands

Engine: `C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe`
(Godot **4.7.2-stable mono official**; the mono build is used because that is what is
installed — the project is pure GDScript).

```powershell
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
$repo  = 'C:\Users\Admin\Documents\Projects\VoxelWorld_oneshot'

# Automated tests (headless, exit code is the result)
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd

# Runtime integration test: boots the real scene and drives WASD/collision (exit code)
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game

# Headless smoke run (deterministic world fingerprint)
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=30

# Play the game
& $godot --path prototypes/m17/godot

# Render a screenshot from inside the running game and quit
& $godot --path prototypes/m17/godot -- --capture --capture-name=look-spawn.png --hide-hud --settle=12

# Scripted camera tour, one PNG per viewpoint
& $godot --path prototypes/m17/godot -- --capture --shots="38:-12; 90:-8:-30,66,0"
```

Note for shell scripting: launching the Godot GUI executable through a PowerShell
pipe can hang; use `Start-Process -Wait -RedirectStandardOutput` instead (that is
what the capture commands above were run with). Auxiliary CLI flags used for
inspection: `--fly`, `--player-at=x,y,z`, `--look=yaw,pitch`, `--render-distance=N`,
`--no-shadows`, `--fog=<density>` (`0` disables fog), `--settle=<seconds>`,
`--capture-name=<file>`, `--time=0..1` (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight)
and `--time-rate=<day-length-seconds>` (`0` freezes the clock).

## 6. Tests and visual verification performed

**Automated (headless)**

- `M17_TESTS_PASS 383 assertions`, exit code 0, 0 bytes of stderr.
- Modules: coordinates, chunk data/indexing, block DB, generation, mesher (incl. a
  stale-padding regression), **mesh winding**, raycast, edits, **persistence (SaveManager
  write/read/apply, validation and quarantine)**, fluid, fixture contract, textures,
  day/night clock (wrap semantics, lighting curves, continuity, determinism, clock text,
  save round-trip), streaming determinism, view/clear teardown.
- Runtime integration: `M17_INTEGRATION_PASS 17 assertions`, exit code 0
  (`run_integration.gd` boots `game.tscn` and drives the real player). It asserts
  physics processing is on, the player settles onto the ground at exactly
  `y=70.000` and reports `is_on_floor()`, that WASD forward/strafe/back actually move
  the body, that movement still works after pause→resume, that looking straight down
  targets/places/breaks a block through the real controller, and that walking across a
  chunk boundary keeps the player grounded while the neighbour chunk streams in.

**Runtime**

- `--straight-to-game --quit-after=30` (3 runs): `world_hash=6372495951065888771`,
  `faces=166074`, `faces_hash=6977993294663025454`, `meshed=392`, `loaded=392`,
  `queued=0`; two byte-identical `--fog=0` vs `--fog=0.0018` captures proved the
  render path is deterministic.
- **Post-fix**: the same smoke run and the radius-4 spawn capture
  (`fix-spawn.png`) still report `world_hash=6372495951065888771`, `faces=166074`
  and `faces_hash=6977993294663025454` — the winding fix changed only triangle order,
  not world data or face counts.
- Windowed captures: 1280×720, 224 draw calls, 201 684 primitives, 60 fps.
- Longer stability run: `--straight-to-game --quit-after=60` (60 s of play) exits 0 with
  0 bytes of stderr and no `ERROR`/`WARNING`/`SCRIPT ERROR` lines; ~120 fps headless.

**Visual — post-fix (images actually inspected)**

| Capture | What it shows |
| --- | --- |
| `results/godot/fix-spawn.png` | post-fix first-person spawn view: solid grass/path ground, intact trees, sand shore, ocean; no tearing or flipped faces |
| `results/godot/fix-aerial.png` | post-fix aerial view: continuous terrain, coastline and water with no holes |
| `results/godot/fix-water.png`, `fix-water-top.png` | post-fix water: transparent surface, seabed visible, sun glint; no independent defect |
| `results/godot/winding-test.png` | controlled two-quad render: only the correctly (reversed) wound quad survives `cull_back`, pinning the convention |
| `results/godot/fix-legacy-slice.png` | post-fix legacy `main.gd` slice (windowed `--capture-on-ready`): solid green/dirt/water blocks with correct shading, confirming the same fix in the compat entry point |

**Visual — pre-fix baseline captures (retained for comparison; the terrain views show the inverted-winding artifacts)**

| Capture | What it shows |
| --- | --- |
| `results/godot/look-spawn.png` | first-person spawn view: grass, sand terrace, trees, coast, blue sky |
| `results/godot/look-aerial.png` | aerial radius-6 view: lake, coastline, forest, no holes in the terrain |
| `results/godot/look-shore.png` | shore/underwater transparency, seabed visible through water |
| `results/godot/light-shore.png` + `light-shore-noshadow.png` | shadow control pair (dark ground under canopies disappears without shadows) |
| `results/godot/light-aerial.png`, `fogtest-*.png`, `light-aerial-nofog.png` | fog tuning series (table below) |
| `results/godot/diag-aerial.png`, `diag-shore.png`, `diag-water.png` | earlier HUD/tour captures from the previous session |
| `results/godot/godot-game-tour-0..3.png` | HUD, hotbar, targeting, tooltips |
| `results/godot/day-noon.png` (`--time=0.25`) | 12:00 Day — bright, washed-out-free daylight, HUD clock reads `12:00 Day` |
| `results/godot/day-dusk.png` (`--time=0.53`) | 18:43 Dusk — already deep twilight: dark blue sky, land lit only by the fill light |
| `results/godot/day-night.png` (`--time=0.75`) | 00:00 Night — moonlit blue-grey terrain, no pale horizon band, water dark blue |

Night capture means, from `tools/image_stats.py` (whole frame, spawn vantage):

| time | mean RGB | crushed (max channel ≤ 24) |
| --- | --- | --- |
| 0.25 noon | 100 121 118 | 0.0 % |
| 0.53 dusk | 13 22 30 | 42.1 % |
| 0.75 night | 11 19 27 | 48.2 % |

Both night values are dark but readable in the inspected image; the `dusk` sample at
0.53 is past the point where the twilight curve has already fallen (daylight ≈ 0.03),
so a true mid-twilight capture (`--time=0.50`) is still outstanding.

Lighting/fog work done in this session, with measurements from
`tools/image_stats.py` (mean RGB of the whole frame, aerial vantage):

| Setting | mean RGB | evidence file |
| --- | --- | --- |
| original (`fog_density 0.0032`, SSAO 1.6, sun 1.5) | 134 156 159 | `diag-aerial.png` |
| SSAO 0.85 / sun 1.22 / ambient 1.45, fog 0.0018 | 114 134 138 | `light-aerial.png` |
| fog 0.0014 | 108 127 131 | `fogtest-0.0014.png` |
| fog 0.0010 | 102 120 123 | `fogtest-0.0010.png` |
| fog 0.0006 | 93 111 113 | `fogtest-0.0006.png` |
| fog 0 (no fog) | 74 91 91 | `light-aerial-nofog.png` |

Final settings: exponential fog `0.0008`, SSAO radius 0.5 / intensity 0.85, sun energy
1.22 at noon — see `results/godot/look-*.png`. Ambient is sky-sourced during the day
(`ambient_light_sky_contribution = 1.0`), but the night sky is almost black, so the clock
fades the sky term down to 0.15 at night and mixes in `DayNight.NIGHT_AMBIENT`
(`#33436b`) — without that, night rendered as pitch black (mean RGB 6/8/15, 74 % of pixels
crushed); with it, night is mean 11/19/27 and readable in `day-night.png`.

Shadows were confirmed to be the dark patches in the earlier `diag-shore.png`
(identical capture with `--no-shadows` removed them): not a rendering defect.

## 7. Performance measurements (this machine, seed 17017)

- GPU: NVIDIA GeForce RTX 3080; CPU: Intel Core i7-10700K; 32 GB RAM; 1920×1080.
- Render radius 4 (392 chunks, 166 074 faces): 224 draw calls, 60 fps windowed.
- First fill: `generation_ms_total≈2 810 ms`, `mesh_ms_total≈2 190 ms`
  (fill 341 / emit 1 792 / assemble 55), `worst_mesh_ms≈15.6`, `queued=0`.
- Render radius 6 (565 chunks, 232 260 faces): still 60 fps in the capture run.
- Headless smoke run (no rendering) reports ~119 fps — not a rendering measurement.

## 8. Known defects, limitations, blockers

**Resolved in this session (was the top blocker; fixed in `c22d056`)**

- **Inverted triangle winding** — the user-reported WASD movement failure *and* the
  rendering defects had one root cause. The mesher emitted each quad wound opposite to
  Godot's front-face convention (Godot winds so the right-hand-rule normal points *into*
  the solid; verified against the engine's own `BoxMesh`).
  - *Severity*: critical — the game was effectively unplayable while the symptom looked
    like an input bug.
  - *Repro*: play the game (or run `run_integration.gd`); the player wedges into the
    ground instead of standing on it, and the terrain renders as grey streaks / torn and
    flipped triangles. The earlier scripted `--fly` captures never exercised the keyboard
    path, which is why the movement claim had gone unreproduced.
  - *Root cause*: with `cull_back`, every outward face was a back face, so outward
    surfaces were hidden and the collision trimesh reported inverted normals —
    `is_on_floor()` was always `false`, so WASD input reached the controller but the body
    never moved cleanly (mouse look still worked, which made it look like a movement bug).
  - *Fix*: reversed `QUAD_INDICES` from `[0,1,2,0,2,3]` to `[0,2,1,0,3,2]` in
    `chunk_mesher.gd`, and the same one-line fix in the legacy `main.gd` for consistency.
    UVs and normals are unchanged; only triangle order changed.
  - *Evidence*: `test_mesh_winding.gd` (unit) pins every solid + collision triangle to
    `BoxMesh`'s convention; `run_integration.gd` proves the player lands at `y=70.000`,
    reports `is_on_floor()` and moves with WASD; `winding-test.png` is a controlled
    two-quad render showing only the correctly wound quad surviving `cull_back`. Spawn
    capture `fix-spawn.png` is coherent and still reports `world_hash=6372495951065888771`.
    The legacy `main.gd` fix was verified twice: analytically (its own `FACE_CORNERS`
    wound all six faces back-facing before, all six front-facing after) and visually
    (`fix-legacy-slice.png`, windowed `--capture-on-ready`).
- **Water** — investigated; **no independent water defect**. Water uses `cull_disabled`,
  so it was never affected by the winding bug; its apparent “distortion” was the broken
  surrounding terrain. With the terrain fixed the water shows the intended transparency
  (seabed visible), a level-based surface and sun glint (`fix-water.png`,
  `fix-water-top.png`). Left unchanged.

**Open limitations (not regressions)**

- First fill takes ~2.9 s of generation + ~2.2 s of meshing before the world is ready
  (staged across frames, so the window stays responsive, but the loading screen is long).
- The world edge is visible at the horizon when the render distance is small; fog
  density is a compromise (too much fog washes the scene out, as measured above).
- `MILESTONES.md` is not present in this repository and the mission text says the
  shared scenario seed is `17015`, while `prototypes/m17/shared/scenario.json`
  contains `17017`. The shared fixture is authoritative and is what both the fixture
  tests and the game use; the discrepancy is recorded here rather than “fixed” by
  editing a contract that other work depends on.
- A second agent was editing the same project files during the session (it added
  `fixture_adapter.gd` and rewrote `main.gd`/`capture.gd`); re-run the tests after
  any unexpected file change.
- A true mid-twilight capture (`--time=0.50`) has not been taken; only the noon and night
  endpoints of the lighting curve have been inspected visually (both are covered by tests).
- Runtime validation of the fix is headless + offscreen capture only. No human played the
  game with a real keyboard/mouse in this session; the integration test drives the same
  `Input`/`_physics_process` path the keyboard uses, but a human play-through is still
  outstanding.

## 9. Resume

Read this file and `godot-roadmap.md`, then run the baseline commands at the end of this
section. The current baseline is **1447 unit + 257 integration assertions** (post-M19),
both exit 0 with 0 bytes of stderr. The M18 content pass (denser trees, boulders) changed
the generated world, so the spawn-region smoke is now `world_hash=7995773462820745781`,
`faces=170492`, `faces_hash=6834793821708419232`, `edits=0`, `meshed=392` at radius 4
(re-confirmed after M19). All hashes quoted earlier in this file are historical
(pre-M18 generation); only this one is current.

Phases A, B and C are complete and phase D is well under way. What is implemented and verified
is listed in `godot-roadmap.md`; the honest remaining gaps are:

- **Phase C**: weather / environmental variation.
- **Phase D**: player construction beyond single blocks (blueprints/paste), and the
  city-management foundation (settlement growth, resource economy with the player, guards and
  worked plots).  Raids, residents, tasks and settlement stores exist.
- **Crafting follow-ups** the roadmap still lists as done-with-limits: smelting is menu-driven
  (no timed furnace), the interface matches by ingredient multiset (the shaped *definitions* and
  `match_grid` are real and tested, but there is no drag-and-drop 3×3 grid), and there is no
  anvil/repair.
- **Known limitations per increment** are listed at the end of each section of this file; read
  those before deciding what to fix next — several are deliberate scoping decisions rather than
  defects.
- **Never verified by a human**: every runtime claim in this file comes from headless
  integration tests, scripted captures and inspected PNGs. A real keyboard/mouse play-through
  remains the single most valuable validation left.

Baseline sanity command set (copy/paste):

```powershell
cd C:\Users\Admin\Documents\Projects\VoxelWorld_oneshot
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd | Select-Object -Last 1
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game | Select-Object -Last 1
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=30 | Select-String M17_GAME_SUMMARY
```

Note for any new `class_name` script: the headless runner cannot see a new class until the
project's class cache is refreshed, so run this once after adding one (it is not a test change,
just a scan):

```powershell
& $godot --headless --path prototypes/m17/godot --import
```

## 10. Savepoint log

Every entry is a commit on `main` that was made only after the automated suite passed and
the listed evidence had been inspected. Nothing in the working tree was discarded.

| Commit | Content | Evidence at the time |
| --- | --- | --- |
| `e029c68` | Playable voxel game: generation, streaming, meshing, water, edits/persistence, HUD/hotbar, main + pause menu, capture harness, test suite, docs, assets | 271 assertions exit 0; deterministic `world_hash=6372495951065888771`; `look-*.png`, `diag-*.png` inspected |
| `fd9f7d2` | Day/night cycle: `core/day_night.gd`, clock-driven sun/sky/ambient/fog/water, `--time=` / `--time-rate=`, save `VERSION 2`, new test module, image-stats Pillow fix | 338 assertions exit 0, 0 bytes stderr; `day-noon.png` / `day-dusk.png` / `day-night.png` captured and inspected; post-commit smoke run still reports `world_hash=6372495951065888771` |
| `c22d056` | Fix inverted triangle winding: `QUAD_INDICES` reversed in `chunk_mesher.gd` + legacy `main.gd`; new unit test `test_mesh_winding.gd`; new runtime integration harness `run_integration.gd`; `fix-*.png` + `winding-test.png` evidence; `.gitignore` adds `*.log.err` | 346 unit + 17 integration assertions exit 0; `winding-test.png`, `fix-spawn.png`, `fix-aerial.png`, `fix-water*.png` inspected; post-fix smoke + radius-4 spawn capture still report `world_hash=6372495951065888771`, `faces=166074`, `faces_hash=6977993294663025454` |
| `23a8919` | Persistence regression test `test_persistence.gd` (SaveManager write/read/apply, validation, quarantine) added to the runner | 383 unit assertions exit 0, 0 bytes stderr; the test round-trips blocks/fluid/player/inventory/clock, refuses a wrong-seed save, loads a version-1 save, and quarantines bad saves without losing them |
| `4af42d6` | Crafting increment: `core/crafting.gd` (recipes, atomic `craft`, capacity), `game/crafting_panel.gd` (C-key overlay), `game.gd`/`project.godot` integration, `--open-crafting`, `world_gen.gd` clay-band fix, `test_crafting.gd` + clay-presence test, docs, `crafting-ui.png` | 435 unit + 17 integration assertions exit 0, 0 bytes stderr; `crafting-ui.png` inspected (panel lists all five recipes, affordable rows bright, clay row dimmed); post-fix capture `world_hash=441363152919021799`, `faces=166074`; independent Builder→Tester→Reviewer round, Reviewer verdict PASS |
| `5e04d03` | Health, survival feedback, death/respawn: `core/health.gd`, `core/survival.gd`, player fall tracking/camera shake, HUD health/breath/hurt flash, death screen, game integration, SaveManager v3, tests, captures | 552 unit + 29 integration assertions exit 0, 0 bytes stderr; integration exercises lethal death and Respawn button signal; `health-hud.png` and `death-screen.png` inspected; 30-second submerged runtime smoke exited 0 at 60 fps (breath 0, health 5.43); independent Reviewer verdict PASS |
| `b993af4` | Passive creatures: `core/passive_creatures.gd` (node-free model, live-ground checks), `game/passive_creature.gd` (primitive boar), bounded spawner + LMB creature attack/drop in `game.gd`/`voxel_player.gd`, `test_creatures.gd` + integration, `tools/hud_probe.py`, `passive-creature.png` | 587 unit + 35 integration assertions exit 0, 0 bytes stderr; integration drives real spawn/wander/ray-attack/kill/drop; `passive-creature.png` inspected (boar + "Boar hurt (2/3)"); Reviewer initially FAIL on generator-vs-live ground, fixed with `supports_standing`/`wander_destination` + 8 asserting tests, then PASS |

The winding savepoint is **complete and validated for the behaviour it introduced**; the
three user-reported items (movement, rendering, water) are resolved. Day/night from the
previous savepoint is unchanged. The persistence test closes the Priority-4 reliability gap
where `SaveManager` had no coverage. Unfinished work is listed in §8 and the resume section
§9; it is *not* part of these savepoints.

## 11. Session plan (2026-10-16, autonomous mission run)

This run follows the repository agent architecture (Plan/orchestrator → Builder → Tester →
Reviewer). The Plan agent does not implement; implementation is delegated to the Builder,
independent runtime verification to the Tester, and independent review to the Reviewer.

Baseline re-measured at the start of this run (unchanged): unit suite
`M17_TESTS_PASS 383 assertions` exit 0; integration
`M17_INTEGRATION_PASS 17 assertions` exit 0. Godot
`4.7.2.stable.mono.official.ed1daf0bf`.

Planned increments (Phase B/C of the mission §8), each Builder → Tester → Reviewer, each
ending in a Git savepoint and a roadmap/progress update:

1. **Crafting** — done, `4af42d6` (`[x]` recipes + `[x]` interface).
2. **Health & damage** — done, `5e04d03` (health/damage/feedback/death/respawn).
3. **Living world** — passive creatures done, `b993af4`; hostile creatures, combat exchange
   and loot are the next increment (Phase C).

Each increment must keep the existing suites green, add new automated tests, and produce a
runtime capture that is *inspected* (not merely generated) before the increment is called
done.

## 12. Crafting increment (2026-10-16)

Phase B crafting: the recipe data model, the crafting interface and their tests, plus a
world-generation repair required to make one recipe reachable.

**Changed**

- New `scripts/core/crafting.gd` (`class_name Crafting`): a fixed, ordered five-recipe
  list (Oak Log → 4 Planks; 4 Planks → Crafting Table; Stone → Cobblestone;
  2 Sand → Glass; 4 Clay → Brick) plus `recipes()`, `can_craft()`, `craft()`,
  `available_recipes()` and `label()`. Only blocks that exist in `BlockDB`.
  - `craft()` is atomic: it validates the recipe, checks the ingredients and checks that
    the output fits *after* the inputs would be consumed (computed on a scratch copy of
    the slot counts, never the live inventory) — all before touching the inventory.
    Consuming the inputs is therefore allowed to free the slot the output needs.
  - `validate()` rejects an `AIR` output, so an AIR-output recipe can never consume inputs
    and then fail. `available_recipes()` returns deep copies, so callers cannot corrupt the
    canonical recipe list.
- New `scripts/game/crafting_panel.gd` (`class_name CraftingPanel extends Control`): a
  centred overlay listing the recipes with a per-row enabled/disabled state and a Craft
  button. It reads the `Inventory` and `Crafting` data only and never mutates the world;
  it emits `crafted(result)`.
- `game.gd`: builds the panel on a layer-15 `CanvasLayer` (between the HUD at 10 and the
  menu at 20), toggles it with the new `open_crafting` (C) action while `PLAYING` (mouse
  `VISIBLE` and `player.can_interact` disabled while open; `CAPTURED` and interaction
  restored when closed), flashes the outcome with `hud.flash`, and adds `--open-crafting`.
  Escape closes the panel before it would pause; pausing also closes it.
- `project.godot`: new `open_crafting` action (`physical_keycode` 67 = C).
- `game_hud.gd`: control hint now mentions "C craft".
- `core/world_gen.gd`: the clay band in submerged columns was unreachable — the
  `elif underwater and world_y >= height - 2` clause sat after the `elif world_y >= height - 3`
  fallback, which captured every cell it could match. Reordered so the clay clause precedes
  the fallback; clay now generates as a thin subsurface band (~1 in 5 of the two cells below
  an underwater surface). This is what makes the `4 Clay → 1 Brick` recipe obtainable, and it
  changes world content (see the new hash below). Bedrock, caves, ores and surface material
  are untouched.
- New `scripts/tests/test_crafting.gd`, registered in `run_tests.gd`; `test_generation.gd`
  gained a clay-presence assertion.

**Tests / evidence**

- Unit: `M17_TESTS_PASS 435 assertions` (383 baseline + 52 new), exit 0, 0 bytes stderr.
  The crafting module covers: the fixed/ordered/valid recipe list; `can_craft` true/false;
  exact input consumption and output addition; insufficient ingredients rejected with the
  inventory byte-identical; a genuinely-full inventory rejected atomically (input slot
  retains items after consumption); the freed-slot case that now succeeds; merging into an
  existing stack; an `AIR` output rejected without consuming; unknown/malformed recipes
  rejected; and `available_recipes` returning copies. `test_generation.gd` finds clay in
  underwater columns (13 cells in the scan).
- Integration: `M17_INTEGRATION_PASS 17 assertions`, exit 0, 0 bytes stderr.
- Runtime (temporary windowed harness, since removed, re-run after the fixes): 17/17
  assertions — the C action opens and closes the panel, mouse mode and `player.can_interact`
  follow it, a real Craft button press consumes the inputs and adds the output, Escape closes
  the panel without pausing, and pausing closes it. (A headless run cannot confirm the mouse
  mode: Godot's headless DisplayServer always reports `mouse_mode = VISIBLE`; the same probe
  returns `CAPTURED` in a windowed run.)
- Capture `results/godot/crafting-ui.png` (1280×720; `--capture --open-crafting
  --capture-name=crafting-ui.png --settle=14`) inspected: the centred dark "CRAFTING" panel
  lists all five recipes, the four affordable rows bright and "4 Clay → 1 Brick" dimmed (the
  starter kit has no Clay — clay must be mined, and now generates), with the hint line, drawn
  above the hotbar. The run exits 0 with 0 bytes of stderr and no `ERROR`/`SCRIPT ERROR` lines.
  With the clay fix the world content changed: `world_hash=441363152919021799` (was
  `6372495951065888771`); `faces=166074` and `faces_hash=6977993294663025454` are unchanged,
  because clay swaps one opaque subsurface block for another and so adds no visible faces.

**Savepoint**: `4af42d6` — "M17 Godot: crafting recipes, interface, tests and the clay
generation fix".

## M17 Phase B increment: health, survival feedback, death/respawn (2026-10-16)

**Implemented in the current working tree; no commit created (orchestrator owns commits).**
This increment is limited to health/damage, environmental feedback and death/respawn.
No creatures, combat exchange, or loot were added. The production Ursina implementation
and the root milestone/architecture instructions were not changed.

- Added node-free `Health` and pure `Survival` helpers. Health clamps damage/healing,
  emits changed/damaged/died signals, is inert after death until revive, and validates
  dictionary state. Survival rules use a 3-block safe fall, 1 damage per excess block,
  15-second breath (1/s drain, 4/s refill), drowning damage at zero, and regeneration
  after 8 seconds at 0.5 health/s.
- The player reports landed fall distance; game owns damage application, half-second
  impact invulnerability, regeneration, drowning, HUD health/breath and hurt feedback.
  Death freezes play and presents Respawn; respawn restores full health/breath at the
  generated valid spawn. Camera shake is bounded and reversible.
- SaveManager is VERSION 3, serializes health/breath, validates them and retains v1/v2
  compatibility, seed checks and invalid-save quarantine. Health/survival tests and
  persistence round-trip/legacy cases are registered.

**Verification actually run** (Godot 4.7.2 stable Mono, Windows):

- Unit: `--headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd`
  via redirected `Start-Process`; exit **0**, `M17_TESTS_PASS 540 assertions`, stderr
  0 bytes. This includes health, survival and persistence cases.
- Integration: same project/script with `-- --straight-to-game`; exit **0**,
  `M17_INTEGRATION_PASS 29 assertions`, stderr 0 bytes. The new assertions drive lethal
  health through the real game death path and emit the actual Respawn button's `pressed`
  signal, then verify DEAD/PLAYING states, disabled/enabled player physics and interaction,
  full health/breath, hidden overlay and valid grounded spawn. A simulated mouse click was
  not performed. (Without the documented user
  argument the harness stayed in MENU and exited 2; rerunning with the required flag
  passed.)
- Windowed capture with `--capture --health=14 --submerge --capture-name=health-hud.png
  --settle=8`: exit 0; 1280x720 `results/godot/health-hud.png`, summary HEALTH 14/20 and
  breath 8/15 (7.99 at capture); inspected image shows both meters in the submerged view.
- Windowed capture with `--capture --hurt=30 --capture-name=death-screen.png --settle=8`:
  exit 0; `M17_GAME_DEATH cause=startup`, summary state DEAD and health 0/20, 1280x720
  `results/godot/death-screen.png`; inspected image shows You Died, cause and Respawn.
  The death screenshot still has the capture countdown in the upper-left. The automated
  integration exercises the Respawn button signal; a physical mouse click was not tested.
- World-generation regression summary remains `world_hash=441363152919021799`,
  `faces=166074` from existing baseline capture data; no new performance claim is made.

Files for this increment are the Godot core/game/test scripts and captures plus this
roadmap/progress record. Capture artifacts are evidence of rendered output and were
visually inspected here; this does not claim an interactive desktop play session.
Reviewer initially found two issues: v3 breath bounds were not validated and
`Health.set_health(0)` omitted the death signal. Both were fixed and independently reviewed
PASS. v3 now rejects out-of-range breath before applying any live state; legacy v1/v2 keep
the missing-breath sentinel. Tests cover invalid values/quarantine/no mutation and
set-health death exactly once. Latest direct reruns: unit `M17_TESTS_PASS 552 assertions`
exit 0; integration `M17_INTEGRATION_PASS 29 assertions` exit 0; both stderr 0 bytes.
**Savepoint**: `5e04d03` — "M17 Godot: health, survival feedback, death and respawn".

## M17 Phase C increment: passive creatures (2026-10-16)

Implemented one modest passive-creature gameplay loop in the Godot project. This was a
working-tree increment only: the orchestrator owns commits; no files were staged or
committed. Existing unrelated dirty files were preserved.

**Implementation**

- Added `scripts/core/passive_creatures.gd`, a node-free boar state model with seed-based
  spawn candidate ordering, stable IDs, 3 HP, 1.2-unit/s bounded wander steps, one-use
  Oak Log drop rules, and bounded pruning. Spawn selection is capped at 6, searches no
  farther than 38 blocks, uses only loaded chunks, rejects ocean/water and occupied foot
  or head cells, and avoids duplicate world columns. Living creatures outside 54 blocks
  are despawned; at most 4 model entries are pruned per game frame.
- Added `scripts/game/passive_creature.gd`: a small stylized boar built from primitive
  meshes, with a capsule collider, voxel-surface-following wander targets, water/solid-cell
  avoidance, subtle bob animation, health and damage response. The game owns its bounded
  scene population (one node per creature, never per voxel).
- `game.gd` schedules spawns once per second and updates the model from moving positions.
  Existing left-click block break is unchanged unless a passive creature is hit first by
  the physics ray and is closer than the voxel DDA block hit. Each click removes one HP;
  three hits kill this species and its one Oak Log enters the existing inventory once.
  Full inventory keeps the kill and reports the uncollected item in HUD feedback.
- Creature states are deliberately transient, not saved in VERSION 4. Saves preserve the
  world seed, player state and inventory; on load, living animals are regenerated from the
  seeded terrain/player neighborhood with a fresh bounded population. This avoids saving
  short-lived wander offsets; the successful death item is credited directly to the
  already-persisted inventory. Save VERSION 3 and v1-v3 compatibility are unchanged.
- Added a `--creature-feedback-capture` diagnostic option to position one legal animal in
  front of the player, apply one hit and hold the usual hurt message for screenshot
  inspection. This is capture-only; normal play uses the regular attack path.
- Added `test_creatures.gd` and integration coverage for deterministic spawn state, cap,
  radius, valid solid land/headroom, damage/death/drop-once, bounded wander/prune,
  population cap and real player-ray attack plus inventory pickup.

**Validation actually performed (Windows, Godot 4.7.2 stable Mono; RTX 3080)**

- TDD RED: before `PassiveCreatures` existed, suite failed compiling the new creature test
  with the expected undeclared-model error. A subsequent execution caught test fixture
  chunks loaded at y=0 while land cells were in chunk y=4; corrected the fixture.
- Unit command (redirected `Start-Process`):
  `--headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd`;
  final exit 0, `M17_TESTS_PASS 579 assertions`, stderr 0 bytes.
- Integration command (redirected `Start-Process`):
  `--headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game`;
  exit 0, `M17_INTEGRATION_PASS 35 assertions`, stderr 0 bytes. Includes live capped spawn,
  ray target prioritization, three attacks, and exactly one inventory item.
- Windowed capture command:
  `--path prototypes/m17/godot -- --capture --capture-name=passive-creature.png
  --creature-feedback-capture --settle=14 --time-rate=0`; exit 0, stderr 0 bytes,
  `results/godot/passive-creature.png` (1280x720) inspected. Image shows the primitive
  boar in the forest, health/hotbar HUD, and centered `Boar hurt (2/3)` feedback. Capture
  summary: seed 17017, world hash 441363152919021799, 392 loaded/meshed chunks, 166074
  faces, generation 2857 ms / mesh build 2209 ms for the whole streamed region; FPS sample
  60. These environment-specific capture values are not a creature-only
  benchmark; no long-exploration performance claim is made.

**Limitations / not implemented**: hostile mobs, broad combat, animal products beyond the
Oak Log utility drop, saved creature health/positions, and multiple species remain out of
scope. Creatures use primitive geometry and grid-column movement rather than navmesh. Manual
physical mouse attack was not performed; the windowed capture verified rendered appearance
and feedback, while automated integration exercised the real player ray-target/break path.

Savepoint: `b993af4` — "M17 Godot: passive creatures (spawning, wander, attack drops)";
the prior savepoint was `5e04d03`.

## M17 Phase C follow-up: passive creatures use live ground (2026-10-16, reviewer fix)

The reviewer passed the passive-creature increment except for one concrete defect and
required exactly that defect to be fixed (working-tree only; the orchestrator owns
commits, so nothing was staged or committed).

**Defect (as reported and confirmed in source)**

`scripts/core/passive_creatures.gd::spawn_candidates` and
`scripts/game/passive_creature.gd::_physics_process` decided "is there ground here?" from
the **procedural generator** (`world.generator.height_at(...)` and
`world.generator._surface_block(...)`), not from the live voxel world. When the player
mined the ground block, the generator still reported a solid surface there, so a creature
could spawn or wander over the resulting hole -- violating the milestone requirement to
"use valid ground and do not step into air".

**Fix (smallest change)**

- `scripts/core/passive_creatures.gd`: new node-free helper
  `supports_standing(world, x, z, height)` -- true only when the **live** world has the
  ground cell `Vector3i(x, height, z)` loaded and `BlockDB.is_solid(block)` and
  `not BlockDB.is_liquid(block)`, and the foot `(x, height+1, z)` and head
  `(x, height+2, z)` cells are loaded air. New pure method
  `wander_destination(world, position, target, delta)` returns the next world position for
  one `wander_step`, or the unchanged `position` when the destination column has no live
  supported ground. `spawn_candidates` keeps its height/sea-level guard and now rejects a
  column unless `supports_standing(...)` is true, so player edits (not just generated base
  terrain) are respected.
- `scripts/game/passive_creature.gd::_physics_process`: the node no longer reads the
  generator surface at all; it delegates the move to
  `MODEL.new(world.world_seed).wander_destination(world, global_position, _wander_target, delta)`
  and only advances when the returned destination differs. Deterministic IDs, the cap,
  spawn radius, despawn range, damage/drop semantics and the transient save policy are
  unchanged.

**TDD**

Tests were written first and watched to fail (`test-driven-development`):

- RED: with the tests in place but the fix absent, the suite exited **1** with
  `M17_ASSERT_FAIL a mined ground column is not chosen as a spawn candidate` plus
  `M17_TEST_FAILURE passive creatures follow live ground: the module reached its end (a
  script error aborted it)` (the not-yet-existing helper call). This is the exact defect:
  `spawn_candidates` still selected the column after its ground block was mined.
- GREEN: after the fix, the unit suite exits **0** (see below).

New assertions in `scripts/tests/test_creatures.gd` (8 added): the accepted candidate
stands on solid generated land; its ground block can be mined; a mined ground column is
**not** chosen as a spawn candidate; valid ground still yields spawn candidates after an
edit; a mined column no longer `supports_standing`; a wander step over a mined hole is
refused (unchanged position); restored ground supports standing again; a wander step over
valid ground still advances. The creature fixture now also loads the `y=3` chunk rows so
the ground cells under candidates are loaded and can be edited.

**Verification actually run (Windows, Godot 4.7.2 stable Mono)**

- Unit: `--headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd`
  (redirected `Start-Process`); exit **0**, `M17_TESTS_PASS 587 assertions`,
  stderr **0 bytes**. (Baseline before this follow-up was 579; the 8 new assertions are the
  only change.)
- Integration: `--headless --path prototypes/m17/godot --script
  res://scripts/tests/run_integration.gd -- --straight-to-game`; exit **0**,
  `M17_INTEGRATION_PASS 35 assertions`, stderr **0 bytes**. The integration run exercises
  the real creature node (spawn, physics wander, ray attack, kill/drop) with no script
  errors.

**Not changed / not fixed here**

- Pre-existing green horizontal striping is visible in the pre-increment
  `results/godot/fix-spawn.png` (written 11:05, before the creature increment at 15:57).
  It is therefore **not** caused by this increment and is not being fixed here.
- The capture-only diagnostic `--creature-feedback-capture` (`game.gd`) still picks its
  display column from the generator height; it is not gameplay spawning, the placed animal
  has physics disabled and never wanders, so it is out of scope for this defect and was
  left unchanged.
- A human interactive play-through of mining ground under a live creature was not
  performed; the rule is covered by the unit tests above plus the passing runtime
  integration.

This follow-up is included in savepoint `b993af4` (independently re-reviewed: PASS).

## M17 bug fix: missing faces and walk-through at Z chunk boundaries (2026-10-18)

A user-reported gameplay defect ("after breaking blocks some terrain faces disappear and the
player can sometimes walk through the terrain") was reproduced, traced to one line group, and
fixed in the current working tree. Nothing was committed (the orchestrator owns commits);
existing dirty files were preserved.

**Symptom.** Breaking a block that sits on a chunk's **-Z or +Z border** left the neighbouring
chunk's newly exposed face missing from both the rendered mesh and the collision trimesh. The
player could therefore see through the hole into the terrain behind it and pass through the
boundary wall. Interior edits and X/Y boundaries behaved correctly, which made the defect look
intermittent and orientation-dependent (digging `+Z`/`-Z`).

**Root cause (`scripts/core/voxel_world.gd::_flag_neighbours`).** The routine that dirties the
loaded neighbour chunk after an edit mapped the two Z directions backwards:

```gdscript
if local.z == 0:            neighbours.append(Vector3i.BACK)     # (0,0,1)  -- wrong
if local.z == SIZE - 1:     neighbours.append(Vector3i.FORWARD)  # (0,0,-1) -- wrong
```

Godot's `Vector3i.FORWARD` is `(0,0,-1)` and `BACK` is `(0,0,1)`, so the negative-Z face marked
the chunk *ahead* and the positive-Z face marked the chunk *behind*. The true neighbour was never
marked dirty, so its shared face stayed culled (it was still hiding the old block) and no
collision was generated there. The legacy `scripts/main.gd` equivalent uses the correct mapping
(`local_z == 0 -> FORWARD`, `== SIZE-1 -> BACK`), which is what the fix restores.

**Fix (one scope-limited change).** `_flag_neighbours` now maps the -Z border to
`coord + Vector3i(0, 0, -1)` and the +Z border to `coord + Vector3i(0, 0, 1)`, using explicit
vectors with a comment naming Godot's convention. Only invalidation changed; world data, face
counts and the deterministic fingerprint are untouched.

**Tests first (TDD).** New `scripts/tests/test_edit_rebuild.gd`, registered in `run_tests.gd`,
verifying resulting geometry and collision rather than internal flags:

- breaking a fully enclosed block exposes exactly its six neighbouring faces in the render mesh
  **and** collision, the authoritative voxel is gone, and untouched adjacent blocks keep their
  shared face culled (the 3x3x3 cube stays at 54 outer faces, plus a separate adjacent pair);
- all six chunk-boundary directions invalidate and rebuild the neighbour's exposed face
  (render + collision) -- this is the RED case for PZ/NZ;
- the real threaded `ChunkStreamer` rebuilds the +Z neighbour after a boundary edit and its live
  view mesh/collision contain the exposed face;
- two consecutive edits with the first rebuild genuinely in flight both survive and the final
  rendered geometry matches a fresh build from the authoritative voxels.

RED before the fix: exit **1**, **13** failing assertions (all PZ/NZ boundary cases plus the
streamed +Z and consecutive-edit cases). GREEN after the fix: exit **0**.

`scripts/tests/run_integration.gd` gained **17** assertions (35 -> 52) that boot the real game
scene, break an enclosed block and a +Z boundary block through the live threaded streamer, and
assert the live chunk mesh/collision match a fresh voxel build, that the neighbour gained the
exposed face, and that a physics ray through each hole is stopped at the remaining wall.

**Visual evidence (windowed, scripted, `--time-rate=0`).** A two-layer stone-brick wall was
built across the +Z boundary at `z=16` and a hole was broken in the front layer (chunk `z=0`),
so the hole's back faces belong to the neighbour chunk (`z=1`):

- before the fix `results/godot/m17-edit-bug-after.png`: the hole shows straight through the
  terrain (distant landscape visible, neighbour faces missing);
- after the fix `results/godot/m17-edit-fix-after.png`: the same break reveals a closed,
  recessed stone chamber (every neighbour face present);
- `m17-edit-{bug,fix}-before.png` are the intact-wall baselines.

**Verification actually run (Godot 4.7.2-stable mono, Windows, this machine).**

```powershell
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=25
```

- Unit: exit **0**, `M17_TESTS_PASS 701 assertions`, stderr **0 bytes** (was 615).
- Integration: exit **0**, `M17_INTEGRATION_PASS 52 assertions`, stderr **0 bytes** (was 35).
- Headless smoke: exit **0**, `world_hash=441363152919021799`, `faces=166074`,
  `faces_hash=6977993294663025454` -- unchanged, confirming the fix is invalidation-only.

**Remaining limitations.**

- A separate, transient race (an in-flight threaded mesh build captured before a chunk is
  unloaded/reloaded can briefly keep stale culling at the loaded-region edge) was investigated
  and left unchanged to keep this fix narrowly scoped; it resolves once the chunk is next
  invalidated. It is not the reported defect.
- The runtime/visual validation was scripted through the real scene (player-path physics rays
  and windowed captures); no human keyboard/mouse play-through was performed.
- `m17-edit-*` captures were produced by a temporary harness that was removed after the run;
  the PNGs are retained as evidence.

## M17 stabilization pass and hostile creatures (2026-10-18, continued)

Uncommitted working-tree increment; the previous session's renderer/threading work and all
other dirty files were preserved. No unrelated project file was touched.

### 1. Day/night cycle finished and visually verified

The previous session had left one capture outstanding (a true mid-twilight frame). The cycle
was exercised across the whole clock in the real game with the deterministic capture harness
(frozen clock, same seed 17017 and spawn vantage), and every frame was inspected:

| capture (`results/godot/`) | clock | observation |
| --- | --- | --- |
| `day-cycle-000.png` | 06:00 Dawn | cool dawn light, terrain fully readable |
| `day-cycle-025.png` | 12:00 Day | bright, correct textures, canopy shadows |
| `day-cycle-050.png` | 18:00 Dusk | sun on the horizon, cold sky, still day-lit |
| `day-cycle-055.png` | 19:12 Night | moonlit blue-grey terrain, readable |
| `day-cycle-075.png` | 00:00 Night | moonlit, no pale horizon band, water dark |
| `day-cycle-095.png` | 05:xx pre-dawn | night palette, slightly brighter fill |

`tools/image_stats.py` confirms the curve is monotonic and bounded (mean RGB `83 149 89` at
noon, `8-9 27-30 17` at night; crushed shadows 0 % at noon, ~21-25 % at night). The HUD clock
text matches `DayNight` (`06:00`, `12:00`, `18:00 Dusk`, `19:12 Night`, `00:00`). A live-clock
smoke (`--time-rate=120`, 10 s) advanced the clock in PLAYING (`time_of_day 0.28 → 0.3519`,
`14:27 Day`), so the running game drives the cycle, not just the frozen captures.

No defect was found: the sunset-to-night transition is quick (the twilight window is ~0.076 of
a day ≈ 69 s at the default 900 s cycle) because the sun-elevation curve is steep near the
horizon, and the existing tests pin the intended `daylight() = 0.5` at sunrise/sunset. It is a
tuning choice, not a bug, and was left unchanged.

### 2. Documented asynchronous chunk-rebuild race (FIXED)

The race left open in the previous pass was reproduced and fixed with tests first. When a chunk
with a mesh build in flight had its neighbour set change (a neighbour unloaded, loaded or
regenerated), the finished build was captured against the *old* border. `_apply_result` then saw
an unchanged `mesh_revision`, cleared `mesh_dirty`, and `_collect_mesh_batch` erased the queued
rebuild, so the chunk kept a mesh (and collision) that culled against a chunk that no longer
existed -- a hole at the edge of the loaded region until something else re-dirtied it.

Fix in `scripts/game/chunk_streamer.gd`:

- `_on_chunk_created` / `_on_chunk_removed` now call `mark_dirty()` on every loaded neighbour
  instead of only queueing it, so the neighbour's `mesh_revision` advances and any build already
  in flight for it is discarded as stale.
- `_collect_mesh_batch` only erases the coordinate from the queue when the attached result was
  current; a still-dirty coordinate stays queued and is rebuilt by the same frame's submit pass.

TDD: the new `test_edit_rebuild.gd` case `_test_pending_build_survives_neighbour_unload` starts a
build that culls against a neighbour, unloads that neighbour while the build is in flight, and
asserts the edited chunk is rebuilt with the newly exposed face in both the render mesh and the
collision. RED before the fix: exit 1, 3 failures (face count 11 vs 12, missing render face,
missing collision face). GREEN after: exit 0.

### 3. WASD reliability: the player moved while the game was paused (FIXED)

`_pause()` set `player.can_interact = false` but never stopped the player's physics, so the body
kept reading WASD and gravity behind the pause menu. Reproduced through the real controller:
30 physics frames of forward input while paused moved the body **8.67 units**. Fix:
`_pause()` now calls `player.set_physics_process(false)` and `_resume()` restores it (death and
respawn already managed this). Integration assertions added: the player does not move while
paused (0.000 units), pause disables physics, resume enables it.

### 4. Texture corruption: no remaining defect reproduced

The layer-sampling corruption fixed in the previous session is pinned by `test_textures.gd` and
by the inspected before/after captures. A fresh runtime check was performed: a close-up wall of
brick, glass, oak leaves, oak log, sand, stone, dirt and grass was rendered at noon with the HUD
hidden (`results/godot/stabilize-textures.png`). Every tile matches its source texture; glass is
transparent over the leaves behind it, leaves keep their cutout, no face samples a neighbouring
array layer. No new code change was needed and none is claimed.

### 5. FPS drops: measured, no regression; remaining hitch documented

The race fix does not regress frame times. `run_perf.gd` (windowed, seed 17017) before → after:

| scenario | p95 | p99 | 1 % low | stream-work frames |
| --- | --- | --- | --- | --- |
| settle | 17.16 → 17.20 ms | 21.90 → 21.44 ms | 34.7 → 31.5 fps | 402 → 404 |
| walk | 8.17 → 8.62 ms | 17.19 → 17.12 ms | 49.3 → 49.5 fps | 1450 → 1439 |

The remaining slow frames are the known, previously-documented ones: one ~49 ms first-PLAYING
frame (present in every baseline) and 23-26 ms walk/settle frames whose time is chunk
**generation** (~12-20 ms, still on the main thread) plus GPU first-use of newly attached
geometry. Meshing itself is already off-thread. Threaded generation remains the roadmap item;
no performance fix is claimed here.

### 6. Phase C increment: hostile creatures, melee combat and loot

One dark-dwelling hostile species ("grunt") with the same node-free-plus-node shape as the
passive boar:

- `scripts/core/hostile_creatures.gd` -- deterministic spawn on **live** ground (never on top of
  the player, 12-32 blocks away), a night-only gate (`dark` flag), chase decisions that stop at
  attack range and refuse mined/flooded ground, a pure attack cadence
  (`ATTACK_DAMAGE 2.0`, `ATTACK_INTERVAL 1.2 s`), 4 HP, one Coal drop and bounded pruning.
- `scripts/game/hostile_creature.gd` -- primitive dark humanoid with glowing eyes, a capsule
  collider on layer 2, voxel-following movement and `attacked_player` / `killed` signals.
- `game.gd` -- owns a transient night population (cap 4, spawn every 2 s while `clock.is_night()`
  or `--spawn-hostiles`), retires it a few per frame at dawn, routes contact damage through the
  existing `_apply_impact_damage` (invulnerability window + camera shake), and shares the
  existing LMB creature attack path. `--hostile-feedback-capture` renders a controlled grunt for
  evidence. Hostiles are deliberately not saved, exactly like the boars.
- `voxel_player.gd` -- the LMB creature ray now also recognizes `hostile_creature`.

Tests: new `test_hostiles.gd` (38 assertions: darkness gate, determinism, cap/distance, live
ground, chase bounds and hole refusal, attack cadence, damage/drop-once, bounded prune) and 8
new integration assertions (contact damage 20→18 through the real node, LMB targeting, four
player hits kill it, loot added, and the night clock spawning through the game's own spawner).

Visual evidence: `results/godot/hostile-creature.png` (windowed, `--time=0.75`,
`--hostile-feedback-capture`) shows the grunt in the forest at midnight with "Grunt hurt (3/4)".

### 7. Test-runner hardening

A module that fails to parse used to be returned by `load()` as a non-instantiable GDScript;
`(script as GDScript).new()` then aborted the whole runner and hung the suite until the watchdog.
`run_tests.gd` now checks `can_instantiate()` and reports a normal failure, so a broken module
can never hang the run. (Found while doing the hostile TDD RED step.)

### Verification actually run (Godot 4.7.2-stable mono, Windows)

- Unit: `M17_TESTS_PASS 745 assertions`, exit 0, stderr 0 bytes.
- Integration: `M17_INTEGRATION_PASS 60 assertions`, exit 0, stderr 0 bytes.
- Smoke: exit 0, `world_hash=441363152919021799`, `faces=166074`,
  `faces_hash=6977993294663025454` (unchanged).
- Perf: `perf-settle-racefix.json`, `perf-walk-racefix.json` written and compared above.

### Remaining limitations

- Chunk generation is still synchronous; the residual 23-26 ms streaming frames are documented
  and thread-generation is the next engineering step.
- Hostile combat is melee-only with one drop and one species; no weapons/durability, ranged
  attack, varied loot or daytime spawning. Weather, exploration incentives and Phase D
  (structures/NPCs) remain unchecked.
- Validation is scripted through the real scene (physics, rays and windowed captures); no human
  keyboard/mouse play-through was performed.

## M17 Phase B increment: configuration screen (2026-10-18, same session)

The roadmap's configuration item was finished: the render distance was CLI-only and nothing
exposed sensitivity or vsync.

- `scripts/core/game_settings.gd` (`class_name GameSettings`): render distance (2-8), mouse
  sensitivity (0.0005-0.006) and vsync, with clamping setters and a `to_dictionary` /
  `from_dictionary` round-trip. `from_dictionary` reads only well-typed keys (out-of-range
  numbers clamp, garbage is rejected without touching live values).
- `scripts/game/settings_panel.gd`: a centred overlay mirroring the crafting panel -- two
  sliders with numeric readouts plus a vsync toggle, emitting `setting_changed(key, value)`.
- `game.gd`: builds the panel on a layer-16 `CanvasLayer`, opens it with the new `O` action
  (or `--open-settings`), applies each change live and persists the whole set to
  `user://voxelworld_settings.cfg` (a `--render-distance` on the command line still wins for
  captures). Render-distance changes call the new
  `ChunkStreamer.apply_render_radius()`, which recomputes the wanted set, unloads what fell out
  of range and queues what came in. Opening settings closes crafting (and vice versa); Escape
  closes the panel before it would pause; pausing closes it.
- `project.godot` gains the `open_settings` action; the HUD hint mentions "O settings".

Tests: `test_settings.gd` (22 assertions: defaults, clamping, round-trip, clamped payloads,
garbage rejection leaving state untouched) and 8 real-scene integration assertions (open,
interaction disabled, render distance stored and applied to the streamer, sensitivity applied
to the player, vsync stored, close, restored distance re-applied).

Verification: unit `M17_TESTS_PASS 767 assertions` exit 0 stderr 0; integration
`M17_INTEGRATION_PASS 68 assertions` exit 0 stderr 0; smoke unchanged
(`world_hash=441363152919021799`). Windowed capture `results/godot/settings-ui.png`
(`--capture --open-settings`) inspected: the panel shows Render distance 4, Mouse sensitivity
0.0022, Vertical sync, with the persistence hint, over the paused-looking scene.

Limitations: no settings file migration/versioning yet; only the three listed settings are
exposed (shadows, fog and vertical radius remain CLI-only); verification is scripted, not a
human click-through.

## M17 Priority 4: hunger, eating and fed regeneration (2026-10-19)

The survival loop had health, drowning and fall damage, and food items existed with values,
but nothing consumed them.  Hunger is now a real system that makes the food chain meaningful.

### Rules (`scripts/core/survival.gd`)

- A 20-point hunger bar (like health) plus an accumulating **exhaustion** budget:
  every `EXHAUSTION_PER_HUNGER` (4.0) of exhaustion costs one hunger point, and activity
  builds it at `idle 0.004 / walk 0.02 / sprint 0.08` per second (`ACTIVITY_EXHAUSTION`).
  `hunger_step()` is a pure function of hunger, exhaustion, the current drain rate and delta.
- **Starvation**: at zero hunger the body loses `0.25` health per second, but never below a
  `STARVE_HEALTH_FLOOR` of 1, so starvation is a pressure, not a death trap.
- **Fed regeneration**: the existing heal-after-8-seconds rule now only applies when hunger is
  at least `MIN_REGEN_HUNGER` (6) and healing itself burns hunger
  (`REGEN_EXHAUSTION_PER_SECOND`).  That closes the loop: eating pays for health.  The
  `hunger`/`exhaustion` parameters default to "not tracked", so the previous behaviour is
  unchanged for callers that do not pass them.
- `food_effect()` returns the new hunger value, the health a food restores and whether the meal
  would be an improvement at all.

### Gameplay

- `game.gd` tracks `hunger`/`exhaustion`, derives the drain rate from what the player is doing
  (flying, standing, walking, sprinting) and runs the starvation and fed-regeneration steps in
  the same per-frame survival pass as drowning.
- **Eating is right-click** with food in hand (the same action as building), which is why the
  HUD hint now reads "RMB build/eat".  A full body refuses and says so instead of destroying
  the item; otherwise the item is consumed, hunger fills and the golden apple also heals.
  Eating works while looking at the sky (no block target needed).
- Respawning restores a full hunger bar; the death path is otherwise unchanged.
- HUD: a hunger bar beside the health bar (`HUNGER 7 / 20`), which turns red at zero.

### Persistence

- Save `VERSION 4` adds `hunger`.  Versions 1-3 still load: a missing/legacy hunger is the
  `-1` sentinel and the game keeps a full bar.  A current-version hunger outside
  `[0, Survival.MAX_HUNGER]` is rejected and the save quarantined, like breath.

### Tests and evidence

- `test_survival.gd` gained 32 assertions: the exhaustion budget and its per-activity rates,
  clamping, starvation damage and its health floor, `food_effect` (values, capping, waste,
  non-food) and fed regeneration (unfed bodies do not heal, healing burns hunger, and the
  no-hunger default keeps the old rule).
- `test_persistence.gd` covers the v4 hunger round-trip, the v1/v2/v3 legacy paths (each
  reporting no hunger) and quarantine for out-of-range hunger and for an inventory holding an
  unknown item id (the new atomic inventory validation).
- `run_integration.gd` gained **16 assertions** (109 -> 125): the HUD readout, eating at full
  hunger being refused without consuming, a real right-click eating an apple for four points,
  the golden apple refilling hunger and healing through the real `Health` model, an empty bar
  starving the player down to the floor without killing them, and a fed body regenerating
  again after the delay.
- Unit **1017 assertions**, exit 0, 0 bytes stderr.  Integration **125 assertions**, exit 0,
  0 bytes stderr.  Smoke unchanged (`world_hash=441363152919021799`, `faces=166074`,
  `faces_hash=6977993294663025454`) and now reports
  `"hunger":{"hunger":20.0,"exhaustion":0.09...}`.
- Windowed capture `hunger-hud.png` (`--capture --tools --hunger=7`) inspected: the health bar
  and the partially filled gold hunger bar side by side, reading `HUNGER 7 / 20`, with the
  tool hotbar below.

### Limitations

- Hunger only drops through the exhaustion budget and regenerating; there is no saturation
  layer, no "eat when nearly full" preference and no food-poisoning/raw-food concept.
- Starvation deliberately cannot kill, so the survival pressure is soft.
- Verification is scripted through the real scene plus the capture; no human play-through.

## M17 Phase B completion: the full inventory interface (2026-10-19)

The last unchecked Phase B item ("only the hotbar row is visible; no drag & drop").  The
inventory now has a real interface, and the item model gained the slot operations an interface
needs.

### Model (`scripts/game/inventory.gd`)

- `swap_slots(a, b)` exchanges item, count **and** durability.
- `move_slot(from, to)` tops up a matching stack (respecting the 64 cap, leaving the remainder
  behind) and otherwise swaps — the operation Godot's drag & drop drop handler performs.
- `take_stack(index)` / `put_stack(index, stack)` are the click-to-carry primitives.  `put_stack`
  returns exactly what the caller must still hold (the part that did not fit, or the stack a
  swap displaced) so a move can never duplicate or lose an item.
- `clear_slot(index)` is public.

### Interface (`scripts/game/inventory_panel.gd`, `inventory_slot.gd`, both new)

- `InventorySlot` draws one slot (icon, count, durability bar with the same green/amber/red
  thresholds as the HUD, slot number) and implements both interactions: a left click reports
  intent, and it is a real Godot drag source/target (`_get_drag_data`/`_can_drop_data`/
  `_drop_data`).  The dragged stack is drawn as a preview but stays in the model until the drop,
  so cancelling a drag cannot lose an item.
- `InventoryPanel` shows nine readable slots in a grid, a "carrying" slot with the picked-up
  stack, and an item facts pane for the focused slot: kind (block / material / food / tool),
  block hardness and whether it is solid, its drop, the tool class and tier it needs, stack cap,
  how many are held, tool tier/mining speed/attack/remaining durability and how many blocks that
  is good for, food value and healing, the recipe that makes it and every recipe that uses it
  (via `Crafting`).  Closing with a carried stack puts it back rather than dropping it.
- `focus_slot(index)` selects a slot (and mirrors it into the hotbar selection).

### Game integration

- New `open_inventory` action on **I**; `--open-inventory` for captures.  The three overlays
  (crafting, inventory, settings) are mutually exclusive — opening one closes the others — and
  Escape closes the inventory before it would pause.  The HUD hint now lists "I inventory".

### Tests and evidence

- `test_items.gd` gained slot-move coverage: swap (including durability), move into an empty
  slot, merge with a remainder, swap-on-different-item, tools never merging, `take_stack` on
  empty/bad indices, `put_stack` into an empty slot, over the cap (overflow returned), onto a
  full matching stack, and the swap returning the displaced stack.
- `run_integration.gd` gained **28 assertions** (125 -> 153): the panel opens and takes the
  mouse, shows every slot, a stack is picked up / refused twice / dropped through the panel's
  own handlers with the count conserved, the drag & drop drop handler swaps slots, a tool keeps
  its durability through a move, the details pane names the selected item and reports its
  durability, mining speed and recipe uses, and closing with a carried stack puts it back.
- Unit **1062 assertions**, integration **153 assertions**, both exit 0 with 0 bytes stderr.
  Smoke unchanged (`world_hash=441363152919021799`, `faces_hash=6977993294663025454`).
- Windowed capture `inventory-panel.png` (`--capture --tools --open-inventory`) inspected: the
  nine slots with icons, counts and durability bars, the selected slot highlighted, the
  carrying row, and the facts pane reading "Wooden Pickaxe / Wooden tool (Pickaxe) / Stack: 1 /
  Held: 1 / Tool tier: Wooden / Mining speed: 2.0x / Attack: 2 / Durability: 20 / 60 / Blocks
  left: about 20 / Made by: 3 Planks + 2 Stick → 1 Wooden Pickaxe · Crafting Table".

### Limitations

- There is one nine-slot row, so there is no second page or overflow area (the fixed hotbar is
  the whole inventory by design); stack reordering is the interface's main job.
- Verification is scripted; the drag & drop code path is exercised through the same
  `move_slot` call the drop handler makes, not by synthesising OS-level mouse drags.

## M17 Phase D foundation: procedural structures / points of interest (2026-10-19)

The first Phase D system. Structures are authored as data, placed deterministically as part of
generation, and written across chunk boundaries without any runtime bookkeeping.

### Definitions (`scripts/core/structure_db.gd`, new)

- A structure is an ASCII layer map: `{"dy": 1, "key": {"P": PLANKS}, "rows": ["PGP", ...]}`,
  where row 0 is the -Z edge, each character is one +X step, `.` leaves the generated block
  alone (so a building can sit on a hillside without carving), `_` forces air and any other
  character must appear in the layer's `key`. `dy` is the height above the anchor and may be
  negative (the ore outcrop digs into the ground).
- `footprint()`, `symbol_block()`, `allows_biome()` and a strict `validate()` (reserved symbols,
  unknown blocks/biomes, mismatched keys, footprints over 8x8, negative siting limits).
- Five structures, all built from blocks the game already had:
  - **Abandoned Hut** — planks, glass windows, a log roof, and a crafting table plus furnace
    inside as the reward.
  - **Campsite** — a cobblestone platform, four log posts, a crafting table and a furnace.
  - **Ruined Watchtower** — a broken stone-brick/mossy ring; a landmark with a view.
  - **Desert Well** — a sandstone rim with a water source (a reliable drink stop).
  - **Ore Outcrop** — visible coal and iron with more below, gated behind a pickaxe by the
    existing harvest rules.

### Placement (`scripts/core/world_gen.gd`)

- One structure per 96-block "region": a hash roll picks whether the region has one (62 %), a
  hash offset picks the anchor inside the region (kept 8 blocks from the edge so footprints
  cannot overlap), and the catalogue is tried in a hash-chosen order, so a kind whose biome or
  slope does not fit is replaced by another kind instead of leaving the region empty.
- Siting is a pure function of the seed and the world columns: the biome must be allowed, the
  height spread over the footprint must be within the structure's `max_slope`, and the base must
  be at least `min_floor_above_sea` above the sea. The anchor height is the highest footprint
  column + 1, so nothing floats.
- `generate_chunk` writes the part of every placed structure whose footprint reaches into the
  chunk, for anchor regions up to `max_extent` away. A chunk therefore never depends on its
  neighbour being generated first, chunks can be generated in any order or on either thread, and
  the whole thing stays a pure function of the seed. Bedrock is never overwritten, and the well's
  water goes into the fluid arrays like generated water does.
- `StructureDB` definitions are stripped of any knowledge of the world, so the same data can
  later feed a structure editor or a settlement planner.

### Diagnostics and evidence

- `--find-structure=<id|any>` teleports the player above the nearest placement (searching
  expanding region rings) and prints `M17_STRUCTURE_FOUND id=… x=… y=… z=… biome=…`, so a
  capture can inspect a structure without a long walk.
- Windowed captures inspected: `structure-hut.png` (a plank-and-glass hut with its log roof on a
  grassy slope, at x=44 z=-172) and `structure-tower.png` (a broken stone-brick/mossy watchtower
  in a snowy pine forest, at x=-116 z=62).

### Tests

- New `scripts/tests/test_structures.gd` (43 assertions, bounded scans so the suite stays at
  ~17 s): definition validity and every rejection case, footprint measurement (including the
  outcrop's three layers and the 8x8 limit), the reserved-symbol contract, placement
  determinism across calls and seeds, region maths for negative coordinates, siting (biome,
  slope, sea level, "sits on the highest column") on every placement in a bounded scan,
  **cross-chunk completeness** (every block of six placements present at its world position,
  with at least one block on a chunk border), bedrock preservation and the outcrop's real ore.
- Unit **1105 assertions**, integration **153 assertions**, both exit 0 with 0 bytes stderr.
- Smoke: `world_hash=441363152919021799`, `faces=166074`, `faces_hash=6977993294663025454`
  unchanged — the nearest structure is outside the 4-chunk streamed spawn region, so the spawn
  area is byte-identical. `generation_worker_ms` was 2810 ms versus 2799 ms before the change
  (+0.4 %, i.e. the siting tests are not a measurable cost at radius 4).
- Existing generation tests still pass unchanged (surface materials, water, clay, trees,
  decorations, biome variety), which is why siting rejects slopes and water columns.

### Limitations

- Only five kinds, all surface structures; there are no dungeons, villages or interiors with
  loot containers (there is no container block yet).
- Structures do not claim or clear trees outside their own cells, so a forest can crowd a ruin
  (visible in the tower capture).
- Placement is per-region with no spacing rule beyond the region size, so two structures can be
  as close as ~90 blocks; there is no "village" grouping yet.
- No runtime evidence of a player *walking* to a structure: the captures teleport to one.

## M17 Phase D: settlements and their residents (2026-10-19)

Structures that people live in (huts and campsites) now have residents with a job: they gather
resources near the settlement, carry them home to a shared store, and their identity and state
persist across saves.  This is the NPC foundation plus its first integrated task.

### Settlements (`scripts/core/settlement.gd`, new)

- A settlement is **derived**, not stored: it exists wherever the generator placed a hut or a
  campsite, so its id (`settlement-<x>-<z>`), name (a deterministic "Oakrest"/"Coldwater" pair)
  and anchor are pure functions of the seed and the structure.  The same world always has the
  same settlements from any direction.
- `nearby(world, center, radius, limit)` scans only the regions that radius can reach, sorts by
  distance and caps the result, so asking from anywhere is cheap.  `LEASH` (24 blocks) is the
  radius a resident may not leave.

### Residents (`scripts/core/npc.gd`, new)

- A resident is a plain dictionary: id, name, role (woodcutter or miner), task, position, home,
  target block, work progress, what it is carrying, health, and lifetime counters.  Everything
  is a pure function of the seed and the settlement, so a world always has the same people with
  the same names and jobs.
- The task loop is `SEEK → WALK → WORK → RETURN`: a woodcutter looks for exposed logs and a
  miner for exposed stone and ore within 10 blocks of home, walks to the block, works it for
  3.5 s, then carries it home — and hands the whole load to the settlement store at 6 items.
- **Bounded by construction**: only loaded chunks are considered (so a resident never edits a
  chunk the player has not streamed in), only *exposed* blocks (so it never tunnels through
  rock), only within `GATHER_RADIUS` of home, at most `SEARCH_BUDGET` cells per search, with a
  1.5 s retry when there is no work, and never more than `REACH_HEIGHT` (3) above or below its
  feet.  A resident beyond the leash heads home.
- Mining goes through the same `world.set_block` path the player uses, so a resident's work is a
  real world edit that the meshes, collision, saves and the fingerprint all see.

### The node and the game

- `scripts/game/npc_node.gd`: a primitive villager (green tunic for a woodcutter, blue for a
  miner) with a capsule collider on the interaction layer, gravity and collision so it walks the
  terrain, a work bob, and hit reactions.  It is in the `npc` group, so the player's LMB ray
  targets it like a creature, and killing one drops everything it was carrying into the
  inventory.
- `game.gd` derives the settlements near the player every 2 s, spawns a state per resident
  (capped), steps only the residents within `ACTIVE_RADIUS` (96 blocks), retires nodes that walk
  out of range while **keeping their state**, reports deliveries on the HUD, shows the resident
  under the crosshair in the readout ("Neil the Woodcutter — working (1 Oak Log)"), and keeps
  each body on the ground: the model moves in x/z, the game resolves the ground and pulls a
  resident that has fallen (or been dug out from under) more than 3 blocks back home.
- Capture diagnostics: `--follow-resident` keeps the camera on the nearest live resident, so a
  screenshot shows somebody actually working.

### Persistence

- Save `VERSION 5` adds `npcs`: the settlement stores (as `[item_id, count]` rows, because JSON
  turns integer keys into strings) and every resident's serialised state.  Versions 1-4 still
  load with no residents.  `_apply_npcs` restores the stores and the residents and drops
  anything unreadable (a bad payload is quarantined by the existing save validation), and a
  restored resident starts looking for work rather than resuming a stale target.

### Tests and evidence

- New `scripts/tests/test_npcs.gd` (73 assertions): settlement derivation and determinism, names,
  `nearby` radius/limit/sorting, resident rosters and ids, the full work loop on a controlled
  plot (find a log, walk to it, work it, carry it, deliver a full load, store accounting), the
  miner's stone→cobblestone drop, the leash, "no work in an unloaded region", bounded carrying,
  dead residents doing nothing, damage and death drops, and serialisation (round-trip, the
  no-target sentinel, and every rejection case).
- `test_persistence.gd` covers the v5 payload (stores and residents survive a write/read/apply),
  the legacy paths (v1-v4 report no residents) and quarantine for a malformed `npcs` payload.
- `run_integration.gd` gained **21 assertions** (153 -> 174): settlements are derived from the
  world, a resident gets a scene node in the `npc` group, the resident gathers a block through
  the game's own update loop and carries it home, the player's attack ray targets it, the
  readout names it and its role, killing it drops its load, and the store, names and resident
  state survive `_npcs_to_dictionary` → `_apply_npcs`.
- Unit **1185 assertions**, integration **174 assertions**, both exit 0 with **0 bytes stderr**
  (the residents' name plates started as `Label3D`s, which leaked font/text RIDs at exit in this
  engine build; role-coloured tunics plus the readout replaced them).  Smoke unchanged:
  `world_hash=441363152919021799`, `faces=166074`, `edits=0` — the nearest settlement is outside
  the streamed spawn region, so no resident acts during a smoke run.
- Windowed captures inspected: `resident-working.png` (a green-tunic woodcutter standing on its
  campsite by the shore) and `settlement-hut.png` / `settlement-campsite.png` (settlements with
  the readout naming the resident under the crosshair).

### Limitations

- Two roles only (woodcutter, miner) and no construction, farming, trading or guard behaviour;
  there are no raids yet.
- Settlement stores accumulate but the player cannot open or withdraw from them, and residents
  do not consume anything.
- A resident that falls is teleported home rather than learning to avoid the edge; there is no
  pathfinding around obstacles (a stuck resident just re-seeks).
- The "settlement" is the structure's own footprint: there are no plots, buildings or layout
  generation, and residents do not build.
- Verification is scripted (headless integration + windowed captures); no human play-through.

## M17 Phase D: night raids on settlements (2026-10-19)

The threat that gives the survival loop its point: every other night the raiders come for a
settlement near the player, the residents fight back, and the player can stand with them.

### Schedule (`scripts/core/raid.gd`, new)

- Pure, deterministic decisions: `is_raid_day(day_index)` (every `RAID_PERIOD_DAYS`), 
  `group_size_for_night()` (2-4, from the seed, the day and the settlement id),
  `spawn_offset()` (a ring 22-27 blocks out around the anchor, one point per raider),
  `raider_id()` and `should_start()`.  Nothing here touches the world or the scene tree, so the
  whole raid can be reasoned about and tested.
- `DayNight` gained a `day_index` that only advances when the clock wraps midnight (a forced
  `set_time` is not "time passing"), and it is **saved**: the day counter decides when raids
  happen, so an older save without one simply starts its calendar again.

### The fight

- Raiders are the existing grunt node aimed at a *resident* instead of the player, so hostile
  behaviour, movement, contact damage and loot all come from the code the player already faces.
  A raider that kills its target retargets the next living resident, and falls back to the
  player when a settlement has no one left.
- Residents gained `Task.DEFEND` and an optional `threats` argument on the model's step: a
  resident with a raider inside `DEFEND_RADIUS` (wider than the spawn ring, so the settlement
  reacts as the raid starts) walks at it and strikes for `DEFEND_DAMAGE` every
  `DEFEND_INTERVAL`, then goes back to work when the raid is over.  A dead resident takes no
  part; nothing chases a raider out of the settlement.
- `game.gd` starts the raid at night when a settlement is close enough (`ENGAGE_RADIUS`), spawns
  the group, feeds the raiders' positions to the residents each frame, routes raider blows to
  whoever they are chasing, applies residents' strikes to the nearest raider, and ends the raid
  when the raiders are gone ("Oakhollow beat off the raid").  Dawn retires any leftovers, and
  the last-raided day is remembered so a night is not fought twice.
- `--raid-now` forces tonight's raid for captures and manual checks.

### Tests and evidence

- New `scripts/tests/test_raids.gd` (62 assertions): the schedule, group sizes within their
  bounds and varying, the spawn ring and its determinism, unique/stable raider ids,
  `should_start` (quiet night, raid night, already raided, engage radius), the whole DEFEND task
  (nearest-threat selection relative to home, walking in, repeated strikes with the right
  damage, leaving defend when the threats are gone, a distance check that stays relative to
  home), and the clock's day counter (advance, wrap, frozen, save round-trip, legacy payload).
- `run_integration.gd` gained **10 assertions** (174 -> 184) driving a real raid: raiders spawn
  within their bounds, they are real hostile nodes, they target a resident rather than the
  player, a resident strikes one through the game's own `_apply_npc_events`, and the raid ends
  and is marked as fought once the raiders are gone.
- Unit **1238 assertions**, integration **184 assertions**, both exit 0 with **0 bytes stderr**.
  Smoke unchanged: `world_hash=441363152919021799`, `edits=0`, and
  `"raid":{"day":0,"active":0,...}` (no settlement in the streamed spawn region).
- Windowed capture `raid-night.png` (`--capture --find-structure=campsite --raid-now --time=0.50`)
  inspected: a resident crossing the beach in front of the campsite with two raiders (dark
  grunts) closing in, and the run summary reporting three live raiders.

### Limitations

- Raids come only when the player is near the settlement, so an unwatched settlement is never
  attacked, and there is no raid "resolution" off-screen.
- Residents fight with their hands; there is no weapon or armour item for them, and no
  guard role, so a raid can kill a settlement's whole population (it is not replenished).
- Raiders are ordinary grunts with no siege behaviour: they do not break blocks or target
  buildings, and their loot is the normal coal drop.
- The last-raided day is in memory only; a reload restores the day counter but not "this night
  was already fought", so a save taken mid-raid can be raided again.
- Verification is scripted (headless integration + windowed captures); no human play-through.


## M17 Priority 3: items, tools, mining and a real crafting system (2026-10-19)

The crafting system was five fixed recipes over block-only inventory slots.  It is now a
catalogue of **32 recipes** across five categories, gated by two placeable stations, with a
**tool and material item namespace**, item durability, hardness- and tool-driven mining, and a
crafting interface built for repeated use.  This is the largest gameplay increment of M17 so
far; it is one savepoint because the pieces are not separable (tools need the item namespace,
mining needs the tool rules, the catalogue needs both).

### 1. Item namespace (`scripts/core/item_db.gd`, new)

- Item ids are a superset of block ids: `0 .. BlockDB.COUNT-1` **are** the block ids, so every
  block lookup, face texture, mesh layer and saved edit keeps working unchanged.  Ids above
  that are 26 non-block items: `Stick`, `Coal`, `Iron Lump`, `Iron Ingot`, `Gold Lump`,
  `Diamond`, `Wheat`, `Apple`, `Bread`, `Golden Apple` and four tool classes (pickaxe, axe,
  shovel, sword) in four tiers (wood, stone, iron, diamond).
- Per item: name, atlas icon key, stack size, tool class, tier, mining speed, durability,
  attack damage, food/heal value, icon tint, placeability.
- Mining rules live here too: `break_seconds(block, held)` (hardness x 0.5 s, divided by the
  tool speed; the wrong tool is never slower than a hand, a sword is 1.5x), `harvestable()`
  (stone family needs a pickaxe; iron ore needs stone+, gold/diamond need iron+, obsidian needs
  diamond), `drop_for_block()` (ores drop lumps/crystals, not ore blocks) and `bonus_drop()`
  (leaves sometimes carry an apple, tall grass sometimes wheat - a pure function of the world
  position, so a replayed world mines identically).

### 2. Inventory: durability, stack cap, atomic load (`scripts/game/inventory.gd`)

- New `durability` array; `wear(slot, amount)` spends a tool's durability and clears the slot
  when it breaks; `add(item, count, tool_durability)` never merges tools and respects
  `ItemDB.max_stack` (64 for blocks and materials) - which is what makes the inventory
  genuinely fill up and the "inventory full" paths reachable.
- `from_dictionary` is now **atomic**: the payload is validated into scratch arrays and only
  committed when every entry is legal, so a malformed save cannot half-apply.
- `clear_slot()` and `remove_from_slot()` added; `selected_item()` (any item) alongside
  `selected_block()` (only when it is placeable).
- The starter kit is 16 per stack instead of 64: with a per-slot cap a full kit would leave a
  new player unable to pick up their first mining drop.

### 3. Crafting engine (`scripts/core/crafting.gd`, rewritten)

- Data-driven catalogue: each recipe has an `id`, a `category` (Basics, Building, Tools,
  Smelting, Food), a `station` (`hand` / `table` / `furnace`), either an ingredient dictionary
  or a 3x3 `pattern` + `key`, an output with a count, and - for smelting - a `fuel` cost.
- 32 recipes: log-to-planks and planks-to-sticks basics, crafting table, furnace; cobblestone,
  stone brick, sandstone, glass, brick; **all sixteen tools** (wood from planks, stone from
  cobblestone, iron from smelted ingots, diamond) as real shaped recipes; four smelting
  recipes that need a furnace and burn one coal each; bread from wheat and the golden apple.
- Shaped recipes declare the shape and `ingredients()` derives the multiset from it, so the
  two can never disagree; `match_grid()` implements the real shape semantics (trim + offset,
  no mirroring) and is tested even though the interface offers the ingredients as a list.
- Stations are blocks in the world: `best_station(world, center, radius)` scans loaded voxels,
  and a furnace also serves as a work surface so a player never has to carry both.
- `craft`/`craft_many` are atomic across the whole batch (ingredients, fuel, station and the
  output's room *after* consumption, all checked on a scratch copy of the stack counts with
  the 64 cap respected) - the check the old `_has_room_after` would have got wrong under the
  new stack cap.  `missing()` explains a shortfall, `craftable_count()` reports how many the
  ingredients allow, `can_craft_times()` answers for a batch.

### 4. Crafting interface (`scripts/game/crafting_panel.gd`, rewritten)

- Category filter buttons, a scrollable recipe list, and per row: the output icon, its count,
  a status line (`ready` / `missing 2 more Sand` / `needs Crafting Table` / `inventory full`)
  with red/amber colouring, the ingredient list as `have/need`, and **Craft** plus **x5**
  buttons that are disabled exactly when that craft (or batch) cannot happen.
- The header shows the station the *world* currently provides; the footer counts how many
  recipes are ready.  `press_craft()` activates the real buttons so the integration test
  drives the same code path a mouse click does.

### 5. Mining, drops and durability through the player

- `voxel_player.gd`: holding the break action mines **progressively**; the block takes
  `ItemDB.break_seconds()` to break and a progress bar appears under the crosshair.  Changing
  the target restarts the progress.  `break_target()` stays as the instant path used by tests
  and diagnostics.
- Drops now depend on the held tool: an inadequate tool still breaks the block but yields
  nothing and emits `harvest_failed` (the HUD explains "Stone needs a Pickaxe to drop
  anything"); the right tool yields the item drop and spends one durability, and the tool
  breaking emits `tool_broken` ("Your Wooden Pickaxe broke").
- Creature hits scale with the held item's attack damage and share the same durability spend.
- Placement accepts only block items ("Coal is not a placeable block").

### 6. HUD (`game_hud.gd`)

Item icons for every item (with an optional tint - the golden apple reuses the apple art),
per-slot durability bars that turn amber and then red, the selected-item line showing
`Wooden Pickaxe  20 / 60  (slot 1)`, and the mining progress bar.

### 7. Assets and persistence

- The furnace block (id 34) and 26 item icons were added from the **same in-repo Minetest
  `default` pack** already vendored by M12/M14 - no downloads, no new licence obligations;
  `tools/import_textures.py` and `ASSET_MANIFEST.md` were extended (67 keys now).
- `SaveManager` still writes the inventory as one dictionary, so durability rides along with
  no format break; `apply()` and `_sanitise()` now validate the inventory payload *before*
  mutating the world, the clock or the player, and reject it as invalid instead of applying
  half of it.

### Tests and evidence

- New `scripts/tests/test_items.gd` (namespace integrity, icon resolution, tool tiers and
  ordering, break times, harvest requirements, ore/bonus drops, food values, stack cap, full
  inventory, durability wear/break, atomic serialisation with legacy payloads).
- `scripts/tests/test_crafting.gd` rewritten for the catalogue: integrity (unique ids, valid
  stations/categories/outputs), **reachability** (every recipe is producible from mining drops
  and other recipes - this is what keeps the progression honest), shaped vs shapeless and
  `match_grid`, fifteen validation rejections, station gating, fuel consumption, batch
  crafting, `craftable_count`, atomicity (including the case the stack cap makes possible: a
  stack with 2 room and no free slot refuses a 4-item output without consuming anything), and
  the available-recipes copy contract.
- `scripts/tests/run_integration.gd` gained **37 assertions** (72 -> 109) that drive the real
  scene: a placed table/furnace becomes the station, the panel's own Craft and x5 buttons
  craft, the iron smelt consumes its coal, a worked column mines progressively (one frame
  breaks nothing; holding breaks it), a bare hand gets no stone drop and is told it needs a
  pickaxe, and a wooden pickaxe lasts exactly two blocks and then breaks.
- Unit **973 assertions**, exit 0, 0 bytes stderr (was 785).  Integration **109 assertions**,
  exit 0, 0 bytes stderr.  Headless smoke unchanged: `world_hash=441363152919021799`,
  `faces=166074`, `faces_hash=6977993294663025454`.
- Windowed captures inspected: `crafting-panel.png` (the kit loadout: ready / missing /
  needs-Crafting-Table / inventory-full rows, "4 of 32 recipes ready"), `crafting-panel-tools.png`
  (the `--tools` loadout: every row correctly unaffordable, 0 of 32 ready) and `tools-hud.png`
  (four tiers of tools with durability bars, the `Wooden Pickaxe 20 / 60` readout, cobblestone,
  sticks, ingots, coal and an apple in the hotbar).
- New `--tools` capture diagnostic (a deterministic nine-slot loadout) so the item HUD can be
  inspected without a scripted mining session.

### Limitations

- Mining has no visual crack overlay on the block; the progress is on the HUD bar only.
- The crafting interface matches recipes by ingredient multiset (the shaped definition and
  `match_grid` are real and tested, but there is no drag-and-drop 3x3 grid).
- Smelting is menu-driven per craft (one coal per item); there is no furnace fuel queue or
  timed burn.
- No eating yet: food items exist and have values, but hunger and consumption arrive in the
  next increment.
- Verification is scripted through the real scene and windowed captures; no human
  keyboard/mouse play-through was performed.


## M17 Priority 1: background chunk generation (2026-10-18, continued)

The roadmap's remaining streaming-hitch item. Chunk **generation** was still the one
expensive streaming step running inside the frame (~6 ms per chunk typical, up to ~21 ms),
so a heavy chunk could still drop a frame even though meshing had already moved to a
worker thread. Generation now runs on its own worker thread too.

### Measurement-harness defect found first (FIXED)

Before touching the streamer, an A/B run was taken and it showed *every* phase pinned at
~60 fps with idle frames costing 15.2 ms instead of the usual 1.2 ms. The cause was not the
streamer: the configuration screen added in `9cd77de` persists vsync to
`user://voxelworld_settings.cfg`, and `game.gd::_ready()` applies it — which overrode
`run_perf.gd`'s pre-boot `VSYNC_DISABLED` / `Engine.max_fps = 0`. The first two benchmark
runs of this session were therefore measuring the display refresh rate, not the game, and
were deleted rather than reported. `run_perf.gd` now:

- re-asserts `VSYNC_DISABLED` / `max_fps = 0` after the game scene boots (its `_ready` runs
  during `add_child`) and at the start of every phase;
- records `vsync_mode`, `max_fps`, `threaded_generation` and `threaded_meshing` in the
  report, so the measurement conditions are auditable instead of implied;
- gained `--sync-generation`, which turns the background generator off after boot, so the
  two code paths can be A/B-compared on one machine in one session.

### Implementation

- `scripts/game/chunk_streamer.gd`: new `threaded_generation` (default `true`) and
  `max_generation_in_flight` (default 8). A second worker thread owns its **own**
  `WorldGen`, seeded identically, so the shared `_column_cache` is never touched from two
  threads. The main thread only `_submit_generation_batch()`es coordinates (cheap, bounded
  by `generation_budget` and the in-flight cap) and `_collect_generation_batch()`es finished
  `ChunkData`s, adopting them through `world.adopt_chunk`. `is_settled()` counts in-flight
  generation; `clear()`/`_exit_tree()` tear the worker down and `clear()` restarts it;
  `_rebuild_wanted()` drops queued generation for coordinates the focus has left; `report()`
  gained `generation_in_flight` and `generation_worker_ms`.
- `scripts/core/voxel_world.gd::adopt_chunk` now applies the saved edits **before** counting
  solids, so a background-generated chunk is adopted exactly the way `ensure_chunk` used to
  build one (previously the order differed).
- Determinism is preserved by construction (the generator is a pure function of seed and
  coordinate and only ever writes inside its own chunk) and is pinned by tests.

### Measured (windowed, RTX 3080 / i7-10700K, seed 17017, radius 4, vsync off)

A/B in the same session: `--sync-generation` (`perf-*-inline.json`) vs the default
background generator (`perf-*-bg.json`).

| run | phase | metric | inline (sync) | background |
| --- | --- | --- | --- | --- |
| walk | settle | p95 / p99 / worst | 16.73 / 25.19 / 55.94 ms | **5.61 / 11.99 / 52.93 ms** |
| walk | settle | 1 % low | 31.3 fps | **46.9 fps** |
| walk | walk | p95 / p99 / worst | 4.54 / 16.32 / 31.01 ms | **3.80 / 6.30 / 31.21 ms** |
| walk | walk | 1 % low | 52.4 fps | **111.2 fps** |
| settle | settle | p95 / p99 / worst | 16.38 / 22.22 / 56.95 ms | **5.26 / 8.30 / 53.43 ms** |
| settle | settle | 1 % low | 33.8 fps | **52.0 fps** |
| walk | boot + settle | wall clock to ready | 5.26 s | **3.47 s** |
| settle | boot + settle | wall clock to ready | 5.47 s | **3.76 s** |

The `worst` frames are unchanged (~53 ms in both) and are the previously documented single
first-PLAYING frame (engine first-use), not a streaming frame. The remaining >20 ms walk
frames are GPU-bound, not CPU: three consecutive 31 ms frames report `process_ms` 6.5 ms
with 300 draw calls, and the same 31 ms frames exist in both runs. Main-thread montage cost
that survives is `attach` (ArrayMesh upload + `create_trimesh_shape()`), measured at up to
~26 ms on one settle frame; capping attachments per frame was already tested in a previous
session and made no measurable difference.

### Tests

- New `scripts/tests/test_streaming_lifecycle.gd` (registered in `run_tests.gd`): the
  in-flight generation count never exceeds `max_generation_in_flight`; a result for a
  coordinate that left the wanted set while it was being generated is **dropped**, so the
  loaded set stays exactly the wanted set after a large focus jump; `clear()` unloads
  everything and the streamer streams again afterwards.
- `scripts/tests/test_determinism.gd`: background generation must produce the identical
  logical-world fingerprint and identical geometry hash as synchronous generation, must
  leave `generation_in_flight == 0` when settled, and must load the same chunk count. The
  `--sync-generation` control in the harness is what makes this a real equivalence test.
- `test_determinism.gd` also had a swallowed assertion: a stray `#` made
  `h.eq(fine.face_counts.size(), wanted, "every wanted chunk is meshed exactly once")` part
  of a comment. Restored (and it passes).
- Unit: **785 assertions**, exit 0, 0 bytes stderr (was 767).
- Integration: **68 assertions**, exit 0, 0 bytes stderr.
- Smoke: exit 0, `world_hash=441363152919021799`, `faces=166074`,
  `faces_hash=6977993294663025454` — unchanged, and `generation_worker_ms=2829` matches the
  old main-thread `generation_ms_total≈2810`, which is the direct proof the work moved
  rather than disappeared.

Savepoint (this increment): committed with message
"M17 Godot: background chunk generation + trustworthy perf harness".

