extends RefCounted

## M31 wilderness generation: pinned legacy output, version-2 canopy invariants,
## and cross-chunk determinism for the new forest path.

## Fingerprints of chunks x,z in -2..2 and y in 0..5 for seed 17017, measured on the
## pre-M31 generator (version 0 and version 1).  Any drift means legacy saves
## regenerate different terrain.
const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
## Forest probe box (x 200..247, z 280..303) used for canopy density checks.
const FOREST_BOX := Rect2i(200, 280, 48, 24)


func name() -> String:
	return "m31 wilderness generation"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func run(h: TestHarness) -> void:
	h.eq(WorldGen.WILDERNESS_VERSION, 2, "the M31 generator is version 2")
	h.check(WorldGen.CURRENT_VERSION >= 2, "new worlds use the M31 path or newer")
	h.check(WorldGen.is_supported_version(WorldGen.LEGACY_VERSION), "version 0 remains a supported legacy save")
	h.check(WorldGen.is_supported_version(1), "version 1 (M30) remains a supported save")
	h.check(WorldGen.is_supported_version(2), "version 2 is a supported save")
	h.check(WorldGen.is_supported_version(3), "version 3 (M32) is a supported save")
	h.check(WorldGen.is_supported_version(WorldGen.CURRENT_VERSION),
		"the current M33 version is a supported save")
	h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1), "a future version is rejected")
	h.check(not WorldGen.is_supported_version(-1), "a negative version is rejected")

	h.eq(_region_hash(WorldGen.LEGACY_VERSION), PINNED_LEGACY_HASH,
		"version 0 terrain is byte-identical to the pinned M29 output")
	h.eq(_region_hash(1), PINNED_M30_HASH, "version 1 terrain is byte-identical to the pinned M30 output")
	h.check(_region_hash(2) != PINNED_M30_HASH, "version 2 terrain differs from version 1")

	# Cross-chunk determinism on the new forest path, in both load orders.
	var forward := VoxelWorld.new(17017, 2)
	forward.ensure_chunk(Vector3i(14, 4, 18))
	forward.ensure_chunk(Vector3i(13, 4, 18))
	var forward_blocks := (forward.get_chunk(Vector3i(13, 4, 18)) as ChunkData).blocks.duplicate()
	var backward := VoxelWorld.new(17017, 2)
	backward.ensure_chunk(Vector3i(13, 4, 18))
	backward.ensure_chunk(Vector3i(14, 4, 18))
	var backward_blocks := (backward.get_chunk(Vector3i(13, 4, 18)) as ChunkData).blocks.duplicate()
	h.eq(forward_blocks, backward_blocks, "version 2 forest chunks do not depend on load order")

	# Canopy invariant: at most one tree candidate per CANOPY_CELL block of columns.
	var generator := WorldGen.new(17017, 2)
	var forest_columns := 0
	var tree_columns := 0
	var duplicate_cells := 0
	var seen_cells := {}
	for z in range(FOREST_BOX.position.y, FOREST_BOX.end.y):
		for x in range(FOREST_BOX.position.x, FOREST_BOX.end.x):
			if generator.biome_at(x, z) != WorldGen.Biome.FOREST:
				continue
			forest_columns += 1
			if int(generator.tree_at(x, z)["type"]) == WorldGen.TreeType.NONE:
				continue
			tree_columns += 1
			var cell := Vector2i(floori(float(x) / WorldGen.CANOPY_CELL), floori(float(z) / WorldGen.CANOPY_CELL))
			if seen_cells.has(cell):
				duplicate_cells += 1
			seen_cells[cell] = true
	h.greater(float(forest_columns), 100.0, "the probe box contains a real forest")
	h.eq(duplicate_cells, 0, "each canopy cell holds at most one tree")
	var fraction := float(tree_columns) / maxf(1.0, float(forest_columns))
	h.check(fraction >= 0.04 and fraction <= 0.20,
		"forest tree density is in the dense-but-not-carpeted band (measured %.3f)" % fraction)
	h.check(WorldGen.WILDERNESS_TREE_PAD >= 6, "the tree pad covers a radius-4 crown plus lean and shelf")

	# A version-1 (M30) save records its generator and reloads on that terrain, so
	# an M30 world keeps its trees and terrain after the M31 generator ships.
	var m30_source := VoxelWorld.new(17017, 1)
	m30_source.ensure_chunk(Vector3i(13, 4, -1))
	var m30_reference := VoxelWorld.new(17017, 1)
	m30_reference.ensure_chunk(Vector3i(13, 4, -1))
	h.eq(m30_source.generator.terrain_version, 1, "a version-1 world generates with the M30 terrain")
	h.eq((m30_source.get_chunk(Vector3i(13, 4, -1)) as ChunkData).blocks,
		(m30_reference.get_chunk(Vector3i(13, 4, -1)) as ChunkData).blocks,
		"a version-1 chunk is reproducible under the M31 build")
	var m30_save := SaveManager.new()
	var m30_payload: Dictionary = m30_save.to_dictionary(m30_source, null, Inventory.new())
	h.eq(int(m30_payload["terrain_generator_version"]), 1, "a version-1 save records terrain version 1")
	var m30_restored := VoxelWorld.new(17017, int(m30_payload["terrain_generator_version"]))
	h.eq(m30_restored.generator.terrain_version, 1, "a version-1 save restores the M30 generator")

	# The oak at (47, -40) stands one block west of the x=48 chunk border, so its crown
	# crosses into the eastern chunk.  Its crown stays inside z-chunk -3, so only
	# that row of chunks is needed.  Each chunk must hold the same cells whichever
	# one generates first.
	var seam_generator := WorldGen.new(17017, 2)
	h.eq(int(seam_generator.tree_at(47, -40)["type"]), WorldGen.TreeType.OAK,
		"the seam fixture is an oak standing on the x=48 border")
	var seam_a := VoxelWorld.new(17017, 2)
	var seam_b := VoxelWorld.new(17017, 2)
	for cy in [4, 5]:
		seam_a.ensure_chunk(Vector3i(3, cy, -3))
		seam_a.ensure_chunk(Vector3i(2, cy, -3))
		seam_b.ensure_chunk(Vector3i(2, cy, -3))
		seam_b.ensure_chunk(Vector3i(3, cy, -3))
	var east_leaves := 0
	for cy in [4, 5]:
		east_leaves += _leaf_count(seam_a.get_chunk(Vector3i(3, cy, -3)))
	h.greater(float(east_leaves), 10.0, "the oak crown reaches into the eastern chunk of the border")
	for cy in [4, 5]:
		h.eq((seam_a.get_chunk(Vector3i(2, cy, -3)) as ChunkData).blocks,
			(seam_b.get_chunk(Vector3i(2, cy, -3)) as ChunkData).blocks,
			"the western chunk (y layer %d) is independent of generation order" % cy)
		h.eq((seam_a.get_chunk(Vector3i(3, cy, -3)) as ChunkData).blocks,
			(seam_b.get_chunk(Vector3i(3, cy, -3)) as ChunkData).blocks,
			"the eastern chunk (y layer %d) is independent of generation order" % cy)
	h.finish()


func _leaf_count(chunk: ChunkData) -> int:
	var count := 0
	for block in chunk.blocks:
		if block == BlockDB.OAK_LEAVES:
			count += 1
	return count
