import sys
import collections
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import numpy
from world import World
from block_data import BlockType
from chunk import Chunk
from terrain_generation import surface_height
from vegetation import tree_candidate, tree_blocks
import vegetation

CHUNK_SIZE = Chunk.SIZE_X


def _fill_terrain(chunk, seed):
    for x in range(Chunk.SIZE_X):
        for z in range(Chunk.SIZE_Z):
            gx, gz = chunk.chunk_x * CHUNK_SIZE + x, chunk.chunk_z * CHUNK_SIZE + z
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


def _planned_cells(chunks, seed, pad=3):
    """Every tree cell expected inside ``chunks``, with its block type.

    Computed from a deliberately generous scan (``pad`` grid cells wider than
    the production scan), so a production scan that under-covers the boundary
    shows up as missing cells rather than agreeing with itself. Returns the
    cell map and a per-cell claim count, which must stay at 1 (spec D7.1).
    """
    wanted = set(chunks)
    min_x = min(k[0] for k in wanted) * CHUNK_SIZE
    max_x = max(k[0] for k in wanted) * CHUNK_SIZE + CHUNK_SIZE - 1
    min_z = min(k[1] for k in wanted) * CHUNK_SIZE
    max_z = max(k[1] for k in wanted) * CHUNK_SIZE + CHUNK_SIZE - 1

    planned = {}
    claims = collections.Counter()
    for gx in range(min_x // vegetation.TREE_GRID - pad,
                    max_x // vegetation.TREE_GRID + pad + 1):
        for gz in range(min_z // vegetation.TREE_GRID - pad,
                        max_z // vegetation.TREE_GRID + pad + 1):
            cand = tree_candidate(gx, gz, seed)
            if not cand:
                continue
            for (cx, cy, cz, block) in tree_blocks(
                cand["origin_x"], cand["origin_z"], cand["surface"],
                cand["height"], seed,
            ):
                if (cx // CHUNK_SIZE, cz // CHUNK_SIZE) not in wanted:
                    continue
                cell = (cx, cy, cz)
                claims[cell] += 1
                planned[cell] = int(block)
    return planned, claims


def _present_cells(world, chunks):
    """Every tree cell actually written inside ``chunks``, with its block type."""
    found = {}
    for (cx, cz) in chunks:
        chunk = world.chunks[(cx, 0, cz)]
        for x in range(CHUNK_SIZE):
            for y in range(CHUNK_SIZE):
                for z in range(CHUNK_SIZE):
                    block = chunk.get_block(x, y, z)
                    if block in (BlockType.OAK_LOG, BlockType.OAK_LEAVES):
                        found[(cx * CHUNK_SIZE + x, y, cz * CHUNK_SIZE + z)] = int(block)
    return found


def test_generation_order_does_not_change_output():
    order_a = [(cx, cz) for cx in range(-2, 3) for cz in range(-2, 3)]
    order_b = list(reversed(order_a))
    _assert_same_world(_generate(42, order_a), _generate(42, order_b))


def test_crossing_grid_cells_exist_by_construction():
    # Pure arithmetic, independent of any seed: TREE_GRID does not divide
    # CHUNK_SIZE, so X, Z and corner crossings must exist.
    from vegetation import CANOPY_RADIUS, TREE_GRID, TREE_JITTER_MIN, TREE_JITTER_MAX

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
    # tree blocks equals the cells planned by the trees intersecting those
    # chunks (no missing part, no extra block, and no cell claimed by two trees).
    planned, claims = _planned_cells(owned, seed)
    present = _present_cells(worlds[0], owned)

    doubled = sorted(cell for cell, count in claims.items() if count > 1)
    assert not doubled, f"{kind}: cells claimed by more than one tree: {doubled}"
    assert present == planned, (
        f"{kind}: missing={sorted(set(planned) - set(present))} "
        f"extra={sorted(set(present) - set(planned))} "
        f"wrong_block={sorted(c for c in set(present) & set(planned) if present[c] != planned[c])}"
    )
    candidate_cells = {c[:3]: int(c[3]) for c in cells}
    assert candidate_cells.items() <= present.items(), (
        f"{kind}: candidate's own cells truncated"
    )

    # Every planned cell of the candidate lies inside the involved chunks, and
    # the crossing candidate's own trunk column is contiguous at full height
    # even though it is assembled from more than one chunk.
    assert {(c[0] // CHUNK_SIZE, c[2] // CHUNK_SIZE) for c in cells} == set(owned)
    col = (cand["origin_x"], cand["origin_z"])
    trunks = sorted(c[1] for c in present
                    if (c[0], c[2]) == col and present[c] == int(BlockType.OAK_LOG))
    assert trunks == list(range(cand["surface"] + 1,
                               cand["surface"] + 1 + cand["height"])), trunks


def test_x_boundary_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("x")


def test_z_boundary_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("z")


def test_corner_crossing_tree_is_complete_and_unique_in_every_order():
    _assert_crossing_tree("corner")
