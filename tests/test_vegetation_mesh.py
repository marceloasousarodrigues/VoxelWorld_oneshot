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
