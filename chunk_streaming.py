"""
Chunk streaming policy for VoxelWorld (M16).

``ChunkStreamer`` decides *which* chunks should exist around the player and
schedules their load/unload incrementally, nearest-first, within per-frame work
limits. It is deliberately policy-only: the authoritative registry, entity
lifecycle and neighbour dirtying live in ``World.load_chunk`` /
``World.unload_chunk``.

Streaming is horizontal (the ground layer ``chunk_y == 0``), which is the only
layer that carries terrain, water and vegetation. The desired set is a Chebyshev
(square) radius of chunks around the player's chunk; retention is the larger
radius outside which chunks unload, giving hysteresis so a chunk is not
thrashed as the player wobbles on a boundary.

Every setting comes from ``config/world_config.json`` through ``world_config``;
nothing here is hard-coded.
"""

from __future__ import annotations

import math

import world_config
from coordinate_system import get_chunk_containing_world_coords


class ChunkStreamer:
    """Loads chunks around the player and unloads distant ones, incrementally."""

    def __init__(
        self,
        world,
        terrain_generator=None,
        water_sim=None,
        streaming_distance=None,
        retention_distance=None,
        max_loads_per_frame=None,
        max_unloads_per_frame=None,
    ):
        self.world = world
        self.terrain_generator = terrain_generator
        self.water_sim = water_sim

        self.streaming_distance = int(
            world_config.streaming_distance()
            if streaming_distance is None
            else streaming_distance
        )
        self.retention_distance = int(
            world_config.retention_distance()
            if retention_distance is None
            else retention_distance
        )
        # A chunk may never be unloaded while it is still desired.
        if self.retention_distance < self.streaming_distance:
            self.retention_distance = self.streaming_distance

        self.max_loads_per_frame = int(
            world_config.max_chunk_loads_per_frame()
            if max_loads_per_frame is None
            else max_loads_per_frame
        )
        self.max_unloads_per_frame = int(
            world_config.max_chunk_unloads_per_frame()
            if max_unloads_per_frame is None
            else max_unloads_per_frame
        )

        # The rendered-chunk registry: one entity per loaded chunk. A staged
        # chunk (stage A done, geometry pending) is already registered here with
        # the empty entity that stage A created, so this registry is never
        # missing a loaded chunk.
        self.rendered = {}
        self._last_player_chunk = None

        # M16 stutter fix 3: chunks whose data is loaded but whose mesh has not
        # been built yet. A streamed load is split across two frames - data
        # generation in one, mesh build + entity fill in the next - so no single
        # frame carries both halves. Kept at most `max_loads_per_frame` entries
        # because a new load is only started when this is empty.
        self._pending_mesh = {}

    # ------------------------------------------------------------------
    # Desired / retained sets
    # ------------------------------------------------------------------

    def player_chunk_coords(self, player_position) -> tuple[int, int]:
        """Return the (chunk_x, chunk_z) of the player's ground layer chunk."""
        world_x = int(math.floor(player_position[0]))
        world_z = int(math.floor(player_position[2]))
        chunk_x, _, chunk_z = get_chunk_containing_world_coords(world_x, 0, world_z)
        return chunk_x, chunk_z

    @staticmethod
    def _radius_keys(player_chunk: tuple[int, int], radius: int) -> set:
        chunk_x, chunk_z = player_chunk
        return {
            (chunk_x + dx, 0, chunk_z + dz)
            for dx in range(-radius, radius + 1)
            for dz in range(-radius, radius + 1)
        }

    def desired_chunk_keys(self, player_position) -> set:
        """Chunks that should be loaded for ``player_position``."""
        return self._radius_keys(
            self.player_chunk_coords(player_position), self.streaming_distance
        )

    def retained_chunk_keys(self, player_position) -> set:
        """Chunks kept loaded for ``player_position`` (never unloaded inside)."""
        return self._radius_keys(
            self.player_chunk_coords(player_position), self.retention_distance
        )

    def active_keys(self) -> set:
        """Currently loaded (and therefore rendered) chunk keys."""
        return set(self.world.chunks)

    def has_pending_work(self) -> bool:
        """True while the loaded set does not match the last known player chunk."""
        if self._pending_mesh:
            return True
        if self._last_player_chunk is None:
            return True
        desired = self._radius_keys(self._last_player_chunk, self.streaming_distance)
        retained = self._radius_keys(self._last_player_chunk, self.retention_distance)
        loaded = set(self.world.chunks)
        return bool((desired - loaded) or (loaded - retained))

    # ------------------------------------------------------------------
    # Scheduling
    # ------------------------------------------------------------------

    @staticmethod
    def _distance(key, player_chunk) -> int:
        chunk_x, chunk_z = player_chunk
        return max(abs(key[0] - chunk_x), abs(key[2] - chunk_z))

    def _ordered_loads(self, keys, player_chunk):
        """Nearest first, tie-broken by coordinates for determinism."""
        return sorted(keys, key=lambda key: (self._distance(key, player_chunk), key))

    def _ordered_unloads(self, keys, player_chunk):
        """Farthest first, tie-broken by coordinates for determinism."""
        return sorted(keys, key=lambda key: (-self._distance(key, player_chunk), key))

    def _start_load(self, key) -> None:
        """Stage A: register the chunk, generate its data, queue its mesh."""
        chunk = self.world.begin_chunk_load(
            key[0], key[1], key[2], terrain_generator=self.terrain_generator
        )
        self.rendered[key] = getattr(chunk, "entity", None)
        self._pending_mesh[key] = chunk
        # Newly available sources must join the water simulation. Guarded so a
        # streamer remains usable without a water simulation.
        seed = getattr(self.water_sim, "seed_chunk_sources", None)
        if seed is not None:
            seed(chunk)

    def _finish_load(self, key) -> bool:
        """Stage B: build the queued chunk's mesh into its existing entity.

        Returns True when a mesh was built. A queued chunk that was unloaded in
        the meantime is simply dropped: its own unload already released the
        entity, so there is nothing left to fill.
        """
        chunk = self._pending_mesh.pop(key, None)
        if chunk is None:
            return False
        if self.world.chunks.get(key) is not chunk:
            return False
        self.world.finish_chunk_load(chunk)
        self.rendered[key] = getattr(chunk, "entity", None)
        return True

    def _unload_one(self, key) -> None:
        self._pending_mesh.pop(key, None)
        self.world.unload_chunk(key[0], key[1], key[2])
        self.rendered.pop(key, None)

    def update(self, player_position, force: bool = False) -> dict:
        """Advance streaming by up to one frame's worth of work.

        Loads at most ``max_loads_per_frame`` nearest missing chunks and unloads
        at most ``max_unloads_per_frame`` farthest chunks beyond retention. When
        the player has not changed chunk and nothing is pending, this is a no-op.

        Returns a stats dict describing this update and what remains.
        """
        player_chunk = self.player_chunk_coords(player_position)
        desired = self.desired_chunk_keys(player_position)
        retained = self.retained_chunk_keys(player_position)

        loaded = set(self.world.chunks)
        # Adopt any chunk that entered the world outside the streamer (the
        # initial generated region, or a chunk created by an edit) so the
        # rendered registry stays a complete, authoritative view. Chunks the
        # streamer staged itself are already registered there.
        for key in loaded:
            if key not in self.rendered:
                self.rendered[key] = getattr(self.world.chunks[key], "entity", None)

        to_load = desired - loaded
        to_unload = loaded - retained

        if (
            not force
            and not to_load
            and not to_unload
            and not self._pending_mesh
            and player_chunk == self._last_player_chunk
        ):
            return {
                "loaded": 0,
                "unloaded": 0,
                "active": len(loaded),
                "desired": len(desired),
                "pending_loads": 0,
                "pending_unloads": 0,
                "player_chunk": player_chunk,
            }

        self._last_player_chunk = player_chunk

        # Stage B first: a chunk whose data is already registered must not wait
        # behind a newer one.
        staged_built = 0
        for key in self._ordered_loads(list(self._pending_mesh), player_chunk):
            if staged_built >= self.max_loads_per_frame:
                break
            if self._finish_load(key):
                staged_built += 1

        # A frame does one *kind* of load work, never both halves: that is the
        # whole point of staging, and it is what keeps a boundary-crossing frame
        # under the frame budget instead of paying data + mesh in the same frame.
        loaded_count = 0
        if staged_built == 0:
            for key in self._ordered_loads(to_load, player_chunk)[
                : self.max_loads_per_frame
            ]:
                self._start_load(key)
                loaded_count += 1

        unloaded_count = 0
        for key in self._ordered_unloads(to_unload, player_chunk)[
            : self.max_unloads_per_frame
        ]:
            self._unload_one(key)
            unloaded_count += 1

        loaded_after = set(self.world.chunks)
        return {
            "loaded": loaded_count,
            "unloaded": unloaded_count,
            "active": len(loaded_after),
            "desired": len(desired),
            "pending_loads": len(desired - loaded_after),
            "pending_unloads": len(loaded_after - retained),
            "pending_mesh": len(self._pending_mesh),
            "meshed": staged_built,
            "player_chunk": player_chunk,
        }
