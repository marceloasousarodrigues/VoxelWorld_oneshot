"""M15 Task 6 - golden-output regression gate for ``generate_chunk_mesh_split``.

Mesh generation is the hot spot being optimised. Before any change to
``chunk_mesh`` internals, this test pins the exact vertices, triangles and UVs
produced for a fixed set of chunks. Any shift of a single value fails loudly.

Outputs are hashed by ``repr`` so the comparison is byte-exact, including
floating-point formatting.
"""

import hashlib
import random
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from block_data import BlockType  # noqa: E402
from chunk_mesh import generate_chunk_mesh_split  # noqa: E402
from terrain_generation import TerrainGenerator  # noqa: E402
from world import World  # noqa: E402

SEED = 42


def _chunk_outputs():
    """Deterministically build the fixed chunk set and return raw mesh outputs."""
    outputs = {}

    # 1. Generated terrain + vegetation + lake (the real scene).
    random.seed(SEED)
    world = World()
    TerrainGenerator().generate_world(world)
    outputs["generated"] = generate_chunk_mesh_split(world.chunks[(0, 0, 0)], world=world)

    # 2. Hand-built tree chunk crossing no boundary.
    tree_world = World()
    tree_chunk = tree_world.get_chunk(0, 0, 0)
    tree_chunk.set_block(4, 0, 4, BlockType.GRASS)
    tree_chunk.set_block(4, 1, 4, BlockType.OAK_LOG)
    tree_chunk.set_block(4, 2, 4, BlockType.OAK_LOG)
    tree_chunk.set_block(4, 3, 4, BlockType.OAK_LOG)
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            tree_chunk.set_block(4 + dx, 3, 4 + dz, BlockType.OAK_LEAVES)
    tree_chunk.set_block(4, 4, 4, BlockType.OAK_LEAVES)
    tree_chunk.set_decoration(2, 1, 2, 3)
    tree_chunk.set_decoration(2, 1, 3, 1)
    outputs["tree"] = generate_chunk_mesh_split(tree_chunk, world=tree_world)

    # 3. Water chunk with a solid neighbour face.
    water_world = World()
    water_chunk = water_world.get_chunk(0, 0, 0)
    for x in range(16):
        for z in range(16):
            water_chunk.set_block(x, 0, z, BlockType.STONE)
            if 4 <= x <= 8 and 4 <= z <= 8:
                water_chunk.set_block(x, 1, z, BlockType.WATER)
                water_chunk.set_water_level(x, 1, z, 8)
    outputs["water"] = generate_chunk_mesh_split(water_chunk, world=water_world)

    # 4. Empty chunk.
    empty_world = World()
    empty_chunk = empty_world.get_chunk(0, 0, 0)
    outputs["empty"] = generate_chunk_mesh_split(empty_chunk, world=empty_world)

    # 5. Boundary chunk with a loaded neighbour, exercising cross-chunk culling.
    boundary_world = World()
    boundary_chunk = boundary_world.get_chunk(0, 0, 0)
    neighbour = boundary_world.get_chunk(1, 0, 0)
    for y in range(4):
        for z in range(16):
            boundary_chunk.set_block(15, y, z, BlockType.STONE)
            neighbour.set_block(0, y, z, BlockType.STONE)
    outputs["boundary"] = generate_chunk_mesh_split(boundary_chunk, world=boundary_world)

    return outputs


def _hash_output(output):
    digest = hashlib.sha256()
    for part in output:
        digest.update(repr(part).encode("utf-8"))
        digest.update(b"|")
    return digest.hexdigest()


# Frozen from the pre-optimisation output. This is the regression gate: the
# optimised mesher must produce byte-identical vertices, triangles and UVs.
EXPECTED_HASHES = {
    "generated": "8faa70e3861274be5042946551c3901af63a2a5642ed61e21c8238295a3d3453",
    "tree": "258fd5154a4af66a0ac78df046bbce3fdf8aca4ea96944f6f8ba58de3bb009df",
    "water": "b86a55263c9d4e842bbf08c66c4fdb06f8356307c43da9336c9f460c8ac1d21f",
    "empty": "0e7f2eb4b267f8ce181d784c0dc217eb0836fad2aa11be4f51876aed638797b5",
    "boundary": "53dd4f6d87bef0cf51ce21323c0f8352dd13664bceecf16068358516d4214ef9",
}


def test_mesh_output_is_byte_identical_to_golden():
    outputs = _chunk_outputs()
    actual = {name: _hash_output(output) for name, output in outputs.items()}
    assert actual == EXPECTED_HASHES


def test_generated_chunk_actually_has_geometry():
    outputs = _chunk_outputs()
    vertices, triangles, uvs, *_ = outputs["generated"]
    assert vertices
    assert triangles
    assert uvs


if __name__ == "__main__":
    for name, output in _chunk_outputs().items():
        print(name, _hash_output(output))
    test_mesh_output_is_byte_identical_to_golden()
    print("M15 mesh golden test passed!")
