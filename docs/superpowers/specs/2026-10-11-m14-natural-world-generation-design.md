# M14 — Natural World Generation: Design Spec

**Date:** 2026-10-11 (rev. 1)
**Milestone:** M14
**Status:** Proposed — awaiting explicit approval before implementation.

**Scope guard:** M14 only. No M15 work, no unrelated refactoring, and no production code or texture changes until this spec and its implementation plan are explicitly approved. M1–M13 behavior must be preserved, with water simulation treated as the highest-risk regression surface.

This spec defines vegetation generation and rendering on top of the existing architecture. It reuses the M10/M11/M12 texture manifest and atlas pipeline and the one-combined-mesh-per-chunk renderer.

---

## 1. Objective

Make the generated world feel natural by adding, deterministically:

- small ground vegetation (grass tufts) as lightweight crossed-plane decorations;
- a single oak-like tree type (trunk + leaf canopy);
- chunk-boundary-safe tree generation with no duplication or missing parts;
- rendering that keeps one combined mesh and one Ursina Entity per rendered terrain chunk (no entity per tuft or leaf);
- automated tests for determinism, placement validity, tree structure, chunk boundaries, non-interference and regeneration, plus separate runtime and visual verification.

The milestone must not disturb the M13 water simulation, the M7/M8 interaction and inventory systems, or the M9–M12 texture pipeline.

---

## 2. Evidence from the current implementation

Investigated directly from the repository (read-only) at design time. The test baseline is `python -m pytest tests -q` → **155 passed**.

| Fact | Evidence |
|---|---|
| Block types are `AIR, GRASS, DIRT, STONE, WATER, SAND` | `block_data.py:17-22` |
| Per-face textures come from the manifest via `texture_config.block_face_textures` | `block_data.py:8,68-72`, `texture_config.py:46-53` |
| `BlockType` values are matched to manifest keys by name in tests | `tests/test_block_data_m9_task3.py:10-12` |
| Block data is independent of rendering; mesh generation consumes block data | `ARCHITECTURE.md:34`, `chunk_mesh.py:54-124` |
| Mesh generation produces one opaque and one transparent (water) vertex list per chunk | `chunk_mesh.py:54-124` |
| One opaque Entity per chunk plus one water child Entity | `chunk_entity.py:57-130` |
| `double_sided=True` and `unlit_shader` are already used for chunk entities | `chunk_entity.py:99-115` |
| The opaque mesh has no alpha handling; only the water child applies a material | `chunk_entity.py:21-36`, `chunk.py:66-124` |
| `Chunk.refresh` rebuilds meshes and re-applies the water material after model reassignment | `chunk.py:66-124`, `chunk_entity.py:118-120` |
| Terrain generation writes only `chunk_y == 0` chunks in `range(-1, 2)` for x/z | `terrain_generation.py:39-100` |
| Surface height is a pure function of `(seed, x, z)` (sine noise; the `random.seed` call is not used by `_noise`) | `terrain_generation.py:102-156` |
| The lake is a deterministic circle (center 0,0; radius 6; floor 2; level 4) | `terrain_generation.py:43-47` |
| Water `is_passable` is `AIR or WATER`; solids (GRASS/DIRT/STONE) are boundaries | `water.py` `is_passable` |
| Raycast ignores non-solid blocks and resolves cross-chunk lookups through `World.get_block` | `raycast.py:11-27,112-128` |
| Player collision only treats solid blocks as blocking | `player.py:837-900` |
| Inventory is generic over `BlockType` (no hardcoded type table) | `inventory.py:19-86` |
| Inventory UI derives icons from `get_block_face_textures` | `inventory_ui.py:74-90` |
| The atlas packer collects only `manifest["blocks"][*].{top,side,bottom}` | `scripts/pack_textures.py:67-75` |
| Available Minetest assets fit the design (measured with Pillow) | see D10 and §2 table |
| The environment cannot inspect rendered pixels | M11/M12/M13 completion reports |

Measured candidate assets (all under `voxel_textures/minetest_textures/`):

| Asset | Size | Mode | Alpha profile |
|---|---|---|---|
| `default_grass_1.png` … `default_grass_5.png` | 64×64 | RGBA | heavy transparency (plant cutout) |
| `default_tree.png` | 128×128 | RGBA | fully opaque (trunk side) |
| `default_tree_top.png` | 128×128 | RGBA | fully opaque (trunk top/bottom) |
| `default_wood.png` | 128×128 | RGBA | fully opaque (alternate trunk) |
| `default_leaves.png` | 128×128 | RGBA | 1461 transparent + 1838 partial pixels (cutout foliage) |
| `default_leaves_simple.png` | 128×128 | RGBA | 1218 transparent + 2668 partial pixels |

No genuinely new external texture is required; the required foliage, trunk and leaf sources already exist in the local Minetest pack.

**Known documentation defect (do not repair here):** the M13 section of `MILESTONES.md` is truncated at `#### 6. Performance`. It must not be modified as part of M14.

---

## 3. Design decisions

### D1. Grass tufts are a per-Chunk decoration layer, not a BlockType

Add a logical, non-rendering decoration layer to `Chunk`, analogous to the M13 water metadata:

- `decorations`: `int8[16,16,16]`; `0` = none, `1..5` = grass tuft variant.

A decoration cell does **not** occupy the block grid. Consequences:

- Player movement is unaffected (collision reads `chunk.blocks`).
- Raycast and block interaction are unaffected (raycast reads `World.get_block`).
- Placement into a plant cell is unaffected (the cell is still `AIR`).
- Water simulation is unaffected (`is_passable` reads `blocks`; the cell is `AIR`).

This guarantees the requirement that decorations "do not obstruct player movement or interfere with block interaction", and it removes all risk to M13 water behavior. It follows the existing precedent of `water_levels` / `water_sources` living on `Chunk` as logical metadata.

**Rejected alternative:** a non-solid `BlockType.GRASS_TUFT`. It would require a third mesh category and would make a plant cell block placement (target must be `AIR`) and change water passability, i.e. it would interfere with interaction and risk M13 regressions.

### D2. Trees are ordinary solid block types: `OAK_LOG` and `OAK_LEAVES`

Add two block types:

- `BlockType.OAK_LOG = 6` — solid, opaque, trunk.
- `BlockType.OAK_LEAVES = 7` — solid, opaque-rendered-but-alpha-cutout (see D6), canopy.

Both are `is_solid=True` and `is_transparent=False`. Consequences:

- Trees collide, are raycast-selectable, breakable and collectable through the existing M7/M8 systems with no new code.
- Water treats them as boundaries (`is_passable` false), which is the existing behavior for all solids; no water code change is required.
- `inventory`/`inventory_ui`/`hotbar` work generically because item type equals block type.

Leaf decay, tree falling and leaf physics are explicitly **out of scope** (see §8). Breaking any tree block removes only that block; no cascade.

**Rejected alternative:** store trees as decorations too. The trunk must be solid for collision and interaction, so it must be a block. Keeping the trunk and canopy as blocks keeps trees within the existing systems.

### D3. Rendering: one combined mesh and one Entity per chunk, with alpha-cutout foliage

All solid blocks (terrain, trunk, leaves) and all crossed-plane grass tufts are merged into the **existing opaque** vertex/triangle/UV lists produced by `generate_chunk_mesh_split`. The water split is unchanged.

- Grass tufts emit two crossed vertical quads (four triangles) per decoration cell.
- The opaque chunk Entity receives an alpha-test ("cutout") render state so transparent texels are discarded: `TransparencyAttrib.M_binary`, `double_sided` (already set), depth write/test left on.
- Terrain tiles are fully opaque (alpha 255), so the cutout state does not change existing terrain, grass-side, stone, sand or water rendering.
- Water stays on the existing transparent child Entity with `apply_water_material`.

This preserves "one combined mesh and one Ursina Entity per rendered terrain chunk" and creates no Entity per tuft or leaf. It also avoids a third per-chunk Entity.

**Verification/risk:** the exact alpha-test threshold and its compatibility with `unlit_shader` must be confirmed at runtime (see §9.3). If `TransparencyAttrib.M_binary` cannot be made to cut out foliage cleanly, the documented fallback is to render leaves/plants fully opaque and record the visual limitation; a blended foliage child Entity is a last resort that must be re-approved because it adds a per-chunk Entity.

### D4. Determinism: pure arithmetic hash over `(seed, x, z, salt)`

No generation decision may depend on iteration order, chunk load order, wall-clock state, or the global `random` module. Generation uses a small, explicit integer hash:

- `hash32(seed, x, z, salt) -> uint32`, implemented with fixed arithmetic (e.g. splitmix-style mixing) and 32-bit masking. Python's built-in `hash()` must not be used because it is salted per process.
- Surface height reuses the existing pure `(seed, x, z)` terrain formula; the terrain generator's lake test is reused so vegetation and terrain agree on what counts as grass/water.
- `random.seed(...)` must not be called by vegetation code.

### D5. Grass tuft placement rule

For each column `(x, z)` in a chunk (chunk-local `x,z`, world `gx = chunk_x*16 + x`, `gz = chunk_z*16 + z`):

1. Let `surface = surface_height(seed, gx, gz)`.
2. Skip the column if `in_lake(gx, gz)`.
3. Skip if `surface + 1 > 15` (no room inside `chunk_y == 0`).
4. Require the block at `(x, surface, z)` to be `GRASS` and the block at `(x, surface+1, z)` to be `AIR` (i.e. valid exposed ground, not water, not occupied by a tree).
5. Let `r = hash32(seed, gx, gz, PLANT_SALT) % 100`. Place a tuft only if `r < GRASS_DENSITY_PERCENT` (default 30).
6. Variant `v = 1 + hash32(seed, gx, gz, VARIANT_SALT) % 5` (`default_grass_1..5.png`).
7. Set `chunk.set_decoration(x, surface + 1, z, v)`.

Trees (D7) are written before tufts within each chunk so a tuft is never placed inside a trunk that occupies `surface+1`.

### D6. Leaf/tuft cutout rendering detail

- Grass tuft quads: two quads across the cell diagonals, inset by `0.05` on each axis to avoid z-fighting with adjacent cube faces. Both quads span the full cell height `y..y+1` and use the full tile UVs of the variant.
- Leaves: rendered as normal cube faces (in the opaque pass) using the leaf tile UVs; the cutout state turns the leaf texture's transparent texels into holes.
- Face culling for solid cubes is unchanged (a leaf face against a solid leaf is culled; a leaf face against air is emitted).

### D7. Tree shape and placement

An oak-like tree is defined by a deterministic anchor and shape.

**Anchors and spacing.** Candidate anchors lie on a world-space grid of `TREE_GRID = 6` blocks. Each anchor is jittered inside its cell by `hash32` into `[TREE_JITTER_MIN, TREE_JITTER_MAX] = [2, 3]` on each axis. The canopy horizontal radius is `CANOPY_RADIUS = 2` (a 5×5 bounding box) and the trunk is a 1×1 column at the origin. With these constants adjacent anchors are at least `TREE_GRID + TREE_JITTER_MIN - TREE_JITTER_MAX = 5` blocks apart and, more strongly, every footprint lies inside its own grid cell (D7.1), so footprints cannot overlap. A tree exists at an anchor with probability `TREE_DENSITY_PERCENT` (default 35), decided by `hash32(seed, gx, gz, TREE_SALT) % 100`.

`TREE_GRID = 6` is chosen deliberately so that grid cells — and therefore tree footprints — straddle chunk boundaries: `CHUNK_SIZE = 16` is not a multiple of `6`, so trees genuinely cross X and Z chunk boundaries and can span a chunk corner (D7.3). `TREE_JITTER_MAX = 3` is the largest jitter that still keeps every footprint inside its own grid cell for `TREE_GRID = 6` (D7.1). Together these constants give both non-overlap and real cross-chunk coverage.

**Dimensions.** Trunk height `H ∈ {4,5,6}` from `hash32(seed, gx, gz, HEIGHT_SALT)`. Trunk is a 1×1 column of `OAK_LOG` from `surface+1` to `surface+H`.

**Canopy layers** (relative to the trunk base `b = surface`), each cell placed only where expected-air (see below):

- `y = b+H-2` and `y = b+H-1`: full 5×5 footprint minus the four corners (blob).
- `y = b+H`: full 3×3.
- `y = b+H+1`: a plus/cross of 5 cells (or 1 cell) — deterministic choice from `hash32`.

**Suitability (all evaluated from pure functions; no neighbour chunk reads):**

1. `not in_lake(gx, gz)` where `gx,gz` is the anchor column.
2. `surface` at the anchor maps to `GRASS` (true for every non-lake column by the terrain rule).
3. `surface + H + 1 <= 15` (the whole tree fits in `chunk_y == 0`).
4. The anchor column is at least `CANOPY_RADIUS + 1` cells away from the lake circle so leaves never hang over water.
5. Every intended tree cell `(cx, cy, cz)` must satisfy `cy > surface_height(seed, cx, cz)` and `not in_lake(cx, cz)`. This deterministically prevents leaves or trunk from being generated inside terrain or over water.

**Writing rule.** A tree block is written into the chunk that owns its world coordinate, and only when (a) the writing candidate is that cell's owner under D7.2 and (b) the target block is currently `AIR`. The trunk is written before the canopy so leaves never replace the trunk. Decoration in that cell is cleared. No terrain or water block is ever replaced.

Rule (b) is a safety property, not the determinism argument: determinism comes from the ownership rule (a) and the non-overlap proof in D7.1, both of which are pure functions of the cell coordinate. Arrival order never decides a cell's value.

#### D7.1 Non-overlap proof (every allowed tree shape, trunk included)

Let a candidate anchor sit in grid cell `(i, j)` with
`origin_x = TREE_GRID*i + jx` and `origin_z = TREE_GRID*j + jz`, where
`jx, jz ∈ [TREE_JITTER_MIN, TREE_JITTER_MAX] = [2, 3]`.

Every canopy layer is bounded by `CANOPY_RADIUS = 2` in each horizontal direction
(the 5×5 layers have half-width 2; the 3×3 and plus layers have half-width 1), and the
trunk is a 1×1 column at the origin. The whole footprint is therefore contained in
`[origin_x - R, origin_x + R] × [origin_z - R, origin_z + R]` with `R = CANOPY_RADIUS = 2`, and

- `origin_x - 2 = TREE_GRID*i + (jx - 2) ∈ [TREE_GRID*i, TREE_GRID*i + 1]`
- `origin_x + 2 = TREE_GRID*i + (jx + 2) ∈ [TREE_GRID*i + 4, TREE_GRID*i + 5]`

so with `TREE_GRID = 6` every tree cell `(cx, *, cz)` satisfies

`6i ≤ cx ≤ 6i + 5` and `6j ≤ cz ≤ 6j + 5`.

**Lemma (footprint containment).** Every tree's horizontal footprint lies entirely
inside its own `TREE_GRID` cell and never touches a grid-cell boundary. Both defining
inequalities hold, with zero slack:

- `TREE_JITTER_MIN - R = 2 - 2 = 0 ≥ 0`
- `TREE_JITTER_MAX + R = 3 + 2 = 5 ≤ TREE_GRID - 1 = 5`

**Theorem (non-overlap).** Grid cells partition the plane. By the lemma each
footprint is a subset of its own cell, so the footprints of distinct anchors are
disjoint. No world cell can be claimed by two trees: **overlap is impossible**, not
merely unlikely. The bound applies to the complete shape including the trunk, because
the trunk and every canopy layer satisfy the same containment inequality.

**Corollary (spacing).** Adjacent anchors along one axis are at least
`TREE_GRID + TREE_JITTER_MIN - TREE_JITTER_MAX = 5` blocks apart, which equals the
canopy box width `2R + 1 = 5`. Adjacent 5×5 canopy boxes are therefore adjacent without
overlapping and without sharing a cell.

**Consequences.**

- `TREE_JITTER_MAX = 3` is the largest admissible jitter for `TREE_GRID = 6`: raising
  it to 4 breaks the second inequality and lets a footprint leave its grid cell. Any
  future change to `TREE_GRID`, the jitter range or `CANOPY_RADIUS` must re-check both
  inequalities before non-overlap can be relied on again.
- The `AIR`-only write rule is **not** what makes generation order-independent.
  Non-overlap is proven from geometry, and D7.2 states the ordering guarantee
  explicitly instead of leaving it accidental.

#### D7.2 Deterministic ownership rule

So that each cell's value is a pure function of the world coordinate — and stays so
if `TREE_GRID`, the jitter range or `CANOPY_RADIUS` are retuned — the write predicate
is defined by ownership rather than by arrival order:

- For a world cell `(cx, cy, cz)`, the **owning candidate** is the anchor whose
  footprint contains that cell.
- If more than one anchor contained it, the owner is the candidate with the
  lexicographically smallest `(grid_x, grid_z)`; this is a total, order-independent
  tie-break.
- A candidate writes a cell only when it is that cell's owner.

Because D7.1 proves that every footprint is a subset of its own grid cell, the owner
reduces to a closed form using floor division (correct for negative coordinates):

`cell_owner(cx, cy, cz, seed) = (cx // TREE_GRID, cz // TREE_GRID)`

No search and no neighbouring-chunk read is needed, and `tree_owns_cell(candidate,
cx, cy, cz, seed)` is exactly

`(cx // TREE_GRID, cz // TREE_GRID) == (candidate["grid_x"], candidate["grid_z"])`

The containment-plus-tie-break rule above is the definition; the closed form is the
proof that it is unique and O(1) under the adopted constants. Ownership is therefore
independent of which chunk is generated first and of the order candidates are
visited: each cell has exactly one owner, computed from the cell's own coordinates.

#### D7.3 Cross-chunk trees (X, Z and corner crossing)

`CHUNK_SIZE = 16` is **not** a multiple of `TREE_GRID = 6`, so grid cells do not align
with chunk boundaries and trees genuinely cross them. Grid cell `i = 2` spans
`x ∈ [12, 17]`, straddling the boundary at `x = 16`; the same construction applies on Z.

- **X-boundary tree:** a footprint whose `x` range spans two chunk columns, for
  example grid `i = 2` — `x ∈ [12, 17]`.
- **Z-boundary tree:** a footprint whose `z` range spans two chunk rows.
- **Corner-crossing tree:** a footprint that spans an `x` boundary *and* a `z`
  boundary, for example grid cell `(2, 2)` — `x ∈ [12, 17], z ∈ [12, 17]` — which
  occupies all four chunks `(0,0), (1,0), (0,1), (1,1)`.

These cases are bounded, not open-ended: a 6-wide span contains at most one boundary
when boundaries are 16 apart, so a footprint spans **at most 2 chunks per axis and at
most 4 chunks in total**. Each involved chunk computes the same deterministic tree
independently from `(seed, coordinates)` and writes only the cells it owns (D7.2), so
the tree is complete and unique once all involved chunks have been generated.

### D8. Chunk-boundary safety and order independence

`generate_vegetation_for_chunk(chunk, seed)` scans the anchor grid cells whose footprint can intersect this chunk and writes only the cells this chunk owns. Because `TREE_GRID = 6` does not divide `CHUNK_SIZE = 16`, this padding is load-bearing: for a chunk spanning `[chunk_min, chunk_max]` along an axis, the scan range is

`range(chunk_min // TREE_GRID - 1, chunk_max // TREE_GRID + 2)`

which is a superset of every grid cell whose footprint intersects that chunk (verified exhaustively for chunk indices from `-8` to `8`).

Consequences:

- Each cell's writer is fixed by the D7.2 ownership rule, a pure function of the world coordinate, so a chunk's output depends only on `(seed, chunk coordinates)` and the terrain function — never on which neighbours are loaded or on generation order.
- A tree crossing an X boundary, a Z boundary or a chunk corner has its cells written by each chunk that owns them, and each part is written exactly once. When every involved chunk has been generated the tree is complete, with no duplicated trunk and no missing part, regardless of the order in which those chunks were generated.
- A tree's suitability is decided from pure functions only (D7), so a chunk never reads a neighbouring chunk's data to decide whether part of a tree belongs to it.
- Decorations are strictly per-column and per-chunk, so they are inherently boundary-safe.

### D9. Interaction with block edits and regeneration

- `World.set_block(x,y,z,type)` additionally clears any decoration at `(x,y,z)` (placing a block removes a tuft in that cell) and, when the new block is non-solid (not a plant support), clears any decoration directly above at `(x,y+1,z)` so a tuft cannot float after its support is removed.
- Existing dirty-chunk and boundary-neighbour marking is preserved, so the affected chunk mesh (including foliage) is regenerated.
- `Chunk.refresh()` must re-apply the foliage cutout state after reassigning the opaque model, mirroring the existing water-material re-application.
- Vegetation generation is a startup/terrain-generation step; it is not re-run on mesh refresh. Deterministic regeneration means re-running `generate_vegetation` on the same seed produces identical data.

### D10. Textures and atlas

- Reuse the local Minetest sources. No new external or derived texture is required.
- Add manifest `blocks` entries for `OAK_LOG` (top/bottom `default_tree_top.png`, side `default_tree.png`) and `OAK_LEAVES` (all faces `default_leaves.png`).
- Extend the manifest with a new top-level `decorations` object mapping variant names to `default_grass_1..5.png`, and extend `scripts/pack_textures.collect_sources` to collect those paths. `texture_config` gains a `decoration_textures()` accessor.
- Regenerate `voxel_textures/gen_atlas.png` and `voxel_textures/atlas_map.json` with the existing packer (2 px padding, `nearest`, ≤ 2048). WATER remains unchanged.
- Manifest path casing follows the existing entries (`voxel_textures/MINETEST_TEXTURES/...`); this resolves on the Windows checkout (case-insensitive).

### D11. Interface summary

`chunk.py`

- `decorations: int8[16,16,16]`
- `get_decoration(x, y, z) -> int`
- `set_decoration(x, y, z, value) -> None`
- `clear_decoration(x, y, z) -> None`

`terrain_generation.py` (pure helpers; methods delegate)

- `LAKE_CENTER_X, LAKE_CENTER_Z, LAKE_RADIUS, LAKE_FLOOR, LAKE_LEVEL` (module constants)
- `surface_height(seed, x, z) -> int`
- `in_lake(x, z) -> bool`
- `TerrainGenerator.generate_world(world)` calls vegetation generation after terrain (lazy import to avoid a cycle).

`vegetation.py` (new; headless, no Ursina import)

- constants: `DECORATION_NONE`, grass/tree grid/jitter/density/salt constants, canopy radius.
- `hash32(seed, x, z, salt=0) -> int`
- `tree_candidate(gx, gz, seed) -> dict | None` (keys: `grid_x`, `grid_z`, `origin_x`, `origin_z`, `surface`, `height`)
- `tree_blocks(origin_x, origin_z, surface, height, seed) -> list[(x,y,z,BlockType)]`
- `cell_owner(cx, cy, cz, seed) -> tuple[int, int] | None` (the owning `(grid_x, grid_z)`; closed form `(cx // TREE_GRID, cz // TREE_GRID)`, or `None` when that grid cell has no candidate; D7.2)
- `tree_owns_cell(candidate, cx, cy, cz, seed) -> bool` (`cell_owner(...) == (candidate["grid_x"], candidate["grid_z"])`)
- `generate_vegetation_for_chunk(chunk, seed) -> None`
- `generate_vegetation(world, seed) -> None`

`chunk_mesh.py`

- `generate_chunk_mesh_split` merges decoration crossed-planes into the opaque lists.
- `_add_cross_planes(vertices, triangles, uvs, x, y, z, variant, atlas_map)`.
- decoration UV lookup from the atlas map's decoration tile paths.

`chunk_entity.py`

- `apply_foliage_cutout(entity) -> None` (alpha-test state on the opaque entity).

`world.py`

- `set_block` decoration cleanup (D9).

---

## 4. Approaches considered

1. **Separate decoration layer + solid tree block types + merged opaque cutout mesh — selected.** Isolates decorations from all block-based systems (movement, raycast, placement, water), keeps trees fully within the existing block systems, and preserves one mesh/one Entity per chunk.
2. **Non-solid `GRASS_TUFT` block type — rejected.** Interferes with placement and water passability and adds regression risk to M13.
3. **Third per-chunk Entity for foliage — rejected as the primary approach.** Adds a per-chunk Entity beyond the established opaque+water pair; only a re-approved fallback.
4. **Per-tuft/per-leaf Ursina Entities — rejected.** Explicitly forbidden by the milestone and by the architecture invariants.
5. **Random-walk / Poisson tree scattering — rejected.** Harder to make order-independent and boundary-safe than a fixed jittered grid with a pure hash.
6. **Reading neighbouring chunks during tree generation — rejected.** Makes results depend on load order and violates the determinism requirement. The pure-function suitability test removes the need.

---

## 5. Testing strategy

Two evidence classes, kept separate.

### 5.1 Automated tests (`python -m pytest tests -q`)

New/updated test modules:

- `tests/test_vegetation_determinism.py` — same seed ⇒ identical blocks and decorations; permuted chunk-generation order ⇒ identical output; `hash32` is stable and not the builtin hash.
  The order-independence assertion compares the chunk **key sets** first and then each corresponding `blocks` and `decorations` array with `numpy.array_equal`. It must never compare dictionaries or tuples of NumPy arrays with `==`, which yields an array rather than a single Boolean and raises on truth-value ambiguity. The test fails only when the generated data actually differs.
- `tests/test_vegetation_placement.py` — tufts only above `GRASS` with `AIR` above; none over lake/water/sand/stone; none above `y=15`; density is within expectation for a large sample.
- `tests/test_tree_structure.py` — trunk is a contiguous `OAK_LOG` column of height 4–6 on grass; canopy is `OAK_LEAVES` with the specified layer shape; no leaf/trunk cell is inside terrain; no tree anchor inside/near the lake.
- `tests/test_tree_chunk_boundaries.py` — a deterministic search over grid cells finds, for seed 42, at least one X-boundary-crossing, one Z-boundary-crossing and one corner-crossing candidate (D7.3); the search asserts these cases exist, so the suite cannot silently degrade into containment-only coverage. For each case every involved chunk is generated in several different orders and the per-chunk `blocks` **and** `decorations` arrays are compared across orders with `numpy.array_equal` over a matching chunk key set. For each case the complete tree is present exactly once across the generated chunks (trunk cells matching the candidate height, canopy present, no duplicate trunk, no missing part) and each chunk contains only the cells it owns. A separate check asserts that every cell of a generated world has exactly one owner under the D7.2 closed form.
- `tests/test_vegetation_mesh.py` — a decoration cell emits 4 triangles (2 quads) with valid in-atlas UVs; leaf/log cubes emit normal faces; existing opaque/UV orientation for GRASS is unchanged; chunk-boundary culling still uses `World` neighbours.
- `tests/test_vegetation_interaction.py` — raycast ignores tuft cells; player collision ignores tuft cells; `World.set_block` clears a tuft in the target cell and clears a tuft above a removed support; and the full reproducible water-preservation protocol of §5.2.
- `tests/test_m14_textures.py` — all new manifest references resolve; `default_tree.png`, `default_tree_top.png`, `default_leaves.png` and `default_grass_1..5.png` exist with the expected sizes; atlas includes the new tiles; UV rects valid and inside the atlas; WATER unchanged.

The existing suite (baseline 155 passed) must continue to pass, including all M13 water tests.

### 5.2 Water-preservation before/after protocol (reproducible)

Water is the highest-risk regression surface, so its verification must be
reproducible: the same seed, the same initial world and water setup, the same number
of simulation steps and the same measurement method on both sides, so that the only
difference between the two runs is vegetation.

**Construction** — one helper builds both worlds and the only variable is the flag:

```python
import random
from world import World
from terrain_generation import TerrainGenerator
import vegetation


def build(seed=42, with_vegetation=True):
    world = World()
    generator = TerrainGenerator()
    generator.seed = seed
    random.seed(seed)                              # matches generate_world
    generator._generate_height_map_terrain(world)  # identical terrain + lake + metadata
    if with_vegetation:
        vegetation.generate_vegetation(world, seed)
    return world
```

Both branches call the same terrain function, so the terrain, the lake and the M13
water metadata are identical before vegetation is added.

**Measurement** — pure functions over logical chunk data, with no rendering:

```python
from block_data import BlockType


def water_cells(world):
    return sum(int((c.blocks == BlockType.WATER).sum()) for c in world.chunks.values())


def water_level_total(world):
    return sum(int(c.water_levels.sum()) for c in world.chunks.values())


def water_source_count(world):
    return sum(int(c.water_sources.sum()) for c in world.chunks.values())
```

**Simulation steps** — identical on both sides: seed all sources once, then a fixed
number of ticks at the same budget.

```python
from water import WaterSimulation

STEPS = 200


def simulate(world):
    sim = WaterSimulation(world)
    sim.seed_all_sources()
    for _ in range(STEPS):
        sim.consume_changes()
        sim.tick()
    return sim
```

**Assertions.**

1. *Pre-simulation identity.* `build(42, False)` and `build(42, True)` report identical
   `water_cells`, `water_level_total` and `water_source_count`. Adding vegetation may
   not create, remove, move or re-level a single water cell.
2. *No vegetation on water.* In the vegetated world, no decoration cell and no
   `OAK_LOG` or `OAK_LEAVES` block occupies a `WATER` cell.
3. *Passability.* `water.is_passable` is unchanged for every pre-existing block type
   (`AIR`, `WATER` `->` `True`; `GRASS`, `DIRT`, `STONE`, `SAND` `->` `False`), and both
   new types are non-passable. Cell-wise, passability may change only from passable to
   non-passable (terrain `AIR` becoming a solid tree block); no cell may change from
   non-passable to passable. That is the precise meaning of "adding vegetation does not
   change water passability" for a world that gains solid blocks.
4. *Post-simulation identity.* `simulate(build(42, False))` and
   `simulate(build(42, True))` report identical `water_cells`, `water_level_total` and
   `water_source_count` under equivalent conditions (equal seed, equal initial state,
   equal `STEPS`, equal budget).

`water.py` and the water rendering path are out of scope and must not be modified, and
no existing water test may be weakened to accommodate this milestone.

### 5.3 Runtime and visual verification (separate from automated tests)

Runtime smoke:

- `python main.py` for a bounded interval (~12 s). Confirm window creation, chunk entities built, player spawned, no exception, and that decorated chunks build a mesh.
- Headless smoke: generate a seeded world, count decorations and tree blocks and assert non-zero and bounded, then run the §5.2 before/after protocol to show that water cell counts, level totals and source counts are identical with and without vegetation.

Visual verification (attempt; report honestly):

- Trees and grass tufts visible, upright, alpha-cutout with no black boxes.
- No per-tuft/per-leaf Entities (assert the chunk has exactly the opaque Entity plus the existing water child).
- No atlas bleeding or seams at block/chunk boundaries.
- Water and terrain look unchanged.

If the environment cannot inspect rendered pixels (as in M11–M13), report visual verification as **not performed** and do not infer visual correctness from automated tests or startup success.

---

## 6. Acceptance criteria mapping

| Requirement | Design |
|---|---|
| Grass tufts / small ground vegetation | D1, D3, D5, D6 |
| Trees (one oak type: trunk + canopy) | D2, D7 |
| Deterministic placement from the seed | D4, D5, D7, D8 |
| Order- and load-order independence | D4, D8 |
| Trees consistent across X, Z and corner chunk boundaries, no duplication/missing parts | D7.1, D7.2, D7.3, D8 |
| Deterministic tree conflict handling | D7.1, D7.2, D7.3 |
| Vegetation only on suitable exposed ground | D5, D7 |
| Decorations do not obstruct movement or block interaction | D1 |
| Reuse textures/atlas; identify genuinely new textures | D10 (none needed) |
| One combined mesh and one Entity per chunk; no entity per tuft/leaf | D3 |
| Prevent trees underwater / inside terrain / unsuitable spots | D7 |
| Trees integrate with existing blocks and future edits | D2, D9 |
| Automated tests for determinism, placement, structure, boundaries, collisions, regeneration | §5.1 |
| Preserve M1–M13, especially water | D1, D2, §5.2 |

---

## 7. Non-goals

- More than one tree type (only oak-like).
- Biomes, flowers, tall grass variants beyond `default_grass_1..5`, crops, shrubs.
- Leaf decay, tree falling, sapling growth, tree regrowth.
- Animated foliage.
- New item types, tools, crafting or gameplay around wood/leaves.
- Water changes, buckets, or fluid interaction with vegetation.
- World streaming, dynamic chunk loading, persistence.
- A renderer rewrite, per-block Entities, LOD or greedy meshing.
- Changes to block IDs of existing types or to existing texture assignments.
- Repairing the truncated M13 documentation.

---

## 8. Risks, limitations and open questions

- **Alpha-test support.** `TransparencyAttrib.M_binary` must cut out foliage cleanly with `unlit_shader`. This is verified at runtime; the fallback (fully opaque leaves/plants) is documented in D3 and must be recorded as a limitation if used.
- **Leaves are solid.** The player collides with and can stand on leaves; this is a deliberate simplification.
- **No leaf decay.** Floating leaves after a trunk is broken are expected and out of scope.
- **Atlas growth.** New tiles increase the atlas size but stay far below the 2048 maximum; must be confirmed by the packer output.
- **Tree density near the lake.** Trees are excluded within `CANOPY_RADIUS + 1` of the lake circle; the immediate shoreline stays tree-free.
- **Visual verification** may be unavailable in this environment and must be reported honestly.
- **Open question (resolved by decision, confirm at review):** leaf solidity (chosen solid) and the `TREE_DENSITY_PERCENT` default (35%) are tuning parameters. `TREE_GRID = 6` and the jitter range `[2, 3]` are **not** free tuning parameters: they are the values that simultaneously satisfy the D7.1 non-overlap inequalities and produce the cross-chunk coverage D7.3 requires. Changing either requires re-checking both inequalities and re-confirming that X, Z and corner-crossing trees still exist.
- **Open question (confirm at review):** whether the packed atlas should place decoration tiles before/after block tiles is irrelevant to correctness because tiles are keyed by manifest path; the packer's existing deterministic sort governs it.

---

## 9. Decisions requiring explicit approval before implementation

1. Grass tufts as a `Chunk` decoration layer (D1).
2. `OAK_LOG` / `OAK_LEAVES` as new solid block types (D2).
3. Foliage merged into the opaque mesh with an alpha-test cutout, preserving one mesh/one Entity per chunk (D3, D6).
4. Pure-hash determinism and pure-function tree suitability (D4, D7).
5. Reusing the local Minetest assets with no new textures (D10).

Implementation must not begin until this spec and the implementation plan are approved.
