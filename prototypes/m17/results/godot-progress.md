# M17 Godot — Progress and Resume Point

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
input/collision), `prototypes/m17/tools/image_stats.py` (objective image statistics).

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

Read this file and `godot-roadmap.md`, then run the tests and the smoke command from
§5 to confirm the baseline still holds (`435` unit + `17` integration assertions;
current `world_hash=441363152919021799`, `faces=166074`, `faces_hash=6977993294663025454`
— the clay generation fix in §12 changed the world content, so the earlier
`world_hash=6372495951065888771` is historical). Then continue with the first unchecked
item of `godot-roadmap.md` phase B/C (see §11 for this run's plan: crafting done, next is
health & damage, then the living world).

**Stabilization is done for the three user-reported items**: the WASD movement failure,
the rendering defects and the water concern all traced to the inverted-winding bug now
fixed in `c22d056` (§8). Phase B is under way: the crafting data model and interface landed
in §12 (independently reviewed: PASS). The remaining Phase B items are the full inventory
interface, tools/durability, health & damage, hunger, feedback, death/respawn and a
configuration screen.

**Outstanding validation**: the fix is verified headless (unit + integration) and by
offscreen capture; a human play-through with real keyboard/mouse has not been done. If a
real play-through is possible, it should be the first thing to do before building on top.

Baseline sanity command set (copy/paste):

```powershell
cd C:\Users\Admin\Documents\Projects\VoxelWorld_oneshot
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd | Select-Object -Last 1
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_integration.gd -- --straight-to-game | Select-Object -Last 1
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=30 | Select-String M17_GAME_SUMMARY
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

1. **Crafting** — recipe data model + deterministic rules + tests + a functional crafting
   interface (Phase B: `[ ] Crafting recipes`, `[ ] Crafting interface`).
2. **Health & damage** — player health, fall damage, drowning, HUD hearts, death + respawn,
   saved with the world (Phase B: health/damage, feedback, death/respawn).
3. **Living world** — passive and hostile creatures, voxel-aware AI, spawn/despawn rules,
   combat and loot (Phase C).

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
