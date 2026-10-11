"""
Chunk entity creation for VoxelWorld.

Creates Ursina entities from chunk mesh data.
"""

from panda3d.core import TransparencyAttrib
from ursina import Entity, Mesh
from ursina.shaders import unlit_shader

from chunk_mesh import generate_chunk_mesh_split
from chunk import Chunk
from texture_config import (
    TEXTURE_LEGACY,
    TEXTURE_M9,
    atlas_assets_available,
    load_atlas_map,
)


def apply_water_material(entity: Entity) -> None:
    """Configure a water child entity for alpha-blended, depth-sorted rendering.

    Ursina applies ``TransparencyAttrib.M_dual`` and the default (opaque) bin
    when a model is assigned. Water needs plain alpha blending, no depth
    writes and Panda3D's depth-sorted transparent bin so stacked water faces
    and the terrain behind them composite correctly. Re-apply after every mesh
    reassignment (see ``Chunk.refresh``).
    """
    model = entity.model
    if model is None:
        return
    model.setTransparency(TransparencyAttrib.M_alpha)
    model.setDepthWrite(False)
    model.setDepthTest(True)
    model.setBin("transparent", 0)


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
            atlas_map=load_atlas_map(),
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

    texture = TEXTURE_M9 if atlas_assets_available() else TEXTURE_LEGACY

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
            )
            apply_water_material(child)
            child.enabled = True
        else:
            child = Entity(
                parent=entity,
                texture=texture,
                shader=unlit_shader,
                double_sided=True,
            )
            child.model = None
            child.enabled = False

        chunk.entity = entity
        chunk.entity_transparent = child
        return entity

    except Exception:
        return None
