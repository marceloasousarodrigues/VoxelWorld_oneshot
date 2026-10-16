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
- [x] First-person player: mouse look, WASD, jump, gravity, sprint, AABB collision
- [x] Block targeting (voxel DDA raycast), left-click break, right-click place against the targeted face
- [x] Placement blocked inside the player and inside other solids
- [x] Mesh + collision invalidation of the edited chunk and its neighbours
- [x] Water: logical fluid solver, cross-chunk propagation, bounded per-tick work, animated transparent surface
- [x] Texture atlas (Minetest `default` pack), directional sun with shadows, sky, fog, SSAO
- [x] Versioned save/load of block edits, fluid overrides, player and inventory (atomic write, corrupt-save quarantine)
- [x] Main menu, pause menu, autosave, HUD with hotbar and item counts
- [x] Automated test suite (435 assertions) + runtime integration harness (17 assertions) + headless determinism fingerprint
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
- [ ] Health and damage (fall damage, drowning, hostile damage)
- [ ] Hunger / survival settings
- [ ] Environmental and combat feedback (hurt flash, camera shake, particles)
- [ ] Death and respawn
- [ ] Configuration screen (render distance, sensitivity, vsync) — render distance is currently CLI-only
- [x] Pause menu

## Phase C — Living world

- [x] Day/night cycle (sun angle, sky, ambient and fog follow a clock) — `day_night.gd`,
      tested, `day-noon.png` / `day-dusk.png` / `day-night.png` inspected;
      `--time=` / `--time-rate=` drive it, saved with the world (save VERSION 2)
- [ ] Passive creatures (spawn rules, wandering AI, drops)
- [ ] Hostile creatures (targeting, melee, spawning in the dark)
- [ ] Combat, damage exchange and loot
- [ ] Spawning and despawning rules tied to the player's surroundings
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
- [~] First-fill cost: ~2.9 s generation + ~2.2 s meshing; reduce by spreading work or
      caching the height field
- [ ] Background/threaded generation (mission §9: only if profiling shows it is needed)
- [x] Save format versioning: VERSION 2 accepts versions 1..2 (adds the day/night clock);
      unknown versions are still quarantined
- [x] Remove temporary diagnostics (`M17_OPTIONS`, `_probe_surface.gd`)
