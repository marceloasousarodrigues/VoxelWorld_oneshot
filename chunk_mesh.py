"""
Chunk mesh generation for VoxelWorld.

Generates vertices, triangle indices and UV coordinates.
"""

from pathlib import Path
import json

from chunk import Chunk
from block_data import (
    BlockType,
    get_block_face_textures,
    is_block_solid,
    is_block_transparent,
)


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

    for x in range(Chunk.SIZE_X):
        for y in range(Chunk.SIZE_Y):
            for z in range(Chunk.SIZE_Z):
                block_type = blocks[x, y, z]

                if block_type == BlockType.AIR:
                    continue

                if is_block_solid(block_type):
                    _add_exposed_faces_to_split(
                        vertices_opaque,
                        triangles_opaque,
                        uvs_opaque,
                        x,
                        y,
                        z,
                        chunk,
                        block_type,
                        world=world,
                        atlas_map=atlas_map,
                    )

                if is_block_transparent(block_type):
                    if _block_has_non_null_face_textures(block_type):
                        _add_exposed_faces_to_split(
                            vertices_transparent,
                            triangles_transparent,
                            uvs_transparent,
                            x,
                            y,
                            z,
                            chunk,
                            block_type,
                            world=world,
                            atlas_map=atlas_map,
                            force_transparent=True,
                        )

    return (
        vertices_opaque,
        triangles_opaque,
        uvs_opaque,
        vertices_transparent,
        triangles_transparent,
        uvs_transparent,
    )


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
    chunk,
    block_type,
    world=None,
    atlas_map=None,
    force_transparent: bool = False,
):
    faces = [
        # Back
        (
            (0, 0, -1),
            [
                (0, 1, 0),
                (1, 1, 0),
                (1, 0, 0),
                (0, 0, 0),
            ],
        ),
        # Front
        (
            (0, 0, 1),
            [
                (0, 0, 1),
                (1, 0, 1),
                (1, 1, 1),
                (0, 1, 1),
            ],
        ),
        # Bottom
        (
            (0, -1, 0),
            [
                (0, 0, 0),
                (1, 0, 0),
                (1, 0, 1),
                (0, 0, 1),
            ],
        ),
        # Top
        (
            (0, 1, 0),
            [
                (0, 1, 1),
                (1, 1, 1),
                (1, 1, 0),
                (0, 1, 0),
            ],
        ),
        # Left
        (
            (-1, 0, 0),
            [
                (0, 0, 0),
                (0, 1, 0),
                (0, 1, 1),
                (0, 0, 1),
            ],
        ),
        # Right
        (
            (1, 0, 0),
            [
                (1, 0, 1),
                (1, 1, 1),
                (1, 1, 0),
                (1, 0, 0),
            ],
        ),
    ]

    vertex_offset = len(vertices) // 3

    for face_index, (normal, local_vertices) in enumerate(faces):
        neighbor_x = x + normal[0]
        neighbor_y = y + normal[1]
        neighbor_z = z + normal[2]

        neighbor_block = _get_neighbor_block(
            chunk,
            neighbor_x,
            neighbor_y,
            neighbor_z,
            world=world,
        )

        if is_block_solid(neighbor_block):
            continue

        if force_transparent:
            face_uvs = _get_face_uvs_optional(
                block_type,
                face_index=face_index,
                atlas_map=atlas_map,
            )
            if face_uvs is None:
                continue
        else:
            face_uvs = _get_face_uvs_optional(
                block_type,
                face_index=face_index,
                atlas_map=atlas_map,
            )
            if face_uvs is None:
                continue

        for vertex in local_vertices:
            vertices.extend(
                [
                    x + vertex[0],
                    y + vertex[1],
                    z + vertex[2],
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
        return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]

    return _get_face_uvs(block_type, face_index=face_index, atlas_map=atlas_map)


def _add_exposed_faces(
    vertices,
    triangles,
    uvs,
    x,
    y,
    z,
    chunk,
    block_type,
    world=None,
    atlas_map=None,
):
    """
    Add exposed faces for one block.
    """

    faces = [
        # Back
        (
            (0, 0, -1),
            [
                (0, 1, 0),
                (1, 1, 0),
                (1, 0, 0),
                (0, 0, 0),
            ],
        ),

        # Front
        (
            (0, 0, 1),
            [
                (0, 0, 1),
                (1, 0, 1),
                (1, 1, 1),
                (0, 1, 1),
            ],
        ),

        # Bottom
        (
            (0, -1, 0),
            [
                (0, 0, 0),
                (1, 0, 0),
                (1, 0, 1),
                (0, 0, 1),
            ],
        ),

        # Top
        (
            (0, 1, 0),
            [
                (0, 1, 1),
                (1, 1, 1),
                (1, 1, 0),
                (0, 1, 0),
            ],
        ),

        # Left
        (
            (-1, 0, 0),
            [
                (0, 0, 0),
                (0, 1, 0),
                (0, 1, 1),
                (0, 0, 1),
            ],
        ),

        # Right
        (
            (1, 0, 0),
            [
                (1, 0, 1),
                (1, 1, 1),
                (1, 1, 0),
                (1, 0, 0),
            ],
        ),
    ]

    vertex_offset = len(vertices) // 3

    for face_index, (normal, local_vertices) in enumerate(faces):

        neighbor_x = x + normal[0]
        neighbor_y = y + normal[1]
        neighbor_z = z + normal[2]

        neighbor_block = _get_neighbor_block(
            chunk,
            neighbor_x,
            neighbor_y,
            neighbor_z,
            world=world,
        )

        # Hidden face.
        if is_block_solid(neighbor_block):
            continue

        # ----------------------------------------------------------
        # Vertices
        # ----------------------------------------------------------

        for vertex in local_vertices:
            vertices.extend(
                [
                    x + vertex[0],
                    y + vertex[1],
                    z + vertex[2],
                ]
            )

        # ----------------------------------------------------------
        # Triangles
        # ----------------------------------------------------------

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

        # ----------------------------------------------------------
        # UVs
        # ----------------------------------------------------------

        face_uvs = _get_face_uvs(
            block_type,
            face_index=face_index,
            atlas_map=atlas_map,
        )

        uvs.extend(face_uvs)

        vertex_offset += 4


def _load_default_atlas_map():
    atlas_map_path = Path("voxel_textures") / "atlas_map.json"
    if not atlas_map_path.is_file():
        return None
    with open(atlas_map_path, encoding="utf-8") as handle:
        return json.load(handle)


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
            return [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]

    # Legacy fallback to 3-cell atlas; preserve previous behavior.
    u0, u1 = _get_texture_u_range(block_type)
    return [(u0, 1.0), (u1, 1.0), (u1, 0.0), (u0, 0.0)]


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
        return world.get_block(global_x, global_y, global_z)

    return BlockType.AIR