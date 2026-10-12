# M16 — Chunk Streaming & World Management: Design Spec

**Status:** APPROVED (design decisions) — implementation follows in
`docs/superpowers/plans/2026-10-12-m16-chunk-streaming-world-management.md`.

**Companion milestone definition:** `MILESTONES.md`, section "M16 — Chunk Streaming &
World Management".

**Date on the filename:** `2026-10-12`, matching the current date and the most recent
milestone documents.

---

## 1. Objective

Give VoxelWorld a chunk lifecycle so the player can explore beyond the fixed 3×3
generated region, while CPU, rendering workload and memory stay bounded.

The system must:

1. Load chunks around the player and unload distant ones as the player moves.
2. Keep the logical `Chunk` authoritative and keep the one-entity-per-rendered-chunk
   rule.
3. Reuse the existing terrain, vegetation and mesh pipelines; never regenerate a valid
   chunk.
4. Preserve player modifications across an unload/re-entry.
5. Bound per-frame streaming work so movement does not stall the frame.
6. Preserve M1–M15 behaviour and every existing test.

This milestone does **not** assume a design. The evidence below was gathered from the
repository at `main` HEAD `9a3177a` on 2026-10-12.

---

## 2. Evidence from the current implementation

### 2.1 Repository state and baseline

| Item | Value |
|---|---|
| Repository state | `main`, HEAD `9a3177a` (`feat(m15): complete performance profiling and budgetable water commits`) |
| Python / Ursina / Panda3D / NumPy / pytest | 3.14.5 / 8.3.0 / 1.10.16 / 2.4.4 / 9.1.1 |
| Existing suite | `python -m pytest tests -q` → **261 passed in 23.10s** |
| Pre-existing untracked files | `.freebuff/`, `.opencode/skills/ursina-doc/`, `.superpowers/sdd/…`, `tests_final_report.txt`, `voxel_textures/blocks_bck/` — reported, untouched |

### 2.2 There is no chunk lifecycle at all (source-confirmed)

- `World.chunks` (`world.py:33`) is a plain `dict` that only ever grows.
- `World.get_chunk` (`world.py:122`) creates on demand; nothing removes a chunk.
- A grep for `unload`, `view_distance`, `render_distance`, `chunks.pop`, `removeNode`
  finds only test names and docstrings.
- Membership is bounded today only because world generation is hard-wired to 3×3
  chunks: `TerrainGenerator._generate_height_map_terrain` iterates `range(-1, 2)`
  twice (`terrain_generation.py`).
- A read is safe against phantom growth after the M6 fix: `World.get_block` never
  creates (`world.py:154`), `WaterSimulation`'s view reads `world.chunks` directly,
  and `World.set_water` refuses to create (`world.py:256`). This invariant must be
  preserved (guard test: `tests/test_m15_memory_growth.py::test_read_only_traversal_does_not_create_chunks`).

Consequence: memory currently scales with the *loaded* set, which is the right model,
but nothing bounds the loaded set. At the M15-measured 28,672 B/chunk, an unbounded
exploration world cannot be loaded at once — a bounded active region is required.

### 2.3 Meshing depends on neighbour load state (source-confirmed)

`chunk_mesh._add_exposed_faces_to_split` (`chunk_mesh.py`, neighbour branch) queries
`world.is_loaded(global_x, global_y, global_z)` and treats an **unloaded** neighbour as
`AIR`. Therefore:

- a boundary face toward an unloaded neighbour is **rendered** (exposed);
- when that neighbour loads, the face must be **re-culled** on the first chunk;
- when a neighbour unloads, the face becomes exposed again and must be **re-rendered**.

Any load or unload must therefore mark the affected chunk's *loaded* neighbours dirty.
This is the same rule `World._mark_dirty_with_neighbors` already applies to block edits.

### 2.4 M15 already provides the scheduling primitives to build on

- `World.reconcile()` (`world.py:63`) rebuilds dirty chunk meshes under an 8 ms
  per-frame budget, edited chunk first, never starving the queue.
- `main.py:update()` is the single frame hook (`reconcile` → water).
- `WaterSimulation.tick()` is resumable, time-budgeted, and discards its `active_job`
  when `world.water_edit_version` changes (`water.py`), re-queuing the job's seeds.
- `World.set_block` is the **single external-edit path** (player break/place); terrain
  generation writes through `Chunk.set_block` and water through
  `Chunk.set_block`/`apply_water_cells`/`World.apply_water_batch`.

### 2.5 Terrain and vegetation are deterministic and chunk-local (source-confirmed)

- `surface_height(seed, x, z)` and `in_lake(x, z)` are pure functions of the column
  only (`terrain_generation.py`).
- `generate_vegetation_for_chunk(chunk, seed)` never reads a neighbour chunk: tree
  cells are written only into their owning chunk and only into `AIR`, and tufts read
  the chunk's own blocks plus the pure terrain predicates (`vegetation.py`).
- `Chunk.decorations` is a separate logical layer that never touches collision,
  raycast, placement or water.

Therefore a single chunk can be generated independently, and regenerating a chunk
reproduces byte-identical terrain and vegetation.

### 2.6 The M6 boundary guard is a fallback, not an obstacle

`VoxelPlayer._position_inside_generated_world` / `_chunk_exists`
(`player.py`) refuse movement into a chunk that is not in `world.chunks`. With
streaming keeping chunks loaded ahead of the player, that guard becomes a safety net.
Crucially, `tests/test_player_boundary.py` drives **only** player methods, so an
explicitly-invoked streamer leaves its assertions ("player stays inside the generated
region", "no phantom chunks") green.

### 2.7 Config precedent

There is no general configuration module. M10 established the pattern that matters
here: a `config/*.json` document read once by a small loader with graceful defaults and
an `lru_cache`/`reset_cache` pair (`texture_config.py`). Streaming settings will follow
that exact pattern.

---

## 3. Approved decisions

The user explicitly approved the two pivotal decisions on 2026-10-12:

1. **Chunk lifecycle & persistence — discard + regenerate with an in-memory edit
   overlay.** Unload releases the rendered entity *and* removes the logical chunk from
   the registry. Re-entry regenerates terrain and vegetation deterministically and
   re-applies a sparse in-memory overlay of player edits. Memory stays bounded and no
   save/load file is introduced.
2. **Streaming defaults — stream 3 / retain 5 / 1 load + 4 unload per frame.** All
   four values are tunable through `config/world_config.json`.

### D1. Two responsibilities, two owners

- `ChunkStreamer` (`chunk_streaming.py`, new) owns **policy**: the desired/retained
  chunk sets, nearest-first scheduling, per-frame budgets, and the rendered-chunk
  registry.
- `World` owns **lifecycle**: `load_chunk`/`unload_chunk` keep `world.chunks`
  authoritative and consistent (single registration, entity create/release, neighbour
  dirtying, water invalidation).

This keeps `world.chunks` the authoritative logical registry (M16 scope, architecture
invariant 1) and separates "which chunks should exist" from "how a chunk enters/leaves".

### D2. Horizontal streaming only

Streaming operates on `chunk_y = 0`, because only that layer carries terrain, water and
vegetation. The desired set is a Chebyshev (square) radius around the player's chunk
coordinates:

```
desired(x, z)  = { (cx, 0, cz) : max(|cx - px|, |cz - pz|) <= streaming_distance }
retained(x, z) = { (cx, 0, cz) : max(|cx - px|, |cz - pz|) <= retention_distance }
```

Chebyshev (not Euclidean) is chosen because it is exact, deterministic, cheap, and
directly matches "horizontal render distance in chunks". Floor division
(`// 16`) gives correct negative chunk coordinates, preserving architecture invariant 4.

### D3. Load path

`World.load_chunk(cx, cy, cz)`:

1. Return the existing chunk when already registered (no duplicates).
2. Create the `Chunk`; for `cy == 0`, generate terrain and vegetation for **that chunk
   only** through `TerrainGenerator.generate_chunk`.
3. Re-apply the chunk's slice of the edit overlay (D5/D6).
4. Register in `world.chunks`.
5. Create the rendered entity with `create_chunk_entity` (which builds the mesh with the
   currently known neighbour load state).
6. Bump `water_edit_version` so a running water job re-solves against the new domain.

Returning the existing chunk makes load idempotent, which is what guarantees "a chunk
must not be registered or generated twice for the same coordinates".

### D4. Unload path

`World.unload_chunk(cx, cy, cz)`:

1. Return `False` when the chunk is not registered.
2. Destroy the opaque entity and the transparent child (guarded; `None` in headless
   tests) and clear `chunk.entity` / `chunk.entity_transparent`.
3. Remove the chunk from `world.chunks` and from `dirty_chunks`; clear
   `recent_edit_chunk` when it pointed at this chunk.
4. Mark the chunk's **loaded** neighbours dirty (§2.3: their boundary faces are now
   exposed).
5. Bump `water_edit_version`.

### D5. Persistence policy (explicit)

| Chunk state | Classification | Mechanism |
|---|---|---|
| Base terrain blocks (GRASS/DIRT/STONE/AIR) | **regenerable** | deterministic `surface_height`/`in_lake` |
| Lake water blocks, levels and sources | **regenerable** | deterministic lake geometry |
| Vegetation: grass tufts (`decorations`) and tree blocks | **regenerable** | deterministic `hash32`/`tree_*` |
| Player block edits (`World.set_block`) | **authoritative, persistent** | in-memory `World.block_overrides` |
| Decoration cleared by an edit | **authoritative, persistent** | in-memory `World.decoration_overrides` |
| Water simulation spread (`set_water` / `apply_water_batch`) | **derived, not persisted** | re-derived from deterministic sources after re-entry |
| `dirty_chunks`, `changed_blocks`, `water_edit_version`, entities | **transient** | rebuilt by the frame loop |

Player edits are recorded in `World.set_block` (the only external-edit entry point), so
this policy does not require touching the player, raycast or inventory code.

### D6. Edit overlay mechanics

- `World.block_overrides: dict[(wx, wy, wz) -> int]`
- `World.decoration_overrides: dict[(wx, wy, wz) -> int]`

`set_block` records the new block for the edited cell, and records a cleared decoration
(`0`) for the edited cell and for the cell above it when the new block cannot support a
plant — mirroring exactly what `set_block` already does to `chunk.decorations`.

`World.apply_overrides(chunk)` rewrites the chunk's cells from the overlay after
generation. A block override also clears the cell's water level/source, matching
`set_block`'s clearing, so a block placed over regenerated lake water does not come back
as water. Overrides are sparse and grow only with edits.

### D7. Per-frame scheduling and budgets

`ChunkStreamer.update(player_position)` each frame:

1. Resolve the player's chunk coordinates; **skip entirely** when they are unchanged and
   no pending load/unload remains (M16: "avoid unnecessary work when the player remains
   within the same chunk").
2. Compute `desired` and `retained` (D2).
3. `to_load = desired - loaded`, sorted nearest-first, tie-broken by coordinates.
4. `to_unload = loaded - retained`, sorted farthest-first.
5. Load at most `max_chunk_loads_per_frame`; unload at most
   `max_chunk_unloads_per_frame`.
6. Return a stats dict (`loaded`, `unloaded`, `active`, `desired`, `pending_loads`,
   `pending_unloads`, `player_chunk`).

Loading one chunk performs one terrain+vegetation generation plus one combined-mesh
build. That single chunk is the **irreducible streaming unit**: the mesh generator
builds a chunk's combined mesh in one pass (M15 measured ≈42 ms) and cannot be split
without changing the renderer, which is an M16 non-goal. It is therefore documented as
the unavoidable per-frame cost, and the load *count* is what is bounded.

### D8. Water across the lifecycle

- On load, `WaterSimulation.seed_chunk_sources(chunk)` enqueues the newly available
  source cells (the startup path already uses `seed_all_sources`).
- On load **and** unload, `World` bumps `water_edit_version`. The existing version gate
  in `WaterSimulation.tick()` then discards any `active_job` built on the old domain and
  re-queues its seeds, so pending water work can never publish a result computed for a
  chunk that has been unloaded or replaced.
- Derived water spread is regenerated from the deterministic sources after re-entry
  (D5); it is not persisted.

### D9. Configuration

- `config/world_config.json` holds `streaming_distance`, `retention_distance`,
  `max_chunk_loads_per_frame`, `max_chunk_unloads_per_frame`.
- `world_config.py` loads it once (`lru_cache`), validates it (non-negative integers,
  `retention_distance >= streaming_distance`), falls back to the D-approved defaults on
  any missing/invalid value, and exposes `reset_cache()` for test isolation — the exact
  `texture_config.py` pattern.
- No streaming setting is hard-coded in `chunk_streaming.py` or `world.py`.

### D10. Frame integration order

`main.py:update()` becomes:

```python
world.reconcile()                        # M15: bounded mesh rebuild of last frame's dirt
streamer.update(player_entity.position)  # M16: load/unload + neighbour re-culling dirt
water_sim.consume_changes()
if not world.dirty_chunks:
    water_sim.tick()
```

M15's "player edit first" rule is preserved (reconcile still runs first). Streaming
dirt (neighbour re-culling) is therefore handled by the **next** frame's reconcile,
which bounds a streaming frame to one generation + one mesh build. The player's own edit
keeps absolute priority.

### D11. Terrain generation refactor (behaviour-preserving)

`TerrainGenerator` gains:

- `generate_chunk_terrain(world, cx, cy, cz)` — the per-chunk terrain loop extracted
  verbatim from `_generate_height_map_terrain`.
- `generate_chunk(world, cx, cy, cz)` — `generate_chunk_terrain` + (for `cy == 0`)
  `generate_vegetation_for_chunk`.
- `_generate_height_map_terrain` now calls `generate_chunk_terrain` for its 3×3 range;
  `generate_world` is otherwise unchanged (`_generate_height_map_terrain` +
  `generate_vegetation`).

Because vegetation is order-independent and chunk-local (2.5), the extraction preserves
`generate_world` output byte-for-byte; a golden regression test pins this.

---

## 4. Approaches considered

| Approach | Verdict |
|---|---|
| Policy (`ChunkStreamer`) + lifecycle (`World.load_chunk`/`unload_chunk`) split | **Chosen** — keeps the logical registry authoritative and makes both halves unit-testable. |
| Streaming inside `VoxelPlayer` movement | **Rejected** — would make movement tests generate chunks, breaking the M6 boundary guard's test and mixing responsibilities. |
| Streaming inside `World.get_block`/`get_chunk` | **Rejected** — reads must never create (M6 fix); implicit generation is the exact defect M6 fixed. |
| Retain all logical chunks, release only render resources | **Rejected by the user** — memory grows with the explored footprint; does not satisfy the milestone's memory goal. |
| Discard chunks, persist nothing, regenerate | **Rejected** — silently loses player modifications, which M16 forbids. |
| Discard + regenerate + in-memory edit overlay | **Chosen (user-approved)** — bounded memory, no save files, modifications preserved. |
| Euclidean radius | **Rejected** — Chebyshev matches "horizontal distance in chunks" and is cheaper and exact. |
| Unload/load every chunk in one frame | **Rejected** — unbounded frame cost (each chunk ≈42 ms mesh). |
| Create the mesh incrementally across frames | **Rejected for M16** — requires splitting the combined-mesh renderer; documented as the irreducible unit instead. |
| On-disk persistence / save files | **Out of scope** (M16 non-goals). |

---

## 5. Testing strategy

### 5.1 Automated tests (new; existing tests unmodified)

| File | Covers |
|---|---|
| `tests/test_m16_config.py` | defaults, JSON load/override, validation, `reset_cache` |
| `tests/test_m16_desired_set.py` | desired/retained sets, Chebyshev radius, negative chunk coords |
| `tests/test_m16_load_unload.py` | idempotent load, single registration, entity create/release, registry consistency |
| `tests/test_m16_neighbour_dirtying.py` | load and unload dirty *loaded* neighbours only |
| `tests/test_m16_persistence.py` | block + decoration overrides survive unload/re-entry; regenerated terrain identical; regenerated lake water |
| `tests/test_m16_generation_equivalence.py` | per-chunk generation equals `generate_world` (golden hash) |
| `tests/test_m16_streaming_budget.py` | per-frame load/unload caps, nearest-first order, convergence, same-chunk skip |
| `tests/test_m16_water_lifecycle.py` | `seed_chunk_sources`; version bump discards a stale job; no stale publication |

### 5.2 Regression coverage

The acceptance run includes the full suite (`python -m pytest tests -q`, baseline **261
passed**) plus the M6/M7/M13/M14-specific files:
`test_player_boundary.py`, `test_break_block.py`, `test_place_block.py`,
`test_world_dirty_tracking.py`, `test_chunk_mesh.py`, `test_m12_face_orientation.py`,
`test_tree_chunk_boundaries.py`, `test_vegetation_determinism.py`,
`test_water_rules.py`, `test_water_chunk_integration.py`, `test_m15_*.py`.

### 5.3 Runtime verification and measurement

A headless/offscreen script (`scripts/measure_m16_streaming.py`) builds the real
`main.py` scene, then walks the player across positive and negative chunk boundaries and
records, per the M16 acceptance criteria:

- loaded/desired/active/rendered counts and that they match the streaming/retention
  radius;
- duplicate chunk/entity checks after repeated transitions;
- re-entry restores terrain and a prior edit;
- frame time p50/p95/p99/max for streaming frames vs idle frames;
- per-chunk numpy bytes over time (bounded active set);
- water pending-work behaviour across load/unload.

Output is written to `config/m16_streaming_metrics.json`. Because the agent environment
cannot display or inspect rendered images, on-screen visual verification is **not**
possible and is reported as a limitation rather than claimed.

---

## 6. Acceptance-criteria mapping

| M16 criterion | Mechanism | Test / evidence |
|---|---|---|
| Chunks load/unload as the player moves | `ChunkStreamer.update` + `World.load_chunk`/`unload_chunk` | `test_m16_streaming_budget.py`, runtime harness |
| Active set follows streaming/retention distances | Chebyshev desired/retained sets | `test_m16_desired_set.py`, runtime harness |
| No duplicate chunks/entities or stale resources | idempotent load, rendered registry, entity destroy | `test_m16_load_unload.py`, runtime harness |
| Terrain/modifications/water follow the documented policy | D5/D6 overlay + deterministic regeneration | `test_m16_persistence.py`, `test_m16_generation_equivalence.py` |
| Pending work cannot corrupt unloaded/recreated chunks | version-gated water discard (D8) | `test_m16_water_lifecycle.py` |
| Per-frame streaming work bounded | `max_chunk_loads_per_frame`/`unloads` (D7) | `test_m16_streaming_budget.py`, recorded frame times |
| All new + existing tests pass | — | `python -m pytest tests -q` |
| Runtime exploration across ± boundaries | offscreen harness | `config/m16_streaming_metrics.json` |
| CPU/frame-time/memory recorded, GPU limits identified | harness meta + limitations | metrics JSON + completion report |
| Architecture/milestone docs updated | this spec, the plan, `MILESTONES.md` report, `ARCHITECTURE.md` | review |

---

## 7. Non-goals

- Multiplayer/networked streaming.
- Procedural terrain redesign; changing generation rules, textures or the atlas.
- On-disk save/load or any persistent world file.
- Splitting a chunk into multiple rendered entities, LOD, greedy meshing, renderer
  replacement.
- Any change to M13 water levels/spread rules/determinism, or M14 generation rules.
- Unrelated refactoring (e.g. removing the dead `World.generate_initial_terrain`).
- Starting M17.

---

## 8. Risks, limitations and open questions

| Risk | Mitigation |
|---|---|
| Regeneration drifts from original generation | Golden equivalence test pins `generate_chunk` == `generate_world`. |
| Overlay misses non-regenerable state | D5 is exhaustive over what exists; the overlay records exactly what `World.set_block` mutates; test asserts block *and* decoration survival. |
| Boundary faces stale for a few frames after load/unload | Neighbours are marked dirty; reconcile (≤8 ms/frame) re-culls them; documented as bounded staleness. On unload this can briefly expose a missing face at the *far* streaming edge, behind the player. |
| Water job churn as the player crosses chunk boundaries | Version gate re-queues seeds; water is derived, so churn is correctness-neutral. |
| One chunk's mesh is ~42 ms, above a frame budget | Documented as the irreducible unit; only the load *count* per frame is bounded (D7). |
| Memory: retention + overlay growth | Retention bounds the active/loaded set; overlay is sparse and grows with edits. Per-chunk and overlay bytes are measured and reported. |
| Offscreen measurement misses GPU cost | GPU/draw-call scaling is reported as counts and explicitly not verified on the GPU. |

**Open questions resolved during implementation:** exact per-frame generation+mesh cost
for a streamed chunk on this machine (recorded in the metrics JSON), and whether the
8 ms reconcile budget keeps neighbour re-culling within a small, bounded number of
frames (measured).
