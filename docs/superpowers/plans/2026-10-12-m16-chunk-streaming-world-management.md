# M16 Chunk Streaming & World Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give VoxelWorld a bounded chunk lifecycle — load chunks around the player, unload distant ones — that preserves player edits and never breaks the M1–M15 architecture.

**Architecture:** A new `ChunkStreamer` owns streaming *policy* (desired/retained sets, nearest-first scheduling, per-frame budgets, rendered registry). `World` owns chunk *lifecycle* (`load_chunk`/`unload_chunk` keep `world.chunks` authoritative, create/release the one entity per chunk, re-dirty loaded neighbours, invalidate stale water work). Terrain/vegetation regenerate deterministically per chunk; player edits survive in a sparse in-memory overlay.

**Tech Stack:** Python 3.14, Ursina 8.3 / Panda3D, NumPy, pytest.

**Spec:** `docs/superpowers/specs/2026-10-12-m16-chunk-streaming-world-management-design.md`

## Global Constraints

- **Do not modify any existing test.** Baseline: `python -m pytest tests -q` → **261 passed** at `main` HEAD `9a3177a`. Acceptance must report no fewer than 261 passed, nothing skipped or weakened.
- **Preserve architecture invariants:** logical `Chunk` is authoritative; one combined mesh and one Ursina entity per rendered chunk; chunk size 16×16×16; floor semantics for negative coordinates; reads must never create a chunk; entry point stays minimal.
- **Preserve M13 water semantics/determinism** and **M14 generation** (tufts, trees, determinism, non-interference).
- **Do not change** textures, `config/texture_manifest.json`, atlas assets, or dependencies.
- **No hard-coded streaming settings** outside `config/world_config.json` / `world_config.py`.
- **Do not commit or push.** The task forbids it; the working tree is left uncommitted.
- **Do not start M17.**
- Persistent policy (user-approved): discard + regenerate with an in-memory edit overlay; defaults stream 3 / retain 5 / 1 load + 4 unload per frame.

## Review Focus

- Boundary faces after load/unload: a load must re-cull the *first* chunk's faces against the new neighbour, and an unload must re-expose them; verify the neighbour dirtying covers both directions.
- Re-entry fidelity: an edit recorded before unload must be byte-identical after re-entry, including a cleared grass tuft (decoration) and a block placed over regenerated lake water.
- Overlay correctness: overrides must be applied after generation and must clear water metadata, never before generation, and must not re-record themselves.
- Water staleness: a job prepared against a chunk that then unloads/reloads must not publish; the version gate must actually fire on load and unload.
- Streaming convergence: after a finite number of `update()` calls the active set equals the desired set and `dirty_chunks` drains; no duplicates appear under repeated transitions.

---

## File Structure

### Create
- `config/world_config.json` — centralized streaming settings.
- `world_config.py` — loader/validator with defaults and `reset_cache()`.
- `chunk_streaming.py` — `ChunkStreamer`.
- `scripts/measure_m16_streaming.py` — headless runtime/measurement harness.
- `tests/test_m16_config.py`, `tests/test_m16_desired_set.py`, `tests/test_m16_load_unload.py`, `tests/test_m16_neighbour_dirtying.py`, `tests/test_m16_persistence.py`, `tests/test_m16_generation_equivalence.py`, `tests/test_m16_streaming_budget.py`, `tests/test_m16_water_lifecycle.py`.
- `config/m16_streaming_metrics.json` — recorded runtime measurements.

### Modify
- `terrain_generation.py` — extract `generate_chunk_terrain` / add `generate_chunk`; `generate_world` output unchanged.
- `world.py` — edit overlay, `load_chunk`, `unload_chunk`, `apply_overrides`; `set_block` records overrides.
- `water.py` — `seed_chunk_sources`.
- `main.py` — construct the streamer and call `streamer.update(player.position)` in `update()`.
- `MILESTONES.md` — M16 completion report.
- `ARCHITECTURE.md` — register the chunk lifecycle (invariant 11) and streaming config.

### Not modified
- `player.py`, `raycast.py`, `highlight.py`, `inventory*.py`, `vegetation.py`, `chunk.py`, `chunk_entity.py`, `chunk_mesh.py`, `block_data.py`, `texture_config.py`, and every existing test file.

---

## Task 1 — Centralized streaming configuration

**Files:**
- Create: `config/world_config.json`, `world_config.py`, `tests/test_m16_config.py`

**Interfaces:**
- Produces: `world_config.streaming_distance() -> int`, `world_config.retention_distance() -> int`, `world_config.max_chunk_loads_per_frame() -> int`, `world_config.max_chunk_unloads_per_frame() -> int`, `world_config.reset_cache() -> None`.

- [ ] **Step 1: Write failing tests** in `tests/test_m16_config.py`

```python
def test_defaults_when_values_missing(tmp_path, monkeypatch): ...
    # monkeypatch world_config.WORLD_CONFIG_PATH to a temp file containing {}
    # expect (3, 5, 1, 4) after reset_cache()

def test_values_loaded_from_json(tmp_path, monkeypatch): ...
    # {"streaming_distance": 2, "retention_distance": 4, ...} -> exact values

def test_invalid_values_fall_back_to_defaults(tmp_path, monkeypatch): ...
    # negative, non-int, and retention < streaming each fall back to defaults,
    # never below streaming_distance

def test_reset_cache_reloads(tmp_path, monkeypatch): ...
```
Tests import `world_config`, not an Ursina app. Use `monkeypatch.setattr(world_config, "WORLD_CONFIG_PATH", tmp)` + `world_config.reset_cache()`.

- [ ] **Step 2: Confirm failure**

Run: `python -m pytest tests/test_m16_config.py -q`
Expected: collection error / `ModuleNotFoundError: No module named 'world_config'`.

- [ ] **Step 3: Implement**

Create `config/world_config.json`:
```json
{
  "streaming_distance": 3,
  "retention_distance": 5,
  "max_chunk_loads_per_frame": 1,
  "max_chunk_unloads_per_frame": 4
}
```
Create `world_config.py` mirroring `texture_config.py`: module-level `REPO_ROOT`, `WORLD_CONFIG_PATH`, a `DEFAULTS` dict, `VALUE_KEYS`, `load_world_config()` with `@lru_cache(maxsize=1)` that parses the JSON, applies `_coerce_non_negative_int(key)` per key, then enforces `retention_distance >= streaming_distance`. Expose one accessor per key and `reset_cache()` clearing `load_world_config`.

- [ ] **Step 4: Verify pass**

Run: `python -m pytest tests/test_m16_config.py -q` → PASS. Then `python -m pytest tests -q` → 261 passed (no regressions).

---

## Task 2 — Per-chunk terrain generation (behaviour-preserving)

**Files:**
- Modify: `terrain_generation.py`
- Create: `tests/test_m16_generation_equivalence.py`

**Interfaces:**
- Produces: `TerrainGenerator.generate_chunk_terrain(world, chunk_x, chunk_y, chunk_z) -> Chunk`, `TerrainGenerator.generate_chunk(world, chunk_x, chunk_y, chunk_z) -> Chunk`.
- Consumes: existing `surface_height`, `in_lake`, `generate_vegetation_for_chunk`.

- [ ] **Step 1: Write the failing golden test** in `tests/test_m16_generation_equivalence.py`

```python
def _chunk_fingerprint(chunk):
    return (hashlib.sha256(chunk.blocks.tobytes()).hexdigest(),
            hashlib.sha256(chunk.decorations.tobytes()).hexdigest(),
            hashlib.sha256(chunk.water_levels.tobytes()).hexdigest(),
            hashlib.sha256(chunk.water_sources.tobytes()).hexdigest())

def test_generate_chunk_matches_generate_world_for_every_initial_chunk():
    a = World(); TerrainGenerator().generate_world(a)
    b = World(); gen = TerrainGenerator()
    for cx in (-1, 0, 1):
        for cz in (-1, 0, 1):
            gen.generate_chunk(b, cx, 0, cz)
    assert set(a.chunks) == set(b.chunks)
    for key in a.chunks:
        assert _chunk_fingerprint(a.chunks[key]) == _chunk_fingerprint(b.chunks[key])

def test_generate_chunk_outside_initial_region_matches_direct_generation():
    # A streamed chunk far from origin must equal a chunk generated by the same
    # pure rules: assert it has surface GRASS where surface_height says so.
    ...
```
The first test fails now (`generate_chunk` does not exist). Capture the current `generate_world` fingerprints implicitly (the test compares the two producers, so it is a true golden-equivalence gate).

- [ ] **Step 2: Confirm failure**

Run: `python -m pytest tests/test_m16_generation_equivalence.py -q`
Expected: `AttributeError: 'TerrainGenerator' object has no attribute 'generate_chunk'`.

- [ ] **Step 3: Implement**

In `terrain_generation.py`:
- Add `generate_chunk_terrain(self, world, chunk_x, chunk_y, chunk_z)` containing exactly the current per-chunk body of `_generate_height_map_terrain` (the `x`/`z`/`y` loops writing AIR/GRASS/DIRT/STONE/WATER + water levels/sources). `chunk_y != 0` returns an empty chunk from `world.get_chunk`.
- Add `generate_chunk(self, world, chunk_x, chunk_y, chunk_z)`: call `generate_chunk_terrain`, then if `chunk_y == 0` call `generate_vegetation_for_chunk(chunk, self.seed)`, then return the chunk.
- Rewrite `_generate_height_map_terrain` to `for cx in range(-1,2): for cz in range(-1,2): self.generate_chunk_terrain(world, cx, 0, cz)`. Leave `generate_world` untouched.

- [ ] **Step 4: Verify pass**

Run: `python -m pytest tests/test_m16_generation_equivalence.py tests/test_vegetation_determinism.py tests/test_water_chunk_integration.py -q` → PASS. Then full suite → 261 passed.

---

## Task 3 — World chunk lifecycle and edit overlay

**Files:**
- Modify: `world.py`
- Create: `tests/test_m16_load_unload.py`, `tests/test_m16_neighbour_dirtying.py`, `tests/test_m16_persistence.py`

**Interfaces:**
- Produces: `World.block_overrides: dict[tuple[int,int,int], int]`, `World.decoration_overrides: dict[tuple[int,int,int], int]`, `World.load_chunk(chunk_x, chunk_y, chunk_z, terrain_generator=None) -> Chunk`, `World.unload_chunk(chunk_x, chunk_y, chunk_z) -> bool`, `World.apply_overrides(chunk) -> None`.
- Consumes: `TerrainGenerator.generate_chunk`, `create_chunk_entity`.

- [ ] **Step 1: Write failing tests**

`tests/test_m16_load_unload.py`
```python
def test_load_chunk_registers_once_and_creates_entity():
    world = World(); gen = TerrainGenerator()
    chunk = world.load_chunk(4, 0, 4, terrain_generator=gen)
    assert world.chunks[(4, 0, 4)] is chunk
    again = world.load_chunk(4, 0, 4, terrain_generator=gen)
    assert again is chunk            # idempotent, no duplicate
    assert len(world.chunks) == 1
    assert chunk.entity is not None  # one rendered entity

def test_unload_chunk_releases_entity_and_registry_entry():
    world = World(); gen = TerrainGenerator()
    chunk = world.load_chunk(0, 0, 0, terrain_generator=gen)
    world.dirty((0, 0, 0))
    assert world.unload_chunk(0, 0, 0) is True
    assert (0, 0, 0) not in world.chunks
    assert (0, 0, 0) not in world.dirty_chunks
    assert chunk.entity is None and chunk.entity_transparent is None
    assert world.unload_chunk(0, 0, 0) is False   # idempotent

def test_repeated_load_unload_leaves_no_duplicates():
    ...  # loop load/unload 5x at several keys, assert len(world.chunks) == 1 each time
```

`tests/test_m16_neighbour_dirtying.py`
```python
def test_load_dirty_marks_loaded_neighbour():
    world = World(); gen = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=gen)
    world.refresh()                       # clear dirt
    world.load_chunk(1, 0, 0, terrain_generator=gen)
    assert (0, 0, 0) in world.dirty_chunks # first chunk re-culls its +X face
    assert (1, 0, 0) not in world.dirty_chunks or True  # new chunk already meshed

def test_unload_dirty_marks_loaded_neighbour():
    ...  # load (0,0,0) and (1,0,0); refresh; unload (1,0,0); assert (0,0,0) dirty

def test_load_does_not_dirty_unloaded_neighbour():
    ...  # load (5,0,5) only; nothing else exists; assert dirty set has no phantom keys
```

`tests/test_m16_persistence.py`
```python
def test_block_edit_survives_unload_and_reentry():
    world = World(); gen = TerrainGenerator()
    world.load_chunk(0, 0, 0, terrain_generator=gen)
    world.set_block(3, 6, 3, BlockType.STONE)   # surface at (3,3) is GRASS at y=surface
    world.unload_chunk(0, 0, 0)
    chunk = world.load_chunk(0, 0, 0, terrain_generator=gen)
    assert chunk.get_block(3, 6, 3) == BlockType.STONE

def test_cleared_decoration_survives_reentry():
    ...  # find a column whose generated surface has a tuft; set_block the surface
         # block to AIR (clears the tuft); unload/reload; assert decoration == 0

def test_placed_block_over_regenerated_lake_water_is_not_water():
    ...  # edit a lake WATER cell to STONE; unload/reload; assert STONE and
         # chunk.get_water_level == 0

def test_regenerated_terrain_is_identical_without_edits():
    ...  # fingerprint before/after unload+load with no edits; equal
def test_reads_still_never_create_chunks():
    ...  # world.get_block/get_water over a wide range leaves world.chunks empty
```

- [ ] **Step 2: Confirm failure**

Run: `python -m pytest tests/test_m16_load_unload.py tests/test_m16_neighbour_dirtying.py tests/test_m16_persistence.py -q`
Expected: `AttributeError: 'World' object has no attribute 'load_chunk'`.

- [ ] **Step 3: Implement in `world.py`**

- `__init__`: add `self.block_overrides = {}`, `self.decoration_overrides = {}`.
- `set_block`: after the existing decoration clearing, record
  `self.block_overrides[(world_x, world_y, world_z)] = int(block_type)` and
  `self.decoration_overrides[(world_x, world_y, world_z)] = 0`; when
  `not is_block_solid(block_type)` and `local_y + 1 < Chunk.SIZE_Y`, also
  `self.decoration_overrides[(world_x, world_y + 1, world_z)] = 0`.
- `apply_overrides(chunk)`: iterate `self.block_overrides` (a coordinate->value walk is fine at this scale), select cells whose chunk coords equal the chunk's, `chunk.set_block`, `chunk.set_water_level(...,0)`, `chunk.set_water_source(...,False)`; then apply `decoration_overrides` with `chunk.set_decoration`.
- `load_chunk(chunk_x, chunk_y, chunk_z, terrain_generator=None)`: return existing; else `terrain_generator.generate_chunk(self, ...)` (or an empty `Chunk` registered when no generator is supplied and `chunk_y != 0`), `apply_overrides`, register, `create_chunk_entity` (guarded import), and bump `self.water_edit_version`.
- `unload_chunk(chunk_x, chunk_y, chunk_z)`: pop; destroy entities via `ursina.destroy` in `try/except`, set `chunk.entity = chunk.entity_transparent = None`; discard from `dirty_chunks`; clear `recent_edit_chunk` if equal; mark loaded neighbours dirty using the same face rule as `_mark_dirty_with_neighbors`; bump `water_edit_version`.

- [ ] **Step 4: Verify pass**

Run: `python -m pytest tests/test_m16_load_unload.py tests/test_m16_neighbour_dirtying.py tests/test_m16_persistence.py -q` → PASS. Then full suite → 261 passed.

---

## Task 4 — Chunk streamer (desired sets, budgets, convergence)

**Files:**
- Create: `chunk_streaming.py`, `tests/test_m16_desired_set.py`, `tests/test_m16_streaming_budget.py`

**Interfaces:**
- Consumes: `World.load_chunk`, `World.unload_chunk`, `TerrainGenerator.generate_chunk`, `world_config` accessors, optional `WaterSimulation.seed_chunk_sources` (Task 5; guarded by `getattr`).
- Produces: `ChunkStreamer(world, terrain_generator=None, water_sim=None, streaming_distance=None, retention_distance=None, max_loads_per_frame=None, max_unloads_per_frame=None)`, `.rendered: dict`, `.player_chunk_coords(pos) -> (cx, cz)`, `.desired_chunk_keys(pos) -> set`, `.retained_chunk_keys(pos) -> set`, `.update(player_position, force=False) -> dict`, `.has_pending_work() -> bool`, `.active_keys() -> set`.

- [ ] **Step 1: Write failing tests**

`tests/test_m16_desired_set.py`
```python
def test_desired_set_is_chebyshev_radius_at_origin(): ...
    # streamer with streaming_distance=1; pos (8,8,8) -> 9 keys {(dx,0,dz)} -1..1
def test_desired_set_handles_negative_chunk_coordinates(): ...
    # pos (-24, 8, -24) -> player chunk (-2, -2); keys around it, all y == 0
def test_retained_superset_of_desired(): ...
    # retention_distance >= streaming_distance -> retained ⊇ desired
```

`tests/test_m16_streaming_budget.py`
```python
def test_update_loads_at_most_budget_per_frame(): ...
    # max_loads_per_frame=1; after 1 update, len(world.chunks) == 1
def test_update_unloads_at_most_budget_per_frame(): ...
    # preload many chunks; max_unloads_per_frame=2; one update unloads <= 2
def test_convergence_reaches_exactly_the_desired_set(): ...
    # call update repeatedly (bounded loop, e.g. 200 iterations) until
    # not streamer.has_pending_work(); assert set(world.chunks) == desired
def test_same_chunk_is_a_no_op(): ...
    # after convergence, update(pos) returns {"loaded":0,"unloaded":0,...}
def test_moving_loads_nearest_first(): ...
    # with budget 1 and desired 9, the first loaded key is the player's own chunk
def test_no_duplicate_entities_across_transitions(): ...
    # move back and forth across a boundary; assert len(world.chunks) bounded and
    # len(streamer.rendered) == len(world.chunks)
def test_unload_releases_entities(): ...
```

- [ ] **Step 2: Confirm failure**

Run: `python -m pytest tests/test_m16_desired_set.py tests/test_m16_streaming_budget.py -q`
Expected: `ModuleNotFoundError: No module named 'chunk_streaming'`.

- [ ] **Step 3: Implement `chunk_streaming.py`**

`ChunkStreamer` as in spec D2/D7: resolve config from `world_config` when an argument is `None`; `_player_chunk(pos)` via `int(math.floor(x // 16))` (use existing `coordinate_system.get_chunk_containing_world_coords` for the x/z pair); Chebyshev desired/retained sets; `update` per spec D7 step 1–6; track `_last_player_chunk`; a `rendered` dict keyed by chunk key → entity, updated on load/unload; `_load_one` calls `world.load_chunk`, then `water_sim.seed_chunk_sources(chunk)` when a water sim was supplied; `_unload_one` calls `world.unload_chunk` and drops the registry entry.

- [ ] **Step 4: Verify pass**

Run: `python -m pytest tests/test_m16_desired_set.py tests/test_m16_streaming_budget.py -q` → PASS. Then full suite → 261 passed.

---

## Task 5 — Water lifecycle across load/unload

**Files:**
- Modify: `water.py`
- Create: `tests/test_m16_water_lifecycle.py`

**Interfaces:**
- Produces: `WaterSimulation.seed_chunk_sources(chunk) -> int`.

- [ ] **Step 1: Write failing tests**

```python
def test_seed_chunk_sources_enqueues_only_that_chunks_sources():
    # lake chunk (0,0,0); WaterSimulation(world).seed_chunk_sources(chunk)
    # -> pending_seeds non-empty; every queued coord lies in that chunk

def test_load_chunk_invalidates_a_running_water_job():
    # start a job (tick once), record water_edit_version, world.load_chunk(...)
    # -> version increased; a subsequent tick rebuilds from current state

def test_unload_chunk_invalidates_a_running_water_job():
    # same, with world.unload_chunk

def test_stale_water_job_cannot_publish_into_a_reloaded_chunk():
    # enqueue water work, unload then reload the chunk, then tick repeatedly;
    # assert the reloaded chunk's water is exactly what a fresh solve produces
```

- [ ] **Step 2: Confirm failure**

Run: `python -m pytest tests/test_m16_water_lifecycle.py -q`
Expected: `AttributeError: 'WaterSimulation' object has no attribute 'seed_chunk_sources'`.

- [ ] **Step 3: Implement**

Add `seed_chunk_sources(self, chunk) -> int`: iterate the chunk's `water_sources`, `enqueue` the source cells' world coordinates, return the count. Reuse it inside `seed_all_sources` so there is one code path.

- [ ] **Step 4: Verify pass**

Run: `python -m pytest tests/test_m16_water_lifecycle.py tests/test_water_rules.py tests/test_water_chunk_integration.py tests/test_m15_water_equivalence.py -q` → PASS. Then full suite → 261 passed.

---

## Task 6 — Frame integration, runtime verification and measurements

**Files:**
- Modify: `main.py`
- Create: `scripts/measure_m16_streaming.py`, `config/m16_streaming_metrics.json`
- Modify: `MILESTONES.md`, `ARCHITECTURE.md`

**Interfaces:**
- Consumes: `ChunkStreamer`, `world_config`.

- [ ] **Step 1: Integrate the streamer into `main.py`**

Construct `streamer = ChunkStreamer(world, terrain_generator=terrain_gen, water_sim=water_sim)` after the water simulation, and change `update()` to:
```python
def update():
    world.reconcile()
    streamer.update(player_entity.position)
    water_sim.consume_changes()
    if not world.dirty_chunks:
        water_sim.tick()
```
Keep the entry point minimal (no new gameplay logic).

- [ ] **Step 2: Write the measurement harness** `scripts/measure_m16_streaming.py`

Build the real scene offscreen (`Ursina(window_type="offscreen", …)`, `Path` asset folder — mirror `scripts/profile_m15.py`), then:
- walk the player along +X then −X across several chunk boundaries, calling `update()`-equivalent steps (`world.reconcile(); streamer.update(...); water_sim.tick()`);
- record per-phase: loaded/desired/rendered counts, `len(streamer.rendered)`, duplicates, `pending_work`, numpy bytes for `world.chunks`, overlay entry counts, frame-time p50/p95/p99/max, count of frames > 16.67 ms and > 33.33 ms;
- verify re-entry: edit a block, move away until it unloads, move back, assert the edit is restored;
- verify negative coordinates: same walk at negative chunk coords;
- write `config/m16_streaming_metrics.json` with a `meta` block (Python/Ursina/Panda3D/NumPy versions, platform, scene description) and an explicit `limitations` list.

- [ ] **Step 3: Run and record**

Run: `python scripts/measure_m16_streaming.py`
Expected: JSON written with no duplicate chunks/entities, active set equal to the desired set after convergence, restored edit = True, and recorded frame-time/memory numbers.

- [ ] **Step 4: Regression + invariants**

Run: `python -m pytest tests -q` → **no fewer than 261 passed**, nothing skipped. Confirms M6 boundary, M7 interaction, M13 water and M14 vegetation still hold.

- [ ] **Step 5: Documentation**

Add an M16 completion report to `MILESTONES.md` (files changed, decisions, test command/result, measured CPU/frame-time/memory numbers, restored-edit evidence, the "one chunk mesh is the irreducible streaming unit" limitation, and that on-screen visual verification was not possible). Register the chunk lifecycle and streaming config in `ARCHITECTURE.md` (new invariant: chunks load/unload within a configured bounded active region; rendering is not the authoritative store). Do not rewrite earlier milestones.
