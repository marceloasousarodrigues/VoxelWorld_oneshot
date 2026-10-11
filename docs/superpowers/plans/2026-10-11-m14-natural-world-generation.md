# M14 Natural World Generation Implementation Plan

> **For agentic workers:** Follow the repository's Superpowers workflow. Read the required skills before starting. Use `subagent-driven-development` or `executing-plans` only if appropriate to the actual environment. For this project, execute tasks sequentially and do not launch parallel subagents.

**Goal:** Add deterministic natural-world vegetation — alpha-cutout grass tufts and a single oak-like tree (trunk + canopy) — that generate consistently across chunk boundaries and render inside the existing one-combined-mesh / one-Entity-per-chunk pipeline, without disturbing M1–M13 behavior (especially water).

**Architecture:** Grass tufts live in a new per-`Chunk` decoration layer (like M13 water metadata) so they never enter the block grid and cannot interfere with collision, raycast, placement or water. Trees are two new solid block types (`OAK_LOG`, `OAK_LEAVES`). All foliage geometry is merged into the existing opaque chunk mesh; the opaque Entity receives an alpha-test cutout state. Generation is a pure function of `(seed, world coordinates)` so it is independent of chunk order and load order.

**Tech stack:** Python 3.14, NumPy, pytest; Ursina/Panda3D for rendering only. Vegetation and mesh logic must be Ursina-free and headless-testable.

**Spec:** `docs/superpowers/specs/2026-10-11-m14-natural-world-generation-design.md`

## Global constraints

- Do not change existing block IDs or the existing `AIR, GRASS, DIRT, STONE, WATER, SAND` semantics. Only append `OAK_LOG = 6`, `OAK_LEAVES = 7`.
- Do not modify `voxel_textures/blocks/water.png`, the WATER manifest entry, or any water rendering behavior.
- Do not add a non-solid plant block type.
- Preserve one combined opaque mesh and one Ursina Entity per rendered terrain chunk; preserve the existing single water child Entity. Do not create a third per-chunk Entity without re-approval.
- Preserve `Chunk` block data as authoritative; decorations are logical metadata consumed by mesh generation.
- Do not call `random.seed` or Python's builtin `hash()` in vegetation code.
- All generation decisions must be pure functions of `(seed, x, z, salt)` or identical to the terrain height function.
- Tree footprints are non-overlapping by construction (spec D7.1) and a cell is written only by its spec-D7.2 owner. Determinism must not rest on the order in which candidates are visited, and no vegetation code may read neighbouring chunk data.
- Execute tasks sequentially. Do not launch parallel subagents.
- Do not change global OpenCode configuration or agent definitions.
- Do not modify production code before the design and plan receive explicit approval.
- Existing test baseline: `python -m pytest tests -q` → **155 passed** (verified at design time).
- Constants: `TREE_GRID = 6`, `TREE_JITTER_MIN = 2`, `TREE_JITTER_MAX = 3`, `TREE_DENSITY_PERCENT = 35`, `GRASS_DENSITY_PERCENT = 30`, `CANOPY_RADIUS = 2`, trunk height `4..6`, cutout threshold from `TransparencyAttrib.M_binary`. `TREE_GRID = 6` with jitter `[2, 3]` is required, not merely default: it is the largest jitter that keeps every footprint inside its own grid cell (non-overlap) while `CHUNK_SIZE = 16` is not a multiple of `6`, so trees really do cross X and Z chunk boundaries and can span a corner.

## Review focus

Each of the following failure modes must have a test in its owning task:

1. The same seed with permuted chunk-generation order produces identical blocks and decorations.
2. A tuft is never placed over water, sand, stone or a non-`GRASS` surface, nor floating in mid-air.
3. A tree's trunk and canopy are complete, contiguous and never generated inside terrain or over water.
4. An X-boundary-crossing, a Z-boundary-crossing and a corner-crossing tree each generate completely and exactly once across every chunk they touch, in any chunk generation order; no cell is claimed by two trees; no duplicate trunk and no missing canopy part.
5. A decoration cell emits crossed planes in the chunk mesh and no per-tuft Entity is created.
6. A leaf/log cube culls and renders faces exactly like existing solid blocks; existing GRASS UV orientation is unchanged.
7. Breaking a support clears the decoration above it; placing into a tuft cell clears the tuft; water `is_passable` is unchanged.
8. The spec §5.2 before/after protocol passes: with an identical seed, identical initial world and water setup, identical simulation steps and an identical measurement method, water cell counts, level totals and source counts are identical with and without vegetation, and passability only narrows.
9. All new manifest references resolve and the regenerated atlas contains the new tiles while WATER is unchanged.

---

## File structure

### Create

- `vegetation.py` — deterministic hashing, tuft placement, tree shape/placement, per-chunk and world generation. No Ursina import.
- `tests/test_vegetation_determinism.py`
- `tests/test_vegetation_placement.py`
- `tests/test_tree_structure.py`
- `tests/test_tree_chunk_boundaries.py`
- `tests/test_vegetation_mesh.py`
- `tests/test_vegetation_interaction.py`
- `tests/test_m14_textures.py`

### Modify

- `chunk.py` — decoration layer and accessors; re-apply cutout state after refresh.
- `terrain_generation.py` — module-level pure `surface_height` / `in_lake` / lake constants; call vegetation generation after terrain.
- `block_data.py` — add `OAK_LOG`, `OAK_LEAVES`, and their properties.
- `config/texture_manifest.json` — add `OAK_LOG` / `OAK_LEAVES` block entries and a `decorations` section.
- `scripts/pack_textures.py` — collect `decorations` sources.
- `texture_config.py` — expose `decoration_textures()`.
- `chunk_mesh.py` — emit crossed planes into the opaque lists; decoration UV lookup.
- `chunk_entity.py` — `apply_foliage_cutout`.
- `world.py` — `set_block` decoration cleanup.
- `voxel_textures/gen_atlas.png`, `voxel_textures/atlas_map.json` — regenerated by the packer (not hand-edited).
- `MILESTONES.md` — M14 completion report in the final task only.

### Not modified

`water.py`, `raycast.py`, `player.py`, `inventory.py`, `inventory_ui.py`, `highlight.py`, `coordinate_system.py`, and all existing textures except the regenerated atlas outputs.

---

## Task 1 — Chunk decoration storage layer

**Files**
- Modify: `chunk.py`
- Test: `tests/test_vegetation_placement.py`

**Interfaces produced**

- `Chunk.decorations` (`int8[16,16,16]`, starts at 0)
- `Chunk.get_decoration(x, y, z) -> int`
- `Chunk.set_decoration(x, y, z, value) -> None`
- `Chunk.clear_decoration(x, y, z) -> None`

### Step 1 — Write failing tests

```python
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from chunk import Chunk


def test_decoration_defaults_and_roundtrip():
    c = Chunk(0, 0, 0)
    assert c.get_decoration(1, 2, 3) == 0
    c.set_decoration(1, 2, 3, 4)
    assert c.get_decoration(1, 2, 3) == 4


def test_clear_decoration_resets_to_none():
    c = Chunk(0, 0, 0)
    c.set_decoration(0, 0, 0, 2)
    c.clear_decoration(0, 0, 0)
    assert c.get_decoration(0, 0, 0) == 0


def test_decoration_layer_does_not_touch_blocks():
    c = Chunk(0, 0, 0)
    c.set_decoration(5, 5, 5, 3)
    assert c.get_block(5, 5, 5) == 0  # AIR unchanged
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_placement.py -q`

Expected: failure; the decoration array and accessors do not exist.

### Step 3 — Implement

In `Chunk.__init__`, add `self.decorations = np.full((SIZE_X, SIZE_Y, SIZE_Z), 0, dtype=np.int8)` alongside `blocks`. Add the three accessors. No existing method changes.

### Step 4 — Verify

Run the same targeted command. Expected: PASS.

### Step 5 — Commit

```bash
git add chunk.py tests/test_vegetation_placement.py
git commit -m "feat(m14): add per-chunk decoration layer"
```

---

## Task 2 — Pure terrain helpers and deterministic hash

**Files**
- Modify: `terrain_generation.py`
- Create: `vegetation.py`
- Test: `tests/test_vegetation_determinism.py`

**Interfaces produced**

- `terrain_generation.LAKE_CENTER_X, LAKE_CENTER_Z, LAKE_RADIUS, LAKE_FLOOR, LAKE_LEVEL`
- `terrain_generation.surface_height(seed, x, z) -> int`
- `terrain_generation.in_lake(x, z) -> bool`
- `vegetation.hash32(seed, x, z, salt=0) -> int`

### Step 1 — Write failing tests

```python
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from terrain_generation import surface_height, in_lake, LAKE_RADIUS
import vegetation


def test_surface_height_matches_generator():
    from terrain_generation import TerrainGenerator

    gen = TerrainGenerator()
    for (x, z) in [(0, 0), (5, -3), (-17, 22), (100, -100)]:
        assert surface_height(gen.seed, x, z) == gen._simple_terrain_height(x, z)


def test_hash32_is_stable_and_bounded():
    a = vegetation.hash32(42, 3, -7, 1)
    b = vegetation.hash32(42, 3, -7, 1)
    assert a == b
    assert 0 <= a < 2**32
    assert vegetation.hash32(42, 3, -7, 2) != vegetation.hash32(42, 3, -7, 1)


def test_in_lake_matches_radius():
    assert in_lake(0, 0) is True
    assert in_lake(LAKE_RADIUS + 5, 0) is False
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_determinism.py -q`

Expected: `vegetation.py` and the module-level helpers do not exist.

### Step 3 — Implement

- In `terrain_generation.py`, lift the lake constants and the sine-noise height math to module-level pure functions. `TerrainGenerator._simple_terrain_height` must delegate to `surface_height(self.seed, x, z)` and produce identical output. `_generate_height_map_terrain` must use the module constants and `in_lake`.
- Create `vegetation.py` with `hash32` implemented via explicit 32-bit mixing (e.g. splitmix64 truncated to 32 bits) over `(seed, x, z, salt)`, masking with `& 0xFFFFFFFF`. Do not use the builtin `hash()`.

### Step 4 — Verify

Run the targeted command; then run `python -m pytest tests/test_water_chunk_integration.py -q` to confirm terrain output is unchanged. Expected: PASS.

### Step 5 — Commit

```bash
git add terrain_generation.py vegetation.py tests/test_vegetation_determinism.py
git commit -m "feat(m14): add pure terrain helpers and deterministic hash"
```

---

## Task 3 — Grass tuft placement and generation

**Files**
- Modify: `vegetation.py`
- Test: `tests/test_vegetation_placement.py`

**Interfaces produced**

- `vegetation.DECORATION_NONE`, `GRASS_DENSITY_PERCENT`, `PLANT_SALT`, `VARIANT_SALT`
- `vegetation.grass_variant_for_column(seed, x, z) -> int` (0 = none, 1..5 = variant)
- `vegetation.generate_vegetation_for_chunk(chunk, seed) -> None`

This task implements tufts only; tree wiring arrives in Task 4.

### Step 1 — Write failing tests

```python
from chunk import Chunk
from terrain_generation import surface_height, in_lake, LAKE_LEVEL
import vegetation


def _fresh_chunk(cx=0, cz=0, seed=42):
    c = Chunk(cx, 0, cz)
    # minimal terrain: fill the grass surface via the same pure function
    for x in range(16):
        for z in range(16):
            gx, gz = cx * 16 + x, cz * 16 + z
            h = surface_height(seed, gx, gz)
            for y in range(h + 1):
                c.set_block(x, y, z, 1 if y == h else 2)  # GRASS / DIRT
    return c


def test_tufts_only_on_exposed_grass():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for z in range(16):
            gx, gz = x, z
            if in_lake(gx, gz):
                continue
            y = surface_height(42, gx, gz) + 1
            if y > 15:
                continue
            v = c.get_decoration(x, y, z)
            if v:
                assert c.get_block(x, y - 1, z) == 1  # GRASS support
                assert c.get_block(x, y, z) == 0     # AIR above


def test_no_tufts_above_y15_or_in_lake():
    c = _fresh_chunk()
    vegetation.generate_vegetation_for_chunk(c, 42)
    for x in range(16):
        for y in range(16):
            for z in range(16):
                if c.get_decoration(x, y, z):
                    assert y <= 15
                    assert not in_lake(x, z)


def test_tuft_density_is_reasonable():
    placed = total = 0
    for cx in range(-2, 3):
        c = _fresh_chunk(cx, 0)
        vegetation.generate_vegetation_for_chunk(c, 42)
        for x in range(16):
            for z in range(16):
                gx = cx * 16 + x
                y = surface_height(42, gx, z) + 1
                if in_lake(gx, z) or y > 15:
                    continue
                total += 1
                if c.get_decoration(x, y, z):
                    placed += 1
    assert total > 0
    assert 0.15 < placed / total < 0.5
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_placement.py -q`

Expected: `generate_vegetation_for_chunk` does not exist.

### Step 3 — Implement

Implement `grass_variant_for_column` and the tuft part of `generate_vegetation_for_chunk` exactly per spec D5. The function must not call `random`. It must not write into `chunk.blocks`.

### Step 4 — Verify

Run the targeted command. Expected: PASS.

### Step 5 — Commit

```bash
git add vegetation.py tests/test_vegetation_placement.py
git commit -m "feat(m14): deterministic grass tuft placement"
```

---

## Task 4 — Tree shape and placement

**Files**
- Modify: `vegetation.py`
- Test: `tests/test_tree_structure.py`

**Interfaces produced**

- `vegetation.TREE_GRID`, `TREE_JITTER_MIN`, `TREE_JITTER_MAX`, `TREE_DENSITY_PERCENT`, `CANOPY_RADIUS`, `TREE_MIN_HEIGHT`, `TREE_HEIGHT_RANGE`, `TREE_SALT`, `HEIGHT_SALT`
- `vegetation.tree_candidate(gx, gz, seed) -> dict | None` (keys: `grid_x`, `grid_z`, `origin_x`, `origin_z`, `surface`, `height`)
- `vegetation.tree_blocks(origin_x, origin_z, surface, height, seed) -> list[tuple[int,int,int,int]]`
- `vegetation.cell_owner(cx, cy, cz, seed) -> tuple[int, int] | None` (owning `(grid_x, grid_z)`; spec D7.2)
- `vegetation.tree_owns_cell(candidate, cx, cy, cz, seed) -> bool`
- `generate_vegetation_for_chunk` writes tree blocks (before tufts).

### Step 1 — Write failing tests

```python
from block_data import BlockType
from vegetation import (
    tree_candidate,
    tree_blocks,
    TREE_GRID,
    TREE_JITTER_MIN,
    TREE_JITTER_MAX,
)


def _find_tree(seed, gx_range=range(-4, 5), gz_range=range(-4, 5)):
    for gx in gx_range:
        for gz in gz_range:
            c = tree_candidate(gx, gz, seed)
            if c:
                return c
    raise AssertionError("no tree found for seed")


def test_tree_candidate_jitter_within_cell():
    cand = _find_tree(42)
    assert TREE_JITTER_MIN <= cand["origin_x"] - cand["grid_x"] * TREE_GRID <= TREE_JITTER_MAX
    assert TREE_JITTER_MIN <= cand["origin_z"] - cand["grid_z"] * TREE_GRID <= TREE_JITTER_MAX
    assert 4 <= cand["height"] <= 6


def test_tree_blocks_contain_trunk_and_canopy():
    cand = _find_tree(42)
    blocks = tree_blocks(cand["origin_x"], cand["origin_z"], cand["surface"], cand["height"], 42)
    logs = [b for b in blocks if b[3] == BlockType.OAK_LOG]
    leaves = [b for b in blocks if b[3] == BlockType.OAK_LEAVES]
    assert len(logs) == cand["height"]
    assert leaves
    # single contiguous trunk column
    xs = {b[0] for b in logs}
    zs = {b[2] for b in logs}
    ys = sorted(b[1] for b in logs)
    assert len(xs) == 1 and len(zs) == 1
    assert ys == list(range(cand["surface"] + 1, cand["surface"] + 1 + cand["height"]))
    # every trunk block is above the surface
    assert all(b[1] > cand["surface"] for b in logs)


def test_tree_footprint_stays_inside_its_own_grid_cell():
    # Spec D7.1: TREE_JITTER_MIN - R >= 0 and TREE_JITTER_MAX + R <= TREE_GRID - 1.
    from vegetation import CANOPY_RADIUS, TREE_GRID

    assert TREE_JITTER_MIN - CANOPY_RADIUS >= 0
    assert TREE_JITTER_MAX + CANOPY_RADIUS <= TREE_GRID - 1
    for gx in range(-3, 4):
        for gz in range(-3, 4):
            cand = tree_candidate(gx, gz, 42)
            if not cand:
                continue
            lo_x, hi_x = gx * TREE_GRID, gx * TREE_GRID + TREE_GRID - 1
            lo_z, hi_z = gz * TREE_GRID, gz * TREE_GRID + TREE_GRID - 1
            for (cx, _cy, cz, _block) in tree_blocks(
                cand["origin_x"], cand["origin_z"], cand["surface"],
                cand["height"], 42,
            ):
                assert lo_x <= cx <= hi_x
                assert lo_z <= cz <= hi_z


def test_no_two_trees_claim_the_same_cell():
    # Spec D7.1/D7.2: at most one owner per cell, and cell_owner reports it.
    from vegetation import cell_owner

    seen = {}
    for gx in range(-3, 4):
        for gz in range(-3, 4):
            cand = tree_candidate(gx, gz, 42)
            if not cand:
                continue
            for cell in tree_blocks(
                cand["origin_x"], cand["origin_z"], cand["surface"],
                cand["height"], 42,
            ):
                key = cell[:3]
                assert key not in seen, f"cell {key} claimed twice"
                seen[key] = (gx, gz)
    assert seen
    for key, owner in seen.items():
        assert cell_owner(key[0], key[1], key[2], 42) == owner
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_tree_structure.py -q`

Expected: `tree_candidate` does not exist.

### Step 3 — Implement

Implement anchor jitter, density, height and the canopy layers per spec D7. `tree_candidate` must return the `grid_x`/`grid_z` that produced the candidate so tests can verify jitter bounds. `tree_blocks` must exclude any cell where `cy <= surface_height(seed, cx, cz)` or `in_lake(cx, cz)`. Keep `tree_candidate`, `tree_blocks`, `cell_owner` and `tree_owns_cell` free of `chunk`/`world` access so tests can call them directly. Implement the spec D7.2 ownership predicate. `cell_owner(cx, cy, cz, seed)` returns the owning `(grid_x, grid_z)`, which the D7.1 containment lemma reduces to the closed form `(cx // TREE_GRID, cz // TREE_GRID)` (floor division, correct for negatives); `tree_owns_cell(candidate, cx, cy, cz, seed)` compares that with the candidate's `(grid_x, grid_z)`. Do not implement it with a search over neighbouring candidates or as a function of which chunk is being generated. In `generate_vegetation_for_chunk`, generate trees first, writing the trunk before the canopy, only into `AIR`, clearing decorations, and only for cells the candidate owns; then tufts.

### Step 4 — Verify

Run the targeted command. Expected: PASS.

### Step 5 — Commit

```bash
git add vegetation.py tests/test_tree_structure.py
git commit -m "feat(m14): deterministic oak tree shape and placement"
```

---

## Task 5 — Cross-chunk boundary safety and order independence

**Files**
- Modify: `vegetation.py`
- Test: `tests/test_tree_chunk_boundaries.py`, `tests/test_vegetation_determinism.py`

### Step 1 — Write failing tests

```python
import numpy
from world import World
from block_data import BlockType
from chunk import Chunk
from terrain_generation import surface_height, in_lake
from vegetation import tree_candidate, tree_blocks
import vegetation

CHUNK_SIZE = Chunk.SIZE_X


def _fill_terrain(chunk, seed):
    for x in range(16):
        for z in range(16):
            gx, gz = chunk.chunk_x * 16 + x, chunk.chunk_z * 16 + z
            h = surface_height(seed, gx, gz)
            for y in range(h + 1):
                chunk.set_block(x, y, z, 1 if y == h else 2)  # GRASS / DIRT


def _generate(seed, order):
    w = World()
    for (cx, cz) in order:
        chunk = w.get_chunk(cx, 0, cz)
        _fill_terrain(chunk, seed)
        vegetation.generate_vegetation_for_chunk(chunk, seed)
    return w


def _assert_same_world(a, b):
    # Compare the chunk key sets first, then each NumPy array with
    # numpy.array_equal. Dictionary or tuple equality over NumPy arrays returns an
    # array rather than a single Boolean and raises on truth-value ambiguity, so it
    # must not be used here. This fails only when the data actually differs.
    assert set(a.chunks) == set(b.chunks)
    for key in a.chunks:
        assert numpy.array_equal(a.chunks[key].blocks, b.chunks[key].blocks), key
        assert numpy.array_equal(
            a.chunks[key].decorations, b.chunks[key].decorations
        ), key


CROSSING_SEEDS = (42, 43, 44, 45, 46, 47, 48)


def _find_crossing(kind, seeds=CROSSING_SEEDS, grid_range=range(-8, 9)):
    """Return (seed, candidate, cells) for the first footprint crossing chunks
    in the requested way: 'x' crosses an X boundary, 'z' a Z boundary, and
    'corner' crosses both. Deterministic: fixed seed list and scan order."""
    for seed in seeds:
        for gx in grid_range:
            for gz in grid_range:
                cand = tree_candidate(gx, gz, seed)
                if not cand:
                    continue
                cells = tree_blocks(
                    cand["origin_x"], cand["origin_z"], cand["surface"],
                    cand["height"], seed,
                )
                if not cells:
                    continue
                cx = {c[0] // CHUNK_SIZE for c in cells}
                cz = {c[2] // CHUNK_SIZE for c in cells}
                crosses_x, crosses_z = len(cx) > 1, len(cz) > 1
                if kind == "x" and crosses_x and not crosses_z:
                    return seed, cand, cells
                if kind == "z" and crosses_z and not crosses_x:
                    return seed, cand, cells
                if kind == "corner" and crosses_x and crosses_z:
                    return seed, cand, cells
    raise AssertionError(f"no {kind}-crossing tree for seeds {seeds}")


def _owned_chunks(cells):
    return sorted({(c[0] // CHUNK_SIZE, c[2] // CHUNK_SIZE) for c in cells})


def test_generation_order_does_not_change_output():
    order_a = [(cx, cz) for cx in range(-2, 3) for cz in range(-2, 3)]
    order_b = list(reversed(order_a))
    _assert_same_world(_generate(42, order_a), _generate(42, order_b))


def test_crossing_grid_cells_exist_by_construction():
    # Pure arithmetic, independent of any seed: TREE_GRID does not divide
    # CHUNK_SIZE, so X, Z and corner crossings must exist.
    from vegetation import CANOPY_RADIUS, TREE_GRID

    def span(i):
        return (
            TREE_GRID * i + TREE_JITTER_MIN - CANOPY_RADIUS,
            TREE_GRID * i + TREE_JITTER_MAX + CANOPY_RADIUS,
        )

    assert CHUNK_SIZE % TREE_GRID != 0
    crossing = [i for i in range(-32, 33)
                if span(i)[0] // CHUNK_SIZE != span(i)[1] // CHUNK_SIZE]
    assert crossing, "no grid cell straddles a chunk boundary"
    assert all(span(i)[1] // CHUNK_SIZE - span(i)[0] // CHUNK_SIZE <= 1 for i in crossing)
    assert len(crossing) >= 2  # so a corner-crossing cell exists too


def _assert_crossing_tree(kind):
    seed, cand, cells = _find_crossing(kind)
    owned = _owned_chunks(cells)
    assert len(owned) == (4 if kind == "corner" else 2), (kind, owned)

    orders = [
        owned,
        list(reversed(owned)),
        sorted(owned, key=lambda k: (k[1], k[0])),
    ]
    worlds = [_generate(seed, order) for order in orders]
    for other in worlds[1:]:
        _assert_same_world(worlds[0], other)

    # Across every involved chunk the tree is present exactly once: the union of
    # tree blocks equals the candidate's planned cells (no missing part), each
    # planned cell appears at most once, and no extra tree block exists.
    planned = {tuple(c[:3]) for c in cells}
    present = set()
    duplicates = []
    for key in owned:
        chunk = worlds[0].chunks[key]
        for x in range(16):
            for y in range(16):
                for z in range(16):
                    block = chunk.get_block(x, y, z)
                    if block in (BlockType.OAK_LOG, BlockType.OAK_LEAVES):
                        cell = (key[0] * 16 + x, y, key[1] * 16 + z)
                        if cell in present:
                            duplicates.append(cell)
                        present.add(cell)
    assert not duplicates, f"duplicated tree cells: {duplicates}"
    assert present == planned, (
        f"{kind}: missing={sorted(planned - present)} "
        f"extra={sorted(present - planned)}"
    )

    # Exactly one contiguous trunk column of the candidate's height.
    col = (cand["origin_x"], cand["origin_z"])
    trunks = sorted(c[1] for c in present
                    if (c[0], c[2]) == col and
                    worlds[0].get_block(c[0], c[1], c[2]) == BlockType.OAK_LOG)
    assert trunks == list(range(cand["surface"] + 1,
                               cand["surface"] + 1 + cand["height"])), trunks


def test_x_boundary_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("x")


def test_z_boundary_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("z")


def test_corner_crossing_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("corner")


```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_tree_chunk_boundaries.py tests/test_vegetation_determinism.py -q`

Expected: the crossing tests fail because generation is not yet order-independent and the padded scan and ownership predicate do not exist (or the tests do not exist).

### Step 3 — Implement

Per spec D8, each chunk scans the anchor grid cells whose footprint can intersect it and writes only the cells this chunk owns. Because `TREE_GRID = 6` does not divide `CHUNK_SIZE = 16`, this padding is load-bearing: for a chunk spanning `[chunk_min, chunk_max]` along an axis, scan `range(chunk_min // TREE_GRID - 1, chunk_max // TREE_GRID + 2)`, which is a superset of every intersecting grid cell. The write predicate is the D7.2 ownership test `(cx // TREE_GRID, cz // TREE_GRID) == (candidate.grid_x, candidate.grid_z)`, never arrival order. Add `generate_vegetation(world, seed)`; it iterates chunks but is provably order-independent because every cell has exactly one owner (D7.1/D7.2) and no neighbouring-chunk data is read, so an X-, Z- or corner-crossing tree is assembled identically regardless of chunk order.

### Step 4 — Verify

Run the targeted commands. Expected: PASS.

### Step 5 — Commit

```bash
git add vegetation.py tests/test_tree_chunk_boundaries.py tests/test_vegetation_determinism.py
git commit -m "feat(m14): order-independent cross-chunk tree generation"
```

---

## Task 6 — New block types and manifest block entries

**Files**
- Modify: `block_data.py`, `config/texture_manifest.json`
- Test: `tests/test_m14_textures.py`

### Step 1 — Write failing tests

```python
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType, get_block_face_textures, is_block_solid, is_block_transparent


def test_new_block_types_exist():
    assert int(BlockType.OAK_LOG) == 6
    assert int(BlockType.OAK_LEAVES) == 7


def test_tree_blocks_are_solid_and_opaque():
    assert is_block_solid(BlockType.OAK_LOG) is True
    assert is_block_solid(BlockType.OAK_LEAVES) is True
    assert is_block_transparent(BlockType.OAK_LOG) is False
    assert is_block_transparent(BlockType.OAK_LEAVES) is False


def test_tree_face_textures_resolve():
    log = get_block_face_textures(BlockType.OAK_LOG)
    leaves = get_block_face_textures(BlockType.OAK_LEAVES)
    assert log["top"] == "voxel_textures/MINETEST_TEXTURES/default_tree_top.png"
    assert log["side"] == "voxel_textures/MINETEST_TEXTURES/default_tree.png"
    assert leaves["top"] == leaves["side"] == leaves["bottom"] == "voxel_textures/MINETEST_TEXTURES/default_leaves.png"
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_m14_textures.py -q`

Expected: the new block types do not exist.

### Step 3 — Implement

- `block_data.py`: add `OAK_LOG = 6`, `OAK_LEAVES = 7`; add `BLOCK_PROPERTIES` entries with `is_solid=True`, `is_transparent=False`, and a legacy `texture` name.
- `config/texture_manifest.json`: add `OAK_LOG` (`top`/`bottom` = `voxel_textures/MINETEST_TEXTURES/default_tree_top.png`, `side` = `voxel_textures/MINETEST_TEXTURES/default_tree.png`) and `OAK_LEAVES` (all faces `voxel_textures/MINETEST_TEXTURES/default_leaves.png`).

### Step 4 — Verify

Run `python -m pytest tests/test_m14_textures.py tests/test_block_data_m9_task3.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add block_data.py config/texture_manifest.json tests/test_m14_textures.py
git commit -m "feat(m14): add oak log/leaves block types and textures"
```

---

## Task 7 — Manifest decorations, packer support, atlas regeneration

**Files**
- Modify: `config/texture_manifest.json`, `scripts/pack_textures.py`, `texture_config.py`
- Regenerate: `voxel_textures/gen_atlas.png`, `voxel_textures/atlas_map.json`
- Test: `tests/test_m14_textures.py`, `tests/test_atlas_generator.py`

### Step 1 — Write failing tests

```python
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import texture_config as tc
import pack_textures as pt


def test_decoration_textures_exposed():
    deco = tc.decoration_textures()
    assert deco["grass_tuft_1"] == "voxel_textures/MINETEST_TEXTURES/default_grass_1.png"
    assert len(deco) == 5


def test_packer_collects_decorations():
    sources = pt.collect_sources(pt.load_manifest(pt.DEFAULT_MANIFEST))
    assert "voxel_textures/MINETEST_TEXTURES/default_grass_1.png" in sources
    assert "voxel_textures/MINETEST_TEXTURES/default_leaves.png" in sources


def test_atlas_contains_new_tiles():
    atlas_map = tc.load_atlas_map()
    assert atlas_map is not None
    for key in ("default_tree.png", "default_tree_top.png", "default_leaves.png",
                "default_grass_1.png"):
        assert any(t.endswith(key) for t in atlas_map["tiles"])
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_m14_textures.py -q`

Expected: no `decorations` section, no `decoration_textures`, atlas lacks new tiles.

### Step 3 — Implement

- Add a top-level `"decorations"` object to the manifest mapping `grass_tuft_1..5` to the five grass PNGs.
- Extend `collect_sources` in `scripts/pack_textures.py` to also include `manifest.get("decorations", {}).values()` (the function must tolerate a missing section).
- Add `texture_config.decoration_textures() -> dict` reading the manifest `decorations` section.
- Regenerate the atlas: `python scripts/pack_textures.py`. Confirm it stays within 2048 and WATER is unchanged.

### Step 4 — Verify

Run `python -m pytest tests/test_m14_textures.py tests/test_atlas_generator.py tests/test_texture_config.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add config/texture_manifest.json scripts/pack_textures.py texture_config.py voxel_textures/gen_atlas.png voxel_textures/atlas_map.json tests/test_m14_textures.py
git commit -m "feat(m14): pack decoration and foliage textures into the atlas"
```

---

## Task 8 — Crossed-plane mesh geometry for decorations

**Files**
- Modify: `chunk_mesh.py`
- Test: `tests/test_vegetation_mesh.py`

**Interfaces produced**

- `generate_chunk_mesh_split` appends decoration geometry to the opaque lists.
- `_add_cross_planes(vertices, triangles, uvs, x, y, z, variant, atlas_map)`.
- Decoration UV lookup from `atlas_map["tiles"]` by manifest path via `texture_config.decoration_textures()`.

### Step 1 — Write failing tests

```python
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from chunk import Chunk
from chunk_mesh import generate_chunk_mesh_split


def _atlas_with_deco():
    return {
        "version": 1,
        "atlas": {"width": 1, "height": 1, "padding": 2, "filter": "nearest"},
        "tiles": {
            "voxel_textures/MINETEST_TEXTURES/default_grass_1.png":
                {"u0": 0.1, "v0": 0.1, "u1": 0.2, "v1": 0.3},
        },
    }


def test_decoration_emits_crossed_planes():
    c = Chunk(0, 0, 0)
    c.set_decoration(0, 1, 0, 1)
    vo, to, uo, vt, tt, ut = generate_chunk_mesh_split(c, atlas_map=_atlas_with_deco())
    assert len(to) == 2 * 6      # two quads (6 indices each)
    assert len(vo) == 2 * 4 * 3  # two quads, four vertices each
    assert len(uo) == 8          # four UVs per quad


def test_decoration_absent_means_no_geometry():
    c = Chunk(0, 0, 0)
    vo, to, uo, vt, tt, ut = generate_chunk_mesh_split(c, atlas_map=_atlas_with_deco())
    assert to == [] and vo == []
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_mesh.py -q`

Expected: decorations emit no geometry.

### Step 3 — Implement

After the block loop in `generate_chunk_mesh_split`, iterate `chunk.decorations`; for each non-zero variant, call `_add_cross_planes` to append two diagonal quads (4 triangles) to the opaque lists using the variant's atlas tile. Inset each quad by `0.05` from the cell faces. Use the existing `_flip_v` convention for UVs. Do not modify the water/transparent path.

### Step 4 — Verify

Run the targeted command plus `python -m pytest tests/test_chunk_mesh.py tests/test_m12_face_orientation.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add chunk_mesh.py tests/test_vegetation_mesh.py
git commit -m "feat(m14): emit crossed-plane decoration geometry"
```

---

## Task 9 — Alpha-cutout material and refresh re-application

**Files**
- Modify: `chunk_entity.py`, `chunk.py`
- Test: runtime smoke (Task 11); a light structural test in `tests/test_vegetation_mesh.py` may assert the helper exists.

**Interfaces produced**

- `chunk_entity.apply_foliage_cutout(entity) -> None`

### Step 1 — Write a failing structural test

```python
import inspect
import chunk_entity


def test_apply_foliage_cutout_exists():
    assert callable(chunk_entity.apply_foliage_cutout)
    src = inspect.getsource(chunk_entity.apply_foliage_cutout)
    assert "M_binary" in src
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_mesh.py -q`

Expected: the function does not exist.

### Step 3 — Implement

- Add `apply_foliage_cutout(entity)`: return early when `entity.model is None`; set `entity.model.setTransparency(TransparencyAttrib.M_binary)`; leave depth write/test enabled. Mirror the structure of `apply_water_material`.
- Call it for the opaque entity in `create_chunk_entity` after constructing the Entity.
- In `Chunk.refresh`, after assigning `self.entity.model = new_mesh`, call `apply_foliage_cutout(self.entity)` (mirroring the water-material re-application).

### Step 4 — Verify

Run `python -m pytest tests/test_vegetation_mesh.py tests/test_chunk_refresh.py tests/test_transparency_child_entity.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add chunk_entity.py chunk.py tests/test_vegetation_mesh.py
git commit -m "feat(m14): alpha-cutout foliage rendering on the opaque chunk mesh"
```

---

## Task 10 — World decoration cleanup on edits

**Files**
- Modify: `world.py`
- Test: `tests/test_vegetation_interaction.py`

### Step 1 — Write failing tests

```python
from world import World
from block_data import BlockType


def test_placing_block_clears_decoration_in_cell():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 2, 1, BlockType.STONE)
    assert c.get_decoration(1, 2, 1) == 0


def test_removing_support_clears_decoration_above():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(1, 1, 1, BlockType.GRASS)
    c.set_decoration(1, 2, 1, 3)
    w.set_block(1, 1, 1, BlockType.AIR)
    assert c.get_decoration(1, 2, 1) == 0


def test_set_block_still_marks_dirty_and_records_edit():
    w = World()
    w.get_chunk(0, 0, 0)
    w.set_block(1, 1, 1, BlockType.STONE)
    assert (0, 0, 0) in w.dirty_chunks
    assert (1, 1, 1) in w.changed_blocks
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_interaction.py -q`

Expected: decorations are not cleared on edit.

### Step 3 — Implement

In `World.set_block`, after writing the block and before/with existing dirty marking: clear the decoration at `(local_x, local_y, local_z)`; if the new block is not solid, clear the decoration at `(local_x, local_y + 1, local_z)` when it is inside the chunk. Preserve all existing water-metadata, edit-log, version and dirty-neighbour behavior.

### Step 4 — Verify

Run `python -m pytest tests/test_vegetation_interaction.py tests/test_world_set_block.py tests/test_water_chunk_integration.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add world.py tests/test_vegetation_interaction.py
git commit -m "feat(m14): clear decorations on block edits"
```

---

## Task 11 — Terrain wiring and startup smoke

**Files**
- Modify: `terrain_generation.py` (call vegetation after terrain)
- Test: `tests/test_vegetation_interaction.py`, `tests/test_vegetation_determinism.py`

### Step 1 — Write failing tests

```python
import random

import numpy as np

from world import World
from terrain_generation import TerrainGenerator
from block_data import BlockType
import water
from water import WaterSimulation
import vegetation

SEED = 42
STEPS = 200


def _build(with_vegetation):
    # Spec 5.2: one helper builds both worlds; the only variable is the flag.
    world = World()
    generator = TerrainGenerator()
    generator.seed = SEED
    random.seed(SEED)
    generator._generate_height_map_terrain(world)
    if with_vegetation:
        vegetation.generate_vegetation(world, SEED)
    return world


def _water_cells(world):
    return sum(int((c.blocks == BlockType.WATER).sum()) for c in world.chunks.values())


def _water_level_total(world):
    return sum(int(c.water_levels.sum()) for c in world.chunks.values())


def _water_source_count(world):
    return sum(int(c.water_sources.sum()) for c in world.chunks.values())


def _simulate(world):
    # Identical on both sides: seed all sources once, then a fixed number of ticks.
    sim = WaterSimulation(world)
    sim.seed_all_sources()
    for _ in range(STEPS):
        sim.consume_changes()
        sim.tick()
    return sim


def test_vegetation_is_added():
    world = _build(True)
    decor = sum(int((c.decorations > 0).sum()) for c in world.chunks.values())
    trees = sum(int((c.blocks == BlockType.OAK_LOG).sum()) for c in world.chunks.values())
    assert decor > 0
    assert trees > 0


def test_water_setup_identical_before_simulation():
    # Same seed and same terrain function, so nothing water-related may differ.
    base = _build(False)
    veg = _build(True)
    assert _water_cells(veg) == _water_cells(base) > 0
    assert _water_level_total(veg) == _water_level_total(base)
    assert _water_source_count(veg) == _water_source_count(base) > 0


def test_no_vegetation_on_water_cells():
    world = _build(True)
    for c in world.chunks.values():
        water_mask = c.blocks == BlockType.WATER
        assert not (c.decorations[water_mask] > 0).any()
        tree_mask = np.isin(c.blocks, (BlockType.OAK_LOG, BlockType.OAK_LEAVES))
        assert not (tree_mask & water_mask).any()


def test_passability_only_narrows():
    base = _build(False)
    veg = _build(True)
    # The predicate itself is unchanged for pre-existing block types.
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    for block in (BlockType.GRASS, BlockType.DIRT, BlockType.STONE, BlockType.SAND):
        assert water.is_passable(block) is False
    assert water.is_passable(BlockType.OAK_LOG) is False
    assert water.is_passable(BlockType.OAK_LEAVES) is False
    # Cell-wise, passability may only change passable -> non-passable.
    assert set(base.chunks) == set(veg.chunks)
    passable = (BlockType.AIR, BlockType.WATER)
    for key in base.chunks:
        before = base.chunks[key].blocks
        after = veg.chunks[key].blocks
        became_passable = (~np.isin(before, passable)) & np.isin(after, passable)
        assert not became_passable.any(), key


def test_water_identical_after_simulation():
    # Equivalent conditions: equal seed, initial state, STEPS and budget.
    base = _simulate(_build(False))
    veg = _simulate(_build(True))
    assert _water_cells(veg.world) == _water_cells(base.world)
    assert _water_level_total(veg.world) == _water_level_total(base.world)
    assert _water_source_count(veg.world) == _water_source_count(base.world)
```

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_interaction.py -q`

Expected: `_build(True)` adds no vegetation yet, so the water-preservation tests fail.

### Step 3 — Implement

At the end of `TerrainGenerator.generate_world`, call `generate_vegetation(world, self.seed)` (lazy import inside the method to avoid an import cycle). Do not change the terrain block layout.

### Step 4 — Verify

Run `python -m pytest tests/test_vegetation_interaction.py tests/test_water_chunk_integration.py tests/test_vegetation_determinism.py -q`. Expected: PASS.

### Step 5 — Commit

```bash
git add terrain_generation.py tests/test_vegetation_interaction.py tests/test_vegetation_determinism.py
git commit -m "feat(m14): generate vegetation as part of world generation"
```

---

## Task 12 — Interaction, collision and water non-interference verification

**Files**
- Test: `tests/test_vegetation_interaction.py` (extend)

### Step 1 — Write tests

```python
from raycast import raycast
from world import World
from block_data import BlockType
from chunk import Chunk
import water


def test_raycast_passes_through_tuft_cells():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(5, 0, 0, BlockType.STONE)
    c.set_decoration(3, 0, 0, 1)  # tuft in the ray path, cell stays AIR
    hit = raycast((0.5, 0.5, 0.5), (1, 0, 0), w, max_range=6)
    assert hit is not None
    assert hit["position"] == (5, 0, 0)


def test_tuft_cells_are_not_solid_for_water():
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    assert water.is_passable(BlockType.GRASS) is False
    # decoration layer does not change block types


def test_passability_predicate_unchanged_for_every_block_type():
    # Spec 5.2 assertion 3: the predicate is unchanged for pre-existing types and
    # the two new solid tree types are non-passable.
    assert water.is_passable(BlockType.AIR) is True
    assert water.is_passable(BlockType.WATER) is True
    for block in (BlockType.GRASS, BlockType.DIRT, BlockType.STONE,
                  BlockType.SAND, BlockType.OAK_LOG, BlockType.OAK_LEAVES):
        assert water.is_passable(block) is False
```

Also add a test that a chunk with both terrain and decorations produces exactly one opaque mesh plus the existing water child after `create_chunk_entity` (skipped when Ursina is unavailable), or assert structurally via `Chunk.refresh` + the mesh list lengths. The full reproducible water before/after protocol is owned by Task 11 and spec §5.2; this task must not duplicate or weaken it.

### Step 2 — Confirm failure

Run: `python -m pytest tests/test_vegetation_interaction.py -q`

Expected: additions fail until the raycast/decoration expectations are correct.

### Step 3 — Implement

Production code should require no change here if Tasks 1–11 are correct; fix any discovered non-interference gap minimally. Do not modify `raycast.py` or `water.py` unless a genuine defect is proven and reported.

### Step 4 — Verify

Run the targeted command plus the full suite. Expected: PASS.

### Step 5 — Commit

```bash
git add tests/test_vegetation_interaction.py
git commit -m "test(m14): verify vegetation non-interference"
```

---

## Task 13 — Final verification and M14 completion report

**Files**
- Modify: `MILESTONES.md` — M14 report only.

### Step 1 — Automated test evidence

Run: `python -m pytest tests -q`. Record the exact command, final count and result (baseline 155 passed). Record the spec §5.2 protocol results explicitly: for seed 42 the pre-simulation and post-simulation water cell counts, level totals and source counts must be identical between the vegetation-free and vegetated worlds, and no cell may become passable.

### Step 2 — Startup and smoke evidence

Run `python main.py` for a bounded interval (~12 s). Confirm the window is created, chunks/entities build, no exception is raised, and decorated chunks produce geometry. Record headless counts: number of decorations, number of `OAK_LOG`/`OAK_LEAVES` blocks, and the seed-42 water count before/after simulation.

This proves integration only, not visual correctness.

### Step 3 — Visual verification

Attempt to launch and inspect the running game. If rendered pixels cannot be inspected, report visual verification as **not performed**. Do not claim visual correctness from tests or startup success. If the cutout state could not be verified, state that explicitly.

### Step 4 — Write the completion report

Update only the M14 status/report in `MILESTONES.md`. Include: files changed; block/decoration design; deterministic-generation evidence; the D7.1 non-overlap proof and D7.2 ownership evidence; chunk-boundary evidence (the X-boundary, Z-boundary and corner-crossing trees, each verified complete and unique across every involved chunk in multiple generation orders, plus the arithmetic proof that crossing grid cells must exist because `TREE_GRID` does not divide `CHUNK_SIZE`); the §5.2 water before/after numbers; texture/atlas changes; automated test evidence; startup/smoke evidence; visual verification status; and known limitations.

Do not repair the truncated M13 section or any other milestone documentation.

### Step 5 — Commit

```bash
git add MILESTONES.md
git commit -m "docs(m14): add natural world generation completion report"
```

---

## Final self-review checklist

Before declaring M14 complete, verify:

- [ ] Grass tufts live in a decoration layer and never occupy the block grid.
- [ ] `OAK_LOG`/`OAK_LEAVES` are the only new block types; existing IDs are unchanged.
- [ ] Generation is a pure function of `(seed, coordinates)`; no `random`/builtin `hash`.
- [ ] Permuted chunk-generation order yields identical blocks and decorations, compared with `numpy.array_equal` per chunk key (never dict/tuple `==` over NumPy arrays), including for the X-, Z- and corner-crossing trees.
- [ ] Tufts appear only on exposed `GRASS` with `AIR` above and never in the lake.
- [ ] Trees never generate inside terrain or over water; trunk/canopy shapes match the spec.
- [ ] `TREE_GRID = 6` with jitter `[2, 3]` satisfies both non-overlap inequalities with zero slack, and crossing grid cells provably exist on X, on Z and on both.
- [ ] An X-boundary, a Z-boundary and a corner-crossing tree each generate completely and exactly once across every chunk they touch, in any chunk order, with no duplicated trunk and no missing canopy part.
- [ ] No cell is claimed by two trees; `cell_owner` is the `(cx // TREE_GRID, cz // TREE_GRID)` closed form and does not depend on generation order.
- [ ] Decoration crosses planes are part of the opaque chunk mesh; no per-tuft/per-leaf Entity.
- [ ] The opaque Entity uses alpha-cutout; water rendering is unchanged.
- [ ] `World.set_block` clears a decoration in the target cell and above a removed support.
- [ ] Raycast, collision, placement and water `is_passable` are unchanged by decorations.
- [ ] The spec §5.2 protocol passes: identical seed, initial world/water setup, simulation steps and measurement give identical water cell counts, level totals and source counts, and passability only narrows.
- [ ] New manifest references resolve; atlas contains the new tiles; WATER is unchanged.
- [ ] All M1–M13 tests pass (baseline 155).
- [ ] Automated, smoke and visual evidence are reported separately.
- [ ] The truncated M13 documentation is left untouched.

**Stop after the plan is approved and completed. Do not start M15 or unrelated refactoring.**
