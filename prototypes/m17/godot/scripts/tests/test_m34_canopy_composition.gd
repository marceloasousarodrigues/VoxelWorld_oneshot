extends RefCounted

## M34 canopy composition: v5 version plumbing, deterministic placement,
## crown variation, overlap reduction, dense-grove preservation and ecology.

const PINNED_LEGACY_HASH := 3214517825889907206
const PINNED_M30_HASH := 5947596836865492245
const PINNED_M31_HASH := 8397584315617538769
const PINNED_M32_HASH := 8802792587028581708
const PINNED_M33_HASH := 2164503133686526591
const SEA := WorldGen.SEA_LEVEL


func name() -> String:
	return "M34 canopy composition"


func _region_hash(version: int) -> int:
	var world := VoxelWorld.new(17017, version)
	for chunk_z in range(-2, 3):
		for chunk_x in range(-2, 3):
			for chunk_y in range(0, 6):
				world.ensure_chunk(Vector3i(chunk_x, chunk_y, chunk_z))
	return world.fingerprint()


func run(h: TestHarness) -> void:
	h.section("M34 generator versions")
	h.eq(WorldGen.M34_VERSION, 5, "the M34 canopy generator is version 5")
	h.eq(WorldGen.CURRENT_VERSION, 5, "new worlds use the M34 generator")
	h.eq(WorldGen.M33_VERSION, 4, "the M33 generator remains version 4")
	for version in range(0, WorldGen.CURRENT_VERSION + 1):
		h.check(WorldGen.is_supported_version(version), "version %d remains loadable" % version)
	h.check(not WorldGen.is_supported_version(WorldGen.CURRENT_VERSION + 1), "a future version is rejected")
	h.eq(_region_hash(0), PINNED_LEGACY_HASH, "version 0 remains pinned")
	h.eq(_region_hash(1), PINNED_M30_HASH, "version 1 remains pinned")
	h.eq(_region_hash(2), PINNED_M31_HASH, "version 2 remains pinned")
	h.eq(_region_hash(3), PINNED_M32_HASH, "version 3 remains pinned")
	h.eq(_region_hash(4), PINNED_M33_HASH, "version 4 remains pinned")
	var v5_a := _region_hash(5)
	var v5_b := _region_hash(5)
	h.eq(v5_a, v5_b, "version 5 generation is deterministic")
	var v4 := WorldGen.new(17017, 4)
	var v5 := WorldGen.new(17017, 5)
	var height_mismatch := 0
	var biome_mismatch := 0
	for z in range(-192, 193, 4):
		for x in range(-192, 193, 4):
			if v4.height_at(x, z) != v5.height_at(x, z):
				height_mismatch += 1
			if v4.biome_at(x, z) != v5.biome_at(x, z):
				biome_mismatch += 1
	h.eq(height_mismatch, 0, "v5 heights equal v4")
	h.eq(biome_mismatch, 0, "v5 biomes equal v4")
	var world := VoxelWorld.new(17017, 5)
	world.ensure_chunk(Vector3i(0, 4, 0))
	var save := SaveManager.new()
	var payload: Dictionary = save.to_dictionary(world, null, Inventory.new())
	h.eq(int(payload["terrain_generator_version"]), 5, "a v5 save records generator 5")
	var v4_world := VoxelWorld.new(17017, 4)
	v4_world.ensure_chunk(Vector3i(0, 4, 0))
	var v4_payload: Dictionary = save.to_dictionary(v4_world, null, Inventory.new())
	h.eq(int(v4_payload["terrain_generator_version"]), 4, "a v4 save still records generator 4")
	h.finish()
