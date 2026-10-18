# M17 Godot — Roadmap

Status legend:

- `[x]` implemented **and verified** (automated test or inspected runtime/visual evidence)
- `[~]` implemented, not yet verified
- `[ ]` not started
- `[!]` blocked

Source of the phase structure: `prototypes/m17/GODOT_MISSION.md` §8.

---

## Phase A — Core playable world

- [x] Godot project that opens, runs and renders (4.7.2-stable, windowed run verified)
- [x] 16³ chunk storage, logical voxels authoritative, chunk↔world coordinate conversion with floor semantics
- [x] Central block definitions (34 blocks: terrain, ores, wood, glass, decoration, crafting table)
- [x] Face-culled chunk meshing, five render layers, no per-voxel engine objects
- [x] Deterministic terrain generation (seed 17017): height field, biomes, caves, ores, trees, decoration
- [x] Chunk streaming with per-frame generation/meshing budgets and neighbour-aware culling
- [x] Mesh construction runs on a dedicated worker thread (main thread only snapshots the
      voxel input and attaches finished meshes); profiling in the 2026-10-16 renderer
      investigation showed in-frame meshing was the frame-time spike source
- [x] First-person player: mouse look, WASD, jump, gravity, sprint, AABB collision
- [x] Block targeting (voxel DDA raycast), left-click break, right-click place against the targeted face
- [x] Placement blocked inside the player and inside other solids
- [x] Mesh + collision invalidation of the edited chunk and its neighbours
- [x] Water: logical fluid solver, cross-chunk propagation, bounded per-tick work, animated transparent surface
- [x] Texture atlas (Minetest `default` pack), directional sun with shadows, sky, fog, SSAO
- [x] Versioned save/load of block edits, fluid overrides, player and inventory (atomic write, corrupt-save quarantine)
- [x] Main menu, pause menu, autosave, HUD with hotbar and item counts
- [x] Automated test suite (767 assertions, verified 2026-10-18) + runtime integration harness (68 assertions, verified 2026-10-18) + headless determinism fingerprint
- [x] Frame-time benchmark harness (`scripts/tests/run_perf.gd`): six scripted activities, per-frame
      timings and streaming counters, before/after JSON reports (verified 2026-10-16)
- [x] Capture harness for reproducible screenshots + objective image statistics tool
- [x] Visual quality pass: lighting/fog retuned and re-inspected; sand is bright and near-tree
      shadows are dark (both plausible, not fixed)

## Phase B — Building and survival

- [x] Inventory data model (9 slots, block id + count, serialisable)
- [x] Visible hotbar with real block icons, selection, counts and tooltip
- [ ] Full inventory interface (only the hotbar row is visible; no drag & drop, no overflow page)
- [x] Collecting drops into the inventory (mining adds the drop; inventory-full feedback)
- [x] Placing items consumes them
- [x] Crafting recipes (data model + rules + tests) — `core/crafting.gd`: 5 fixed
      recipes, atomic `craft` (AIR output rejected, capacity judged against the
      post-consumption state), `can_craft`/`available_recipes`; all five inputs are
      obtainable (clay generation fixed — see backlog)
- [x] Crafting interface — `game/crafting_panel.gd`, opened with C; `crafting-ui.png` inspected
- [ ] Tools, tool tiers and durability
- [x] Health and damage (fall damage and drowning; hostile damage is Phase C)
- [ ] Hunger / survival settings
- [x] Environmental feedback (hurt flash, bounded reversible camera shake; particles not included)
- [x] Death and respawn (death screen and valid spawn; no creature combat in this increment)
- [x] Configuration screen (render distance, sensitivity, vsync) — `core/game_settings.gd`
      (clamped, validated, dictionary round-trip) + `game/settings_panel.gd`, opened with `O`
      or `--open-settings`; render distance applies live through
      `ChunkStreamer.apply_render_radius`, sensitivity to the player, vsync to the display,
      all persisted to `user://voxelworld_settings.cfg` (CLI `--render-distance` still wins for
      captures). `test_settings.gd` + 8 integration assertions; `settings-ui.png` inspected
      (2026-10-18)
- [x] Pause menu

## Phase C — Living world

- [x] Day/night cycle (sun angle, sky, ambient and fog follow a clock) — `day_night.gd`,
      tested, `day-noon.png` / `day-dusk.png` / `day-night.png` inspected;
      `--time=` / `--time-rate=` drive it, saved with the world (save VERSION 2).
      **Finished and fully visually verified 2026-10-18**: the whole clock was captured and
      inspected (`day-cycle-000/025/050/055/075/095.png`), the missing mid-twilight frame is
      included, image statistics confirm the monotonic bounded curve, the HUD clock text
      matches, and a live `--time-rate=120` run advanced the clock in PLAYING. The quick
      sunset→night transition is a tuning choice (the curve is pinned by tests), not a defect.
- [x] One passive boar species (bounded deterministic nearby spawn, unique per-column
      identity, cap 6, 54-block despawn range, bounded pruning, voxel-aware wandering,
      primitive animated silhouette, player damage and one Oak Log drop; unit + runtime
      integration verified 2026-10-16). Ground is taken from the **live world voxels**
      (`supports_standing` / `wander_destination` in `core/passive_creatures.gd`), not the
      procedural generator, so mining the ground block removes the spawn/move site
      (reviewer defect fixed 2026-10-16 with new unit assertions)
- [x] Hostile creatures (targeting, melee, spawning in the dark) — `core/hostile_creatures.gd`
      + `game/hostile_creature.gd`: one "grunt" species, night-only gate (or `--spawn-hostiles`),
      live-ground spawn 12-32 blocks from the player (cap 4), chase that stops at attack range
      and refuses mined/flooded floor, contact melee (2 damage / 1.2 s), 4 HP, one Coal drop,
      bounded pruning, transient (not saved). `test_hostiles.gd` (38 assertions) and 8 real-scene
      integration assertions; `hostile-creature.png` inspected (grunt at midnight, "Grunt hurt
      (3/4)"). Verified 2026-10-18
- [x] Combat, damage exchange and loot (minimal melee exchange, 2026-10-18) — the player's LMB
      creature path damages hostiles and kills them for one drop; a hostile in contact damages
      the player through the shared impact-damage path (invulnerability window + camera shake),
      verified in integration (20→18 health, four hits to kill, loot added). Weapons/durability,
      ranged attacks and varied loot remain out of scope
- [x] Passive creature spawning/despawning tied to the player's surroundings (38-block
      spawn search, 54-block retention, streamed loaded-cell checks, deterministic IDs,
      live-world ground/headroom so player edits are respected)
- [x] Creature save policy documented: transient living animals are re-seeded from the
      world seed and current player neighborhood on load; dead-creature drops are placed
      directly in the existing persistent inventory. Save format remains VERSION 3.
- [ ] Weather or environmental variation
- [ ] Exploration incentives: caves, ores and landmarks are generated but unrewarded
      (no ore→tool progression yet)

## Phase D — Structures and settlements

- [ ] Procedural structures (camps, ruins, wells) as reusable definitions
- [ ] Player construction beyond single blocks (blueprint/paste helpers)
- [ ] Reusable structure definition format
- [ ] NPC foundation with persistent identity and state
- [ ] NPC movement and basic tasks
- [ ] Settlement layout and resident assignment
- [ ] Resource storage and task delegation
- [ ] Defensive behaviour and enemy raids
- [ ] City-management foundation

---

## Engineering backlog (not gameplay)

- [x] Stale padded-buffer bug in `ChunkMesher._fill_padded` (leaked the previous chunk's
      neighbour data into a reused buffer) — fixed, regression test added
- [x] Inverted triangle winding in `ChunkMesher` (faces wound opposite to Godot's
      front-face convention, so `cull_back` hid the terrain and the collision trimesh
      reported inverted normals — the root cause of the reported WASD movement failure and
      the rendering defects) — fixed in `chunk_mesher.gd` + legacy `main.gd`, pinned by the
      `test_mesh_winding.gd` unit test and the `run_integration.gd` runtime test
- [x] Determinism regression tests (streaming batch sizes, generation order, fingerprints)
- [x] Persistence regression test (`SaveManager` write/read/apply round-trip, version-1
      load, seed-mismatch rejection, corrupt-save quarantine) — previously untested
- [x] Clay was unreachable: the `elif underwater and world_y >= height - 2` clay clause in
      `world_gen.gd` was shadowed by the preceding `>= height - 3` branch, so clay never
      generated (and the `4 Clay → 1 Brick` recipe was unusable). Reordered so the clay band
      generates in submerged columns; `test_generation.gd` asserts clay is present.
      This changed world content — `world_hash` is now `441363152919021799`
      (`faces`/`faces_hash` unchanged: clay swaps one opaque subsurface block for another).
- [x] Texture array layer sampling: every voxel shader sampled `texture(atlas, vec3(UV, UV2.x + 0.5))`.
      The `+ 0.5` puts the array-layer coordinate exactly on the midpoint between two layers;
      this engine build rounds the coordinate, so faces and per-pixel patches rendered the
      neighbouring texture (grass_top→gravel, sand→sandstone, leaves→log side) and the pattern
      changed with the camera. Fixed by sampling the exact integer layer in all five shaders;
      pinned by a shader-source contract test in `test_textures.gd` and before/after captures.
- [x] Streaming frame-time spikes: attribution showed every >20 ms frame did chunk generation
      and/or meshing on the main thread (gen+mesh frames averaged 23–25 ms, worst 52 ms; idle
      frames cost ~1.2 ms). Chunk meshing moved to a worker thread (`capture_input` snapshot on
      the main thread, pure `build_geometry` on the worker, `assemble` + node attach on the main
      thread); measured walk p99 28.5→16.3 ms, 1 % low 31.9→53.5 fps, and settling 4.3→3.1 s
      wall clock. See the renderer-investigation section of `godot-progress.md`.
- [~] First-fill cost: ~2.9 s generation + ~2.3 s meshing + ~0.5 s attach for 392 chunks after
      the worker-thread change; generation is still synchronous on the main thread and a single
      heavy chunk (~10 ms typical, ~17 ms worst) can occasionally drop one frame
- [ ] Background/threaded generation (mission §9): meshing is now threaded; **generation** still
      runs in the frame. This is the remaining known hitch source and the next step if the
      residual single-frame dips matter more than their current size
- [x] Save format versioning: VERSION 3 accepts versions 1..3 (adds health and breath;
      v1/v2 fields remain optional); unknown versions are still quarantined
- [x] Remove temporary diagnostics (`M17_OPTIONS`, `_probe_surface.gd`)
- [x] Passive creatures decided ground from the procedural generator (`height_at` /
      `_surface_block`) instead of the live world, so a mined ground block still looked
      like valid floor and a boar could spawn/wander over a hole. Fixed with the node-free
      `supports_standing` / `wander_destination` helpers in `core/passive_creatures.gd`
      (loaded + solid + non-liquid ground; loaded-air foot/head) used by both
      `spawn_candidates` and `game/passive_creature.gd::_physics_process`; regression
      assertions added to `test_creatures.gd` (reviewer defect, 2026-10-16)
- [x] Chunk-boundary invalidation along Z was inverted: `voxel_world.gd::_flag_neighbours`
      mapped the `-Z` border to `BACK` (+Z) and the `+Z` border to `FORWARD` (-Z), so a block
      broken on a chunk's Z border never dirtied the real neighbour. Its shared face stayed
      culled in the render mesh and collision, letting the player see through the hole and walk
      through the boundary wall (X/Y were correct, making it look intermittent). Fixed with
      explicit `(0,0,-1)` / `(0,0,1)` offsets; pinned by the new `test_edit_rebuild.gd`
      (all six boundary directions, the threaded streamer, and consecutive edits racing a
      rebuild) and 17 new real-scene integration assertions (mesh + collision + physics-ray
      probes). Before/after windowed captures `m17-edit-{bug,fix}-after.png` (2026-10-18)
- [x] Asynchronous chunk-rebuild race (2026-10-18): a mesh build in flight for a chunk whose
      neighbour set changed (unload/load/regeneration) was attached with the old border because
      the neighbour change only queued the chunk and did not bump its `mesh_revision`; the stale
      result then cleared the dirty flag and the queued rebuild was dropped, leaving a
      render+collision hole at the edge of the loaded region. `chunk_streamer.gd` now
      `mark_dirty()`s loaded neighbours on chunk create/remove and keeps a still-dirty coordinate
      queued in `_collect_mesh_batch`. Pinned by
      `test_edit_rebuild.gd::_test_pending_build_survives_neighbour_unload` (RED: 3 failures,
      GREEN: pass)
- [x] Player kept moving while paused (2026-10-18): `_pause()` disabled interaction but not
      physics, so WASD and gravity ran behind the pause menu (30 frames moved the body 8.67
      units). `_pause()`/`_resume()` now toggle `player.set_physics_process(...)`; integration
      asserts no movement while paused (0.000 units). This was the reproducible WASD reliability
      defect
- [x] Test runner hung on a module that fails to parse (2026-10-18):
      `(script as GDScript).new()` aborted `_run_all` and left the suite running until the 300 s
      watchdog. `run_tests.gd` now checks `can_instantiate()` and reports a normal failure
- [~] Remaining streaming hitch (2026-10-18 re-measured after the race fix): walk p99
      17.12 ms / settle p99 21.44 ms, unchanged by the race fix and still dominated by chunk
      **generation** (~12-20 ms in-frame) plus GPU first-use of new geometry; threaded
      generation is the next engineering step (no performance fix claimed)
