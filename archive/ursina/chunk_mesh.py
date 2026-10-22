"""
Chunk mesh generation for VoxelWorld.

Generates vertices, triangle indices and UV coordinates.

M15 performance notes
---------------------
``generate_chunk_mesh_split`` is the hot path (≈42 ms per chunk on the
reference machine). The output must stay byte-identical (guarded by
``tests/test_m15_mesh_golden.py``), so only constant-factor work was removed:

* the 6-face table is a module-level constant instead of being rebuilt per block;
* per-block-type ``is_solid`` / ``is_transparent`` / face-texture presence and the
  per-face UV corners are precomputed once per rebuild instead of per face;
* the y sweep is limited to the rows that can contain a non-air block;
* the decoration pass is skipped entirely for decoration-free chunks.
"""

import numpy as np

from chunk import Chunk
from block_data import (
    BLOCK_PROPERTIES,
    BlockType,
    get_block_face_textures,
)
from texture_config import decoration_textures, load_atlas_map


# M14: crossed-plane decorations are inset slightly from the cell faces so they
# cannot z-fight with an adjacent cube face.
_DECORATION_INSET = 0.05


# Per-face UV corner order. Corners are indexed in the canonical tile order
# [top-left, top-right, bottom-right, bottom-left]. Each entry lists the corner
# to assign to face vertex 0..3 so the texture renders upright (image top at
# world +y on side faces) and consistently wound when viewed from outside.
# Face indices match the order in _add_exposed_faces_to_split:
# 0 Back, 1 Front, 2 Bottom, 3 Top, 4 Left, 5 Right.
_FACE_UV_ORDER = {
    0: (1, 0, 3, 2),  # Back
    1: (3, 2, 1, 0),  # Front
    2: (3, 2, 1, 0),  # Bottom
    3: (3, 2, 1, 0),  # Top
    4: (3, 0, 1, 2),  # Left
    5: (3, 0, 1, 2),  # Right
}

# The 6 cube faces, in the exact order the mesher has always emitted them:
# face normal plus the four local vertex offsets flattened to (v0..v3).
# Hoisted out of the per-block loop (M15) so nothing is rebuilt per block.
_FACE_NORMALS = (
    (0, 0, -1),  # Back
    (0, 0, 1),   # Front
    (0, -1, 0),  # Bottom
    (0, 1, 0),   # Top
    (-1, 0, 0),  # Left
    (1, 0, 0),   # Right
)

_FACE_OFFSETS = (
    # Back        v0        v1        v2        v3
    (0, 1, 0,  1, 1, 0,  1, 0, 0,  0, 0, 0),
    # Front
    (0, 0, 1,  1, 0, 1,  1, 1, 1,  0, 1, 1),
    # Bottom
    (0, 0, 0,  1, 0, 0,  1, 0, 1,  0, 0, 1),
    # Top
    (0, 1, 1,  1, 1, 1,  1, 1, 0,  0, 1, 0),
    # Left
    (0, 0, 0,  0, 1, 0,  0, 1, 1,  0, 0, 1),
    # Right
    (1, 0, 1,  1, 1, 1,  1, 1, 0,  1, 0, 0),
)

_FACE_COUNT = len(_FACE_NORMALS)


def _build_type_tables():
    """Build block-type-indexed solid/transparent/face-presence tables (M15)."""
    size = max(int(block_type) for block_type in BLOCK_PROPERTIES) + 1
    solid = [False] * size
    transparent = [False] * size
    has_faces = [False] * size
    for block_type, properties in BLOCK_PROPERTIES.items():
        index = int(block_type)
        solid[index] = bool(properties.get("is_solid", False))
        transparent[index] = bool(properties.get("is_transparent", False))
        has_faces[index] = any(
            value is not None
            for value in (
                properties.get("top_texture"),
                properties.get("side_texture"),
                properties.get("bottom_texture"),
            )
        )
    return tuple(solid), tuple(transparent), tuple(has_faces)


_SOLID_TABLE, _TRANSPARENT_TABLE, _HAS_FACE_TEXTURES_TABLE = _build_type_tables()
_BLOCK_TYPES = tuple(range(len(_SOLID_TABLE)))


def _is_solid_value(block_type) -> bool:
    """Table lookup mirroring ``block_data.is_block_solid`` (M15 fast path)."""
    index = int(block_type)
    if 0 <= index < len(_SOLID_TABLE):
        return _SOLID_TABLE[index]
    return False


def _order_face_uvs(face_index: int, corners):
    """Reorder canonical tile corners for a face's vertex order."""
    order = _FACE_UV_ORDER.get(face_index, (0, 1, 2, 3))
    return [corners[i] for i in order]


def _active_y_range(array, empty_value):
    """Return the inclusive (lo, hi) y rows that can contain a non-empty value.

    Restricting the sweep to this range skips rows that are empty throughout,
    which produces no geometry anyway, so the output is unchanged.
    """
    active = np.any(array != empty_value, axis=(0, 2))
    ys = np.nonzero(active)[0]
    if ys.size == 0:
        return None
    return int(ys[0]), int(ys[-1])


def generate_chunk_mesh(
    chunk: Chunk,
    world=None,
    atlas_map=None,
) -> tuple[list[float], list[int], list[tuple[float, float]]]:
    vertices_opaque, triangles_opaque, uvs_opaque, vertices_transparent, triangles_transparent, uvs_transparent = (
        generate_chunk_mesh_split(chunk, world=world, atlas_map=atlas_map)
    )

    vertices = vertices_opaque + vertices_transparent
    triangles = triangles_opaque + triangles_transparent
    uvs = uvs_opaque + uvs_transparent
    return vertices, triangles, uvs


def generate_chunk_mesh_split(
    chunk: Chunk,
    world=None,
    atlas_map=None,
) -> tuple[
    list[float],
    list[int],
    list[tuple[float, float]],
    list[float],
    list[int],
    list[tuple[float, float]],
]:
    if atlas_map is None:
        atlas_map = _load_default_atlas_map()

    blocks = chunk.blocks

    vertices_opaque: list[float] = []
    triangles_opaque: list[int] = []
    uvs_opaque: list[tuple[float, float]] = []

    vertices_transparent: list[float] = []
    triangles_transparent: list[int] = []
    uvs_transparent: list[tuple[float, float]] = []

    # One UV-corner list per (block_type, face_index) for this rebuild's atlas.
    uv_table = _build_face_uv_table(atlas_map)

    y_range = _active_y_range(blocks, BlockType.AIR)
    if y_range is not None:
        y_lo, y_hi = y_range
        # A nested Python list indexes far faster than a numpy array in the
        # inner loops; the conversion is a single C-level pass per rebuild.
        block_rows = blocks.tolist()
        add_faces = _add_exposed_faces_to_split
        solid_table = _SOLID_TABLE
        transparent_table = _TRANSPARENT_TABLE
        has_face_textures = _HAS_FACE_TEXTURES_TABLE

        for x in range(Chunk.SIZE_X):
            columns = block_rows[x]
            for y in range(y_lo, y_hi + 1):
                row = columns[y]
                for z in range(Chunk.SIZE_Z):
                    block_type = row[z]

                    if block_type == 0:
                        continue

                    if solid_table[block_type]:
                        add_faces(
                            vertices_opaque,
                            triangles_opaque,
                            uvs_opaque,
                            x,
                            y,
                            z,
                            block_rows,
                            chunk,
                            block_type,
                            uv_table[block_type],
                            world=world,
                        )

                    if transparent_table[block_type] and has_face_textures[block_type]:
                        add_faces(
                            vertices_transparent,
                            triangles_transparent,
                            uvs_transparent,
                            x,
                            y,
                            z,
                            block_rows,
                            chunk,
                            block_type,
                            uv_table[block_type],
                            world=world,
                            force_transparent=True,
                        )

    # M14 foliage: crossed-plane grass tufts join the opaque lists, so no extra
    # Entity is created per tuft and the water split stays untouched. The whole
    # 4,096-cell pass is skipped when the chunk has no decorations (M15).
    decorations = chunk.decorations
    if decorations.any():
        deco_tiles = _build_decoration_tiles(atlas_map)
        deco_rows = decorations.tolist()
        deco_range = _active_y_range(decorations, 0)
        if deco_range is not None:
            y_lo, y_hi = deco_range
            for x in range(Chunk.SIZE_X):
                columns = deco_rows[x]
                for y in range(y_lo, y_hi + 1):
                    row = columns[y]
                    for z in range(Chunk.SIZE_Z):
                        variant = row[z]
                        if variant:
                            _add_cross_planes(
                                vertices_opaque,
                                triangles_opaque,
                                uvs_opaque,
                                x,
                                y,
                                z,
                                variant,
                                deco_tiles,
                            )

    return (
        vertices_opaque,
        triangles_opaque,
        uvs_opaque,
        vertices_transparent,
        triangles_transparent,
        uvs_transparent,
    )


def _build_face_uv_table(atlas_map) -> dict:
    """Precompute every (block_type -> 6 face-UV lists) for one atlas map."""
    return {
        block_type: tuple(
            _get_face_uvs_optional(block_type, face_index=face_index, atlas_map=atlas_map)
            for face_index in range(6)
        )
        for block_type in _BLOCK_TYPES
    }


def _build_decoration_tiles(atlas_map) -> dict:
    """Precompute variant -> atlas tile for every decoration variant."""
    if atlas_map is None or "tiles" not in atlas_map:
        return {}
    textures = decoration_textures()
    tiles = atlas_map["tiles"]
    variant_tiles = {}
    for key, rel in textures.items():
        if not key.startswith("grass_tuft_"):
            continue
        try:
            variant = int(key.rsplit("_", 1)[1])
        except (IndexError, ValueError):
            continue
        variant_tiles[variant] = tiles.get(rel)
    return variant_tiles


def _decoration_tile(variant: int, atlas_map):
    """Atlas tile for a decoration variant, or ``None`` when unavailable."""
    if atlas_map is None or "tiles" not in atlas_map:
        return None
    rel = decoration_textures().get(f"grass_tuft_{variant}")
    if not rel:
        return None
    return atlas_map["tiles"].get(rel)


def _add_cross_planes(
    vertices: list[float],
    triangles: list[int],
    uvs: list[tuple[float, float]],
    x: int,
    y: int,
    z: int,
    variant: int,
    tiles,
) -> None:
    """Append two crossed vertical quads for one decoration cell (spec D6).

    One quad runs along the cell's main diagonal and one along the other, each
    spanning the full cell height and inset by ``_DECORATION_INSET`` on both
    horizontal axes so the planes do not z-fight with neighbouring cube faces.
    Both quads use the variant's full tile UVs, oriented so the image top is at
    the higher Y, matching the block-face convention.

    Args:
        vertices: Opaque vertex list to extend
        triangles: Opaque triangle-index list to extend
        uvs: Opaque UV list to extend
        x: Chunk-local X of the decoration cell
        y: Chunk-local Y of the decoration cell
        z: Chunk-local Z of the decoration cell
        variant: Decoration variant (1..5), selecting the tuft texture
        tiles: Precomputed variant -> atlas tile map
    """
    if isinstance(tiles, dict):
        tile = tiles.get(variant)
    else:
        tile = _decoration_tile(variant, tiles)
    if tile is None:
        return

    u0 = tile["u0"]
    u1 = tile["u1"]
    v_top = _flip_v(tile["v0"])
    v_bottom = _flip_v(tile["v1"])
    # Canonical tile corners, the same order the block faces use: the image top
    # pairs with the higher world Y, so the sprites stand upright.
    corners = [(u0, v_top), (u1, v_top), (u1, v_bottom), (u0, v_bottom)]

    lo = _DECORATION_INSET
    hi = 1.0 - _DECORATION_INSET
    bottom = float(y)
    top = float(y + 1)

    for (start_x, start_z), (end_x, end_z) in (
        ((lo, lo), (hi, hi)),
        ((hi, lo), (lo, hi)),
    ):
        vertex_offset = len(vertices) // 3
        # Top edge first so vertex order matches the canonical corner order.
        vertices.extend(
            [
                x + start_x, top, z + start_z,
                x + end_x, top, z + end_z,
                x + end_x, bottom, z + end_z,
                x + start_x, bottom, z + start_z,
            ]
        )
        triangles.extend(
            [
                vertex_offset + 0,
                vertex_offset + 1,
                vertex_offset + 2,
                vertex_offset + 0,
                vertex_offset + 2,
                vertex_offset + 3,
            ]
        )
        uvs.extend(corners)


def _block_has_non_null_face_textures(block_type) -> bool:
    faces = get_block_face_textures(block_type)
    return any(value is not None for value in faces.values())


def _add_exposed_faces_to_split(
    vertices,
    triangles,
    uvs,
    x,
    y,
    z,
    block_rows,
    chunk,
    block_type,
    face_uvs_list,
    world=None,
    force_transparent: bool = False,
):
    """Append the exposed (non-occluded) faces of one block.

    ``block_rows`` is a nested Python-list copy of the chunk's block array and
    ``face_uvs_list`` is the precomputed 6-entry UV table for ``block_type``
    under this rebuild's atlas map (M15); a ``None`` UV entry means the face has
    no texture and is skipped.
    """
    solid_table = _SOLID_TABLE
    size_x = Chunk.SIZE_X
    size_y = Chunk.SIZE_Y
    size_z = Chunk.SIZE_Z
    table_size = len(solid_table)

    if world is not None:
        get_block = world.get_block
        is_loaded = getattr(world, "is_loaded", None)
        base_x = chunk.chunk_x * size_x
        base_y = chunk.chunk_y * size_y
        base_z = chunk.chunk_z * size_z
    else:
        get_block = None
        is_loaded = None
        base_x = base_y = base_z = 0

    vertex_offset = len(vertices) // 3

    for face_index in range(_FACE_COUNT):
        normal_x, normal_y, normal_z = _FACE_NORMALS[face_index]
        neighbor_x = x + normal_x
        neighbor_y = y + normal_y
        neighbor_z = z + normal_z

        if 0 <= neighbor_x < size_x and 0 <= neighbor_y < size_y and 0 <= neighbor_z < size_z:
            neighbor_value = block_rows[neighbor_x][neighbor_y][neighbor_z]
        elif get_block is not None:
            global_x = base_x + neighbor_x
            global_y = base_y + neighbor_y
            global_z = base_z + neighbor_z
            # Never create a neighbouring chunk as a side effect of meshing.
            if is_loaded is not None and not is_loaded(global_x, global_y, global_z):
                neighbor_value = 0
            else:
                neighbor_value = get_block(global_x, global_y, global_z)
        else:
            neighbor_value = 0

        if 0 <= neighbor_value < table_size and solid_table[neighbor_value]:
            continue

        if force_transparent and neighbor_value == block_type:
            # Cull internal faces between adjacent transparent blocks of the
            # same type (water/water). Solid and air neighbours still render.
            continue

        face_uvs = face_uvs_list[face_index]
        if face_uvs is None:
            continue

        offsets = _FACE_OFFSETS[face_index]
        vertices.extend(
            (
                x + offsets[0], y + offsets[1], z + offsets[2],
                x + offsets[3], y + offsets[4], z + offsets[5],
                x + offsets[6], y + offsets[7], z + offsets[8],
                x + offsets[9], y + offsets[10], z + offsets[11],
            )
        )

        triangles.extend(
            (
                vertex_offset,
                vertex_offset + 1,
                vertex_offset + 2,
                vertex_offset,
                vertex_offset + 2,
                vertex_offset + 3,
            )
        )

        uvs.extend(face_uvs)

        vertex_offset += 4


def _get_face_uvs_optional(block_type, face_index: int, atlas_map):
    faces = get_block_face_textures(block_type)

    if face_index in (0, 1, 4, 5):
        atlas_key = faces.get("side")
    elif face_index == 2:
        atlas_key = faces.get("bottom")
    elif face_index == 3:
        atlas_key = faces.get("top")
    else:
        atlas_key = faces.get("side")

    if atlas_map is not None and "tiles" in atlas_map:
        if not atlas_key:
            return None
        tile = atlas_map["tiles"].get(atlas_key)
        if tile is None:
            return None

        u0 = tile["u0"]
        u1 = tile["u1"]
        v0 = _flip_v(tile["v0"])
        v1 = _flip_v(tile["v1"])
        corners = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
        return _order_face_uvs(face_index, corners)

    return _get_face_uvs(block_type, face_index=face_index, atlas_map=atlas_map)


def _load_default_atlas_map():
    return load_atlas_map()


def _flip_v(v: float) -> float:
    return 1.0 - v


def _get_face_uvs(block_type, face_index: int, atlas_map):
    faces = get_block_face_textures(block_type)

    if face_index in (0, 1, 4, 5):
        atlas_key = faces.get("side")
    elif face_index == 2:
        atlas_key = faces.get("bottom")
    elif face_index == 3:
        atlas_key = faces.get("top")
    else:
        atlas_key = faces.get("side")

    if atlas_key and atlas_map and "tiles" in atlas_map:
        tile = atlas_map["tiles"].get(atlas_key)
        if tile is not None:
            u0 = tile["u0"]
            u1 = tile["u1"]
            v0 = _flip_v(tile["v0"])
            v1 = _flip_v(tile["v1"])
            corners = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            return _order_face_uvs(face_index, corners)

    # Legacy fallback to 3-cell atlas; preserve previous behavior.
    u0, u1 = _get_texture_u_range(block_type)
    corners = [(u0, 1.0), (u1, 1.0), (u1, 0.0), (u0, 0.0)]
    return _order_face_uvs(face_index, corners)


def _get_texture_u_range(block_type):
    """
    Get the horizontal UV range in the 3-cell texture atlas.

    Atlas:

        0.0 - 0.333...  GRASS
        0.333... - 0.666... DIRT
        0.666... - 1.0   STONE
    """

    if block_type == BlockType.GRASS:
        return 0.0, 1.0 / 3.0

    if block_type == BlockType.DIRT:
        return 1.0 / 3.0, 2.0 / 3.0

    if block_type == BlockType.STONE:
        return 2.0 / 3.0, 1.0

    # Fallback to grass.
    return 0.0, 1.0 / 3.0


def _get_neighbor_block(
    chunk: Chunk,
    x: int,
    y: int,
    z: int,
    world=None,
) -> int:

    if (
        0 <= x < Chunk.SIZE_X
        and 0 <= y < Chunk.SIZE_Y
        and 0 <= z < Chunk.SIZE_Z
    ):
        return chunk.blocks[x, y, z]

    if world is not None:
        global_x = chunk.chunk_x * Chunk.SIZE_X + x
        global_y = chunk.chunk_y * Chunk.SIZE_Y + y
        global_z = chunk.chunk_z * Chunk.SIZE_Z + z
        # Never create a neighbouring chunk as a side effect of meshing.
        if hasattr(world, "is_loaded") and not world.is_loaded(global_x, global_y, global_z):
            return BlockType.AIR
        return world.get_block(global_x, global_y, global_z)

    return BlockType.AIR
