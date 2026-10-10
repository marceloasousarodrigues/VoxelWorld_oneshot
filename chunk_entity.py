"""
Chunk entity creation for VoxelWorld.

Creates Ursina entities from chunk mesh data.
"""

import json
from pathlib import Path

from ursina import Entity, Mesh
from ursina.shaders import unlit_shader

from chunk_mesh import generate_chunk_mesh_split
from chunk import Chunk


TEXTURE_LEGACY = "voxel_textures/blocks.png"
TEXTURE_M9 = "voxel_textures/gen_atlas.png"
ATLAS_MAP_PATH = Path("voxel_textures") / "atlas_map.json"
ATLAS_IMAGE_PATH = Path(TEXTURE_M9)


def _m9_assets_available() -> bool:
    return ATLAS_IMAGE_PATH.is_file() and ATLAS_MAP_PATH.is_file()


def _load_atlas_map_if_available() -> dict | None:
    if not _m9_assets_available():
        return None
    with open(ATLAS_MAP_PATH, encoding="utf-8") as handle:
        return json.load(handle)


def _mesh_from_lists(vertices: list[float], triangles: list[int], uvs):
    vertex_tuples = [
        (
            vertices[i],
            vertices[i + 1],
            vertices[i + 2],
        )
        for i in range(0, len(vertices), 3)
    ]
    return Mesh(
        vertices=vertex_tuples,
        triangles=triangles,
        uvs=uvs,
        mode="triangle",
        static=True,
    )


def create_chunk_entity(
    chunk: Chunk,
    world_position: tuple[float, float, float] = (0, 0, 0),
    world=None,
) -> Entity:
    vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
        generate_chunk_mesh_split(
            chunk,
            world=world,
            atlas_map=_load_atlas_map_if_available(),
        )
    )

    opaque_has_geom = bool(vertices_o) and bool(triangles_o)
    transparent_has_geom = bool(vertices_t) and bool(triangles_t)

    from block_data import is_block_transparent

    has_any_transparent_block = False
    for x in range(Chunk.SIZE_X):
        for y in range(Chunk.SIZE_Y):
            for z in range(Chunk.SIZE_Z):
                if is_block_transparent(chunk.blocks[x, y, z]):
                    has_any_transparent_block = True
                    break
            if has_any_transparent_block:
                break
        if has_any_transparent_block:
            break

    if not opaque_has_geom and not transparent_has_geom and not has_any_transparent_block:
        return None

    texture = TEXTURE_M9 if _m9_assets_available() else TEXTURE_LEGACY

    try:
        mesh_opaque = (
            _mesh_from_lists(vertices_o, triangles_o, uvs_o)
            if opaque_has_geom
            else None
        )

        entity = Entity(
            model=mesh_opaque,
            position=world_position,
            texture=texture,
            shader=unlit_shader,
            double_sided=True,
        )

        if transparent_has_geom:
            mesh_trans = _mesh_from_lists(vertices_t, triangles_t, uvs_t)
            child = Entity(
                parent=entity,
                model=mesh_trans,
                texture=texture,
                shader=unlit_shader,
                double_sided=True,
                transparency=True,
                render_queue=1,
            )
            child.enabled = True
        else:
            child = Entity(
                parent=entity,
                texture=texture,
                shader=unlit_shader,
                double_sided=True,
                transparency=True,
                render_queue=1,
            )
            child.model = None
            child.enabled = False

        chunk.entity = entity
        chunk.entity_transparent = child
        return entity

    except Exception:
        return None
