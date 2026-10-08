"""
Chunk mesh generation for VoxelWorld.

Generates vertices, triangle indices and UV coordinates.
"""

from chunk import Chunk
from block_data import BlockType, is_block_solid


def generate_chunk_mesh(
    chunk: Chunk,
) -> tuple[list[float], list[int], list[tuple[float, float]]]:

    vertices = []
    triangles = []
    uvs = []

    blocks = chunk.blocks

    for x in range(Chunk.SIZE_X):
        for y in range(Chunk.SIZE_Y):
            for z in range(Chunk.SIZE_Z):

                block_type = blocks[x, y, z]

                if (
                    is_block_solid(block_type)
                    and block_type != BlockType.AIR
                ):
                    _add_exposed_faces(
                        vertices,
                        triangles,
                        uvs,
                        x,
                        y,
                        z,
                        chunk,
                        block_type,
                    )

    return vertices, triangles, uvs


def _add_exposed_faces(
    vertices,
    triangles,
    uvs,
    x,
    y,
    z,
    chunk,
    block_type,
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

    for normal, local_vertices in faces:

        neighbor_x = x + normal[0]
        neighbor_y = y + normal[1]
        neighbor_z = z + normal[2]

        neighbor_block = _get_neighbor_block(
            chunk,
            neighbor_x,
            neighbor_y,
            neighbor_z,
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

        u0, u1 = _get_texture_u_range(block_type)

        face_uvs = [
            (u0, 1.0),
            (u1, 1.0),
            (u1, 0.0),
            (u0, 0.0),
        ]

        uvs.extend(face_uvs)

        vertex_offset += 4


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
) -> int:

    if (
        0 <= x < Chunk.SIZE_X
        and 0 <= y < Chunk.SIZE_Y
        and 0 <= z < Chunk.SIZE_Z
    ):
        return chunk.blocks[x, y, z]

    return BlockType.AIR