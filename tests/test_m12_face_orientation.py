import sys
from pathlib import Path

import pytest
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

import texture_config as tc
from block_data import BlockType
from chunk import Chunk
from chunk_mesh import generate_chunk_mesh

MINETEST = "voxel_textures/MINETEST_TEXTURES"
GRASS_TOP = f"{MINETEST}/default_grass.png"
GRASS_SIDE = "voxel_textures/blocks/grass_side_composite.png"
DIRT = f"{MINETEST}/default_dirt.png"
STONE = f"{MINETEST}/default_stone.png"
SAND = f"{MINETEST}/default_sand.png"

FACES = ("Back", "Front", "Bottom", "Top", "Left", "Right")
SIDE_FACES = ("Back", "Front", "Left", "Right")
# Face order: 0 Back, 1 Front, 2 Bottom, 3 Top, 4 Left, 5 Right.
FACE_INDEX = {name: i for i, name in enumerate(FACES)}


def _tile_edges(key):
    tile = tc.load_atlas_map()["tiles"][key]
    return tile["u0"], tile["u1"], 1.0 - tile["v0"], 1.0 - tile["v1"]


def _single_grass_block():
    atlas_map = tc.load_atlas_map()
    chunk = Chunk(0, 0, 0)
    chunk.set_block(8, 8, 8, BlockType.GRASS)
    verts, _, uvs = generate_chunk_mesh(chunk, atlas_map=atlas_map)
    assert len(uvs) == 6 * 4
    return verts, uvs


def test_selected_assets_are_png_128():
    for key in (GRASS_TOP, GRASS_SIDE, DIRT, STONE, SAND):
        path = tc.REPO_ROOT / key
        assert path.is_file(), key
        with Image.open(path) as image:
            assert image.format == "PNG", key
            assert image.size == (128, 128), (key, image.size)


def test_manifest_grass_face_assignments():
    faces = tc.block_face_textures("GRASS")
    assert faces["top"] == GRASS_TOP
    assert faces["side"] == GRASS_SIDE
    assert faces["bottom"] == DIRT
    assert faces["side"] == "voxel_textures/blocks/grass_side_composite.png"


def test_side_faces_are_upright():
    verts, uvs = _single_grass_block()
    _, _, v_top, v_bottom = _tile_edges(GRASS_SIDE)
    for name in SIDE_FACES:
        base = FACE_INDEX[name] * 4
        for k in range(4):
            y = verts[(base + k) * 3 + 1]
            v = uvs[base + k][1]
            expected = v_top if y == 9 else v_bottom
            assert v == pytest.approx(expected), (name, k, y, v, expected)


def test_side_faces_are_not_mirrored_u():
    # The two top vertices of each side face must map to opposite u edges,
    # matching the face's x/z winding (no duplicated u across the top edge).
    verts, uvs = _single_grass_block()
    u0, u1, _, _ = _tile_edges(GRASS_SIDE)
    for name in SIDE_FACES:
        base = FACE_INDEX[name] * 4
        top_us = sorted(
            round(uvs[base + k][0], 6)
            for k in range(4)
            if verts[(base + k) * 3 + 1] == 9
        )
        assert top_us == [round(u0, 6), round(u1, 6)], (name, top_us)


def test_grass_top_and_dirt_bottom_tiles_used():
    _, uvs = _single_grass_block()
    gu0, gu1, _, _ = _tile_edges(GRASS_TOP)
    du0, du1, _, _ = _tile_edges(DIRT)
    top_us = {round(uvs[12 + k][0], 6) for k in range(4)}
    bottom_us = {round(uvs[8 + k][0], 6) for k in range(4)}
    assert top_us == {round(gu0, 6), round(gu1, 6)}
    assert bottom_us == {round(du0, 6), round(du1, 6)}


def test_grass_side_composite_is_fully_opaque_in_source_and_atlas():
    # The overlay default_grass_side.png has transparent pixels; the composited
    # replacement must be fully opaque so the opaque mesh never shows gaps.
    source = tc.REPO_ROOT / GRASS_SIDE
    assert source.is_file()
    with Image.open(source).convert("RGBA") as image:
        assert image.size == (128, 128)
        assert image.getchannel("A").getextrema() == (255, 255)

    atlas_map = tc.load_atlas_map()
    tile = atlas_map["tiles"][GRASS_SIDE]
    with Image.open(tc.ATLAS_IMAGE_PATH).convert("RGBA") as atlas:
        region = atlas.crop(
            (tile["x"], tile["y"], tile["x"] + tile["w"], tile["y"] + tile["h"])
        )
    assert region.getchannel("A").getextrema() == (255, 255)


def test_grass_side_overlay_is_not_used():
    # The raw Minetest overlay must no longer be a manifest or atlas entry.
    overlay = "voxel_textures/MINETEST_TEXTURES/default_grass_side.png"
    assert tc.block_face_textures("GRASS")["side"] != overlay
    assert overlay not in tc.load_atlas_map()["tiles"]


def test_atlas_uvs_inside_tiles_and_atlas():
    atlas_map = tc.load_atlas_map()
    width = atlas_map["atlas"]["width"]
    height = atlas_map["atlas"]["height"]
    for key, tile in atlas_map["tiles"].items():
        assert 0.0 < tile["u0"] < tile["u1"] < 1.0, key
        assert 0.0 < tile["v0"] < tile["v1"] < 1.0, key
        assert tile["u0"] == pytest.approx(tile["x"] / width), key
        assert tile["v1"] == pytest.approx((tile["y"] + tile["h"]) / height), key
