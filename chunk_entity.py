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


def apply_foliage_cutout(entity: Entity) -> None:
    """Give the opaque chunk entity a binary alpha test (spec D3/D6).

    Leaves and grass tufts are painted with non-zero alpha only where the sprite
    is solid, so a binary alpha test discards the empty texels and leaves holes,
    while the fully opaque terrain tiles (alpha 255) are unaffected. Depth write
    and depth test stay enabled so cutout foliage still occludes correctly, and
    the transparent water child keeps its own ``apply_water_material`` state.

    Re-apply after every mesh reassignment (see ``Chunk.refresh``): assigning a
    new model resets the node's transparency state.
    """
    model = entity.model
    if model is None:
        return
    model.setTransparency(TransparencyAttrib.M_binary)


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


def create_chunk_entity_placeholder(
    chunk: Chunk,
    world_position: tuple[float, float, float] = (0, 0, 0),
    world=None,
) -> Entity:
    """Create a chunk's entity and transparent child with no geometry yet.

    This is stage A of a streamed chunk load (M16 stutter fix 3). The entity
    exists from the moment the chunk is registered, so no caller can ever observe
    a loaded chunk without its entity, but it carries no model until
    ``apply_chunk_mesh`` fills it in on the following frame. That keeps the
    one-entity-per-loaded-chunk invariant true *at every point in time* while
    splitting the load's cost across two frames.

    Args:
        chunk: The chunk this entity renders
        world_position: World-space position of the chunk's origin
        world: World the chunk belongs to (unused here, kept for signature parity)

    Returns:
        The created (empty) entity, also stored on ``chunk.entity``
    """
    texture = TEXTURE_M9 if atlas_assets_available() else TEXTURE_LEGACY

    entity = Entity(
        position=world_position,
        texture=texture,
        shader=unlit_shader,
        double_sided=True,
    )
    entity.model = None
    entity.enabled = False

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


def apply_chunk_mesh(chunk: Chunk, world=None) -> Entity:
    """Build a chunk's mesh into the entity it already has.

    This is the mesh half of a chunk load (stage B of M16 stutter fix 3) and the
    implementation behind ``create_chunk_entity``'s geometry. It reuses the
    chunk's existing entity, so a staged load never creates a second entity.

    When the chunk has no geometry to show and no transparent block anywhere (the
    fully empty or fully enclosed case), the entity is released and ``chunk.entity``
    is set back to ``None`` - the contract ``create_chunk_entity`` has always had.

    Args:
        chunk: The chunk to mesh; must already own an entity
        world: World used for cross-chunk neighbour face tests

    Returns:
        The meshed entity, or None when the chunk shows nothing at all
    """
    vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
        generate_chunk_mesh_split(
            chunk,
            world=world,
            atlas_map=load_atlas_map(),
        )
    )

    opaque_has_geom = bool(vertices_o) and bool(triangles_o)
    transparent_has_geom = bool(vertices_t) and bool(triangles_t)

    # M16 stutter fix 2: one vectorised whole-array test instead of a Python
    # triple loop over all 4096 cells (measured 4.33 ms -> 0.028 ms per chunk).
    has_any_transparent_block = chunk.has_transparent_block()

    entity = getattr(chunk, "entity", None)
    child = getattr(chunk, "entity_transparent", None)

    if not opaque_has_geom and not transparent_has_geom and not has_any_transparent_block:
        if entity is not None:
            try:
                from ursina import destroy

                destroy(entity)
            except Exception:
                pass
        chunk.entity = None
        chunk.entity_transparent = None
        return None

    if entity is None:
        # Defensive: nothing should have released the entity between the stages,
        # but a chunk with data must always end up renderable.
        entity = create_chunk_entity_placeholder(chunk, _chunk_world_position(chunk), world=world)
        child = getattr(chunk, "entity_transparent", None)

    entity.model = (
        _mesh_from_lists(vertices_o, triangles_o, uvs_o) if opaque_has_geom else None
    )
    apply_foliage_cutout(entity)
    entity.enabled = True

    if child is not None:
        if transparent_has_geom:
            child.model = _mesh_from_lists(vertices_t, triangles_t, uvs_t)
            apply_water_material(child)
            child.enabled = True
        else:
            child.model = None
            child.enabled = False

    chunk.entity = entity
    chunk.entity_transparent = child
    return entity


def _chunk_world_position(chunk: Chunk) -> tuple[float, float, float]:
    """World-space origin of a chunk, without importing the coordinate helper."""
    from coordinate_system import chunk_to_world_coords

    return chunk_to_world_coords(chunk.chunk_x, chunk.chunk_y, chunk.chunk_z)


def create_chunk_entity(
    chunk: Chunk,
    world_position: tuple[float, float, float] = (0, 0, 0),
    world=None,
) -> Entity:
    """Create a chunk's entity and fill it with geometry in one call.

    The synchronous form every existing caller and test uses. The streamed path
    splits it into ``create_chunk_entity_placeholder`` (data frame) and
    ``apply_chunk_mesh`` (mesh frame); ``tests/test_m16_staged_load.py`` pins the
    two paths to the same resulting world state, so this body and the staged pair
    cannot drift apart.

    Args:
        chunk: The chunk to render
        world_position: World-space position of the chunk's origin
        world: World used for cross-chunk neighbour face tests

    Returns:
        The rendered entity, or None when the chunk shows nothing at all
    """
    vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
        generate_chunk_mesh_split(
            chunk,
            world=world,
            atlas_map=load_atlas_map(),
        )
    )

    opaque_has_geom = bool(vertices_o) and bool(triangles_o)
    transparent_has_geom = bool(vertices_t) and bool(triangles_t)

    # M16 stutter fix 2: one vectorised whole-array test instead of a Python
    # triple loop over all 4096 cells (measured 4.33 ms -> 0.028 ms per chunk).
    has_any_transparent_block = chunk.has_transparent_block()

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
        apply_foliage_cutout(entity)

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
