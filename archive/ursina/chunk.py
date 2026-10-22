"""
Chunk class for VoxelWorld.

Handles storage and management of a 16x16x16 block volume.
"""

import numpy as np

from block_data import BlockType, has_transparent_block


class Chunk:
    """A chunk represents a 16x16x16 volume of blocks in the world."""

    SIZE_X = 16
    SIZE_Y = 16
    SIZE_Z = 16

    def __init__(self, chunk_x: int, chunk_y: int, chunk_z: int):
        self.chunk_x = chunk_x
        self.chunk_y = chunk_y
        self.chunk_z = chunk_z
        self.entity = None
        self.entity_transparent = None

        # M16: whether terrain generation has populated this chunk. A chunk made
        # on demand by ``World.get_chunk`` is a placeholder until
        # ``TerrainGenerator.generate_chunk_terrain`` runs, so streaming knows to
        # populate it rather than treat it as a finished chunk.
        self.generated = False

        self.blocks = np.full(
            (self.SIZE_X, self.SIZE_Y, self.SIZE_Z),
            BlockType.AIR,
            dtype=np.int32,
        )

        self.water_levels = np.full(
            (self.SIZE_X, self.SIZE_Y, self.SIZE_Z),
            0,
            dtype=np.int8,
        )

        self.water_sources = np.full(
            (self.SIZE_X, self.SIZE_Y, self.SIZE_Z),
            False,
            dtype=bool,
        )

        # M14 vegetation: logical decoration layer. 0 = none, 1..5 = grass tuft
        # variant. Decorations never occupy the block grid, so they cannot affect
        # collision, raycast, block placement or water passability.
        self.decorations = np.full(
            (self.SIZE_X, self.SIZE_Y, self.SIZE_Z),
            0,
            dtype=np.int8,
        )

    def has_transparent_block(self) -> bool:
        """True when any cell in this chunk holds a transparent-pass block.

        The entity factory uses this to decide whether a chunk with no geometry
        still needs a (disabled) transparent child slot. This is deliberately a
        vectorised whole-array test: the per-cell scan it replaces cost 4.33 ms
        of a 26 ms chunk load (M16 stutter fix 2).
        """
        return has_transparent_block(self.blocks)

    def get_block(self, local_x: int, local_y: int, local_z: int) -> int:
        return int(self.blocks[local_x, local_y, local_z])

    def set_block(self, local_x: int, local_y: int, local_z: int, block_type: int) -> None:
        self.blocks[local_x, local_y, local_z] = block_type

    def get_water_level(self, local_x: int, local_y: int, local_z: int) -> int:
        return int(self.water_levels[local_x, local_y, local_z])

    def set_water_level(self, local_x: int, local_y: int, local_z: int, level: int) -> None:
        self.water_levels[local_x, local_y, local_z] = np.clip(level, 0, 8)

    def get_water_source(self, local_x: int, local_y: int, local_z: int) -> bool:
        return bool(self.water_sources[local_x, local_y, local_z])

    def set_water_source(self, local_x: int, local_y: int, local_z: int, source: bool) -> None:
        self.water_sources[local_x, local_y, local_z] = source

    def clear_water(self, local_x: int, local_y: int, local_z: int) -> None:
        self.water_levels[local_x, local_y, local_z] = 0
        self.water_sources[local_x, local_y, local_z] = False

    def apply_water_cells(self, local_x, local_y, local_z, levels, sources):
        """Apply prepared water writes for many cells in one vectorised step.

        ``local_x``/``local_y``/``local_z`` are parallel index arrays and
        ``levels``/``sources`` carry the value for each cell. Cells with
        ``level <= 0`` drain to AIR; cells with ``level > 0`` become WATER at
        that level. This mirrors ``set_water``/``clear_water`` cell for cell, but
        writes the whole batch as a handful of array operations, so the block
        grid and the water metadata of a chunk can never be observed
        disagreeing with each other.

        Returns the boolean mask of the cells whose *occupancy* changed.
        """
        fill = levels > 0
        drain = ~fill

        # Advanced indexing copies, so this reads the pre-write state.
        old_blocks = self.blocks[local_x, local_y, local_z]
        changed = np.where(fill, old_blocks != BlockType.WATER,
                          old_blocks == BlockType.WATER)

        if fill.any():
            self.blocks[local_x[fill], local_y[fill], local_z[fill]] = BlockType.WATER
            self.water_levels[local_x[fill], local_y[fill], local_z[fill]] = np.clip(
                levels[fill], 0, 8
            )
            self.water_sources[local_x[fill], local_y[fill], local_z[fill]] = sources[fill]

        if drain.any():
            self.blocks[local_x[drain], local_y[drain], local_z[drain]] = BlockType.AIR
            self.water_levels[local_x[drain], local_y[drain], local_z[drain]] = 0
            self.water_sources[local_x[drain], local_y[drain], local_z[drain]] = False

        return changed

    def get_decoration(self, local_x: int, local_y: int, local_z: int) -> int:
        return int(self.decorations[local_x, local_y, local_z])

    def set_decoration(self, local_x: int, local_y: int, local_z: int, value: int) -> None:
        self.decorations[local_x, local_y, local_z] = value

    def clear_decoration(self, local_x: int, local_y: int, local_z: int) -> None:
        self.decorations[local_x, local_y, local_z] = 0

    def refresh(self, world=None):
        from chunk_mesh import generate_chunk_mesh_split

        vertices_o, triangles_o, uvs_o, vertices_t, triangles_t, uvs_t = (
            generate_chunk_mesh_split(self, world=world, atlas_map=None)
        )

        self._mesh_vertices = vertices_o + vertices_t
        self._mesh_triangles = triangles_o + triangles_t
        self._mesh_uvs = uvs_o + uvs_t

        if getattr(self, "entity", None) is not None:
            if vertices_o and triangles_o:
                from ursina import Mesh

                vertex_tuples = [
                    (vertices_o[i], vertices_o[i + 1], vertices_o[i + 2])
                    for i in range(0, len(vertices_o), 3)
                ]
                new_mesh = Mesh(
                    vertices=vertex_tuples,
                    triangles=triangles_o,
                    uvs=uvs_o,
                    mode="triangle",
                    static=True,
                )
                self.entity.model = new_mesh
                from chunk_entity import apply_foliage_cutout

                apply_foliage_cutout(self.entity)
                if getattr(self.entity, "collider", None) is not None:
                    self.entity.collider = "mesh"
                self.entity.enabled = True
            else:
                self.entity.model = None
                if getattr(self.entity, "collider", None) is not None:
                    self.entity.collider = None
                self.entity.enabled = False

        if getattr(self, "entity_transparent", None) is not None:
            if vertices_t and triangles_t:
                from ursina import Mesh

                vertex_tuples_t = [
                    (vertices_t[i], vertices_t[i + 1], vertices_t[i + 2])
                    for i in range(0, len(vertices_t), 3)
                ]
                new_mesh_t = Mesh(
                    vertices=vertex_tuples_t,
                    triangles=triangles_t,
                    uvs=uvs_t,
                    mode="triangle",
                    static=True,
                )
                self.entity_transparent.model = new_mesh_t
                from chunk_entity import apply_water_material

                apply_water_material(self.entity_transparent)
                self.entity_transparent.enabled = True
            else:
                self.entity_transparent.model = None
                self.entity_transparent.enabled = False
