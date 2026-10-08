"""
Chunk entity creation for VoxelWorld.

Creates Ursina entities from chunk mesh data.
"""

from ursina import Entity, Mesh
from ursina.shaders import unlit_shader

from chunk_mesh import generate_chunk_mesh
from chunk import Chunk


TEXTURE_ATLAS = "voxel_textures/blocks.png"


def create_chunk_entity(
    chunk: Chunk,
    world_position: tuple[float, float, float] = (0, 0, 0),
) -> Entity:

    vertices, triangles, uvs = generate_chunk_mesh(chunk)

    if not vertices or not triangles:
        print(
            f"Warning: No geometry to render for chunk at "
            f"{chunk.chunk_x}, {chunk.chunk_y}, {chunk.chunk_z}"
        )
        return None

    try:

        vertex_tuples = [
            (
                vertices[i],
                vertices[i + 1],
                vertices[i + 2],
            )
            for i in range(0, len(vertices), 3)
        ]

        print(
            f"Creating entity with "
            f"{len(vertex_tuples)} vertices and "
            f"{len(triangles)} triangle indices"
        )

        mesh_data = Mesh(
            vertices=vertex_tuples,
            triangles=triangles,
            uvs=uvs,
            mode="triangle",
            static=True,
        )

        entity = Entity(
            model=mesh_data,
            position=world_position,
            texture=TEXTURE_ATLAS,
            shader=unlit_shader,
            double_sided=True,
        )

        print(f"Entity created at {world_position}")
        print(f"  - entity object: {entity}")
        print(f"  - model vertices: {len(entity.model.vertices)}")
        print(f"  - model triangles: {len(entity.model.triangles)}")
        print(f"  - model UVs: {len(entity.model.uvs)}")
        print(
            f"Successfully created chunk entity "
            f"at {world_position}"
        )

        return entity

    except Exception as e:

        print(
            f"Error creating chunk entity: {e}"
        )

        return None