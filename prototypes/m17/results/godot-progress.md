# M17 Godot — Progress and Resume Point

Last updated: 2026-10-16 (autonomous Godot development session).
Mission: `prototypes/m17/GODOT_MISSION.md`.
Roadmap: `prototypes/m17/results/godot-roadmap.md`.

---

## 1. Current objective

Turn VoxelWorld into a real, playable Godot 4 first-person voxel game and keep
expanding it toward a survival/building game (mission phases A → D). Phase A
(the playable voxel foundation) is essentially complete and visually verified;
work is now on phase B (survival systems) and C (living world).

## 2. Current phase and next concrete task

- **Phase**: A complete, B in progress.
- **Next concrete task**: see §9 “Resume”.

## 3. What actually works (verified)

Verified means: observed in a run of the real project, not merely written.

| Area | State | Evidence |
| --- | --- | --- |
| Project opens and runs | verified | windowed runs, 60 fps, exit code 0, empty stderr |
| Deterministic terrain generation | verified | 3 consecutive runs, `world_hash=6372495951065888771`, `faces=166074` |
| Chunk meshing (face culling) | verified | 392 chunks, 166 074 faces, 332 148 triangles at radius 4 |
| Streaming + bounded work | verified | `queued=0`, `worst_mesh_ms≈16`, `generation_ms_total≈2.8 s` |
| Player movement + collision | verified | movement observed in captures; physics-driven spawn/settle |
| Block breaking / placing | verified | automated tests + HUD target readout in captures |
| Negative coordinates | verified | `test_coordinates.gd`, floor-based conversion |
| Water (logical + rendered) | verified | `test_fluid.gd`, water visible in captures |
| Save / load, versioned | verified | `SaveManager` + `test_edits.gd`; quarantine path on bad saves |
| Main menu / pause / play loop | verified | menu is the boot scene; `--straight-to-game` skips it |
| HUD, hotbar, item counts | verified | visible in `diag-shore.png`, `godot-game-tour-*.png` |
| Textures, lighting, sky, fog | verified | inspected captures (see §6) |

## 4. Files and architecture

Godot project root: `prototypes/m17/godot/`.
`project.godot` main scene: `res://scenes/game.tscn` → `scripts/game/game.gd`.

**Engine layer** (`scripts/core/`, no scene-tree knowledge):

- `chunk_data.gd` — 16³ voxel storage, chunk/world coordinate conversion (floor semantics).
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

**Diagnostics**: the capture harness inside `game.gd`, `scripts/tests/*` (`run_tests.gd` is the
headless runner), `prototypes/m17/tools/image_stats.py` (objective image statistics).

## 5. Commands

Engine: `C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe`
(Godot **4.7.2-stable mono official**; the mono build is used because that is what is
installed — the project is pure GDScript).

```powershell
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
$repo  = 'C:\Users\Admin\Documents\Projects\VoxelWorld_oneshot'

# Automated tests (headless, exit code is the result)
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd

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
`--no-shadows`, `--fog=<density>` (`0` disables fog).

## 6. Tests and visual verification performed

**Automated (headless)**

- `M17_TESTS_PASS 271 assertions`, exit code 0, 0 bytes of stderr.
- Modules: coordinates, chunk data/indexing, block DB, generation, mesher (incl. a
  stale-padding regression), raycast, edits/persistence, fluid, fixture contract,
  textures, streaming determinism, view/clear teardown.

**Runtime**

- `--straight-to-game --quit-after=30` (3 runs): `world_hash=6372495951065888771`,
  `faces=166074`, `faces_hash=6977993294663025454`, `meshed=392`, `loaded=392`,
  `queued=0`; two byte-identical `--fog=0` vs `--fog=0.0018` captures proved the
  render path is deterministic.
- Windowed captures: 1280×720, 224 draw calls, 201 684 primitives, 60 fps.

**Visual (images actually inspected)**

| Capture | What it shows |
| --- | --- |
| `results/godot/look-spawn.png` | first-person spawn view: grass, sand terrace, trees, coast, blue sky |
| `results/godot/look-aerial.png` | aerial radius-6 view: lake, coastline, forest, no holes in the terrain |
| `results/godot/look-shore.png` | shore/underwater transparency, seabed visible through water |
| `results/godot/light-shore.png` + `light-shore-noshadow.png` | shadow control pair (dark ground under canopies disappears without shadows) |
| `results/godot/light-aerial.png`, `fogtest-*.png`, `light-aerial-nofog.png` | fog tuning series (table below) |
| `results/godot/diag-aerial.png`, `diag-shore.png`, `diag-water.png` | earlier HUD/tour captures from the previous session |
| `results/godot/godot-game-tour-0..3.png` | HUD, hotbar, targeting, tooltips |

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

Final settings: exponential fog `0.0008`, SSAO radius 0.5 / intensity 0.85, sun 1.22,
ambient sky contribution 1.0 at energy 1.45 — see `results/godot/look-*.png`.

Shadows were confirmed to be the dark patches in the earlier `diag-shore.png`
(identical capture with `--no-shadows` removed them): not a rendering defect.

## 7. Performance measurements (this machine, seed 17017)

- GPU: NVIDIA GeForce RTX 3080; CPU: Intel Core i7-10700K; 32 GB RAM; 1920×1080.
- Render radius 4 (392 chunks, 166 074 faces): 224 draw calls, 60 fps windowed.
- First fill: `generation_ms_total≈2 810 ms`, `mesh_ms_total≈2 190 ms`
  (fill 341 / emit 1 792 / assemble 55), `worst_mesh_ms≈15.6`, `queued=0`.
- Render radius 6 (565 chunks, 232 260 faces): still 60 fps in the capture run.
- Headless smoke run (no rendering) reports 145 fps — not a rendering measurement.

## 8. Known defects, limitations, blockers

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

## 9. Resume

Read this file and `godot-roadmap.md`, then run the tests and the smoke command from
§5 to confirm the baseline still holds (`271 assertions`, `world_hash=6372495951065888771`).
Then continue with the first unchecked item of `godot-roadmap.md` phase B/C.

Baseline sanity command set (copy/paste):

```powershell
cd C:\Users\Admin\Documents\Projects\VoxelWorld_oneshot
$godot = 'C:\Godot\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64.exe'
& $godot --headless --path prototypes/m17/godot --script res://scripts/tests/run_tests.gd | Select-Object -Last 1
& $godot --headless --path prototypes/m17/godot -- --straight-to-game --quit-after=30 | Select-String M17_GAME_SUMMARY
```
