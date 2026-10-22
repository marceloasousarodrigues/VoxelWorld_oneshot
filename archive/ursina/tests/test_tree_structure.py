import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

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
