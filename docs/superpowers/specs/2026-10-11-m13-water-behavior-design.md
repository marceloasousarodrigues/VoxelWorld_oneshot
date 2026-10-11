# M13 — Water Behavior & Fluid Simulation: Design Spec

**Date:** 2026-10-11 (rev. 5)  
**Milestone:** M13  
**Status:** Proposed — awaiting explicit approval before implementation.

**Scope guard:** M13 only. No other milestone is started, no block IDs or textures are changed, and no implementation occurs until explicitly approved.

Revision 5 preserves the previous design decisions and adds explicit requirements for bounded commit preparation, atomic publication, world-version invalidation, chunk-availability changes, and deterministic restart behavior.

---

## 1. Objective

Implement functional voxel water behavior: source water, flowing water, vertical flow with priority, bounded horizontal propagation, interaction with air / solid blocks / player block edits, cross-chunk propagation with dirty-chunk tracking and neighbouring-mesh regeneration, transparent water rendering with internal face culling, and a documented compatibility decision for the existing water textures.

The existing architecture is preserved:

- Logical `Chunk` block data remains authoritative.
- Block data stays independent from rendering.
- One combined mesh per rendered chunk and one Ursina Entity per rendered chunk.
- Dirty-chunk regeneration and cross-chunk face culling continue to work.
- Block IDs, the current `blocks/water.png` texture, and M1–M12 behavior remain unchanged.
- Water simulation remains headless-testable and must not import Ursina in its core logic.

## 2. Evidence from the current implementation

| Fact | Evidence |
|---|---|
| `BlockType.WATER = 4`; non-solid and transparent | `block_data.py` |
| There is no separate source/flowing block type | `block_data.py` |
| Water is generated inside the lake, approximately y=2..4 and radius 6 | `terrain_generation.py` |
| `World.set_block` marks the containing chunk and loaded boundary neighbours dirty | `world.py` |
| `World.refresh()` regenerates dirty chunk meshes | `world.py` |
| Terrain generation writes through `chunk.set_block` | `terrain_generation.py` |
| Water uses the transparent child entity while preserving combined chunk meshes | `chunk_entity.py`, `chunk.py` |
| Transparent mesh generation currently does not cull water-water internal faces | `chunk_mesh.py` |
| The opaque pass treats water as non-solid, preserving solid faces next to water | `chunk_mesh.py` |
| Current `voxel_textures/blocks/water.png` is 16×16 RGBA, with alpha approximately 130–215 | Previously measured |
| Minetest still water textures are opaque 128×128 images; animated variants are 128×1024 eight-frame strips | Previously measured; atlas pipeline is static |
| The block raycast ignores non-solid blocks, so water is not currently selectable or breakable | `raycast.py` |
| Existing test baseline was 96 passing tests | Previously run with `python -m pytest tests -q` |

These observations are inherited from the earlier design investigation. They must be rechecked against the repository before implementation if the code has changed.

**Known documentation defect:** the M13 section in `MILESTONES.md` is truncated and ends mid-sentence at `#### 6. Performance — Do not simulate`. Do not repair unrelated milestone documentation as part of M13.

---

## 3. Design decisions

### D1. Water state representation — one WATER type plus per-Chunk metadata

Keep `BlockType.WATER` as the authoritative occupancy.

Add non-rendering logical metadata to `Chunk`:

- `water_levels`: `int8[16,16,16]`; 0 means dry, 1–7 means flowing water, 8 means full-strength water.
- `water_sources`: `bool[16,16,16]`; true only for permanent sources.

Source versus flowing water is represented by the level and source flag, not by new block types.

This preserves block IDs, inventory mapping, raycast behavior and the existing world representation.

**Rejected alternative:** adding `WATER_SOURCE` and `WATER_FLOWING` block types. This would modify the enum and item mapping while still requiring level metadata.

### D2. Flow model — deterministic, source-derived and finite

Levels are derived from permanent sources by path cost. Never relax a cell toward `neighbour_level - 1`.

Constants:

- `MAX_LEVEL = 8`
- `SOURCE_LEVEL = 8`
- `MAX_HORIZONTAL_SPREAD = 32` (configurable; raised from the initial 7 to support long cascade testing, and intentionally left configurable so it can be increased or removed later based on test results)
- `DEFAULT_MAX_CELLS_PER_TICK = 65536`

A source has level 8. A reachable cell has level `max(1, SOURCE_LEVEL - cost)`, where cost is the cheapest valid path from any source. The clamp to a minimum level of 1 prevents long horizontal runs (or a long vertical fall at the edge of the horizontal range) from drying out purely from level exhaustion — the finite range, not the level clamp, is the bound.

- A downward step into a loaded passable cell below (`AIR` or `WATER`) costs 0. There is no arbitrary vertical distance limit; water flows down any valid connected opening.
- A horizontal step into a loaded passable neighbour (`AIR` or `WATER`) costs 1.
- Horizontal propagation is limited to `MAX_HORIZONTAL_SPREAD` (configurable; default 32).
- Cells with no valid source path drain to `AIR`.

#### D2.1 Horizontal-spread predicate

The cell below determines whether the current cell can spread horizontally.

| Cell below | Downward propagation | Horizontal propagation |
|---|---|---|
| Loaded `AIR` | Allowed, cost 0 | Suppressed; water falls first |
| Loaded `WATER` | Allowed, cost 0 | Allowed, cost 1 |
| Solid | Not allowed | Allowed, cost 1 |
| Unloaded chunk | Not allowed | Allowed, cost 1 |
| Below `y=0` | Not allowed | Allowed, cost 1 |

The only suppression condition is that the cell below is a **loaded `AIR` cell**.

A `WATER` cell below does not suppress horizontal spread. It is fed at cost 0.

#### D2.2 Vertical-fill rules

1. If the cell below is loaded and passable, water fills or feeds it with downward cost 0.
2. A source above empty space fills the cell below. That cell continues filling downward until a solid blocker, unavailable chunk boundary or world floor is reached.
3. A water cell above existing water can spread horizontally while feeding the column below.
4. When falling water reaches a blocker, the supported cell can spread horizontally with decreasing levels.
5. Water never enters a solid block or an unloaded chunk. The solver must not create chunks.

The solver only accesses cells whose chunks are loaded. Unloaded chunks are boundaries, not air.

#### D2.3 Deterministic solver

Use a source-derived 0-1 BFS or an equivalent deterministic shortest-path implementation.

- Discover the affected water region.
- Seed the solver from every permanent source in that region.
- Apply the expansion rules above.
- Use fixed neighbour ordering and deterministic coordinate tie-breaking.
- Never treat old flowing levels as sources.
- Never query block data for an unloaded coordinate.
- Never create a chunk as a side effect of water propagation.

The pure reference solver is:

`solve_water_view(view, seeds, max_horizontal_spread=32) -> dict[tuple[int, int, int], int]`

It returns the desired level of each water cell in the affected solution. Existing region cells absent from the solution must drain.

### D3. Recession and multiple sources

Recompute the affected region from scratch rather than relaxing previous levels.

1. Identify the connected component of existing `WATER` blocks containing the seed cells. Connectivity is six-directional and bounded to loaded chunks.
2. Discover reachable passable cells under D2.
3. Calculate the source-derived solution.
4. Drain existing region cells absent from the solution.
5. Prepare and publish the complete update atomically.

Required behavior:

- Removing the only source drains all derived water no longer reachable from a source.
- Two adjacent sources remain independent permanent sources.
- Overlapping source influence uses the minimum valid path cost.
- Water supported by another source remains.
- Equal-level neighbours cannot sustain one another without a source path.
- Re-running a stable region produces no occupancy changes.
- Stale metadata cannot resurrect drained water.

### D4. Metadata cleanup and World mutation rules

#### `World.set_block`

`World.set_block(x, y, z, block_type)` must:

1. Clear the cell's water level and source flag.
2. Set the requested block type.
3. Preserve existing dirty-chunk and loaded-boundary-neighbour marking.
4. Record the coordinate in `changed_blocks`.
5. Increment `water_edit_version` when the logical occupancy changes.

A `set_block(WATER)` call is not the supported way to create water. It clears metadata, so the resulting water block is not silently treated as a permanent source. Water creation and simulation changes must use `set_water`.

A no-op edit should not increment the version unnecessarily. The edit log behavior must remain compatible with existing callers and be covered by tests.

#### `World.set_water`

`World.set_water(x, y, z, level, source=False) -> bool` follows these rules:

- `level <= 0`: change water occupancy to `AIR` if necessary, set level to 0 and clear the source flag.
- `level > 0`: set occupancy to `WATER`, update the level and set the source flag to the supplied value.
- Do nothing if the target chunk is unloaded or `y < 0`.
- Never create a chunk.
- Mark dirty chunks only when occupancy changes between `AIR` and `WATER`.
- Do not mark a mesh dirty for a level-only metadata change.
- Never append simulation writes to `changed_blocks`.
- Never increment `water_edit_version` for internal simulation writes.

Return whether occupancy changed.

### D5. Scheduling — resumable jobs and atomic publication

`world.changed_blocks` is the external-edit log. It is written by `World.set_block`, not by the water solver.

Each frame, the driver runs:

1. `water.consume_changes()`
2. `water.tick()`
3. `world.refresh()` if occupancy changed and the refresh contract requires it.

`consume_changes()` transfers each changed coordinate and its six neighbours into the deduplicated pending-seed queue, then clears the consumed log.

#### D5.1 Job state

At most one region job is active at a time.

The job retains enough state to resume across ticks:

- Stage and captured world version.
- Seed queue and deduplication state.
- Flood frontier and visited cells.
- Region membership.
- Source list.
- Solver distances and BFS frontier.
- Prepared solution and drain set.
- Prepared occupancy changes and affected chunks.

The logical stages are:

1. `flood`
2. `solve`
3. `prepare_commit`
4. `commit` / publication

#### D5.2 Work budget

`max_cells_per_tick` must bound simulation work across flood, solve and commit preparation.

One traversal unit is one queue/frontier pop, including examining up to six neighbours and adding newly discovered cells.

The job must make progress under a positive budget and must preserve intermediate state between frames.

Commit preparation must not hide an unbounded full-region copy or a whole-world scan outside the budget.

#### D5.3 Atomic publication requirement

The original architecture stores logical blocks and metadata in mutable chunk arrays. Applying thousands of cell updates sequentially would exceed the budget and expose a partially updated region unless the implementation introduces a publication mechanism.

Therefore, before implementation, the repository must be inspected to determine how to publish a complete prepared region atomically.

The required semantics are:

- Build the complete new region state privately, over as many ticks as needed.
- Keep the previously published region visible during preparation.
- Publish the new logical state through one atomic region-state publication operation.
- Ensure `World.get_block`, water metadata queries, and the renderer's input observe one consistent published state.
- Only after publication, schedule affected mesh regeneration.
- Do not mutate a portion of the visible region and leave the rest at its previous state.
- Do not claim bounded commit time if publication still applies every cell individually.

A single pointer swap to an immutable published-state object or an equivalent transactional representation may satisfy this requirement, provided the implementation proves compatibility with chunk-authoritative storage and the existing rendering architecture.

If the current architecture cannot support this without a substantial redesign, stop before implementing a weaker solution. Report the precise blocker and the smallest viable architectural change. Do not silently sacrifice atomicity or the work budget.

#### D5.4 Version invalidation

Each job captures `water_edit_version` at start.

Before publication, compare the captured version with the current world version. If they differ:

1. Discard the stale prepared result.
2. Publish none of it.
3. Preserve pending edits and seeds.
4. Restart from the current authoritative state.

The version must increment for external changes that can affect the result, including:

- Occupancy changes.
- Source creation or removal.
- Relevant chunk load/unload changes that alter connectivity or boundary availability.

Simulation-internal water writes must not invalidate their own job.

A global version is acceptable for M13. An unrelated edit may conservatively restart the active job; document and test this. Do not introduce per-chunk versions unless correctness requires them.

#### D5.5 Forward progress and determinism

When external edits stop and the work budget is positive:

- A job must continue making progress on each tick until its queues are exhausted.
- Pending seeds must not be lost during invalidation.
- The final result must match the one-shot reference solver for the same final world state.
- The result must be independent of the per-tick budget.
- A world with no pending seeds and no active job must do no simulation work.

Continuous edits may cause restarts, but must never allow stale publication or a partially updated region.

### D6. Rendering and face culling

Water and solid faces are decided independently.

| Adjacency | Water face | Solid face |
|---|---|---|
| Water / solid | Culled | Rendered |
| Water / water | Culled | Not applicable |
| Water / air | Rendered | Not applicable |
| Solid / air | Not applicable | Rendered |
| Solid / solid | Not applicable | Culled |

In `chunk_mesh.py`, update the transparent water pass to cull a face against a neighbour of the same water block type.

Do not change the opaque pass. Solid faces adjacent to water must remain visible.

Preserve the transparent child Entity and the one-combined-mesh-per-chunk architecture.

### D7. Texture and animation

Keep `voxel_textures/blocks/water.png` unchanged.

The existing Minetest assets are incompatible with the current pipeline:

- Still textures are opaque and would lose transparency without material-alpha changes.
- Animated textures are eight-frame vertical strips.
- The current atlas and static mesh pipeline use a single atlas frame and do not animate UVs.

Water animation is out of scope. Do not change the texture manifest, atlas, texture packer or renderer for this milestone.

### D8. Player interaction semantics

- Breaking a solid block beside water turns it into air and records the edit.
- The next simulation update re-evaluates the affected region.
- Placement remains restricted to `AIR` targets.
- Water is not a valid placement target.
- Water itself remains non-breakable, non-collectable and non-placeable.
- No water item or bucket is added.
- Block edits trigger water re-evaluation through the external edit log.

### D9. Source origin and startup

The existing lake generator continues to determine the lake geometry.

For every generated lake cell:

- Set the block to `WATER`.
- Initialize `water_level` to 8.
- Set `water_source=True` only when `y == lake_level`.
- Set `water_source=False` for lower lake cells.

This ensures the lake begins in a stable state while allowing its derived lower water to drain if no source can support it.

At startup, call `WaterSimulation.seed_all_sources()` once.

The prior deterministic-generator investigation reported 339 lake water cells at y=2–4 for seed 42 and no horizontal outflow candidates. Recheck these figures if the generator changes; do not alter terrain to accommodate water unless the current generation no longer satisfies containment.

---

## 4. Approaches considered

1. **Source-derived 0-1 BFS with resumable jobs and atomic publication — selected.** Deterministic, finite, source-correct, headless-testable, and compatible with bounded preparation work.
2. **Neighbour-relaxation cellular automaton — rejected.** Equal-level cells can sustain one another and recession becomes slow or incorrect.
3. **New source/flowing block types — rejected.** Changes the block enum and inventory while still requiring level metadata.
4. **Physical or particle-based fluid simulation — out of scope.** Unnecessary for the specified voxel behavior and incompatible with the current scope.
5. **Incremental visible mutation of a region — rejected.** It violates atomic publication and can expose partially resolved water.

---

## 5. Interfaces

### `Chunk` (`chunk.py`)

- `get_water_level(x, y, z) -> int`
- `set_water_level(x, y, z, level: int) -> None`
- `get_water_source(x, y, z) -> bool`
- `set_water_source(x, y, z, source: bool) -> None`
- `clear_water(x, y, z) -> None`

Levels are clamped to 0–8.

### `World` (`world.py`) — WaterView

- `changed_blocks: set[tuple[int, int, int]]`
- `water_edit_version: int`
- `is_loaded(world_x, world_y, world_z) -> bool`
- `get_block(world_x, world_y, world_z) -> int`
- `get_water(world_x, world_y, world_z) -> int`
- `is_source(world_x, world_y, world_z) -> bool`
- `set_water(world_x, world_y, world_z, level: int, source: bool = False) -> bool`
- Existing `set_block(...)`, extended with metadata cleanup, external-edit recording and version invalidation.

`get_block` must only be called for loaded cells by the solver.

### `water.py` — no Ursina import

- `MAX_LEVEL = 8`
- `SOURCE_LEVEL = 8`
- `MAX_HORIZONTAL_SPREAD = 32` (configurable per simulation/solve call)
- `DEFAULT_MAX_CELLS_PER_TICK = 65536`
- `is_water(block_type) -> bool`
- `is_passable(block_type) -> bool`
- `is_empty(block_type) -> bool`
- `solve_water_view(view, seeds, max_horizontal_spread=32) -> dict[coord, int]`
- `WaterSimulation(world, max_cells_per_tick=DEFAULT_MAX_CELLS_PER_TICK)`

`WaterSimulation` provides:

- `pending_seeds`
- `active_job`
- `enqueue(x, y, z)`
- `on_block_changed(x, y, z)`
- `consume_changes()`
- `seed_all_sources()`
- `tick() -> int`
- `has_pending_work()`

The internal job persists its stage, captured version, flood queue, region, visited set, sources, distances, solver frontier, prepared solution and prepared publication data.

---

## 6. Non-goals

- New block types, including `WOOD`, or changes to block IDs.
- Inventory, hotbar or UI changes.
- Water placement or collection; buckets.
- Animated water or renderer rewrite.
- Partial-height water geometry or flowing UV scroll.
- Persistence, streaming, biomes or fluid physics beyond the level model.
- Repairing or rewriting earlier milestone documentation.

---

## 7. Acceptance criteria mapping

| Requirement | Design |
|---|---|
| Source and flowing water | D1, D2, D9 |
| Vertical priority and multi-cell drops | D2 |
| Horizontal spread and finite range | D2 |
| Recession, multiple sources and no mutual sustain | D3 |
| Player edits and interaction with air/solid blocks | D4, D8 |
| Metadata cleanup | D4 |
| Cross-chunk propagation | D2, D5 |
| Dirty tracking and neighbouring mesh regeneration | D4, D6 |
| Water internal face culling | D6 |
| Texture compatibility | D7 |
| Resumable bounded processing | D5 |
| Atomic publication | D5.3 |
| Safe invalidation and restart | D5.4 |
| M1–M12 regression and runtime verification | §8 |

---

## 8. Verification plan

Three evidence classes must remain separate.

### 8.1 Automated tests

Run:

`python -m pytest tests -q`

The previous baseline was 96 tests. Record the exact final count and result.

Automated tests must cover water rules, recession, metadata cleanup, culling, chunk boundaries, job invalidation, atomic publication and bounded work.

### 8.2 Startup and smoke tests

Run `python main.py` for a bounded interval, for example 12 seconds.

Verify:

- The window is created.
- Chunks and entities are built.
- No exception is raised.
- Headless smoke tests confirm water levels and face counts.

Smoke tests prove integration, not visual correctness.

### 8.3 Visual verification

Inspect the running game for:

- Lake presence and visible water surface.
- Absence of internal water faces.
- Water flowing after digging beside it.
- Correct behavior at chunk boundaries.
- Correct recession behavior where it can be exercised.

If the environment cannot inspect rendered pixels, report visual verification as **not performed**. Do not infer visual correctness from automated tests or startup success.

---

## 9. Risks and limitations

- `MILESTONES.md` contains a truncated M13 section and must not be repaired as part of unrelated work.
- Water remains flat; level-only changes do not rebuild geometry.
- Water is not placeable or collectable.
- Large regions may span multiple ticks.
- Continuous external edits may restart jobs and delay completion.
- Only the lake's top layer contains permanent sources.
- Atomic publication must be demonstrated against the real world data and renderer architecture before implementation can proceed.
- Visual correctness must be reported honestly.

---

## 10. Decisions retained from revision 4

1. Single `WATER` type and per-Chunk level/source metadata.
2. Source-derived 0-1 BFS, bounded seven-cell horizontal spread and loaded-chunk boundaries.
3. Resumable jobs with bounded per-tick work.
4. Only the lake's top layer contains permanent sources.
5. Keep the existing water texture; no animation.
6. No water placement or collection.
7. Leave the truncated `MILESTONES.md` section unchanged.
8. M13 implementation requires explicit approval.
