import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / "scripts"))

import pack_textures as pt  # noqa: E402
from block_data import BlockType, get_block_face_textures, is_block_transparent
from chunk import Chunk
from chunk_mesh import generate_chunk_mesh
from chunk_entity import create_chunk_entity
from world import World


MANIFEST_PATH = REPO_ROOT / "config" / "texture_manifest.json"


def _run_pack_to_tmp(tmp_path):
    out_img = tmp_path / "gen_atlas.png"
    out_map = tmp_path / "atlas_map.json"
    pt.build_atlas(
        manifest_path=MANIFEST_PATH,
        out_image=out_img,
        out_map=out_map,
        base_dir=REPO_ROOT,
        max_size=2048,
    )
    return out_img, out_map


def test_water_asset_exists():
    p = Path("voxel_textures/blocks/water.png")
    assert p.is_file()
    from PIL import Image

    im = Image.open(p)
    assert im.size == (16, 16)
    assert im.mode == "RGBA"


def test_manifest_registers_water_faces():
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    water = manifest["blocks"]["WATER"]
    assert water["top"].endswith("water.png")
    assert water["side"].endswith("water.png")
    assert water["bottom"].endswith("water.png")


def test_atlas_generator_includes_water_mapping(tmp_path):
    _img, map_path = _run_pack_to_tmp(tmp_path)
    data = json.loads(map_path.read_text(encoding="utf-8"))
    faces = get_block_face_textures(BlockType.WATER)
    for k in ("top", "side", "bottom"):
        ref = faces[k]
        assert ref in data["tiles"]


def test_chunk_mesh_water_faces_use_transparent_mesh_uvs(tmp_path):
    # Ensure atlas_map is used so we can validate UVs are present.
    _img, map_path = _run_pack_to_tmp(tmp_path)
    atlas_map = json.loads(map_path.read_text(encoding="utf-8"))

    c = Chunk(0, 0, 0)
    c.set_block(0, 0, 0, BlockType.WATER)

    verts, tris, uvs = generate_chunk_mesh(c, atlas_map=atlas_map)
    # For one block, we expect all 6 faces exposed => 24 UVs (4 per face).
    assert len(uvs) == 6 * 4
    assert len(verts) > 0
    assert len(tris) > 0


def test_chunk_entity_water_uses_transparent_child():
    w = World()
    c = w.get_chunk(0, 0, 0)
    c.set_block(0, 0, 0, BlockType.WATER)

    entity = create_chunk_entity(c, (0, 0, 0), world=w)
    assert entity is not None
    assert hasattr(c, "entity_transparent")
    # Water is transparent; transparent child should exist.
    assert c.entity_transparent is not None


def test_water_classification():
    assert is_block_transparent(BlockType.WATER) is True
    assert is_block_transparent(BlockType.GRASS) is False
